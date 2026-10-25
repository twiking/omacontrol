pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// A machine is thirteen hundred packages and twenty gigabytes, and this page
// answers the two questions anyone has about that: what is waiting to change,
// and what is all of it costing. The counts and the sizes are one read of the
// local database and free; the list of what is *available* is a database sync,
// so it is cached and the page says how old it is.
//
// Nothing here changes anything on its own. Every action opens a terminal,
// because installing a kernel or removing a package wants a password, a
// confirmation and somewhere for the output to go.
Ui.SectionBody {
  id: root
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property var pending: app.packages.pending !== undefined ? app.packages.pending : []
  readonly property var all: app.packageList !== undefined && app.packageList !== null
    ? app.packageList : []
  readonly property int checkedAt: app.packages.checkedAt !== undefined ? Number(app.packages.checkedAt) : 0
  readonly property int updatedAt: app.packages.updatedAt !== undefined ? Number(app.packages.updatedAt) : 0

  // ------------------------------------------------------------ one of them
  //
  // A drill-in rather than a panel over the table, the same shape the Apps
  // page uses: what there is to say about a package is a dozen facts and two
  // actions, and inlining that under a row would push the rest of the list
  // off the screen and lose the row it came from.
  property string openPackage: ""
  onOpenPackageChanged: app.pollPackageInfo(openPackage)

  // The reader is a call of its own and arrives after the page has already
  // redrawn with the new name, so what it holds is only this package's while
  // the two agree. Otherwise the last one's size sits under this one's title.
  readonly property var info: {
    var got = app.packageInfo !== undefined && app.packageInfo !== null ? app.packageInfo : ({})
    return String(got.name !== undefined ? got.name : "") === openPackage ? got : ({})
  }

  readonly property string headerTitle: openPackage
  readonly property bool headerBack: openPackage !== ""
  function headerBackTriggered() { openPackage = "" }

  // Nothing. What a package *is* goes in the group note below, which has a
  // width and wraps — the window draws a header note as a bare Text on the
  // title's baseline, with no width, no elide and nothing clipping it, which
  // is right for the short window-authored qualifiers every other page passes
  // ("running now") and wrong for a stranger's sentence: ninety-two of the
  // packages here describe themselves in more than eighty characters, and
  // those would paint straight out through the side of the window.
  readonly property string headerNote: ""

  property Component headerControl: Component {
    Ui.Chip {
      visible: root.openPackage === ""
      text: root.app.packagesSyncing
        ? strings.t("shared.checking", "Checking…")
        : strings.t("shared.checkUpdates", "Check for updates")
      onClicked: root.app.refreshPackages()
    }
  }

  // Which of them the reader is asking for, and in what order. Both are
  // answered here rather than in the reader: the whole list is already in
  // hand, and asking pacman again to reorder what it just said would be
  // slower and no truer.
  property string filter: "all"
  property string order: "size"
  // Biggest first, A to Z: the direction a column is worth reading in the
  // first time it is pressed. Pressing the one already being sorted by turns
  // it round.
  property bool ascending: false

  function sortBy(key) {
    if (order === key) { ascending = !ascending; return }
    order = key
    ascending = key !== "size"
  }

  // A box of its own, and not the window's. That one searches *settings* — it
  // narrows the sidebar, and a term no page answers to takes the reader off
  // this page entirely, which is exactly what typing a package name does. It
  // also could not help if it stayed: what it hides is the rows that were
  // drawn, and the package being looked for is usually one of the eleven
  // hundred the cap never reached. This one is asked of the whole list.
  property string nameQuery: ""

  // What is waiting, keyed by name, so a row can say what is arriving without
  // the list and the pending list having to be walked together.
  readonly property var updateFor: {
    var map = ({})
    for (var i = 0; i < pending.length; i++)
      map[String(pending[i].name)] = String(pending[i].available)
    return map
  }

  readonly property var shown: {
    var out = []
    var query = nameQuery.toLowerCase()
    for (var i = 0; i < all.length; i++) {
      var p = all[i]
      if (query !== "" && String(p.name).toLowerCase().indexOf(query) < 0) continue
      if (filter === "updates") {
        if (updateFor[p.name] === undefined) continue
      } else if (filter !== "all" && originOf(p) !== filter) continue
      out.push(p)
    }
    var dir = ascending ? 1 : -1
    if (order === "size")
      out.sort(function(a, b) { return (Number(a.bytes) - Number(b.bytes)) * dir })
    else if (order === "from")
      // Ties inside one repository fall back to the name, or the rows under a
      // heading are in whatever order the machine happened to list them.
      out.sort(function(a, b) {
        var x = root.originOf(a), y = root.originOf(b)
        if (x !== y) return (x < y ? -1 : 1) * dir
        return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
      })
    else
      out.sort(function(a, b) {
        return (a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)) * dir
      })
    return out
  }

  // Without expac there are no sizes at all, and a column of "0 B" answers
  // "what is taking the room" wrongly rather than declining to answer. The
  // column and the order that depends on it go together.
  readonly property bool sized: app.packages.diskBytes !== undefined
    && Number(app.packages.diskBytes) > 0
  onSizedChanged: if (!sized && order === "size") { order = "name"; ascending = true }

  // The places these came from, named as the column names them. Arch and
  // Omarchy first because that is the order the machine is built in, and a
  // repository that is neither goes after them under its own name.
  readonly property var origins: {
    var present = []
    for (var i = 0; i < all.length; i++) {
      var o = originOf(all[i])
      if (o !== "" && present.indexOf(o) < 0) present.push(o)
    }
    var out = []
    var preferred = ["Arch", "Omarchy", "AUR"]
    for (var j = 0; j < preferred.length; j++)
      if (present.indexOf(preferred[j]) >= 0) out.push(preferred[j])
    for (var k = 0; k < present.length; k++)
      if (preferred.indexOf(present[k]) < 0) out.push(present[k])
    return out
  }

  // A chip that can only return everything, or nothing, is not a filter:
  // Updates is offered when there is an update, and a place when something
  // came from there.
  readonly property var filterChips: {
    var out = [{ id: "all", title: strings.t("packagessection.title.3", "All")}]
    if (pending.length > 0) out.push({ id: "updates", title: strings.t("packagessection.title.4", "Updates")})
    for (var i = 0; i < origins.length; i++)
      out.push({ id: origins[i], title: origins[i] })
    return out
  }

  // An update taken is a chip that leaves while it is being filtered on, and
  // one that is no longer drawn cannot be pressed again to get out of it.
  onFilterChipsChanged: {
    for (var i = 0; i < filterChips.length; i++)
      if (filterChips[i].id === filter) return
    filter = "all"
  }

  // Over everything waiting, not over whatever the chips have narrowed it to:
  // this is the figure on the card, and the card is about the update, not
  // about the filter three rows below it.
  //
  // Only the repositories publish a download size — an AUR package is built
  // rather than fetched — so the group's own note says what the figure leaves
  // out rather than presenting a partial sum as a total.
  readonly property real pendingBytes: {
    var total = 0
    for (var i = 0; i < pending.length; i++)
      if (pending[i].bytes !== null && pending[i].bytes !== undefined)
        total += Number(pending[i].bytes)
    return total
  }

  readonly property bool aurWaiting: {
    for (var i = 0; i < pending.length; i++)
      if (pending[i].foreign === true) return true
    return false
  }

  // A kernel update is the one that changes what happens at the next boot, so
  // it is worth saying out loud rather than leaving in row 87 of a table.
  //
  // Which of the waiting packages is a kernel is the machine's answer, not a
  // guess at the name: the reader is about to be shown a version, and
  // linux-firmware and linux-headers are updating today too.
  readonly property var kernelPending: {
    var kernels = app.packages.kernels !== undefined ? app.packages.kernels : []
    var out = []
    for (var i = 0; i < pending.length; i++)
      if (kernels.indexOf(String(pending[i].name)) >= 0) out.push(pending[i])
    return out
  }

  // The versions and nothing else: which one is arriving is what decides
  // whether it can wait, and a machine can be carrying two kernels — the name
  // is what says which of them this is.
  readonly property string kernelVersions: {
    var parts = []
    for (var i = 0; i < kernelPending.length; i++) {
      var k = kernelPending[i]
      parts.push(k.name + " " + k.installed + " → " + k.available)
    }
    return parts.join(", ")
  }

  // Omarchy itself, which is a package like any other and is the one everybody
  // means by "is there an update". Which package that is comes from the
  // reader, since omarchy-dev is what is installed on a machine following the
  // branch — the same question omarchy-update-available asks before it looks.
  readonly property var omarchyPending: {
    var name = app.packages.omarchyPackage !== undefined
      ? String(app.packages.omarchyPackage) : ""
    if (name === "") return null
    for (var i = 0; i < pending.length; i++)
      if (String(pending[i].name) === name) return pending[i]
    return null
  }

  // No package name in front of these: the box is already called Omarchy, and
  // there is only ever one of it.
  readonly property string omarchyVersions: omarchyPending !== null
    ? omarchyPending.installed + " → " + omarchyPending.available : ""

  // Whether the package on screen is one of the ones waiting, which is worth
  // knowing before removing it and worth knowing instead of removing it.
  readonly property var openPending: {
    for (var i = 0; i < pending.length; i++)
      if (String(pending[i].name) === openPackage) return pending[i]
    return null
  }

  // How many rows are drawn at once. Every one is an item with a cursor stop
  // on it, so the whole inventory is thirteen hundred of those before the page
  // has finished opening — the cap is what the reader can reach by scrolling,
  // and the search box, the filters and the order are how the rest is reached.
  readonly property int listCap: 200

  // Naming the few is the answer to "why is this here at all"; counting the
  // many is the answer to "can this go". Listing all 822 that need glibc is
  // neither, so the list becomes a number once it stops being readable.
  //
  // A property and not an expression in the grid below: a statement block is
  // a binding, not a value, and one written inline as an object literal's
  // member is a parse error that takes the whole page down with it.
  readonly property string neededBy: {
    var by = info.requiredBy !== undefined ? info.requiredBy : []
    if (openPackage === "" || info.name === undefined) return "—"
    if (by.length === 0) return strings.t("packagessection.removable", "Nothing — it can be removed on its own")
    if (by.length <= 4) return by.join(", ")
    return strings.t("packagessection.otherPackages", "%1 other packages").arg(by.length)
  }

  // Where a package came from, in the three names that mean something to
  // whoever is reading: Arch's own repositories, Omarchy's, and a package that
  // is in no repository at all — built here from a recipe, which on this
  // desktop means the AUR. A fourth repository someone added is named rather
  // than folded into one of the three, and a row whose origin is not known
  // yet says nothing rather than guessing at one.
  function originOf(p) {
    if (p.foreign === true) return "AUR"
    var repo = p.repo !== undefined && p.repo !== null ? String(p.repo) : ""
    // The testing repositories are the same two places by another name.
    if (repo.indexOf("omarchy") === 0) return "Omarchy"
    if (repo.indexOf("core") === 0 || repo.indexOf("extra") === 0
        || repo.indexOf("multilib") === 0) return "Arch"
    return repo
  }

  // The one on screen has room to say a little more than a cell does: a
  // package in no repository was built here, and the AUR is the likely but not
  // the only way that happens.
  readonly property string openOrigin: {
    if (info.name === undefined) return "—"
    if (info.foreign === true) return strings.t("packagessection.originAurOrHand", "The AUR, or by hand")
    var named = originOf(info)
    return named !== "" ? named : strings.t("packagessection.originRepository", "A repository")
  }

  function askRemove(name) {
    if (String(name) === "") return
    app.askConfirm(strings.t("packagessection.removeConfirm", "Remove %1?").arg(name),
                   strings.t("packagessection.remove", "Remove"), function() {
      app.run(["packages", "remove", String(name)])
      app.hide()
    })
  }

  // A check the reader never asked for, and only when the last one has gone
  // stale: a day-old "nothing waiting" is not an answer, and nobody should
  // have to press a button to find out that they are behind. The reader
  // decides whether it is owed, so this is free whenever it is not.
  Component.onCompleted: { app.fetchPackages(); app.pollPackageList() }

  // Counts and sizes come off the local database and cost nothing; the pending
  // list is whatever the last sync left behind. So this polls, and syncing is
  // a button.
  Timer {
    interval: 10000
    running: root.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: root.app.pollPackages()
  }

  // ============================================================== the list
  //
  // Three readings, three subjects: what is about to change, when it last
  // changed, and what it is all costing. Nothing here is repeated in a row
  // below it — the cache figure belongs beside the button that clears it, at
  // the foot of the page, and not up here where the button is not.
  Ui.SettingGroup {
    visible: !searchEmpty && root.openPackage === ""

    RowLayout {
      width: parent.width
      spacing: Style.space(12)

      Ui.StatCard {
        Layout.fillWidth: true
        label: strings.t("packagessection.label.1", "Waiting")
        value: root.checkedAt === 0 ? "—" : (root.pending.length === 0 ? strings.t("packagessection.none", "None") : String(root.pending.length))
        // Only the repositories publish a download size — an AUR package is
        // built rather than fetched — so the figure says what it leaves out
        // rather than presenting a partial sum as a total.
        note: root.pendingBytes > 0
          ? strings.t("packagessection.toDownload", "%1 to download")
              .arg(root.app.formatBytes(root.pendingBytes))
            + (root.aurWaiting ? strings.t("packagessection.plusBuilt", ", plus what is built") : "")
          : (root.checkedAt === 0 ? strings.t("shared.notChecked", "Not checked yet") : "")
      }

      Ui.StatCard {
        Layout.fillWidth: true
        label: strings.t("packagessection.label.2", "Last updated")
        value: root.updatedAt > 0 ? root.app.formatWhen(root.updatedAt) : "—"
        note: root.updatedAt > 0 ? strings.t("packagessection.lastReplaced", "When a package was last replaced") : ""
      }

      Ui.StatCard {
        Layout.fillWidth: true
        label: strings.t("packagessection.label.3", "On disk")
        value: root.app.packages.diskBytes > 0 ? root.app.formatBytes(root.app.packages.diskBytes) : "—"
        note: root.app.packages.installed !== undefined
          ? strings.t("packagessection.acrossPackages", "across %1 packages").arg(root.app.packages.installed) : ""
      }
    }
  }

  Ui.SettingGroup {
    visible: !searchEmpty && root.openPackage === ""
    title: strings.t("packagessection.title.1", "Waiting to update")
    // The remainder goes here rather than into a summary row at the foot of
    // the table. A table declared navigable makes every row a cursor stop
    // offering ⏎ Open, and a row that is a count of other rows has nothing to
    // open — the legend would promise it once per visit and do nothing.
    note: root.checkedAt === 0
      ? strings.t("packagessection.mirrorsNever",
          "Mirrors have not been checked yet — nothing here is known to be current.")
      : strings.t("updates.mirrorsChecked", "Mirrors last checked %1")
          .arg(root.app.formatWhen(root.checkedAt))

    // First in the section, above the filters that can take them off screen and
    // above the table they would otherwise be rows four and eight of. Two of
    // the ten things waiting are not like the other eight: one decides what
    // boots next time, the other is the desktop this window is part of.
    RowLayout {
      width: parent.width
      spacing: Style.space(12)
      visible: root.kernelPending.length > 0 || root.omarchyPending !== null

      Ui.CalloutCard {
        Layout.fillWidth: true
        visible: !searchHidden && root.kernelPending.length > 0
        glyph: ""
        // A literal, not a count: the word is a heading rather than a
        // sentence, and the search index is built by reading these sources
        // for `label: "…"` — a label computed in a ternary is a page the
        // window can no longer find by what is on it.
        label: strings.t("packagessection.label.4", "Kernel update")
        detail: root.kernelVersions
      }

      Ui.CalloutCard {
        Layout.fillWidth: true
        visible: !searchHidden && root.omarchyPending !== null
        glyph: ""
        label: strings.t("packagessection.label.5", "Omarchy update")
        detail: root.omarchyVersions
      }
    }

    // One press, because `omarchy-update` is one thing — it prunes the cache,
    // takes a snapshot, updates the repositories, the AUR and mise, clears
    // orphans and offers the reboot — and nothing is said about that here,
    // because it says it itself in the terminal it opens, where the answer can
    // still be no.
    Row {
      spacing: Style.space(8)

      Ui.Chip {
        text: strings.t("packagessection.text.1", "Update all")
        onClicked: { root.app.run(["packages", "update"]); root.app.hide() }
      }
    }
  }

  // ============================================================ all of them
  //
  // One table and not two. A list of what is waiting and a list of what is
  // biggest are the same 1339 packages asked two questions, and kept apart
  // they named the same package twice on one page and could answer neither
  // question about the other's rows — what is waiting never said what it
  // costs, and what is biggest never said an update was there for it.
  Ui.SettingGroup {
    visible: !searchEmpty && root.openPackage === "" && root.all.length > 0
    title: strings.t("packagessection.title.2", "Every package")
    note: strings.t("packagessection.note.1", "Open one to see what it is and what would go with it.")
      + (root.shown.length > root.listCap
         ? strings.t("packagessection.showingFirst", " Showing the first %1 of %2")
             .arg(root.listCap).arg(root.shown.length)
           + strings.t("packagessection.typeToReachRest", " — type a name to reach the rest.") : "")

    // What, then in what order. Two rows rather than one of seven chips: they
    // are two questions, and the words say which is which without a label
    // over either.
    Item {
      width: parent.width
      implicitHeight: nameField.implicitHeight

      TextField {
        id: nameField
        width: Math.min(parent.width, Style.space(360))
        placeholderText: strings.t("packagessection.placeholderText.1", "Filter by name")
        foreground: Ui.Palette.foreground
        accent: Ui.Palette.accent
        onTextChanged: root.nameQuery = text.trim()
      }
    }

    Row {
      spacing: Style.space(8)

      Repeater {
        model: root.filterChips

        Ui.Chip {
          required property var modelData
          text: modelData.title
          on: root.filter === modelData.id
          onClicked: root.filter = modelData.id
        }
      }
    }

    Ui.DataTable {
      navigable: true
      rowActionLabel: strings.t("packagessection.rowActionLabel.1", "Open")
      // The version column carries both when there is an update, rather than
      // an Available column that is blank on thirteen hundred rows and full
      // on ten. An arrow in it is also what says, while reading the list for
      // another reason entirely, that this one has something waiting.
      //
      // No column for whether a package was asked for or dragged in by
      // something else. It is pacman's install reason, it is nearly binary,
      // and every wording of it this page tried — "explicit", "Ones you
      // chose", "Why it is here" — had to be explained to the person reading
      // it, which is the definition of a column that is not pulling its
      // weight down thirteen hundred rows. It is one fact about one package,
      // so it is said in the package's own page, in a sentence, where it is
      // attached to the decision it bears on.
      // Version is the one heading that cannot be pressed: comparing two
      // version strings is a question about what upstream meant by them, and
      // sorting a thousand packages by somebody else's numbering scheme
      // answers nothing anybody asked.
      columns: root.sized
        ? [{ title: strings.t("packagessection.title.5", "Package"), weight: 2.4, sort: "name" },
           { title: strings.t("packagessection.title.6", "Version"), weight: 2.8 },
           { title: strings.t("packagessection.title.7", "Size on disk"), weight: 1.2, align: "right", sort: "size" },
           { title: strings.t("packagessection.title.8", "From"), weight: 0.9, sort: "from" }]
        : [{ title: strings.t("packagessection.title.9", "Package"), weight: 2.4, sort: "name" },
           { title: strings.t("packagessection.title.10", "Version"), weight: 2.8 },
           { title: strings.t("packagessection.title.11", "From"), weight: 0.9, sort: "from" }]
      sortKey: root.order
      sortAscending: root.ascending
      onSortRequested: function(key) { root.sortBy(key) }
      emptyNote: root.nameQuery !== "" ? strings.t("packagessection.noPackageByName", "No package here by that name.")
                                       : strings.t("shared.nothingHere", "Nothing here.")
      rows: {
        var out = []
        var capped = Math.min(root.shown.length, root.listCap)
        for (var i = 0; i < capped; i++) {
          var p = root.shown[i]
          var waiting = root.updateFor[p.name]
          var cells = [
            // A grey pill after the name, and nothing at all on the ones
            // you asked for: the answer to "what could go" is the rows that
            // are only a name. Weight said the same thing without naming it,
            // which left the reader to work out what the two kinds of row
            // were — a word costs a pill and no column.
            { text: p.name, strong: true,
              tag: p.reason === "explicit" ? "" : "dependency" },
            { text: waiting !== undefined ? p.version + " → " + waiting : p.version,
              strong: waiting !== undefined }
          ]
          if (root.sized)
            cells.push({ text: root.app.formatBytes(p.bytes), align: "right" })
          cells.push({ text: root.originOf(p) })
          out.push({ cells: cells })
        }
        return out
      }
      onActivated: function(index) {
        if (index < root.shown.length) root.openPackage = String(root.shown[index].name)
      }
    }

    // Omarchy's own picker. Everything is in the table above now, so this is
    // not the only way to reach a package — it is the one that removes several
    // in a run, and it removes what you pick there and then, with no second
    // prompt, since choosing in the finder *is* the confirmation.
    Ui.ActionRow {
      label: strings.t("packagessection.label.6", "Remove several at once")
      description: strings.t("packagessection.description.1", "Search the ones you chose by name, with each one's details beside it. ")
        + strings.t("packagessection.pickedRemoved", "What you pick there is removed without asking again.")
      buttonText: strings.t("packagessection.buttonText.1", "Search")
      onTriggered: { root.app.run(["packages", "pick"]); root.app.hide() }
    }
  }

  Ui.SettingGroup {
    visible: !searchEmpty && root.openPackage !== ""
    framed: true
    // The package's own one-line description of itself, which is the one
    // thing its name never says.
    note: root.openPackage === "" ? ""
      : (root.info.description !== undefined ? String(root.info.description) : "")

    Ui.FactGrid {
      columns: 4
      layout: [
        { key: "size", label: strings.t("packagessection.label.10", "Size on disk")},
        { key: "version", label: strings.t("packagessection.label.11", "Version")},
        { key: "from", label: strings.t("packagessection.label.12", "From")},
        { key: "why", label: strings.t("packagessection.label.13", "Why it is here")},
        { rule: true },
        { key: "when", label: strings.t("packagessection.label.14", "Installed")},
        { key: "needed", label: strings.t("packagessection.label.15", "Needed by"), span: 3 }
      ]
      values: ({
        "size": root.info.bytes !== undefined ? root.app.formatBytes(root.info.bytes) : "—",
        "version": root.info.version !== undefined ? root.info.version : "—",
        "from": root.openOrigin,
        "why": root.info.reason === undefined ? "—"
          : (root.info.reason === "explicit"
             ? strings.t("packagessection.whyExplicit", "You asked for it")
             : strings.t("packagessection.whyRequired", "Something else needs it")),
        "when": root.info.installed !== undefined ? root.info.installed : "—",
        "needed": root.neededBy
      })
    }
  }

  Ui.SettingGroup {
    visible: !searchEmpty && root.openPackage !== ""

    Ui.NoticeRow {
      visible: !searchHidden && root.openPending !== null
      glyph: ""
      label: strings.t("packagessection.label.7", "An update is waiting for this one")
      description: root.openPending !== null
        ? strings.t("packagessection.pendingCounts", "%1 installed, %2 available.")
            .arg(root.openPending.installed).arg(root.openPending.available)
        : ""
    }

    Ui.ActionRow {
      visible: !searchHidden && String(root.info.url !== undefined ? root.info.url : "") !== ""
      label: strings.t("packagessection.label.8", "Home page")
      description: String(root.info.url !== undefined ? root.info.url : "")
      buttonText: strings.t("packagessection.buttonText.2", "Open")
      onTriggered: { root.app.run(["packages", "site", root.openPackage]); root.app.hide() }
    }

    // pacman asks again in the terminal, and its list of what else goes is the
    // reason this happens in front of the reader at all. This one is about
    // having pressed the button on the wrong row.
    Ui.ActionRow {
      label: strings.t("packagessection.label.9", "Remove this package")
      description: {
        var by = root.info.requiredBy !== undefined ? root.info.requiredBy : []
        if (by.length > 0)
          return strings.t("packagessection.removeBlockedBy",
              "Other packages need this one, so pacman will refuse until they go first.")
        return strings.t("packagessection.removeDepends",
            "Removes it and anything that came in only for it. The terminal lists them and asks.")
      }
      buttonText: strings.t("packagessection.buttonText.3", "Remove")
      onTriggered: root.askRemove(root.openPackage)
    }
  }
}
