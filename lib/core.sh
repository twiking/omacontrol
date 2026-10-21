# Part of OmaControl. Sourced by bin/omacontrol; not run on its own.
#
# Paths, and the handful of helpers every other module leans on: how a file is
# written, and the promise that a hand-written file is copied before it is
# first touched.

HOME_DIR=${HOME:?}
SHELL_JSON="${OMARCHY_SHELL_JSON:-$HOME_DIR/.config/omarchy/shell.json}"
STORE="${OMACONTROL_STORE:-$HOME_DIR/.config/omarchy/omacontrol.json}"
HYPR_DIR="${OMACONTROL_HYPR_DIR:-$HOME_DIR/.config/hypr}"
MANAGED_LUA="$HYPR_DIR/omacontrol.lua"
MANAGED_CONF="$HYPR_DIR/omacontrol.conf"
XCOMPOSE="${OMACONTROL_XCOMPOSE:-$HOME_DIR/.XCompose}"

MANAGED_MARKER="omacontrol:managed"

die() { echo "omacontrol: $*" >&2; exit 1; }

# A program's command line is readable by every user on the machine, through
# /proc/<pid>/cmdline, for as long as it runs. jq takes its variables there, and
# what this window hands it is often a document read from a private file:
# shell.json, with whatever tokens and keys a widget keeps in its settings; the
# store, which holds those settings while the widget is switched off; a
# plugin's remote, which can carry credentials. A marketplace review found the
# whole of shell.json going past that way on every state read.
#
# So no value reaches jq through argv. Each `--arg` and `--argjson` travels in
# the environment of that one jq process instead, which /proc shows to its own
# user alone, and is bound back to the same name at the head of the filter —
# `$ARGS.named` included. Callers go on writing `--arg name value`: a rule each
# of three hundred call sites has to remember is a rule the next one forgets.
#
# The options go first, then `--`, the program and its inputs, which is how
# jq reads them wherever they were written. An option short of its value is
# refused here rather than handed on, since handing on the original arguments
# would put every value before it back on the command line. So is a program
# that opens with `import` or `include`, which has to come before anything
# this could put in front of it, and an `-L` in a cluster; nothing here writes
# either.
#
# `env.X` rather than `$ENV.X`, because a caller may name a variable ENV. And
# `--argjson` that is not JSON fails when the filter runs, with status 5 rather
# than 2, and without echoing the value: checking it up front would cost a
# second jq for every one of them, and every caller only asks whether jq
# failed.
jq() {
  local -a options=() inputs=()
  local program='' have=false from_file=false bound='' named='' n=0 var no_more=false
  while (( $# )); do
    if ! $no_more && [[ $1 == -?* ]]; then
      case $1 in
        --arg|--argjson|--slurpfile|--rawfile)
          (( $# >= 3 )) || { echo "jq: $1 takes two parameters (e.g. $1 varname value)" >&2; return 2; }
          if [[ $1 == --slurpfile || $1 == --rawfile ]]; then
            options+=("$1" "$2" "$3")
          elif [[ $2 =~ ^[A-Za-z_][A-Za-z0-9_]*$ && $2 != __loc__ && $2 != ENV ]]; then
            var=OMACONTROL_JQ_VAR_$((n++))
            local -x "$var=$3"
            if [[ $1 == --arg ]]; then bound+="env.$var as \$$2 | "
            else bound+="(env.$var | try fromjson catch error(\"--argjson $2 is not JSON\")) as \$$2 | "; fi
            named+="${named:+, }$2: \$$2"
          fi
          # A name no filter could refer to, or one jq keeps for itself, is
          # dropped rather than carried.
          shift 3; continue ;;
        --indent|-L|--library-path)
          (( $# >= 2 )) || { echo "jq: error: $1 takes a parameter" >&2; return 2; }
          options+=("$1" "$2"); shift 2; continue ;;
        # A flag, as jq has it: the program is then read from the file the
        # first positional names, wherever the flag was written. Taken out of
        # a cluster too, so jq does not go on to read the program text as a
        # file name.
        -f|--from-file) from_file=true; shift; continue ;;
        --) no_more=true; shift; continue ;;
        -[!-]*L*)
          echo "jq: error: give -L on its own, not in $1" >&2; return 2 ;;
        -[!-]*f*)
          from_file=true
          [[ ${1//f/} != - ]] && options+=("${1//f/}")
          shift; continue ;;
        *) options+=("$1"); shift; continue ;;
      esac
    fi
    if ! $have; then program=$1 have=true; else inputs+=("$1"); fi
    shift
  done
  $have || { command jq "${options[@]}"; return; }
  if $from_file; then program=$(<"$program") || return 2; fi
  if [[ -n $bound && -n ${program//[[:space:]]/} ]]; then
    [[ $program =~ ^[[:space:]]*(import|include)[[:space:]] ]] \
      && { echo "jq: error: a program with import or include cannot take --arg here" >&2; return 2; }
    program="$bound(\$ARGS | .named += { $named }) as \$ARGS | $program"
  fi
  command jq "${options[@]}" -- "$program" "${inputs[@]}"
}

# The window is a long-lived shell process that retains and parses whatever a
# reader prints, so a producer that hangs or never stops is its problem too.
# Every read of the compositor or the system goes through here: bounded in
# time, and bounded in bytes before any of it is held.
OMACONTROL_READ_TIMEOUT=${OMACONTROL_READ_TIMEOUT:-5}
OMACONTROL_READ_MAX=${OMACONTROL_READ_MAX:-4194304}

# A pipe ends when the last writer closes it, not when the producer exits, and
# a command that backgrounds a daemon without redirecting it hands that daemon
# the pipe — Omarchy's nightlight toggle does, with hyprsunset. Waiting for the
# end then waits for the daemon, and the window, which runs one command at a
# time, stops answering. So the wait is for the producer, and the reader gets a
# moment to drain what it wrote; after that the answer is taken as it stands.
#
# The reader is never killed, and goes on swallowing whatever comes after the
# cap. A daemon left holding a pipe nobody reads dies of SIGPIPE on its next
# log line: hyprsunset did, a request after it was switched on. `stdbuf -o0`
# so what `head` has read is in the file when the wait gives up on it.
#
# Still a pipe, and not a file read afterwards: a file is only cut down once
# the producer is done, and `yes` fills a gigabyte of /tmp, which is memory,
# every fifth of a second. Past the cap it goes nowhere.
#
# The status is the producer's, as it was through `pipefail`, so a producer
# that failed is told apart from one that said nothing.
OMACONTROL_READ_DRAIN=${OMACONTROL_READ_DRAIN:-1}

read_bounded() {
  local how=$1 seconds=$2 out pipe reader drain rc
  shift 2
  out=$(mktemp) || return 1
  exec {pipe}> >(exec >/dev/null 2>&1; stdbuf -o0 head -c "$OMACONTROL_READ_MAX" >"$out"; exec cat)
  reader=$!
  if [[ $how == err ]]; then
    timeout "$seconds" "$@" >&"$pipe" 2>&1
  else
    timeout "$seconds" "$@" >&"$pipe" 2>/dev/null
  fi
  rc=$?
  exec {pipe}>&-
  sleep "$OMACONTROL_READ_DRAIN" >/dev/null 2>&1 &
  drain=$!
  wait -n "$reader" "$drain" 2>/dev/null
  kill "$drain" 2>/dev/null
  head -c "$OMACONTROL_READ_MAX" "$out"
  rm -f "$out"
  return "$rc"
}

capture() { read_bounded out "$OMACONTROL_READ_TIMEOUT" "$@"; }

# A directory walk is not a read, and five seconds is not its budget.
#
# Five seconds is right for anything on a poll — everything else on a live
# page re-runs every few seconds — but a walk of a home directory is asked
# once, nothing waits on it, and three million files take a minute of a cold
# cache however fast the drive is. Held to the read timeout it never finished
# on a real machine, so the answer was always "could not measure" and the
# space went on being reported as something else.
OMACONTROL_WALK_TIMEOUT=${OMACONTROL_WALK_TIMEOUT:-120}

capture_for() {
  local seconds=$1
  shift
  read_bounded out "$seconds" "$@"
}

# ---------------------------------------------------------- asked together
#
# A state read is two dozen independent questions put to the system — the
# theme, the plugins, the network, the battery, the keyboard — and nearly all
# of its time is spent waiting for each answer rather than working out any of
# them. Asked one after another they took two and a half seconds. Asked
# together they take as long as the slowest one alone.
#
# This is not a nicety. Every button in the window waits for a state read
# before anything on screen moves, so it is the difference between a window
# that answers and one that thinks about it.
#
# Two rules keep it safe. **Only reads go in here** — anything that writes runs
# before the block, or two of them race for the same file. And **a producer
# must not depend on another one's output**: what is derived from several
# answers is derived after they are all in.
par_begin() {
  PAR_DIR=$(mktemp -d) || return 1
}

# The name is the answer's; the rest is the question. A producer that fails
# leaves an empty file, which par_get reads as the fallback.
par_run() {
  local name=$1
  shift
  ( "$@" >"$PAR_DIR/$name" 2>/dev/null ) &
}

par_wait() { wait; }

# Bounded, like every other read here. The answers are ours, written into a
# directory only this process can see, so there is no name to be swapped
# underneath them — but they are the output of tools that can say more than
# anyone expected, and this is the last place their size is ours to limit
# before the shell that lives as long as the bar parses them.
par_get() {
  local file=$PAR_DIR/$1
  [[ -s $file ]] && head -c "$OMACONTROL_READ_MAX" "$file" && return
  printf '%s' "${2:-}"
}

par_end() {
  [[ -n ${PAR_DIR:-} ]] && rm -rf "$PAR_DIR"
  PAR_DIR=""
}

# Same bounds, but the tool's own complaint is what the caller is after: a
# validator that rejects a write has to be able to say why.
capture_err() { read_bounded err "$OMACONTROL_READ_TIMEOUT" "$@"; }

# Reading someone else's file means reading a name, and a name is not a
# promise: between the test and the open it can become a symlink somewhere
# else, a FIFO that never answers, or something far larger than a config. So
# the open happens first and every check is made against the descriptor, not
# the path. A config that is legitimately a symlink into a dotfiles repo still
# reads, because what is verified is that the descriptor is the regular file
# the path resolves to, and the read is bounded either way.
read_file() {
  timeout "$OMACONTROL_READ_TIMEOUT" sh -c '
    exec 3<"$1" || exit 1
    [ -f /dev/fd/3 ] || exit 1
    opened=$(stat -Lc "%d:%i" /dev/fd/3 2>/dev/null) || exit 1
    named=$(stat -Lc "%d:%i" -- "$1" 2>/dev/null) || exit 1
    [ "$opened" = "$named" ] || exit 1
    head -c "$2" <&3
  ' sh "$1" "$OMACONTROL_READ_MAX" 2>/dev/null
}

# The first time OmaControl writes to a file the user could have edited by
# hand, keep a copy of what was there. Only the first time: later writes must
# not overwrite the pristine backup with our own output.
# The backup path is predictable, so it is never written through: a symlink
# sitting there is treated as "already taken" rather than followed, and the
# copy is created exclusively by linking a fresh sibling into place.
backup_once() {
  local file=$1 bak tmp
  bak="$file.omacontrol.bak"
  [[ -e $file || -L $file ]] || return 0
  [[ -e $bak || -L $bak ]] && return 0
  tmp=$(mktemp "$file.omacontrol.bak.XXXXXX") || return 1
  # A file we cannot read as a bounded regular file is one we will not write
  # either: the caller aborts rather than changing something it could not copy.
  read_file "$file" >"$tmp" || { rm -f "$tmp"; return 1; }
  chmod --reference="$file" "$tmp" 2>/dev/null
  ln "$tmp" "$bak" 2>/dev/null
  rm -f "$tmp"
}

# Creating a config that is not there yet means creating a *file*: opening a
# FIFO for writing waits for a reader that never comes, and a device node at
# that path is not something a setting belongs in. Anything already there has
# to be a regular file, symlinked or not, or nothing is written at all.
ensure_regular_file() {
  local file=$1
  if [[ -e $file || -L $file ]]; then
    [[ -f $file ]] || return 1
    return 0
  fi
  mkdir -p "$(dirname "$file")" || return 1
  : >"$file"
}

# `managed` marks a file OmaControl generates in full: there is no
# hand-written version of it worth keeping a backup of.
write_file() {
  local file=$1 managed=${2:-} tmp target
  ensure_regular_file "$file" || return 1
  [[ -n $managed ]] || backup_once "$file" || return 1
  # A config symlinked into a dotfiles repo is a config, not a redirect to
  # refuse: the rename lands on what the link points at, so the link survives
  # and the repo sees the change. The resolved path has to be a regular file
  # for that to be true, which ensure_regular_file has already said.
  target=$(readlink -f -- "$file") && [[ -f $target ]] || target=$file
  mkdir -p "$(dirname "$target")"
  tmp=$(mktemp "$target.omacontrol.XXXXXX") || return 1
  cat >"$tmp" || { rm -f "$tmp"; return 1; }
  chmod --reference="$target" "$tmp" 2>/dev/null
  mv "$tmp" "$target"
}

lines_to_array() { jq -Rn '[inputs | select(length > 0)]'; }

# A reader that ends in `jq` cannot decide what it emitted from its own exit
# status. Under `pipefail` the status of `producer | jq` is the *producer's*
# failure, even when jq went on to make perfectly good JSON out of the nothing
# it was given — so `... | jq ... || echo '[]'` prints jq's answer *and* the
# fallback, and the two together are not JSON at all. That cost a page that
# worked in every test run by hand and failed the moment it was run through
# bin/omacontrol, which is the only place `pipefail` is set.
#
# So the value decides. What is emitted is what parses.
emit_json() {
  local value=$1 fallback=${2:-null}
  if jq -e . >/dev/null 2>&1 <<<"$value"; then printf '%s' "$value"
  else printf '%s' "$fallback"; fi
}
