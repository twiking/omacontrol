#!/bin/bash
# Power settings: the sleep/hibernate timeouts, the lid action and its
# bindings.lua override, and the battery charge limits.
# Run from any directory: bash tests/power-settings.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
fakebin="$sandbox/bin"
mkdir -p "$fakebin" "$sandbox/sys/BAT0" "$sandbox/sys/AC" "$sandbox/sys-empty" \
  "$sandbox/sys-nothreshold/BAT0" "$sandbox/state" "$sandbox/hypr" "$sandbox/xdg-state"

export OMACONTROL_STORE="$sandbox/state/omacontrol.json"
export OMARCHY_SHELL_JSON="$sandbox/shell.json"
export OMACONTROL_BINDINGS_LUA="$sandbox/bindings.lua"
export OMACONTROL_HYPR_DIR="$sandbox/hypr"
export OMACONTROL_POWER_SUPPLY_DIR="$sandbox/sys"
export OMACONTROL_PKEXEC_TIMEOUT=2
export XDG_STATE_HOME="$sandbox/xdg-state"
export OMACONTROL_SYSTEMCTL="$fakebin/systemctl"
export FAKE_LOG="$sandbox/state"
export PATH="$fakebin:$PATH"

# ------------------------------------------------------------- fakes
# Every external command the power module calls, answered from $FAKE_LOG and
# the FAKE_* switches, so the test never touches the real system.

cat >"$fakebin/systemctl" <<'EOF'
#!/bin/bash
echo "$*" >>"$FAKE_LOG/systemctl.log"
EOF
cat >"$fakebin/hyprctl" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$fakebin/upower" <<'EOF'
#!/bin/bash
if [[ ${1:-} == -e ]]; then
  echo /org/freedesktop/UPower/devices/battery_BAT0
  exit 0
fi
cat <<'READING'
  native-path:          BAT0
  state:                Discharging
  percentage:           86
  time to empty:        3.2 hours
  capacity:             90.5
  energy-rate:          12.3 W
READING
EOF
cat >"$fakebin/powerprofilesctl" <<'EOF'
#!/bin/bash
echo balanced
EOF
cat >"$fakebin/omarchy-powerprofiles-list" <<'EOF'
#!/bin/bash
printf 'power-saver\nbalanced\nperformance\n'
EOF
cat >"$fakebin/busctl" <<'EOF'
#!/bin/bash
case ${!#} in
  OnBattery) echo 'b false' ;;
  LidIsPresent) echo 'b true' ;;
  CanSuspend) echo 's "yes"' ;;
  CanHibernate) echo 's "yes"' ;;
esac
EOF
cat >"$fakebin/omarchy-hibernation-available" <<'EOF'
#!/bin/bash
exit "${FAKE_HIBERNATE:-0}"
EOF
cat >"$fakebin/omarchy-hw-laptop" <<'EOF'
#!/bin/bash
exit "${FAKE_LAPTOP:-0}"
EOF
cat >"$fakebin/omarchy-hw-external-monitors" <<'EOF'
#!/bin/bash
exit "${FAKE_DOCKED:-1}"
EOF
chmod +x "$fakebin"/*

# The fake battery: a charge limit at 80/75, and a mains device that is not
# a battery and must never be picked.
echo Battery >"$sandbox/sys/BAT0/type"
echo 80 >"$sandbox/sys/BAT0/charge_control_end_threshold"
echo 75 >"$sandbox/sys/BAT0/charge_control_start_threshold"
echo Mains >"$sandbox/sys/AC/type"
echo Battery >"$sandbox/sys-nothreshold/BAT0/type"

printf '{"version":1,"idle":{"screensaver":150,"lock":300}}\n' >"$OMARCHY_SHELL_JSON"
printf -- '-- my own bindings\n' >"$OMACONTROL_BINDINGS_LUA"

# ------------------------------------------------------------- the modules
source "$root/lib/core.sh"
source "$root/lib/store.sh"
source "$root/lib/shell_config.sh"
source "$root/lib/bindings.sh"
source "$root/lib/power.sh"
source "$root/lib/setters.sh"
source "$root/lib/state.sh"
# Store edits re-render the managed Lua; the renderer is not under test here.
render_managed() { :; }

# ------------------------------------------------------------- assertions
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
check() { [[ $2 == "$3" ]] || fail "$1 (expected [$2], got [$3])"; }
has() { grep -qF -- "$1" "$2" || fail "$3 (missing [$1] in $2)"; }
lacks() { if grep -qF -- "$1" "$2"; then fail "$3 (found [$1] in $2)"; fi; }

# ------------------------------------------------------------- lid action read
jq -n '{version:1, omacontrol:{lid:"bogus"}}' >"$OMARCHY_SHELL_JSON"
check "garbage lid action falls back to the default" suspend "$(power_lid_action)"
jq -n '{version:1, omacontrol:{lid:"lock"}}' >"$OMARCHY_SHELL_JSON"
check "a valid lid action reads back" lock "$(power_lid_action)"
jq -n '{"version":1,"idle":{"screensaver":150,"lock":300}}' >"$OMARCHY_SHELL_JSON"
check "an absent lid action is the default" suspend "$(power_lid_action)"

# ------------------------------------------------------------- idle slice
idle=$(state_slice idle)
check "idle slice reads the sleep timeout as off" 0 "$(jq -r '.idle.suspend' <<<"$idle")"
check "idle slice reads the hibernate timeout as off" 0 "$(jq -r '.idle.hibernate' <<<"$idle")"

# ------------------------------------------------------------- sleep timeout
set_key idle-suspend 900
check "sleep timeout written to shell.json" 900 "$(jq -r '.idle.suspend' "$OMARCHY_SHELL_JSON")"
check "sleep timeout reads back" 900 "$(setting_value_now idle-suspend)"
check "sleep timeout remembers it was off" 0 "$(jq -r '.written["idle-suspend"]' "$OMACONTROL_STORE")"
idle=$(state_slice idle)
check "idle slice reads the sleep timeout" 900 "$(jq -r '.idle.suspend' <<<"$idle")"
setting_reset idle-suspend
check "sleep timeout reset writes off" 0 "$(jq -r '.idle.suspend' "$OMARCHY_SHELL_JSON")"
check "sleep timeout record cleared" null "$(jq -r '.written["idle-suspend"] // "null"' "$OMACONTROL_STORE")"
if ( set_key idle-hibernate abc ) 2>/dev/null; then fail "a non-numeric timeout was accepted"; fi
if ( set_key idle-suspend -5 ) 2>/dev/null; then fail "a negative timeout was accepted"; fi

# ------------------------------------------------------------- lid action set
set_key lid-action nothing
check "lid action written to shell.json" nothing "$(jq -r '.omacontrol.lid' "$OMARCHY_SHELL_JSON")"
check "lid action reads back" nothing "$(setting_value_now lid-action)"
check "lid action remembers the default" suspend "$(jq -r '.written["lid-action"]' "$OMACONTROL_STORE")"
has 'hl.unbind("switch:on:Lid Switch")' "$OMACONTROL_BINDINGS_LUA" "lid override block missing the unbind"
has 'o.bind("switch:on:Lid Switch", nil, "omarchy-hyprland-monitor-clamshell", { locked = true })' \
  "$OMACONTROL_BINDINGS_LUA" "lid override block missing the clamshell rebind"
has "$LID_BEGIN" "$OMACONTROL_BINDINGS_LUA" "lid override block missing its begin marker"
has "$LID_END" "$OMACONTROL_BINDINGS_LUA" "lid override block missing its end marker"
has '-- my own bindings' "$OMACONTROL_BINDINGS_LUA" "the user's own bindings were eaten"

setting_reset lid-action
check "lid action reset writes the default back" suspend "$(jq -r '.omacontrol.lid' "$OMARCHY_SHELL_JSON")"
lacks 'hl.unbind("switch:on:Lid Switch")' "$OMACONTROL_BINDINGS_LUA" "lid override block survived the reset"
has '-- my own bindings' "$OMACONTROL_BINDINGS_LUA" "the user's own bindings were eaten by the removal"

if ( set_key lid-action bogus ) 2>/dev/null; then fail "a bad lid action was accepted"; fi

# Any other action leaves Omarchy's lid binding alone: no block at all.
set_key lid-action lock
lacks "$LID_BEGIN" "$OMACONTROL_BINDINGS_LUA" "a lock action installed the override block"
setting_reset lid-action

# A machine with no bindings.lua is not an error, and creates nothing.
rm -f "$OMACONTROL_BINDINGS_LUA"
set_key lid-action nothing
check "lid action written without a bindings file" nothing "$(jq -r '.omacontrol.lid' "$OMARCHY_SHELL_JSON")"
[[ -f $OMACONTROL_BINDINGS_LUA ]] && fail "a bindings.lua was created for a missing target"
printf -- '-- my own bindings\n' >"$OMACONTROL_BINDINGS_LUA"
setting_reset lid-action

# ------------------------------------------------------------- charge limits
check "charge threshold supported" true "$(power_charge_threshold | jq -r '.supported')"
check "charge threshold end" 80 "$(power_charge_threshold | jq -r '.end')"
check "charge threshold start" 75 "$(power_charge_threshold | jq -r '.start')"
check "charge threshold start supported" true "$(power_charge_threshold | jq -r '.startSupported')"

power_charge_set end 85
check "end threshold written" 85 "$(cat "$sandbox/sys/BAT0/charge_control_end_threshold")"
check "start threshold untouched" 75 "$(cat "$sandbox/sys/BAT0/charge_control_start_threshold")"

# A lower end threshold takes the start threshold down with it: the kernel
# refuses a begin-charging level at or above the stop one.
power_charge_set end 70
check "end threshold lowered" 70 "$(cat "$sandbox/sys/BAT0/charge_control_end_threshold")"
check "start threshold lowered with it" 65 "$(cat "$sandbox/sys/BAT0/charge_control_start_threshold")"

if ( power_charge_set start 90 ) 2>/dev/null; then fail "a start threshold above the end was accepted"; fi
power_charge_set start 60
check "start threshold written" 60 "$(cat "$sandbox/sys/BAT0/charge_control_start_threshold")"

if ( power_charge_set end 0 ) 2>/dev/null; then fail "a zero percent was accepted"; fi
if ( power_charge_set end 101 ) 2>/dev/null; then fail "an over-100 percent was accepted"; fi
if ( power_charge_set end abc ) 2>/dev/null; then fail "a non-numeric percent was accepted"; fi

# A battery with no threshold files supports nothing and writes nothing.
POWER_SUPPLY_DIR="$sandbox/sys-nothreshold"
check "a battery without thresholds is unsupported" null "$(power_charge_threshold)"
if ( power_charge_set end 85 ) 2>/dev/null; then fail "an end threshold was written without support"; fi
if ( power_charge_set start 50 ) 2>/dev/null; then fail "a start threshold was written without support"; fi
POWER_SUPPLY_DIR="$sandbox/sys-empty"
check "no battery means no thresholds" null "$(power_charge_threshold)"
if ( power_charge_set end 85 ) 2>/dev/null; then fail "a threshold was written with no battery"; fi
POWER_SUPPLY_DIR="$sandbox/sys"

# ------------------------------------------------------------- power state
jq -n '{"version":1,"omacontrol":{"lid":"lock"}}' >"$OMARCHY_SHELL_JSON"
state=$(power_state)
check "power state available" true "$(jq -r '.available' <<<"$state")"
check "suspend available" true "$(jq -r '.suspendAvailable' <<<"$state")"
check "hibernate available" true "$(jq -r '.hibernateAvailable' <<<"$state")"
check "lid present" true "$(jq -r '.hasLid' <<<"$state")"
check "lid action in state" lock "$(jq -r '.lidAction' <<<"$state")"
check "charge end in state" 70 "$(jq -r '.chargeThreshold.end' <<<"$state")"

export FAKE_HIBERNATE=1
state=$(power_state)
check "hibernate unavailable reported" false "$(jq -r '.hibernateAvailable' <<<"$state")"
export FAKE_HIBERNATE=0
export FAKE_LAPTOP=1
state=$(power_state)
check "a missing lid reported" false "$(jq -r '.hasLid' <<<"$state")"
export FAKE_LAPTOP=0

# ------------------------------------------------------------- power actions
: >"$FAKE_LOG/systemctl.log"
power_sleep
check "sleep runs systemctl suspend" suspend "$(cat "$FAKE_LOG/systemctl.log")"
: >"$FAKE_LOG/systemctl.log"
power_hibernate
check "hibernate runs systemctl hibernate" hibernate "$(cat "$FAKE_LOG/systemctl.log")"

# A closed lid hibernates — the one action the service has to perform itself.
jq -n '{"version":1,"omacontrol":{"lid":"hibernate"}}' >"$OMARCHY_SHELL_JSON"
: >"$FAKE_LOG/systemctl.log"
power_lid_closed
check "a closed lid hibernates" hibernate "$(cat "$FAKE_LOG/systemctl.log")"

# Docked, the lid close is clamshell mode and must do nothing.
: >"$FAKE_LOG/systemctl.log"
export FAKE_DOCKED=0
power_lid_closed
check "a docked lid close does nothing" "" "$(cat "$FAKE_LOG/systemctl.log")"
export FAKE_DOCKED=1

# Every other action is Omarchy's own machinery, not this one's.
jq -n '{"version":1,"omacontrol":{"lid":"suspend"}}' >"$OMARCHY_SHELL_JSON"
: >"$FAKE_LOG/systemctl.log"
power_lid_closed
check "the default lid action is left to logind" "" "$(cat "$FAKE_LOG/systemctl.log")"

# Hibernating without hibernation available is refused, not attempted.
jq -n '{"version":1,"omacontrol":{"lid":"hibernate"}}' >"$OMARCHY_SHELL_JSON"
export FAKE_HIBERNATE=1
if ( power_lid_closed ) 2>/dev/null; then fail "an unavailable hibernate was attempted"; fi
export FAKE_HIBERNATE=0

# ------------------------------------------------------------- the commands
: >"$FAKE_LOG/systemctl.log"
power_cmd sleep
check "power sleep runs systemctl suspend" suspend "$(cat "$FAKE_LOG/systemctl.log")"
: >"$FAKE_LOG/systemctl.log"
power_cmd charge end 90
check "power charge end writes the threshold" 90 "$(cat "$sandbox/sys/BAT0/charge_control_end_threshold")"
if ( power_cmd charge start 95 ) 2>/dev/null; then fail "power charge start above the end was accepted"; fi
if ( power_cmd bogus ) 2>/dev/null; then fail "an unknown power action was accepted"; fi

echo 'PASS: timeouts, lid action and override block, charge limits, power actions'
