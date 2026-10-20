---
paths:
  - "lib/{core,store,setters,hypr,devices,monitors,shell_config,bindings,compose,themes,tmux,neovim,herdr}.sh"
  - "SettingsWindow.qml"
---

# Changed, and putting back

> **Read this when:** you add a setting that has to show a change mark, or you touch `setting_reset`, `.written`, `.hyprOriginal` or the reset-all path.

## Changed, and putting back

"Changed" means the value differs from what the setting was before this window
first wrote it — not merely that the window wrote it. A switch flipped and
flipped back is not a change, and must stop saying it is.

Three kinds of change, three ways back:

- **A Hyprland key** is an override: drop it and the value comes from wherever
  it came from before — Omarchy, the theme, a hand-written `looknfeel.lua`.
  A **per-device** setting is the same shape; clearing it hands the device back
  to the global one, so the store is the whole record and no original is kept.
- **A value in someone else's config** — theme, font, text size, the bar, the
  idle timeouts, tmux, Neovim, Herdr, a monitor scale — has no unset state.
  The way back is the value found before the first write, kept in `.written`
  under a key naming what it configures (`tmux:mouse`, `device:<name>:<opt>`,
  `monitor:<display-key>:<field>` — where the display key is what the display
  says about itself, not the connector it happens to be in). Hyprland keys keep
  theirs in `.hyprOriginal`.
- **A list you add to** — compose entries, keybindings — is not a setting with
  a default at all. Those rows carry Remove, Turn off and Restore, which is
  what a thing you created wants rather than a reset.

The window shows one mark for all of them, because from the outside they are
the same thing: you changed it, and it can go back. `Ctrl+Backspace`, or
**Undo all** beside the changed count in the window header, puts back
everything at once, after asking — the one action here a second click cannot
undo.

The live pages are deliberately unmarked: audio, network, bluetooth and the
Power page's readings, profile and charge limit move on their own, so "you
changed this" would be a guess. The Power page's timeouts and lid action are
shell.json settings, and are marked like any other.

Three things this will not forgive:

- **Read the previous value before the write.** Read after, and the recorded
  original is the value it has just become.
- **Read it with `has()`, never `//`.** jq's alternative operator treats
  **false** as empty, so every switch that starts off reads its original back
  as null and never matches. This bit twice: Shadow, Blur and Glow went on
  claiming a change after being turned off again.
- **Restoring writes the value found at the first change.** If a theme has
  moved text size since, the reset puts back the older number, not the theme's.
  A key written before any of this existed has no original at all, and stays
  marked until reset once.

