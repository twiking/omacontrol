---
paths:
  - "lib/{plugins,shell_config}.sh"
  - "sections/{Bar,Plugins,Idle}Section.qml"
  - "Panel.qml"
  - "Service.qml"
  - "manifest.json"
  - "omacontrol.desktop"
---

# The bar layout, and the plugin the window lives in

> **Read this when:** you touch `lib/plugins.sh`, `lib/shell_config.sh`, `sections/BarSection.qml`, `sections/PluginsSection.qml`, `Service.qml`, `Panel.qml`, `manifest.json` or `omacontrol.desktop`.

## The service owns the window

Omarchy counts a plugin as enabled when its id appears anywhere in
`shell.json` — a `bar.layout` entry or a `plugins[]` entry. When the bar
widget hosted the window, taking the gear out of the bar was the same thing as
uninstalling: the `omacontrol` IPC target answered "Target not found", the
launcher entry was deleted, and a hotkey bound to it stopped working.

So `Service.qml` holds the window, its `Loader` and the `IpcHandler`; the
shell keeps a service alive for as long as the plugin is enabled, however it
was enabled. `Panel.qml` is only the button: it looks the service up through
`bar.shell.serviceFor()` and forwards to it, keeping `open`/`close`/`opened`
so `Bar.findPanelWidget` still routes `shell summon` through it. One window
also means one window on a two-monitor setup, where each bar instance used to
carry its own.

The shell tears services down on `reloadPlugins()` as well as widgets, so the
Plugins page's summon-back dance below is still needed.

## The count on the gear

The gear carries a badge counting which of the Overview page's switches are
on — night light, do not disturb, stay awake — and its tooltip names them.
With no network at all the badge shows Wi-Fi-off instead, and a click opens
the window on the Network page. "No network" is NetworkManager's overall
state, not the Wi-Fi radio's: a docked laptop on a cable has no Wi-Fi and is
online, and a mark there would be a false alarm every day it is docked.
Below that, the laptop's own battery, by Omarchy's rule for its "Time to
recharge!" warning — present, on battery, discharging, at 10 % or under — shows
a battery-alert mark and the click opens the Power page. That one is read from
Quickshell's UPower module in `Panel.qml`, as Omarchy's battery service reads
it: the module is live and not gated, so it needs no watcher. Below that, a
Bluetooth device under 10 % shows the Bluetooth variant of the mark and the
click opens the Bluetooth page. The list is the Overview page's own
"nearly flat" notices, so the page and the badge share one threshold;
UPower signals each level change, so it costs an idle `gdbus monitor` and no
polling. AirPods are not on it: their battery comes from Apple's own
broadcast, which OmaPods reads and UPower never sees.

It cannot read them the way the bar's own indicators do. Omarchy hands its
idle, night-light and notification services only to a plugin that replaces
the whole bar or declares itself a clone of `omarchy.indicators`;
`firstPartyServiceFor` returns `null` to anyone else, quietly. Declaring the
clone would be untrue, so `Service.qml` runs `overview watch`
instead: one watcher however many bars there are, running only while a gear
has said it is there. Stay awake and do not disturb are files under
`~/.local/state/omarchy`, `nmcli monitor` reports the connection and UPower
the batteries, so those wake it at once; night light has no file behind it and is asked again every
fifteen seconds. Dictation is not counted: it is
on only while someone is speaking, and the bar shows its own mark then.

Each of the three can be turned off on **OmaControl → Settings** — the
count, the network mark, and the two battery marks together — because the bar
may already say it. They are keys of the gear's own layout entry
(`showActiveSwitchCount`, `showNetworkWarning`, `showBatteryWarnings`), so
`omarchy bar set` reaches them too. A mark switched off also stops sending the
click to its page; the tooltip always names everything.

## The launcher entry

The plugin is an app as well as a bar widget: `Service.qml` is also the
`service` entry point that writes `~/.local/share/applications/omacontrol.desktop` from
the template beside it, substituting the icon path, and deletes it again on
disable or remove. Omarchy has no install hook, which is why this lives in the
plugin rather than in a package.

Both halves guard on `X-OmaControl-Managed=true`: a file at that path without
the marker is never written and never deleted, so a hand-written entry
survives. Every failure in the script is a quiet exit — a launcher entry is a
convenience, and none of it is worth interrupting the shell over.

Changing either file means testing the whole cycle, not just the write:
`omarchy plugin disable`, check the file is gone, `omarchy plugin enable`,
check it is back, and `desktop-file-validate` what it wrote.


## The bar layout

`bar move` and `bar shift` edit `.bar.layout` in `shell.json`. Both move the
widget's **whole object**, never rebuild it from its id: a widget keeps its own
settings in that same object, and half the bar would lose its configuration the
first time it was reordered.

**A widget's settings are the keys of its entry beside the id** — the bar hands
a widget every key of its layout entry except `id`, so a width is written
`{ "id": "omarchy.spacer", "size": 60 }`, not under a `settings` object. Nested,
it arrives as `settings.settings.size`, the widget reads nothing there and
falls back to its default, and the setting does nothing at *every* value. From
outside that is indistinguishable from a widget that does not work at all —
which is the wrong conclusion to reach, and an expensive one: the fix is to
check `entrySettings` in the bar's own `BarModel.js` before blaming the widget.

**A spacer is named by its place, not its id.** Its manifest sets
`allowMultiple`, so two spacers in a section are the same id twice and the bar
tells them apart by position alone. `bar move-at`, `shift-at` and the
`bar spacer` commands therefore take a section and an index, and carry the id
only to be checked against what is actually in that slot — a page acting on a
list read a moment ago must not resize whatever has moved into it since. The
by-id forms remain for the widgets that are unique.

**Disabling a widget is ours to do, not Omarchy's.** A widget is in
`.bar.layout` or it is not — that is the whole of its enabled state — and
`omarchy plugin disable` says so by removing the entry. It removes only the
entry, though, so the widget's own settings go with it: Omatop came back from a
round trip without its `showValues`, and Spotify would come back without its
account and its session. `plugin enable` then appends, so a widget switched off
and on again walks to the end of its section. So `bar_disable` keeps the whole
object, and where it was, in `.barHidden`, and `bar_enable` puts that object
back in its place. A widget this window never disabled has no place to go back
to, and that placement is Omarchy's to decide — so for that one case its own
command is what runs.

Each widget appears once on the page: under the section it sits in, or in
**Disabled** at the foot. A list of switches beside the three section lists
would have named every widget twice and left the reader deciding which list to
believe.

## The Plugins page

Removing hands off to the Omarchy flow in a terminal, because it asks what
else goes and prints what it deleted. **Update and add do not.**
`omarchy-plugin-update <id> --yes` is entirely non-interactive — the diff and
the confirm are the half `--yes` skips — and a terminal opening over this
window was the whole of what that bought. So the row does the asking instead:
how many commits are coming, and what the first three of them say, read off
the same `FETCH_HEAD` the count came from, at no extra network cost.

`omarchy-plugin-add <url> --yes [--enable]` is the same: it prompts only for
what it was not given, so a form can give it everything and get nothing back.
What that flow asked for was a git URL, whether to enable it, and a
confirmation of the warning — and the warning is the one part that was not
ceremony, so the form carries it in the window's own words, above the button
it is about, and the page defaults the switch on the way `gum confirm` did.
Two things are the window's to say rather than upstream's: on success,
because upstream signs off with "Enable it later with: omarchy plugin enable
x", which is a command to type at someone who has just pressed a button; and
on failure, where every one of Omarchy's scripts leads with its own name and
the notice already has a heading. The id for the sentence is taken off the
"Added <id> into <path>" line, and falls back to "it" if upstream ever
rewords that.

**A plugin cannot update another plugin and stay on screen.** The shell watches
`~/.config/omarchy/plugins` with `inotifywait -m -r` and calls
`reloadPlugins()` on any change under it, which unloads every plugin widget —
including the bar widget hosting this window. A `git merge` is a change under
it, so the window goes. Deferring `omarchy-plugin-update`'s own
`rescanPlugins` does not help; the watcher has already fired. (This also
bites while testing: a `git` command run by hand inside any plugin directory
closes the window, so rewind a plugin *before* opening it, not after.) Three
things follow, and they are the design rather than a workaround:

- **The update is detached** (`setsid`, re-entering as `plugin update-run`).
  A child of the window would be killed part-way through its own merge.
- **It reports into the cache, not up its own stdout.** `running` says a
  spinner is owed, `last` says how it went — and `adding`/`lastAdd` are the
  same pair for an add, singular because there is no id to key one by until
  the clone has been read. An add is subject to all of this too: the clone
  lands *inside* the watched directory, as `.add.tmp.$$` before it is even a
  plugin, so the window goes before git has finished. The exception is a URL
  refused before anything is written — `omarchy-git-url-check` answers in
  milliseconds and nothing reloads — which is why the page keeps watching
  the cache rather than assuming it is about to be torn down. The page polls while something is
  in flight and picks up an update already running when it is built again, so
  the answer waits for the window to come back rather than dying with it. The
  page says up front that it will close, because it will.
- **It summons the window back.** The job that outlived the window is the only
  thing left that knows it should return, so it waits for
  `omarchy-shell shell ping` to answer, lets the teardown settle, and then
  calls `omacontrol showPage plugins` until the layer is actually there — the
  IPC call returns nothing either way, and a summon eaten by a dying panel
  looks exactly like one that worked. Whether to return is decided *before*
  the update, while the window is still up to be asked: afterwards there is no
  telling a window that was torn down from one the reader had closed, and
  opening a window nobody asked for is worse than not returning to one.

The update check fetches every plugin at
once and prints each verdict as it lands, so spinners retire one at a time
rather than all at the end; the verdicts outlive the sweep in
`~/.cache/omarchy/omacontrol/plugin-updates.json`, since a check costs a
network round trip per plugin.

The window is a plugin too, and says so in the window header, beside the changed count, when it is behind:
the cached verdict draws it at once and a single background fetch corrects it
a moment after opening. The comparison is `omarchy-plugin-update`'s own — fetch
`origin HEAD`, count `HEAD..FETCH_HEAD` — on purpose, so the count never
promises an update the button then refuses to make. The same `FETCH_HEAD`
gives the **version upstream is calling itself** (`git show
FETCH_HEAD:manifest.json`), at no second round trip, which is what the
Available column shows. Not the marketplace's listed version: the listing is
what was submitted, and this is what the Update button would install.

**A directory is not a plugin.** The sweep walks
`~/.config/omarchy/plugins`, and `omarchy plugin remove` leaves what it
removed beside the others as `.<id>.bak.<stamp>` — a git checkout with a live
remote. So every sweep spent a fetch on it, and the count of plugins with an
update included one no row on the page offered. Both the sweep and the local
read skip hidden directories, and the page counts updates over the *plugins*
rather than over the sweep's answers.

## What the page reads, and where from

The page has three sources and they are deliberately separate:

- **`plugins` in the state document** — id, name, kinds, `enabled`,
  `canDisable`, `firstParty`. The Bar page needs the widget ids, so this stays
  where it is, and it stays small.
- **`plugin poll`** — what each plugin's own manifest declares (version,
  author, licence, description) and what it occupies on disk. A local read, on
  the page's own timer, never in the state document: a state read happens after
  every write anywhere in the window. Sizes are `du -sbL`, held to the *read*
  timeout rather than the walk budget — a plugin is a few hundred kilobytes,
  and a du that cannot answer in five seconds should leave the column empty
  rather than hold the poll open.
- **`plugin directory-fetch` / `directory-refresh`** — what
  plugins.omarchy.org says.

## The marketplace lookup

Who wrote a plugin and whether anyone has reviewed it cannot be answered on
the machine. Two sources answer it, and both are the network:

| Source | Holds |
| --- | --- |
| `https://plugins.omarchy.org/catalog.json` | author, version, category, licence, `verificationStatus` and the `verificationCommit` it covers, GitHub stars, repo URL, and `status` — the catalogue's own word for whether the plugin still installs |
| `https://api.omarchyplugins.com/v1/stats` | hearts, views, copies |

Both are overridable (`OMACONTROL_PLUGIN_CATALOG_URL`,
`OMACONTROL_PLUGIN_STATS_URL`), and the reduced answer is cached at
`OMACONTROL_PLUGIN_DIRECTORY`.

- **The catalogue is nine megabytes describing three and a half thousand
  plugins**, of which a machine has twenty. It is asked for compressed,
  streamed through `jq`, and reduced to those twenty before any of it is kept
  — thirteen kilobytes on disk. The byte ceiling is there to stop a redirect to
  something enormous, not to police the catalogue's growth: past it the read
  truncates, jq refuses the fragment, and the last good answer stands. Every
  failure here is the same shape — a request that did not arrive leaves the
  previous answer rather than reporting every plugin unlisted.
- **The id finds the listing; the copy has to earn it.** This used to be a
  join on the id alone, and a marketplace maintainer reviewing OmaControl's own
  submission sent it back for that: a fork that kept the id, or a copy edited
  where it sits, wore the original's Verified badge without any of its code
  having been looked at. A listing is a repository and a verification is one
  commit of it (`verificationCommit`), so:
  - a copy gets the listing — author, stars, hearts, the Repository row —
    only when its `origin` is the listed repository, compared as
    host/owner/name in any spelling git accepts. Omarchy's own plugins are the
    exception: the namespace is reserved and the package installs them, so
    there is no clone to ask.
  - it gets the badge only at the verified commit with its files unchanged:
    `git diff HEAD` clean, and nothing untracked beyond the plugin's own
    `.gitignore`. Global excludes do not count, and a plugin's declared build
    output does not cost it the badge.
    An untracked `.gitignore` is a change in itself — they are read tracked
    or not, and one containing `*` hides itself and everything beside it —
    and so is a file flagged assume-unchanged or skip-worktree.
  - every other case says which it is — "Listed, this version not verified",
    "Listed, changed on this machine", "Listed from another repository",
    "Listed, installed twice" — because each one has a different thing to do
    about it. A git read that timed out is *not checked*, never *changed*.

  **The local read is keyed by the manifest's id, not the directory's name.**
  The shell keys plugins the same way, so a fork cloned by hand into a second
  directory under the same id is loaded *instead of* one of them — and the
  page, reading the directory named after the id, gave the fork's id the real
  copy's badge. Two directories claiming one id are `contested` and match no
  listing.

  `plugin_checkout` asks only a directory with its own `.git` (otherwise git
  walks up into whatever repository holds it), reads the origin through
  `git remote get-url` so an `insteadOf` alias resolves, and runs every git
  call with fsmonitor and replace objects off: with `core.fsmonitor` set
  globally, as Scalar does, a bare `ls-files` starts a daemon per plugin on
  every poll. A cache written before the commit was kept counts as owed a
  refresh, or every badge would vanish for a day.
- **`ids` records who the last check asked about.** Without it there is no
  telling a plugin the catalogue does not have from one installed since the
  check — and the page would call the second unlisted for a day, which is
  exactly when someone wants to know whether what they just installed is
  verified. So `directory-fetch` refreshes on age *or* on a plugin it has never
  looked up.
- **Nothing is ever sent.** The stats API takes a POST and the website's heart
  button uses it; this page reads the counts and does not offer one. A number
  read from a public endpoint is one thing; an event sent from someone's
  desktop to a third party on a click is another, and the browser is where that
  belongs.
- **Null is not zero.** A plugin nobody has hearted and one nobody has looked
  up are different answers; the second is a dash.

