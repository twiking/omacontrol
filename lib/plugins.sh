# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.

# ----------------------------------------------------------------- plugins

# An update check is a network round trip per plugin, so its answer outlives
# the sweep: the page shows the last verdict the moment it opens instead of a
# blank list waiting to be re-checked. It is derived data, re-earnable at any
# time by checking again, so it lives in the cache rather than next to the
# settings the user actually chose.
OMACONTROL_FETCH_TIMEOUT="${OMACONTROL_FETCH_TIMEOUT:-30}"
UPDATE_CACHE="${OMACONTROL_UPDATE_CACHE:-${XDG_CACHE_HOME:-$HOME_DIR/.cache}/omarchy/omacontrol/plugin-updates.json}"

# The cache path is as predictable as any other, and it is read straight into
# the window, so it is read the same bounded, descriptor-checked way as
# anything else we did not write this second.
plugin_updates_cache() {
  read_file "$UPDATE_CACHE" \
    | jq -c --argjson now "$(date +%s)" '
        { checkedAt: (.checkedAt // 0),
          results: (.results // {}),
          changes: (.changes // {}),
          versions: (.versions // {}),
          # An update detached from this window can be killed with the shell
          # it was started from, and would then spin forever. A marker older
          # than the longest plausible update is not an update in flight.
          running: ((.running // {}) | with_entries(select(.value > $now - 600))),
          last: (.last // {}),
          # An add is one at a time rather than one per plugin — there is no
          # id to key it by until the clone has been read — and it goes stale
          # the same way an update marker does.
          adding: (if ((.adding // null) != null and .adding.at > $now - 600)
                   then .adding else null end),
          lastAdd: (.lastAdd // null) }' 2>/dev/null && return
  echo '{"checkedAt":0,"results":{},"changes":{},"versions":{},"running":{},"last":{},"adding":null,"lastAdd":null}'
}

# Same for putting it back: a fresh random sibling, renamed into place, so a
# name planted at the cache path is replaced rather than written through.
write_update_cache() {
  local tmp
  mkdir -p "$(dirname "$UPDATE_CACHE")" || return 1
  tmp=$(mktemp "$UPDATE_CACHE.XXXXXX") || return 1
  cat >"$tmp" || { rm -f "$tmp"; return 1; }
  [[ -s $tmp ]] || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$UPDATE_CACHE"
}

# `emit_json` and not `… | jq … || echo '[]'`. Under pipefail the status of
# `producer | jq` is the *producer's*, so a plugin list that printed perfectly
# good JSON and then exited non-zero got `[]` stapled to the end of it — and
# the result is not JSON at all. It matters more than it did: the page's poll
# and both halves of the marketplace lookup now read this.
plugins_state() {
  emit_json "$(capture omarchy plugin list --json | jq -c '[.[] | {
    id: .id,
    name: (.name // .id),
    kinds: (.kinds // []),
    enabled: (.enabled == true),
    # The bar cannot be switched off, and a toggle that refuses is worse than
    # no toggle: Omarchy already knows which ones those are.
    canDisable: (.canDisable != false),
    firstParty: (.firstParty // .isFirstParty // false),
    description: (.description // "")
  }]' 2>/dev/null)" '[]'
}

# Whether each installed plugin has commits waiting upstream. One line per
# plugin, printed the moment that plugin's own fetch settles rather than at
# the end, so the window can retire one spinner at a time. The count is the
# payload; -1 means the plugin is not a git checkout, -2 that the fetch
# failed (no network, private remote, gone), and -3 that it was not tried
# because the remote's address carries a sign-in.
plugin_updates() {
  local dir="$HOME_DIR/.config/omarchy/plugins"
  [[ -d $dir ]] || return 0

  # The comparison is omarchy-plugin-update's own, on purpose: it fetches
  # origin HEAD — the remote's default branch, not the local branch's
  # upstream — and fast-forwards onto it. Counting anything else here would
  # promise an update the Update button then refuses to make. A plugin parked
  # on a non-default branch is therefore measured against the default one,
  # upstream's limitation and ours alike.
  #
  # The fetches are network-bound and independent, so they run together —
  # sequentially this takes a second per plugin and feels broken.
  local out
  out=$(mktemp) || return 1

  # The verdicts stream out as they land and are kept at the same time; the
  # window wants them one by one, the next window wants them all at once.
  # Hidden directories are skipped, and it matters here rather than merely
  # being tidy: `omarchy plugin remove` leaves the plugin behind as
  # `.<id>.bak.<stamp>`, which is a git checkout with a remote, so every sweep
  # spent a network fetch on it and reported it as something to update.
  { find -L "$dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -printf '%f\n' 2>/dev/null | sort |
    PLUGINS_DIR="$dir" FETCH_TIMEOUT="$OMACONTROL_FETCH_TIMEOUT" xargs -r -P 6 -I{} bash -c '
      id=$1
      repo="$PLUGINS_DIR/$id"
      if [[ ! -d $repo/.git ]]; then
        printf "%s\t-1\n" "$id"
      # An address with a sign-in in it is not fetched: git hands the whole
      # URL to its https helper as an argument, where every user on the
      # machine can read it for as long as the fetch takes. The address is
      # read locally; nothing has gone over the network to find this out.
      elif [[ $(git -C "$repo" remote get-url origin 2>/dev/null) =~ ^[Hh][Tt][Tt][Pp][Ss]?://[^/]*@ ]]; then
        printf "%s\t-3\n" "$id"
      elif GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}" \
           timeout "${FETCH_TIMEOUT:-30}" git -C "$repo" fetch -q origin HEAD 2>/dev/null; then
        # The bounds are spelled out rather than shared: this runs in a bash
        # xargs started, which never sourced anything of ours.
        # Double quotes on purpose: this whole worker is a single-quoted
        # string, so a single quote here ends it and the script stops parsing.
        #
        # The subjects come off the FETCH_HEAD the count was just taken from,
        # so saying what is coming costs no second round trip. They stand in
        # for the diff the terminal used to print: enough to decide with,
        # short enough to sit on a row.
        #
        # The version upstream is calling itself comes off the same FETCH_HEAD
        # too, so the row can name what is coming rather than only counting
        # it. Read from the manifest in that commit and not from the
        # marketplace listing: the listing is what was submitted, and this is
        # what the Update button would actually install.
        printf "%s\t%s\t%s\t%s\n" "$id" \
          "$(timeout 10 git -C "$repo" rev-list --count HEAD..FETCH_HEAD 2>/dev/null | head -c 32 || echo 0)" \
          "$(timeout 10 git -C "$repo" log --format=%s -n 3 HEAD..FETCH_HEAD 2>/dev/null \
             | tr "\t|" "  " | paste -s -d "|" - | head -c 300)" \
          "$(timeout 10 git -C "$repo" show FETCH_HEAD:manifest.json 2>/dev/null \
             | head -c 16384 | jq -r ".version // empty" 2>/dev/null \
             | tr -d "\t\n" | head -c 32)"
      else
        printf "%s\t-2\n" "$id"
      fi' _ {}
  } | tee "$out"

  # What an update said about itself outlives a sweep: the sweep is about the
  # counts, and rebuilding the whole document would throw away the answer the
  # page is still showing.
  #
  # Carried forward only for what is still installed, though, and a failure
  # only while the plugin is still behind. A "cannot fast-forward" that the
  # reader has since mended by hand — or by removing and adding the plugin —
  # otherwise stayed on its row until the next Update, which there was no
  # longer any reason to press. A success stays: it is the answer to a button
  # pressed a moment ago. 0 is "fetched and up to date"; a fetch that failed
  # (-2) proves nothing, so its failure stands.
  jq -Rn --argjson at "$(date +%s)" --argjson prev "$(plugin_updates_cache)" '
    [inputs | split("\t") | select(length >= 2)] as $rows
    | ([$rows[] | { key: .[0], value: (.[1] | tonumber) }] | from_entries) as $results
    | { checkedAt: $at,
        results: $results,
        changes: ([$rows[] | select((.[2] // "") != "") | { key: .[0], value: .[2] }] | from_entries),
        versions: ([$rows[] | select((.[3] // "") != "") | { key: .[0], value: .[3] }] | from_entries),
        running: (($prev.running // {}) | with_entries(.key as $id | select($results | has($id)))),
        last: (($prev.last // {}) | with_entries(.key as $id
                | select(($results | has($id))
                         and (.value.ok == true or $results[$id] != 0)))) }' \
    <"$out" 2>/dev/null | write_update_cache
  rm -f "$out"
}

# ------------------------------------------------------- our own update
#
# The window is itself a plugin, and a plugin that is behind says so in its
# own corner rather than waiting to be noticed on the Plugins page. The id
# comes from the manifest beside this code, so a fork or a clone reports on
# itself rather than on whoever it was forked from.
OMACONTROL_DIR="${OMACONTROL_DIR:-$(cd "$OMACONTROL_LIB/.." 2>/dev/null && pwd)}"

self_id() {
  jq -r '.id // empty' "$OMACONTROL_DIR/manifest.json" 2>/dev/null
}

# The manifest is the one place a version is written, so it is the one place
# it is read from: a copy anywhere else is a number that goes stale on the
# release that forgets it.
self_version() {
  jq -r '.version // empty' "$OMACONTROL_DIR/manifest.json" 2>/dev/null
}

# What the last sweep — the Plugins page, or self_check below — learned about
# us. Reading the cache costs nothing, so the corner can be drawn immediately
# and corrected once the check behind it lands.
self_update_state() {
  local id version
  id=$(self_id)
  version=$(self_version)
  [[ -n $id ]] || { echo '{"behind":0,"checkedAt":0,"version":""}'; return; }

  plugin_updates_cache | jq -c --arg id "$id" --arg version "$version" '
    { id: $id, version: $version, behind: ((.results[$id] // 0)), checkedAt: (.checkedAt // 0) }'
}

# An http(s) address with a user or token before the host. An ssh user name
# (`git@github.com`) is not a secret and is not counted.
url_signed_in() { [[ ${1,,} =~ ^https?://[^/]*@ ]]; }
plugin_remote_signed_in() {
  url_signed_in "$(capture git -C "$1" remote get-url origin)"
}

# One fetch, ours only, folded into the same cache the Plugins page reads.
# The window runs it in the background on open: it is a network round trip,
# and nothing should wait on it.
self_check() {
  local id repo behind
  id=$(self_id)
  [[ -n $id ]] || return 0
  repo="$HOME_DIR/.config/omarchy/plugins/$id"
  [[ -d $repo/.git ]] || { self_update_state; return 0; }

  # Not fetched with a sign-in in the address, for the reason the sweep gives.
  if plugin_remote_signed_in "$repo"; then
    behind=-3
  elif GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}" \
     git -C "$repo" fetch -q origin HEAD 2>/dev/null; then
    behind=$(capture git -C "$repo" rev-list --count HEAD..FETCH_HEAD || echo 0)
  else
    behind=-2
  fi

  jq -c --arg id "$id" --argjson behind "${behind:-0}" --argjson at "$(date +%s)" \
    '.checkedAt = $at | .results = ((.results // {}) | .[$id] = $behind)' \
    <<<"$(plugin_updates_cache)" 2>/dev/null | write_update_cache

  self_update_state
}

# ---------------------------------------------------------- applying one
#
# `omarchy-plugin-update <id> --yes` is entirely non-interactive: the diff and
# the gum confirm it prints are the *unattended* half of the flow, skipped by
# --yes. Only the asking needed a terminal, and this window has already asked
# — the row says how many commits are coming and what they say.
#
# It does not run as a child of the window, though. The shell watches the
# plugins directory with `inotifywait -m -r` and reloads every plugin widget
# on any change under it — this window's host included — so a `git merge` in
# there takes the window down while the merge is still running. A child of it
# would be killed part-way through, and the answer would die with the window
# that asked. So the work is detached, says what it did in the cache the page
# reads, and then brings the window back.

# Bringing the window back afterwards. The reload takes it down mid-update, so
# the job that survived is the only thing left that knows it should return —
# and it has to wait its turn: the shell may still be tearing down, rebuilding,
# or (having been asked to rescan) starting the plugins up again. Summoning
# into that lands on the panel that is going away, so this waits for the shell
# to answer at all, lets the teardown settle, and then keeps asking.
reopen_window() {
  local page=${1:-plugins} i
  for i in $(seq 1 60); do
    [[ -n $(omarchy-shell shell ping 2>/dev/null) ]] && break
    sleep 0.5
  done
  sleep 0.6
  for i in $(seq 1 20); do
    omarchy-shell omacontrol showPage "$page" >/dev/null 2>&1
    window_open && return 0
    sleep 0.5
  done
}

# The layer, not the exit code: the IPC call returns nothing either way, and a
# summon eaten by a dying panel looks exactly like one that worked.
window_open() {
  capture hyprctl layers -j | jq -e '..|select(.namespace? == "omacontrol")' >/dev/null 2>&1
}

plugin_update_start() {
  local id=$1

  jq -c --arg id "$id" --argjson at "$(date +%s)" \
    '.running = ((.running // {}) | .[$id] = $at) | .last = ((.last // {}) | del(.[$id]))' \
    <<<"$(plugin_updates_cache)" 2>/dev/null | write_update_cache

  # Whether to come back is decided here, while the window is still up to be
  # asked. A summon after the fact cannot tell a window that was torn down
  # from one the reader had already closed, and opening a window nobody asked
  # for is worse than not returning to one.
  local reopen=0
  window_open && reopen=1

  setsid bash "$OMACONTROL_BIN" plugin update-run "$id" "$reopen" >/dev/null 2>&1 &
  disown 2>/dev/null || true

  # The window wants the spinner now, not at the next poll.
  plugin_updates_cache
}

# Adding is the same shape as updating, and for the same reason: the clone
# lands in the directory the shell watches, so the reload takes this window
# down before git has finished — a child of the window would be killed
# part-way through its own clone, leaving a half-cloned stage directory
# beside the plugins. Detached, it reports into the cache and brings the
# window back.
plugin_add_start() {
  local url=$1 enable=${2:-leave} reopen=0
  [[ -n $url ]] || die "no git URL given"
  # Git would pass it to its https helper on the command line, and this
  # window to two processes of its own, all readable by every user here.
  url_signed_in "$url" && die "leave the sign-in out of the address"

  jq -c --arg url "$url" --argjson at "$(date +%s)" \
    '.adding = { url: $url, at: $at } | .lastAdd = null' \
    <<<"$(plugin_updates_cache)" 2>/dev/null | write_update_cache

  # Asked while the window is still up to be asked, exactly as an update is.
  window_open && reopen=1

  setsid bash "$OMACONTROL_BIN" plugin add-run "$url" "$enable" "$reopen" >/dev/null 2>&1 &
  disown 2>/dev/null || true

  plugin_updates_cache
}

plugin_add_run() {
  local url=$1 enable=${2:-leave} reopen=${3:-0} out rc msg id args=()

  # --yes is the whole of what the terminal flow asked: the trust warning and
  # the confirm, both of which the page has already put in front of the
  # reader, and the bar section, which is the plugin's own default here.
  args=("$url" --yes)
  [[ $enable == enable ]] && args+=(--enable)
  out=$(omarchy-plugin-add "${args[@]}" 2>&1 | tail -c 4096)
  rc=$?

  if (( rc == 0 )); then
    # Upstream's own last line is "Enable it later with: omarchy plugin
    # enable x", which is a command to type at a reader who has just pressed
    # a button. So the id is taken off the line that has it and the sentence
    # is the window's own.
    id=$(sed -n 's/^Added \([^[:space:]]*\) into .*/\1/p' <<<"$out" | head -n 1)
    if [[ $enable == enable ]]; then
      msg="Added ${id:-it} and switched it on."
    else
      msg="Added ${id:-it}. It stays off until you switch it on."
    fi
  else
    msg=$(printf '%s' "$out" | grep -v '^[[:space:]]*$' | tail -n 1 | head -c 400)
    # Whichever of Omarchy's scripts refused, it says so by name first, and
    # a command name is not something the window shows a reader — its own
    # heading already says what could not be done. Shortest match, so it
    # stops at the first colon and leaves a path in the message alone.
    msg=${msg#omarchy-*: }
    msg=${msg:-Could not add it.}
  fi

  jq -c --argjson ok "$(( rc == 0 ? 1 : 0 ))" --arg msg "$msg" --argjson at "$(date +%s)" \
    '.adding = null | .lastAdd = { ok: ($ok == 1), message: $msg, at: $at }' \
    <<<"$(plugin_updates_cache)" 2>/dev/null | write_update_cache

  (( reopen == 1 )) && reopen_window
  return 0
}

# What it said stands until the reader has read it and said so.
plugin_add_clear() {
  jq -c '.lastAdd = null' <<<"$(plugin_updates_cache)" 2>/dev/null | write_update_cache
  plugin_updates_cache
}

plugin_update_run() {
  local id=$1 reopen=${2:-0} out rc msg
  # Bounded by the tail rather than the head, and deliberately: `head -c`
  # closes the pipe once it has enough, and the SIGPIPE that follows would
  # land on a git merge half way through someone's plugin. Reading it all and
  # keeping the end costs nothing here — the last line is the whole point —
  # and cannot kill the thing being measured.
  out=$(omarchy-plugin-update "$id" --yes 2>&1 | tail -c 4096)
  rc=$?

  # Upstream's own last line is the message worth showing: "Updated x.",
  # "x is up to date.", or why it refused.
  msg=$(printf '%s' "$out" | grep -v '^[[:space:]]*$' | tail -n 1 | head -c 400)
  if [[ -z $msg ]]; then
    (( rc == 0 )) && msg="Updated." || msg="Update failed."
  fi

  # A successful update makes the recorded count a lie; the cheapest honest
  # answer is zero, which is what a fresh check would find anyway.
  jq -c --arg id "$id" --argjson ok "$(( rc == 0 ? 1 : 0 ))" --arg msg "$msg" \
     --argjson at "$(date +%s)" '
       .running = ((.running // {}) | del(.[$id]))
       | .last = ((.last // {}) | .[$id] = { ok: ($ok == 1), message: $msg, at: $at })
       | if $ok == 1 then
           .results = ((.results // {}) | .[$id] = 0)
           | .changes = ((.changes // {}) | del(.[$id]))
         else . end' \
    <<<"$(plugin_updates_cache)" 2>/dev/null | write_update_cache

  # The verdict is written before the window is asked back, so the page it
  # opens on already has it.
  (( reopen == 1 )) && reopen_window
  return 0
}

# --------------------------------------------- what the machine itself knows
#
# What a marketplace verification can be held against: where this copy was
# cloned from, the commit it is at, and whether its files are still that
# commit's. Sets `origin`, `head` and `pristine` in the caller; `pristine` is
# null when git could not answer, which is not the same as a copy changed.
#
# Only a directory with its own `.git` is asked. Without that check git walks
# upwards, and a plugin copied into a dotfiles repository would answer with
# the dotfiles' remote and commit.
#
# Untracked files are judged by the plugin's own `.gitignore` alone, not by
# this machine's global excludes or `info/exclude`: a plugin that builds a
# helper on install leaves output its repository already declares, and only
# a file it does not account for makes the copy different from the commit.
# That leaves the `.gitignore` files themselves, which are read whether
# tracked or not — so an untracked one, which could hide itself and anything
# beside it, is a change on its own.
#
# fsmonitor is off because reading the index otherwise starts a daemon in
# every plugin for anyone who has it on globally, and replace objects and
# external diff drivers are off so the commit compared is the one named.
plugin_git() {
  capture git -c core.fsmonitor=false --no-replace-objects -C "$path" "$@"
}

plugin_checkout() {
  local path=$1 rc listed
  origin='' head='' pristine=null
  [[ -e $path/.git ]] || { pristine=false; return 0; }
  # `get-url` rather than the raw config, so an `insteadOf` alias arrives as
  # the address it stands for.
  origin=$(plugin_git remote get-url origin)
  head=$(plugin_git rev-parse --verify -q HEAD)
  [[ -n $head ]] || return 0

  plugin_git diff --quiet --no-ext-diff --no-textconv HEAD -- >/dev/null
  rc=$?
  (( rc == 1 )) && { pristine=false; return 0; }
  (( rc == 0 )) || return 0

  # Files git has been told to stop looking at: assume-unchanged (lower case)
  # and skip-worktree (S) are both edits a diff will not show.
  listed=$(plugin_git ls-files -v) || return 0
  [[ $'\n'$listed =~ $'\n'[a-zS]' ' ]] && { pristine=false; return 0; }

  listed=$(plugin_git ls-files --others -- ':(glob)**/.gitignore') || return 0
  [[ -n $listed ]] && { pristine=false; return 0; }
  listed=$(plugin_git ls-files --others --exclude-per-directory=.gitignore) || return 0
  [[ -n $listed ]] && pristine=false || pristine=true
  return 0
}

# What each installed plugin declares about itself, and what it occupies.
#
# `omarchy plugin list` answers none of this: it knows an id, a name, the kinds
# and whether the plugin is on. The version, the author and the licence are in
# the manifest beside each plugin — the same file Omarchy reads to build that
# list, and the one place a plugin's version is written.
#
# Keyed by the manifest's id, not the directory's name, because that is how
# the shell keys them. Two directories claiming one id are both loaded under
# it and only one of them runs, so neither can be said to be the copy the
# page is describing: the entry is marked `contested` and earns no listing.
plugin_local() {
  local dir="$HOME_DIR/.config/omarchy/plugins"
  [[ -d $dir ]] || { echo '{}'; return; }

  local names
  names=$(capture find -L "$dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -printf '%f\n' | sort)
  [[ -n $names ]] || { echo '{}'; return; }

  # The sizes are held to the read timeout and not the walk budget. This runs
  # on the page's poll, and a plugin is a few hundred kilobytes of QML with its
  # history behind it — a du that cannot answer in five seconds should leave
  # the column empty rather than hold the poll open behind it.
  #
  # `du -L` and not `du -x`: a plugin can be a symlink to a checkout elsewhere,
  # which is how anyone developing one has it, and the question is what the
  # plugin is rather than what this directory entry costs.
  local rows name bytes history manifest origin head pristine
  rows=$(
    while IFS= read -r name; do
      [[ -n $name ]] || continue
      bytes=$(capture du -sbL -- "$dir/$name" | cut -f1 | tr -dc '0-9')
      history=$(capture du -sbL -- "$dir/$name/.git" | cut -f1 | tr -dc '0-9')
      # Empty when the manifest is missing or is not JSON, which jq says by
      # printing nothing rather than by its exit status.
      manifest=$(capture jq -c '{ id: (.id // ""), version: (.version // ""),
                                  author: (.author // ""), license: (.license // ""),
                                  description: (.description // "") }' \
                   "$dir/$name/manifest.json")
      [[ -n $manifest ]] || manifest='{}'
      plugin_checkout "$dir/$name"
      jq -cn --arg name "$name" --argjson bytes "${bytes:-0}" --argjson history "${history:-0}" \
        --argjson manifest "$manifest" \
        --arg origin "$origin" --arg head "$head" --argjson pristine "$pristine" \
        '$manifest + { id: (if ($manifest.id // "") != "" then $manifest.id else $name end),
                       bytes: $bytes, gitBytes: $history,
                       origin: $origin, head: $head, pristine: $pristine }' 2>/dev/null
    done <<<"$names"
  )

  emit_json "$(jq -c -s '
    group_by(.id)
    | map({ key: .[0].id,
            value: (if length == 1 then .[0] + { contested: false }
                    else .[0] + { contested: true, origin: "", head: "", pristine: false,
                                  bytes: (map(.bytes) | add) } end) })
    | from_entries' <<<"$rows" 2>/dev/null)" '{}'
}

# ------------------------------------------------ what the marketplace says
#
# A plugin is someone else's code running inside the shell, and the two
# questions that raises — who wrote this, and has anyone looked at it — cannot
# be answered on the machine. They are answered at plugins.omarchy.org, whose
# catalogue is a static document, and by the engagement API behind it, which
# holds the hearts.
#
# Both are the network, so neither is ever on a poll: the page asks at most
# once a day, says when it last asked, and shows the previous answer until
# then. Same shape as the package check, for the same reason.
#
# The catalogue is nine megabytes describing three and a half thousand
# plugins, of which a machine has twenty. It is asked for compressed, streamed
# through jq and reduced to those twenty before any of it is kept, so what
# lands in the cache is a few hundred bytes a plugin.
#
# **The id finds the listing; the copy has to earn it.** A listing is a
# repository, and a verification is one commit of it. A fork that kept the id,
# or a copy edited where it sits, shares the id and none of what was
# reviewed. So `plugins_report` gives a copy its listing only when it was
# cloned from the listed repository, and the badge only when it is at the
# verified commit with its files unchanged (`plugin_checkout`). Handing
# someone else's verification to code nobody looked at is the one mistake a
# badge like this must not make.
PLUGIN_DIRECTORY_CACHE="${OMACONTROL_PLUGIN_DIRECTORY:-${XDG_CACHE_HOME:-$HOME_DIR/.cache}/omarchy/omacontrol/plugin-directory.json}"
PLUGIN_CATALOG_URL="${OMACONTROL_PLUGIN_CATALOG_URL:-https://plugins.omarchy.org/catalog.json}"
PLUGIN_STATS_URL="${OMACONTROL_PLUGIN_STATS_URL:-https://api.omarchyplugins.com/v1/stats}"
# A day, for the same reason the package check uses one: long enough that
# opening the page ten times in an afternoon is ten local reads and no
# network, short enough that a verification badge is never a week old.
PLUGIN_DIRECTORY_AUTO_AGE=${OMACONTROL_PLUGIN_DIRECTORY_AUTO_AGE:-86400}
PLUGIN_DIRECTORY_TIMEOUT=${OMACONTROL_PLUGIN_DIRECTORY_TIMEOUT:-45}
# Generous on purpose. The ceiling is here to stop a redirect to something
# enormous, not to police the catalogue's growth — past it the read is
# truncated, jq refuses the fragment, and the last good answer stands.
PLUGIN_CATALOG_MAX=${OMACONTROL_PLUGIN_CATALOG_MAX:-67108864}
PLUGIN_STATS_MAX=${OMACONTROL_PLUGIN_STATS_MAX:-8388608}
# A request that does not say what it is gives the other end no way to ask it
# to stop. The same one the news reader sends.
PLUGIN_DIRECTORY_AGENT="omacontrol (+https://github.com/twiking/omacontrol)"

plugin_directory_cached() {
  emit_json "$(read_file "$PLUGIN_DIRECTORY_CACHE" \
    | jq -c '{ checkedAt: (.checkedAt // 0), ids: (.ids // []), plugins: (.plugins // {}) }' \
      2>/dev/null)" '{"checkedAt":0,"ids":[],"plugins":{}}'
}

# A fresh random sibling renamed into place, like the update cache beside it:
# the path is as predictable as any other, so a name planted there is replaced
# rather than written through.
write_directory_cache() {
  local tmp
  mkdir -p "$(dirname "$PLUGIN_DIRECTORY_CACHE")" || return 1
  tmp=$(mktemp "$PLUGIN_DIRECTORY_CACHE.XXXXXX") || return 1
  cat >"$tmp" || { rm -f "$tmp"; return 1; }
  [[ -s $tmp ]] || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$PLUGIN_DIRECTORY_CACHE"
}

plugin_directory_refresh() {
  local ids listed stats merged
  ids=$(plugins_state | jq -c '[ .[] | .id ]' 2>/dev/null)
  [[ -n $ids ]] || ids='[]'

  listed=$(curl --compressed -sS -L --max-time "$PLUGIN_DIRECTORY_TIMEOUT" \
      -A "$PLUGIN_DIRECTORY_AGENT" "$PLUGIN_CATALOG_URL" 2>/dev/null \
    | head -c "$PLUGIN_CATALOG_MAX" \
    | jq -c --argjson ids "$ids" '
        ($ids | map({ key: ., value: true }) | from_entries) as $want
        | [ .plugins[]
            | select($want[.id] == true)
            | { key: .id,
                value: { author: (.author // ""),
                         version: (.version // ""),
                         category: (.category // ""),
                         license: (.license // ""),
                         # The catalogue'"'"'s own word for whether the plugin
                         # still installs: "Available", "Manual setup",
                         # "Compatibility failed".
                         status: (.status // ""),
                         stars: (.stars // 0),
                         repo: (.repo // ""),
                         verified: (.verificationStatus == "verified"),
                         commit: (.verificationCommit // ""),
                         verifiedAt: (.verificationCheckedAt // "") } } ]
        | from_entries' 2>/dev/null)

  # A catalogue that did not arrive, or arrived as something other than a
  # catalogue, is not an answer. The previous one stands rather than every
  # plugin on the page suddenly reporting itself unlisted.
  [[ -n $listed ]] || { plugin_directory_cached; return; }

  stats=$(curl --compressed -sS -L --max-time "$PLUGIN_DIRECTORY_TIMEOUT" \
      -A "$PLUGIN_DIRECTORY_AGENT" "$PLUGIN_STATS_URL" 2>/dev/null \
    | head -c "$PLUGIN_STATS_MAX" \
    | jq -c --argjson ids "$ids" '
        ($ids | map({ key: ., value: true }) | from_entries) as $want
        | (.plugins // {})
        | with_entries(select($want[.key] == true))
        | with_entries(.value = { hearts: (.value.hearts // 0),
                                  views: (.value.views // 0),
                                  copies: (.value.copies // 0) })' 2>/dev/null)
  # The hearts are the softer half of this: a catalogue entry without them is
  # still worth keeping, so a stats request that failed costs the counts and
  # not the badge.
  [[ -n $stats ]] || stats='{}'

  # `ids` records which plugins this check actually asked about. Without it a
  # plugin installed since cannot be told from one the catalogue does not have.
  merged=$(jq -cn --argjson listed "$listed" --argjson stats "$stats" \
    --argjson ids "$ids" --argjson at "$(date +%s)" '
      { checkedAt: $at,
        ids: $ids,
        plugins: ($listed | with_entries(.value += ($stats[.key] // {}))) }' 2>/dev/null)
  [[ -n $merged ]] || { plugin_directory_cached; return; }

  printf '%s\n' "$merged" | write_directory_cache
  printf '%s' "$merged"
}

# Asked on open, and free to ask: the age is compared here rather than in the
# page, so the page may ask as often as it likes and only a check that is
# actually owed costs a request. The same shape as `packages fetch` and
# `news fetch`, for the same reason.
#
# Coverage counts as well as age. A plugin installed since the last check was
# never looked up, and the page would otherwise call it unlisted for a day —
# which is exactly the moment someone wants to know whether what they have
# just installed is verified.
plugin_directory_fetch() {
  local cached ids at missing
  cached=$(plugin_directory_cached)
  ids=$(plugins_state | jq -c '[ .[] | .id ]' 2>/dev/null)
  [[ -n $ids ]] || ids='[]'

  at=$(jq -r '.checkedAt // 0' <<<"$cached" 2>/dev/null)
  # `$known | index(.)` would be the trap CLAUDE.md names: past the pipe the
  # `.` is `$known`, so the array is asked to find *itself*, every answer is
  # null, and nothing is ever missing. Bound first, it asks the question it
  # looks like it is asking.
  #
  # An entry without the verified commit was cached before the badge needed
  # one, and it would take every badge away for up to a day; it counts as
  # missing too.
  missing=$(jq -r --argjson ids "$ids" \
    '(.ids // []) as $known
     | ([ $ids[] | . as $id | select(($known | index($id)) == null) ] | length)
       + ([ (.plugins // {})[] | select(has("commit") | not) ] | length)' \
    <<<"$cached" 2>/dev/null)

  if (( $(date +%s) - ${at:-0} > PLUGIN_DIRECTORY_AUTO_AGE )) || (( ${missing:-0} > 0 )); then
    plugin_directory_refresh
  else
    printf '%s' "$cached"
  fi
}

# The plugin's own repository, looked up here rather than handed in: the window
# never passes a URL to be opened, so there is nothing to point elsewhere. The
# address is a stranger's listing either way, so http and https are opened and
# nothing else is.
plugin_site() {
  local id=$1 url
  url=$(plugin_directory_cached | jq -r --arg id "$id" '.plugins[$id].repo // ""' 2>/dev/null)
  [[ $url == http://* || $url == https://* ]] || die "no page listed for $id"
  setsid -f xdg-open "$url" >/dev/null 2>&1
}

# ------------------------------------------------------------- the page
#
# Everything the Plugins page shows, in one read.
#
# The page reports as much as it configures, so this is not in the state
# document: what every plugin declares, what each occupies and what the
# marketplace says are questions for the page on screen, and a state read
# happens after every write anywhere in the window. `plugins` stays in the
# document because the Bar page needs the widget ids, and that is all it needs.
plugins_report() {
  par_begin || { echo '{}'; return; }
  par_run list plugins_state
  par_run mine plugin_local
  par_wait
  local list mine directory
  list=$(par_get list '[]')
  mine=$(par_get mine '{}')
  par_end

  # Off the cache, never fetched here: this runs on the page's poll.
  directory=$(plugin_directory_cached)

  # A remote spelled as https, as ssh, with or without `.git`, is still one
  # repository; GitHub does not care about case in either half of the name.
  emit_json "$(jq -cn --argjson list "${list:-[]}" --argjson mine "${mine:-{\}}" \
    --argjson directory "${directory:-{\}}" '
      def repository:
        ascii_downcase
        | if test("^[a-z][a-z0-9+.-]*://")
          then sub("^[a-z][a-z0-9+.-]*://(?:[^@/]*@)?(?<host>[^/:]+)(?::[0-9]*)?"; "\(.host)")
          else sub("^(?:[^@/]*@)?(?<host>[^/:]+):"; "\(.host)/") end
        | sub("/+$"; "") | sub("\\.git$"; "");
      ($directory.plugins // {}) as $listing
      | ($directory.ids // []) as $covered
      | [ $list[]
          | . as $p
          | ($mine[$p.id] // {}) as $own
          | ($listing[$p.id] // null) as $candidate
          # Both sides have to name a repository before they can be compared.
          | (($own.origin // "") != "" and ($candidate.repo // "") != "") as $matchable
          # Omarchy ships its own plugins and reserves their namespace, so
          # for those the id is the whole answer. Anyone else has to have
          # been cloned from the repository the listing names.
          | ($candidate != null
             and ($p.firstParty == true
                  or ($matchable and ($own.contested // false | not)
                      and ($own.origin | repository) == ($candidate.repo | repository))))
            as $same
          | (if $same then $candidate else null end) as $entry
          # A verification that does not say which commit it covers cannot be
          # held against any copy.
          | (($entry.verified // false) and ($entry.commit // "") != "") as $reviewed
          | (if $own | has("pristine") then $own.pristine else null end) as $pristine
          | $p + { version: ($own.version // ""),
                   # The manifest first and the listing second: the listing is
                   # what was submitted, the manifest is what is installed.
                   author: (if ($own.author // "") != "" then $own.author
                            else ($entry.author // "") end),
                   license: (if ($own.license // "") != "" then $own.license
                             else ($entry.license // "") end),
                   description: (if ($own.description // "") != "" then $own.description
                                 else ($p.description // "") end),
                   bytes: ($own.bytes // 0),
                   gitBytes: ($own.gitBytes // 0),
                   listed: ($entry != null),
                   # Only a plugin the last check asked about can be said to be
                   # missing from the catalogue. One installed since was never
                   # looked up, and calling it unlisted would be inventing an
                   # answer nobody went and got.
                   looked: (($covered | index($p.id)) != null),
                   # The id is listed, but from a repository this copy did not
                   # come from, or one of the two cannot be named, or two
                   # copies here claim it.
                   elsewhere: ($candidate != null and ($same | not)),
                   elsewhereReviewed: ($candidate != null and ($same | not)
                                       and ($candidate.verified // false)),
                   contested: ($own.contested // false),
                   matchable: $matchable,
                   origin: ($own.origin // ""),
                   # What was reviewed, and whether this copy is it. A built-in
                   # has no checkout to compare: it is the package Omarchy
                   # installed, so the listing speaks for it.
                   reviewed: $reviewed,
                   reviewedCommit: (if $reviewed then $entry.commit else "" end),
                   head: ($own.head // ""),
                   pristine: $pristine,
                   verified: ($reviewed
                              and ($p.firstParty == true
                                   or (($own.head // "") == $entry.commit and $pristine == true))),
                   verifiedAt: ($entry.verifiedAt // ""),
                   status: ($entry.status // ""),
                   category: ($entry.category // ""),
                   repo: ($entry.repo // ""),
                   # Null and not zero: a plugin nobody has hearted and one
                   # nobody has looked up are different answers, and a column
                   # of zeroes says the second when it means the first.
                   hearts: ($entry.hearts // null),
                   views: ($entry.views // null),
                   copies: ($entry.copies // null),
                   stars: ($entry.stars // null) } ] as $items
      | { items: $items,
          diskBytes: ([ $items[] | .bytes ] | add // 0),
          installed: ($items | length),
          on: ([ $items[] | select(.enabled == true) ] | length),
          directoryAt: ($directory.checkedAt // 0) }')" '{}'
}
