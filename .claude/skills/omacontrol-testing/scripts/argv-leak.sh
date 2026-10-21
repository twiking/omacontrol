#!/usr/bin/env bash
# Whether anything private reaches a command line, where /proc/<pid>/cmdline
# shows it to every user on the machine.
#
# A canary goes into a sandboxed shell.json widget's settings and into the
# git remote of two plugins (one of them standing in for this window's own
# checkout), and the commands that carry those are run. Two nets catch it:
# every program reached through PATH is a shim that logs an argv holding the
# canary before running the real one, and /proc is polled throughout for what
# is started some other way — git runs its https helper from its own
# directory, with the whole URL as an argument. Polling alone misses a jq that
# lives for a millisecond, and strace is not installed here. The remote is a
# local port that accepts and never answers, so a fetch that should not have
# been made stays on screen long enough to be seen.
#
# Every path is sandboxed and the compositor and Omarchy are fakes, because a
# write re-renders the managed Lua and Hyprland reloads whatever changes.
# Exits non-zero when anything leaked.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
work=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/omacontrol-argv-leak.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
sb=$work/sandbox
mkdir -p "$sb"/{home/.config/omarchy/plugins,home/.config/hypr,cache,state,fake,shim}

canary_file=$work/canary
printf 'OMACONTROL-LEAK-%s' "CANARY-$RANDOM$RANDOM" >"$canary_file"
canary=$(<"$canary_file")
hits=$work/hits
: >"$hits"

jq --rawfile c "$canary_file" \
  '.bar.layout.right += [{ id: "test.secretwidget", apiToken: $c, session: { token: $c } }]' \
  "$HOME/.config/omarchy/shell.json" >"$sb/home/.config/omarchy/shell.json" || exit 1
chmod 600 "$sb/home/.config/omarchy/shell.json"
cp "$HOME/.config/hypr/hyprland.lua" "$sb/home/.config/hypr/" 2>/dev/null

python3 -I -c '
import socket, sys, time
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(16)
print(s.getsockname()[1], flush=True)
held = []
while True:
    held.append(s.accept()[0])
' >"$work/port" 2>/dev/null &
listener=$!
trap 'kill $listener 2>/dev/null; rm -rf "$work"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s $work/port ]] && break; sleep 0.1; done
port=$(<"$work/port")

self_id=$(jq -r .id "$repo/manifest.json")
for id in test.credplugin "$self_id"; do
  plugin=$sb/home/.config/omarchy/plugins/$id
  mkdir -p "$plugin"
  printf '{"schemaVersion":1,"id":"%s","name":"Cred","version":"1.0.0","author":"t","description":"t","kinds":["service"],"entryPoints":{"service":"S.qml"}}' \
    "$id" >"$plugin/manifest.json"
  git -C "$plugin" init -q && git -C "$plugin" add -A \
    && git -C "$plugin" -c user.email=t@t -c user.name=t commit -qm init \
    && git -C "$plugin" remote add origin "https://user:$canary@127.0.0.1:$port/example/cred.git"
done

for b in hyprctl omarchy omarchy-shell notify-send tmux herdr; do
  printf '#!/bin/sh\nexit 0\n' >"$sb/fake/$b"
  chmod +x "$sb/fake/$b"
done

cat >"$work/shim.sh" <<SH
#!/bin/bash
name=\${0##*/}
all="\$*"
[[ \$all == *"$canary"* ]] && printf '%s %s\\n' "\$name" "\${all//\$'\\n'/ }" | cut -c1-200 >>"$hits"
[[ -x $sb/fake/\$name ]] && exit 0
exec "/usr/bin/\$name" "\$@"
SH
chmod +x "$work/shim.sh"
for f in /usr/bin/* "$sb"/fake/*; do ln -sf "$work/shim.sh" "$sb/shim/${f##*/}"; done

export HOME=$sb/home XDG_CACHE_HOME=$sb/cache XDG_STATE_HOME=$sb/state XDG_CONFIG_HOME=$sb/home/.config
export OMARCHY_SHELL_JSON=$sb/home/.config/omarchy/shell.json
export OMACONTROL_STORE=$sb/home/.config/omarchy/omacontrol.json
export OMACONTROL_HYPR_DIR=$sb/home/.config/hypr OMACONTROL_BINDINGS_LUA=$sb/home/.config/hypr/bindings.lua
export PATH=$sb/shim:$PATH
for b in jq hyprctl omarchy; do
  [[ $(command -v "$b") == "$sb/shim/$b" ]] || { echo "$b is not the shim; refusing to run" >&2; exit 1; }
done

touch "$work/watching"
( while [[ -e $work/watching ]]; do
    for f in /proc/[0-9]*/cmdline; do
      grep -qaFf "$canary_file" "$f" 2>/dev/null \
        && { printf 'proc '; tr '\0' ' ' <"$f" | cut -c1-180; } >>"$hits"
    done
  done ) &
watcher=$!

# Bounded, because a fetch that should not have been made would otherwise
# wait on the silent port for as long as git cares to.
run() { OMACONTROL_FETCH_TIMEOUT=4 timeout 8 bash "$repo/bin/omacontrol" "$@" >/dev/null 2>&1; }
run state
run bar disable test.secretwidget
run bar enable test.secretwidget
run bar move test.secretwidget left
run bar shift test.secretwidget down
run plugin poll
run plugin directory
run search
run plugin updates
run plugin self-check
rm -f "$work/watching"; wait "$watcher"

kept=$(jq --rawfile c "$canary_file" \
  '[.bar.layout[][] | select(.id == "test.secretwidget" and .apiToken == $c)] | length' \
  "$OMARCHY_SHELL_JSON")
echo "the widget came back with its settings: $([[ $kept == 1 ]] && echo yes || echo NO)"

n=$(grep -c . "$hits")
if (( n == 0 )); then
  echo "nothing private on any command line"
  exit 0
fi
echo "$n command lines carried the canary:"
awk '{ print "  " ($1 == "proc" ? "seen in /proc: " $2 : $1) }' "$hits" | sort | uniq -c
grep -oE -- '--arg(json)? [A-Za-z_]+' "$hits" | sort | uniq -c | sort -rn | head -12
exit 1
