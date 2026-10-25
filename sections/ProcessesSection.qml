import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// What the machine is busy with. It exists for one question — what is making
// this slow — so it leads with the three figures that answer it, then the ten
// heaviest by CPU and by memory, then every process in the tree that started
// it, the way btop draws it.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property var cores: app.processes.cores !== undefined ? app.processes.cores : []
  readonly property var memory: app.processes.memory !== undefined ? app.processes.memory : ({})
  readonly property var load: app.processes.load !== undefined ? app.processes.load : ({})
  readonly property var busiest: app.processes.busiest !== undefined ? app.processes.busiest : []
  readonly property var heaviest: app.processes.heaviest !== undefined ? app.processes.heaviest : []
  readonly property var tree: app.processes.tree !== undefined ? app.processes.tree : []

  // By PID rather than by row: the tree is re-read every two seconds and
  // processes come and go above the one picked, so a row number would move
  // the selection onto whatever slid into its place.
  property int selectedPid: -1

  // Folded branches, by PID, as the reader left them. The kernel's own
  // threads start folded — three hundred rows of zeros under one parent is
  // what btop scrolls past too, and the one row standing for them is enough.
  property var folds: ({})
  function folded(pid) {
    var key = String(pid)
    return folds[key] !== undefined ? folds[key] : pid === 2
  }

  // Folding is the page's and not the table's, because a folded row is drawn
  // standing for its whole branch and only the page knows what that means.
  readonly property var shown: {
    var out = []
    var hideBelow = -1
    for (var i = 0; i < tree.length; i++) {
      var p = tree[i]
      if (hideBelow >= 0) {
        if (p.depth > hideBelow) continue
        hideBelow = -1
      }
      out.push(p)
      if (p.parent === true && folded(p.pid)) hideBelow = p.depth
    }
    return out
  }

  readonly property int selectedRow: {
    for (var i = 0; i < shown.length; i++)
      if (shown[i].pid === selectedPid) return i
    return -1
  }
  readonly property var selected: selectedRow >= 0 ? shown[selectedRow] : null

  // A row in the top lists is a program, not a process — every process of
  // one name in one container — so it is picked by that pair, and ending it
  // ends all of them. The PIDs come from the latest poll rather than the one
  // the row was picked on, since a browser starts and drops helpers all the
  // time. One selection on the page at a time: picking here lets go of the
  // tree's, and the other way round, so it is never a question which one End
  // is about.
  property string selectedProgram: ""
  function programKey(p) { return p.name + "\n" + p.container }
  function programRow(list, key) {
    if (key === "") return -1
    for (var i = 0; i < list.length; i++)
      if (programKey(list[i]) === key) return i
    return -1
  }
  readonly property var program: {
    var i = programRow(busiest, selectedProgram)
    if (i >= 0) return busiest[i]
    i = programRow(heaviest, selectedProgram)
    return i >= 0 ? heaviest[i] : null
  }
  function topList(which) { return which === "memory" ? heaviest : busiest }
  function pickProgram(table, which, index) {
    var list = topList(which)
    if (index < 0 || index >= list.length) return
    selectedProgram = programKey(list[index])
    selectedPid = -1
    // As on the tree: the click wrote a row number over the binding. By name
    // of the list and not the list itself, which is a new array every poll.
    table.currentRow = Qt.binding(function() { return programRow(topList(which), selectedProgram) })
  }

  // Every bar is a share of the whole machine — all of its CPU, all of its
  // memory — so a bar means the same in the lists as in the tree and as on
  // the cards above. Scaled to the heaviest row instead, the top bar was
  // always full, and a process using 1 % of the machine looked like it was
  // using all of it.
  function cpuShare(value) { return Math.max(0, Math.min(1, Number(value) / 100)) }
  function memoryShare(value) {
    var total = Number(memory.total)
    return total > 0 ? Math.max(0, Math.min(1, Number(value) / total)) : 0
  }

  // Docker's whale on a container's badge: the name alone is a grey word
  // that could be anything, and the whale says what kind of thing it is
  // before the word is read.
  readonly property string dockerGlyph: "\uf308"
  function containerCell(name, container) {
    return { text: name, strong: true, tag: container,
             tagIcon: container !== "" ? dockerGlyph : "", tagIconColor: Ui.Palette.docker }
  }

  function percent(value) {
    var n = Number(value)
    // A tenth of a percent of sixteen cores is still a process doing
    // something, and rounding it to 0 % would say it was not.
    return (n > 0 && n < 0.1 ? "< 0.1" : n.toFixed(1)) + " %"
  }

  // Faster than the other pages poll, because this is the one page whose whole
  // subject is what is true this second. Slower than a monitor would: the
  // reader is looking for what is heavy, not watching a graph.
  Timer {
    interval: 2000
    running: page.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: page.app.pollProcesses()
  }

  Ui.SettingGroup {
    RowLayout {
      width: parent.width
      spacing: Style.space(12)

      Ui.StatCard {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        label: strings.t("processessection.label.1", "CPU")
        value: page.app.processes.cpu !== undefined && page.app.processes.cpu !== null
          ? page.app.processes.cpu + " %" : "—"
        note: {
          var parts = []
          if (page.load.cores !== undefined) parts.push(strings.t("processessection.cores", "%1 cores").arg(page.load.cores))
          if (page.app.processes.temperature !== undefined && page.app.processes.temperature !== null)
            parts.push(page.app.processes.temperature + " °C")
          return parts.join(" · ")
        }

        // A bar per core rather than one average. The average hides the case
        // the reader is usually looking at: one core pinned by one thread,
        // which is a machine that feels slow while it reads as 6 % busy.
        // Short and squarely cut. Tall pill-shaped tracks on a machine that is
        // 7 % busy read as a row of empty arches with a line under each; what
        // is wanted is a small bar chart that is mostly floor.
        Row {
          width: parent.width
          height: Style.space(15)
          spacing: Style.space(3)

          Repeater {
            model: page.cores

            Rectangle {
              required property var modelData
              width: (parent.width - (cores.length - 1) * Style.space(3)) / Math.max(1, cores.length)
              height: parent.height
              radius: Style.space(2)
              color: Ui.Palette.shade(0.12)

              Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Math.max(Style.spacing.hairline,
                                 parent.height * Math.max(0, Math.min(100, Number(parent.modelData))) / 100)
                radius: parent.radius
                color: Ui.Palette.accent
              }
            }
          }
        }
      }

      Ui.StatCard {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        label: strings.t("processessection.label.2", "Memory")
        value: page.memory.used !== undefined ? page.app.formatBytes(page.memory.used) : "—"
        note: {
          if (page.memory.total === undefined) return ""
          var note = "of " + page.app.formatBytes(page.memory.total)
          if (Number(page.memory.swap) > 0) note += " · swap " + page.app.formatBytes(page.memory.swap)
          return note
        }

        Ui.Meter {
          width: parent.width
          value: page.memory.percent !== undefined ? Number(page.memory.percent) / 100 : 0
          warn: Number(page.memory.percent) >= 90
        }
      }

      // All three figures at once, as `uptime` and every monitor print them:
      // the five- and fifteen-minute ones are what say whether the first is a
      // spike or the way things have been.
      Ui.StatCard {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        label: strings.t("processessection.label.3", "Load")
        value: page.load.one !== undefined
          ? [page.load.one, page.load.five, page.load.fifteen].map(function(v) { return Number(v).toFixed(2) }).join("  ")
          : "—"
        // Three bare decimals mean nothing to someone who has not met a load
        // average. The note says what they count — tasks — so that the core
        // count, said in the same unit, is a yardstick they can be held
        // against: up to one per core, nothing is kept waiting.
        note: {
          if (page.load.one === undefined) return ""
          var note = strings.t("processessection.loadNote",
              "Tasks waiting for the processor over 1, 5 and 15 min.")
          var cores = Number(page.load.cores)
          return cores > 0
            ? note + strings.t("processessection.loadCores",
                " With %1 cores, under %1 is fine.").arg(cores)
            : note
        }
      }
    }
  }

  Ui.SettingGroup {
    title: strings.t("processessection.title.1", "Top processes")

    // Counted by name, so a browser's twenty processes are one browser — the
    // question is which program, not which of its helpers.
    RowLayout {
      width: parent.width
      spacing: Style.space(12)

      Ui.DataTable {
        id: busiestTable
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        columns: [
          { title: strings.t("processessection.title.3", "Process"), weight: 1.5 },
          { title: strings.t("processessection.title.4", "CPU"), weight: 1.2 }
        ]
        currentRow: programRow(page.busiest, page.selectedProgram)
        onActivated: function(index) { pickProgram(busiestTable, "cpu", index) }
        emptyNote: strings.t("processessection.emptyNote.1", "Nothing to report.")
        rows: {
          var out = []
          for (var i = 0; i < page.busiest.length; i++) {
            var p = page.busiest[i]
            out.push({ cells: [
              containerCell(p.name, p.container),
              { text: percent(p.value), meter: cpuShare(p.value) }
            ] })
          }
          return out
        }
      }

      Ui.DataTable {
        id: heaviestTable
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        columns: [
          { title: strings.t("processessection.title.5", "Process"), weight: 1.5 },
          { title: strings.t("processessection.title.6", "Memory"), weight: 1.2 }
        ]
        currentRow: programRow(page.heaviest, page.selectedProgram)
        onActivated: function(index) { pickProgram(heaviestTable, "memory", index) }
        emptyNote: strings.t("processessection.emptyNote.2", "Nothing to report.")
        rows: {
          var out = []
          for (var i = 0; i < page.heaviest.length; i++) {
            var p = page.heaviest[i]
            out.push({ cells: [
              containerCell(p.name, p.container),
              { text: page.app.formatBytes(p.value), meter: memoryShare(p.value) }
            ] })
          }
          return out
        }
      }
    }

    // Under the lists, and only once a program is picked. Unlike the tree's,
    // these can come and go: what they push down is the tree below, not the
    // row that was just clicked.
    //
    // The count is in the label because the row's name does not say it: End
    // on "brave" is twenty processes, and on a name this window shares with
    // something else it can be more than the reader meant.
    Row {
      visible: page.program !== null
      spacing: Style.space(8)

      Ui.Chip {
        text: {
          if (page.program === null) return ""
          var n = page.program.pids !== undefined ? page.program.pids.length : 0
          return strings.t("processessection.endNamed", "End %1").arg(page.program.name)
            + (n > 1 ? strings.t("processessection.processesCount", " (%1 processes)").arg(n) : "")
        }
        onClicked: if (page.program !== null) page.app.run(["processes", "end"].concat(page.program.pids.map(String)))
      }

      Ui.Chip {
        text: strings.t("processessection.text.1", "Force quit")
        onClicked: if (page.program !== null) page.app.run(["processes", "kill"].concat(page.program.pids.map(String)))
      }
    }
  }

  Ui.SettingGroup {
    title: strings.t("processessection.title.2", "All processes")

    // Above the tree rather than under it, where the actions on a table
    // usually go. Under a list this long they are a scroll away from the row
    // just picked; here they are in sight of it from anywhere in the first
    // screenful, and the tree only grows downwards.
    //
    // Always there, and dimmed until a process is picked. Hidden instead,
    // picking one brought them in and pushed the whole tree down under the
    // pointer that had just clicked it.
    Row {
      spacing: Style.space(8)

      // TERM and not KILL. A process asked to stop can save what it was
      // doing, and a settings window is not the place that decides it may not
      // — so the harder one is a second, separate press rather than the first.
      Ui.Chip {
        enabled: page.selected !== null
        opacity: enabled ? 1 : 0.4
        text: page.selected !== null
          ? strings.t("processessection.endNamed", "End %1").arg(page.selected.name)
          : strings.t("processessection.endProcess", "End process")
        onClicked: if (page.selected !== null) page.app.run(["processes", "end", String(page.selected.pid)])
      }

      Ui.Chip {
        enabled: page.selected !== null
        opacity: enabled ? 1 : 0.4
        text: strings.t("processessection.text.2", "Force quit")
        onClicked: if (page.selected !== null) page.app.run(["processes", "kill", String(page.selected.pid)])
      }
    }

    Ui.DataTable {
      columns: [
        { title: strings.t("processessection.title.7", "PID"), weight: 0.7, align: "right" },
        { title: strings.t("processessection.title.8", "Process"), weight: 3.2 },
        { title: strings.t("processessection.title.9", "CPU"), weight: 1.2 },
        { title: strings.t("processessection.title.10", "Memory"), weight: 1.2 }
      ]
      id: processTree
      currentRow: page.selectedRow
      emptyNote: strings.t("processessection.emptyNote.3", "Nothing to report.")
      rows: {
        // A folded row stands for its whole branch, so it carries the
        // branch's totals — otherwise folding a terminal would make
        // everything running in it vanish from the figures as well as from
        // the list.
        function cpuOf(p) { return p.parent === true && folded(p.pid) ? p.treeCpu : p.cpu }
        function memoryOf(p) { return p.parent === true && folded(p.pid) ? p.treeMemory : p.memory }

        var out = []
        for (var i = 0; i < page.shown.length; i++) {
          var p = page.shown[i]
          var cpu = Number(cpuOf(p))
          var mem = Number(memoryOf(p))
          out.push({ cells: [
            { text: String(p.pid) },
            { text: p.name, strong: true, tag: p.container,
              tagIcon: p.container !== "" ? page.dockerGlyph : "", tagIconColor: Ui.Palette.docker,
              tree: { depth: p.depth, lines: p.lines, last: p.last,
                      folded: p.parent === true ? folded(p.pid) : undefined } },
            { text: percent(cpu), meter: cpuShare(cpu) },
            { text: page.app.formatBytes(mem), meter: memoryShare(mem) }
          ] })
        }
        return out
      }
      onActivated: function(index) {
        if (index >= 0 && index < page.shown.length) page.selectedPid = page.shown[index].pid
        page.selectedProgram = ""
        // The table writes the row it was clicked on into `currentRow`,
        // which replaces the binding — and a row number goes on pointing at
        // whatever slides into it, while End and Force quit still act on the
        // PID. Bound again, the highlight follows the process.
        processTree.currentRow = Qt.binding(function() { return page.selectedRow })
      }
      onFoldRequested: function(index) {
        if (index < 0 || index >= page.shown.length) return
        var pid = page.shown[index].pid
        var next = {}
        for (var key in page.folds) next[key] = page.folds[key]
        next[String(pid)] = !page.folded(pid)
        page.folds = next
      }
    }
  }
}
