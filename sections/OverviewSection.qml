pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// The page the window opens on, and the only one that is not about a subject.
// It answers three questions in the order they are asked: is anything wrong,
// what do I flip several times a day, and what did I come here to start.
//
// Nothing here is a setting of its own. Every switch is Omarchy's, every
// notice points at the page that can actually fix it, and both are shown
// rather than kept — so this page cannot disagree with the bar.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property var toggles: app.overview.toggles !== undefined ? app.overview.toggles : []

  readonly property var toggleGlyphs: ({
    "nightlight": "\uf186",
    "dnd": "\uf1f6",
    "awake": "\uf0f4",
    "dictation": "\uf130"
  })

  // Mostly the reader's, plus the one thing the window already knows about
  // itself. Nothing here re-reads what it is already holding.
  readonly property var updates: app.overview.updates !== undefined ? app.overview.updates : ({})
  readonly property var news: app.overview.news !== undefined ? app.overview.news : ({})
  readonly property var newsItems: news.items !== undefined ? news.items : []
  readonly property int unreadNews: {
    var n = 0
    for (var i = 0; i < newsItems.length; i++) if (newsItems[i].read === false) n++
    return n
  }
  readonly property var updatePlugins: updates.plugins !== undefined ? updates.plugins : []
  readonly property bool hasUpdates: (updates.omarchy !== undefined && updates.omarchy !== null)
    || updates.packages > 0 || updatePlugins.length > 0

  readonly property var attention: {
    var items = []
    var reported = app.overview.attention !== undefined ? app.overview.attention : []
    for (var i = 0; i < reported.length; i++) items.push(reported[i])

    if (app.selfBehind > 0)
      items.push({
        id: "self",
        title: strings.tn("overviewsection.selfBehind", app.selfBehind,
             "OmaControl is 1 commit behind").arg(app.selfBehind),
        note: strings.t("overviewsection.note.1", "Checked once this opening."),
        actionLabel: strings.t("overviewsection.actionLabel.1", "Update"),
        update: true
      })

    return items
  }

  readonly property string headerNote: attention.length === 0 ? ""
    : strings.tn("overviewsection.attention", attention.length,
                 "1 thing needs attention").arg(attention.length)

  // Switch state is held in the running system — hyprsunset's temperature, the
  // shell's own do-not-disturb — so it can be changed from the bar or a
  // keybinding while this page is on screen. Polling is how the page agrees
  // with them rather than arguing.
  Timer {
    interval: 5000
    running: page.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: page.app.pollOverview()
  }

  // The one thing in this window that leaves the machine, and the *cache's
  // age* decides whether it happens — not the page, and not the reader. A
  // fetch that finds the cache under half an hour old does nothing at all, so
  // asking on open and again on a timer costs nothing but catches the case
  // this is for: a window left open all afternoon.
  Component.onCompleted: app.fetchNews()

  Timer {
    interval: 1800000
    running: page.app.shown
    repeat: true
    onTriggered: page.app.fetchNews()
  }

  // First, and tiles across rather than rows down, with no heading over them.
  // They are the strip of chrome the page opens with rather than a section of
  // it: the question they
  // answer is *which of these are on*, asked of all four at once, and a filled
  // tile answers it from across the room where four knobs in a line do not.
  Ui.SettingGroup {
    // The tiles are the cards.
    Grid {
      id: toggleGrid
      width: parent.width
      columns: 4
      spacing: Style.space(10)

      Repeater {
        model: page.toggles

        Ui.ToggleTile {
          required property var modelData

          // Grid does not stretch what it lays out, so a tile is told its
          // share of the row.
          width: (toggleGrid.width - (toggleGrid.columns - 1) * toggleGrid.spacing)
            / toggleGrid.columns
          glyph: page.toggleGlyphs[modelData.id] !== undefined ? page.toggleGlyphs[modelData.id] : ""
          label: modelData.label
          note: modelData.note !== undefined ? modelData.note : ""
          checked: modelData.on === true
          // The command that owns the switch is the one that flips it, side
          // effects and all — starting hyprsunset, telling the bar to redraw.
          // Then the page asks again rather than assuming it worked.
          onRequested: {
            page.app.run(["overview", "toggle", modelData.id])
          }
        }
      }
    }
  }

  // Anything the reader would want to know before they got to whatever they
  // opened the window for. Gone entirely when there is nothing, heading and
  // all — not replaced by a note saying so. A section that reports its own
  // emptiness takes up room on every good day to reassure the reader on none
  // of them, and the page says it better by its absence: with nothing wrong,
  // the toggles run straight into the updates.
  Ui.SettingGroup {
    framed: true
    title: strings.t("overviewsection.title.1", "Needs attention")
    visible: !searchEmpty && page.attention.length > 0

    Repeater {
      model: page.attention

      Ui.NoticeRow {
        required property var modelData

        label: modelData.title
        description: modelData.note !== undefined ? modelData.note : ""
        glyph: modelData.urgent === true ? "\uf071" : "\uf05a"
        urgent: modelData.urgent === true
        actionText: modelData.actionLabel !== undefined ? modelData.actionLabel : strings.t("overviewsection.open", "Open")
        dismissable: modelData.id !== undefined

        onTriggered: {
          if (modelData.update === true) {
            if (page.app.selfId !== "") page.app.run(["plugin", "update", page.app.selfId])
          } else if (modelData.migrate === true) {
            page.app.run(["migrate", "start"])
          } else if (modelData.page !== undefined) {
            page.app.pageId = modelData.page
          } else if (modelData.action !== undefined) {
            page.app.pageId = modelData.action
          }
        }

        onDismissed: {
          page.app.run(["overview", "dismiss", modelData.id])
        }
      }
    }
  }

  // What is waiting, from three caches and no network. The note says when the
  // package list was last synced, because a count of updates is meaningless
  // without knowing how old it is.
  Ui.SettingGroup {
    framed: true
    title: strings.t("overviewsection.title.2", "Updates")
    note: page.updates.checkedAt > 0
      ? strings.t("updates.mirrorsChecked", "Mirrors last checked %1")
          .arg(page.app.formatWhen(page.updates.checkedAt))
      : strings.t("overviewsection.mirrorsNever", "Mirrors have not been checked yet.")
    visible: !searchEmpty && page.hasUpdates

    // Omarchy ships as a package, so its row is that package pulled out of
    // the list and named as the thing the reader actually thinks about.
    Ui.NoticeRow {
      visible: !searchHidden && page.updates.omarchy !== undefined && page.updates.omarchy !== null
      glyph: ""
      label: page.updates.omarchy ? "Omarchy " + page.updates.omarchy.available : ""
      description: strings.t("overviewsection.onVersion", "You are on %1").arg(page.updates.version)
        + (page.updates.channel !== "" ? " · "
           + strings.t("overviewsection.onChannel", "%1 channel").arg(page.updates.channel) : "")
      actionText: strings.t("overviewsection.actionText.1", "Update")
      onTriggered: { page.app.run(["packages", "update"]); page.app.hide() }
    }

    Ui.NoticeRow {
      visible: !searchHidden && page.updates.packages > 0
      glyph: ""
      label: strings.tn("overviewsection.packagesWaiting", page.updates.packages,
           "1 package").arg(page.updates.packages)
      description: strings.t("overviewsection.description.1", "Waiting in the repositories and the AUR.")
      actionText: strings.t("overviewsection.actionText.2", "Open Packages")
      onTriggered: page.app.pageId = "packages"
    }

    Ui.NoticeRow {
      visible: !searchHidden && page.updatePlugins.length > 0
      glyph: ""
      label: strings.tn("overviewsection.pluginsWaiting", page.updatePlugins.length,
           "1 plugin").arg(page.updatePlugins.length)
      description: page.updatePlugins.join(" · ")
      actionText: strings.t("overviewsection.actionText.3", "Open Plugins")
      onTriggered: page.app.pageId = "plugins"
    }
  }

  // The only thing in this window that comes off the network. It is last
  // because it is the only thing on the page that is not about this machine.
  Ui.SettingGroup {
    framed: true
    title: strings.t("overviewsection.title.3", "News from omarchy.org")
    // The count first, because it is the only part of this heading anyone
    // scans for; the age second, because a headline with no age on it is one
    // you cannot judge.
    note: (page.unreadNews > 0
         ? (strings.tn("overviewsection.newsNew", page.unreadNews, "1 new").arg(page.unreadNews) + " · ") : "")
      + (page.news.fetchedAt !== undefined && page.news.fetchedAt > 0
         ? strings.t("overviewsection.fetched", "fetched %1").arg(page.app.formatWhen(page.news.fetchedAt)) : "")
    visible: !searchEmpty && page.newsItems.length > 0

    Repeater {
      model: page.newsItems.slice(0, 5)

      // A headline is a link, so the whole row is one. A Read button beside
      // each of five rows is five buttons doing what clicking the headline
      // already does, and they out-weigh everything above them on the page.
      Ui.LinkRow {
        required property var modelData

        label: modelData.title
        // What the site itself printed, rather than a date reformatted into
        // something its author would not recognise.
        value: modelData.shown !== undefined ? modelData.shown : ""
        unread: modelData.read === false
        // Opening one reads it — the reader does not have to say so twice —
        // and `news open` records that itself, so both paths agree.
        //
        // Then this window gets out of the way. It takes keyboard focus
        // exclusively while it is open, so leaving it up means the article you
        // just asked for is behind a settings window you have to dismiss.
        // `news open` follows the browser to its workspace from its side.
        onTriggered: { page.app.run(["news", "open", modelData.url]); page.app.hide() }
        onStarred: page.app.run(["news", "read", modelData.url])
      }
    }

    Ui.Chip {
      visible: page.unreadNews > 0
      text: strings.t("overviewsection.text.1", "Mark all as read")
      onClicked: page.app.run(["news", "read-all"])
    }
  }
}
