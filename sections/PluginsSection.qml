import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// Every plugin this shell has, what each one is, and what is known about it.
// A plugin is someone else's code running inside the process that draws the
// bar, so the page answers three questions rather than one: is it on, is it
// current, and who wrote it. The third is the one nothing else here could
// answer — it comes from plugins.omarchy.org, which is the network, so it is
// cached, stamped, and the page says how old it is.
//
// It reports as much as it configures, so the readings poll and are not in the
// state document. `plugins` stays there for the Bar page's widget ids.
Ui.SectionBody {
  id: page
  property var app: null

  readonly property var report: app.pluginsReport !== undefined
    && app.pluginsReport !== null ? app.pluginsReport : ({})
  readonly property var items: report.items !== undefined ? report.items : []

  // What the update sweep has learned so far, keyed by plugin id: still
  // checking, and how many commits are waiting (-1 not a git checkout,
  // -2 the fetch failed, -3 not fetched because the address holds a sign-in). Both are replaced wholesale rather than mutated,
  // since that is what re-evaluates the rows' bindings.
  property var checking: ({})
  // Seeded from the last sweep's cache, so leaving the page and coming back
  // shows what was already learned instead of an empty list.
  property var behind: (app.state.pluginUpdates && app.state.pluginUpdates.results) || ({})
  // What the incoming commits say, keyed by plugin id — the sweep read them
  // off the same FETCH_HEAD it counted, so a row can say what an update is
  // before it is taken.
  property var changes: (app.state.pluginUpdates && app.state.pluginUpdates.changes) || ({})
  // And what upstream is calling itself at that commit, off the same read: the
  // version the Update button would actually install, which is not always the
  // one the marketplace has listed.
  property var upstream: (app.state.pluginUpdates && app.state.pluginUpdates.versions) || ({})
  property double checkedAt: (app.state.pluginUpdates && app.state.pluginUpdates.checkedAt) || 0
  property bool checked: checkedAt > 0

  // Adding and removing hand off to a terminal flow that outlives
  // the window's own refresh, so the list is re-read a few times afterwards
  // rather than once, 400ms later, while the clone is still downloading.
  Timer {
    id: catchUp
    interval: 3000
    repeat: true
    property int ticks: 0
    onTriggered: {
      page.app.refresh()
      page.app.pollPlugins()
      if (++ticks >= 10) stop()
    }
  }

  function handOff(args) {
    app.run(args)
    catchUp.ticks = 0
    catchUp.restart()
  }

  // What each plugin declares and occupies is a local read and polls; what the
  // marketplace says is a request, so it is asked for on open and the reader
  // decides whether one is owed. Free whenever it is not.
  Component.onCompleted: {
    app.fetchPluginDirectory()
    if (working) updateWatch.start()
  }

  Timer {
    interval: 20000
    running: app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: page.app.pollPlugins()
  }

  // Updating happens without a terminal: upstream's flow is non-interactive
  // with --yes, and the only thing the terminal added was the question this
  // page has already answered — the row says how many commits are coming and
  // what they say.
  //
  // The work is detached from the window for the same reason: a child process
  // would be killed part-way through its own git merge when the shell reloads
  // its plugins. So the page does not own the work; it watches the cache the
  // work reports into, and picks up an update already in flight when it is
  // built again.
  property var updating: (app.state.pluginUpdates && app.state.pluginUpdates.running) || ({})
  property var updateResult: (app.state.pluginUpdates && app.state.pluginUpdates.last) || ({})
  // Adding one is the same work in the same cache: a clone lands in the
  // directory the shell watches, so this window goes down and comes back
  // with the answer. There is one at a time and no id to key it by.
  property var adding: (app.state.pluginUpdates && app.state.pluginUpdates.adding) || null
  property var addResult: (app.state.pluginUpdates && app.state.pluginUpdates.lastAdd) || null

  readonly property bool addingNow: adding !== null && adding !== undefined

  readonly property bool anyUpdating: {
    for (var k in updating) return true
    return false
  }
  // One at a time: both take the shell's plugins down and back up, and two
  // at once is two reloads racing over the same directory.
  readonly property bool working: anyUpdating || addingNow
  onWorkingChanged: if (working) updateWatch.start()

  function updateOne(id) {
    if (updateProc.running || page.working) return
    // Optimistic, so the spinner starts on the click rather than on the poll:
    // the reply below replaces it either way.
    var next = {}
    for (var k in page.updating) next[k] = page.updating[k]
    next[id] = 1
    page.updating = next
    app.startPluginUpdate(id)
  }

  // Both the start and the watch below answer with the same document — the
  // cache — so there is one place that takes it in, and the window is what
  // asks for it either way.
  Connections {
    target: page.app
    function onPluginUpdateCacheChanged() { page.absorb(page.app.pluginUpdateCache) }
  }

  function absorb(d) {
    if (!d) return
    page.updating = d.running || ({})
    page.updateResult = d.last || ({})
    page.adding = d.adding || null
    page.addResult = d.lastAdd || null
    page.behind = d.results || page.behind
    page.changes = d.changes || page.changes
    page.upstream = d.versions || page.upstream
    if (d.checkedAt) page.checkedAt = d.checkedAt
  }

  // Only while something is in flight, and only while this page is the one on
  // screen: a plugin update is a git fetch and a merge, not a state anyone
  // needs polled the rest of the time.
  Timer {
    id: updateWatch
    interval: 1000
    repeat: true
    running: false
    onTriggered: {
      if (!page.working) { stop(); page.app.refresh(); page.app.pollPlugins(); return }
      page.app.pollPluginUpdates()
    }
  }

  // One button, because from the reader's side there is one question: go and
  // ask. Both halves of the answer are the network — a fetch per plugin for
  // what is waiting, one request for what the marketplace says — and neither
  // is worth a button of its own.
  function checkUpdates() {
    if (updateProc.running) return
    // Only the ones the sweep will actually report on. It walks the plugins
    // directory, and a built-in is not in it — marked as checking, thirty-six
    // of them would sit there saying so until the sweep it is not part of
    // finished.
    var pending = {}
    for (var i = 0; i < items.length; i++)
      if (items[i].firstParty !== true) pending[items[i].id] = true
    page.checking = pending
    updateProc.running = true
    app.refreshPluginDirectory()
  }

  // The one reader this page still owns, and the reason it does: the sweep
  // prints a plugin's verdict the moment that plugin's own fetch settles, and
  // the page acts on each line as it arrives so the cells fill one row at a
  // time instead of all at the end. The window's `Poller` collects a whole
  // document and hands it over once, which is the right shape for everything
  // else here and the wrong one for this.
  Process {
    id: updateProc
    command: ["bash", page.app.helperPath, "plugin", "updates"]
    stdout: SplitParser {
      splitMarker: "\n"
      // A fresh object each time, not the same one mutated: assigning back
      // an unchanged reference tells the rows nothing, and their bindings
      // never re-run.
      onRead: function(line) {
        var parts = line.split("\t")
        if (parts.length < 2) return
        var id = parts[0].trim()
        var next = {}
        for (var k in page.behind) next[k] = page.behind[k]
        next[id] = parseInt(parts[1], 10)
        page.behind = next
        var pending = {}
        for (var p in page.checking) if (p !== id) pending[p] = true
        page.checking = pending
      }
    }
    onRunningChanged: if (!running) {
      page.checking = ({})
      page.checked = true
      // The sweep also wrote the cache; re-reading keeps checkedAt honest.
      page.app.refresh()
    }
  }

  readonly property bool busy: updateProc.running || app.pluginDirectorySyncing

  // ------------------------------------------------------------ one of them
  //
  // A drill-in rather than a panel over the table, the same shape Apps and
  // Packages use: what there is to say about a plugin is a dozen facts and
  // four actions, and inlining that under a row would push the rest of the
  // list off the screen and lose the row it came from.
  property string openPlugin: ""

  // Asked here rather than in a terminal, the way Apps asks for a new web app
  // or TUI: `omarchy-plugin-add` takes every answer as an argument when given
  // all of them, so the window can ask in its own fields and still leave the
  // clone, the validation and the enabling to it. It shares the drill-in with
  // an open plugin — one page showing one subject.
  property bool creating: false

  function startCreating() {
    openPlugin = ""
    urlField.text = ""
    urlField.touched = false
    addEnable = true
    creating = true
  }

  // On, the way the flow this replaces defaults: a plugin nobody switches on
  // does nothing at all, and the notice above the button is where the reason
  // to leave it off is put.
  property bool addEnable: true

  readonly property var opened: {
    for (var i = 0; i < items.length; i++)
      if (String(items[i].id) === openPlugin) return items[i]
    return null
  }

  // With the tick, the way the row it was opened from carries it: a reader
  // who came here from a verified row should not have to wonder whether the
  // page is about the same plugin.
  readonly property string headerTitle: creating ? "Add a plugin"
    : opened === null ? ""
    : String(opened.name) + (opened.verified === true ? "  \uf058" : "")
  readonly property bool headerBack: openPlugin !== "" || creating
  function headerBackTriggered() { openPlugin = ""; creating = false }

  // Nothing. What a plugin is, and the warning about the window going away
  // mid-update, both go in a group note — the window draws a header note as a
  // bare Text on the title's baseline, with no width and nothing clipping it,
  // which is right for a two-word qualifier and wrong for a sentence.
  readonly property string headerNote: ""

  property Component headerControl: Component {
    Row {
      spacing: Style.space(8)

      Ui.Chip {
        visible: page.openPlugin === "" && !page.creating
        text: "Add a plugin"
        onClicked: page.startCreating()
      }

      Ui.Chip {
        visible: page.openPlugin === "" && !page.creating
        text: page.busy ? "Checking…" : "Check for updates"
        onClicked: page.checkUpdates()
      }
    }
  }

  // Which plugins the reader is asking for. Yours by default: the built-in
  // ones have no version of their own to compare, nothing to remove and no
  // size that is theirs, and there are thirty-six of them in front of the
  // twenty that were actually chosen.
  property string filter: "yours"

  // Three of them split the list by where a plugin came from; the fourth
  // asks a different question, and is offered only while it has an answer.
  // It is what the reader came for on the day something is waiting, and a
  // chip that narrows twenty rows to none is a dead end on every other day.
  readonly property var filters: {
    var out = [
      // Two halves of one question — where did this come from — so they are
      // phrased alike. "Ones you installed" beside "Comes with Omarchy" was
      // a noun phrase beside a verb phrase, and the pair read as two
      // unrelated filters rather than as a split of the same list.
      { id: "yours", title: "Installed by you" },
      { id: "builtin", title: "Built into Omarchy" }
    ]
    if (waiting.length > 0) out.push({ id: "updates", title: "Ready to update" })
    return out
  }

  // A filter that stops having anything to show has to hand the reader back
  // a list rather than an empty table: the last update finishing would
  // otherwise take the chip away and leave its emptiness on screen.
  onWaitingChanged: if (filter === "updates" && waiting.length === 0) filter = "yours"

  // Six of the columns are about a plugin somebody chose, and the built-in
  // list has no answer for any of them: the author is Omarchy thirty-seven
  // times, no built-in manifest declares a version so there is nothing
  // installed or available to compare, nothing measures a size for code that
  // lives outside the plugins directory, and the marketplace's two figures —
  // which the catalogue does carry, so those are not empty columns — are the
  // one repository's stars on every row and hearts for something nobody
  // chose to install. They go with that list, headings and cells together.
  readonly property bool builtinList: filter === "builtin"

  readonly property var shown: {
    var out = []
    if (filter === "updates") return waiting
    for (var i = 0; i < items.length; i++) {
      var p = items[i]
      if (filter === "yours" && p.firstParty === true) continue
      if (filter === "builtin" && p.firstParty !== true) continue
      out.push(p)
    }
    return out
  }

  readonly property int yoursCount: {
    var n = 0
    for (var i = 0; i < items.length; i++) if (items[i].firstParty !== true) n++
    return n
  }

  // The ones with something waiting, and the ones that have just been told to
  // take it: an update that has reported back is still worth saying so until
  // the reader has read what it said.
  readonly property var waiting: {
    var out = []
    for (var i = 0; i < items.length; i++) {
      var id = String(items[i].id)
      var n = behind[id] === undefined ? 0 : behind[id]
      if (n > 0 || updating[id] !== undefined || fresh(updateResult[id])) out.push(items[i])
    }
    return out
  }

  // What the last update said stands until a check goes and asks again —
  // after that the row's answer is the check's. Without that bound a word
  // about something taken last week sits in the list for ever, which was
  // tolerable while these rows had a section of their own to justify and is
  // noise in the list of everything installed.
  function fresh(result) {
    return result !== undefined && result !== null && Number(result.at) > checkedAt
  }

  // What an update said when it would not go through, which is upstream's
  // own sentence and the only thing on this page a reader has to *read*
  // rather than glance at.
  readonly property var failures: {
    var out = []
    for (var i = 0; i < items.length; i++) {
      var r = updateResult[String(items[i].id)]
      if (fresh(r) && r.ok !== true)
        out.push({ name: String(items[i].name), message: String(r.message) })
    }
    return out
  }

  // How long ago in words, so a stale answer says so rather than passing
  // itself off as current.
  readonly property string checkedAgo: {
    if (checkedAt <= 0) return "never"
    var mins = Math.floor((Date.now() / 1000 - checkedAt) / 60)
    if (mins < 1) return "just now"
    if (mins < 60) return mins + (mins === 1 ? " minute ago" : " minutes ago")
    var hours = Math.floor(mins / 60)
    if (hours < 24) return hours + (hours === 1 ? " hour ago" : " hours ago")
    var days = Math.floor(hours / 24)
    return days + (days === 1 ? " day ago" : " days ago")
  }

  // Counted over the plugins, not over the sweep's answers. The sweep walks
  // directories, and a directory is not a plugin: a backup left beside one —
  // `.something.bak.20260910213514`, which `omarchy plugin remove` writes — is
  // fifty-eight commits behind whatever it was a copy of, and was counted as a
  // plugin needing an update that no row on the page offered.
  readonly property int updatesFound: {
    var n = 0
    for (var i = 0; i < items.length; i++)
      if ((behind[String(items[i].id)] || 0) > 0) n++
    return n
  }

  // What the marketplace's answer for one plugin is, in a sentence. The
  // difference between the last two is the whole point: nobody went and
  // looked is not the same as looked and it is not there. And a listing that
  // was verified says so only of the copy that was reviewed — a newer
  // commit, an edit made here, or a fork under the same id is something else.
  function standing(p) {
    if (p === null || p === undefined) return "—"
    if (p.verified === true)
      return p.verifiedAt !== "" ? "Verified " + shortDate(p.verifiedAt) : "Verified"
    if (p.listed === true && p.reviewed === true) {
      if (p.head !== p.reviewedCommit) return "Listed, this version not verified"
      if (p.pristine === false) return "Listed, changed on this machine"
      return "Listed, this copy not checked"
    }
    if (p.listed === true) return "Listed, not verified"
    if (p.contested === true) return "Listed, installed twice"
    if (p.elsewhere === true)
      return p.matchable === true ? "Listed from another repository" : "Listed, source unknown"
    if (p.looked === true) return "Not listed"
    return "Not checked yet"
  }

  // An ISO instant as a date anyone reads. Taken apart rather than parsed:
  // Date.parse on a string this window did not write is a guess, and the day
  // is the only part of it worth showing.
  function shortDate(stamp) {
    var text = String(stamp)
    if (text.length < 10) return text
    var d = new Date(text)
    if (isNaN(d.getTime())) return text.substring(0, 10)
    return Qt.formatDate(d, "d MMM yyyy")
  }

  function askRemove(p) {
    if (p === null || p === undefined) return
    app.askConfirm("Remove " + p.name + "?", "Remove", function() {
      page.handOff(["plugin", "remove", String(p.id)])
      page.openPlugin = ""
    })
  }

  function toggle(p) {
    if (p === null || p === undefined || p.canDisable === false) return
    app.run(["plugin", p.enabled === true ? "disable" : "enable", String(p.id)])
  }

  // ================================================================ the list
  Ui.SettingGroup {
    visible: !searchEmpty && openPlugin === "" && !creating

    RowLayout {
      width: parent.width
      spacing: Style.space(12)

      Ui.StatCard {
        Layout.fillWidth: true
        label: "Updates waiting"
        value: !page.checked ? "—" : (page.updatesFound === 0 ? "None" : String(page.updatesFound))
        note: page.checked ? "Checked " + page.checkedAgo : "Not checked yet"
      }

      Ui.StatCard {
        Layout.fillWidth: true
        label: "Switched on"
        value: page.items.length > 0 ? String(page.report.on) : "—"
        note: page.items.length > 0
          ? "of " + page.report.installed + " the shell has" : ""
      }

      Ui.StatCard {
        Layout.fillWidth: true
        label: "On disk"
        value: page.report.diskBytes > 0 ? app.formatBytes(page.report.diskBytes) : "—"
        note: page.yoursCount > 0
          ? "across " + page.yoursCount + " you installed" : ""
      }
    }
  }

  // ============================================================== adding one
  //
  // A form and not a terminal: `omarchy-plugin-add` prompts only for what it
  // was not given, so asked in fields it needs nothing back. What the
  // terminal did carry was the warning, which is the one thing here a reader
  // has to have read — so it is on screen, in the window's own words, above
  // the button that acts on it.
  Ui.SettingGroup {
    visible: !searchEmpty && creating
    note: "Adding one reloads the shell's plugins, so this window closes for "
      + "a moment and comes back with the result."

    Column {
      width: parent.width
      spacing: Style.space(16)

      Ui.FormField {
        id: urlField
        label: "Git URL"
        placeholder: "https://github.com/acme/omarchy-weather"
        error: text.trim() === "" ? "Give it a git URL."
          : /\s/.test(text.trim()) ? "A git URL cannot contain spaces."
          // Refused before it is sent anywhere: the address would travel as
          // an argument, to the window's own commands and to git's download,
          // where everyone on this computer can read it.
          : /^https?:\/\/[^\/]*@/i.test(text.trim())
            ? "Leave the password out of the address. While it downloads, anyone on this computer could read it."
          : ""
        onAccepted: addButton.clicked()
      }

      // The bare switch, not the kit's Toggle: that one is a whole settings
      // row and draws its own bordered surface, which in a form reads as a
      // box around one question.
      Row {
        spacing: Style.space(10)

        ToggleSwitch {
          id: enableSwitch
          checked: page.addEnable
          foreground: Ui.Palette.foreground
          accent: Ui.Palette.accent
          onToggled: page.addEnable = !page.addEnable
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: enableSwitch.verticalCenter
          text: "Switch it on once it is added"
          color: Ui.Palette.foreground
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.bodySmall

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.addEnable = !page.addEnable
          }
        }
      }

      // The warning the terminal flow prints before it asks, which is the
      // reason that flow asked at all. Above the button, because a caution
      // under the thing it is about is read after the press.
      Ui.NoticeRow {
        glyph: "\uf071"
        urgent: true
        label: "A plugin is code running inside your shell"
        description: "Not a sandbox and not a separate process: it runs in the "
          + "one that draws your bar, with everything you can reach. Add "
          + "repositories you trust, and read a plugin before switching it on."
      }

      Row {
        spacing: Style.space(10)

        Button {
          id: addButton
          text: "Add plugin"
          bordered: true
          enabled: urlField.error === "" && !page.working
          opacity: enabled ? 1 : 0.4
          foreground: Ui.Palette.foreground
          accent: Ui.Palette.accent
          fontFamily: Ui.Palette.fontFamily
          onClicked: {
            // Pressing a dead button marks the field, which is what turns it
            // into an answer rather than a wall.
            if (!enabled) { urlField.touched = true; return }
            page.app.startPluginAdd(urlField.text.trim(), page.addEnable)
            page.creating = false
          }
        }

        Button {
          text: "Cancel"
          foreground: Ui.Palette.foreground
          accent: Ui.Palette.accent
          fontFamily: Ui.Palette.fontFamily
          onClicked: page.creating = false
        }
      }
    }
  }

  Ui.SettingGroup {
    visible: !searchEmpty && openPlugin === "" && !creating
    title: "Plugins"

    // A clone is seconds of network and then a reload that takes this window
    // with it, so most of the time the reader sees this on the way back
    // rather than on the way out. It is still owed while a URL that never
    // reached the filesystem is being refused, which is the one case where
    // nothing reloads and the window stays.
    Ui.NoticeRow {
      visible: !searchHidden && page.addingNow
      glyph: "\uf019"
      label: "Adding a plugin"
      description: page.adding !== null ? String(page.adding.url) : ""
    }

    // Dismissed rather than timed out: what an add said is the only record
    // of it, and the plugin either appearing in the list below or not is
    // not an explanation of why.
    Ui.NoticeRow {
      visible: !searchHidden && page.addResult !== null && !page.addingNow
      glyph: page.addResult !== null && page.addResult.ok === true ? "\uf058" : "\uf071"
      urgent: page.addResult !== null && page.addResult.ok !== true
      label: page.addResult !== null && page.addResult.ok === true
        ? "Added" : "Could not add it"
      description: page.addResult !== null ? String(page.addResult.message) : ""
      dismissable: true
      onDismissed: page.app.clearPluginAdd()
    }

    Row {
      spacing: Style.space(8)

      Repeater {
        model: page.filters

        Ui.Chip {
          required property var modelData
          text: modelData.title
          on: page.filter === modelData.id
          onClicked: page.filter = modelData.id
        }
      }
    }

    Ui.DataTable {
      navigable: true
      rowActionLabel: "Open"
      // The two counts are headed by their own mark rather than by a word.
      // "Hearts" and "GitHub stars" are wider than any figure under them, and
      // a column headed by a word it is three times the width of is a column
      // spent on its own label.
      columns: {
        var cols = [{ title: "Plugin", weight: 2.2 }]
        if (!page.builtinList) {
          cols.push({ title: "Author", weight: 1.2 })
          cols.push({ title: "Installed", weight: 1 })
          cols.push({ title: "Available", weight: 1 })
          cols.push({ title: "\uf004", weight: 0.55, align: "center" })
          cols.push({ title: "\uf005", weight: 0.55, align: "center" })
          cols.push({ title: "Size", weight: 0.85, align: "right" })
        }
        // Headed by nothing. "Update" over a column of Update buttons is the
        // same word twice, and there is no other word for what these do.
        // Blank on most rows, which is the whole answer for a plugin with
        // nothing waiting — the Available column is what says whether that
        // is known.
        cols.push({ title: "", weight: 1.2, align: "right" })
        // Last, and hard against the edge: the switch is the one thing on
        // the row that is neither a reading nor a hand-off to somewhere
        // else, and the end of the row is where a hand reaches for it.
        cols.push({ title: "State", weight: 0.9, align: "right" })
        return cols
      }
      emptyNote: page.items.length === 0 ? "Looking for plugins…" : "Nothing here."
      rows: {
        var out = []
        for (var i = 0; i < page.shown.length; i++) {
          var p = page.shown[i]
          var id = String(p.id)
          var n = page.behind[id] === undefined ? 0 : page.behind[id]
          var ahead = page.upstream[id]
          var cells = [
            // The check rides with the name rather than taking a column: it
            // is a fact about the plugin, not a value to be compared down a
            // column of mostly blanks.
            { text: p.name, strong: true, mark: p.verified === true ? "" : "" },
            // Built in is not an author, but it is the true answer to who is
            // responsible for this one, and it is the same answer for all
            // thirty-six.
            { text: p.firstParty === true ? "Omarchy" : p.author },
            { text: p.version },
            // Filled in whether or not it differs from the installed
            // version: a column that answers only for the plugins that are
            // behind is a column of blanks, and a blank reads as "not known"
            // rather than as "nothing to do". The weight on the figure is
            // what tells those two apart.
            //
            // So a successful fetch always has something to say. When the
            // remote manifest gave no version — no `version` key, or not at
            // the repository root — but nothing is waiting, upstream's files
            // *are* the installed ones, so the installed version is the
            // available one. Left blank, that row was indistinguishable from
            // one the sweep never reached.
            //
            // Empty is reserved for exactly that: never asked. The sweep
            // prints each verdict as its own fetch settles, so the cells
            // fill one row at a time rather than all at the end.
            { text: page.checking[id] === true ? "checking…"
                : n === -1 ? "not from git"
                : n === -2 ? "unreachable"
                : n === -3 ? "not checked"
                : ahead !== undefined ? String(ahead)
                : n === 0 ? String(p.version) : "",
              strong: n > 0 },
            { text: p.hearts !== null && p.hearts !== undefined ? String(p.hearts) : "" },
            { text: p.stars !== null && p.stars !== undefined ? String(p.stars) : "" },
            // No bar. A bar earns its place where the reader is asking which
            // row is the big one — that is the question on the Packages page,
            // and it is not the question here: a plugin's size is a fact you
            // check about the one you are looking at, and twenty bars for it
            // are twenty lengths nobody is comparing.
            { text: p.bytes > 0 ? app.formatBytes(p.bytes) : "", align: "right" },
            // The one thing there is to do to a row that the row's own state
            // does not cover, on the rows that can be done it. While it is
            // out, and after it has failed, the cell is still the way in — a
            // failure leaves the commits waiting, so the button comes back
            // and the notice under the table says what happened.
            page.updating[id] !== undefined
              ? { action: "Updating…", id: "update", actionEnabled: false, align: "right" }
              : n > 0
                ? { action: "Update", id: "update", actionEnabled: !page.working,
                    align: "right" }
                : { text: page.fresh(page.updateResult[id])
                      && page.updateResult[id].ok === true ? "Updated" : "",
                    align: "right" },
            // The switch is the state as well as the way to change it, so
            // the word under State went with the gear: "On" beside a switch
            // that is on is the same fact twice. The one row that cannot be
            // switched says so in words instead — "Always on" is why nothing
            // moves, which is the one thing a dead switch cannot say for
            // itself.
            p.canDisable === false
              ? { text: "Always on" }
              : { toggle: true, on: p.enabled === true, id: "toggle" }
          ]
          // The headings above drop five of the columns for the built-in
          // list, so the cells drop with them: a row longer than its header
          // puts every figure after the gap under the wrong word, and the
          // last of them off the end of the table.
          if (page.builtinList) cells.splice(1, 6)
          out.push({ cells: cells })
        }
        return out
      }
      onRowAction: function(index, id) {
        if (index < 0 || index >= page.shown.length) return
        if (id === "update") { page.updateOne(String(page.shown[index].id)); return }
        if (id === "toggle") { page.toggle(page.shown[index]); return }
        page.openPlugin = String(page.shown[index].id)
      }
      onActivated: function(index) {
        if (index >= 0 && index < page.shown.length)
          page.openPlugin = String(page.shown[index].id)
      }
    }

    // The one thing about an update that cannot be said in a cell: upstream's
    // own last line about why it refused, which runs to four hundred
    // characters. A column wide enough for that is a column of blanks the
    // rest of the time, so what went wrong is said underneath, where it has
    // the width to wrap.
    Repeater {
      model: page.failures

      delegate: Ui.NoticeRow {
        required property var modelData
        glyph: "\uf071"
        urgent: true
        label: "Could not update " + modelData.name
        description: modelData.message
      }
    }

  }

  // ============================================================= one plugin
  //
  // Facts in a grid rather than rows: these describe one thing, and a name on
  // the left with a value on the right is the shape for a setting being
  // changed, not for twelve readings about a subject the header already names.
  Ui.SettingGroup {
    visible: !searchEmpty && openPlugin !== ""
    framed: true
    note: opened !== null ? String(opened.description) : ""

    Ui.FactGrid {
      columns: 4
      // The marketplace's verdict runs the width of the grid, last: it is the
      // one value here that is a sentence rather than a figure, and the one
      // worth reading after all the figures.
      layout: [
        { key: "version", label: "Version" },
        { key: "available", label: "Available" },
        { key: "author", label: "Author" },
        { key: "license", label: "Licence" },
        { rule: true },
        { key: "size", label: "Size on disk" },
        { key: "history", label: "Of that, history" },
        { key: "provides", label: "Provides" },
        { key: "category", label: "Category" },
        { rule: true },
        { key: "hearts", label: "Hearts" },
        { key: "stars", label: "GitHub stars" },
        { key: "views", label: "Views" },
        { key: "copies", label: "Installs copied" },
        { rule: true },
        { key: "standing", label: "Marketplace", span: 4 }
      ]
      values: ({
        "version": page.opened !== null && String(page.opened.version) !== ""
          ? String(page.opened.version) : "—",
        "available": page.availableText,
        "author": page.opened !== null
          ? (page.opened.firstParty === true ? "Omarchy"
             : (String(page.opened.author) !== "" ? String(page.opened.author) : "—")) : "—",
        "license": page.opened !== null && String(page.opened.license) !== ""
          ? String(page.opened.license) : "—",
        "size": page.opened !== null && page.opened.bytes > 0
          ? app.formatBytes(page.opened.bytes) : "—",
        // Its own cell rather than a clause after the size: the two together
        // ran past the width of a quarter-grid column and the second half
        // elided away, which is the one way of saying it that is worse than
        // not saying it.
        "history": page.opened !== null && page.opened.gitBytes > 0
          ? app.formatBytes(page.opened.gitBytes) : "—",
        "provides": page.providesText,
        "category": page.opened !== null && String(page.opened.category) !== ""
          ? String(page.opened.category) : "—",
        "standing": page.standing(page.opened),
        "hearts": page.count(page.opened !== null ? page.opened.hearts : null),
        "stars": page.count(page.opened !== null ? page.opened.stars : null),
        "views": page.count(page.opened !== null ? page.opened.views : null),
        "copies": page.count(page.opened !== null ? page.opened.copies : null)
      })
    }
  }

  // A property and not an expression in the grid above: a statement block is a
  // binding, not a value, and one written inline as an object literal's member
  // is a parse error that takes the whole page down with it.
  readonly property string availableText: {
    if (opened === null) return "—"
    var id = String(opened.id)
    var n = behind[id] === undefined ? 0 : behind[id]
    if (n === -1) return "Not a git checkout"
    if (n === -2) return "Could not reach its remote"
    // Fetching would show the password in its address to everyone on this
    // computer while it ran, so nothing was asked.
    if (n === -3) return "Not checked: its address holds a password"
    if (!checked) return "Not checked yet"
    var ahead = upstream[id]
    if (n > 0)
      return (ahead !== undefined ? String(ahead) + " · " : "")
        + n + (n === 1 ? " commit" : " commits") + " behind"
    return "Up to date"
  }

  readonly property string providesText: {
    if (opened === null) return "—"
    var kinds = opened.kinds !== undefined ? opened.kinds : []
    if (kinds.length === 0) return "—"
    var words = []
    for (var i = 0; i < kinds.length; i++) {
      var k = String(kinds[i])
      words.push(k === "bar-widget" ? "A bar widget"
        : k === "bar" ? "The bar"
        : k === "panel" ? "A panel"
        : k === "overlay" ? "An overlay"
        : k === "service" ? "A service"
        : k)
    }
    return words.join(", ")
  }

  // Null is not zero here: nobody has hearted this, and nobody has looked it
  // up, are different answers, and a dash says the second.
  function count(value) {
    return value === null || value === undefined ? "—" : String(value)
  }

  Ui.SettingGroup {
    visible: !searchEmpty && openPlugin !== ""

    // The marketplace's own verdict on whether the plugin still installs, said
    // out loud rather than left in a field: it is about the code in the shell.
    Ui.NoticeRow {
      visible: !searchHidden && page.opened !== null
        && String(page.opened.status) === "Compatibility failed"
      glyph: ""
      urgent: true
      label: "The marketplace could not get this one working"
      description: "Its last check of this plugin failed against the current Omarchy. "
        + "It may still run here; it is no longer offered to anyone else."
    }

    Ui.NoticeRow {
      visible: !searchHidden && page.opened !== null && page.opened.firstParty !== true
        && page.opened.listed !== true && page.opened.looked === true
      glyph: ""
      // The grid above already says "Not listed" under Marketplace, so the
      // notice says what that *means* — nobody has read this code — and why
      // it is usually nothing to act on. A copy whose id is listed from
      // somewhere it did not come from is the case that matters: the review
      // exists, and it is of other code.
      label: "Nobody has reviewed this one"
      description: page.opened === null || page.opened.elsewhere !== true
        ? "It is not on plugins.omarchy.org, which is expected for one of "
          + "your own or one installed straight from a git URL."
        : page.opened.contested === true
          ? "More than one copy here claims this id and only one of them runs, so "
            + "neither can be matched to the plugins.omarchy.org listing."
        : page.opened.matchable === true
          ? "plugins.omarchy.org lists this id from a different repository than the "
            + "one this copy was cloned from"
            + (page.opened.elsewhereReviewed === true
               ? ", so its review is of that code, not this." : ".")
        : page.opened.origin === ""
          ? "This copy does not say where it was cloned from, so it cannot be "
            + "matched to the plugins.omarchy.org listing under the same id."
          : "The plugins.omarchy.org listing under this id does not name its "
            + "repository, so this copy cannot be matched to it."
    }

    // Listed and verified, but not this copy. The grid says that much; what it
    // cannot say is which commit was reviewed and which one is here.
    Ui.NoticeRow {
      visible: !searchHidden && page.opened !== null && page.opened.listed === true
        && page.opened.reviewed === true && page.opened.verified !== true
      label: "This copy is not the one that was reviewed"
      description: {
        if (page.opened === null) return ""
        var reviewed = String(page.opened.reviewedCommit).slice(0, 7)
        if (page.opened.head !== page.opened.reviewedCommit)
          return "plugins.omarchy.org verified commit " + reviewed + ", and this copy is at "
            + (page.opened.head !== "" ? String(page.opened.head).slice(0, 7) : "no commit")
            + "."
        if (page.opened.pristine === false)
          return "Files here differ from commit " + reviewed
            + ", the one plugins.omarchy.org verified."
        return "Its files could not be read in time to compare them with commit "
          + reviewed + ", the one plugins.omarchy.org verified."
      }
    }

    Ui.SwitchRow {
      label: "Enabled"
      description: page.opened !== null && page.opened.canDisable === false
        ? "The shell will not start without this one."
        : "Off leaves it installed and loads none of it."
      enabled: page.opened !== null && page.opened.canDisable !== false
      checked: page.opened !== null && page.opened.enabled === true
      onRequested: page.toggle(page.opened)
    }

    Ui.ActionRow {
      visible: !searchHidden && page.opened !== null
        && (page.behind[String(page.opened.id)] || 0) > 0
      label: "Update"
      description: {
        if (page.opened === null) return ""
        var id = String(page.opened.id)
        var n = page.behind[id] || 0
        var subjects = (page.changes[id] || "").split("|").join(" · ")
        return n + (n === 1 ? " commit" : " commits") + " waiting"
          + (subjects !== "" ? " · " + subjects : "")
          + ". The window closes for a moment while the shell reloads."
      }
      buttonText: page.opened !== null && page.updating[String(page.opened.id)] !== undefined
        ? "Updating…" : "Update"
      actionEnabled: !page.working
      onTriggered: page.updateOne(String(page.opened.id))
    }

    Ui.ActionRow {
      visible: !searchHidden && page.opened !== null && String(page.opened.repo) !== ""
      label: "Repository"
      description: page.opened !== null ? String(page.opened.repo) : ""
      buttonText: "Open"
      onTriggered: { app.run(["plugin", "site", String(page.opened.id)]); app.hide() }
    }

    // Only a plugin you installed can be removed; the built-in ones come back
    // with the next Omarchy update anyway.
    Ui.ActionRow {
      visible: !searchHidden && page.opened !== null && page.opened.firstParty !== true
      label: "Remove"
      description: "Deletes the plugin and its checkout. Omarchy lists what goes and asks in a terminal."
      buttonText: "Remove"
      onTriggered: page.askRemove(page.opened)
    }
  }
}
