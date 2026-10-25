# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# What this machine is. Every line of it is a reading; the page writes nothing
# except the release channel, which is Omarchy's own command.
#
# `fastfetch --format json` answers most of it in one call, and it is already
# on every Omarchy machine because the About screen uses it. Preferring it to
# reading a dozen files under /sys is the same rule as everywhere else here:
# where a tool already knows, ask the tool. It also knows things a naive read
# gets wrong — that a laptop's "model" is the DMI product *family* plus its
# SKU, that a machine can have two GPUs.

about_fastfetch() {
  emit_json "$(capture fastfetch --format json \
    -s OS:Kernel:Host:CPU:GPU:Memory:Uptime:Packages)" '[]'
}

about_state() {
  par_begin || { echo '{}'; return; }
  par_run fetch about_fastfetch
  par_run version omarchy_version
  par_run channel omarchy_channel
  par_run updated omarchy_last_update
  par_run compositor about_compositor
  par_run disk about_disk
  par_run chassis about_chassis
  par_run waiting about_waiting
  par_run age about_os_age
  par_run branding about_branding
  par_wait

  local fetch version channel updated compositor disk age branding chassis waiting updatedAt
  fetch=$(par_get fetch '[]')
  version=$(par_get version '')
  channel=$(par_get channel '')
  updated=$(par_get updated '')
  compositor=$(par_get compositor '')
  disk=$(emit_json "$(par_get disk '{}')" '{}')
  chassis=$(par_get chassis '')
  waiting=$(emit_json "$(par_get waiting '{}')" '{}')
  age=$(par_get age null)
  branding=$(par_get branding '')
  par_end
  updatedAt=$(about_epoch "$updated")

  jq -cn \
    --argjson fetch "${fetch:-[]}" \
    --arg version "$version" \
    --arg channel "$channel" \
    --arg updated "$updated" \
    --arg compositor "$compositor" \
    --argjson disk "${disk:-{\}}" \
    --argjson age "${age:-null}" \
    --arg branding "$branding" \
    --arg chassis "$chassis" \
    --argjson waiting "$waiting" \
    --argjson updatedAt "${updatedAt:-null}" '''
    # fastfetch answers as a list of modules; keyed by type it reads like a
    # record, which is what every line below wants.
    ( reduce $fetch[] as $m ({}; .[$m.type] = $m.result) ) as $f
    | {
        model: ([ $f.Host.family // $f.Host.name // "", $f.Host.version // "" ]
                | map(select(. != "")) | join(" ")),
        sku: ($f.Host.sku // ""),
        cpu: ($f.CPU.cpu // ""),
        cpuCores: ($f.CPU.cores.physical // null),
        cpuThreads: ($f.CPU.cores.online // $f.CPU.cores.logical // null),
        cpuFrequency: ($f.CPU.frequency.max // null),
        # Two integrated GPUs is a real answer on this hardware, so they are
        # all named rather than the first one being called "the" GPU.
        gpus: [ $f.GPU[]? | .name // "" | select(. != "") ],
        memoryBytes: ($f.Memory.total // null),
        kernel: ([ $f.Kernel.name // "", $f.Kernel.release // "" ]
                 | map(select(. != "")) | join(" ")),
        packages: ($f.Packages.all // $f.Packages.pacman // null),
        uptimeSeconds: (if $f.Uptime.uptime then ($f.Uptime.uptime / 1000 | floor) else null end),
        disk: { model: ($disk.model // ""), size: ($disk.size // null) },
        version: $version,
        channel: $channel,
        lastUpdate: $updated,
        lastUpdateAt: $updatedAt,
        chassis: $chassis,
        waiting: $waiting,
        compositor: $compositor,
        osAgeDays: $age,
        branding: $branding
      }'''
}

# The drive the system is on, by the name its maker gave it. The Storage page
# measures every drive; this is the one line a bug report wants.
about_disk() {
  local device
  device=$(disk_backing_device "$(disk_root_source)")
  [[ -n $device ]] || { echo '{}'; return; }
  capture lsblk -dn --json --bytes -o MODEL,SIZE "/dev/$device" \
    | jq -c '.blockdevices[0] // {} | { model: ((.model // "") | gsub("^\\s+|\\s+$"; "")), size: (.size // null) }'
}

# The SMBIOS chassis type, which the kernel leaves readable to everyone: a
# laptop is pictured as one. The types are the ones the spec calls portable.
about_chassis() {
  local type
  type=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)
  case $type in
    8 | 9 | 10 | 11 | 14 | 30 | 31 | 32) printf laptop ;;
    "") ;;
    *) printf desktop ;;
  esac
}

# The same cached count the Packages page shows, so the two pages can never
# give two answers. Never a check of its own: that is a sync over the network.
about_waiting() {
  packages_pending_cached | jq -c '{ count: ((.items // []) | length), checkedAt: (.checkedAt // 0) }'
}

# `omarchy-version-pkgs` words the date for people — "Saturday, September 26
# 2026 at 09:26" — and the page also wants how long ago that was.
about_epoch() {
  local words=${1#*, }
  [[ -n $1 ]] || { printf null; return; }
  date -d "${words/ at / }" +%s 2>/dev/null || printf null
}

omarchy_version() { capture omarchy-version; }
omarchy_channel() { capture omarchy-channel-current; }
# Omarchy already words this the way the About page shows it.
omarchy_last_update() { capture omarchy-version-pkgs; }

about_compositor() {
  local version
  version=$(capture hyprctl version | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /^v?[0-9]+\./) { print $i; exit } }')
  [[ -n ${version:-} ]] && printf 'Hyprland %s (Wayland)' "${version#v}" || printf 'Hyprland (Wayland)'
}

# How long this install has been an install. The first line pacman ever wrote
# is the closest thing to a birthday: a filesystem's own creation date is often
# the date of the last reinstall of the *bootloader*, and /etc is touched by
# every update.
about_os_age() {
  local first now birth
  first=$(capture head -n 200 /var/log/pacman.log \
    | awk 'match($0, /^\[[0-9]{4}-[0-9]{2}-[0-9]{2}/) { print substr($0, 2, 10); exit }')
  [[ -n ${first:-} ]] || { printf 'null'; return; }
  birth=$(date -d "$first" +%s 2>/dev/null) || { printf 'null'; return; }
  now=$(date +%s)
  printf '%s' $(( (now - birth) / 86400 ))
}

# The ASCII the About screen draws, if the user has set one. Shown as the page's
# mark rather than a logo we chose for them.
about_branding() {
  local file="$HOME_DIR/.config/omarchy/branding/about.txt"
  [[ -r $file ]] && read_file "$file" || true
}

about_cmd() {
  case ${1:-state} in
    state|poll) about_state ;;
    channel) shift; [[ -n ${1:-} ]] || die "usage: omacontrol about channel <stable|rc|dev>"
      # Changing channel changes what every future update pulls, so it goes
      # through Omarchy's own command and its confirmation.
      setsid -f omarchy-launch-floating-terminal-with-presentation \
        "omarchy-channel-set $1" >/dev/null 2>&1 ;;
    # One block of text, the way a bug report wants it.
    copy) about_text | wl-copy 2>/dev/null || die "could not copy" ;;
    *) die "usage: omacontrol about state|poll|channel <name>|copy" ;;
  esac
}

about_text() {
  about_state | jq -r '''
    def line(k; v): if (v // "") == "" then empty else "\(k): \(v)" end;
    [ line('"$(i18n_t aboutsection.label.1 'Model')"'; .model + (if .sku != "" then " (" + .sku + ")" else "" end)),
      line('"$(i18n_t aboutsection.label.2 'CPU')"'; .cpu),
      line('"$(i18n_t aboutsection.label.3 'GPU')"'; (.gpus | join(", "))),
      line('"$(i18n_t aboutsection.label.4 'Memory')"'; (if .memoryBytes then ((.memoryBytes / 1000000000) | round | tostring) + " GB" else "" end)),
      line('"$(i18n_t aboutsection.label.5 'Disk')"'; (.disk.model + (if .disk.size then " · " + ((.disk.size / 1000000000) | round | tostring) + " GB" else "" end))),
      line('"$(i18n_t aboutsection.label.6 'OS')"'; "Omarchy " + .version + (if .channel != "" then " (" + '"$(i18n_fill overviewsection.onChannel '%1 channel' '.channel')"' + ")" else "" end)),
      line('"$(i18n_t aboutsection.label.7 'Kernel')"'; .kernel),
      line('"$(i18n_t aboutsection.label.8 'Compositor')"'; .compositor),
      line('"$(i18n_t aboutsection.label.9 'Packages')"'; (.packages | tostring)),
      line('"$(i18n_t aboutsection.label.11 'OS age')"'; (if .osAgeDays then '"$(i18n_fill aboutsection.osAge '%1 days' '.osAgeDays | tostring')"' else "" end))
    ] | join("\n")'''
}
