# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.

# --------------------------------------------------------------------- themes
#
# The pictures, not the names. A theme is a look, and a list of twenty-five
# words is the one description of a look that helps nobody.
#
# Which picture stands for a theme is Omarchy's own rule, lifted from
# `omarchy-theme-switcher`: a preview file at the theme's root, in any of the
# formats it accepts, and failing that the first of its backgrounds. A second
# rule here would show a different picture for the same theme in two places.
theme_preview() {
  local dir=$1 name

  for name in preview.png preview.jpg preview.jpeg preview.webp preview.gif preview.bmp; do
    local found
    found=$(find -L "$dir" -maxdepth 1 -type f -iname "$name" -print -quit 2>/dev/null)
    [[ -n $found ]] && { printf '%s\n' "$found"; return; }
  done

  [[ -d $dir/backgrounds ]] || return
  find -L "$dir/backgrounds" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
       -o -iname '*.bmp' -o -iname '*.webp' \) 2>/dev/null | sort | head -n1
}

# `omarchy-theme-list` prints display names — "Catppuccin Latte" — while every
# path is the slug the directory is actually called. The list command builds
# one from the other with a sed; this is that transformation run backwards.
theme_slug() {
  printf '%s\n' "${1,,}" | tr ' ' '-'
}

# Both homes of a theme, user first. `omarchy-theme-dir` answers with one or
# the other, and on this machine the user's copy of Catppuccin holds a single
# neovim.lua — a partial override — so asking it alone finds a theme with no
# colours and no backgrounds. Everything here reads the pair.
theme_dirs() {
  local slug=$1
  [[ -d $HOME_DIR/.config/omarchy/themes/$slug ]] && printf '%s\n' "$HOME_DIR/.config/omarchy/themes/$slug"
  [[ -d ${OMARCHY_PATH:-/usr/share/omarchy}/themes/$slug ]] && printf '%s\n' "${OMARCHY_PATH:-/usr/share/omarchy}/themes/$slug"
  return 0
}

themes_list() {
  local current names name slug dir dirs preview rows=""
  current=$(capture omarchy-theme-current)
  # Read the whole list before looping. Commands run inside a `while read`
  # loop share its stdin and eat the rest of the list — which is why the first
  # version returned exactly one theme.
  names=$(capture omarchy-theme-list)

  while IFS= read -r name; do
    [[ -n $name ]] || continue
    slug=$(theme_slug "$name")
    dirs=$(theme_dirs "$slug")
    [[ -n $dirs ]] || continue

    preview=""
    local isTheme=false first=""
    while IFS= read -r dir; do
      [[ -n $dir ]] || continue
      [[ -z $first ]] && first=$dir
      [[ -f $dir/colors.toml ]] && isTheme=true
      [[ -z $preview ]] && preview=$(theme_preview "$dir")
    done <<<"$dirs"

    # A directory in the themes folder is not a theme unless it says what the
    # colours are; both folders collect other things.
    [[ $isTheme == true ]] || continue
    rows+="$name"$'\t'"$first"$'\t'"$preview"$'\n'
  done <<<"$names"

  jq -R -s -c --arg current "$current" 'split("\n")
    | map(select(length > 0) | split("\t")
      | { name: .[0], dir: .[1], preview: (.[2] // ""),
          current: (.[0] == $current) })' <<<"$rows"
}

# Exactly the two places `omarchy-theme-bg-next` looks, in its order: the
# wallpapers you dropped in for this theme, then the theme's own. And the one
# in force is read off the symlink rather than matched by name —
# `omarchy-theme-bg-current` prints a prettified title, which is a string to
# show a person, not a key to compare paths against.
themes_backgrounds() {
  local theme mine theirs current files
  theme=$(capture omarchy-theme-current)
  mine="$HOME_DIR/.config/omarchy/backgrounds/$theme"
  theirs="$HOME_DIR/.local/state/omarchy/current/theme/backgrounds"
  current=$(readlink -f "$HOME_DIR/.local/state/omarchy/current/background" 2>/dev/null)

  files=$(find -L "$mine" "$theirs" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \
       -o -iname '*.bmp' -o -iname '*.webp' \) 2>/dev/null | sort)

  jq -R -s -c --arg current "${current:-}" 'split("\n") | map(select(length > 0))
    | map({ path: .,
            title: (. | split("/") | last | sub("\\.[^.]+$"; "")
                      | sub("^[0-9]+[-_ ]*"; "") | gsub("[-_]"; " ")
                      | split(" ") | map(select(length > 0)
                      | (.[0:1] | ascii_upcase) + .[1:]) | join(" ")),
            current: (. == $current) })'  <<<"$files"
}

# ------------------------------------------------------------- unlock screens
#
# Plymouth, which Omarchy dresses from a theme: every theme that has one ships
# a `preview-unlock.png` beside its colours, and the shipped default has one
# under `default/plymouth`. So the same rule the Theme page follows applies
# here — the picture is the choice, and a list of names is the one description
# of a look that helps nobody.
#
# `omarchy-plymouth-switcher` builds exactly this list to hand to its own
# picker; it is read rather than run, since running it opens that picker.
unlock_list() {
  local current rows="" name dir preview
  current=$(capture omarchy-plymouth-current)
  [[ -n $current ]] || current=default

  preview="${OMARCHY_PATH:-/usr/share/omarchy}/default/plymouth/preview-unlock.png"
  [[ -f $preview ]] && rows+="default"$'\t'"$(jq -rn "$(i18n_t theme.unlockDefault 'Default')")"$'\t'"$preview"$'\n'

  while IFS= read -r name; do
    [[ -n $name ]] || continue
    while IFS= read -r dir; do
      [[ -n $dir ]] || continue
      [[ -f $dir/preview-unlock.png ]] || continue
      rows+="$name"$'\t'"$(theme_title "$name")"$'\t'"$dir/preview-unlock.png"$'\n'
      break
    done < <(theme_dirs "$name")
  done < <(capture omarchy-plymouth-list)

  jq -R -s -c --arg current "$current" 'split("\n")
    | map(select(length > 0) | split("\t")
      | { name: .[0], title: .[1], preview: .[2], current: (.[0] == $current) })' <<<"$rows"
}

# The slug back into words: plymouth deals in directory names, and the rest of
# this window shows a theme as "Tokyo Night".
theme_title() {
  printf '%s\n' "$1" | tr '-' ' ' \
    | awk '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2); print }'
}

# Setting it needs root — plymouth lives in /usr/share and the initramfs has to
# be rebuilt — so it goes to a terminal with its own password prompt and its
# own output, the way every other privileged flow in this window does. That is
# also exactly what the menu entry does.
unlock_set() {
  local name=${1:-}
  [[ -n $name ]] || die "no unlock screen given"
  if [[ $name == default ]]; then
    setsid -f omarchy-launch-floating-terminal-with-presentation \
      "omarchy-plymouth-reset" >/dev/null 2>&1
  else
    capture omarchy-plymouth-list | grep -qxF -- "$name" \
      || die "'$name' is not an unlock screen"
    setsid -f omarchy-launch-floating-terminal-with-presentation \
      "omarchy-plymouth-set-by-theme $(printf %q "$name")" >/dev/null 2>&1
  fi
}

themes_cmd() {
  local action=${1:-}
  case $action in
    list) themes_list ;;
    unlock-list) unlock_list ;;
    unlock) shift; unlock_set "${1:-}" ;;
    backgrounds) themes_backgrounds ;;
    bg)
      [[ -n ${2:-} ]] || die "no background given"
      [[ -f $2 ]] || die "no such image"
      omarchy-theme-bg-set "$2" >/dev/null 2>&1 || die "could not set the background" ;;
    *) die "unknown theme action '$action'" ;;
  esac
}
