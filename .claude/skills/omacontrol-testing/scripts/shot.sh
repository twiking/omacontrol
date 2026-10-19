#!/usr/bin/env bash
# `grim -g` takes logical coordinates while a full `grim -o` capture is
# physical pixels, so: capture the window's monitor, and crop from that with
# the scale read out of hyprctl rather than assumed. The window is a layer
# surface, not a client, which is why the geometry comes from `hyprctl
# layers` — and that geometry is in the global layout, so it is taken relative
# to its monitor's origin first. Left global, a monitor at x=5440 and scale
# 1.5 asked for a crop starting 8160 pixels into a 3840-pixel capture, and the
# image came out empty.
#
# The monitor is the one holding the layer, not the focused one: the window
# stays where it was opened when the focus moves.
set -uo pipefail
out=${1:-${XDG_RUNTIME_DIR:-/tmp}/omacontrol-page.png}

read -r mon lx ly lw lh < <(hyprctl layers -j | jq -r '
  [to_entries[] | .key as $mon | .value.levels[][]
   | select(.namespace == "omacontrol") | "\($mon) \(.x) \(.y) \(.w) \(.h)"][0] // empty')
[ -n "${mon:-}" ] || { echo "the omacontrol window is not open" >&2; exit 1; }

geom=$(hyprctl -j monitors | jq -r --arg mon "$mon" \
  --argjson lx "$lx" --argjson ly "$ly" --argjson lw "$lw" --argjson lh "$lh" '
  .[] | select(.name == $mon) | .scale as $s
  | "\(($lw*$s)|floor)x\(($lh*$s)|floor)+\((($lx-.x)*$s)|floor)+\((($ly-.y)*$s)|floor)"')
[ -n "$geom" ] || { echo "monitor $mon is not in hyprctl monitors" >&2; exit 1; }

full=$(mktemp --suffix=.png)
grim -o "$mon" "$full" || exit 1
magick "$full" -crop "$geom" +repage "$out" && rm -f "$full"
echo "$out"
