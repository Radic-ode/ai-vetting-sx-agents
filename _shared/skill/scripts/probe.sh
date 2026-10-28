#!/usr/bin/env bash
# probe.sh — run ONE capability probe of a third-party component in its own
# disposable bubblewrap sandbox, trace every file/network/process syscall
# with strace, and report what reached past the capability granted.
#
# Linux or WSL2 only. Needs: bwrap, strace  (sudo apt install bubblewrap strace)
# See references/capability-sandboxes.md for the capability IDs and grants.
#
# Usage:
#   probe.sh -c <capability> -t <component-dir> [-a host1,host2] [-k] -- <command> [args...]
#
#   -c  baseline | install | net-out | net-listen | fs-read | fs-write |
#       exec | secrets | persist | self-update
#   -t  folder holding the component (mounted read-only at /work, except
#       for `install`, which gets a writable copy)
#   -a  hosts the component is expected to contact (net-out, install,
#       self-update); their current IPs are listed for comparison
#   -k  keep the run folder (trace + canaries) instead of deleting it
#
# Example:
#   probe.sh -c net-out -t ./pkg -a registry.npmjs.org -- node /work/index.js --check
#
# Exit code: 0 = everything observed was within scope, 3 = out-of-scope
# activity found, 1/2 = usage or setup error.

set -uo pipefail

CAP="" TARGET="" ALLOW="" KEEP=0
while getopts "c:t:a:kh" o; do
  case "$o" in
    c) CAP="$OPTARG" ;; t) TARGET="$OPTARG" ;; a) ALLOW="$OPTARG" ;; k) KEEP=1 ;;
    *) sed -n '2,25p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift
[ -n "$CAP" ] && [ -n "$TARGET" ] && [ $# -gt 0 ] || { sed -n '2,25p' "$0"; exit 1; }
case "$CAP" in baseline|install|net-out|net-listen|fs-read|fs-write|exec|secrets|persist|self-update) ;;
  *) echo "unknown capability: $CAP" >&2; exit 1 ;; esac
for t in bwrap strace; do command -v "$t" >/dev/null || { echo "missing: $t (sudo apt install bubblewrap strace)" >&2; exit 2; }; done
[ -d "$TARGET" ] || { echo "not a folder: $TARGET" >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

RUN="$(mktemp -d "${TMPDIR:-/tmp}/probe-$CAP-XXXXXX")"
cleanup() { [ "$KEEP" = 1 ] && echo "run folder kept: $RUN" || rm -rf "$RUN"; }
trap cleanup EXIT

# --- canaries: a fake home with fake credentials, each string unique to this probe
TAG="CANARY-$CAP-$(head -c6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
H="$RUN/home"
mkdir -p "$H/.ssh" "$H/.aws" "$H/.config/gh" "$H/.mozilla/firefox/probe.default" "$RUN/out"
echo "$TAG-ssh"     > "$H/.ssh/id_rsa"
printf '[default]\naws_access_key_id = %s-aws\n' "$TAG" > "$H/.aws/credentials"
echo "API_KEY=$TAG-env" > "$H/.env"
printf 'github.com:\n  oauth_token: %s-gh\n' "$TAG" > "$H/.config/gh/hosts.yml"
echo "$TAG-browser" > "$H/.mozilla/firefox/probe.default/logins.json"
if [ "$CAP" = secrets ]; then echo "$TAG-configured" > "$H/.probe-credential"; fi
CANARY_RE='/home/probe/(\.ssh|\.aws|\.env|\.config/gh|\.mozilla)'

# --- sandbox: deny-all base, then this probe's single grant
# The root is bwrap's own empty tmpfs (so /work and /out can be created), with the
# host's system folders bound read-only into it; it is made read-only at the end.
B=(bwrap --die-with-parent --new-session --unshare-all)
for d in /*; do
  case "$d" in /home|/root|/mnt|/media|/run|/tmp|/proc|/dev|/lost+found) continue ;; esac
  if [ -L "$d" ]; then B+=(--symlink "$(readlink "$d")" "$d"); else B+=(--ro-bind "$d" "$d"); fi
done
B+=(--tmpfs /home --tmpfs /root --tmpfs /mnt --tmpfs /media --tmpfs /run --tmpfs /tmp
   --dev /dev --proc /proc --dir /work --dir /out
   --setenv HOME /home/probe --setenv CANARY_TOKEN "$TAG-envvar" --chdir /work)
case "$CAP" in
  persist) B+=(--bind "$H" /home/probe) ;;
  *)       B+=(--ro-bind "$H" /home/probe) ;;
esac
case "$CAP" in
  install) cp -a "$TARGET" "$RUN/work"; B+=(--bind "$RUN/work" /work) ;;
  *)       B+=(--ro-bind "$TARGET" /work) ;;
esac
case "$CAP" in
  fs-write|self-update) B+=(--bind "$RUN/out" /out) ;;
esac
case "$CAP" in
  net-out|install|self-update)
    B+=(--share-net --ro-bind-try /run/systemd/resolve /run/systemd/resolve) ;;
esac   # every other probe: own network namespace, loopback only
B+=(--remount-ro /)

echo "== probe: $CAP   component: $TARGET"
echo "== command: $*"
if [ -n "$ALLOW" ]; then
  echo "== expected hosts and their current IPs:"
  for h in ${ALLOW//,/ }; do echo "   $h -> $(getent ahosts "$h" | awk '{print $1}' | sort -u | tr '\n' ' ')"; done
fi

TRACE="$RUN/trace.log"
timeout --signal=TERM 120 strace -f -qq -s 256 -o "$TRACE" \
  -e trace=execve,openat,open,creat,unlink,unlinkat,rename,renameat,renameat2,mkdir,mkdirat,connect,bind,listen,sendto,sendmsg,write,writev,pwrite64,sendfile,splice,copy_file_range \
  "${B[@]}" "$@" </dev/null
STATUS=$?
echo "== command exit status: $STATUS (124 = killed after 120 s)"

# --- ignore bwrap's own setup: start at the first execve of something that isn't bwrap
awk 'f || (/execve\(/ && !/bwrap/) {f=1; print}' "$TRACE" > "$RUN/t.log"
T="$RUN/t.log"
# successful program starts, in order, as "pid path". strace splits a call into
# "<unfinished ...>" + "<... execve resumed>" when processes overlap: pair them by pid.
awk '
  /execve\(/ { p=$0; sub(/^[^"]*execve\("/, "", p); sub(/".*/, "", p); path[$1]=p
               if ($0 ~ / = 0$/) print $1, p; next }
  /<\.\.\. execve resumed>/ && / = 0$/ { print $1, path[$1] }
' "$T" > "$RUN/exec.log"
# no traced program start means the sandbox itself failed: never report that as a pass
if [ ! -s "$RUN/exec.log" ]; then
  echo "== VERDICT: PROBE FAILED: the command never started inside the sandbox (see bwrap error above)"
  exit 2
fi

granted() { case " $1 " in *" $CAP "*) return 0 ;; esac; return 1; }
FOUND=0
report() { # $1 capability needed, $2 title, $3 lines
  [ -z "$3" ] && return
  if granted "$1"; then echo "-- [within grant: $1] $2"; else echo "!! [OUT OF SCOPE: needs $1] $2"; FOUND=1; fi
  echo "$3" | head -15 | sed 's/^/     /'
}

echo
echo "== findings"
# canary reads are out of scope for every probe (secrets only gets .probe-credential)
CAN=$(grep -E "open(at)?\(.*\"$CANARY_RE" "$T" | grep -v ' = -1 ' | grep -oE '"[^"]+"' | sort -u)
[ -n "$CAN" ] && { echo "!! [OUT OF SCOPE] canary credential files OPENED:"; echo "$CAN" | sed 's/^/     /'; FOUND=1; }

# a canary string inside any write/send means a secret (file or $CANARY_TOKEN) left the process
LEAK=$(grep -E '^[0-9]+ +(write|writev|pwrite64|sendto|sendmsg)\(' "$T" | grep -F "$TAG" | grep -v -- "-configured" | cut -c1-160)
[ -n "$LEAK" ] && { echo "!! [OUT OF SCOPE] canary value WRITTEN or SENT (exfiltration or logging of secrets):"; echo "$LEAK" | head -10 | sed 's/^/     /'; FOUND=1; }
# kernel-side copies carry no visible data, so a secret copied this way can't be matched
KCOPY=$(grep -cE '^[0-9]+ +(sendfile|splice|copy_file_range)\(.* = [1-9]' "$T")
[ "$KCOPY" -gt 0 ] && [ -n "$CAN" ] && echo "-- note: $KCOPY kernel-side copies (sendfile/splice/copy_file_range) after a canary was opened: the canary contents may have been copied without being visible here"

NET=$(grep -E 'connect\(.*AF_INET6?' "$T" | grep -vE '127\.0\.0\.1|::1"|inet_addr\("127\.' \
      | grep -oE '(inet_addr|inet_pton)\([^)]*\)|sin6?_port=htons\([0-9]+\)' | paste - - 2>/dev/null | sort -u)
report "net-out install self-update" "outbound connections:" "$NET"

LST=$(grep -E '^[0-9]+ +(bind|listen)\(.*AF_INET6?' "$T" | grep -oE 'sin6?_port=htons\([0-9]+\).*(inet_addr|inet_pton)\([^)]*\)' | sort -u)
NONLOOP=$(echo "$LST" | grep -vE '127\.0\.0\.1|::1' | grep -v '^$')
report "net-listen" "listening sockets:" "$LST"
[ -n "$NONLOOP" ] && { echo "!! [OUT OF SCOPE] bound to a NON-loopback address:"; echo "$NONLOOP" | sed 's/^/     /'; FOUND=1; }

WR=$(grep -E '(open(at)?\(.*O_(WRONLY|RDWR|CREAT)|creat\(|unlink(at)?\(|rename(at2?)?\(|mkdir(at)?\()' "$T" \
     | grep -oE '"/[^"]*"' | tr -d '"' | grep -vE '^/(tmp|dev|proc)(/|$)' | sort -u)
case "$CAP" in
  fs-write|self-update) WR_BAD=$(echo "$WR" | grep -vE '^/out(/|$)') ;;
  install)              WR_BAD=$(echo "$WR" | grep -vE '^/work(/|$)') ;;
  persist)              WR_BAD="" ;;
  *)                    WR_BAD="$WR" ;;
esac
[ -n "$(echo "$WR_BAD" | grep -v '^$')" ] && { echo "!! [OUT OF SCOPE] write/delete attempts (most fail: the filesystem is read-only):"; echo "$WR_BAD" | head -15 | sed 's/^/     /'; FOUND=1; }

PERS=$(echo "$WR" | grep -E '/home/probe/(\.bashrc|\.profile|\.zshrc|\.bash_profile|\.config/autostart|\.config/systemd|\.local/share/applications|\.claude)|/etc/(cron|systemd|init)|/var/spool/cron')
[ -n "$PERS" ] && { echo "!! [persistence locations touched]:"; echo "$PERS" | sed 's/^/     /'; [ "$CAP" = persist ] || FOUND=1; }

# the probe command itself = first SUCCESSFUL execve (a bare name fails a few PATH entries first)
FIRST_EXE=$(head -1 "$RUN/exec.log" | cut -d' ' -f2-)
EXE=$(tail -n +2 "$RUN/exec.log" | cut -d' ' -f2- | sort | uniq -c)
report "exec install" "other programs started (count, path):" "$EXE"

if [ "$CAP" = fs-read ] || [ "$CAP" = baseline ]; then
  RD=$(grep -E 'open(at)?\(.*"/home/probe' "$T" | grep -v ' = -1 ' | grep -oE '"/home/probe[^"]*"' | sort -u)
  [ -n "$RD" ] && { echo "-- reads inside the fake home:"; echo "$RD" | sed 's/^/     /'; }
fi

if [ "$CAP" = secrets ]; then
  grep -q '/home/probe/.probe-credential' "$T" && echo "-- configured credential was read (expected)"
fi
if [ "$CAP" = fs-write ] || [ "$CAP" = self-update ]; then
  echo "-- files left in /out:"; (cd "$RUN/out" && find . -type f | sed 's/^/     /')
fi

echo
if [ "$FOUND" = 0 ]; then echo "== VERDICT: within scope for '$CAP'"; exit 0
else echo "== VERDICT: OUT OF SCOPE activity for '$CAP' — see !! lines"; exit 3; fi
