#!/bin/sh
# check.sh: run every golden scenario (desktop/tests/golden/README.md) against the Swift tools and diff the result.
#
#   sh desktop/tests/check.sh [--only <prefix>] [--update] [--render]
#
#   The Swift tools (the probe jebctl, dev/release/release, desktop/gates/jebgates, art/jebart) run with the clock and pid pinned
#   through JEB_TEST_NOW / JEB_TEST_PID.
#   --only <prefix> only the goldens whose path starts with <prefix>, e.g. runtime/follow or release/steps/auto-minor;
#                   --only dev-run runs just dev/run's own test (desktop/tests/dev-run.sh) and --only defaults just run-defaults-test.sh
#   --update        write the produced files into desktop/tests/golden (for intentional deviations; review the diff)
#   --render        also run the parity compare against the frozen band-out.txt (needs a built desktop/src/JebDesktop)
#
# Deterministic and sandboxed: TZ=America/Chicago, LC_ALL=C, clock 1780000000, pid 4242, throwaway ssh keys,
# fake claude/gh/launchctl/curl, the C stub (desktop/tests/stub.c) for every native binary; the real install is never read or written.
# The checker itself is Swift: desktop/tests/goldencheck/*.swift, built into a cache folder under TMPDIR on first use.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GC="$ROOT/desktop/tests/goldencheck"
ONLY=""; UPDATE=0; RENDER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --impl|--impl=*) echo "check.sh: --impl was removed in v1.7.0; the checker drives the Swift tools only" >&2; exit 2;;
    --only) ONLY=$2; shift;;
    --only=*) ONLY=${1#--only=};;
    --update) UPDATE=1;;
    --render) RENDER=1;;
    *) echo "usage: sh desktop/tests/check.sh [--only <prefix>] [--update] [--render]" >&2; exit 2;;
  esac
  shift
done
# the shell and unit tests that are not goldens: dev/run (stubs, no real Jeb) and the defaults-suite check
EXTRA=0
case "$ONLY" in ""|dev-run*) sh "$ROOT/desktop/tests/dev-run.sh" || EXTRA=1;; esac
case "$ONLY" in ""|defaults*) sh "$ROOT/desktop/tests/run-defaults-test.sh" || EXTRA=1;; esac
case "$ONLY" in dev-run*|defaults*) exit $EXTRA;; esac
TMP=${TMPDIR:-/tmp}; TMP=${TMP%/}      # macOS's default TMPDIR ends in "/"; a "//" in a path would dodge the normalizer

# build the checker when a source is newer than the binary. Explicit file list.
SRCS="$GC/main.swift $GC/Sandbox.swift $GC/Normalize.swift $GC/Snapshot.swift $GC/Scenarios.swift $GC/Art.swift"
BIN_DIR="$TMP/jeb-goldencheck-$(id -u)"
BIN="$BIN_DIR/goldencheck"
mkdir -p "$BIN_DIR" || exit 1
NEWER=0
for s in $SRCS; do [ "$s" -nt "$BIN" ] && NEWER=1; done
if [ ! -x "$BIN" ] || [ $NEWER = 1 ]; then
  # shellcheck disable=SC2086
  xcrun swiftc -O -o "$BIN" $SRCS || { echo "check.sh: could not build the checker" >&2; exit 1; }
fi

ARCH=arm64; [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] || ARCH=x86_64
# the probe jebctl (JEB_PROBES=1 desktop/cli/build.sh), unless JEB_CHECK_JEBCTL already names one; rebuilt when a source is newer
if [ -z "${JEB_CHECK_JEBCTL:-}" ]; then
  JEB_CHECK_JEBCTL="$ROOT/desktop/cli/probes/jebctl"
  NEWER=0
  for s in "$ROOT"/desktop/cli/*.swift "$ROOT"/desktop/cli/probes/*.swift "$ROOT/desktop/cli/build.sh"; do
    [ "$s" -nt "$JEB_CHECK_JEBCTL" ] && NEWER=1
  done
  if [ ! -x "$JEB_CHECK_JEBCTL" ] || [ $NEWER = 1 ]; then
    JEB_PROBES=1 JEB_OUT="$JEB_CHECK_JEBCTL" sh "$ROOT/desktop/cli/build.sh" || { echo "check.sh: could not build the probe jebctl (desktop/cli/build.sh)" >&2; exit 1; }
  fi
  export JEB_CHECK_JEBCTL
fi
# the release tool (dev/release/build.sh), unless JEB_CHECK_RELEASE already names one; rebuilt when a source is newer
if [ -z "${JEB_CHECK_RELEASE:-}" ]; then
  JEB_CHECK_RELEASE="$ROOT/dev/release/release"
  NEWER=0
  for s in "$ROOT"/dev/release/*.swift "$ROOT/dev/release/build.sh" "$ROOT"/desktop/cli/*.swift; do
    [ "$s" -nt "$JEB_CHECK_RELEASE" ] && NEWER=1
  done
  if [ ! -x "$JEB_CHECK_RELEASE" ] || [ $NEWER = 1 ]; then
    sh "$ROOT/dev/release/build.sh" || { echo "check.sh: could not build the release tool (dev/release)" >&2; exit 1; }
  fi
  export JEB_CHECK_RELEASE
fi
# the art tool (art/build.sh), unless JEB_CHECK_JEBART already names one; rebuilt when a source is newer. Only the art goldens use it.
case "$ONLY" in ""|art*)
  if [ -z "${JEB_CHECK_JEBART:-}" ]; then
    JEB_CHECK_JEBART="$ROOT/art/jebart"
    NEWER=0
    for s in "$ROOT"/art/src/*.swift "$ROOT/art/build.sh" "$ROOT/art/CZlib/shim.h"; do
      [ "$s" -nt "$JEB_CHECK_JEBART" ] && NEWER=1
    done
    if [ ! -x "$JEB_CHECK_JEBART" ] || [ $NEWER = 1 ]; then
      sh "$ROOT/art/build.sh" || { echo "check.sh: could not build the art tool (art)" >&2; exit 1; }
    fi
    export JEB_CHECK_JEBART
  fi;;
esac
# the gates (desktop/gates/build.sh), unless JEB_CHECK_GATES already names one; rebuilt when a source is newer
if [ -z "${JEB_CHECK_GATES:-}" ]; then
  JEB_CHECK_GATES="$ROOT/desktop/gates/jebgates"
  NEWER=0
  for s in "$ROOT"/desktop/gates/*.swift "$ROOT/desktop/gates/build.sh" "$ROOT/desktop/cli/Json.swift"; do
    [ "$s" -nt "$JEB_CHECK_GATES" ] && NEWER=1
  done
  if [ ! -x "$JEB_CHECK_GATES" ] || [ $NEWER = 1 ]; then
    sh "$ROOT/desktop/gates/build.sh" || { echo "check.sh: could not build the gates (desktop/gates)" >&2; exit 1; }
  fi
  export JEB_CHECK_GATES
fi
T=$(mktemp -d "$TMP/jeb-check.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT INT TERM
export TZ=America/Chicago LC_ALL=C LANG=C
unset DEVELOPER_DIR CLAUDE_CONFIG_DIR CLAUDE_CODE_PLUGIN_DIRS
for v in $(env | sed -n 's/^\(JEB_[A-Za-z0-9_]*\)=.*/\1/p'); do
  case "$v" in JEB_CHECK_*) ;; *) unset "$v";; esac
done
# not exec: the EXIT trap must still run to remove $T
"$BIN" --root "$ROOT" --tmp "$T" --arch "$ARCH" --only "$ONLY" --update "$UPDATE" --render "$RENDER" --home "$HOME"
rc=$?
[ "$EXTRA" = 0 ] || rc=1
exit $rc
