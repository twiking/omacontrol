# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# Power: what the battery is doing, and the profile the machine runs at. The
# profile is remembered per power source, the
# way omarchy-powerprofiles-set stores it: a laptop wants performance on the
# wall and power-saver on the train, and should not be asked twice a day.
#
# The same module carries the sleep, hibernate, lid and charge-limit settings
# the Power page writes. Omarchy's own idle service only knows the screensaver
# and lock timeouts, so idle.suspend and idle.hibernate in shell.json are
# enforced by the plugin's own service (PowerService.qml), and the lid action
# (.omacontrol.lid) is enforced the same way: logind's lid action is suspend by
# default, so any other choice holds a handle-lid-switch inhibitor while the
# service acts on the lid itself. The charge limit is the battery's own sysfs
# thresholds, which are root-owned almost everywhere, so writing one goes
# through polkit — Omarchy's own agent answers that prompt.

POWERPROFILES_STATE="${OMARCHY_POWERPROFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME_DIR/.local/state}/omarchy/powerprofiles}"
POWER_SUPPLY_DIR="${OMACONTROL_POWER_SUPPLY_DIR:-/sys/class/power_supply}"
# Overridable so a test can watch the invocation without sleeping the machine.
SYSTEMCTL="${OMACONTROL_SYSTEMCTL:-systemctl}"
# polkit's prompt is a human typing a password, so the wait is generous; the
# bound is what keeps a machine with no authentication agent from hanging the
# window on a write it can never finish.
PKEXEC_TIMEOUT="${OMACONTROL_PKEXEC_TIMEOUT:-60}"

power_battery_device() {
  capture upower -e | grep -m1 'BAT'
}

# upower's own report, reduced to the handful of facts worth showing.
power_battery_reading() {
  local device=$1
  [[ -n $device ]] || { echo '{}'; return; }

  # `energy-full-design` also matches /energy-full:/ and `energy-empty` matches
  # /energy:/, so every one of these is anchored on the whole field name.
  capture upower -i "$device" | awk -F': +' '
    function trim(v) { gsub(/^[ \t]+|[ \t]+$/, "", v); return v }
    function number(v) { gsub(/[^0-9.].*$/, "", v); return v }
    /state:/ { state = trim($2) }
    /percentage:/ { percentage = trim($2); sub(/%$/, "", percentage) }
    /time to empty:/ { remaining = trim($2) }
    /time to full:/ { untilFull = trim($2) }
    /^ +capacity:/ { health = trim($2); sub(/%$/, "", health) }
    /energy-rate:/ { rate = trim($2); sub(/ W$/, "", rate) }
    /^ +energy:/ { energy = number(trim($2)) }
    /^ +energy-full:/ { energyFull = number(trim($2)) }
    /^ +energy-full-design:/ { energyDesign = number(trim($2)) }
    # Not every firmware counts them, and the ones that do not say so in
    # several ways — a missing line, N/A, or -1.
    /charge-cycles:/ { cycles = trim($2) }
    /warning-level:/ { warning = trim($2) }
    END {
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
        state, percentage, remaining, untilFull, health, rate,
        energy, energyFull, energyDesign, cycles, warning
    }
  ' | jq -R -s -c 'split("\n") | .[0] | split("\t")
    | { state: .[0],
        percentage: ((.[1] | tonumber?) // null),
        remaining: (if .[0] == "charging" then .[3] else .[2] end),
        health: ((.[4] | tonumber?) // null),
        watts: ((.[5] | tonumber?) // null),
        energy: ((.[6] | tonumber?) // null),
        energyFull: ((.[7] | tonumber?) // null),
        energyDesign: ((.[8] | tonumber?) // null),
        cycles: ((.[9] | tonumber?) | if . == null or . < 0 then null else . end),
        # "none" is the answer on every healthy battery, which is a row that
        # says nothing on every day but the bad ones.
        warning: (if .[10] == "none" then "" else (.[10] // "") end) }'
}

# ------------------------------------------------------------- availability
#
# What the system says it can do, asked the way the system itself is asked:
# logind for the power actions, Omarchy's own checks where Omarchy has them.

power_suspend_available() {
  [[ $(capture busctl call org.freedesktop.login1 /org/freedesktop/login1 \
       org.freedesktop.login1.Manager CanSuspend) == *'"yes"'* ]]
}

power_hibernate_available() {
  # Omarchy's own check is the stricter one — it also looks at swap and the
  # resume configuration — and it is what Omarchy's menu offers, so it decides
  # what this page may offer too.
  if command -v omarchy-hibernation-available >/dev/null 2>&1; then
    capture omarchy-hibernation-available >/dev/null
  else
    [[ $(capture busctl call org.freedesktop.login1 /org/freedesktop/login1 \
         org.freedesktop.login1.Manager CanHibernate) == *'"yes"'* ]]
  fi
}

power_has_lid() {
  if command -v omarchy-hw-laptop >/dev/null 2>&1; then
    capture omarchy-hw-laptop >/dev/null
  else
    capture busctl get-property org.freedesktop.UPower /org/freedesktop/UPower \
      org.freedesktop.UPower LidIsPresent | grep -q 'b true'
  fi
}

# ------------------------------------------------------------- the lid action
#
# shell.json's .omacontrol.lid, validated against the four actions the service
# knows how to perform. Absent means Omarchy's default: lock and suspend, the
# way the lid has always behaved.

power_lid_action() {
  read_shell_json | jq -r '
    (.omacontrol.lid // "suspend")
    | if . == "nothing" or . == "lock" or . == "suspend" or . == "hibernate"
      then . else "suspend" end'
}

# ------------------------------------------------------------- charge limits

power_charge_battery() {
  local bat
  for bat in "$POWER_SUPPLY_DIR"/BAT*; do
    [[ -f $bat/type && $(<"$bat/type") == Battery ]] || continue
    echo "$bat"
    return 0
  done
  return 1
}

# The battery's charge thresholds as they stand. Null when there is no
# battery or the battery exposes no end threshold — the one a charge limit
# cannot do without.
power_charge_threshold() {
  local bat end start
  bat=$(power_charge_battery) || { echo 'null'; return; }
  [[ -r $bat/charge_control_end_threshold ]] || { echo 'null'; return; }
  end=$(tr -d '[:space:]' <"$bat/charge_control_end_threshold" 2>/dev/null) || end=""
  [[ $end =~ ^[0-9]+$ ]] || { echo 'null'; return; }
  start=""
  if [[ -r $bat/charge_control_start_threshold ]]; then
    start=$(tr -d '[:space:]' <"$bat/charge_control_start_threshold" 2>/dev/null) || start=""
    [[ $start =~ ^[0-9]+$ ]] || start=""
  fi
  jq -cn --argjson end "$end" --arg start "$start" '{
    supported: true,
    end: $end,
    start: (if $start == "" then null else ($start | tonumber) end),
    startSupported: ($start != "")
  }'
}

# sysfs is root-owned on most machines, so a direct write is tried first —
# some setups make it user-writable — and the privileged path goes through
# polkit, which Omarchy's own authentication agent answers.
power_charge_write() {
  local file=$1 value=$2
  # A threshold file that is not there is a battery without that threshold,
  # not a prompt to authorise: fail before polkit is ever asked.
  [[ -e $file ]] || return 1
  if [[ -w $file ]]; then
    printf '%s\n' "$value" >"$file" 2>/dev/null && return 0
  fi
  printf '%s\n' "$value" | timeout "$PKEXEC_TIMEOUT" pkexec tee "$file" >/dev/null 2>&1
}

power_charge_set() {
  local which=$1 value=$2 bat end start
  [[ $value =~ ^[0-9]+$ ]] || die "'$value' is not a whole percent"
  (( value >= 1 && value <= 100 )) || die "'$value' is not between 1 and 100"
  bat=$(power_charge_battery) || die "no battery found"

  case $which in
    end)
      # The kernel refuses a start threshold at or above the end one, so a
      # lower end threshold takes the begin-charging one down with it rather
      # than leaving the pair impossible.
      if [[ -r $bat/charge_control_start_threshold ]]; then
        start=$(tr -d '[:space:]' <"$bat/charge_control_start_threshold" 2>/dev/null) || start=""
        if [[ $start =~ ^[0-9]+$ ]] && (( start >= value )); then
          local begin=$(( value - 5 ))
          (( begin < 0 )) && begin=0
          power_charge_write "$bat/charge_control_start_threshold" "$begin" \
            || die "could not set the begin-charging threshold to $begin"
        fi
      fi
      power_charge_write "$bat/charge_control_end_threshold" "$value" \
        || die "could not set the charge threshold to $value" ;;
    start)
      [[ -r $bat/charge_control_start_threshold ]] \
        || die "this battery has no begin-charging threshold"
      end=$(tr -d '[:space:]' <"$bat/charge_control_end_threshold" 2>/dev/null) || end=""
      if [[ $end =~ ^[0-9]+$ ]] && (( value >= end )); then
        die "begin charging below $value is not below the stop threshold ($end)"
      fi
      power_charge_write "$bat/charge_control_start_threshold" "$value" \
        || die "could not set the begin-charging threshold to $value" ;;
    *) die "expected end or start" ;;
  esac
}

# ------------------------------------------------------------- state

power_state() {
  local device reading profiles current onbattery saved_ac saved_battery
  local suspend_ok=false hibernate_ok=false has_lid=false

  # The battery, the power actions and the lid are worth reporting even when
  # the profile daemon is missing: a desktop without powerprofilesctl still
  # has a lid, and the profile half of the page simply has nothing to say.
  device=$(power_battery_device)
  reading=$(power_battery_reading "$device")
  power_suspend_available && suspend_ok=true
  power_hibernate_available && hibernate_ok=true
  power_has_lid && has_lid=true

  command -v powerprofilesctl >/dev/null 2>&1 || {
    jq -cn --argjson reading "${reading:-{\}}" \
      --argjson hasBattery "$([[ -n $device ]] && echo true || echo false)" \
      --argjson suspendOk "$suspend_ok" \
      --argjson hibernateOk "$hibernate_ok" \
      --argjson hasLid "$has_lid" \
      --arg lidAction "$(power_lid_action)" \
      --argjson charge "$(power_charge_threshold)" \
      '{ available: false,
         hasBattery: $hasBattery,
         battery: $reading,
         suspendAvailable: $suspendOk,
         hibernateAvailable: $hibernateOk,
         hasLid: $hasLid,
         lidAction: $lidAction,
         chargeThreshold: $charge }'
    return
  }

  profiles=$(capture omarchy-powerprofiles-list | jq -R -s -c 'split("\n") | map(select(length > 0))')
  current=$(capture powerprofilesctl get)
  onbattery=$(busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null)
  saved_ac=$(read_file "$POWERPROFILES_STATE/ac")
  saved_battery=$(read_file "$POWERPROFILES_STATE/battery")

  # A machine with no battery still has power profiles worth setting; the
  # battery half of the page simply has nothing to say.
  jq -cn --argjson reading "${reading:-{\}}" \
    --argjson profiles "${profiles:-[]}" \
    --arg current "${current:-}" \
    --argjson onBattery "$([[ $onbattery == "b true" ]] && echo true || echo false)" \
    --arg savedAc "${saved_ac:-}" \
    --arg savedBattery "${saved_battery:-}" \
    --argjson hasBattery "$([[ -n $device ]] && echo true || echo false)" \
    --argjson suspendOk "$suspend_ok" \
    --argjson hibernateOk "$hibernate_ok" \
    --argjson hasLid "$has_lid" \
    --arg lidAction "$(power_lid_action)" \
    --argjson charge "$(power_charge_threshold)" \
    '{ available: true,
       hasBattery: $hasBattery,
       onBattery: $onBattery,
       battery: $reading,
       profiles: $profiles,
       current: $current,
       # What is remembered for each source, falling back to what
       # omarchy-powerprofiles-set would itself choose.
       ac: (if $savedAc != "" then $savedAc
            elif ($profiles | index("performance")) then "performance"
            else "balanced" end),
       forBattery: (if $savedBattery != "" then $savedBattery else "balanced" end),
       # The sleep and hibernate timeouts are in shell.json (state.idle), not
       # here; the rest of what the page needs beyond the battery is.
       suspendAvailable: $suspendOk,
       hibernateAvailable: $hibernateOk,
       hasLid: $hasLid,
       lidAction: $lidAction,
       chargeThreshold: $charge }'
}

# The profile is not this window's alone: the bar's power plugin, the menu and
# powerprofilesctl itself all move it, and the battery drains regardless. Three
# things are worth waking for — the daemon's active profile, UPower's battery
# and AC readings, and the files omarchy-powerprofiles-set writes to remember a
# profile per power source — so all three feed one stream of state lines.
power_watch() {
  command -v powerprofilesctl >/dev/null 2>&1 || { echo '{"available": false}'; return; }

  mkdir -p "$POWERPROFILES_STATE" 2>/dev/null
  power_state

  local reader=$$
  {
    local pids=()
    # The monitors outlive nothing: when this subshell goes, so do they.
    trap 'kill "${pids[@]}" 2>/dev/null' EXIT

    gdbus monitor --system --dest net.hadess.PowerProfiles 2>/dev/null & pids+=($!)
    gdbus monitor --system --dest org.freedesktop.UPower 2>/dev/null & pids+=($!)
    inotifywait -q -m -e close_write,create,moved_to "$POWERPROFILES_STATE" 2>/dev/null & pids+=($!)

    # None of them notices the page closing, and a write to a gone reader is
    # only noticed at the next event — which may be hours away. Watch for the
    # reader instead, so the monitors never outlast the window.
    while kill -0 "$reader" 2>/dev/null; do sleep 2; done
  } | while read -r _; do
        # UPower is chatty and a profile change lands as several signals;
        # draining the burst keeps this to one state read per change.
        while read -r -t 0.2 _; do :; done
        power_state
      done
}

# ------------------------------------------------------------- actions
#
# The commands the window and the always-on service call. sleep and hibernate
# are the same commands Omarchy's own menu runs, so the lock-before-sleep path
# (omarchy-sleep-lock) applies to them exactly as it does to the menu.

power_sleep() { "$SYSTEMCTL" suspend; }

power_hibernate() { "$SYSTEMCTL" hibernate; }

# What a closed lid should do. "suspend" is Omarchy's default and needs no
# help — the service releases its inhibitor for it, so logind suspends and
# Omarchy's own lid binding locks. "lock" and "nothing" are Omarchy's lid
# binding or its managed replacement in bindings.lua. Only hibernate has the
# service acting, and a docked lid close is clamshell mode — still in use on
# the external display — so it must not hibernate, the way logind's own
# HandleLidSwitchDocked defaults to ignore.
power_lid_closed() {
  [[ $(power_lid_action) == hibernate ]] || return 0
  power_hibernate_available || die "hibernate is not available on this computer"
  if command -v omarchy-hw-external-monitors >/dev/null 2>&1; then
    capture omarchy-hw-external-monitors >/dev/null && return 0
  fi
  power_hibernate
}

power_cmd() {
  local action=${1:-} source=${2:-} profile=${3:-}
  case $action in
    state) power_state ;;
    watch) power_watch ;;
    profile)
      [[ $source == ac || $source == battery ]] || die "expected ac or battery"
      [[ -n $profile ]] || die "no profile given"
      omarchy-powerprofiles-set "$source" "$profile" >/dev/null 2>&1 \
        || die "could not set the $source profile to $profile" ;;
    sleep) power_sleep ;;
    hibernate) power_hibernate ;;
    lid)
      [[ $source == closed ]] || die "expected closed"
      power_lid_closed ;;
    charge) power_charge_set "$source" "$profile" ;;
    *) die "unknown power action '$action'" ;;
  esac
}
