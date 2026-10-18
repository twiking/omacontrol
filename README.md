# OmaControl

One window for every Omarchy setting, from Hyprland to your keybindings to tmux.

<p align="center"><img src="preview.png" alt="The OmaControl window" width="800"></p>

- **Find anything.** Type "blur" or "gaps" and every setting that touches it
  appears with its current value, whatever file it normally lives in.
- **Overview.** Opens on what needs you: a partition filling up, a peripheral
  about to run out of battery. The switches you reach for daily — night light,
  do not disturb, stay awake, dictation. What is waiting to update. And the
  latest from omarchy.org, checked every half hour, with a star on anything you
  have not read yet.
- **Packages.** What is installed, what is waiting, and how much it weighs —
  repositories and the AUR together. Plus the housekeeping nobody remembers:
  the package cache, orphans, and `.pacnew` files waiting to be merged.
- **Agent usage.** Where your coding agent's rate limits stand, what it spent
  over the last week, and which models it went to.
- **About.** What this machine is — model, CPU, GPU, memory, disk, kernel,
  compositor — as one block you can copy into a bug report.
- **Disk.** What is holding the space, every mount and how full it is, the
  drive's SMART health, and your snapshots. Mount a stick, trim the drive,
  take a snapshot.
- **Processes.** Per-core CPU, memory, load, and what is heaviest right now —
  sorted by CPU, memory or name. End something without leaving for a terminal.
- **Look and feel.** Theme, font, text size, gaps, borders, rounding, opacity,
  blur, shadows, animations and their speed, window group tabs, tiling layout.
- **The bar.** Position, transparency, which widgets sit where, and which
  plugins are enabled, plus add, remove and update them.
- **Workspaces.** Bind an application to a workspace or a display, open it
  there in the background, floating, pinned or fullscreen, start it when you
  log in, keep the screen awake or hide it from screen sharing. And set up the workspaces themselves: name,
  display, layout, kept when empty, borderless.
- **Keybindings.** Browse every binding you have, add your own, turn Omarchy's
  off, put them back. No Lua.
- **Compose keys.** Your `~/.XCompose` sequences as a list you can add to and
  remove from.
- **Input.** Keyboard layout, repeat rate, mouse and touchpad behaviour, and
  one device can differ from the rest.
- **Displays.** Resolution, refresh rate, scale, rotation, variable refresh,
  HDR where the display supports it, mirroring, brightness, and which screens
  are on — plus the arrangement, dragged into the shape they are on the desk.
  Settings follow the screen rather than the socket, so a display you have
  configured keeps what it was given when you plug it back in.
- **Applications.** Settings for tmux, Herdr and Neovim, written into their
  real configs.
- **The live stuff.** Audio, network, bluetooth and power, so those widgets can
  leave the bar, if you want more space for other widgets.
- **Undo.** Anything you changed is marked and goes back, one setting or all of
  them at once.

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

## Coming from OmaSettings

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

### Active-switch count

The gear counts Night light, Do not disturb and Stay awake by default.
If you use Omarchy's indicators for these modes, turn off
**Show active-switch count** in the widget's settings, or run:

```sh
omarchy bar set io.github.twiking.omacontrol showActiveSwitchCount false --json
```

Network and battery warnings still appear. The tooltip still lists every
active mode, including any you don't show in Omarchy's indicators. Set the
same option to `true` to restore the count.

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

Overview, Disk and Processes write nothing at all. They report, and where
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
| `tmux`, `nvim`, `herdr`      | Their own pages under Applications                    |
| `xkbcli`                     | Checking a keyboard layout compiles before writing it |
| `lsblk`, `df`                | Disk                                                  |
| `smartctl`, `snapper`        | The Disk page's health and snapshot panels             |
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
