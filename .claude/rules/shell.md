---
paths:
  - "lib/*.sh"
  - "bin/*"
---

# Shell conventions

> **Read this when:** you write or change anything in `lib/` or `bin/`.

## Shell conventions

Bash with `set -uo pipefail` (not `-e`; several reads exit non-zero normally).
`jq` for all JSON.

**`... | jq ... || echo '[]'` is a bug under `pipefail`.** The status of
`producer | jq` is the *producer's* failure, even when jq went on to make
perfectly good JSON out of the nothing it was given — so the fallback fires
*as well*, and jq's answer with `[]` stapled to it is not JSON at all. It fails
only when run through `bin/omacontrol`, which is the one place `pipefail` is
set, so it passes every test run by hand. Use `emit_json "$(...)" '[]'` from
`core.sh`: the value decides, not the exit status.

Two `jq` habits worth remembering:

- Inside `($list | index(.x))` the `.` is now `$list` — bind the value first
  (`. as $row | ... index($row[1])`) or every row matches.
- Building a whole file as one string in `awk` (`out = out c`) is quadratic;
  scan per line. That cost 3 seconds of a 3.4-second window open once.

**Every command's output goes through `stdbuf -o0 head -c`, and the `stdbuf`
is load-bearing.** GNU `head` holds what it reads in stdio's block buffer, so
for as long as `bin/omacontrol` ended in a bare `head -c`, the watchers
(`audio watch`, `power watch`, `overview watch`) printed each change
at once and the window received none of it until the buffer filled or the
watcher died. Every test that runs a watcher to completion passes either way;
only reading its first line while it is still running shows the difference.

**A pipe ends when its last writer closes it, not when the producer exits.**
A command that backgrounds a daemon without redirecting it hands the daemon
the pipe, and a reader waiting for the end waits for the daemon.
`omarchy-toggle-nightlight` does it with hyprsunset; through a bare
`cmd | head -c` the window stopped answering every click after it. `capture`
waits for the producer instead, gives the reader a second to drain, and then
**leaves it running** — a daemon whose pipe has no reader dies of SIGPIPE on
its next write, which is what killed hyprsunset the first time this was
fixed. A command you know can start a daemon gets `>/dev/null 2>&1` anyway,
in or out of `capture`: it costs that second, and outside `capture` it holds
`bin/omacontrol`'s own output open.

## Two budgets, and which one a read gets

Every read of the compositor or the system goes through `capture`, bounded by
`OMACONTROL_READ_TIMEOUT` (5 s) and `OMACONTROL_READ_MAX` — the window is a
long-lived process that retains and parses whatever a reader prints, so a
producer that hangs or never stops is its problem too.

**A directory walk is not a read.** `capture_for` and `OMACONTROL_WALK_TIMEOUT`
(120 s) are its budget. Held to the read timeout, the Disk breakdown never
finished on a real machine and reported `null` — which the page then showed as
a slice going missing rather than as a measurement that failed. Nothing waits
on a walk, so the longer ceiling costs only a note on screen while it runs.
The full story is in `.claude/rules/reporting-pages.md`.
