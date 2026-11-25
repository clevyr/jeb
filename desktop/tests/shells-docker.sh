#!/bin/sh
# shells-docker.sh: check, in throwaway Linux containers, that the PATH lines `jebctl add-path` writes for fish and nushell
# work, and that the install's check commands and reload lines (desktop/cli/Picker.swift: checkShell, reloadCommand) do
# what they claim. zsh and bash are covered on the Mac by the unit tests; fish and nushell are usually not installed there.
#
#   sh desktop/tests/shells-docker.sh
#
# Needs Docker. Pulls debian:bookworm-slim (fish from apt) and ghcr.io/nushell/nushell; nothing is written outside the
# containers, which are removed. The lines below must match pathLine() and checkShell(); the unit tests pin pathLine().
set -u

MARK="# added by Jeb's ./install"
FISH_LINE='fish_add_path -g ~/.local/bin'
NU_LINE='$env.PATH = ($env.PATH | split row (char esep) | prepend ("~/.local/bin" | path expand) | uniq)'
FISH_IMAGE=debian:bookworm-slim
NU_IMAGE=ghcr.io/nushell/nushell:latest

command -v docker >/dev/null || { echo "shells-docker: docker is not installed"; exit 2; }

# Shared by both containers: a fake jebctl, a bare PATH, and the expect helper.
PRELUDE='
set -u
fails=0
expect() {  # expect <found|missing> <what> <command...>
  want=$1 what=$2; shift 2
  if "$@" >/dev/null 2>&1; then got=found; else got=missing; fi
  if [ "$got" = "$want" ]; then echo "  ok    $what ($got)"; else echo "  FAIL  $what: wanted $want, got $got"; fails=$((fails+1)); fi
}
mkdir -p "$HOME/.local/bin"
printf "#!/bin/sh\n" > "$HOME/.local/bin/jebctl"
chmod +x "$HOME/.local/bin/jebctl"
'

FISH_SCRIPT=$PRELUDE'
apt-get update -qq >/dev/null && apt-get install -y -qq fish >/dev/null 2>&1 || { echo "  FAIL  apt-get install fish"; exit 1; }
echo "  $(fish --version)"
export PATH=/usr/bin:/bin
f="$HOME/.config/fish/conf.d/jeb.fish"
expect missing "login fish, before the line" fish -l -c "command -q jebctl"
mkdir -p "$(dirname "$f")"
printf "%s\n%s\n" "$MARK" "$LINE" > "$f"
expect found "login fish, after the line (the install check)" fish -l -c "command -q jebctl"
expect missing "fish without config" fish --no-config -c "command -q jebctl"
expect found "the line run twice is harmless" fish -l -c "source $f; command -q jebctl"
rm "$f"   # reload: a fish already open when the line is written; the install offers just the PATH line (reloadCommand)
expect found "reload: the PATH line alone, typed into a window already open" fish -l -c "command -q jebctl; and exit 1; $LINE; command -q jebctl"
exit $fails
'

NU_SCRIPT=$PRELUDE'
NU=$(command -v nu) || { echo "  FAIL  nu not in the image"; exit 1; }
echo "  nushell $($NU --version)"
export PATH=/usr/bin:/bin
f=$($NU -c "\$nu.env-path")
echo "  env.nu: $f"
probe="if (which jebctl | is-empty) { exit 1 }"
expect missing "nu --env-config, before the line" $NU --env-config "$f" -c "$probe"
mkdir -p "$(dirname "$f")"
[ -f "$f" ] && cp "$f" "$f.orig"
printf "%s\n%s\n" "$MARK" "$LINE" >> "$f"
expect found "nu --env-config, after the line (the install check)" $NU --env-config "$f" -c "$probe"
expect found "login nu, after the line" $NU -l -c "$probe"
expect missing "nu -n (no config)" $NU -n -c "$probe"
expect found "reload: the PATH line alone (reloadCommand)" $NU -n -c "$LINE; $probe"
expect found "PATH stays a list with no duplicates" $NU --env-config "$f" -c "source \$nu.env-path; if ((\$env.PATH | describe) !~ \"^list\") or ((\$env.PATH | length) != (\$env.PATH | uniq | length)) { exit 1 }"
exit $fails
'

status=0
echo "fish ($FISH_IMAGE)"
docker run --rm -e MARK="$MARK" -e LINE="$FISH_LINE" "$FISH_IMAGE" sh -c "$FISH_SCRIPT" || status=1
echo "nushell ($NU_IMAGE)"
docker run --rm --entrypoint /bin/sh -e MARK="$MARK" -e LINE="$NU_LINE" "$NU_IMAGE" -c "$NU_SCRIPT" || status=1
[ $status = 0 ] && echo "shells-docker: all passed" || echo "shells-docker: FAILED"
exit $status
