---
description: Screenshot the screen the OmaControl window is open on
argument-hint: "[output path]"
allowed-tools: Bash(cd:*), Bash(.claude/skills/omacontrol-testing/scripts/shot.sh:*), Bash(omarchy-shell omacontrol:*), Read
---

Capture the window:

!`cd "${CLAUDE_PROJECT_DIR:-$PWD}" && .claude/skills/omacontrol-testing/scripts/shot.sh "$ARGUMENTS" || true`

If it says the window is not open, open it with `omarchy-shell omacontrol show`
and try again. Then read the image and describe what is on it.

To reach a page without clicking, set `property string pageId` in
`SettingsWindow.qml`, restart the shell, shoot, and **set it back to
`"overview"` before committing**.
