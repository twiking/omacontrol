# OmaControl

One window for every Omarchy setting and the machine underneath it: Hyprland,
keybindings and themes, alongside Wi-Fi, Bluetooth, disks, processes and
packages.

<p align="center"><img src="preview.png" alt="The OmaControl window, open on the Overview page" width="600"></p>

Omarchy's settings live in a dozen places: `shell.json`, the Hyprland config,
each application's own config, `~/.XCompose`, and a long list of commands.
OmaControl puts them in one window, alongside the live state of the machine —
audio, network, bluetooth, power, disks and processes — so a few widgets can
leave the bar if you want the space for others.

- **Find anything.** Type "blur" or "border" and every setting that touches it
  appears with its current value, whatever file it normally lives in.
- **Undo.** Anything you changed is marked, and goes back one setting at a time
  or all at once.
- **Keyboard first.** Arrows or `j`/`k` move, `h`/`l` change a value,
  `Alt`+arrows change page, `/` searches, `Esc` closes.

<p align="center"><img src="docs/screenshots/search.png" alt="Searching for border: matching settings on the Windows and Configs pages, changed ones marked with a reset link" width="600"></p>

## Everything in the menu

The sections below follow the sidebar, top to bottom. Click a screenshot for
the full size.

<table>
<tr>
<td width="50%" valign="top">
<a href="preview.png"><img src="preview.png" alt="Overview page"></a><br>
<b>Overview</b><br>
Opens on what needs you: a partition filling up, a peripheral about to run
out of battery. The switches you reach for daily — night light, do not
disturb, stay awake, dictation. What is waiting to update. And the latest from
omarchy.org, checked every half hour, with a star on anything you have not
read yet.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/network.png"><img src="docs/screenshots/network.png" alt="Network page"></a><br>
<b>Network</b><br>
The connection you are on and how it is doing: addresses, signal, channel,
traffic, ping to the router, and a warning when something else is crowding
the channel. Join another network, share this one as a QR code, run a speed
test, pick the Wi-Fi band and DNS provider, and see the hosts file.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/bluetooth.png"><img src="docs/screenshots/bluetooth.png" alt="Bluetooth page"></a><br>
<b>Bluetooth</b><br>
Connected devices with their battery, the ones you have paired, and
everything nearby. Connect, pair and forget, and let other devices find
this one.
</td>
<td width="50%" valign="top"></td>
</tr>
</table>

### Experience

<table>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/appearance.png"><img src="docs/screenshots/appearance.png" alt="Appearance page, on the theme picker"></a><br>
<b>Appearance</b><br>
Theme, font and text size, and wallpaper, each picked from previews. Plus
branding: the text or image on the screensaver and the About screen.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/effects.png"><img src="docs/screenshots/effects.png" alt="Effects page"></a><br>
<b>Effects</b><br>
Blur, shadows and the glow around the focused window, down to every knob
Hyprland has for them.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/bar.png"><img src="docs/screenshots/bar.png" alt="Bar page"></a><br>
<b>Bar</b><br>
Position, transparency, which widget the centre is anchored on, and which
widgets sit left, centre and right — moved, added, disabled and spaced out.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/windows.png"><img src="docs/screenshots/windows.png" alt="Windows page, on the general settings"></a><br>
<b>Windows</b><br>
Gaps, borders, rounding, snapping, opacity, dimming and animations. The
tiling layout — dwindle, master or scrolling — and how each one splits. And
window groups: the tab bar's height, titles, rounding and gradients.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/workspaces.png"><img src="docs/screenshots/workspaces.png" alt="Workspaces page"></a><br>
<b>Workspaces</b><br>
Bind an application to a workspace or a display, open it there in the
background, floating, pinned or fullscreen, start it when you log in, keep
the screen awake or hide it from screen sharing. And set up the workspaces
themselves: name, display, layout, kept when empty, borderless.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/keyboard.png"><img src="docs/screenshots/keyboard.png" alt="Keyboard page, on the keybindings"></a><br>
<b>Keyboard</b><br>
Layouts, variant, options and repeat rate, with one keyboard allowed to
differ from the rest. Browse every keybinding you have, add your own, turn
Omarchy's off and put them back, with no Lua. And your <code>~/.XCompose</code>
sequences as a list you can add to and remove from.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/mouse-and-touchpad.png"><img src="docs/screenshots/mouse-and-touchpad.png" alt="Mouse and touchpad page"></a><br>
<b>Mouse & touchpad</b><br>
Sensitivity, acceleration, focus follows mouse, natural scrolling, tap to
click, two-finger right click, disable while typing and scroll speed — and
one device can differ from the rest.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/sound.png"><img src="docs/screenshots/sound.png" alt="Sound page"></a><br>
<b>Sound</b><br>
Volume and mute for output and input, and which device each one uses.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/displays.png"><img src="docs/screenshots/displays.png" alt="Displays page"></a><br>
<b>Displays</b><br>
Resolution, refresh rate, scale, rotation, variable refresh, HDR where the
display supports it, mirroring, brightness, and which screens are on — plus
the arrangement, dragged into the shape they are on the desk. Settings follow
the screen rather than the socket, so a display you have configured keeps
what it was given when you plug it back in.
</td>
<td width="50%" valign="top"></td>
</tr>
</table>

### System

<table>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/power.png"><img src="docs/screenshots/power.png" alt="Power page"></a><br>
<b>Power</b><br>
The battery's charge, health and charge cycles, and the power profile to run
at on battery and plugged in.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/idle-and-lock.png"><img src="docs/screenshots/idle-and-lock.png" alt="Idle and Lock page"></a><br>
<b>Idle & Lock</b><br>
How long before the screensaver starts and the screen locks, and the
animation shown at start-up and while unlocking.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/security.png"><img src="docs/screenshots/security.png" alt="Security page"></a><br>
<b>Security</b><br>
Which incoming connections the firewall lets in, from where, and what is
listening behind them. Set up a fingerprint reader, a FIDO2 key or the SSH
server.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/storage.png"><img src="docs/screenshots/storage.png" alt="Storage page"></a><br>
<b>Storage</b><br>
What is holding the space, every mount and how full it is, swap, the drive's
SMART health, and your snapshots. Mount a stick, or take a snapshot.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/processes.png"><img src="docs/screenshots/processes.png" alt="Processes page"></a><br>
<b>Processes</b><br>
Per-core CPU, memory, load, what is heaviest right now, and every process as
a tree. End something without leaving for a terminal.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/date-and-time.png"><img src="docs/screenshots/date-and-time.png" alt="Date and Time page"></a><br>
<b>Date & Time</b><br>
The timezone, and whether the clock is synchronised — with a resync when it
is not.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/about.png"><img src="docs/screenshots/about.png" alt="About page"></a><br>
<b>About</b><br>
What this machine is — model, CPU, GPU, memory, disk, kernel, compositor —
as one block you can copy into a bug report. When it was last updated, and
the release channel it follows.
</td>
<td width="50%" valign="top"></td>
</tr>
</table>

### Apps & Packages

<table>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/default-apps.png"><img src="docs/screenshots/default-apps.png" alt="Default Apps page"></a><br>
<b>Default Apps</b><br>
The browser, terminal, editor and coding agent everything else opens. One
you have not installed yet is set up the first time you pick it.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/apps.png"><img src="docs/screenshots/apps.png" alt="Apps page"></a><br>
<b>Apps</b><br>
Every application in the launcher, with its version, the workspace it opens
on, whether it starts at login and what it is the default for. Make a new
web app or terminal app, or uninstall one.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/packages.png"><img src="docs/screenshots/packages.png" alt="Packages page"></a><br>
<b>Packages</b><br>
What is installed, what is waiting, and how much it weighs — repositories
and the AUR together. Open a package for why it is here and what needs it,
remove one or several at once, and update everything in one press.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/plugins.png"><img src="docs/screenshots/plugins.png" alt="Plugins page"></a><br>
<b>Plugins</b><br>
Your shell plugins and the ones built into Omarchy: switch them on and off,
update them, remove them, and add new ones from plugins.omarchy.org.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<a href="docs/screenshots/usage.png"><img src="docs/screenshots/usage.png" alt="Agent usage page"></a><br>
<b>Usage</b><br>
Where your coding agent's rate limits stand, what it spent over the last
week, and which models it went to.
</td>
<td width="50%" valign="top">
<a href="docs/screenshots/configs.png"><img src="docs/screenshots/configs.png" alt="Configs page, on tmux"></a><br>
<b>Configs</b><br>
Settings for Herdr, tmux and Neovim, written into their real configs, with a
way into the rest of each file for anything the page does not cover.
</td>
</tr>
</table>

## Why I built it

I wanted a fast overview of everything I could change, and an easier way to find
out which settings Hyprland actually has. Easier management of keybindings and
`~/.XCompose` was the other part.

Dropping a few widgets like audio from the bar frees space for ones I get more
out of. And hopefully someone else finds it useful too.

## Install

```sh
omarchy plugin add https://github.com/twiking/omacontrol.git --enable
```

## Languages

The window speaks the language chosen under Setup > Language, the same way the
shell does. Each language is one file — `i18n/fr.json` here — layered over
`i18n/en.json`, so a string that is not translated yet falls back to English
one string at a time, and switching language re-renders the window without a
restart. French ships with it. Adding a language is one JSON file; plural
entries are plain objects keyed by CLDR category.

## Migrate from OmaSettings

Install OmaControl beside it and restart the shell:

```sh
omarchy plugin add https://github.com/twiking/omacontrol.git --enable
omarchy restart shell
```

Open OmaControl. The Overview page says your OmaSettings settings have not
come across yet; press **Bring them over**. A few seconds later every setting
you made in OmaSettings is marked as changed, and "Undo all" can put each one
back. If the shell reloads its plugins meanwhile, the window closes and comes
back on its own.

OmaControl is the same window renamed, but a rename is not free for a program
that writes into other people's files. Six things on disk carry the old name —
the store of what you changed and what it was before, the generated Hyprland
file, the `require` line that loads it, the marked block in `bindings.lua`, the
`.bak` copies of your originals, and the bar slot the gear sits in — and the
new window recognises none of them until they are renamed. The gear keeps its
place in the bar, and OmaSettings is switched off but left installed;
`omarchy plugin remove io.github.twiking.omasettings` removes it.

Every original is copied into `~/.local/state/omacontrol/migration-<time>/`
first, with an `undo.sh` beside them, so the whole thing is one command to
reverse.

The offer is only made before you change anything in OmaControl: a change gives
it a store of its own, and bringing the old one over would overwrite it. To
see the plan or run it from a terminal instead:

```sh
P=~/.config/omarchy/plugins/io.github.twiking.omacontrol
$P/bin/omacontrol-migrate            # prints what would change, changes nothing
$P/bin/omacontrol-migrate --apply    # carries it out
```

## Usage

Click the gear in the bar to open the window, or find it in the launcher as
OmaControl.

### The badge on the gear

By default the gear shows a badge for three things:

- **No network:** a click opens Network.
- **Battery at 10 % or under**, for the laptop or a Bluetooth device: a click
  opens Power or Bluetooth.
- **How many of Night light, Do not disturb and Stay awake are on.**

If your bar already shows any of these, turn that part off in
**OmaControl → Settings**, or from a terminal:

```sh
omarchy bar set io.github.twiking.omacontrol showActiveSwitchCount false --json
omarchy bar set io.github.twiking.omacontrol showNetworkWarning false --json
omarchy bar set io.github.twiking.omacontrol showBatteryWarnings false --json
```

Hovering over the gear still lists everything, whatever the badge shows. Set an
option back to `true` to bring that part of the badge back.

## How it writes

Your config files are never parsed and rewritten, since that is how a settings
app eats someone's setup. Instead:

- **Hyprland settings** are applied live with `hyprctl eval` and written to a
  file of its own, `~/.config/hypr/omacontrol.lua`, loaded last from a single
  `require` line appended to your `hyprland.lua`. Your own files keep saying
  exactly what you wrote.
- **Keybindings** live in a marked block in `bindings.lua`. Everything outside
  the markers is copied through untouched.
- **Everything else**, meaning Herdr, tmux and Neovim, is edited one value at a
  time, in place, keeping the comment attached to the line it belongs to.

Overview, Storage and Processes write nothing at all. They report, and where
there is something to *do* they hand off to the command that owns it — the same
`omarchy-toggle-nightlight` the bar uses, `udisksctl` for a mount, `snapper` for
a snapshot. That is why those pages cannot disagree with the bar.

Before the first write to any file you could have written yourself, a copy is
kept beside it as `<file>.omacontrol.bak`. Every write is checked in the
format's own terms, with `herdr config check`, by compiling the Lua, or by
applying the tmux option, and rolled back if it fails.

## Requirements

| Tool                         | Needed for                                            |
| ---------------------------- | ----------------------------------------------------- |
| `jq`                         | Everything, it does every read and write              |
| `pactl`                      | Audio                                                 |
| `nmcli`                      | Network                                               |
| `bluetoothctl`               | Bluetooth                                             |
| `upower`, `powerprofilesctl` | Power                                                 |
| `timedatectl`                | Date & Time                                           |
| `tmux`, `nvim`, `herdr`      | Their own pages under Configs                         |
| `xkbcli`                     | Checking a keyboard layout compiles before writing it |
| `lsblk`, `df`                | Storage                                               |
| `smartctl`, `snapper`        | The Storage page's health and snapshot panels         |
| `top`                        | Processes                                             |
| `checkupdates`, `expac`      | Packages                                              |
| `yay`                        | AUR updates on the Packages page                      |
| `fastfetch`                  | About                                                 |
| `curl`                       | The news list on Overview                             |

Only `jq` is required. A page whose tool is missing says so instead of failing.
Nothing here needs root, and nothing is installed on your behalf.

## Remove

```sh
omarchy plugin remove io.github.twiking.omacontrol
```

The launcher entry it wrote is deleted with it.

## License

MIT, see [LICENSE](LICENSE).
