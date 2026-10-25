# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# The Overview page: the handful of switches people reach for several times a
# day, the two things worth starting from here, and whatever needs attention.
#
# Every switch on this page is Omarchy's own — night light, do-not-disturb,
# staying awake, dictation each already have a command that owns the state and
# the side effects. This module asks them and relays the answer; it does not
# keep a copy of what it thinks is on. That is the difference between a page
# that agrees with the bar and one that drifts from it.

overview_toggles() {
  par_begin || { echo '[]'; return; }
  par_run nightlight overview_nightlight
  par_run dnd overview_dnd
  par_run awake overview_stay_awake
  par_run dictation overview_dictation
  par_wait

  local nightlight dnd awake dictation
  nightlight=$(par_get nightlight '{}')
  dnd=$(par_get dnd '{}')
  awake=$(par_get awake '{}')
  dictation=$(par_get dictation '{}')
  par_end

  jq -cn \
    --argjson nightlight "${nightlight:-{\}}" \
    --argjson dnd "${dnd:-{\}}" \
    --argjson awake "${awake:-{\}}" \
    --argjson dictation "${dictation:-{\}}" '''
    [ { id: "nightlight", label: '"$(i18n_t overview.toggle.nightlight 'Night light')"' } + $nightlight,
      { id: "dnd", label: '"$(i18n_t overview.toggle.dnd 'Do not disturb')"' } + $dnd,
      { id: "awake", label: '"$(i18n_t overview.toggle.awake 'Stay awake')"' } + $awake,
      { id: "dictation", label: '"$(i18n_t overview.toggle.dictation 'Dictation')"' } + $dictation ]
    # A switch for something that is not installed is a switch that cannot do
    # anything, so it is not offered.
    | map(select(.available != false))'''
}

overview_nightlight() {
  local status
  status=$(capture omarchy-toggle-nightlight --status)
  [[ -n $status ]] || { echo '{"available":false}'; return; }
  emit_json "$(jq -c '{ on: (.enabled == true),
           note: (if .enabled == true
                  then ((.temperature | tostring) + " K")
                  else '"$(i18n_t overview.toggle.off 'Off')"' end) }' <<<"$status" 2>/dev/null)" '{"available":false}'
}

overview_dnd() {
  local state
  # The shell owns do-not-disturb, so the shell is asked. There is no file to
  # read: notifications are held in the running process.
  state=$(capture omarchy-shell notifications dndState)
  case ${state:-} in
    on)  jq -cn '{"on":true,"note":'"$(i18n_t overview.toggle.dndOn 'Notifications held')"'}' ;;
    off) jq -cn '{"on":false,"note":'"$(i18n_t overview.toggle.dndOff 'Notifications shown')"'}' ;;
    *)   echo '{"available":false}' ;;
  esac
}

overview_stay_awake() {
  local status
  status=$(capture omarchy-toggle-idle --status)
  [[ -n $status ]] || { echo '{"available":false}'; return; }
  emit_json "$(jq -c '{ on: (.enabled == true),
           note: (if .enabled == true then '"$(i18n_t overview.toggle.awakeOn 'Idle inhibited')"'
                  else '"$(i18n_t overview.toggle.awakeOff 'Idles and locks normally')"' end) }' <<<"$status" 2>/dev/null)" \
    '{"available":false}'
}

# voxtype answers about itself in the same JSON the bar's indicator reads, so
# the switch shows what is actually happening rather than a guess: `class` is
# idle or recording, and `model` is the one thing that says whether it is set
# up at all.
#
# Installed is not the same as usable. A voxtype with no model will not
# transcribe anything, and a switch for it is a switch that cannot work — so
# that counts as unavailable and the row is not offered.
overview_dictation() {
  omarchy-cmd-present voxtype || { echo '{"available":false}'; return; }
  local status
  status=$(capture voxtype status --extended --format json)
  [[ -n $status ]] || { echo '{"available":false}'; return; }

  emit_json "$(jq -c '''
    if ((.model // "") == "") then { available: false }
    else { on: ((.class // "idle") == "recording"),
           note: (if (.class // "") == "recording" then '"$(i18n_t overview.toggle.recording 'Recording')"'
                  else '"$(i18n_fill overview.toggle.ready 'Ready · %1' '.model')"' end) }
    end''' <<<"$status" 2>/dev/null)" '{"available":false}'
}

# What the window would tell you if you had not asked. Only what the shell has
# to be asked for: the window already holds its own version and the monitor
# list, so the page derives those notices from state it has rather than paying
# to read them twice.
#
# Package updates are deliberately not here. Answering that is a network round
# trip — `checkupdates` syncs a database — and nothing in this window may wait
# on the network. Omarchy's own update indicator in the bar already says it.
overview_attention() {
  par_begin || { echo '[]'; return; }
  par_run boot overview_boot_space
  par_run peripherals overview_low_peripherals
  par_run migrate migrate_pending
  par_wait
  local boot peripherals migrate
  boot=$(par_get boot 'null')
  peripherals=$(par_get peripherals '[]')
  migrate=$(par_get migrate 'null')
  par_end

  jq -cn --argjson boot "${boot:-null}" --argjson peripherals "${peripherals:-[]}" \
    --argjson migrate "${migrate:-null}" \
    '[ $migrate, $boot ] + $peripherals | map(select(. != null))'
}

# A keyboard or mouse about to die is the one thing on this list the reader
# cannot find out any other way — a Bluetooth peripheral does not warn you, it
# just stops. upower knows, because BlueZ tells it.
#
# 10 % is the threshold, here and on the badge on the bar's gear, which reads
# this same list: one answer everywhere. Low enough that it never nags about a
# device with days left in it, and still minutes before it drops off
# mid-sentence.
OVERVIEW_PERIPHERAL_LOW=10
OVERVIEW_PERIPHERAL_KINDS='mouse|keyboard|headset|headphones|pen|touchpad'

overview_low_peripherals() {
  local devices
  devices=$(capture upower -e | grep -E "/($OVERVIEW_PERIPHERAL_KINDS)_")
  [[ -n ${devices:-} ]] || { echo '[]'; return; }

  local out=() device info model percent
  while read -r device; do
    [[ -n $device ]] || continue
    info=$(capture upower -i "$device")
    percent=$(awk '/percentage:/ { gsub(/%/, "", $2); print $2; exit }' <<<"$info")
    [[ -n ${percent:-} ]] || continue
    [[ ${percent%%.*} -lt $OVERVIEW_PERIPHERAL_LOW ]] 2>/dev/null || continue
    model=$(awk -F': +' '/model:/ { print $2; exit }' <<<"$info")
    [[ -n ${model:-} ]] || model=$(jq -rn "$(i18n_t overview.peripheral.unknown 'A Bluetooth device')")
    out+=("$(jq -cn --arg model "$model" --argjson percent "${percent%%.*}" \
      '{ kind: "peripheral",
         id: ("peripheral:" + $model),
         device: $model, percent: $percent,
         title: '"$(i18n_fill overview.peripheral.title '%1 is at %2 %' '$model' '$percent | tostring')"',
         note: '"$(i18n_t overview.peripheral.note 'Charge it before it drops off Bluetooth.')"',
         action: "bluetooth", actionLabel: '"$(i18n_t overview.peripheral.action 'Open Bluetooth')"'}')")
  done <<<"$devices"

  ((${#out[@]})) && printf '%s\n' "${out[@]}" | jq -cs '.' || echo '[]'
}

# ---------------------------------------------------------------- what is due
#
# Three sources, each already cached by whoever owns it: the package list this
# window keeps, the plugin-update cache the Plugins page reads, and Omarchy's
# own version. Nothing here syncs anything — the page shows what is known and
# says when it was last asked.
overview_updates() {
  local pending plugins version channel
  pending=$(packages_pending_cached)
  plugins=$(plugin_updates_cache)
  version=$(omarchy_version)
  channel=$(omarchy_channel)

  jq -cn \
    --argjson pending "${pending:-{\}}" \
    --argjson plugins "${plugins:-{\}}" \
    --arg version "$version" \
    --arg channel "$channel" '''
    ( [ $pending.items[]? ] ) as $items
    # Omarchy ships as a package like everything else, so its own row is that
    # package pulled out of the list and named properly.
    | ( $items | map(select(.name == "omarchy" or .name == "omarchy-dev")) | first ) as $omarchy
    | ( [ $plugins.results // {} | to_entries[] | select(.value > 0) | .key ] ) as $behind
    | { checkedAt: ($pending.checkedAt // 0),
        version: $version,
        channel: $channel,
        omarchy: (if $omarchy then { available: $omarchy.available } else null end),
        packages: ($items | length),
        plugins: $behind }'''
}

# /boot is small, and it is the one partition where running out stops the
# machine from booting the next kernel rather than merely inconveniencing
# someone. Below the threshold it is not mentioned at all.
overview_boot_space() {
  local line size used pct
  line=$(capture df -B1 --output=size,used,pcent /boot | tail -n1)
  read -r size used pct <<<"$line"
  [[ -n ${size:-} && ${size:-0} -gt 0 ]] || { echo 'null'; return; }
  pct=${pct%\%}
  (( ${pct:-0} >= 75 )) || { echo 'null'; return; }

  jq -cn --argjson pct "${pct:-0}" --argjson size "$size" --argjson used "$used" '''
    { kind: "boot",
      id: "boot",
      urgent: true,
      title: '"$(i18n_fill overview.boot.title '/boot is %1 % full' '$pct | tostring')"',
      note: '"$(i18n_t overview.boot.note 'A kernel update may not fit.')"',
      action: "disk", actionLabel: '"$(i18n_t overview.boot.action 'Open Disk')"'}'''
}

overview_state() {
  par_begin || { echo '{}'; return; }
  par_run toggles overview_toggles
  par_run attention overview_attention
  par_run updates overview_updates
  par_run news news_cached
  par_run dismissed overview_dismissed
  par_wait
  local toggles attention uptime updates news
  toggles=$(par_get toggles '[]')
  attention=$(par_get attention '[]')
  updates=$(par_get updates '{}')
  news=$(par_get news '{}')
  local dismissed
  dismissed=$(par_get dismissed '[]')
  par_end

  # Read here rather than taken off the Processes page: one line of /proc, and
  # the alternative was this page running two frames of `top` every half minute
  # to put a single figure in its header.
  uptime=$(cut -d. -f1 /proc/uptime 2>/dev/null)

  jq -cn \
    --argjson toggles "${toggles:-[]}" \
    --argjson attention "${attention:-[]}" \
    --argjson uptime "${uptime:-0}" \
    --argjson updates "${updates:-{\}}" \
    --argjson news "${news:-{\}}" \
    --argjson dismissed "${dismissed:-[]}" \
    '{ toggles: $toggles,
       attention: [ $attention[] | select((.id // "") as $id | $dismissed | index($id) == null) ],
       uptime: $uptime, updates: $updates, news: $news }'
}

# The three switches the bar's gear counts, from the same readers the page
# uses, so the badge and the page cannot disagree. Dictation is not one: it is
# on only while someone is speaking, and the bar has its own recording mark.
overview_switches() {
  local nightlight dnd awake
  nightlight=$(overview_nightlight)
  dnd=$(overview_dnd)
  awake=$(overview_stay_awake)
  jq -cn --argjson n "$(emit_json "$nightlight" '{}')" --argjson d "$(emit_json "$dnd" '{}')" \
    --argjson a "$(emit_json "$awake" '{}')" \
    '{ nightlight: ($n.on == true), dnd: ($d.on == true), awake: ($a.on == true) }'
}

# Whether this machine is on a network at all. NetworkManager's own state
# rather than the Wi-Fi radio's: a docked laptop on a cable has no Wi-Fi and is
# online, and saying otherwise would be a false alarm every day it is docked.
# Null when NetworkManager is not there to ask, which is not the same as
# offline.
overview_online() {
  command -v nmcli >/dev/null 2>&1 || { printf null; return; }
  local state
  state=$(capture nmcli -t -g STATE general)
  [[ -n $state ]] || { printf null; return; }
  [[ $state == connected* ]] && printf true || printf false
}

overview_compose() {
  local switches=$1 online=$2 low=$3
  jq -cn --argjson s "$(emit_json "$switches" '{}')" --argjson online "${online:-null}" \
    --argjson low "$(emit_json "$low" '[]')" \
    '$s + { online: $online, lowDevices: [ $low[] | { name: .device, percent } ] }'
}

# The switches and the connection as they change, one line each time, for as
# long as the bar is up. Plugins other than a whole bar are not given
# Omarchy's services, so the gear cannot bind to them the way the bar's own
# indicators do.
#
# This runs for as long as the bar does, so each part is asked only when
# something says it moved, and on its own clock otherwise. A read of all of it
# is some fifty processes, and asking everything whenever anything stirred
# once kept the load near 7 on a laptop.
#
# Stay awake and do not disturb are files under Omarchy's state directory, and
# NetworkManager reports its own changes, so those are asked at once and never
# on a clock. Night light is a temperature held by hyprsunset with no file
# behind it, so the switches are asked again every minute: a badge that is a
# minute late about a choice the reader made costs nothing.
#
# UPower signals a Bluetooth device's battery moving, but it also signals the
# laptop's own battery and its DisplayDevice roughly every second, plugged in
# or not, mostly nothing but UpdateTime. Nothing here reads that battery, so
# only the kinds lowDevices lists are acted on. The peripherals are asked again
# every five minutes besides, in case a signal was missed.
OVERVIEW_SWITCHES_RECHECK=60
OVERVIEW_PERIPHERALS_RECHECK=300

overview_watch() {
  local state="$HOME_DIR/.local/state/omarchy" last next line rc wait_for
  local switches online low switches_at=$SECONDS low_at=$SECONDS
  local want_switches=0 want_online=0 want_low=0
  mkdir -p "$state/indicators" 2>/dev/null
  switches=$(overview_switches)
  online=$(overview_online)
  low=$(overview_low_peripherals)
  last=$(overview_compose "$switches" "$online" "$low")
  printf '%s\n' "$last"

  # Sets a flag rather than printing one, so a wake that wants nothing costs
  # no process at all.
  overview_wanted_by() {
    case $1 in
      # The state directory is shared with the clipboard history and a dozen
      # others, so only these two names are worth a read.
      file:stay-awake|file:notifications.json) want_switches=1 ;;
      file:*) ;;
      /org/freedesktop/UPower/devices/*)
        [[ $1 =~ ^/org/freedesktop/UPower/devices/($OVERVIEW_PERIPHERAL_KINDS)_ ]] \
          && want_low=1 ;;
      # A device arriving or leaving.
      /org/freedesktop/UPower:*) want_low=1 ;;
      # gdbus announcing itself; the first read has already been done.
      "Monitoring signals"*|"The name org.freedesktop.UPower"*) ;;
      *) want_online=1 ;;
    esac
  }

  local reader=$$
  {
    local pids=()
    trap 'kill "${pids[@]}" 2>/dev/null' EXIT
    # Files arrive tagged, so anything untagged is NetworkManager or UPower.
    inotifywait -q -m -e create,delete,close_write,moved_to --format 'file:%f' \
      "$state/indicators" "$state" 2>/dev/null & pids+=($!)
    # nmcli holds its output in a block buffer when it is writing to a pipe,
    # exactly as head did.
    command -v nmcli >/dev/null 2>&1 \
      && { stdbuf -oL nmcli monitor 2>/dev/null & pids+=($!); }
    command -v gdbus >/dev/null 2>&1 \
      && { gdbus monitor --system --dest org.freedesktop.UPower 2>/dev/null & pids+=($!); }
    # Nothing here notices the bar going away until the next event, which may
    # be hours off, so the reader is watched instead.
    while kill -0 "$reader" 2>/dev/null; do sleep 2; done
  } | while :; do
        wait_for=$(( switches_at + OVERVIEW_SWITCHES_RECHECK - SECONDS ))
        (( low_at + OVERVIEW_PERIPHERALS_RECHECK - SECONDS < wait_for )) \
          && wait_for=$(( low_at + OVERVIEW_PERIPHERALS_RECHECK - SECONDS ))
        (( wait_for < 1 )) && wait_for=1
        read -r -t "$wait_for" line; rc=$?
        # End of input is the watcher gone; anything over 128 is the timeout.
        (( rc != 0 && rc <= 128 )) && break
        (( rc == 0 )) && overview_wanted_by "$line"
        # A burst is read whole before anything is asked, or one key press
        # costs four reads.
        if (( want_switches || want_online || want_low )); then
          while read -r -t 0.2 line; do overview_wanted_by "$line"; done
        fi
        (( SECONDS - switches_at >= OVERVIEW_SWITCHES_RECHECK )) && want_switches=1
        (( SECONDS - low_at >= OVERVIEW_PERIPHERALS_RECHECK )) && want_low=1
        (( want_switches || want_online || want_low )) || continue

        (( want_switches )) && { switches=$(overview_switches); switches_at=$SECONDS; }
        (( want_online )) && online=$(overview_online)
        (( want_low )) && { low=$(overview_low_peripherals); low_at=$SECONDS; }
        want_switches=0 want_online=0 want_low=0
        next=$(overview_compose "$switches" "$online" "$low")
        [[ $next != "$last" ]] && { printf '%s\n' "$next"; last=$next; }
      done
}

overview_cmd() {
  case ${1:-state} in
    state|poll) overview_state ;;
    switches) overview_switches ;;
    watch) overview_watch ;;
    # The command that owns a switch is the one that flips it, side effects
    # and all: starting hyprsunset, telling the bar to redraw its indicator.
    toggle) shift
      case ${1:-} in
        # Bar off: the toggle's off leaves a filter on the screen, and the
        # setter is where that is put right.
        nightlight)
          if [[ $(nightlight_enabled) == true ]]; then set_key_apply nightlight false
          else omarchy-toggle-nightlight >/dev/null 2>&1; fi ;;
        dnd) capture_err omarchy-toggle-notification-silencing ;;
        awake) capture_err omarchy-toggle-idle ;;
        dictation) setsid -f voxtype record toggle >/dev/null 2>&1 ;;
        *) die "usage: omacontrol overview toggle nightlight|dnd|awake|dictation" ;;
      esac ;;
    # Waving a notice away is remembered for a day, not for ever: the
    # condition that raised it is still true, and a reader who dismisses it
    # wants it gone now rather than never mentioned again.
    dismiss) shift; [[ -n ${1:-} ]] || die "usage: omacontrol overview dismiss <id>"
      overview_dismiss "$1" ;;
    *) die "usage: omacontrol overview state|poll|switches|watch|toggle <switch>|dismiss <id>" ;;
  esac
}

# ---------------------------------------------------------------- dismissals
#
# Kept in OmaControl's own store, beside everything else this window
# remembers. Stamped rather than flagged: a dismissal that never expires turns
# the page into one that quietly stops mentioning a full disk.
OVERVIEW_DISMISS_FOR=${OMACONTROL_DISMISS_FOR:-86400}

overview_dismiss() {
  note_store '.dismissed = ((.dismissed // {}) | .[$id] = $at)' \
    --arg id "$1" --argjson at "$(date +%s)"
}

overview_dismissed() {
  local now
  now=$(date +%s)
  read_store | jq -c --argjson now "$now" --argjson for "$OVERVIEW_DISMISS_FOR" \
    '[ (.dismissed // {}) | to_entries[] | select(($now - .value) < $for) | .key ]'
}
