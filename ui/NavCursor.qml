import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// The keyboard cursor for a row that is not a SettingRow.
//
// A device, a network and a binding are lists of things rather than one
// setting each, and their rows are built to look like it. Rather than force
// them into SettingRow's shape, this carries the same contract into them:
// drop one in, anchored over the row, and the row joins the cursor.
//
// It registers itself rather than its parent, and mirrors the geometry the
// window sorts by, so from the window's side it is simply another row.
Item {
  id: nav
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  // Filled in by whoever drops it in.
  property var navKeys: []
  signal navActivate()
  signal navStep(int delta)

  // The window's side of the contract.
  property bool current: false
  property bool navBlocking: false
  property bool changed: false
  signal resetRequested()
  // What ⌫ is called on this row. A thing you created is not reset, it is
  // removed or forgotten, and the legend has to say which.
  property string navResetLabel: strings.t("navcursor.navResetLabel.1", "Reset")

  // Behind the row's own content: the band is a background, and drawing it
  // over the text would tint what it is meant to be pointing at.
  z: -1

  // What this row is called, for the search. A row named by the system rather
  // than by the source has to say so itself.
  property string searchText: ""
  readonly property bool searchHidden: navController !== null
    && navController.searching === true
    && !navController.rowMatches(searchText, "", "")

  property var navController: null

  // Told, not asked, the same way a NavRow tells it. This was declared and
  // never reported, so a Wi-Fi row with its passphrase field open did not
  // actually hold the keyboard: Up and Down walked the cursor off a row that
  // still had the focus, and the legend offered "esc Close" beside its own
  // "esc Cancel".
  onNavBlockingChanged: if (nav.navController
    && nav.navController.setNavBlocked !== undefined)
      nav.navController.setNavBlocked(nav, nav.navBlocking)

  function findController() {
    var node = nav.parent
    while (node) {
      if (node.registerNavRow !== undefined) return node
      if (node.app !== undefined && node.app !== null
          && node.app.registerNavRow !== undefined) return node.app
      node = node.parent
    }
    return null
  }

  Component.onCompleted: {
    nav.navController = findController()
    if (nav.navController) {
      nav.navController.registerNavRow(nav)
      // A row rebuilt mid-edit is already blocking by the time it is up, so
      // the state is reported rather than waited for.
      if (nav.navBlocking && nav.navController.setNavBlocked !== undefined)
        nav.navController.setNavBlocked(nav, true)
    }
  }

  Component.onDestruction: {
    // A row destroyed while holding the keyboard has to hand it back, or the
    // window stays blocked with nothing left to unblock it. A list rebuilt by
    // a poll can take a row out mid-edit.
    if (nav.navController) {
      if (nav.navBlocking && nav.navController.setNavBlocked !== undefined)
        nav.navController.setNavBlocked(nav, false)
      nav.navController.unregisterNavRow(nav)
    }
  }

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.space(10)
    anchors.rightMargin: -Style.space(10)
    radius: Style.cornerRadius
    color: Qt.rgba(Local.Palette.accent.r, Local.Palette.accent.g, Local.Palette.accent.b, 0.14)
    visible: nav.current
  }
}
