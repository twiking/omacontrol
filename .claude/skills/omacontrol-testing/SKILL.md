---
name: omacontrol-testing
description: Verify an OmaControl change in the running Omarchy shell. Use after editing any .qml file or manifest.json — QML is compiled into the long-lived Quickshell process and is not hot-reloaded, so a change that has not been through `omarchy restart shell` has not been seen working. Covers the restart loop, reading QML errors out of the journal, Qt 6 qmllint against a baseline, driving the window with wtype, and screenshotting a page.
allowed-tools: Bash, Read, Grep, Glob
---

# Verifying a change in the running shell

## What actually needs a restart

Not everything, and the difference matters because a restart kills the user's
bar for about seven seconds.

| Changed | Live when |
| --- | --- |
| `*.qml` | only after `omarchy restart shell` — QML is compiled into the running process |
| `manifest.json` | only after a restart |
| `lib/*.sh`, `bin/omacontrol` | **immediately** — the window spawns `bash bin/omacontrol …` per call and `bin/omacontrol` re-sources every module at the top of each invocation |

The one exception on the last row: a long-lived watcher already running —
`audio watch` and `power watch` — holds the code it started with until its
page is closed and reopened. Close the page and come back, rather than
restarting the shell.

## The loop

```bash
.claude/skills/omacontrol-testing/scripts/verify.sh
```

Validates the manifest, runs `bash -n` over `lib/` and `bin/`, runs qmllint,
restarts the shell, opens the window, checks it **drew** rather than merely
opened, and prints what the journal said from before the restart onwards. It
exits non-zero if any of that failed.

Two things about it are deliberate:

- **The since-stamp is taken before the restart.** A QML error is printed
  while the shell is coming up, so a journal window measured afterwards misses
  exactly the errors it was opened to find.
- **It checks the layer's size, not just its existence.** A page that fails to
  load leaves the window blank with no other sign, and a blank window is a
  layer with the right namespace and nothing in it.

## qmllint, and why it is a baseline

```bash
.claude/skills/omacontrol-testing/scripts/lint-qml.sh            # what is new
.claude/skills/omacontrol-testing/scripts/lint-qml.sh --update   # re-record
```

The `qmllint` on `PATH` is Qt 5's and Quickshell is Qt 6: Qt 5's cannot parse
a typed function signature — `function show(): void`, which `IpcHandler`
requires — and exits 255 with no output when it meets one, so `Panel.qml` is
never linted by it and a clean run from it is worth nothing. The script uses
`/usr/lib/qt6/bin/qmllint` and links the `qs` import root Quickshell aliases.

Qt 6's emits about seven hundred findings on a clean tree, because it cannot
type the `Style` and `Color` singletons, the parent chain a row walks to reach
its page, or anything reached through a `Loader`'s `item`. Excusing those by
*category* was tried and removed 679 findings out of 679 — an undefined
identifier anywhere read as clean. So `qmllint-baseline.txt` records a
known-good tree and the script reports the difference. Regenerate it with
`--update` when a real fix removes findings, and read the diff before
committing it.

The authoritative check is still the shell loading the file. qmllint passes
nearly everything regardless of merit.

## Driving it from the keyboard

`wtype` types into whatever holds keyboard focus, and the window takes focus
exclusively while it is open — so check it is open before every burst:

```bash
hyprctl layers -j | jq -e '..|objects|select(.namespace?=="omacontrol")' >/dev/null \
  && wtype "/" && wtype "blur"
```

Skip that check and the keystrokes go to the terminal you are working in.

## Screenshotting a page

```bash
.claude/skills/omacontrol-testing/scripts/shot.sh [out.png]
```

The window is a **layer surface, not a client**, so its geometry comes from
`hyprctl layers` — `hyprctl clients` has no entry titled "OmaControl" and the
crop comes out empty. `grim -g` takes logical coordinates while a full `grim`
capture is physical pixels, so the script captures the window's monitor and
crops from that, with the scale read out of `hyprctl monitors` rather than
assumed. The layer's position is in the global layout and is taken relative
to its monitor first: on a monitor that is not at 0,0 the crop otherwise falls
outside the capture and the image comes out empty.

The layer covers its whole monitor, so the shot is the whole screen — the
card and whatever is behind it. The card's width comes from the theme's
spacing scale, which the script cannot see.

To reach a page without clicking, set `property string pageId` in
`SettingsWindow.qml` (it defaults to `"overview"`), restart, shoot, and **put
it back before committing**.

## Gotchas

- **`omarchy restart shell` kills the bar for about seven seconds.** On a
  machine someone is using, say so before you run it.
- **A `git` command run by hand inside any plugin directory closes the
  window.** The shell watches `~/.config/omarchy/plugins` with `inotifywait -m
  -r` and calls `reloadPlugins()` on any change under it. Rewind a plugin
  *before* opening the window, not after.
- **`Escape` with nothing focused closes the window, and so does `toggle` when
  it is already open.** Both will end a test half way through. `Escape` only
  clears the search when the search box has focus.
- **QML errors surface only in the journal.** Grep for `qml`, `not a type`,
  `non-existent property`, `binding loop`, `unable to assign` and
  `case mismatch` — a binding loop and an undefined reaching a QString contain
  no word "error" and were how an earlier version of `verify.sh` passed a
  broken build.
- **Before refactoring `lib/`, capture the state document** with
  `scripts/state-diff.sh capture` and compare afterwards. The document is the
  whole contract between the shell side and the window.
