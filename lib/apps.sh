# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# Every application on the machine, and what this desktop has been told to do
# with it. The list is the one the launcher and the Omarchy menu show — the
# visible desktop entries — because three lists of "your apps" that disagree
# are worse than one that is merely long.
#
# Nothing here is a setting. What the page shows about an application is set
# on the pages that own it (a workspace rule on Workspaces, a role on Default
# Apps); this page says what is in force and where to go, and removes the
# application itself. So it polls, like Disk and Processes, and is not in the
# state document: a list of several hundred desktop entries re-read after
# every switch on every other page would be paid for by all of them.

# Which package owns an application, asked one entry at a time.
#
# `pacman -Qo` over four hundred desktop files is seconds; over the one the
# reader has selected it is milliseconds, and the only moment the answer is
# wanted is the moment they ask to remove it.
# Every file that could be this application's entry, nearest first.
#
# Nearest is not the same as owned: an application installed from a package
# often *also* leaves a copy in ~/.local/share/applications — Typora does —
# and that copy belongs to no package. Stopping at the first file found said
# "not owned by a package" about something pacman had installed, so the
# candidates are all offered and the owner is whichever of them a package
# claims.
app_entry_files() {
  local id=$1 dir part
  for dir in "${XDG_DATA_HOME:-$HOME_DIR/.local/share}" "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"; do
    while IFS= read -r part; do
      [[ -f "$part/applications/$id.desktop" ]] && printf '%s\n' "$part/applications/$id.desktop"
    done < <(tr ':' '\n' <<<"$dir")
  done
}

app_owner() {
  local file owner
  while IFS= read -r file; do
    owner=$(capture pacman -Qoq "$file" | head -n1)
    [[ -n $owner ]] && { printf '%s\n' "$owner"; return 0; }
  done < <(app_entry_files "$1")
  return 1
}

# The launcher hides more than a NoDisplay entry: an entry claiming OnlyShowIn
# GNOME, or NotShowIn Hyprland, is not for this desktop and is not shown. That
# rule lives in Omarchy's own `hidden-entries.sh`, which the launcher and the
# menu both run — so it is run here rather than reimplemented, or this page
# would answer "what applications have I got" with thirteen more than Super+
# Space does, and one of the two would be wrong.
app_hidden_ids() {
  local script="${OMARCHY_PATH:-/usr/share/omarchy}/shell/services/hidden-entries.sh"
  [[ -x $script || -f $script ]] || { echo '[]'; return; }
  local desktop
  desktop=$(printf '%s:%s:%s' "${XDG_CURRENT_DESKTOP:-}" "${XDG_SESSION_DESKTOP:-}" "${DESKTOP_SESSION:-}")
  emit_json "$(capture bash "$script" "$desktop" \
    | jq -R -s -c '[ split("\n")[] | select(length > 0) ]')" '[]'
}

# What owns each application, and at which version, in one call.
#
# `pacman -Qo` takes every path at once and names the package *and* its version
# on each line, so the whole page costs one query rather than one per row — a
# query each was 65 forks for a column. A file no package owns is an error line
# and simply has no answer, which is the right one for something installed by
# hand.
apps_owners() {
  local candidates owned
  candidates=$(app_entry_candidates)
  [[ -n $candidates ]] || { echo '{}'; return; }

  owned=$(capture pacman -Qo $(cut -f2 <<<"$candidates" | tr '\n' ' ') \
    | sed -nE 's#^(/.*) is owned by ([^ ]+) (.*)$#\1\t\2\t\3#p')

  # One jq for the whole page. A pass per application was 65 forks and half a
  # second of a poll that runs every five.
  emit_json "$(jq -R -s -c --rawfile candidates <(printf '%s\n' "$candidates") '
    ( [ split("\n")[] | select(length > 0) | split("\t")
        | { key: .[0], value: { package: .[1], version: .[2] } } ] | from_entries) as $owned
    | [ $candidates | split("\n")[] | select(length > 0) | split("\t")
        | select($owned[.[1]] != null)
        | { key: .[0], value: $owned[.[1]] } ]
    # Nearest first, so a packaged application that also drops a copy in the
    # home directory is still owned: the first candidate a package claims wins.
    | reverse | from_entries' <<<"$owned")" '{}'
}

# Every application's candidate entry files, as `id<TAB>path`, nearest first.
app_entry_candidates() {
  local dirs=() dir part id
  IFS=: read -ra dirs <<<"${XDG_DATA_HOME:-$HOME_DIR/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  while IFS= read -r id; do
    for part in "${dirs[@]}"; do
      [[ -f "$part/applications/$id.desktop" ]] && printf '%s\t%s\n' "$id" "$part/applications/$id.desktop"
    done
  done < <(workspace_desktop_entries | jq -r '.[].file')
}

apps_state() {
  local apps ours theirs autostart roles hidden owners
  # The same enumeration the Workspaces page picks from, cached by the mtimes
  # of the applications directories, so opening this page twice is one walk.
  apps=$(workspace_apps)
  ours=$(workspace_rules_ours)
  theirs=$(workspace_config_rules)
  autostart=$(workspace_config_autostart)
  hidden=$(app_hidden_ids)
  owners=$(apps_owners)

  par_begin || { echo '{}'; return; }
  par_run browser capture omarchy-default-browser
  par_run editor capture omarchy-default-editor
  par_run terminal capture omarchy-default-terminal
  par_run agent capture omarchy-default-agent
  # Asked of the folder association itself rather than a default-* command:
  # it names the desktop entry exactly, and every Omarchy has one.
  par_run filemanager capture xdg-mime query default inode/directory
  par_wait
  roles=$(jq -cn \
    --arg browser "$(par_get browser | head -n1)" \
    --arg editor "$(par_get editor | head -n1)" \
    --arg terminal "$(par_get terminal | head -n1)" \
    --arg agent "$(par_get agent | head -n1)" \
    --arg filemanager "$(par_get filemanager | head -n1)" \
    '{ Browser: $browser, Editor: $editor, Terminal: $terminal, Agent: $agent,
       "File manager": ($filemanager | rtrimstr(".desktop")) }
     | with_entries(select(.value != ""))')
  par_end

  emit_json "$(jq -cn --argjson apps "$apps" --argjson ours "${ours:-{\}}" \
    --argjson theirs "${theirs:-{\}}" --argjson autostart "${autostart:-[]}" \
    --argjson roles "${roles:-{\}}" --argjson hidden "${hidden:-[]}" \
    --argjson owners "${owners:-{\}}" '
    # A role names a command ("brave", "nvim"), and an entry is a file
    # ("brave-browser.desktop") — so the two are matched on either the entry
    # id or its class, whichever the command looks like, rather than demanded
    # to be equal.
    def roles_of($id; $class; $name):
      [ $roles | to_entries[]
        | select((.value | ascii_downcase) as $v
                 | $v == ($id | ascii_downcase)
                   or $v == ($class | ascii_downcase)
                   or $v == ($name | ascii_downcase)
                   or ($id | ascii_downcase | startswith($v)))
        | .key ];
    [ $apps[]
      # A running window with no desktop entry belongs to the Workspaces page,
      # which is about classes; this page is about applications you can name.
      | select(.desktop != "")
      | . as $app
      | (.desktop | rtrimstr(".desktop")) as $id
      | select($hidden | index($id) == null)
      | ($ours[.class] // {}) as $o
      | ($theirs[.class] // {}) as $t
      | { id: $id,
          name: .name,
          icon: (.icon // ""),
          kind: (.kind // ""),
          # The version of the package it came from: an application does not
          # report a version anywhere a settings window can read, and the one
          # pacman holds is the one every other tool quotes. Blank for an
          # application no package owns.
          # `"" | split("-")` is the empty list, not [""], so the index has to
          # be defaulted or an unowned application reports null as a version.
          version: (($owners[$id].version // "") | split("-") | (.[0] // "")),
          package: ($owners[$id].package // ""),
          class: .class,
          running: .running,
          workspace: ($o.workspace // $t.workspace // ""),
          autostart: ((($o.autostart // "") != "") or ($autostart | index($app.desktop) != null)),
          # A rule of theirs is shown as a rule, and said to be theirs: this
          # page never writes one, and the difference decides which page can
          # take it back.
          ruled: (($o | length) > 0 or ($t | length) > 0),
          theirs: (($t | length) > 0),
          roles: roles_of($id; .class; .name) }
      | . + { bound: (.workspace != "" or .autostart or .ruled or (.roles | length) > 0) } ]
    | sort_by(.name | ascii_downcase)')" '[]'
}

# The page shows what a web app or a TUI was made with, so the state carries
# it. Only for those two kinds: it is a file read each, and on this machine
# that is five files rather than sixty-five.
apps_state_full() {
  local base made='{}' id kind
  base=$(apps_state)
  while IFS=$'\t' read -r id kind; do
    [[ -n $id ]] || continue
    made=$(jq -c --arg id "$id" --argjson m "$(app_made_with "$id" "$kind")" '.[$id] = $m' <<<"$made")
  done < <(jq -r '.[] | select(.kind == "web" or .kind == "tui") | [.id, .kind] | @tsv' <<<"$base")

  emit_json "$(jq -c --argjson made "${made:-{\}}" \
    'map(. + (if $made[.id] != null then { madeWith: $made[.id] } else {} end))' <<<"$base")" '[]'
}

# The window hides itself for a terminal job — it holds the keyboard
# exclusively, so a password prompt underneath it cannot be typed into — and
# without this the reader is returned to nothing at all, having been somewhere
# a moment ago. So the job outlives the hide and brings the page back.
#
# The terminal is launched detached and does not wait, so "finished" is the
# window going away: the new `org.omarchy.terminal` client, the one that was
# not there before, no longer being there. Waiting on a count instead would
# return early for anyone who already had an Omarchy terminal open.
apps_terminal_windows() {
  capture hyprctl -j clients \
    | jq -r '[ .[] | select(.initialClass == "org.omarchy.terminal") | .address ] | join(" ")'
}

apps_return_after_terminal() {
  local before after new="" address i
  before=$1

  for i in $(seq 1 40); do
    after=$(apps_terminal_windows)
    for address in $after; do
      [[ " $before " == *" $address "* ]] || { new=$address; break 2; }
    done
    sleep 0.5
  done
  [[ -n $new ]] || return 0

  while capture hyprctl -j clients | jq -e --arg a "$new" 'any(.[]; .address == $a)' >/dev/null 2>&1; do
    sleep 1
  done

  # The page it came from, and a re-read with it: the application it was about
  # is either gone now or still there, and both are answers the list has to
  # give rather than keep from before.
  omarchy-shell omacontrol showPage apps.list >/dev/null 2>&1
}

# Making a launcher, with the answers already in hand.
#
# `omarchy-webapp-install` and `omarchy-tui-install` prompt with gum when they
# are given nothing and take every answer as an argument when they are given
# everything — so the window asks in its own fields and hands the whole lot
# over. What is *not* reimplemented is any of what they then do: the favicon
# fetch, the icon cache, the desktop entry and its escaping are theirs, and
# that escaping is the reason this must never write the file itself.
apps_create() {
  local kind=${1:-} out status
  shift || true

  case $kind in
    webapp)
      local name=${1:-} url=${2:-} icon=${3:-}
      [[ -n $name ]] || die "the web app needs a name"
      [[ $name != */* ]] || die "a name cannot contain a slash"
      [[ -n $url ]] || die "the web app needs an address"
      # Left empty, the icon is the site's own: the script fetches it, and
      # asking for one up front would be asking for something most sites give.
      out=$(timeout 45 omarchy-webapp-install "$name" "$url" "$icon" 2>&1)
      status=$? ;;
    tui)
      local name=${1:-} command=${2:-} style=${3:-float} icon=${4:-}
      [[ -n $name ]] || die "the app needs a name"
      [[ $name != */* ]] || die "a name cannot contain a slash"
      [[ -n $command ]] || die "the app needs a command to run"
      [[ $style == float || $style == tile ]] || die "'$style' is not float or tile"
      [[ -n $icon ]] || die "the app needs an icon name or URL"
      out=$(timeout 45 omarchy-tui-install "$name" "$command" "$style" "$icon" 2>&1)
      status=$? ;;
    *) die "unknown thing to create '$kind'" ;;
  esac

  # The script says why in its own words — "Failed to download icon", "web app
  # URL must be http or https" — and that is what the window shows.
  [[ $status -eq 0 ]] || die "${out:-could not create it}"
}

# What an Omarchy-made launcher was made with, read back out of its entry.
#
# A web app is its address and its icon; a TUI is its command, whether it
# floats, and its icon. Both are written into the Exec line by the script that
# made them, and reading it back is the only way to show the reader what they
# chose — the file is the record.
app_made_with() {
  local id=$1 file exec icon kind=$2
  file=$(app_entry_files "$id" | head -n1)
  [[ -n $file ]] || { echo '{}'; return; }
  exec=$(sed -nE 's/^Exec=(.*)$/\1/p' "$file" | head -n1)
  icon=$(sed -nE 's/^Icon=(.*)$/\1/p' "$file" | head -n1)

  local url="" command="" style=""
  case $kind in
    web) url=$(sed -nE 's/.*omarchy-launch-webapp[[:space:]]+"?([^"[:space:]]+)"?.*/\1/p' <<<"$exec") ;;
    tui)
      command=$(sed -nE 's/.*--app-id=TUI\.[a-z]+[[:space:]]+-e[[:space:]]+(.*)$/\1/p' <<<"$exec")
      style=$(sed -nE 's/.*--app-id=TUI\.([a-z]+).*/\1/p' <<<"$exec") ;;
  esac

  jq -cn --arg url "$url" --arg command "$command" --arg style "$style" --arg icon "$icon" \
    '{ url: $url, command: $command, style: $style, icon: $icon }'
}

# Changing one of them is the installer run again with the other answers as
# they stand: the entry is generated by that script, and rewriting the file
# here would be this window taking over a format it does not own — the Exec
# escaping alone is reason enough not to.
apps_edit() {
  local id=${1:-} field=${2:-} value=${3:-} kind made name out status
  [[ -n $id ]] || die "no application given"

  kind=$(apps_state | jq -r --arg id "$id" '.[] | select(.id == $id) | .kind')
  [[ $kind == web || $kind == tui ]] || die "'$id' was not made here"
  made=$(app_made_with "$id" "$kind")
  # The name is the file it lives in, so it is not one of the things that can
  # be changed from here: a rename is a new launcher and the old one left
  # behind, which is not what a field labelled Name would promise.
  name=$(apps_state | jq -r --arg id "$id" '.[] | select(.id == $id) | .name')

  local url command style icon
  url=$(jq -r '.url' <<<"$made"); command=$(jq -r '.command' <<<"$made")
  style=$(jq -r '.style' <<<"$made"); icon=$(jq -r '.icon' <<<"$made")
  case $field in
    url) url=$value ;;
    command) command=$value ;;
    style) [[ $value == float || $value == tile ]] || die "'$value' is not float or tile"; style=$value ;;
    icon) icon=$value ;;
    *) die "unknown setting '$field'" ;;
  esac

  if [[ $kind == web ]]; then
    [[ -n $url ]] || die "the web app needs an address"
    out=$(timeout 45 omarchy-webapp-install "$name" "$url" "$icon" 2>&1)
  else
    [[ -n $command ]] || die "the app needs a command to run"
    [[ -n $icon ]] || die "the app needs an icon name or URL"
    out=$(timeout 45 omarchy-tui-install "$name" "$command" "${style:-float}" "$icon" 2>&1)
  fi
  status=$?
  [[ $status -eq 0 ]] || die "${out:-could not save it}"
}

apps_cmd() {
  local action=${1:-state} id=${2:-}
  case $action in
    state|poll) apps_state_full ;;
    owner)
      [[ -n $id ]] || die "no application given"
      app_owner "$id" || true ;;
    # Removing an application is a package operation with a password prompt
    # and a confirmation, like everything else on the Packages page, so it is
    # handed to a terminal rather than run headless. The owning package is
    # resolved here rather than in the window: a caller naming a package would
    # be naming something this window never showed.
    remove)
      [[ -n $id ]] || die "no application given"
      local owner before kind
      kind=$(apps_state | jq -r --arg id "$id" '.[] | select(.id == $id) | .kind')
      # A web app or a TUI has no package behind it, and Omarchy has a command
      # for each: no terminal and no password, so the list simply loses a row.
      if [[ $kind == web || $kind == tui ]]; then
        local name
        name=$(apps_state | jq -r --arg id "$id" '.[] | select(.id == $id) | .name')
        if [[ $kind == web ]]; then capture omarchy-webapp-remove "$name" >/dev/null
        else capture omarchy-tui-remove "$name" >/dev/null; fi
        return 0
      fi
      owner=$(app_owner "$id")
      # Said in the terminal rather than as an error nobody is there to read:
      # the window hides itself for this, so a `die` here is a click that does
      # nothing at all — which is exactly how it looked.
      if [[ -z $owner ]]; then
        before=$(apps_terminal_windows)
        setsid -f omarchy-launch-floating-terminal-with-presentation \
          "echo 'No package owns $(printf '%q' "$id"). It was installed by hand, so it has to be removed by hand.'" \
          >/dev/null 2>&1
        setsid -f bash "$OMACONTROL_BIN" apps return-after "$before" >/dev/null 2>&1
        return 0
      fi
      before=$(apps_terminal_windows)
      setsid -f omarchy-launch-floating-terminal-with-presentation \
        "sudo pacman -Rns $(printf '%q' "$owner")" >/dev/null 2>&1
      # Detached and re-entered rather than a child: the window is hiding as
      # this returns, and a job of its own would go with the page that asked.
      setsid -f bash "$OMACONTROL_BIN" apps return-after "$before" >/dev/null 2>&1 ;;
    # Not for the window to call: the detached half of `remove`.
    return-after) apps_return_after_terminal "$id" ;;
    # Making one of these is a script that asks questions in a terminal, and
    # the menu already has both — so the menu entry is what runs, rather than a
    # second copy of the command that drifts from it.
    install)
      local opening
      # Read before the terminal is launched, or the window it opens is in the
      # list of the ones that were already there and nothing is ever waited on.
      opening=$(apps_terminal_windows)
      case $id in
        webapp) menu_run install.webapp ;;
        tui) menu_run install.tui ;;
        *) die "unknown thing to install '$id'" ;;
      esac
      setsid -f bash "$OMACONTROL_BIN" apps return-after "$opening" >/dev/null 2>&1 ;;
    create) shift; apps_create "$@" ;;
    edit) shift; apps_edit "$@" ;;
    made-with) [[ -n $id ]] || die "no application given"
      app_made_with "$id" "${3:-}" ;;
    # A fixed address, opened in the browser: the field takes an icon URL and
    # nothing in the window says where to find one.
    icons) setsid -f xdg-open "https://dashboardicons.com" >/dev/null 2>&1 ;;
    launch)
      [[ -n $id ]] || die "no application given"
      setsid -f uwsm app -- "$id.desktop" >/dev/null 2>&1 ;;
    *) die "usage: omacontrol apps state|poll|owner <id>|remove <id>|launch <id>|install webapp|tui|create webapp <name> <url> [icon]|create tui <name> <command> <float|tile> <icon>" ;;
  esac
}
