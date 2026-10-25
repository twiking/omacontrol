pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "ui" as Ui

// OmaControl — one window for the settings that otherwise live scattered
// across ~/.config/omarchy/shell.json, the Hyprland config in ~/.config/hypr,
// and ~/.XCompose.
//
// The window never parses or rewrites those files itself. It reads one JSON
// document from bin/omacontrol and sends every change back as a `set` call;
// that script owns hyprctl, the omarchy commands, the generated Lua, and the
// one-time backup taken before any hand-written file is touched.
Item {
  id: root
  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---------------- window lifecycle ---------------------------------------
  readonly property bool shown: window.visible

  // While the search box is being typed into it owns the keyboard, the same
  // way an open dropdown or a field being edited does.
  readonly property bool searchFocused: searchInput ? searchInput.activeFocus : false
  readonly property TextField searchInput: searchField.item as TextField

  // Which screen the window was opened on. Hyprland knows which one has the
  // focus; Quickshell knows the screens by name, and the two are matched here.
  property var openedOn: null

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    if (name === "") return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === name) return screens[i]
    return null
  }

  function show() {
    openedOn = focusedScreen()
    window.visible = true
    refresh()
    if (!selfCheckProcess.running) selfCheckProcess.running = true
  }
  function hide() { window.visible = false }
  function close() { hide() }

  // ---------------- palette ------------------------------------------------
  // Settings tracks the foundational palette rather than a themable surface of
  // its own, so it renders consistently under every theme.
  readonly property color foreground: Ui.Palette.foreground
  readonly property color background: Ui.Palette.background
  readonly property color accent: Ui.Palette.accent
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.16)
  // The rail beside the page, and the two strips of chrome that frame both
  // columns. Three steps off the window and no more: anything finer stops
  // being visible once a theme supplies the colours.
  readonly property color surface: Ui.Palette.surface
  readonly property color chrome: Ui.Palette.chrome
  readonly property string fontFamily: Style.font.family

  // Decoded, or a home directory with a space in it runs a path with %20 in it.
  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("bin/omacontrol")).replace(/^file:\/\//, ""))

  // ---------------- state --------------------------------------------------
  property var state: ({})
  property bool loaded: false
  property bool busy: false
  property string lastError: ""

  readonly property var hypr: state.hypr !== undefined ? state.hypr : ({})
  readonly property var barState: state.bar !== undefined ? state.bar : ({})
  readonly property var idleState: state.idle !== undefined ? state.idle : ({})
  readonly property var monitors: state.monitors !== undefined ? state.monitors : []
  readonly property var composeEntries: state.compose !== undefined ? state.compose : []
  readonly property var plugins: state.plugins !== undefined ? state.plugins : []
  readonly property var agentsState: state.agents !== undefined ? state.agents : ({})
  readonly property var datetime: state.datetime !== undefined ? state.datetime : ({})
  readonly property var groups: state.groups !== undefined ? state.groups : ({})
  readonly property var branding: state.branding !== undefined ? state.branding : ({})

  // Mute and volume are the server's, not this window's: the media keys, the
  // bar widget and any other panel move them too. While the Audio page is up,
  // PulseAudio's event stream is followed directly so the switches and sliders
  // track what is actually happening rather than what was true at last read.
  property var audioLive: null
  readonly property var audio: audioLive !== null ? audioLive
    : (state.audio !== undefined ? state.audio : ({}))

  Process {
    id: audioWatchProcess
    command: ["bash", root.helperPath, "audio", "watch"]
    running: root.shown && root.pageId === "audio"
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        try {
          var next = JSON.parse(line)
          if (next && typeof next === "object") root.audioLive = next
        } catch (e) {
          // A half-written line is not worth acting on; the next event
          // brings the whole state again.
        }
      }
    }
    // A stale live reading is worse than none: the page falls back to the
    // state document once nothing is watching.
    onRunningChanged: if (!running) root.audioLive = null
  }

  // Input devices. Each page lists its own, one group per device, so the
  // Keyboard and Mouse pages never have to say which device a control means.
  readonly property var devices: state.devices !== undefined ? state.devices : ({})

  function setDevice(name, key, value, kind) {
    run(["devices", "set", name, key, String(value), kind])
  }

  function clearDevice(name) { run(["devices", "clear", name]) }

  // Removes everything for a device, including an hl.device the user wrote
  // themselves — that one is commented out rather than deleted.
  function removeDevice(name) { run(["devices", "remove", name]) }

  // The profile is moved by the bar's power plugin, the menu and the daemon
  // itself, and the battery reading changes on its own. While the Power page
  // is up, those events are followed directly rather than waited for.
  property var powerLive: null
  readonly property var power: powerLive !== null ? powerLive
    : (state.power !== undefined ? state.power : ({}))

  Process {
    id: powerWatchProcess
    command: ["bash", root.helperPath, "power", "watch"]
    running: root.shown && root.pageId === "power"
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        try {
          var next = JSON.parse(line)
          if (next && typeof next === "object") root.powerLive = next
        } catch (e) {
          // A half-written line is not worth acting on; the next event
          // brings the whole state again.
        }
      }
    }
    onRunningChanged: if (!running) root.powerLive = null
  }

  // Like Wi-Fi: the Bluetooth page keeps its own list current while it is on
  // screen, without re-reading the whole state to do it.
  // The page's poll is the only source: BlueZ is not read by the state
  // document at all, so nothing outside the Bluetooth page asks about it.
  property var bluetoothLive: null
  readonly property var bluetooth: bluetoothLive !== null ? bluetoothLive : ({})

  function pollBluetooth() {
    if (bluetoothPollProcess.running) return
    bluetoothPollProcess.command = ["bash", root.helperPath, "bluetooth", "poll"]
    bluetoothPollProcess.running = true
  }

  Process {
    id: bluetoothPollProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (next && typeof next === "object") root.bluetoothLive = next
        } catch (e) {
          // A failed poll leaves the last good list on screen.
        }
      }
    }
  }

  // ---------------- live pages ---------------------------------------------
  //
  // Overview, Disk and Processes are readings rather than settings, and none of
  // them is in the state document: a state read happens after every write in
  // the window, and `df` on a machine with a network mount, or two frames of
  // `top`, would be paid for by every switch on every other page. Each polls
  // for itself while it is the page on screen.
  //
  // One shape, three pages. A reader that fails leaves the last good answer on
  // screen rather than blanking the page — the previous reading is a second
  // old and still true enough to look at, and a page that empties itself on a
  // dropped read flickers every time the machine is busy.
  property var overviewLive: null
  readonly property var overview: overviewLive !== null ? overviewLive : ({})
  function pollOverview() { pollInto(overviewPoll, ["overview", "poll"]) }
  Poller { id: overviewPoll; onParsed: function(value) { root.overviewLive = value } }

  property var diskLive: null
  readonly property var disk: diskLive !== null ? diskLive : ({})
  function pollDisk() { pollInto(diskPoll, ["disk", "poll"]) }
  Poller { id: diskPoll; onParsed: function(value) { root.diskLive = value } }

  // Asked once when the page opens, not on the poll: the only way to answer it
  // is to walk directories, and doing that every five seconds would be a
  // window that spins a disk for as long as the reader looks at it.
  property var diskBreakdown: null
  property bool diskBreakdownAsked: false
  function fetchDiskBreakdown() {
    if (diskBreakdownAsked) return
    diskBreakdownAsked = true
    pollInto(breakdownPoll, ["disk", "breakdown"])
  }
  Poller { id: breakdownPoll; onParsed: function(value) { root.diskBreakdown = value } }

  // Several hundred desktop entries, and what is in force for each. A list
  // this long re-read after every write anywhere in the window would be paid
  // for by every other page, so the page that wants it polls for it.
  property var appsLive: null
  readonly property var apps: appsLive !== null ? appsLive : []
  function pollApps() { pollInto(appsPoll, ["apps", "poll"]) }
  Poller { id: appsPoll; onParsed: function(value) { root.appsLive = value } }

  // The same asking, for anything a page cannot take back by being clicked
  // again. A page hands over the words and what to do, and the window owns
  // the dialog: a page is unloaded the moment the reader navigates, and a
  // question that leaves with its page is a question that answers itself.
  //
  // The callback is held in a plain var, never a property named `onSomething`
  // — that name is the signal-handler syntax, and the assignment is quietly
  // kept as null.
  property var pendingConfirm: null
  function askConfirm(message, confirmText, action) {
    root.pendingConfirm = action
    askDialog.message = message
    askDialog.confirmText = confirmText
    askDialog.selectedIndex = 0
    askDialog.opened = true
  }

  property var packagesLive: null
  readonly property var packages: packagesLive !== null ? packagesLive : ({})
  function pollPackages() { pollInto(packagesPoll, ["packages", "poll"]) }
  Poller { id: packagesPoll; onParsed: function(value) { root.packagesLive = value } }

  // A database sync, so it is asked for and never assumed: the page offers it,
  // and the poll above picks up whatever it wrote.
  property bool packagesSyncing: false
  function refreshPackages() {
    if (packagesSync.running) return
    packagesSyncing = true
    packagesSync.command = ["bash", root.helperPath, "packages", "refresh"]
    packagesSync.running = true
  }
  Process {
    id: packagesSync
    onRunningChanged: if (!running) { root.packagesSyncing = false; root.pollPackages() }
  }

  // Asking is free: `packages fetch` compares the cache's age itself and does
  // nothing if the last check is under a day old, so the page asks on open
  // without that being a sync. It goes through the same process as the button
  // so the page shows "Checking…" for an automatic check exactly as it does
  // for one the reader asked for.
  function fetchPackages() {
    if (packagesSync.running) return
    packagesSyncing = true
    packagesSync.command = ["bash", root.helperPath, "packages", "fetch"]
    packagesSync.running = true
  }

  // Every installed package — what it costs, why it is here, what version is
  // on the disk and which repository put it there — asked once when the page
  // opens rather than on its poll. It is 1339 rows and a read of the sync
  // databases, and none of it changes between two ticks of a ten-second timer.
  // The counts and the pending list stay on the poll, where they are cheap.
  property var packageList: []
  function pollPackageList() { pollInto(packageListPoll, ["packages", "list"]) }
  Poller { id: packageListPoll; onParsed: function(value) { root.packageList = value } }

  // One package, read when the reader opens it rather than on the poll. The
  // list already carries the name, the size and why it is there; the rest —
  // what it is, where it came from, what would break without it — is only
  // ever wanted for the one on screen, and asking for all 1339 of them every
  // ten seconds to have it ready would be the whole local database.
  property var packageInfo: ({})
  function pollPackageInfo(name) {
    if (String(name) === "") { packageInfo = ({}); return }
    pollInto(packageInfoPoll, ["packages", "info", String(name)])
  }
  Poller { id: packageInfoPoll; onParsed: function(value) { root.packageInfo = value } }

  // The Plugins page reports as much as it configures: what each plugin
  // declares, what it occupies, and what plugins.omarchy.org says about it.
  // None of that belongs in the state document — a state read happens after
  // every write anywhere in the window — so the page polls for it, like Disk,
  // Packages and Apps. `plugins` stays in the document for the Bar page's
  // widget ids, which is all the Bar page needs.
  property var pluginsReportLive: null
  readonly property var pluginsReport: pluginsReportLive !== null ? pluginsReportLive : ({})
  function pollPlugins() { pollInto(pluginsPoll, ["plugin", "poll"]) }
  Poller { id: pluginsPoll; onParsed: function(value) { root.pluginsReportLive = value } }

  // What the update cache says: which plugins have a job in flight, how the
  // last one went, and the verdicts the sweep left behind. Read here rather
  // than in the page, because a page calls `app` and does not shell out — the
  // Plugins page was the only one in the window that did.
  //
  // Two readers and not one. `pollInto` remembers a single owed command, so a
  // start sharing a reader with the one-second watch could be overwritten by
  // the next tick before it ran — the click would spin a spinner and begin
  // nothing. They share the property they write into, which is the same race
  // the two processes had and settles on the next tick.
  property var pluginUpdateCache: ({})
  function pollPluginUpdates() { pollInto(pluginUpdatesPoll, ["plugin", "updates-cached"]) }
  function startPluginUpdate(id) {
    pollInto(pluginUpdateStart, ["plugin", "update", String(id)])
  }
  // Both halves of adding one answer with the same document the update does,
  // so the page takes them in the same way and there is one thing to absorb.
  function startPluginAdd(url, enable) {
    pollInto(pluginUpdateStart,
             ["plugin", "add", String(url), enable ? "enable" : "leave"])
  }
  function clearPluginAdd() { pollInto(pluginUpdateStart, ["plugin", "add-clear"]) }
  Poller { id: pluginUpdatesPoll; onParsed: function(value) { root.pluginUpdateCache = value } }
  Poller { id: pluginUpdateStart; onParsed: function(value) { root.pluginUpdateCache = value } }

  // The marketplace is the network, so it is asked for and never assumed.
  // `directory-fetch` compares the cache's age itself and does nothing if the
  // last answer is under a day old, so the page may ask on open without that
  // being a request; the Check button is `directory-refresh`, which always
  // asks. Both go through the same process, so the page shows "Checking…" for
  // an automatic check exactly as it does for one the reader asked for.
  property bool pluginDirectorySyncing: false
  function refreshPluginDirectory() { pluginDirectory("directory-refresh") }
  function fetchPluginDirectory() { pluginDirectory("directory-fetch") }
  function pluginDirectory(action) {
    if (pluginDirectorySync.running) return
    pluginDirectorySyncing = true
    pluginDirectorySync.command = ["bash", root.helperPath, "plugin", action]
    pluginDirectorySync.running = true
  }
  Process {
    id: pluginDirectorySync
    onRunningChanged: if (!running) { root.pluginDirectorySyncing = false; root.pollPlugins() }
  }

  // Brightness is a reading, not a setting: the media keys and Omarchy's own
  // OSD move it, and on a desktop monitor asking costs a DDC round trip over
  // the video cable. So it is not in the state document — the Displays page
  // asks while it is the page on screen, exactly as Network and Bluetooth do.
  property var displayBrightness: ({})
  function pollBrightness() { pollInto(brightnessPoll, ["display", "brightness"]) }
  Poller { id: brightnessPoll; onParsed: function(value) { root.displayBrightness = value } }

  property var usageLive: null
  readonly property var usage: usageLive !== null ? usageLive : ({})
  function pollUsage() { pollInto(usagePoll, ["usage", "poll"]) }
  Poller { id: usagePoll; onParsed: function(value) { root.usageLive = value } }

  property var aboutLive: null
  readonly property var about: aboutLive !== null ? aboutLive : ({})
  function pollAbout() { pollInto(aboutPoll, ["about", "poll"]) }
  Poller { id: aboutPoll; onParsed: function(value) { root.aboutLive = value } }

  property var securityLive: null
  readonly property var security: securityLive !== null ? securityLive : ({})
  function pollSecurity() { pollInto(securityPoll, ["security", "poll"]) }
  Poller { id: securityPoll; onParsed: function(value) { root.securityLive = value } }

  // Read when the Network page opens and when the window comes back to it:
  // the file is only ever changed in an editor this window hands off to, and
  // the window is hidden for as long as that takes.
  property var hostsLive: null
  readonly property var hosts: hostsLive !== null ? hostsLive : ({})
  function pollHosts() { pollInto(hostsPoll, ["hosts", "list"]) }
  Poller { id: hostsPoll; onParsed: function(value) { root.hostsLive = value } }

  // The one outbound request this window makes. Asking is free: `news fetch`
  // checks the cache's age itself and does nothing if it is still warm, so the
  // page can ask on every open and on a timer without either being a request.
  //
  // No "asked once" flag. There was one, and it made the half-hourly timer
  // ornamental — the second call returned early for the life of the window,
  // which is exactly the window this is for.
  function fetchNews() {
    if (newsFetch.running) return
    newsFetch.command = ["bash", root.helperPath, "news", "fetch"]
    newsFetch.running = true
  }
  Process {
    id: newsFetch
    onRunningChanged: if (!running) root.pollOverview()
  }

  property var processesLive: null
  readonly property var processes: processesLive !== null ? processesLive : ({})
  function pollProcesses() { pollInto(processPoll, ["processes", "poll"]) }
  Poller { id: processPoll; onParsed: function(value) { root.processesLive = value } }

  // A poll asked for while one is in flight is *owed*, not dropped. Dropped
  // was the first version, and it cost every action on every live page up to a
  // full poll interval of staleness: marking a headline read wrote the store
  // immediately and the star sat there for another five seconds, because the
  // poll that would have noticed was refused while the timer's own poll — which
  // had already read the old value — finished.
  //
  // The command is remembered rather than reissued, so a page whose reader
  // takes an argument (the package being looked at) re-runs with the argument it asked
  // for and not the one before it.
  function pollInto(process, argv) {
    var command = ["bash", root.helperPath]
    for (var i = 0; i < argv.length; i++) command.push(argv[i])
    if (process.running) { process.owedCommand = command; return }
    process.command = command
    process.running = true
  }

  // One reader: run it, parse what it printed, hand it over. A failed read
  // leaves the last good answer on screen rather than blanking the page.
  component Poller: Process {
    id: poller
    signal parsed(var value)
    property var owedCommand: null

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (next !== null && typeof next === "object") poller.parsed(next)
        } catch (e) {
          // Left as it was.
        }
      }
    }

    onRunningChanged: {
      if (running || poller.owedCommand === null) return
      var next = poller.owedCommand
      poller.owedCommand = null
      poller.command = next
      poller.running = true
    }
  }

  // ---------------- reading numbers out loud -------------------------------
  //
  // Sizes and spans, said the way a person would say them. Both live here
  // rather than in the pages because two pages ask the same questions of them
  // and the answers have to match: 1.4 GB on the Disk page and 1.4 GB on the
  // Processes page cannot be arrived at two different ways.
  function formatBytes(bytes) {
    var n = Number(bytes)
    if (!isFinite(n) || n < 0) return ""
    var units = ["B", "kB", "MB", "GB", "TB", "PB"]
    var unit = 0
    while (n >= 1000 && unit < units.length - 1) { n = n / 1000; unit++ }
    // One decimal up to a hundred, none past it: "255.2 GB" is a size someone
    // reads, "255.23 GB" is a measurement, and "1004 GB" should have been TB.
    var digits = unit === 0 ? 0 : (n < 100 ? 1 : 0)
    return n.toFixed(digits) + " " + units[unit]
  }

  // A span, said the way someone would say it: minutes until an hour, then
  // hours. Not the same question as formatWhen, which is about a moment.
  function formatSpan(seconds) {
    var n = Number(seconds)
    if (!isFinite(n) || n < 0) return "—"
    if (n < 60) return Math.round(n) + " s"
    if (n < 3600) return Math.floor(n / 60) + " min " + Math.round(n % 60) + " s"
    var hours = Math.floor(n / 3600)
    return hours + " h " + Math.round((n % 3600) / 60) + " min"
  }

  // How long ago something happened, said the way someone would say it. Takes
  // a unix stamp because that is what a shell reader can hand over without
  // committing to a format the window would then have to parse back.
  function formatWhen(stamp) {
    var seconds = Math.floor(Date.now() / 1000) - Number(stamp)
    if (!isFinite(seconds)) return ""
    if (seconds < 90) return strings.t("shared.justNow", "just now")
    if (seconds < 5400) return strings.t("settingswindow.minutesAgo", "%1 min ago").arg(Math.round(seconds / 60))
    if (seconds < 172800) return strings.t("settingswindow.hoursAgo", "%1 h ago").arg(Math.round(seconds / 3600))
    return strings.tn("settingswindow.daysAgo", Math.round(seconds / 86400), "%1 day ago").arg(Math.round(seconds / 86400))
  }

  // Token counts run to the hundreds of millions, and formatBytes would call
  // those gigabytes. Same shortening, different unit and no unit suffix — the
  // column heading already says what is being counted.
  function formatTokens(count) {
    var n = Number(count)
    if (!isFinite(n) || n < 0) return ""
    if (n < 1000) return String(Math.round(n))
    if (n < 1000000) return (n / 1000).toFixed(n < 100000 ? 1 : 0) + "k"
    if (n < 1000000000) return (n / 1000000).toFixed(n < 100000000 ? 1 : 0) + "M"
    return (n / 1000000000).toFixed(1) + "B"
  }

  // Whole units, largest first, and never more than two of them: "6 d 3 h" is
  // an uptime, "6 d 3 h 14 m 22 s" is a stopwatch.
  function formatDuration(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var days = Math.floor(total / 86400)
    var hours = Math.floor((total % 86400) / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    if (days > 0) return days + " d" + (hours > 0 ? " " + hours + " h" : "")
    if (hours > 0) return hours + " h" + (minutes > 0 ? " " + minutes + " m" : "")
    return minutes + " m"
  }

  // What the switch says underneath itself: the devices in hand, or why there
  // are none.
  readonly property string bluetoothSummary: {
    if (bluetooth.available === false) return strings.t("settingswindow.bluetoothNoAdapter", "No Bluetooth adapter")
    if (bluetooth.powered !== true) return strings.t("settingswindow.bluetoothOff", "Off")
    var devices = bluetooth.devices !== undefined ? bluetooth.devices : []
    var names = []
    for (var i = 0; i < devices.length; i++)
      if (devices[i].connected) names.push(devices[i].name !== "" ? devices[i].name : devices[i].address)
    return names.length === 0
      ? strings.t("settingswindow.bluetoothNothing", "Nothing connected")
      : strings.t("settingswindow.bluetoothConnectedTo", "Connected to %1").arg(names.join(", "))
  }

  // While the Network page is open it polls Wi-Fi on its own, far more often
  // than the whole state is worth re-reading. That poll's answer stands in
  // for the Wi-Fi part of the state until the next full read replaces it.
  // As with Bluetooth: the page's poll is the only source.
  property var wifiLive: null
  readonly property var wifi: wifiLive !== null ? wifiLive : ({})

  function pollWifi() {
    if (wifiPollProcess.running) return
    wifiPollProcess.command = ["bash", root.helperPath, "wifi", "poll"]
    wifiPollProcess.running = true
  }

  Process {
    id: wifiPollProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (next && typeof next === "object") root.wifiLive = next
        } catch (e) {
          // A failed poll leaves the last good list on screen.
        }
      }
    }
  }
  // What the connection is doing, asked for by the Network page alone. It is
  // not in the state document for the same reason Disk and Processes are not:
  // it changes by the second, and a state read happens after every write
  // anywhere in the window.
  property var wifiLink: ({})
  // The sample before this one, which is the whole of what makes a rate out
  // of a counter. Two reads of a total since boot are a rate; one is a number
  // that never moves.
  property var wifiLinkPrev: null
  property real wifiRxRate: -1
  property real wifiTxRate: -1

  // The other half of a page called Network. Cheap, and read on the page's own
  // poll rather than with the state: a cable is not a setting.
  property var wifiWired: []
  function pollWifiWired() {
    if (wifiWiredProcess.running) return
    wifiWiredProcess.command = ["bash", root.helperPath, "wifi", "wired"]
    wifiWiredProcess.running = true
  }

  Process {
    id: wifiWiredProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (Array.isArray(next)) root.wifiWired = next
        } catch (e) {
          // Leaves the last answer on screen.
        }
      }
    }
  }

  // The themes and the wallpapers, as pictures. Read when their page opens and
  // again after one is set — a theme changes when somebody changes it, so
  // there is nothing here for a timer to watch.
  property var themeList: []
  property var wallpaperList: []

  // The theme a click claimed, until a read confirms it. It lives here rather
  // than on the page because applying a theme rewrites a dozen configs and
  // can take the page down and rebuild it — and a mark that dies with the
  // page is a ring that jumps back to the old theme half way through.
  property string themePending: ""
  property int themeTries: 0

  function setTheme(name) {
    themePending = name
    themeTries = 0
    set("theme", name)
  }

  // A font is applied the same way a theme is — a dozen configs rewritten —
  // so the mark it leaves behaves the same way: claimed on the click, cleared
  // only when the state read says that font is the one in force.
  property string fontPending: ""

  function setFont(name) {
    fontPending = name
    set("font", name)
  }

  function readThemes() {
    if (themeProcess.running) return
    themeProcess.command = ["bash", root.helperPath, "theme", "list"]
    themeProcess.running = true
  }

  // Asked again while the claim is unconfirmed. `omarchy-theme-set` returns
  // before everything it started has finished, so the first read back can
  // still name the old theme; clearing the mark on any answer at all is what
  // made the ring jump back and forth.
  Timer {
    id: themeConfirm
    interval: 500
    onTriggered: root.readThemes()
  }

  // The unlock screens, read the same way and for the same reason: it changes
  // when someone changes it. The claim a click makes lives here too, because
  // setting one runs in a terminal and answers long after the click.
  property var unlockList: []
  property string unlockPending: ""

  function readUnlocks() {
    if (unlockProcess.running) return
    unlockProcess.command = ["bash", root.helperPath, "theme", "unlock-list"]
    unlockProcess.running = true
  }

  function setUnlock(name) {
    unlockPending = name
    run(["theme", "unlock", name])
    unlockConfirm.restart()
  }

  // Rebuilding the initramfs takes a while and the terminal that does it is
  // not this window's to wait on, so the list is asked again a few times and
  // then left alone rather than sitting on a claim for ever.
  property int unlockTries: 0
  Timer {
    id: unlockConfirm
    interval: 2000
    onTriggered: root.readUnlocks()
  }

  Process {
    id: unlockProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (!Array.isArray(next)) return
          root.unlockList = next
          if (root.unlockPending === "") return
          for (var i = 0; i < next.length; i++)
            if (next[i].current === true && next[i].name === root.unlockPending) {
              root.unlockPending = ""
              root.unlockTries = 0
              return
            }
          if (root.unlockTries < 15) { root.unlockTries++; unlockConfirm.restart() }
          else { root.unlockPending = ""; root.unlockTries = 0 }
        } catch (e) {
          // Leaves the last good list on screen.
        }
      }
    }
  }

  function readWallpapers() {
    if (wallpaperProcess.running) return
    wallpaperProcess.command = ["bash", root.helperPath, "theme", "backgrounds"]
    wallpaperProcess.running = true
  }

  Process {
    id: themeProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (!Array.isArray(next)) return
          root.themeList = next
          if (root.themePending === "") return
          for (var i = 0; i < next.length; i++)
            if (next[i].current === true && next[i].name === root.themePending) {
              root.themePending = ""
              root.themeTries = 0
              return
            }
          // Not yet. Ask again — but not forever: a set that failed must not
          // leave the ring sitting on a theme this machine is not wearing.
          if (root.themeTries < 12) { root.themeTries++; themeConfirm.restart() }
          else { root.themePending = ""; root.themeTries = 0 }
        } catch (e) {
          // Leaves the last good list on screen.
        }
      }
    }
  }

  Process {
    id: wallpaperProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (Array.isArray(next)) root.wallpaperList = next
        } catch (e) {
          // Leaves the last good list on screen.
        }
      }
    }
  }

  // The address the internet sees. Asked for when the page opens and not on
  // the poll: the reader decides for itself whether its cache has aged out, so
  // this is a request at most once an hour however often the page is opened.
  property var publicIp: ({})
  function readPublicIp() {
    if (publicIpProcess.running) return
    publicIpProcess.command = ["bash", root.helperPath, "wifi", "publicip"]
    publicIpProcess.running = true
  }

  Process {
    id: publicIpProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (next && typeof next === "object") root.publicIp = next
        } catch (e) {
          // No answer leaves the row saying nothing, which is the truth.
        }
      }
    }
  }

  function pollWifiLink() {
    if (wifiLinkProcess.running) return
    wifiLinkProcess.command = ["bash", root.helperPath, "wifi", "link"]
    wifiLinkProcess.running = true
  }

  Process {
    id: wifiLinkProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (!next || typeof next !== "object") return
          var now = Date.now() / 1000
          var prev = root.wifiLinkPrev
          // A first sample, or a counter that went backwards because the
          // interface was reset, reports nothing rather than a spike.
          if (prev !== null && now > prev.at && next.rx !== null && next.tx !== null
              && next.rx >= prev.rx && next.tx >= prev.tx) {
            root.wifiRxRate = (next.rx - prev.rx) / (now - prev.at)
            root.wifiTxRate = (next.tx - prev.tx) / (now - prev.at)
          }
          root.wifiLinkPrev = { rx: next.rx, tx: next.tx, at: now }
          root.wifiLink = next
        } catch (e) {
          // A failed read leaves the last figures on screen.
        }
      }
    }
  }

  // Bytes per second, said with the window's own `formatBytes` rather than the
  // bar panel's: its steps are binary where this window's are decimal, and a
  // second byte formatter in here would put two answers to "how big" on two
  // pages of the same window. Bytes per second, never bits — which is what
  // the panel says too.
  function formatRate(bytesPerSecond) {
    return bytesPerSecond < 0 ? "\u2014" : formatBytes(bytesPerSecond) + "/s"
  }

  readonly property var wifiNetworks: wifi.networks !== undefined ? wifi.networks : []
  readonly property var wifiConnection: wifi.connection !== undefined ? wifi.connection : ({})

  // The network you are on, and the ones you are not. The page shows the first
  // as a block of its own, so leaving it in the list underneath would describe
  // the same connection twice, a few rows apart.
  readonly property var activeNetwork: {
    for (var i = 0; i < wifiNetworks.length; i++)
      if (wifiNetworks[i].active === true) return wifiNetworks[i]
    return null
  }
  readonly property var otherNetworks: {
    var out = []
    for (var i = 0; i < wifiNetworks.length; i++)
      if (wifiNetworks[i].active !== true) out.push(wifiNetworks[i])
    return out
  }
  readonly property var wifiBand: wifi.band !== undefined ? wifi.band : ({})

  // Automatic plus whichever bands this radio and access point actually
  // offer, so a 2.4-only network never shows a 5 GHz choice that cannot work.
  function bandOptions() {
    var out = [{ value: "auto", label: strings.t("settingswindow.label.1", "Automatic")}]
    var available = wifiBand.available !== undefined ? wifiBand.available : []
    for (var i = 0; i < available.length; i++)
      out.push({ value: String(available[i]), label: String(available[i]) + " GHz" })
    return out
  }
  // The network whose password field is open, if any.
  property string wifiPrompting: ""

  // The network being joined. Association, DHCP and a wrong-password rejection
  // all take seconds, and a row that does not say so reads as a click that
  // missed.
  property string wifiConnecting: ""
  onWifiChanged: if (wifiConnecting !== "" && wifi.connected === wifiConnecting) wifiConnecting = ""

  function connectWifi(ssid, password) {
    wifiPrompting = ""
    wifiConnecting = ssid
    if (password !== undefined && password !== "") {
      // The passphrase goes over stdin, never argv: anything on the command
      // line is readable by every process on the machine for as long as the
      // connection takes.
      root.busy = true
      wifiConnectProc.secret = password
      wifiConnectProc.command = ["bash", root.helperPath, "wifi", "connect", ssid, "--password-stdin"]
      wifiConnectProc.running = true
    } else {
      run(["wifi", "connect", ssid])
    }
  }

  Process {
    id: wifiConnectProc
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
      stdinEnabled = false
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = text.trim()
    }
    onRunningChanged: if (!running) {
      root.busy = false
      root.wifiConnecting = ""
      settleTimer.restart()
    }
  }

  readonly property var bindings: state.bindings !== undefined ? state.bindings : ({})

  // Which workspace an application opens on: the applications that can be
  // picked, and the rules in force for the ones already bound.
  readonly property var workspaces: state.workspaces !== undefined ? state.workspaces : ({})
  readonly property var workspaceApps: workspaces.apps !== undefined ? workspaces.apps : []
  readonly property var workspaceRules: workspaces.rules !== undefined ? workspaces.rules : []
  readonly property var workspaceSetups: workspaces.setups !== undefined ? workspaces.setups : []
  property string bindingFilter: ""

  // Matching on keys and description together is what people actually search
  // by: "super f" for the chord, "screenshot" for the thing it does.
  readonly property var visibleBindings: {
    var items = bindings.items !== undefined ? bindings.items : []
    var needle = bindingFilter.trim().toLowerCase()
    if (needle === "") return items
    var words = needle.split(/\s+/)
    var out = []
    for (var i = 0; i < items.length; i++) {
      var hay = (String(items[i].keys) + " " + String(items[i].description) + " " + String(items[i].command)).toLowerCase()
      var all = true
      for (var w = 0; w < words.length; w++)
        if (hay.indexOf(words[w]) === -1) { all = false; break }
      if (all) out.push(items[i])
    }
    return out
  }

  readonly property var herdr: state.herdr !== undefined ? state.herdr : ({})
  readonly property var herdrValues: herdr.values !== undefined ? herdr.values : ({})

  function herdrValue(key, fallback) {
    var value = herdrValues ? herdrValues[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function setHerdr(key, value) { run(["herdr", "set", key, String(value)]) }

  readonly property var tmux: state.tmux !== undefined ? state.tmux : ({})
  readonly property var tmuxValues: tmux.values !== undefined ? tmux.values : ({})

  function tmuxValue(key, fallback) {
    var value = tmuxValues ? tmuxValues[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function setTmux(key, value) { run(["tmux", "set", key, String(value)]) }

  readonly property var nvim: state.nvim !== undefined ? state.nvim : ({})
  readonly property var nvimValues: nvim.values !== undefined ? nvim.values : ({})

  function nvimValue(key, fallback) {
    var value = nvimValues ? nvimValues[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function setNvim(key, value) { run(["nvim", "set", key, String(value)]) }

  function editConfig(path) {
    editProcess.command = ["bash", "-lc", "omarchy-launch-config-editor \"" + path + "\""]
    editProcess.running = true
  }

  Process { id: editProcess }

  function group(name) {
    var g = groups ? groups[name] : undefined
    return g !== undefined && g !== null ? g : { items: [], current: "" }
  }

  function agentOptions() {
    var items = agentsState.items !== undefined ? agentsState.items : []
    var out = []
    for (var i = 0; i < items.length; i++)
      out.push({ value: String(items[i].id), label: String(items[i].label) })
    return out
  }

  // A menu group as dropdown options, labelled the way the menu labels them.
  function groupOptions(name) {
    var items = group(name).items || []
    var out = []
    for (var i = 0; i < items.length; i++)
      out.push({ value: String(items[i].id), label: String(items[i].label) })
    return out
  }

  // Menu entries can ask for Omarchy's own icon font. Asking Qt for the family
  // by name is not enough — a stale user-installed omarchy.ttf with a single
  // glyph shadows the complete system copy, and the icons come out blank — so
  // the helper resolves which file actually carries the glyphs and this loads
  // that file directly. Falling back to the family name keeps a system without
  // fontconfig from losing the icons entirely.
  readonly property string omarchyFontPath: state.iconFonts && state.iconFonts.omarchy
    ? String(state.iconFonts.omarchy) : ""
  readonly property string omarchyFontFamily: omarchyFontLoader.status === FontLoader.Ready
    && omarchyFontLoader.font.family !== "" ? omarchyFontLoader.font.family : "omarchy"

  FontLoader {
    id: omarchyFontLoader
    source: root.omarchyFontPath !== "" ? "file://" + root.omarchyFontPath : ""
  }

  // Which Hyprland settings this window has written, and the way to hand one
  // back. Anything not in this list is showing a value the system supplies,
  // which is not ours to reset.
  // Not "hyprChanged": the hypr property above already generates a signal of
  // that name, and the two would collide.
  readonly property var changedSettings: state.hyprChanged !== undefined ? state.hyprChanged : []
  function isChanged(key) { return changedSettings.indexOf(key) !== -1 }

  // Said the same way in both places it appears — beside the window's name and
  // beside the page's — so the two read as one fact rather than two counts.
  readonly property string changedLabel: changedSettings.length === 0 ? ""
    : strings.tn("settingswindow.settingsChanged", changedSettings.length, "1 setting changed").arg(changedSettings.length)

  // The far end of the keyhint bar, and only when something is actually
  // happening. "Ready" was none of those — it reported that nothing was.
  readonly property string statusNote: busy ? strings.t("settingswindow.applying", "Applying\u2026") : (!loaded ? strings.t("settingswindow.loading", "Loading\u2026") : "")
  // Both families: a Hyprland key is dropped, anything else is written back
  // the way it was found. The helper knows which is which.
  function resetSetting(key) { run(["reset", key]) }

  // Whether this window is itself behind its remote. The cached answer draws
  // the header at once; the check behind it corrects the cache a moment later.
  readonly property var selfUpdate: state.selfUpdate !== undefined ? state.selfUpdate : ({})
  readonly property int selfBehind: selfUpdate.behind !== undefined ? Number(selfUpdate.behind) : 0
  readonly property string selfId: selfUpdate.id !== undefined ? String(selfUpdate.id) : ""
  // Read from the manifest, which is where a version is decided; the title
  // shows nothing until the state arrives rather than a number to correct.
  readonly property string selfVersion: selfUpdate.version !== undefined ? String(selfUpdate.version) : ""

  Process {
    id: selfCheckProcess
    command: ["bash", root.helperPath, "plugin", "self-check"]
    // Once per opening, and never on the path of anything the user is waiting
    // for: a fetch is a network round trip.
    running: false
    onRunningChanged: if (!running) Qt.callLater(function() { root.refresh() })
  }

  // ---------------- search --------------------------------------------------
  //
  // Only the open page exists, so what the other pages hold cannot be asked of
  // them. The index arrives with the state instead: what each page declares,
  // read from its source, plus the things a page is a list of — this keyboard,
  // that network, your bindings — which no source can know and only the
  // running system can say.
  property string searchQuery: ""
  readonly property var searchIndex: state.searchIndex !== undefined ? state.searchIndex : ({})
  readonly property string searchTerm: searchQuery.trim().toLowerCase()
  readonly property bool searching: searchTerm !== ""

  // Everything that names a setting counts, not just the setting: the heading
  // above it, the page it is on, and the heading that page sits under. So
  // "bluetooth" finds every setting on the Bluetooth page, none of which has
  // the word in its own name, and "blur" finds the eleven under Blur.
  function matchesTerm(label, description, group) {
    if (!searching) return true
    var hay = (String(label || "") + " " + String(description || "") + " " + String(group || "")).toLowerCase()
    return hay.indexOf(searchTerm) !== -1
  }

  // The menu names for a page: its own, the cluster it is drawn under, and
  // what it sits under in the header. All three are names a reader could
  // plausibly type — "configs" should find Tmux — and none of them is written
  // anywhere on the page itself.
  function pageNames(pageId) {
    var page = pageFor(pageId)
    // The rail's label counts as a name for every page under it: "system"
    // should find Disk, and "apps" should find Tmux, neither of which says so
    // anywhere on the page.
    return String(page.title || "") + " " + String(page.cluster || "")
  }

  function matchesOnPage(pageId, label, description, group) {
    return matchesTerm(label, description, String(group || "") + " " + pageNames(pageId))
  }

  // Rows ask about themselves, and are always on the open page.
  function rowMatches(label, description, group) {
    return matchesOnPage(pageId, label, description, group)
  }

  // A page whose own name matches is a match, whatever its settings are
  // called — and some pages, the device lists especially, have no names in
  // their source to match at all.
  function pageTitleMatches(pageId) {
    if (!searching) return false
    return matchesTerm("", "", pageNames(pageId))
  }

  // A page for an application you do not have is a page of settings with
  // nowhere to go. The binary is the test, not its config file: an application
  // can be installed and never yet configured, and a config can outlive the
  // thing it configured.
  function pageAvailable(id) {
    switch (id) {
    case "apps.tmux": return state.tmux === undefined || state.tmux.installed !== false
    case "apps.nvim": return state.nvim === undefined || state.nvim.installed !== false
    case "apps.herdr": return state.herdr === undefined || state.herdr.installed !== false
    default: return true
    }
  }

  function pageMatchCount(pageId) {
    if (!pageAvailable(pageId)) return 0
    if (!searching) return 0
    var entries = searchIndex[pageId]
    if (!entries) return 0
    var n = 0
    for (var i = 0; i < entries.length; i++)
      if (matchesOnPage(pageId, entries[i].label, entries[i].description, entries[i].group)) n++
    return n
  }

  // Everything that has to happen when a fresh state lands. One handler,
  // because a second `onStateChanged` on the same object is not a second
  // handler — it is "Property value set multiple times", and the whole file
  // fails to load.
  onStateChanged: {
    // An application removed while its page is open leaves the window on a
    // page that is no longer there; step off it.
    if (!pageAvailable(pageId)) pageId = "overview"
    // The claimed font, released once the state agrees it is in force.
    if (fontPending !== "" && String(state.font) === fontPending) fontPending = ""
  }

  function pageShows(pageId) {
    if (!pageAvailable(pageId)) return false
    return !searching || pageMatchCount(pageId) > 0 || pageTitleMatches(pageId)
  }

  // Searching onto a page with nothing on it would show an empty page; move to
  // the first page that has something instead.
  onSearchTermChanged: {
    if (!searching) return
    if (pageShows(pageId)) return
    // Walked from the nav model rather than from orderedPages: that list is a
    // binding on this very term, and read from inside the change it is still
    // the list for the term before, which lands you on a page that no longer
    // matches.
    for (var i = 0; i < navItems.length; i++) {
      var pages = navItems[i].pages
      for (var p = 0; p < pages.length; p++)
        if (pageShows(pages[p])) { pageId = pages[p]; return }
    }
  }

  // ---------------- keyboard navigation ------------------------------------
  //
  // One cursor runs down the settings of the open page, and a second one — the
  // sidebar — is reached with Alt. The vocabulary is the shell's own, the one
  // PanelKeyCatcher defines for every Omarchy panel: Up/Down or j/k to move,
  // Left/Right or h/l to change a value, Enter or Space to act, Tab to change
  // section, Escape to close.
  property var navRows: []
  property int navIndex: -1
  // Alt puts the cursor on the sidebar; moving in the page takes it back, so
  // Enter always acts on whichever list was last moved.
  property bool navInSidebar: false
  property int sidebarIndex: 0

  function registerNavRow(row) {
    var rows = navRows.slice()
    rows.push(row)
    navRows = rows
  }

  function unregisterNavRow(row) {
    var rows = []
    for (var i = 0; i < navRows.length; i++)
      if (navRows[i] !== row && navRows[i] !== null) rows.push(navRows[i])
    navRows = rows
    if (navIndex >= rows.length) navIndex = rows.length - 1
  }

  // Registration order follows construction, which is not reading order once a
  // page has groups that come and go. Sorting by where a row actually sits
  // keeps the cursor moving the way the page looks.
  function navOrdered() {
    var out = []
    for (var i = 0; i < navRows.length; i++) {
      var row = navRows[i]
      if (!row || !row.visible || !row.enabled) continue
      var point = row.mapToItem(bodyLoader, 0, 0)
      if (!point) continue
      out.push({ row: row, y: point.y })
    }
    out.sort(function(a, b) { return a.y - b.y })
    return out
  }

  function navCurrent() {
    var ordered = navOrdered()
    if (navIndex < 0 || navIndex >= ordered.length) return null
    return ordered[navIndex].row
  }

  function navSync() {
    var ordered = navOrdered()
    for (var i = 0; i < ordered.length; i++)
      ordered[i].row.current = (!navInSidebar && i === navIndex)
  }

  function navMove(delta) {
    var ordered = navOrdered()
    if (ordered.length === 0) return
    navInSidebar = false
    navIndex = navIndex < 0
      ? (delta > 0 ? 0 : ordered.length - 1)
      : Math.max(0, Math.min(ordered.length - 1, navIndex + delta))
    navSync()
    navReveal(ordered[navIndex])
  }

  function navJump(where) {
    var ordered = navOrdered()
    if (ordered.length === 0) return
    navInSidebar = false
    navIndex = where < 0 ? 0 : ordered.length - 1
    navSync()
    navReveal(ordered[navIndex])
  }

  // Keep the cursor on screen, with a margin so it never sits flush against
  // the edge it just arrived from.
  function navReveal(entry) {
    if (!entry) return
    var margin = Style.space(24)
    var top = entry.y - margin
    var bottom = entry.y + entry.row.height + margin
    if (top < bodyScroll.contentY) bodyScroll.contentY = Math.max(0, top)
    else if (bottom > bodyScroll.contentY + bodyScroll.height)
      bodyScroll.contentY = Math.min(Math.max(0, bodyScroll.contentHeight - bodyScroll.height),
                                     bottom - bodyScroll.height)
  }

  // The list column holds one rail's pages — six at most, and Apps' seven
  // under two headings — so it fits without scrolling, and the arithmetic that
  // used to scroll a twenty-six row rail to the cursor went with it.
  readonly property real listRowHeight: Style.spacing.controlHeight + Style.space(4)
  readonly property real listRowGap: Style.space(2)

  function navActivate() {
    if (navInSidebar) {
      var entry = listPages()[sidebarIndex]
      if (entry) pageId = entry
      // Enter on the sidebar takes the keyboard into the page it just opened,
      // which is the only thing left for it to mean once walking already
      // opened the page.
      navInSidebar = false
      navSync()
      return
    }
    var row = navCurrent()
    if (row) row.navActivate()
  }

  // Backspace on a changed setting is the (reset) beside its name. A setting
  // this window has not written has nothing to hand back, so the key does
  // nothing rather than something surprising.
  function navReset() {
    if (navInSidebar) return
    var row = navCurrent()
    if (row && row.changed) row.resetRequested()
  }

  // A field that has finished editing hands the keyboard back here; clearing
  // the field's own focus is not enough, since the focus has to land
  // somewhere and this is where the navigation keys live.
  function navTakeFocus() { keySink.forceActiveFocus() }

  // The legend at the foot of the window. Everything the keyboard can do here
  // would be fourteen keys and unreadable, so it says what the keys do *here*:
  // the ones that always apply, plus whatever the cursor is resting on.
  // Rows name their keys the way they read them — "\u2190\u2192" for the pair of
  // arrows — and the foot of the window draws one cap per key. A pair of
  // arrows in a single cap is a cap with two keys printed on it, so a string
  // of nothing but arrows is taken apart into the keys it names. Anything
  // with a name of its own ("Space") is one key however long it is.
  function navCaps(entry) {
    if (entry.keys !== undefined) return entry
    var key = String(entry.key || "")
    if (!/^[\u2190-\u2193]+$/.test(key) || key.length < 2)
      return { keys: [key], label: entry.label }
    return { keys: key.split(""), label: entry.label }
  }

  readonly property var navLegend: {
    var keys = []

    if (searchFocused) {
      keys.push({ keys: ["\u21b5"], label: strings.t("settingswindow.label.2", "To settings")})
      keys.push({ keys: ["esc"], label: strings.t("settingswindow.label.3", "Clear")})
      return keys
    }

    var row = navBlocker !== null ? navBlocker : navCurrent()
    var own = row && row.navKeys ? row.navKeys : []
    for (var i = 0; i < own.length; i++) keys.push(navCaps(own[i]))

    // Only offered when there is something to hand back.
    // A list row's ⌫ is not always a reset — a saved network's is Forget — so
    // the row names it, and "Reset" is only the default.
    if (row && row.changed === true)
      keys.push({ keys: ["\u232b"],
                  label: row.navResetLabel !== undefined && String(row.navResetLabel) !== ""
                    ? String(row.navResetLabel) : strings.t("settingswindow.navResetDefault", "Reset") })

    if (navBlocked) return keys

    keys.push({ keys: ["\u2191", "\u2193"], label: strings.t("settingswindow.label.4", "Move")})
    if (orderedPages.length > 1) keys.push({ keys: ["alt", "\u2191", "\u2193"], label: strings.t("settingswindow.label.5", "Change page")})
    keys.push({ keys: ["/"], label: strings.t("settingswindow.label.6", "Search")})
    keys.push({ keys: ["esc"], label: strings.t("settingswindow.label.7", "Close")})
    return keys
  }

  function navStep(delta) {
    if (navInSidebar) return
    var row = navCurrent()
    if (row) row.navStep(delta)
  }

  // What Alt walks: every page in sidebar order, an item's own pages included
  // on the way through. The number keys reach only the first ten items, and
  // walking just the open item's pages left everything from Power down —
  // twelve pages — unreachable from the keyboard except by searching for it.
  function listPages() { return orderedPages }

  function navSidebar(delta) {
    var pages = listPages()
    if (pages.length === 0) return
    // From the page on screen, every time, and not from where the last walk
    // ended: a click, a number key or the IPC can change the page in between,
    // and the walk then jumped from wherever it had stopped before.
    navInSidebar = true
    for (var i = 0; i < pages.length; i++)
      if (pages[i] === pageId) { sidebarIndex = i; break }
    sidebarIndex = Math.max(0, Math.min(pages.length - 1, sidebarIndex + delta))
    navSync()
    pageId = pages[sidebarIndex]
  }

  // A row that has taken the keyboard — an open dropdown, a field being typed
  // into — keeps it until it says otherwise. The row reports it rather than
  // the window deducing it, so a list rebuilt mid-edit cannot lose track of
  // who is holding the keys.
  property var navBlocker: null
  readonly property bool navBlocked: navBlocker !== null

  function setNavBlocked(row, blocking) {
    if (blocking) navBlocker = row
    else if (navBlocker === row) navBlocker = null
  }

  function hyprValue(key, fallback) {
    var value = hypr ? hypr[key] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // A refresh asked for while one is already out used to be dropped. The read
  // in flight had left before the write it would have shown, so the second of
  // two quick presses moved the file and nothing on screen — which reads as a
  // window that ignored you, not one that was busy. One is owed instead, and
  // runs when this one lands. Owed, not queued: any number of presses during
  // a read are answered by a single re-read, since the state is whatever it
  // is by the time it is asked.
  property bool refreshOwed: false

  function refresh() {
    if (stateProc.running) { refreshOwed = true; return }
    refreshOwed = false
    stateProc.command = ["bash", root.helperPath, "state"]
    stateProc.running = true
  }

  // Every mutation is the same shape: hand the helper a command, then re-read
  // the world once it settles rather than guessing what changed.
  function run(args) {
    root.busy = true
    root.lastArgs = args
    applyProc.command = ["bash", root.helperPath].concat(args)
    applyProc.running = true
  }

  // ---------------- what a change is worth re-reading ----------------------
  //
  // A click used to be answered by re-reading everything: the theme, the
  // plugins, the battery, bluetoothctl — for moving a widget one place up.
  // Which parts a command can have changed is knowable, and it is knowable
  // *here*, from the command itself, rather than at the two hundred and eighty
  // places that call this. A page cannot forget to declare what it changed if
  // it never declares anything.
  //
  // Under-naming is safe by construction: the whole document is read a beat
  // behind every one of these, so a command whose effects are wider than its
  // slices leaves the window a moment late, never wrong. Anything not named
  // here — reset, a menu flow, whatever is added next — waits for that read
  // and is simply as fast as it was before.
  property var lastArgs: []

  // A live page's own reader, re-run once the write it asked for has actually
  // finished. Pages used to call their poller on the line after `run`, which
  // races the write: `news read` marks a headline in the store while the poll
  // that would notice is already reading it, so the star cleared five seconds
  // later on the next tick instead of at once.
  function pollFor(args) {
    if (!args || args.length === 0) return
    switch (String(args[0])) {
      case "overview": pollOverview(); return
      case "news": pollOverview(); return
      case "disk": pollDisk(); return
      case "processes": pollProcesses(); return
      case "packages": pollPackages(); return
      // Switching one on or off changes the document as well, so this is the
      // page's own reading and not a substitute for the slices beside it.
      case "plugin": pollPlugins(); return
      case "apps": pollApps(); return
      case "usage": pollUsage(); return
      case "about": pollAbout(); return
      // The command has returned, so the wait is over either way.
      case "wifi": wifiConnecting = ""; pollWifi(); return
      // A new theme brings a new set of wallpapers with it, so both lists are
      // stale the moment either is set.
      case "theme": readThemes(); readWallpapers(); return
      case "set": if (args.length > 1 && String(args[1]) === "theme") {
          readThemes(); readWallpapers()
        }
        return
      case "bluetooth": pollBluetooth(); return
    }
  }

  function slicesFor(args) {
    if (!args || args.length === 0) return []
    switch (String(args[0])) {
      case "bar": return ["bar"]
      case "plugin": return ["plugins", "pluginUpdates", "selfUpdate"]
      case "keys": return ["bindings"]
      case "workspaces": return ["workspaces"]
      case "compose": return ["compose"]
      case "devices": return ["devices", "hyprChanged"]
      case "herdr": return ["herdr", "hyprChanged"]
      case "tmux": return ["tmux", "hyprChanged"]
      case "nvim": return ["nvim", "hyprChanged"]
      case "wifi": return ["wifi"]
      case "bluetooth": return ["bluetooth"]
      case "language": return ["language"]
      case "audio": return ["audio"]
      case "power": return ["power"]
      // The three live pages keep their own readings and poll for them, so a
      // command of theirs has nothing in the state document to re-read — bar
      // the night light, which the bar's own indicator shares with them.
      case "overview": return args.length > 2 && String(args[2]) === "nightlight"
        ? ["nightlight"] : []
      case "disk": return []
      case "processes": return []
      case "packages": return []
      case "apps": return []
      case "usage": return []
      case "news": return []
      case "about": return []
      case "set": return slicesForKey(args.length > 1 ? args[1] : "")
    }
    return []
  }

  // The commands whose slices name everything they can change. Only what has
  // been checked: a workspace rule touches the store and Hyprland's window
  // rules, and nothing else this window shows.
  function slicesSuffice(args) {
    if (!args || args.length === 0) return false
    var command = String(args[0])
    if (command === "workspaces") return true
    // Ending a process or trimming a drive changes nothing this window holds:
    // the page that asked for it polls, and it is the only thing that has to
    // hear back. Re-reading the whole document for a mount would be seconds
    // spent to learn nothing.
    return command === "overview" || command === "disk" || command === "processes"
      || command === "packages" || command === "apps" || command === "usage" || command === "news"
      || command === "about"
      // A language switch restarts the shell: the slice read answers first,
      // and the fresh window whole-reads again anyway.
      || command === "language"
      // Opening an editor changes nothing until the editor is closed.
      || command === "hosts"
      // Starting the migration only detaches it; the Overview poll is what
      // hears how it went.
      || command === "migrate"
      // Brightness is the screen in front of you and nothing this window holds.
      || command === "display"
  }

  // `set` is the one command that is many: what it touches is named by its
  // key. Every setting also carries whether it now differs from what it was,
  // which is why the changed list comes along with all of them.
  function slicesForKey(key) {
    var name = String(key || "")
    if (name.indexOf("bar-") === 0) return ["bar", "hyprChanged"]
    if (name.indexOf("idle-") === 0) return ["idle", "hyprChanged"]
    if (name.indexOf("monitor") === 0) return ["monitors", "hyprChanged"]
    if (name.indexOf("herdr:") === 0) return ["herdr", "hyprChanged"]
    if (name.indexOf("tmux:") === 0) return ["tmux", "hyprChanged"]
    if (name.indexOf("nvim:") === 0) return ["nvim", "hyprChanged"]
    if (name === "font") return ["font", "hyprChanged"]
    if (name === "text-scale") return ["textScale", "hyprChanged"]
    if (name === "nightlight") return ["nightlight"]
    // A theme moves more than it is asked to — colours, fonts, the bar — so
    // it is left to the whole read rather than guessed at in parts.
    if (name === "theme") return []
    return ["hypr", "hyprChanged"]
  }

  function refreshSlices(names) {
    if (!names || names.length === 0) return
    if (sliceProc.running) { sliceOwed = names; return }
    sliceOwed = []
    sliceProc.command = ["bash", root.helperPath, "state"].concat(names)
    sliceProc.running = true
  }

  property var sliceOwed: []

  Process {
    id: sliceProc
    stdout: StdioCollector {
      waitForEnd: true
      // The keys that came back replace the ones on the window; everything
      // else stays as it was. A fresh object, because assigning the same one
      // back tells no binding anything.
      onStreamFinished: {
        try {
          var part = JSON.parse(text)
          if (!part || typeof part !== "object") return
          var next = {}
          for (var k in root.state) next[k] = root.state[k]
          for (var j in part) next[j] = part[j]
          root.state = next
          root.loaded = true
          // Wi-Fi and Bluetooth are not in the document any more, so nothing
          // here can be newer than what their pages are already polling.
        } catch (e) {
          // The whole document is already on its way; it will say the same.
        }
      }
    }
    onRunningChanged: if (!running && root.sliceOwed.length > 0) {
      var owed = root.sliceOwed
      root.sliceOwed = []
      root.refreshSlices(owed)
    }
  }

  function set(key, value) { run(["set", key, String(value)]) }
  function setHypr(key, value) { set(key, value) }

  Process {
    id: stateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (next && typeof next === "object") {
            root.state = next
            root.loaded = true
          }
        } catch (e) {
          // A partial read leaves the last good state on screen.
        }
      }
    }
    onRunningChanged: if (!running && root.refreshOwed) root.refresh()
  }

  Process {
    id: applyProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = text.trim()
    }
    onRunningChanged: if (!running) {
      root.busy = false
      // What the change was about, answered now; everything else a beat
      // later. The wait used to come first, so a click that had already
      // landed sat there for 400ms before the window even asked what it did.
      root.refreshSlices(root.slicesFor(root.lastArgs))
      root.pollFor(root.lastArgs)
      // Theme and font switches ripple through other processes; re-reading a
      // beat later picks up settled values rather than mid-switch ones — and
      // catches anything the slices above did not name. A command whose slice
      // is the whole story skips it: the full read costs seconds under load,
      // and landing after a second click it put the older value back on
      // screen until its own settle read corrected it.
      if (!root.slicesSuffice(root.lastArgs)) settleTimer.restart()
    }
  }

  Timer {
    id: settleTimer
    interval: 400
    onTriggered: root.refresh()
  }

  // ---------------- sections ----------------------------------------------
  // A section is either a page of its own or a parent holding pages; the
  // sidebar renders parents as headings and only pages are selectable.
  property string pageId: "overview"
  // A new page brings new rows, so the cursor starts at its top rather than
  // wherever it happened to be on the page before.
  onPageIdChanged: {
    navIndex = -1
    navRows = []
    bodyLoader.setSource(sectionSource(pageId), { app: root })
  }

  // A page may say something truer about itself than its file path — what the
  // adapter is connected to, say. When it does, that is what the header shows.
  // A page that is a list of things can be open on one of them, and then the
  // page's own name is no longer where the reader is. The title is the page's
  // to override for exactly that case, with the way back beside it: back
  // belongs next to the name of the thing you are backing out of, not at the
  // top of the body under it.
  readonly property string pageHeaderTitle: bodyLoader.item
    && bodyLoader.item.headerTitle !== undefined
    && String(bodyLoader.item.headerTitle) !== ""
    ? String(bodyLoader.item.headerTitle) : pageFor(pageId).title
  readonly property bool pageHeaderBack: bodyLoader.item
    && bodyLoader.item.headerBack !== undefined && bodyLoader.item.headerBack === true
  function pageHeaderBackTriggered() {
    if (bodyLoader.item && bodyLoader.item.headerBackTriggered !== undefined)
      bodyLoader.item.headerBackTriggered()
  }

  readonly property string pageHeaderNote: bodyLoader.item && bodyLoader.item.headerNote !== undefined
    ? String(bodyLoader.item.headerNote) : ""

  // Two levels, and the second one only when it has something to say.
  //
  // The rail is ten destinations, always on screen, each on a number key. Five
  // of them *are* a page — Overview, Network, Bluetooth, Sound, Displays — and
  // for those the list beside the rail is not there at all: a column holding
  // one row is a column asking to be clicked through for nothing. The other
  // five open a list of pages, and Apps splits its list under two headings.
  //
  // This replaced a single flat rail of twenty-six rows. Flat put every page
  // one click away and made none of them findable: the eye has no landmarks in
  // a list that long, so it read top-to-bottom every time. Ten icons are
  // *remembered* — the shape of the grid becomes the map — and the pages under
  // them are a short list you scan rather than a long one you search.
  // One sidebar, grouped under quiet headers, rather than a rail of ten icons
  // beside a list of that rail's pages.
  //
  // The rail made every page two keystrokes away and made none of them
  // visible: you had to know which of ten icons held Neovim before you could
  // see that it existed. Here every destination is on screen at once, in
  // clusters, and an item holding more than one page reveals them indented
  // beneath it while it is open — so the second column exists only where there
  // is something to put in it, and only for as long as you are there.
  //
  // Connectivity leads, because that is what people open this window for
  // mid-task; then the desktop they look at, the machine underneath, and the
  // software on top.
  readonly property var navBlocks: [
    { title: "", items: [
      { id: "overview", label: strings.t("settingswindow.label.8", "Overview"), icon: "\uf0e4", pages: ["overview"] },
      { id: "net", label: strings.t("settingswindow.label.9", "Network"), icon: "\uf1eb", pages: ["network"] },
      { id: "bt", label: strings.t("settingswindow.label.10", "Bluetooth"), icon: "\uf293", pages: ["bluetooth"] }
    ] },
    { title: strings.t("settingswindow.title.1", "Experience"), items: [
      { id: "look", label: strings.t("settingswindow.label.11", "Appearance"), icon: "\uf1fc", pages: ["theme", "font", "wallpaper", "branding"] },
      { id: "fx", label: strings.t("settingswindow.label.12", "Effects"), icon: "\uf0d0", pages: ["effects"] },
      { id: "bar", label: strings.t("settingswindow.label.13", "Bar"), icon: "\uf0c9", pages: ["bar"] },
      { id: "wm", label: strings.t("settingswindow.label.14", "Windows"), icon: "\uf2d0", pages: ["windows", "layout", "groups"] },
      { id: "ws", label: strings.t("settingswindow.label.15", "Workspaces"), icon: "\uf00a", pages: ["workspaces"] },
      { id: "kb", label: strings.t("settingswindow.label.16", "Keyboard"), icon: "\uf11c", pages: ["keyboard", "bindings", "compose"] },
      { id: "ptr", label: strings.t("settingswindow.label.17", "Mouse & touchpad"), icon: "\uf245", pages: ["pointer"] },
      { id: "sound", label: strings.t("settingswindow.label.18", "Sound"), icon: "\uf028", pages: ["audio"] },
      { id: "displays", label: strings.t("settingswindow.label.19", "Displays"), icon: "\uf108", pages: ["displays"] }
    ] },
    { title: strings.t("settingswindow.title.2", "System"), items: [
      // A bolt: the page is the battery and the profile the machine runs at,
      // which a desktop has too. A power symbol read as shutting the machine
      // down, and a battery promised a page a desktop does not get.
      { id: "pwr", label: strings.t("settingswindow.label.20", "Power"), icon: "\uf0e7", pages: ["power"] },
      { id: "idle", label: strings.t("settingswindow.label.21", "Idle & Lock"), icon: "\uf023", pages: ["idle"] },
      { id: "security", label: strings.t("settingswindow.label.22", "Security"), icon: "\uf132", pages: ["security"] },
      { id: "disk", label: strings.t("settingswindow.label.23", "Storage"), icon: "\uf0a0", pages: ["disk"] },
      { id: "proc", label: strings.t("settingswindow.label.24", "Processes"), icon: "\uf080", pages: ["processes"] },
      { id: "time", label: strings.t("settingswindow.label.25", "Date & Time"), icon: "\uf017", pages: ["datetime"] },
      { id: "lang", label: strings.t("settingswindow.label.34", "Language"), icon: "\uf1ab", pages: ["language"] },
      { id: "about", label: strings.t("settingswindow.label.26", "About"), icon: "\uf05a", pages: ["about"] }
    ] },
    { title: strings.t("settingswindow.title.3", "Apps & Packages"), items: [
      { id: "defaults", label: strings.t("settingswindow.label.27", "Default Apps"), icon: "\uf008", pages: ["apps.defaults"] },
      { id: "apps", label: strings.t("settingswindow.label.28", "Apps"), icon: "\uf009", pages: ["apps.list"] },
      { id: "pkg", label: strings.t("settingswindow.label.29", "Packages"), icon: "\uf187", pages: ["packages"] },
      { id: "plugins", label: strings.t("settingswindow.label.30", "Plugins"), icon: "\uf1e6", pages: ["plugins"] },
      { id: "usage", label: strings.t("settingswindow.label.31", "Usage"), icon: "\uf201", pages: ["usage"] },
      { id: "cfg", label: strings.t("settingswindow.label.32", "Configs"), icon: "\uf121", pages: ["apps.herdr", "apps.tmux", "apps.nvim"] }
    ] },
    // Last and apart: everything above configures the desktop, and this is
    // the one block about the window itself.
    { title: strings.t("settingswindow.title.4", "OmaControl"), items: [
      { id: "omacontrol", label: strings.t("settingswindow.label.33", "Settings"), icon: "\uf013", pages: ["omacontrol"] }
    ] }
  ]

  // Flat, for everything that walks items rather than blocks: the number keys,
  // and finding which item holds the open page.
  readonly property var navItems: {
    var out = []
    for (var b = 0; b < navBlocks.length; b++)
      for (var i = 0; i < navBlocks[b].items.length; i++) out.push(navBlocks[b].items[i])
    return out
  }

  function itemPages(item) {
    var out = []
    for (var i = 0; i < item.pages.length; i++)
      if (pageShows(item.pages[i])) out.push(item.pages[i])
    return out
  }

  function itemOf(id) {
    for (var i = 0; i < navItems.length; i++)
      if (navItems[i].pages.indexOf(id) !== -1) return navItems[i]
    return navItems[0]
  }


  // Every page's title, in the order the rail walks them. Most of the window
  // wants the pages and not the nesting, and walking two levels everywhere it
  // asked is how the tree version grew its bugs.
  readonly property var pageTitles: ({

    "overview": strings.t("settingswindow.page.overview", "Overview"),
    "network": strings.t("settingswindow.page.network", "Network"),
    "bluetooth": strings.t("settingswindow.page.bluetooth", "Bluetooth"),
    "audio": strings.t("settingswindow.page.audio", "Audio"),
    "displays": strings.t("settingswindow.page.displays", "Displays"),
    "bar": strings.t("settingswindow.page.bar", "Bar"),
    "effects": strings.t("settingswindow.page.effects", "Effects"),
    // "General", not "Windows": the rail is already called Windows, and a page
    // that repeats its rail's name tells the reader nothing — the crumb read
    // "WINDOWS / Windows". General is what it is: the settings that are about
    // windows in general rather than about the layout, the workspaces or the
    // groups beside it.
    "windows": strings.t("settingswindow.page.windows", "General"),
    "layout": strings.t("settingswindow.page.layout", "Layout"),
    "workspaces": strings.t("settingswindow.page.workspaces", "Workspaces"),
    "groups": strings.t("settingswindow.page.groups", "Groups"),
    "keyboard": strings.t("settingswindow.page.keyboard", "Keyboard"),
    "bindings": strings.t("settingswindow.page.bindings", "Keybindings"),
    "compose": strings.t("settingswindow.page.compose", "Compose Keys"),
    "pointer": strings.t("settingswindow.page.pointer", "Mouse & Touchpad"),
    "power": strings.t("settingswindow.page.power", "Power"),
    "idle": strings.t("settingswindow.page.idle", "Idle & Lock"),
    "security": strings.t("settingswindow.page.security", "Security"),
    "disk": strings.t("settingswindow.page.disk", "Disk"),
    "processes": strings.t("settingswindow.page.processes", "Processes"),
    "datetime": strings.t("settingswindow.page.datetime", "Date & Time"),
    "language": strings.t("settingswindow.page.language", "Language"),
    "about": strings.t("settingswindow.page.about", "About"),
    "apps.list": strings.t("settingswindow.page.apps.list", "Apps"),
    "apps.defaults": strings.t("settingswindow.page.apps.defaults", "Defaults"),
    "packages": strings.t("settingswindow.page.packages", "Packages"),
    "plugins": strings.t("settingswindow.page.plugins", "Plugins"),
    "usage": strings.t("settingswindow.page.usage", "Agent usage"),
    "apps.herdr": strings.t("settingswindow.page.apps.herdr", "Herdr"),
    "apps.tmux": strings.t("settingswindow.page.apps.tmux", "Tmux"),
    "apps.nvim": strings.t("settingswindow.page.apps.nvim", "Neovim"),
    "theme": strings.t("settingswindow.page.theme", "Theme"),
    "font": strings.t("settingswindow.page.font", "Font"),
    "wallpaper": strings.t("settingswindow.page.wallpaper", "Wallpaper"),
    "branding": strings.t("settingswindow.page.branding", "Branding"),
    "omacontrol": strings.t("settingswindow.page.omacontrol", "OmaControl settings"),
  })

  // Which item is open. Driven by the page rather than held on its own: an
  // item that could disagree with the page on screen is one that will.
  readonly property var openItem: itemOf(pageId)
  // The pages under it, shown indented while it is open — and only when there
  // is more than one, since an item that is a page needs no list of itself.
  readonly property var openItemPages: openItem.pages.length > 1 ? itemPages(openItem) : []

  // Every page in sidebar order, which is what the arrows walk.
  readonly property var orderedPages: {
    var out = []
    for (var i = 0; i < navItems.length; i++) {
      var pages = itemPages(navItems[i])
      for (var p = 0; p < pages.length; p++) out.push(pages[p])
    }
    return out
  }

  // What the sidebar draws: the blocks, emptied of items whose pages the
  // search or a missing application has taken away, and blocks emptied of the
  // items that went with them.
  readonly property var sidebarBlocks: {
    var out = []
    for (var b = 0; b < navBlocks.length; b++) {
      var items = []
      for (var i = 0; i < navBlocks[b].items.length; i++) {
        var item = navBlocks[b].items[i]
        var pages = itemPages(item)
        if (pages.length === 0) continue
        var hits = 0
        for (var p = 0; p < pages.length; p++) hits += pageMatchCount(pages[p])
        items.push({ id: item.id, label: item.label, icon: item.icon,
                     pages: pages, matches: hits })
      }
      if (items.length > 0) out.push({ title: navBlocks[b].title, items: items })
    }
    return out
  }

  // Picking an item opens its first page that has anything to show, so a
  // search narrowing an item to one page still lands on that page.
  function pickItem(id) {
    for (var i = 0; i < navItems.length; i++) {
      if (navItems[i].id !== id) continue
      var pages = itemPages(navItems[i])
      if (pages.length > 0) { pageId = pages[0]; return }
      // Nothing in it matches the search; open it anyway rather than
      // swallowing the keypress.
      if (navItems[i].pages.length > 0) pageId = navItems[i].pages[0]
      return
    }
  }

  function pageFor(id) {
    // The crumb is the item's label, and only where the item is a grouping
    // rather than a page: "Overview / Overview" says nothing twice.
    var item = itemOf(id)
    return {
      title: pageTitles[id] !== undefined ? pageTitles[id] : "",
      crumb: item.pages.length > 1 ? item.label : "",
      cluster: item.label
    }
  }

  // Pages live one to a file under sections/; the window only has to know
  // which file answers to which id.
  function sectionSource(id) {
    switch (id) {
    case "overview": return "sections/OverviewSection.qml"
    case "theme": return "sections/ThemeSection.qml"
    case "font": return "sections/FontSection.qml"
    case "wallpaper": return "sections/WallpaperSection.qml"
    case "branding": return "sections/BrandingSection.qml"
    case "packages": return "sections/PackagesSection.qml"
    case "usage": return "sections/UsageSection.qml"
    case "about": return "sections/AboutSection.qml"
    case "disk": return "sections/DiskSection.qml"
    case "processes": return "sections/ProcessesSection.qml"
    case "security": return "sections/SecuritySection.qml"
    case "bar": return "sections/BarSection.qml"
    case "workspaces": return "sections/WorkspacesSection.qml"
    case "windows": return "sections/WindowsSection.qml"
    case "keyboard": return "sections/KeyboardSection.qml"
    case "bindings": return "sections/BindingsSection.qml"
    case "pointer": return "sections/PointerSection.qml"
    case "displays": return "sections/DisplaysSection.qml"
    case "idle": return "sections/IdleSection.qml"
    case "plugins": return "sections/PluginsSection.qml"
    case "compose": return "sections/ComposeSection.qml"
    case "datetime": return "sections/DateTimeSection.qml"
    case "language": return "sections/LanguageSection.qml"
    case "network": return "sections/NetworkSection.qml"
    case "bluetooth": return "sections/BluetoothSection.qml"
    case "layout": return "sections/LayoutSection.qml"
    case "effects": return "sections/EffectsSection.qml"
    case "groups": return "sections/GroupsSection.qml"
    case "power": return "sections/PowerSection.qml"
    case "audio": return "sections/AudioSection.qml"
    case "apps.list": return "sections/AppsSection.qml"
    case "apps.defaults": return "sections/DefaultsSection.qml"
    case "apps.tmux": return "sections/TmuxSection.qml"
    case "apps.nvim": return "sections/NvimSection.qml"
    case "omacontrol": return "sections/OmaControlSection.qml"
    // Named rather than left to the default: the search index reads these
    // cases to learn which file holds which page, and a page reachable only
    // through the default is a page it cannot see.
    case "apps.herdr": return "sections/HerdrSection.qml"
    default: return "sections/HerdrSection.qml"
    }
  }

  // A layer-shell surface rather than an ordinary window: a toplevel is the
  // tiler's to place, so it landed beside whatever was open and only floated
  // for someone who had written a Hyprland rule for it by hand. On the overlay
  // layer the settings open above the current windows on any machine, with
  // nothing to install and nothing to configure — the same way the Omarchy
  // menu and the bar panels do it.
  PanelWindow {
    id: window
    visible: false
    // A layer surface goes to whichever screen it is given, and given none it
    // goes to the first one — so on two monitors the settings could open on
    // the one you are not looking at. Chosen when it opens rather than bound:
    // a window that hops to another screen while you are reading it is worse
    // than one that stays where it was opened.
    screen: root.openedOn !== null ? root.openedOn : null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omacontrol"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Dimming what is behind says the settings are in front of it, and gives
    // the click-outside-to-close target somewhere to live.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.hide()
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      // One size, wherever it opens. It used to be nine tenths of the screen,
      // which reads right on a laptop panel and falls apart on anything
      // larger: a settings row is a name on the left and a value on the right,
      // and at 2300 points wide those two are half a metre apart with nothing
      // in between. So the window is the size a page of settings wants to be
      // read at, and only a screen smaller than that shrinks it.
      //
      // In logical points, not pixels, so a HiDPI screen gets the same window
      // at twice the density rather than half the size.
      // A width the settings are read at, and the height of the screen it is
      // on. Nine tenths either way: a settings row is a name and a value, and
      // at 2300 points wide those two are half a metre apart — but a page of
      // them is a list, and a list wants the room.
      readonly property real preferredWidth: Style.space(1200)
      width: Math.round(Math.min(preferredWidth, window.width * 0.9))
      height: Math.round(window.height * 0.9)
      color: root.background
      radius: Style.cornerRadius
      border.width: 1
      border.color: root.hairline

      // The card is not the scrim: a click that lands on it stays on it.
      MouseArea { anchors.fill: parent }

    // Asked, because this is the one thing here that cannot be undone by
    // clicking again.
    ConfirmDialog {
      id: resetAllDialog
      anchors.fill: parent
      z: 100
      message: root.changedSettings.length === 1
        ? strings.t("settingswindow.resetOneMessage", "Reset the one setting changed from this window?")
        : strings.t("settingswindow.resetAllMessage", "Reset all %1 settings changed from this window?").arg(root.changedSettings.length)
      confirmText: strings.t("settingswindow.confirmText.1", "Reset all")
      cancelText: strings.t("settingswindow.cancelText.1", "Cancel")
      background: root.background
      foreground: root.foreground
      fontFamily: root.fontFamily
      onConfirmed: {
        opened = false
        root.run(["reset", "--all"])
      }
      onCanceled: opened = false
    }

    ConfirmDialog {
      id: askDialog
      anchors.fill: parent
      z: 100
      cancelText: strings.t("settingswindow.cancelText.2", "Cancel")
      background: root.background
      foreground: root.foreground
      fontFamily: root.fontFamily
      onConfirmed: {
        opened = false
        var action = root.pendingConfirm
        root.pendingConfirm = null
        if (action) action()
      }
      onCanceled: { opened = false; root.pendingConfirm = null }
    }

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: true

      // Focus given back to the scope itself lands on whichever child held it
      // last — the very field being left — so it is given to a sink that
      // wants nothing, and the navigation keys are handled above it.
      Item { id: keySink; focus: true }

      // The vocabulary every Omarchy panel uses, plus Alt for the sidebar and
      // Home/End for the ends of a long page. Keys.BeforeItem is what lets
      // Up/Down drive the cursor rather than being eaten by the Flickable —
      // except when a row has taken the keyboard for itself.
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var alt = (event.modifiers & Qt.AltModifier) !== 0
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0

        // A row holding the keyboard gets every key, Escape included: closing
        // an open dropdown is what Escape means while one is open.
        // The dialog has no keys of its own, so it borrows the window's while
        // it is up, and nothing else gets a look in.
        if (askDialog.opened) {
          if (event.key === Qt.Key_Escape) { askDialog.canceled(); event.accepted = true }
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                   || event.text === "h" || event.text === "l"
                   || event.key === Qt.Key_Tab) {
            askDialog.selectedIndex = askDialog.selectedIndex === 1 ? 0 : 1
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                     || event.key === Qt.Key_Space) {
            if (askDialog.selectedIndex === 1) askDialog.confirmed()
            else askDialog.canceled()
            event.accepted = true
          }
          return
        }

        if (resetAllDialog.opened) {
          if (event.key === Qt.Key_Escape) { resetAllDialog.opened = false; event.accepted = true }
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                   || event.text === "h" || event.text === "l"
                   || event.key === Qt.Key_Tab) {
            resetAllDialog.selectedIndex = resetAllDialog.selectedIndex === 1 ? 0 : 1
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                     || event.key === Qt.Key_Space) {
            if (resetAllDialog.selectedIndex === 1) resetAllDialog.confirmed()
            else resetAllDialog.opened = false
            event.accepted = true
          }
          return
        }

        if (root.navBlocked || root.searchFocused) return

        // Undoing everything is a big enough thing to want a key of its own,
        // and a modifier keeps it clear of the Backspace that resets one.
        if (event.key === Qt.Key_Backspace && ctrl) {
          if (root.changedSettings.length > 0) resetAllDialog.opened = true
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true; return }


        // The two things every search box answers to.
        if (event.text === "/" || (ctrl && event.key === Qt.Key_F)) {
          if (root.searchInput) {
            root.searchInput.forceActiveFocus()
            root.searchInput.selectAll()
          }
          event.accepted = true
          return
        }

        if (event.key === Qt.Key_Down || event.text === "j") {
          alt ? root.navSidebar(1) : root.navMove(1)
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Up || event.text === "k") {
          alt ? root.navSidebar(-1) : root.navMove(-1)
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Right || event.text === "l") {
          root.navStep(1); event.accepted = true; return
        }
        if (event.key === Qt.Key_Left || event.text === "h") {
          root.navStep(-1); event.accepted = true; return
        }
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.navActivate(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
          root.navReset(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Home) { root.navJump(-1); event.accepted = true; return }
        if (event.key === Qt.Key_End) { root.navJump(1); event.accepted = true; return }
        // Tab moves between the two lists rather than through every control,
        // which is what the sidebar and a page of settings actually are.
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          if (root.navInSidebar) { root.navInSidebar = false; root.navSync() }
          else root.navSidebar(0)
          event.accepted = true; return
        }
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

      // ---------------- window header --------------------------------------
      // Above both columns, because what it holds belongs to the window and
      // not to either of them: what this window is, what it has changed, and
      // the two keys that are true on every page. The name used to sit at the
      // top of the sidebar, where it was read as a heading for the menu under
      // it rather than as the name of the window.
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: Style.spacing.controlHeight + Style.space(8)
        color: root.chrome

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.panelPadding
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("settingswindow.text.1", "OmaControl")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          // A number in the name's own weight would be read as part of it.
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.selfVersion !== ""
            text: root.selfVersion
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.panelPadding
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          // Beside the count rather than at the foot of the sidebar: being
          // behind is a fact about the window, like what it has changed, and
          // the foot of a long menu is the last place anyone reads.
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.busy && root.loaded && root.selfBehind > 0
            text: strings.t("settingswindow.updateAvailable", "\uf0e7  Update available (")
              + strings.tn("update.commitsBehind", root.selfBehind, "1 commit behind").arg(root.selfBehind) + ")"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.underline: updateMouse.containsMouse
            rightPadding: Style.space(8)

            MouseArea {
              id: updateMouse
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.selfId !== "") root.run(["plugin", "update", root.selfId])
            }
          }

          // What has changed is a fact about the window, not about the page
          // on screen — the live pages change nothing this window tracks, and
          // a count beside their name read as though it were about them. So
          // the count and what undoes it sit here, together, once.
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.changedLabel !== ""
            text: root.changedLabel
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Ui.Chip {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.changedSettings.length > 0
            text: strings.t("settingswindow.text.3", "Undo all")
            onClicked: resetAllDialog.opened = true
          }

          Ui.KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            key: "esc"
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.spacing.hairline
        color: root.hairline
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        // ---------------- sidebar ------------------------------------------
        // One column, not two. Every destination is on screen at once, in
        // clusters under quiet headers, and the pages of the open item appear
        // indented beneath it — so a second column exists only where there is
        // something to put in it, and only while you are there.
        Rectangle {
          Layout.fillHeight: true
          Layout.preferredWidth: Style.space(262)
          color: root.surface

          ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: Style.space(12)
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.bottomMargin: Style.space(14)
            spacing: Style.space(10)

            // At the top of the column it filters. It lived in the window
            // header on the argument that a search crosses every rail — but
            // the rail is gone, and what a search now narrows is this one
            // sidebar, item by item, in front of you.
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: searchField.implicitHeight

              Text {
                id: searchGlyph
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconSmall
                z: 1
              }

              // Built only while the window is shown. A live text field reads
              // the clipboard whenever another application changes it, with no
              // size limit and no deadline, so a hidden window that kept one
              // would let any application stall the whole shell without a
              // paste. The query outlives the field, so reopening still shows
              // the last search.
              Loader {
                id: searchField
                anchors.fill: parent
                active: root.shown
                sourceComponent: searchFieldComponent
              }

              Component {
                id: searchFieldComponent

                TextField {
                  Component.onCompleted: text = root.searchQuery
                  // The kit's own knob, not an override of the `leftPadding` it
                  // derives from it — that binding also carries the border
                  // inset, and replacing it means re-deriving something the kit
                  // already gets right.
                  horizontalPadding: Style.space(26)
                  placeholderText: strings.t("settingswindow.placeholderText.1", "Search settings")
                  foreground: root.foreground
                  accent: root.accent
                  font.family: root.fontFamily
                  onTextChanged: root.searchQuery = text
                  // Escape gives the keyboard back to the page rather than
                  // closing the window out from under a search.
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      if (text !== "") text = ""
                      root.navTakeFocus()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                               || event.key === Qt.Key_Down) {
                      root.navTakeFocus()
                      root.navMove(1)
                      event.accepted = true
                    }
                  }
                }
              }
            }

            Flickable {
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              contentWidth: width
              contentHeight: sidebarColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: sidebarColumn
                width: parent.width
                spacing: Style.space(11)

                Repeater {
                  model: root.sidebarBlocks

                  delegate: Column {
                    id: block
                    required property var modelData
                    required property int index
                    width: sidebarColumn.width
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      visible: block.modelData.title !== ""
                      leftPadding: Style.space(11)
                      bottomPadding: Style.space(2)
                      text: block.modelData.title
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.capitalization: Font.AllUppercase
                      font.letterSpacing: Style.space(1)
                    }

                    Repeater {
                      model: block.modelData.items

                      delegate: Column {
                        id: entry
                        required property var modelData
                        readonly property bool current: modelData.id === root.openItem.id
                        width: parent.width
                        spacing: Style.space(1)

                        Rectangle {
                          width: parent.width
                          implicitHeight: Style.spacing.controlHeight + Style.space(4)
                          radius: Style.cornerRadius
                          color: entry.current ? root.accent
                            : (itemMouse.containsMouse ? Ui.Palette.hover : "transparent")

                          MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pickItem(entry.modelData.id)
                          }

                          // A fixed column for the glyph, with the glyph
                          // centred in it by its ink. See ui/GlyphIcon.qml:
                          // these glyphs share neither an advance nor an ink
                          // width, so a label anchored to the glyph's own
                          // right edge starts at a different x on every row.
                          Ui.GlyphIcon {
                            id: itemIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Style.space(11)
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: entry.modelData.icon
                            size: Style.font.body
                            // On the accent fill the glyph is struck from
                            // onAccent, never from white: a light accent would
                            // swallow it.
                            color: entry.current ? Ui.Palette.onAccent : root.muted
                          }

                          Text {
                            textFormat: Text.PlainText
                            anchors.left: itemIcon.right
                            anchors.leftMargin: Style.space(11)
                            anchors.right: itemCount.left
                            anchors.rightMargin: Style.space(8)
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.label
                            elide: Text.ElideRight
                            color: entry.current ? Ui.Palette.onAccent : root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                          }

                          // How many settings under this item the search
                          // found. Only while searching: a count beside every
                          // item at rest is a number nobody asked for.
                          Text {
                            id: itemCount
                            textFormat: Text.PlainText
                            anchors.right: parent.right
                            anchors.rightMargin: Style.space(11)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.searching && entry.modelData.matches > 0
                            text: entry.modelData.matches
                            color: entry.current ? Ui.Palette.onAccent : root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }
                        }

                        // The pages under the open item, and only when it
                        // holds more than one: an item that is a page needs no
                        // list of itself.
                        Repeater {
                          model: entry.current && entry.modelData.pages.length > 1
                            ? entry.modelData.pages : []

                          delegate: Rectangle {
                            id: subPage
                            required property var modelData
                            readonly property bool current: modelData === root.pageId
                            width: entry.width
                            implicitHeight: Style.spacing.controlHeight
                            radius: Style.cornerRadius
                            color: pageMouse.containsMouse ? Ui.Palette.hover : "transparent"

                            MouseArea {
                              id: pageMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.pageId = subPage.modelData
                            }

                            // A tick rather than a fill: the item above is
                            // already filled, and two filled things one under
                            // the other read as two selections.
                            Rectangle {
                              anchors.left: parent.left
                              anchors.leftMargin: Style.space(18)
                              anchors.verticalCenter: parent.verticalCenter
                              width: Style.space(3)
                              height: Style.space(15)
                              radius: width
                              color: parent.current ? root.accent : "transparent"
                            }

                            Text {
                              textFormat: Text.PlainText
                              anchors.left: parent.left
                              anchors.leftMargin: Style.space(32)
                              anchors.right: parent.right
                              anchors.rightMargin: Style.space(10)
                              anchors.verticalCenter: parent.verticalCenter
                              text: root.pageTitles[subPage.modelData] !== undefined
                                ? root.pageTitles[subPage.modelData] : subPage.modelData
                              elide: Text.ElideRight
                              color: parent.current ? root.foreground : root.muted
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: parent.current
                            }
                          }
                        }
                      }
                    }

                    // The line the design draws under each cluster. Between
                    // blocks only: a rule under the last one separates the
                    // list from nothing.
                    Item {
                      width: parent.width
                      implicitHeight: Style.space(12)
                      visible: block.index < root.sidebarBlocks.length - 1

                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Style.spacing.hairline
                        color: root.hairline
                      }
                    }
                  }
                }

                // Said about the search rather than about any one item: an
                // emptied sidebar is otherwise a blank column that reads as a
                // window which failed to load.
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.searching && root.sidebarBlocks.length === 0
                  padding: Style.space(10)
                  text: strings.t("settingswindow.text.4", "Nothing here for what you typed.")
                  wrapMode: Text.WordWrap
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

          }
        }

        Rectangle {
          Layout.fillHeight: true
          Layout.preferredWidth: Style.spacing.hairline
          color: root.hairline
        }


        // ---------------- body ---------------------------------------------
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0

          // The page names itself once, here, under the thing it belongs to.
          // The crumb is not decoration: a flat rail of twenty-six rows tells
          // the reader where they can go and nothing about where they are, and
          // this is the line that answers it.
          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(64)

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.panelPadding
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width * 0.5
              spacing: Style.space(2)

              // Only where the rail is a grouping rather than a page.
              // "Overview / Overview" and "Network / Network" say nothing
              // twice, and a crumb that is always there stops being read.
              Text {
                textFormat: Text.PlainText
                visible: text !== ""
                text: root.pageFor(root.pageId).crumb || ""
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                // Small caps is what makes it read as a label rather than as
                // a first line of the page.
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Style.space(1)
              }

              Row {
                spacing: Style.space(10)

                // The arrow is the title's, sized with it and on its
                // baseline: a chip here would be a control beside a heading
                // rather than the heading saying where it came from.
                Text {
                  textFormat: Text.PlainText
                  visible: root.pageHeaderBack
                  anchors.baseline: pageTitleText.baseline
                  text: "\u2039"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  font.bold: true

                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pageHeaderBackTriggered()
                  }
                }

                Text {
                  id: pageTitleText
                  textFormat: Text.PlainText
                  text: root.pageHeaderTitle
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  font.bold: true
                }

                // On the title's baseline rather than centred on it: two
                // sizes centred against each other read as two things, and
                // this is the page said once and then qualified.
                Text {
                  textFormat: Text.PlainText
                  anchors.baseline: pageTitleText.baseline
                  visible: root.pageHeaderNote !== ""
                  text: root.pageHeaderNote
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            Row {
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.panelPadding
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(9)

              // A control that governs the whole page belongs beside the page
              // name rather than repeated as the first row of the body.
              Loader {
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: bodyLoader.item && bodyLoader.item.headerControl
                  ? bodyLoader.item.headerControl : null
              }

            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.spacing.hairline
            color: root.hairline
          }

          // The clip runs a gutter outside the page, and the page sits back
          // in by the same gutter, so nothing moves on screen. A row's cursor
          // band reaches into the margin to give its text room, and clipped at
          // the page edge it was cut back to flush with the words.
          Flickable {
            id: bodyScroll
            readonly property real gutter: Math.min(Style.space(10), Style.spacing.panelPadding)
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Style.spacing.panelPadding - gutter
            clip: true
            contentWidth: width
            contentHeight: bodyLoader.implicitHeight + gutter * 2
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Loader {
              id: bodyLoader
              x: bodyScroll.gutter
              y: bodyScroll.gutter
              width: bodyScroll.width - bodyScroll.gutter * 2
              // setSource passes `app` in as an initial property, so a page's
              // bindings never evaluate against a null window.
              Component.onCompleted: setSource(root.sectionSource(root.pageId), { app: root })
            }
          }

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            Layout.margins: Style.spacing.panelPadding
            Layout.topMargin: 0
            visible: root.lastError !== ""
            text: root.lastError
            color: Ui.Palette.urgent
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.spacing.hairline
        color: root.hairline
      }

      // ---------------- keyhint bar ----------------------------------------
      // Across the foot of the window, under both columns. It follows the
      // cursor rather than listing everything: the keys that always apply,
      // and whatever the row under the cursor answers to. What is happening
      // right now — a write in flight, the first state still loading — goes
      // at the far end, where a status line goes.
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: Style.spacing.controlHeight + Style.space(4)
        color: root.chrome

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.panelPadding
          anchors.verticalCenter: parent.verticalCenter
          // Wide enough between entries that each key and what it does read as
          // one thing, rather than the whole bar reading as one long line.
          spacing: Style.space(18)

          Repeater {
            model: root.navLegend

            delegate: Row {
              id: legendKey
              required property var modelData
              spacing: Style.space(5)

              // A hint can answer to more than one key — the arrows, or Alt
              // and an arrow — and a cap per key is what says they are
              // pressed together rather than one key called "alt ↑".
              Repeater {
                model: legendKey.modelData.keys

                delegate: Ui.KeyCap {
                  required property var modelData
                  anchors.verticalCenter: parent.verticalCenter
                  key: modelData
                }
              }

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: legendKey.modelData.label
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.panelPadding
          anchors.verticalCenter: parent.verticalCenter
          visible: root.statusNote !== ""
          text: root.statusNote
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
      }
    }
    }
  }

  // ---------------- sections ----------------------------------------------


  // The bar's centre section is anchored on a widget id; offer the ids the
  // user actually has in their bar rather than a hardcoded list.
  function barWidgetIds() {
    var ids = []
    if (!plugins) return ids
    for (var i = 0; i < plugins.length; i++) {
      var kinds = plugins[i].kinds || []
      if (kinds.indexOf("bar-widget") !== -1) ids.push(plugins[i].id)
    }
    return ids
  }

  // ---------------- shared row components ----------------------------------


}
