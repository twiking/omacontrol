# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# What the machine is busy with. Read-only apart from the two things anyone
# opens a process list to do: end something, or push it out of the way.
#
# Like the Disk page, none of this joins the state document — it is true for
# about a second, and the page polls it while it is on screen.

# Overall CPU, from two samples of /proc/stat rather than one.
#
# One sample cannot answer "how busy is it now": the counters in /proc/stat
# are totals since boot, so a single read gives the average since the machine
# came up, which on a six-day uptime is a number that never moves. The delta
# between two reads a fifth of a second apart is what the reader means.
processes_cpu() {
  local idle1 total1 idle2 total2
  read -r idle1 total1 < <(processes_cpu_sample)
  sleep 0.2
  read -r idle2 total2 < <(processes_cpu_sample)

  awk -v i1="$idle1" -v t1="$total1" -v i2="$idle2" -v t2="$total2" '
    BEGIN {
      dt = t2 - t1
      di = i2 - i1
      if (dt <= 0) { print "null"; exit }
      pct = (1 - di / dt) * 100
      if (pct < 0) pct = 0
      if (pct > 100) pct = 100
      printf "%.0f\n", pct
    }'
}

processes_cpu_sample() {
  awk 'NR == 1 { idle = $5 + $6; total = 0; for (i = 2; i <= NF; i++) total += $i
                 print idle, total; exit }' /proc/stat
}

# Per-core, for the row of bars the page draws beside the figure. Same two
# samples, one line per core.
processes_cores() {
  local first second
  first=$(awk '/^cpu[0-9]/ { idle = $5 + $6; total = 0
                             for (i = 2; i <= NF; i++) total += $i
                             print $1, idle, total }' /proc/stat)
  sleep 0.2
  second=$(awk '/^cpu[0-9]/ { idle = $5 + $6; total = 0
                              for (i = 2; i <= NF; i++) total += $i
                              print $1, idle, total }' /proc/stat)

  emit_json "$(awk '
    NR == FNR { idle[$1] = $2; total[$1] = $3; next }
    {
      dt = $3 - total[$1]
      di = $2 - idle[$1]
      pct = (dt > 0) ? (1 - di / dt) * 100 : 0
      if (pct < 0) pct = 0
      if (pct > 100) pct = 100
      printf "%.0f\n", pct
    }' <(printf '%s\n' "$first") <(printf '%s\n' "$second") \
    | jq -Rc -s '[ split("\n")[] | select(length > 0) | tonumber ]')" '[]'
}

processes_memory() {
  awk '
    /^MemTotal:/ { total = $2 }
    /^MemAvailable:/ { avail = $2 }
    /^SwapTotal:/ { swaptotal = $2 }
    /^SwapFree:/ { swapfree = $2 }
    END {
      if (total <= 0) { print "{}"; exit }
      # /proc/meminfo is in kibibytes; everything the window formats is bytes.
      printf "{\"total\":%d,\"used\":%d,\"swap\":%d,\"swapTotal\":%d,\"percent\":%.0f}\n",
        total * 1024, (total - avail) * 1024, (swaptotal - swapfree) * 1024,
        swaptotal * 1024, ((total - avail) / total) * 100
    }' /proc/meminfo
}

processes_load() {
  local cores
  cores=$(nproc 2>/dev/null || echo 1)
  awk -v cores="$cores" -v uptime="$(cut -d. -f1 /proc/uptime)" '
    { printf "{\"one\":%s,\"five\":%s,\"fifteen\":%s,\"cores\":%s,\"uptime\":%s}\n",
        $1, $2, $3, cores, uptime }' /proc/loadavg
}

# CPU per process, as `pid<TAB>percent of the whole machine`.
#
# `top` and not `ps`. ps reports the average over a process's whole life, so a
# browser that pinned a core an hour ago outranks the one doing it right now,
# which is the opposite of what the page is for. top's second frame is
# measured against its first, so it is the CPU of the moment; the first frame
# is ps's number and is thrown away.
#
# Divided by the core count, the way btop shows it: top calls a thread that
# fills one core 100 %, which on sixteen cores is 6 % of the machine, and the
# card above the lists is a share of the machine.
processes_cpu_by_pid() {
  local cores
  cores=$(nproc 2>/dev/null || echo 1)
  capture top -b -n 2 -d 0.2 -w 512 \
    | awk -v cores="$cores" '
        /^ *PID/ { frame++; next }
        frame == 2 && NF >= 12 {
          cpu = $9; gsub(",", ".", cpu)
          if (cpu + 0 > 0) printf "%s\t%.2f\n", $1, cpu / cores
        }'
}

# Every process, as `pid<TAB>ppid<TAB>bytes<TAB>cpu seconds<TAB>name`.
#
# Fixed-width columns, because a command name can hold a space ("Web Content")
# and would otherwise shift every field after it.
#
# The name is the one a reader would recognise, which is not always the one
# the kernel holds: Node calls its main thread `MainThread`, and a Nix wrapper
# is `.foo-wrapped`. For those the first argument that is neither a flag nor
# an interpreter names the program instead.
processes_table() {
  capture ps -eo pid:10=,ppid:10=,rss:12=,times:12=,comm:64=,args= \
    | awk '
        {
          pid = substr($0, 1, 10) + 0
          ppid = substr($0, 12, 10) + 0
          rss = substr($0, 23, 12) + 0
          seconds = substr($0, 36, 12) + 0
          comm = substr($0, 49, 64); sub(/ +$/, "", comm)
          name = comm
          # The kernel keeps fifteen characters of the name, so a long
          # `.firefox-wrapped` arrives as `.firefox-wrappe`.
          if (comm == "MainThread" || comm ~ /^\..*-wr/) {
            n = split(substr($0, 114), args, " ")
            for (i = 1; i <= n; i++) {
              if (args[i] ~ /^-/) continue
              m = split(args[i], part, "/")
              if (part[m] != "" && part[m] !~ /^(node|python[0-9.]*|bash|sh|zsh|env)$/) { name = part[m]; break }
            }
          }
          gsub(/\t/, " ", name)
          printf "%d\t%d\t%d\t%d\t%s\n", pid, ppid, rss * 1024, seconds, name
        }'
}

# Which Docker container each process belongs to, as `pid<TAB>container`.
#
# By cgroup: a container's processes are the members of its scope, and the
# scope is named by the container's id. The name the reader knows is Docker's
# to give, so `docker ps` is asked for it, and only when there is a scope to
# name — a machine with no containers running never wakes the daemon.
processes_containers() {
  local scopes=(/sys/fs/cgroup/system.slice/docker-*.scope)
  [[ -e ${scopes[0]} ]] || return 0
  command -v docker >/dev/null 2>&1 || return 0

  # A wedged daemon leaves its client waiting, so it gets two seconds rather
  # than the read budget: the page polls every two and would freeze on it.
  local -A names=()
  local id name scope pid
  while read -r id name; do
    [[ -n $id ]] && names[$id]=$name
  done < <(capture_for 2 docker ps --no-trunc --format '{{.ID}} {{.Names}}')

  for scope in "${scopes[@]}"; do
    id=${scope##*/docker-}
    id=${id%.scope}
    name=${names[$id]:-}
    [[ -n $name && -r $scope/cgroup.procs ]] || continue
    while read -r pid; do
      [[ -n $pid ]] && printf '%s\t%s\n' "$pid" "$name"
    done <"$scope/cgroup.procs"
  done
}

# The three readings joined into the tree btop draws, plus the ten heaviest by
# CPU and by memory.
#
# The tree is flat and in reading order, each row carrying what it takes to
# draw its own guides: how deep it is, whether it is the last of its siblings,
# and for every ancestor whether that ancestor's line carries on past it. A
# folded row stands for everything under it, so each row also carries its
# subtree's totals.
#
# Siblings are in PID order rather than by load. The tree refreshes every two
# seconds, and a row that jumps whenever its CPU does cannot be clicked; the
# lists above it are what rank.
#
# The ten heaviest are counted by name and container, so twenty browser
# processes are one browser, and the Node inside a container is not added to
# the Node outside it.
#
# Always ten, even when fewer than ten used any CPU in the sample: a list
# that grows and shrinks every two seconds moves everything under it. The
# rest are ranked by the CPU time they have used in their lives, which is the
# best guess at what will be on the list next — ps's lifetime figure is wrong
# for "now", and right for breaking a tie at zero.
#
# This invocation's own processes are left out — the reader asked what the
# machine is busy with, and `top` measuring itself is not an answer.
processes_build() {
  local cpu=$1 table=$2 containers=$3
  [[ -n $table ]] || { echo '{}'; return; }

  emit_json "$(awk -F'\t' '
      FILENAME == ARGV[1] { cpu[$1] = $2; next }
      FILENAME == ARGV[2] { ctr[$1] = $2; next }
      NF >= 5 { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, (cpu[$1] == "" ? 0 : cpu[$1]), $3, $4, $5, ctr[$1] }
    ' <(printf '%s\n' "$cpu") <(printf '%s\n' "$containers") <(printf '%s\n' "$table") \
    | jq -Rc -s --argjson self "$$" '
      [ split("\n")[] | select(length > 0) | split("\t")
        | { pid: (.[0] | tonumber), ppid: (.[1] | tonumber), cpu: (.[2] | tonumber),
            memory: (.[3] | tonumber), seconds: (.[4] | tonumber), name: .[5],
            container: (.[6] // "") } ] as $all
      | ($all | map({ key: (.pid | tostring), value: . }) | from_entries) as $by
      | ($all | map(select(.pid != $self)) | group_by(.ppid)
         | map({ key: (.[0].ppid | tostring), value: (map(.pid) | sort) }) | from_entries) as $kids

      | def subtree($pid; $depth; $lines; $last):
          $by[$pid | tostring] as $p
          | ($kids[$pid | tostring] // []) as $children
          | ($children | length) as $n
          | (if $depth > 0 then $lines + [$last | not] else $lines end) as $through
          | [ range(0; $n) as $i | subtree($children[$i]; $depth + 1; $through; $i == $n - 1) ] as $below
          | [ $p + { depth: $depth, lines: $lines, last: $last, parent: ($n > 0),
                     treeCpu: ($p.cpu + ([ $below[][0].treeCpu ] | add // 0)),
                     treeMemory: ($p.memory + ([ $below[][0].treeMemory ] | add // 0)) } ]
            + [ $below[][] ];

      [ $all[] | select(.pid != $self and ($by[.ppid | tostring] == null)) | .pid ] | sort
      | [ .[] | subtree(.; 0; []; true)[] ] as $tree

      | def heaviest($key):
          [ $tree | group_by([.name, .container])[]
            | { name: .[0].name, container: .[0].container, value: (map(.[$key]) | add),
                seconds: (map(.seconds) | add), pids: map(.pid) } ]
          | sort_by(-.value, -.seconds) | .[0:10] | map(del(.seconds));

      { tree: ($tree | map(del(.seconds))), busiest: heaviest("cpu"), heaviest: heaviest("memory") }
    ' 2>/dev/null)" '{}'
}

processes_state() {
  par_begin || { echo '{}'; return; }
  # The CPU and core samples each want a fifth of a second of wall clock, and
  # top wants its two frames; run together, the whole page costs the longest
  # of them rather than the sum.
  par_run cpu processes_cpu
  par_run cores processes_cores
  par_run memory processes_memory
  par_run load processes_load
  par_run temp processes_temperature
  par_run sample processes_cpu_by_pid
  par_run table processes_table
  par_run containers processes_containers
  par_wait

  local cpu cores memory load temp list
  cpu=$(par_get cpu null)
  cores=$(par_get cores '[]')
  memory=$(par_get memory '{}')
  load=$(par_get load '{}')
  temp=$(par_get temp null)
  list=$(processes_build "$(par_get sample)" "$(par_get table)" "$(par_get containers)")
  par_end

  # The tree goes in on stdin. On a busy machine it passes 128 KiB, and the
  # kernel refuses any one argv or environment string longer than that, so as
  # an --argjson it failed the whole read with "Argument list too long" and the
  # page drew nothing.
  printf '%s' "${list:-{\}}" | jq -c \
    --argjson cpu "${cpu:-null}" \
    --argjson cores "${cores:-[]}" \
    --argjson memory "${memory:-{\}}" \
    --argjson load "${load:-{\}}" \
    --argjson temperature "${temp:-null}" \
    '. as $list
     | { cpu: $cpu, cores: $cores, memory: $memory, load: $load, temperature: $temperature,
         tree: ($list.tree // []), busiest: ($list.busiest // []), heaviest: ($list.heaviest // []) }'
}

# Whatever the machine is willing to call the CPU's temperature. Nothing at all
# on a machine with no such sensor, which the page renders as nothing rather
# than as zero degrees.
processes_temperature() {
  local degrees
  degrees=$(capture sensors -j 2>/dev/null \
    | jq -r '[ to_entries[] | select(.key | test("coretemp|k10temp|zenpower"))
               | .value | to_entries[] | select(.key | test("Package|Tctl|Tdie"))
               | .value | to_entries[] | select(.key | endswith("_input")) | .value ]
             | first // empty' 2>/dev/null)
  [[ -n ${degrees:-} ]] && printf '%.0f' "$degrees" || printf 'null'
}

# A row in the top lists is every process of one program, so ending it ends
# all of them. Each is signalled on its own: one that exited since the poll
# is not a reason to leave the rest running.
processes_signal() {
  local signal=$1 verb=$2 pid failed=0
  shift 2
  (( $# > 0 )) || die "usage: omacontrol processes $verb <pid>..."
  for pid in "$@"; do
    [[ $pid =~ ^[0-9]+$ ]] || die "not a process: $pid"
  done
  for pid in "$@"; do
    kill "-$signal" "$pid" 2>/dev/null || failed=$((failed + 1))
  done
  (( failed < $# )) || die "could not $verb $*"
}

processes_cmd() {
  case ${1:-state} in
    state|poll) processes_state ;;
    # TERM and not KILL: a process asked to stop can save what it was doing,
    # and a settings window is not the place that decides it may not.
    end) shift; processes_signal TERM end "$@" ;;
    kill) shift; processes_signal KILL kill "$@" ;;
    renice) shift; [[ -n ${1:-} && -n ${2:-} ]] || die "usage: omacontrol processes renice <pid> <nice>"
      renice -n "$2" -p "$1" >/dev/null 2>&1 || die "could not renice $1" ;;
    *) die "usage: omacontrol processes state|poll|end <pid>...|kill <pid>...|renice <pid> <nice>" ;;
  esac
}
