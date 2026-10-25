# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# Carrying an OmaSettings install over, from inside the window. The work is
# bin/omacontrol-migrate's; this decides when to offer it and runs it where the
# window cannot kill it.

OMASETTINGS_STORE_PATH="$(dirname "$STORE")/omasettings.json"
OMASETTINGS_LUA_PATH="$HYPR_DIR/omasettings.lua"
MIGRATE_SCRIPT="$(dirname "$OMACONTROL_BIN")/omacontrol-migrate"
# In the state directory beside the rollbacks, not the cache: a cache
# directory made for a log is one the migration then cannot move the old
# cache into.
MIGRATE_LOG="$HOME_DIR/.local/state/omacontrol/migrate.log"
MIGRATE_LAST="$HOME_DIR/.local/state/omacontrol/migrate-last.json"

# Offered only while there is something to bring and nothing it would land on,
# and not while a run is under way. Once a setting has been changed in
# OmaControl the script refuses without --force, and a button that can only
# fail is worse than no button: that case is the README's, by hand. The script
# answers, so the two cannot disagree.
#
# A run that failed leaves the offer up with what went wrong under it, since
# from the window a failure would otherwise look like a button that did
# nothing.
migrate_pending() {
  [[ -e $OMASETTINGS_STORE_PATH || -e $OMASETTINGS_LUA_PATH ]] || { echo 'null'; return; }
  bash "$MIGRATE_SCRIPT" --pending || { echo 'null'; return; }
  local last='null'
  [[ -f $MIGRATE_LAST ]] && last=$(jq -c 'if type == "object" then . else null end' "$MIGRATE_LAST" 2>/dev/null)
  # The notice strings are resolved here, not spliced into the filter: the
  # filter below stays one single-quoted program, and a splice on one line of a
  # multi-line program is a quote that can trip on the next line's.
  jq -cn --argjson last "${last:-null}" \
    --arg title "$(jq -rn "$(i18n_t migrate.title 'Your settings from OmaSettings have not come across')")" \
    --arg stopped "$(jq -rn --argjson last "${last:-null}" "$(i18n_fill migrate.stopped 'The last try stopped: %1' '$last.message')")" \
    --arg pending "$(jq -rn "$(i18n_t migrate.pending 'Until they do, this window cannot mark them as changed or put back what they replaced. It may close for a moment while they move.')")" \
    --arg action "$(jq -rn "$(i18n_t migrate.action 'Bring them over')")" '
    { kind: "migrate",
      id: "migrate-omasettings",
      urgent: ($last != null and $last.ok == false),
      title: $title,
      note: (if $last != null and $last.ok == false then $stopped else $pending end),
      migrate: true,
      actionLabel: $action }'
}

migrate_cmd() {
  local action=${1:-check}
  case $action in
    check) bash "$MIGRATE_SCRIPT" ;;
    apply) shift; bash "$MIGRATE_SCRIPT" --apply "$@" ;;
    # Detached, because the migration rewrites shell.json, and the shell may
    # answer by reloading its plugins — this window among them — part-way
    # through. Whether to come back is decided now, while there is still a
    # window to ask.
    start)
      local reopen=0
      window_open && reopen=1
      setsid bash "$OMACONTROL_BIN" migrate run "$reopen" >/dev/null 2>&1 &
      disown 2>/dev/null || true ;;
    run)
      local reopen=${2:-0} status message
      mkdir -p "$(dirname "$MIGRATE_LOG")"
      bash "$MIGRATE_SCRIPT" --apply >"$MIGRATE_LOG" 2>&1
      status=$?
      # The script's first complaint is the reason; it leads with its own
      # name, which the notice does not need.
      message=$(grep -m1 '^omacontrol-migrate: ' "$MIGRATE_LOG" | sed 's/^omacontrol-migrate: //')
      jq -cn --argjson ok "$([[ $status -eq 0 ]] && echo true || echo false)" \
        --arg message "${message:-it exited with $status}" --argjson at "$(date +%s)" \
        '{ ok: $ok, message: $message, at: $at }' >"$MIGRATE_LAST"
      (( reopen == 1 )) && reopen_window overview ;;
    *) die "usage: omacontrol migrate check|apply|start|run" ;;
  esac
}
