import QtQuick
import Quickshell
import Quickshell.Io

// The plugin's always-on half: it owns the settings window and the IPC route
// that opens it, and installs the launcher entry.
//
// The window lives here rather than in the bar widget because it is not the
// bar's. A gear in the bar is one way in, `omarchy-shell omacontrol toggle`
// and the launcher entry are others, and the two should not depend on the
// first: with the window in Panel.qml, taking the gear out of the bar takes
// the plugin out of shell.json, and the plugin with it. Enabled through
// `plugins[]` and with no bar entry at all, everything below still works.
//
// The launcher entry makes the window reachable from SUPER+SPACE like any
// other application. Omarchy has no install hook and no manifest field for
// registering one, so a plugin that wants to be an app has to do it itself,
// on enable.
//
// Only a file carrying the X-OmaControl-Managed marker is ever written or
// deleted: an entry you wrote yourself at that path is left alone.
Scope {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // ---------------- window lifecycle ---------------------------------------
  //
  // The lifecycle a plugin surface is expected to carry, in the names the rest
  // of Omarchy uses. open/close and show/hide are the same pair twice, because
  // both names are in circulation and neither is worth surprising anyone over.
  //
  // The window is loaded on first use rather than at startup — the shell
  // process is long-running and a settings window nobody has opened yet should
  // not cost it anything.
  readonly property bool opened: windowLoader.item ? windowLoader.item.shown : false

  function show() { windowLoader.active = true; if (windowLoader.item) windowLoader.item.show() }
  // Opening on a named page is how a job that had to tear this window down
  // brings it back where it was: the loader is asynchronous, so the page is
  // remembered until there is an item to give it to.
  property string pendingPage: ""
  function showPage(page) {
    pendingPage = String(page || "")
    show()
    applyPendingPage()
  }
  function applyPendingPage() {
    if (pendingPage === "" || !windowLoader.item) return
    windowLoader.item.pageId = pendingPage
    pendingPage = ""
  }
  function hide() { if (windowLoader.item) windowLoader.item.hide() }
  function open() { show() }
  function close() { hide() }
  function toggle() {
    if (opened) hide()
    else show()
  }

  // ---------------- the gear's badge -----------------------------------------
  //
  // Which of the Overview page's switches are on, and whether the machine is
  // on a network at all, for the badge on the gear.
  // One watcher however many bars there are, and only while one of them is
  // showing the gear: a plugin enabled with no bar entry has nothing to badge.
  readonly property string helperPath: sourceDir + "/bin/omacontrol"
  property var switches: ({})
  property int switchWatchers: 0
  function watchSwitches(on) { switchWatchers = Math.max(0, switchWatchers + (on ? 1 : -1)) }

  Process {
    id: switchesWatch
    command: ["bash", root.helperPath, "overview", "watch"]
    running: root.switchWatchers > 0
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        try {
          var next = JSON.parse(line)
          if (next && typeof next === "object") root.switches = next
        } catch (e) {
          // A half-written line is not worth acting on; the next change
          // brings the whole state again.
        }
      }
    }
    // A watcher that dies while it is still wanted comes back, though not
    // faster than one try in five seconds if it keeps dying.
    onRunningChanged: {
      if (running) return
      root.switches = ({})
      if (root.switchWatchers > 0) switchesRestart.start()
    }
  }

  Timer {
    id: switchesRestart
    interval: 5000
    onTriggered: if (root.switchWatchers > 0) switchesWatch.running = true
  }

  IpcHandler {
    target: "omacontrol"
    function show(): void { root.show() }
    function showPage(page: string): void { root.showPage(page) }
    function hide(): void { root.hide() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  Loader {
    id: windowLoader
    active: false
    asynchronous: true
    source: Qt.resolvedUrl("SettingsWindow.qml")
    onLoaded: {
      if (item) item.show()
      root.applyPendingPage()
    }
  }

  // ---------------- the always-on power half -------------------------------
  //
  // The sleep and hibernate timeouts and the lid action are enforced while
  // the window is closed, so they live here rather than in the window.
  PowerService {
    pluginDir: root.sourceDir
  }

  // ---------------- launcher entry -----------------------------------------

  // Where this plugin's own files are, from this file's URL rather than the
  // manifest: the shell strips __sourceDir from a third-party manifest before
  // handing it over, so asking there found nothing on every install and the
  // launcher entry was never written. The URL is percent-encoded, and a home
  // directory with a space in it is a path the scripts below must still find.
  readonly property string sourceDir: {
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") !== 0) return ""
    try { url = decodeURIComponent(url.substring(7)) } catch (e) { return "" }
    return url.replace(/\/$/, "")
  }

  readonly property string dest: Quickshell.env("HOME") + "/.local/share/applications/omacontrol.desktop"
  readonly property string marker: "^X-OmaControl-Managed=true$"

  // $1 template, $2 destination, $3 marker, $4 icon. Every failure is a quiet
  // exit: a launcher entry is a convenience, and nothing here is worth
  // interrupting the shell over.
  // The destination is a predictable path in a directory anyone on the machine
  // could have written to first, so nothing here writes through a name it did
  // not create: a symlink at either path is left alone rather than followed,
  // and the rendered entry is built in a fresh random sibling.
  readonly property string installScript:
      '[ -f "$1" ] || exit 0\n'
    + '[ -L "$2" ] && exit 0\n'
    + 'if [ -e "$2" ] && ! grep -q "$3" "$2"; then exit 0; fi\n'
    + 'mkdir -p "${2%/*}" || exit 0\n'
    + 'tmp=$(mktemp "$2.omacontrol.XXXXXX") || exit 0\n'
    + 'sed "s|@ICON@|$4|" "$1" >"$tmp" || { rm -f "$tmp"; exit 0; }\n'
    + 'chmod 644 "$tmp"\n'
    + 'if cmp -s "$tmp" "$2"; then rm -f "$tmp"; else mv -f "$tmp" "$2"; fi\n'

  readonly property string removeScript:
      '[ -L "$1" ] && exit 0\n'
    + 'grep -q "$2" "$1" 2>/dev/null && rm -f "$1"\n'

  property bool installed: false

  Component.onCompleted: {
    if (installed || sourceDir === "") return
    installed = true
    Quickshell.execDetached(["sh", "-c", installScript, "sh",
                             sourceDir + "/omacontrol.desktop", dest, marker, sourceDir + "/icon.png"])
  }

  // Reached on disable and on remove alike: omarchy-plugin-remove disables
  // first, so the service is torn down while the entry is still ours.
  Component.onDestruction: {
    if (!installed) return
    Quickshell.execDetached(["sh", "-c", removeScript, "sh", dest, marker])
  }
}
