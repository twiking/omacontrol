import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The always-on power half: the sleep and hibernate timeouts and the lid
// action are enforced while the window is closed, so they live here beside
// the service rather than inside the window, which exists only while
// someone is changing things.
//
// Omarchy's own idle service reads only the screensaver and lock timeouts,
// so idle.suspend and idle.hibernate are this plugin's to enforce — and its
// Stay Awake indicator pauses these timers along with its own, since "keep
// this machine awake" has to mean both. logind suspends on lid close by
// default, which is Omarchy's default too: "suspend" needs nothing of ours,
// every other choice holds logind off with a handle-lid-switch inhibitor,
// and only "hibernate" is ours to act on — "lock" and "nothing" are
// Omarchy's own lid binding's to carry out once logind is held off.
//
// The shell hands a third-party service no live copy of shell.json (only
// clones of omarchy.idle see shellConfig), so the file is read and watched
// here directly.
Item {
  id: root

  property string pluginDir: ""
  readonly property string helperPath: pluginDir + "/bin/omacontrol"
  readonly property string home: Quickshell.env("HOME")
  readonly property string indicatorsDir: home + "/.local/state/omarchy/indicators"

  // ---------------- config ---------------------------------------------------

  property int suspendTimeout: 0
  property int hibernateTimeout: 0
  property string lidAction: "suspend"
  property bool stayAwake: false

  // logind's own lid action is suspend, so only the other three choices have
  // to be taken out of its hands.
  readonly property bool lidManaged: lidAction !== "suspend"

  function applyConfig(text) {
    var config = {}
    try {
      config = JSON.parse(String(text || ""))
    } catch (error) {
      // A missing or corrupt file is the defaults, not an error: a fresh
      // install has no shell.json until something writes one.
      config = {}
    }

    var idle = (config && config.idle) || {}
    var suspend = Math.max(0, Math.floor(Number(idle.suspend) || 0))
    var hibernate = Math.max(0, Math.floor(Number(idle.hibernate) || 0))
    var lid = String((config && config.omacontrol && config.omacontrol.lid) || "suspend")
    if (["nothing", "lock", "suspend", "hibernate"].indexOf(lid) < 0) lid = "suspend"

    var changed = suspend !== root.suspendTimeout
      || hibernate !== root.hibernateTimeout
      || lid !== root.lidAction
    if (!changed) return

    var timersMoved = suspend !== root.suspendTimeout || hibernate !== root.hibernateTimeout
    root.suspendTimeout = suspend
    root.hibernateTimeout = hibernate
    root.lidAction = lid
    console.log("omacontrol power: config sleep=" + suspend
      + "s hibernate=" + hibernate + "s lid=" + lid)
    // A running cycle carries deadlines taken from the old config; cancel it
    // and let the re-armed monitor start a fresh one from the new values.
    if (timersMoved) cancelIdleCycle("config")
  }

  function applyStayAwake(value) {
    var enabled = !!value
    if (root.stayAwake === enabled) return
    root.stayAwake = enabled
    console.log("omacontrol power: stay awake " + (enabled ? "on" : "off"))
    if (enabled) cancelIdleCycle("stay-awake")
    else Qt.callLater(root.handleIdleChanged)
  }

  function probeStayAwake() {
    if (!stayAwakeProbe.running) stayAwakeProbe.running = true
  }

  // ---------------- the idle cycle --------------------------------------------

  property bool monitorArmed: false
  property bool idledThisCycle: false

  readonly property bool timersWanted: !root.stayAwake
    && (root.suspendTimeout > 0 || root.hibernateTimeout > 0)

  // The monitor reports idle at the earlier of the two deadlines, so the
  // cycle is entered before either can be due. With both off the value is
  // inert: the monitor is disarmed.
  readonly property int monitorTimeout: {
    var smallest = 0
    if (root.suspendTimeout > 0) smallest = root.suspendTimeout
    if (root.hibernateTimeout > 0 && (smallest === 0 || root.hibernateTimeout < smallest)) smallest = root.hibernateTimeout
    return Math.max(1, smallest)
  }

  // Quickshell keeps the previous idle notification registered when only the
  // timeout changes — lgse/sandman documents the same quirk and the same fix:
  // toggle the monitor, which re-registers it.
  function rearmIdleMonitor() {
    root.monitorArmed = false
    Qt.callLater(function() { root.monitorArmed = root.timersWanted })
  }

  onTimersWantedChanged: rearmIdleMonitor()
  onMonitorTimeoutChanged: rearmIdleMonitor()

  function handleIdleChanged() {
    // The monitor is disarmed while the timers are unwanted, but a fire
    // racing a Stay Awake change must not arm a cycle anyway.
    if (!root.timersWanted) return
    if (idleMonitor.isIdle) startIdleCycle()
    else cancelIdleCycle("activity")
  }

  function startIdleCycle() {
    if (root.idledThisCycle) return
    console.log("omacontrol power: idle cycle start (sleep=" + root.suspendTimeout
      + "s, hibernate=" + root.hibernateTimeout + "s)")
    root.idledThisCycle = true
    // Deadlines are taken once per cycle, the way Omarchy's idle service
    // takes them: a config change cancels the cycle rather than moving a
    // timer that is already running.
    if (root.suspendTimeout > 0) armDeadline(suspendTimer, root.suspendTimeout, "suspend")
    if (root.hibernateTimeout > 0) armDeadline(hibernateTimer, root.hibernateTimeout, "hibernate")
  }

  // The monitor reports idle at the earlier of the two deadlines, so each
  // timer runs only for what is left of its own deadline after that —
  // Omarchy's idle service subtracts the same first timeout for the same
  // reason. Without it, a single timeout of X would fire at 2X of idle.
  function armDeadline(timer, timeout, which) {
    var delay = (timeout - root.monitorTimeout) * 1000
    if (delay <= 0) {
      fireDeadline(which)
      return
    }
    timer.interval = delay
    timer.restart()
  }

  function fireDeadline(which) {
    // Whichever deadline comes first ends the cycle: a suspended machine
    // never reaches the later one, and a timer left running would fire the
    // moment the machine wakes.
    if (!root.idledThisCycle) return
    root.idledThisCycle = false
    suspendTimer.stop()
    hibernateTimer.stop()
    // Stay Awake won the race between the probe and the fire: the cycle is
    // over without an action.
    if (root.stayAwake) {
      console.log("omacontrol power: idle cycle cancel (stay-awake)")
      return
    }
    if (which === "hibernate") {
      console.log("omacontrol power: hibernating after " + root.hibernateTimeout + "s idle")
      hibernateProcess.running = true
    } else {
      console.log("omacontrol power: suspending after " + root.suspendTimeout + "s idle")
      suspendProcess.running = true
    }
  }

  function cancelIdleCycle(reason) {
    suspendTimer.stop()
    hibernateTimer.stop()
    if (!root.idledThisCycle) return
    root.idledThisCycle = false
    console.log("omacontrol power: idle cycle cancel (" + reason + ")")
  }

  // Enabled is this service's own flag rather than the wanted state, so the
  // re-arm dance above can take it off before putting it back.
  IdleMonitor {
    id: idleMonitor
    enabled: root.monitorArmed
    timeout: root.monitorTimeout
    // An application holding an idle inhibitor (a playing video) holds these
    // timers off as well, exactly as it holds off Omarchy's own.
    respectInhibitors: true
    onIsIdleChanged: root.handleIdleChanged()
  }

  Timer {
    id: suspendTimer
    repeat: false
    onTriggered: root.fireDeadline("suspend")
  }

  Timer {
    id: hibernateTimer
    repeat: false
    onTriggered: root.fireDeadline("hibernate")
  }

  Process {
    id: suspendProcess
    command: ["bash", root.helperPath, "power", "sleep"]
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("omacontrol power: suspend failed")
    }
  }

  Process {
    id: hibernateProcess
    command: ["bash", root.helperPath, "power", "hibernate"]
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("omacontrol power: hibernate failed")
    }
  }

  // ---------------- the lid ---------------------------------------------------

  property bool lidClosed: false
  property bool lidStateKnown: false
  property bool lidRestarting: false

  // The inhibitor lives exactly as long as the monitor process: while it
  // runs, logind does nothing on lid close and every close is a D-Bus
  // property change this service sees instead. Running is set imperatively —
  // a bound running could never be restarted, and the deliberate stop below
  // is what releases the inhibitor.
  function ensureLidMonitor() {
    if (root.lidManaged && !lidMonitorProcess.running && !root.lidRestarting) {
      lidMonitorProcess.running = true
    } else if (!root.lidManaged && lidMonitorProcess.running) {
      lidMonitorProcess.running = false
    }
  }

  function probeLidState() {
    if (!lidStateProcess.running) lidStateProcess.running = true
  }

  function applyLidClosed(closed) {
    var next = !!closed
    if (!root.lidStateKnown) {
      // The lid may have been closed before the shell was; the first reading
      // is a baseline, never an action.
      root.lidStateKnown = true
      root.lidClosed = next
      return
    }
    if (root.lidClosed === next) return
    root.lidClosed = next
    if (next) handleLidClosed()
  }

  function handleLidClosed() {
    if (root.lidAction !== "hibernate") return
    console.log("omacontrol power: lid closed, hibernating")
    if (!lidActionProcess.running) lidActionProcess.running = true
  }

  Timer {
    // The watchdog keeps the inhibitor in step with the config within a
    // second, without a binding that could hold the process alive against a
    // deliberate stop.
    id: lidWatchdog
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.ensureLidMonitor()
  }

  Timer {
    id: lidRestartTimer
    interval: 50
    onTriggered: {
      root.lidRestarting = false
      root.ensureLidMonitor()
    }
  }

  Process {
    id: lidMonitorProcess
    command: ["systemd-inhibit", "--what=handle-lid-switch", "--mode=block", "--who=OmaControl", "--why=Manage the configured lid-close action", "gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).indexOf("LidClosed") >= 0) root.probeLidState()
      }
    }
    onExited: function(exitCode) {
      // A deliberate stop comes with lidManaged already false; anything else
      // is the monitor dying under this service, and the beat keeps a
      // process that dies instantly from spinning.
      if (!root.lidManaged || root.lidRestarting) return
      root.lidRestarting = true
      lidRestartTimer.restart()
    }
  }

  Process {
    id: lidStateProcess
    command: ["busctl", "get-property", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "LidClosed"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyLidClosed(/b\s+true/.test(String(text)))
    }
  }

  Process {
    id: lidActionProcess
    command: ["bash", root.helperPath, "power", "lid", "closed"]
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("omacontrol power: lid action failed")
    }
  }

  // ---------------- watching --------------------------------------------------

  FileView {
    id: shellConfigFile
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }

  // Omarchy's Stay Awake pauses its own idle timers by dropping a file into
  // the indicators directory. The directory is watched rather than the file
  // because the file does not exist while awake, and a FileView cannot
  // observe a file that is absent.
  FileView {
    id: stayAwakeWatcher
    path: root.indicatorsDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.probeStayAwake()
  }

  // The exit code is the whole answer: zero means the indicator is present.
  // The directory is created the way Omarchy's own idle service creates it, so
  // the watch survives a fresh profile where it does not exist yet.
  Process {
    id: stayAwakeProbe
    command: ["sh", "-c", "mkdir -p \"$1\"; [[ -f \"$1/stay-awake\" ]]", "sh", root.indicatorsDir]
    onExited: function(exitCode) { root.applyStayAwake(exitCode === 0) }
  }

  Component.onCompleted: {
    // Baselines, so the first change after startup is a transition rather
    // than a discovery: stay-awake as the previous session left it, and a
    // lid that was closed before the shell was.
    root.probeStayAwake()
    root.probeLidState()
  }
}
