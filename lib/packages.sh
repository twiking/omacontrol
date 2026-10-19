# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# What pacman has, what it is costing, and what it is waiting to do. Read-only
# apart from the housekeeping the page offers, each of which is handed to the
# tool that owns it rather than reimplemented.
#
# The split that matters here is cheap-vs-network. What is installed, how much
# room it takes and why each package is here is one read of the local database
# and costs nothing. Knowing what is *available* means a database sync, which
# is a network round trip — so it is cached, stamped, and never made because
# someone opened a page. That is what "mirrors last checked 2 h ago" is saying.

PACKAGES_CACHE="${OMACONTROL_PACKAGES_CACHE:-${XDG_CACHE_HOME:-$HOME_DIR/.cache}/omarchy/omacontrol/updates.json}"
PACKAGES_MAX_AGE=${OMACONTROL_PACKAGES_MAX_AGE:-3600}
# How long a check may stand before the page makes one itself. A day, because
# that is how often a rolling distribution is worth asking about unprompted:
# short enough that "nothing waiting" is never a week old, long enough that
# opening the page ten times in an afternoon is still ten local reads and no
# network at all.
PACKAGES_AUTO_AGE=${OMACONTROL_PACKAGES_AUTO_AGE:-86400}

# -------------------------------------------------------------- what is here
#
# Every installed package with its size and why it is here, from one read.
#
# expac asks the same local database `pacman -Qq` does and answers for all
# 1339 packages in twenty milliseconds — so the counts, the total on disk and
# the list of the biggest all come off a single call rather than a
# `pacman -Qq | wc -l` each. The sizes are what was missing: a machine is 1339
# packages *and* 20 GB, and nothing anywhere said the second number.
packages_inventory() {
  par_begin || { echo '{}'; return; }
  par_run rows packages_rows
  par_run orphans pacman_names -Qqdt
  par_run kernels packages_kernels
  par_wait
  local rows orphans kernels
  rows=$(par_get rows '')
  orphans=$(par_get orphans '[]')
  kernels=$(par_get kernels '[]')
  par_end

  emit_json "$(jq -Rc -s --argjson orphans "${orphans:-[]}" \
    --argjson kernels "${kernels:-[]}" '''
    [ split("\n")[] | select(length > 0) | split("\t")
      | { bytes: (.[0] | tonumber? // 0), name: .[2] } ] as $all
    | { installed: ($all | length),
        orphans: ($orphans | length),
        kernels: $kernels,
        # Which package *is* Omarchy, answered the way omarchy-update-available
        # answers it: the dev package where that is what is installed, and the
        # released one otherwise. Free here — the whole inventory is already in
        # hand — where asking pacman again would be a second read to learn a
        # name this list already knows.
        omarchyPackage: (if ($all | map(.name) | index("omarchy-dev"))
                         then "omarchy-dev" else "omarchy" end),
        # Zero without expac, and the page reads that as "no sizes are known"
        # rather than as an empty disk: a column of "0 B" answers "what is
        # taking the room" wrongly instead of declining to answer.
        diskBytes: ([ $all[] | .bytes ] | add // 0) }''' \
    <<<"$rows")" '{}'
}

# Size, install reason and name for every installed package. Without expac
# there are no sizes at all, so the counts still come off pacman and the page
# simply has nothing to show for the space.
packages_rows() {
  if command -v expac >/dev/null 2>&1; then
    capture expac -Q '%m\t%w\t%n\t%v'
  else
    capture pacman -Qq | awk '{ printf "0\tunknown\t%s\t\n", $1 }'
  fi
}

# ------------------------------------------------------------- all of them
#
# Every installed package, with what it costs, why it is here, what version is
# on the disk and which repository put it there.
#
# Its own subcommand rather than part of the poll, for the reason the Disk
# breakdown is: this is 1339 rows and a sync read, wanted once when the page
# opens, and nothing about it changes between two ticks of a ten-second timer.
# The counts and the pending list stay on the poll, where they are cheap.
packages_all() {
  par_begin || { echo '[]'; return; }
  par_run rows packages_rows
  par_run foreign pacman_names -Qqm
  # The whole sync side in one read, and no names passed: asked for all 1339
  # by name it takes 0.3 s, asked for everything it takes 0.13 s and the
  # answer is looked up here. A package's own local record is no use — it
  # calls every repository "local".
  par_run repos packages_sync_repos
  par_wait
  local rows foreign repos
  rows=$(par_get rows '')
  foreign=$(par_get foreign '[]')
  repos=$(par_get repos '')
  par_end

  # The two sides are joined in awk and not in jq: the sync list is 15660 lines
  # and handing it to `--argjson` is one argument longer than the kernel allows
  # for one, which fails as "Argument list too long" rather than as anything
  # about a package.
  emit_json "$(awk -F'\t' -v OFS='\t' '
      NR == FNR { repo[$1] = $2; next }
      { print $1, $2, $3, $4, ($3 in repo ? repo[$3] : "") }' \
      <(printf '%s\n' "$repos") <(printf '%s\n' "$rows") \
    | jq -Rc -s --argjson foreign "${foreign:-[]}" '''
      [ split("\n")[] | select(length > 0) | split("\t")
        | { bytes: (.[0] | tonumber? // 0), reason: .[1], name: .[2],
            version: (.[3] // ""),
            repo: (if (.[4] // "") == "" then null else .[4] end) }
        # Bound before `index`, or the array is asked for its own .name and
        # every row comes back foreign.
        | . as $p
        | $p + { foreign: ($foreign | index($p.name) != null) } ]''')" '[]'
}

# Every package the sync databases know and where it lives, as the two columns
# it is about to be joined on.
packages_sync_repos() {
  command -v expac >/dev/null 2>&1 || return 0
  capture expac -S '%n\t%r'
}

# Which installed packages are kernels, asked the way omarchy-update-restart
# asks it: a kernel is a vmlinuz under /usr/lib/modules that pacman put there.
# Going by the name instead calls linux-firmware and linux-headers kernels —
# both update constantly and neither changes what boots — and misses
# linux-omarchy, which does.
packages_kernels() {
  local images=(/usr/lib/modules/*/vmlinuz)
  [[ -e ${images[0]} ]] || { echo '[]'; return; }
  # An unowned image is an error on stderr and a non-zero exit with the owned
  # ones still printed, so the value decides and the status is not consulted.
  emit_json "$(capture pacman -Qqo "${images[@]}" \
    | jq -Rc -s '[ split("\n")[] | select(length > 0) ] | unique')" '[]'
}

pacman_names() {
  emit_json "$(capture pacman "$@" \
    | jq -Rc -s '[ split("\n")[] | select(length > 0) ]')" '[]'
}

# ---------------------------------------------------------------- what is due
#
# `checkupdates` syncs a temporary database rather than the system one, which
# is the only safe way to ask this question without a lock — but it is still a
# sync, so it happens on request and the answer is kept.
packages_pending_cached() {
  [[ -f $PACKAGES_CACHE ]] || { echo '{}'; return; }
  emit_json "$(read_file "$PACKAGES_CACHE")" '{}'
}

packages_stale() {
  [[ ! -f $PACKAGES_CACHE ]] && return 0
  local at
  at=$(packages_pending_cached | jq -r '.checkedAt // 0' 2>/dev/null)
  (( $(date +%s) - ${at:-0} > PACKAGES_MAX_AGE ))
}

# Asked on open, and free to ask: the age is compared here rather than in the
# page, so the page may ask as often as it likes and only a check that is
# actually owed costs a sync. The same shape as `news fetch`, for the same
# reason.
packages_fetch() {
  local at
  at=$(packages_pending_cached | jq -r '.checkedAt // 0' 2>/dev/null)
  if (( $(date +%s) - ${at:-0} > PACKAGES_AUTO_AGE )); then
    packages_refresh
  else
    packages_pending_cached
  fi
}

packages_refresh() {
  command -v checkupdates >/dev/null 2>&1 || { echo '{}'; return; }
  local repo aur
  # A longer bound than the other readers get: these are network syncs, and
  # five seconds is not enough for a mirror on a bad day.
  repo=$(timeout 60 checkupdates --nocolor 2>/dev/null | head -c "$OMACONTROL_READ_MAX")
  aur=$(packages_aur_pending)

  local items
  # `pkg old -> new` from both, which is the one format they agree on.
  items=$(printf '%s\n%s\n' "$repo" "$aur" \
    | awk 'NF >= 4 && $2 != "" && $3 == "->" {
        printf "%s\t%s\t%s\n", $1, $2, $4
      }' | jq -Rc -s '
      [ split("\n")[] | select(length > 0) | split("\t")
        | { name: .[0], installed: .[1], available: .[2] } ]
      | unique_by(.name)')

  # Which of them came from the AUR, so the page can label and filter them.
  # Asked of the local database, which already knows.
  local foreign explicit sizes
  foreign=$(capture pacman -Qqm | jq -Rc -s '[ split("\n")[] | select(length > 0) ]')
  explicit=$(capture pacman -Qqe | jq -Rc -s '[ split("\n")[] | select(length > 0) ]')
  # What each one costs to fetch. One sync database query for the whole list —
  # 184 packages in a sixth of a second — so there is no reason for the page
  # to show a count of updates without their weight. AUR packages are built
  # rather than downloaded, so the repositories are the only ones with an
  # answer here.
  sizes=$(packages_sizes "$items")

  local next
  next=$(jq -cn --argjson items "${items:-[]}" --argjson foreign "${foreign:-[]}" \
    --argjson explicit "${explicit:-[]}" --argjson sizes "${sizes:-{\}}" \
    --argjson at "$(date +%s)" '''
    { checkedAt: $at,
      # Bound first. Inside `index(...)` the `.` is the list being searched,
      # not the row — so `index(.name)` asks the array for its own .name,
      # which is null, and every row comes back the same. The trap is in
      # CLAUDE.md and it still caught this one.
      items: [ $items[] | . as $row
               | $row + { foreign: ($foreign | index($row.name) != null),
                          explicit: ($explicit | index($row.name) != null),
                          bytes: ($sizes[$row.name].bytes // null),
                          repo: ($sizes[$row.name].repo // null) } ] }''')
  mkdir -p "$(dirname "$PACKAGES_CACHE")"
  printf '%s\n' "$next" >"$PACKAGES_CACHE" 2>/dev/null
  printf '%s' "$next"
}

# Download size and repository per package, keyed by name. expac asks the sync
# database in one call and answers in bytes, which is what the window formats;
# `pacman -Si` would answer in MiB strings that then have to be parsed back.
#
# The repository has to come from the *sync* side: a package's own local record
# says only "local", whoever shipped it.
packages_sizes() {
  local names
  names=$(jq -r '[ .[] | select(.foreign != true) | .name ] | join(" ")' <<<"${1:-[]}" 2>/dev/null)
  [[ -n ${names// /} ]] || { echo '{}'; return; }
  command -v expac >/dev/null 2>&1 || { echo '{}'; return; }

  emit_json "$(capture expac -S '%n\t%k\t%r' $names \
    | jq -Rc -s '[ split("\n")[] | select(length > 0) | split("\t")
                   | { key: .[0], value: { bytes: (.[1] | tonumber? // null),
                                           repo: .[2] } } ] | from_entries')" '{}'
}

# checkupdates is repositories only — it has no idea the AUR exists — so an
# AUR-heavy machine would be told it was up to date while a dozen packages
# waited. yay answers for those, behind the same reachability test Omarchy's
# own updater uses: the AUR is frequently down, and a page should not stall on
# it or report "nothing waiting" when it simply could not ask.
packages_aur_pending() {
  command -v yay >/dev/null 2>&1 || return 0
  capture pacman -Qqm >/dev/null 2>&1 || return 0
  omarchy-pkg-aur-accessible >/dev/null 2>&1 || return 0
  timeout 60 yay -Qua 2>/dev/null | head -c "$OMACONTROL_READ_MAX"
}

# ---------------------------------------------------------------- housekeeping
#
# The four questions worth asking of a machine that has been updating itself
# for a year: what is the cache holding, what is installed that nothing needs,
# what came from outside a repository, and what config changes are waiting.
packages_housekeeping() {
  par_begin || { echo '{}'; return; }
  par_run cache du_bytes /var/cache/pacman/pkg
  par_run pacnew packages_pacnew
  par_wait
  local cache pacnew
  cache=$(par_get cache null)
  pacnew=$(par_get pacnew 0)
  par_end

  jq -cn --argjson cache "${cache:-null}" --argjson pacnew "${pacnew:-0}" \
    '{ cacheBytes: $cache, pacnew: $pacnew }'
}

# A .pacnew is a config pacman would have overwritten and did not. They are
# easy to accumulate and silent about it, which is exactly what a page like
# this is for.
packages_pacnew() {
  local n
  n=$(capture find /etc -maxdepth 3 -name '*.pacnew' | wc -l)
  printf '%s' "${n:-0}"
}

# What pacman did, in the words it used itself. Read from its log rather than
# reconstructed: the log is the record, and summarising a day of upgrades as
# "upgraded 118 packages" is the only transformation applied.
packages_history() {
  local log=/var/log/pacman.log
  [[ -r $log ]] || { echo '[]'; return; }

  emit_json "$(capture tail -c 400000 "$log" \
    | awk '
      # [2026-08-31T18:16:02+0200] [ALPM] upgraded linux (7.1.8-1 -> 7.1.9-1)
      match($0, /^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}/) {
        stamp = substr($0, 2, 16)
        if ($0 ~ /\[ALPM\] (upgraded|installed|removed|downgraded) /) {
          verb = $3; sub(/^\[ALPM\]$/, "", verb)
          for (i = 1; i <= NF; i++)
            if ($i == "upgraded" || $i == "installed" || $i == "removed" || $i == "downgraded") {
              verb = $i; name = $(i + 1); break
            }
          # One line per transaction, not per package: a system upgrade is one
          # thing the reader did, not a hundred and eighteen.
          key = stamp "\t" verb
          if (!(key in count)) { order[++n] = key; first[key] = name }
          count[key]++
        }
      }
      END {
        for (i = n; i >= 1 && i > n - 12; i--) {
          key = order[i]
          split(key, part, "\t")
          printf "%s\t%s\t%s\t%s\n", part[1], part[2], count[key], first[key]
        }
      }' \
    | jq -Rc -s '''
      [ split("\n")[] | select(length > 0) | split("\t")
        | { at: .[0], verb: .[1], count: (.[2] | tonumber? // 1), name: .[3] } ]''' 2>/dev/null)" '[]'
}

# When the machine was last brought up to date, as an instant rather than a
# date. "Four days ago" is what answers "am I behind"; a date is something the
# reader has to work out the answer from. Taken from the last package pacman
# actually upgraded, because that is the moment the machine changed — an
# update that found nothing to do did not bring anything up to date.
packages_last_update() {
  local log=/var/log/pacman.log stamp
  [[ -r $log ]] || { echo 0; return; }
  stamp=$(capture tail -c 400000 "$log" | grep -F '[ALPM] upgraded ' | tail -n1)
  [[ -n $stamp ]] || { echo 0; return; }
  # [2026-09-15T11:09:17+0200] — the offset is part of it, so date reads the
  # instant rather than guessing at the zone the log was written in.
  date -d "$(cut -c2-25 <<<"$stamp")" +%s 2>/dev/null || echo 0
}

packages_state() {
  par_begin || { echo '{}'; return; }
  par_run inventory packages_inventory
  par_run housekeeping packages_housekeeping
  par_run history packages_history
  par_run updated packages_last_update
  par_wait
  local inventory housekeeping history updated pending
  inventory=$(par_get inventory '{}')
  housekeeping=$(par_get housekeeping '{}')
  history=$(par_get history '[]')
  updated=$(par_get updated 0)
  par_end
  # Off the cache, never synced here: this runs on the page's poll.
  pending=$(packages_pending_cached)

  jq -cn \
    --argjson inventory "${inventory:-{\}}" \
    --argjson housekeeping "${housekeeping:-{\}}" \
    --argjson history "${history:-[]}" \
    --argjson updated "${updated:-0}" \
    --argjson pending "${pending:-{\}}" \
    '$inventory + $housekeeping + { history: $history,
                                    updatedAt: $updated,
                                    pending: ($pending.items // []),
                                    checkedAt: ($pending.checkedAt // 0) }'
}

# ------------------------------------------------------------- one of them
#
# Everything the drill-in shows, from one expac call, asked only when the
# reader opens a package. `pacman -Qi` answers the same questions in a
# paragraph of its own labels that would then have to be parsed back out of
# it — and it is the labels that would move, not the fields.
#
# The list separator is a space because package names cannot contain one, and
# the description goes last so that a stray tab in someone's package
# description runs off the end of its own field rather than shifting every
# field after it.
packages_info() {
  local name=${1:-}
  [[ -n $name ]] || { echo '{}'; return; }
  command -v expac >/dev/null 2>&1 || { echo '{}'; return; }

  local row
  row=$(capture expac -Q -l ' ' -t '%Y-%m-%d' \
    '%n\t%v\t%m\t%w\t%l\t%u\t%N\t%d' -- "$name" | head -n1)
  [[ -n $row ]] || { echo '{}'; return; }

  # Read first, tested second. `grep -q` stops at the first match, and under
  # `pipefail` the write it then refuses makes `… | grep -q` report a failure
  # — so `|| echo false` fires on a match. It passes on a machine with twenty
  # AUR packages and flips silently on one with three hundred, which is the
  # machine this module already caters for. The value decides, never the exit
  # status.
  local mine foreign=false
  mine=$(capture pacman -Qqm)
  grep -Fxq -- "$name" <<<"$mine" && foreign=true

  # The sync side again, for the same reason: %m, %w and the rest come off the
  # local record, which calls every repository "local".
  local repo
  repo=$(capture expac -S '%r' -- "$name" | head -n1)

  emit_json "$(jq -Rc --argjson foreign "$foreign" --arg repo "${repo:-}" '''
    split("\t") as $f
    | { name: $f[0], version: $f[1], bytes: ($f[2] | tonumber? // 0),
        reason: $f[3], installed: $f[4], url: $f[5],
        requiredBy: ($f[6] | split(" ") | map(select(length > 0))),
        description: ($f[7:] | join("\t")),
        repo: (if $repo == "" then null else $repo end),
        foreign: $foreign }''' <<<"$row")" '{}'
}

packages_cmd() {
  case ${1:-state} in
    state|poll) packages_state ;;
    list) packages_all ;;
    refresh) packages_refresh ;;
    fetch) packages_fetch ;;
    stale) packages_stale && echo true || echo false ;;
    info) shift; packages_info "${1:-}" ;;
    # Every one of these is a terminal job with a password prompt and a
    # confirmation, so it is handed to a terminal rather than run headless.
    # A settings window is not the place to be silently installing a kernel.
    #
    # `omarchy-update` in particular *must* have one. It re-execs itself under
    # `script` and then asks `gum confirm` whether to go ahead — detached, that
    # prompt is drawn into a pty nobody is attached to and waits for a keypress
    # that can never come, so the update hangs for ever holding the Omarchy
    # update lock and every later update is told one is already running. The
    # bar's own update widget and the Omarchy menu both launch it exactly this
    # way.
    # There is no snapshot button beside it, either: `omarchy-update` takes a
    # snapshot itself, deliberately after pruning the cache, since the cache
    # sits on the snapshotted subvolume and pruning afterwards frees nothing
    # until that snapshot ages out. One offered separately promised a safety
    # net that was already there and took a second, redundant snapshot for it.
    update) setsid -f omarchy-launch-floating-terminal-with-presentation \
      "omarchy-update" >/dev/null 2>&1 ;;
    clean) setsid -f omarchy-launch-floating-terminal-with-presentation \
      "omarchy-update-pkg-prune" >/dev/null 2>&1 ;;
    orphans) setsid -f omarchy-launch-floating-terminal-with-presentation \
      "omarchy-update-orphan-pkgs" >/dev/null 2>&1 ;;
    pacnew) setsid -f omarchy-launch-floating-terminal-with-presentation \
      "sudo DIFFPROG='nvim -d' pacdiff" >/dev/null 2>&1 ;;
    # `-Rns` and not `omarchy-pkg-drop`, which is `--noconfirm`: the terminal
    # is where pacman lists what else goes with it, and that list is the whole
    # reason this happens in front of the reader. Same call the Apps page makes
    # to uninstall an application.
    remove) shift
      [[ -n ${1:-} ]] || die "usage: omacontrol packages remove <name>"
      setsid -f omarchy-launch-floating-terminal-with-presentation \
        "sudo pacman -Rns $(printf '%q' "$1")" >/dev/null 2>&1 ;;
    # For the ones that are not in the list the page shows. Omarchy's own
    # picker, which previews each package as you move down it — and which
    # offers `yay -Qqe`, the packages that were asked for, rather than all
    # 1339: a dependency is not one to remove on its own, and the page's copy
    # has to promise what this actually opens.
    pick) setsid -f omarchy-launch-floating-terminal-with-presentation \
      "omarchy-pkg-remove" >/dev/null 2>&1 ;;
    # The project's own page, looked up here rather than handed in. The window
    # never passes a URL to be opened, so there is nothing to point elsewhere;
    # and a package's %u is whatever its PKGBUILD said, which on the AUR is a
    # stranger's file — so http and https are opened and nothing else is.
    site) shift
      [[ -n ${1:-} ]] || die "usage: omacontrol packages site <name>"
      local url
      url=$(capture expac -Q '%u' -- "$1" | head -n1)
      [[ $url == http://* || $url == https://* ]] || die "no web page for $1"
      setsid -f xdg-open "$url" >/dev/null 2>&1 ;;
    log) setsid -f omarchy-launch-tui "less +G /var/log/pacman.log" >/dev/null 2>&1 ;;
    *) die "usage: omacontrol packages poll|list|refresh|fetch|stale|info <name>|update|clean|orphans|pacnew|remove <name>|pick|site <name>|log" ;;
  esac
}
