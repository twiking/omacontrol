# OmaControl

An Omarchy shell plugin: one window for the settings that otherwise live
scattered across `~/.config/omarchy/shell.json`, the Hyprland config, the
per-application configs, and `~/.XCompose`.

It runs inside `omarchy-shell` — a single long-lived Quickshell (QML) process
that also draws the bar. There is no separate app: the plugin's service loads
the window on first use.

## Layout, and what each part may know

```
manifest.json          Plugin manifest — id, kinds, entry point
Panel.qml              The bar button; forwards show/hide/toggle to the service
Service.qml            Owns the window (loaded on first use), the `omacontrol`
                       IPC target, and the launcher entry
PowerService.qml       The always-on half: enforces the sleep and hibernate
                       timeouts and the lid action while the window is closed
SettingsWindow.qml     Window chrome, sidebar, page routing, and the state
                       every page reads. Pages reach it as `app`.
ui/                    Presentational components + the Palette singleton
                       NavRow is the base: one row the cursor can land on.
                       SettingRow and the table rows are layouts on top of it.
sections/              One file per page
bin/omacontrol         Subcommand routing
lib/                   One module per thing being configured
```

Three rules keep the split honest:

- A `ui/` component knows how a control looks and reports what happened
  through a **signal**. It never knows which setting it is editing, and never
  reaches back into the window.
- A `sections/` page knows what its settings mean and calls `app` to read and
  write them. It never shells out.
- `lib/` shells out. It never knows what any of it looks like.

When a page needs something new, the value goes into `lib/state.sh`'s single
JSON document and a getter goes on the window; the page reads `app.something`.

## The five laws

These apply to every change. Everything else is in `.claude/rules/`, which
loads itself when you open a file it covers.

**1. Never parse and rewrite a hand-written config.** That is how a settings
app eats someone's setup. Every file we touch is one of three patterns:
generated wholly by us (`~/.config/hypr/omacontrol.lua`, or
`omacontrol.conf`), a marked block
inside their file (`bindings.lua`), or edited in place one value at a time
(`herdr/config.toml`, `tmux.conf`, `options.lua`). On top of that:
`backup_once` copies a hand-written file before the **first** write and never
again, and every format is validated in its own terms and rolled back on
failure. Full rules: `.claude/rules/other-peoples-files.md`.

**2. A QML change is not done until the shell has been restarted.** QML is
compiled into the long-lived Quickshell process and is not hot-reloaded, and a
page that fails to load leaves the window blank with no other sign — so a
`.qml` or `manifest.json` change that has not been through
`omarchy restart shell` has not been seen working and **must not be reported
as done**. Run `/verify`.

`lib/` and `bin/` are different and it is worth knowing which: the window
spawns `bash bin/omacontrol …` per call and `bin/omacontrol` re-sources every
module at the top of each invocation, so a shell change is live on the next
call. The exception is a watcher already running — `audio watch`,
`power watch` — which holds its code until its page is closed and reopened.

**3. Prefer Omarchy's own commands to reimplementing them.** They usually know
something you don't — `omarchy-bluetooth-power` clears an rfkill soft block
rather than setting BlueZ's `Powered`, because BlueZ forgets across reboots
and rfkill doesn't. Before building a page over something the bar already
shows, read the widget and use the same source, filter and labels.

**4. Theme first, always.** Never hardcode a colour in a page. Every surface
is an alpha over the theme's own foreground or accent, expressed in
`ui/Palette.qml`, so a Catppuccin desktop and a Gruvbox one each get the
design in their own colours.

**5. Comments say why, never what.** If a line explains the mechanics of the
code beside it, delete it. The ones worth writing record a decision, a
constraint, or a trap — an unbind before a bind so the override wins; the last
tmux assignment being the one that counts; reading the address from the Wi-Fi
device because the default route points at a VPN tunnel. User-facing strings
follow the same discipline in reverse: they say what a setting does for the
reader, never which command runs underneath.

## The Power page

The timeouts group moved here from the Lockscreen page (the menu entry renamed
from "Idle & Lock"), and the page gained three things Omarchy does not do
itself.

**Sleep and hibernate timeouts.** Omarchy's idle service reads only
`idle.screensaver` and `idle.lock` from shell.json, so `idle.suspend` and
`idle.hibernate` (0 is off) are enforced by the plugin's own always-on
`PowerService.qml`: an inhibitor-aware IdleMonitor — the same one Omarchy's
idle service uses — arms one timer per timeout, and the earlier deadline
wins, because a suspended machine never reaches the later one; the sibling
timer is stopped when one fires, so an overdue timer cannot fire the moment
the machine wakes. Stay Awake (`~/.local/state/omarchy/indicators/stay-awake`)
pauses the timers, as it pauses Omarchy's own. The service reads shell.json
itself, because the scoped shell API hands a third-party service no live
shell config. Availability is checked before a row is enabled — logind's
CanSuspend, Omarchy's own `omarchy-hibernation-available`, which is also what
Omarchy's menu offers, and `omarchy-hw-laptop` for the lid — and an
unavailable row is greyed out with a tooltip saying so.

**The lid action.** `omacontrol.lid` in shell.json: nothing, lock, suspend or
hibernate, with an absent key meaning suspend — Omarchy's default. logind's
lid action is suspend by default, so for every action but suspend the service
holds a `handle-lid-switch` inhibitor — one process, `systemd-inhibit`
wrapping a `gdbus` monitor on logind — and acts on the lid itself, which
today means hibernate only: lock and nothing are Omarchy's own lid binding
and its managed replacement. Only "nothing" needs that binding gone (it locks
the moment the lid closes), so the setter renders a second marked block in
`bindings.lua` — an `hl.unbind` of Omarchy's lid binding plus a rebind to
`omarchy-hyprland-monitor-clamshell` alone — and removes it for any other
action. A docked lid close is clamshell mode, so the hibernate skips it, the
way logind's own HandleLidSwitchDocked defaults to ignore. The setting is
tracked like any shell.json value: reset returns to Omarchy's default.

**Charge limits.** The battery's own sysfs thresholds,
`charge_control_end_threshold` (stop charging at) and
`charge_control_start_threshold` (begin charging below). They are root-owned
almost everywhere, so the write goes through `pkexec tee`, answered by
Omarchy's own polkit agent; the bound (`OMACONTROL_PKEXEC_TIMEOUT`, 60s) is
what keeps a machine with no agent from hanging the window. A direct write is
tried first, for setups that make the files user-writable. The kernel refuses
a start threshold at or above the end one, so lowering the end threshold
takes the start one down with it (by 5), and raising the start above the end
is refused. The thresholds are live values, not tracked ones — the page's
readings, profile and charge limit move on their own, so "you changed this"
would be a guess — and the limit does not survive a reboot, which the group's
note says. The page's timeouts and lid action are shell.json settings, and
are marked like any other.

## Where each page writes

This app stores almost nothing. Each page writes into whatever owns the
setting:

| Page | Lands in |
| --- | --- |
| Windows, Layout, Effects, Groups, Keyboard, Mouse & touchpad, Workspaces | `~/.config/hypr/omacontrol.lua`, loaded last (`omacontrol.conf` on a `.conf` setup) |
| Appearance | Omarchy's own config, via `omarchy-theme-set`, `omarchy font set`, `omarchy display text size` |
| Bar, Lockscreen, Plugins, Settings | `~/.config/omarchy/shell.json` (Plugins also *reads* plugins.omarchy.org, cached) |
| Keybindings | a marked block in `~/.config/hypr/bindings.lua` |
| Compose Keys | `~/.XCompose` |
| Herdr, Tmux, Neovim | their own configs, edited in place |
| Displays | `~/.config/hypr/omacontrol.lua`, applied with `hyprctl eval` — plus `monitors.lua` for the laptop panel's scale, and Omarchy's own toggle for turning that panel off |
| Power | `~/.config/omarchy/shell.json` (sleep/hibernate timeouts, lid action) and the battery's sysfs charge thresholds, written through polkit — its readings and profile are live state, owned by UPower and power-profiles-daemon |
| Audio, Network, Bluetooth | nowhere — live system state, owned by PipeWire, NetworkManager and BlueZ |
| Overview | nowhere — every switch is Omarchy's own command, asked and relayed |
| Disk, Processes | nowhere — readings, plus the two or three things there are to *do* |

**Most of the store is not settings** — `hypr`/`hyprOriginal`, `written`,
`devices`, `monitors`, `bindings` and `extras` exist to say what changed and
put it back. The exceptions own themselves and nothing else holds them:
`windowRules`, `workspaceRules`, `barHidden`, `newsRead`, `newsSeeded`,
`dismissed`, `monitorsSchema`.

## The loop

`/verify` runs it: validate the manifest, `bash -n` over `lib/` and `bin/`,
qmllint against a recorded baseline, restart the shell, open the window, check
it **drew** rather than merely opened, and read the journal from before the
restart onwards.

QML errors surface **only** in the journal, and the ones that matter here do
not contain the word "error" — a binding loop, an undefined reaching a
QString, a page that failed to load, an ambiguous import reported as "File name
case mismatch".

`lib/` honours env overrides so writes can be aimed at a sandbox
(`OMACONTROL_STORE`, `OMACONTROL_HYPR_DIR`, `OMACONTROL_XCOMPOSE`,
`OMACONTROL_HERDR_CONFIG`, `OMACONTROL_TMUX_CONFIG`, `OMACONTROL_NVIM_OPTIONS`,
`OMACONTROL_BINDINGS_LUA`, `OMARCHY_SHELL_JSON`) — but **redirecting the file
does not redirect the system**: a sandboxed Hyprland write still reaches the
running compositor through `hyprctl eval`. To see what a write *produces*
without performing one, read `render_managed_lua`.

## Where the rest lives

`.claude/rules/` — path-scoped; each loads when you open a file it covers.

| Rule | Covers |
| --- | --- |
| `other-peoples-files.md` `shell.md` `changed-and-reset.md` `omarchy-commands.md` | `lib/`, `bin/` |
| `hyprland.md` `displays.md` `workspaces.md` | the compositor, monitors, window rules |
| `reporting-pages.md` `news.md` `bar-and-plugins.md` | the pages that report, the feed, the bar and plugin lifecycle |
| `qml.md` `navigation.md` `design.md` `search.md` | anything the reader sees or types at |
| `migration.md` | `bin/omacontrol-migrate` |

A path-scoped rule fires when Claude **reads** a matching file with the Read
tool. **`sed`, `cat`, `python3` and a heredoc do not count**, and that is not a
detail: in bypass-permissions mode the harness asks for shell tools by
preference, so every rule in that table silently stops being delivered exactly
when the most code is being written fastest.

It has already cost something. `design.md` has said "a note earns its place by
adding a fact you cannot see" since before the Plugins page was rewritten; the
rewrite went in through `python3` heredocs, the rule never loaded, and the
table shipped with three lines of legend explaining a heart icon to the reader.

So: **before the first edit to a path in that table, `cat` the rules it names**
— not after, and not only when something feels uncertain. The rules exist
because these mistakes are not the kind that feel uncertain while you are
making them. Two in particular do not announce themselves:

- `design.md` for anything with a word of user-facing copy in it. Notes,
  descriptions, headings, chip labels, empty states.
- `shell.md` for anything in `lib/`, for the `pipefail` and `index(.)` traps
  that pass every test run by hand.

`.claude/skills/` — `omacontrol-testing` (verify a change in the running
shell), `omacontrol-new-page` (add a page end to end), `omacontrol-setting`
(add a setting that writes into someone else's config).

`.claude/commands/` — `/verify`, `/lint`, `/page-shot`, `/state-diff`.

`.claude/agents/` — `omacontrol-reviewer` reviews a diff against these laws;
`devils-advocate` argues the other side of a plan or a piece of work.
