import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// One network: name, band, signal, what it wants to let you in, and what
// clicking it will do. A network that needs a password asks for it in place
// rather than in a dialog on top of the list.
//
// The facts sit in columns rather than in a sentence under the name, because
// the reader is comparing two similar networks and that only works if the
// band sits over the band and the dBm over the dBm.
//
// An Item root, not a Column. This hosts a NavCursor anchored over the whole
// row — which is how every other list row here joins the keyboard cursor — and
// a Column positions its children, so it rejects a fill-anchored one and then
// stops laying out at all: "Column will not function", and the Wi-Fi list
// renders as an empty band. The content goes in an inner Column instead.
Item {
  id: wifiRow
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property string ssid: ""
  property int signalStrength: 0
  property bool secured: false
  // What the network is, beyond its name: which band this access point is on,
  // what it wants to let you in, and the driver's own signal reading.
  property string band: ""
  property string security: ""
  property int dbm: 0
  property bool saved: false
  property bool active: false
  // Whether this row is the one currently asking for a passphrase.
  property bool prompting: false
  // Whether this is the network currently being joined.
  property bool connecting: false

  signal connectRequested(string password)
  signal promptToggled()
  signal disconnectRequested()
  signal forgetRequested()

  // A saved network has its password already; only a new secured one needs asking.
  readonly property bool needsPassword: wifiRow.secured && !wifiRow.saved

  // Equal *space* between the details, which is not the same thing as equal
  // columns and cannot be both: with fixed-width right-aligned cells the gap
  // you see is whatever whitespace each value leaves over, so "5 GHz" and
  // "WPA2" drifted apart while longer values crowded — and an empty Saved cell
  // sat between two figures as a phantom column of pure air.
  //
  // So each value is as wide as itself, one spacing between them, and nothing
  // is drawn when there is nothing to say. The cost is that the figures no
  // longer stack down the list.
  readonly property real detailGap: Style.space(16)

  // Both figures, in that order, rather than one standing in for the other.
  //
  // The percentage is NetworkManager's and is always there; the dBm is the
  // driver's and exists only while the kernel's scan cache holds that access
  // point. Picking whichever was available put "−62 dBm" and "27 %" in the
  // same column on neighbouring rows, which is not a column anyone can
  // compare down. The percentage leads because it is the one always present,
  // and the dBm follows it as the precise reading when there is one.
  readonly property string signalText: wifiRow.signalStrength + "%"
  readonly property string dbmText: wifiRow.dbm !== 0
    ? "−" + Math.abs(wifiRow.dbm) + " dBm" : ""

  // Connecting is the one thing worth a key here; a network that wants a
  // passphrase opens the prompt instead, and the prompt takes the keyboard.
  Local.NavCursor {
    id: nav
    anchors.fill: parent
    searchText: wifiRow.ssid + " " + wifiRow.band + " " + wifiRow.security
    navBlocking: wifiRow.prompting
    // While the prompt is open the row's keys are the prompt's, since that is
    // what the keyboard is actually in.
    navKeys: wifiRow.prompting
        ? [{ key: "↵", label: strings.t("wifirow.label.1", "Connect")}, { key: "esc", label: strings.t("wifirow.label.2", "Cancel")}]
      : wifiRow.active ? [{ key: "Space", label: strings.t("wifirow.label.3", "Disconnect")}]
      : (wifiRow.needsPassword ? [{ key: "Space", label: strings.t("wifirow.label.4", "Passphrase")}]
                               : [{ key: "Space", label: strings.t("wifirow.label.5", "Connect")}])
    // Forgetting a saved network is the second thing there is to do to one,
    // and it was reachable only by hovering it — invisible to the keyboard
    // and to anyone who never happened to hover. ⌫ is where this window puts
    // "undo what you did to this row"; on a network that is Forget.
    changed: wifiRow.saved && !wifiRow.active && !wifiRow.prompting
    navResetLabel: strings.t("wifirow.navResetLabel.1", "Forget")
    onResetRequested: wifiRow.forgetRequested()
    onNavActivate: {
      if (wifiRow.active) wifiRow.disconnectRequested()
      else if (wifiRow.needsPassword) wifiRow.promptToggled()
      else wifiRow.connectRequested("")
    }
  }

  visible: !nav.searchHidden
  width: parent ? parent.width : 0
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: parent.width
    spacing: Style.space(6)

  Item {
    id: line
    width: parent.width
    implicitHeight: Style.spacing.controlHeight + Style.space(4)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: wifiRow.active
        ? Qt.rgba(Local.Palette.accent.r, Local.Palette.accent.g, Local.Palette.accent.b, 0.14)
        : (wifiMouse.containsMouse ? Qt.rgba(Local.Palette.foreground.r, Local.Palette.foreground.g, Local.Palette.foreground.b, 0.08) : "transparent")
    }

    MouseArea {
      id: wifiMouse
      anchors.fill: parent
      hoverEnabled: true
      // The active network's row does nothing when clicked, so it does not
      // offer to be clicked.
      cursorShape: wifiRow.active ? Qt.ArrowCursor : Qt.PointingHandCursor
      onClicked: {
        if (wifiRow.active) return
        if (wifiRow.needsPassword) wifiRow.promptToggled()
        else wifiRow.connectRequested("")
      }
    }

    Local.SignalBars {
      id: bars
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      strength: wifiRow.signalStrength
      accented: wifiRow.active
    }

    Text {
      textFormat: Text.PlainText
      anchors.left: bars.right
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: details.left
      anchors.rightMargin: Style.space(12)
      text: wifiRow.ssid
      elide: Text.ElideRight
      color: Local.Palette.foreground
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    // Everything about the network lives at the right-hand end, with the name
    // alone on the left. Each detail keeps a fixed width so the figures still
    // line up down the list — the point of columns is comparing one row
    // against the next, and a cluster that sizes itself to its contents puts
    // every row's dBm in a different place.
    //
    // The buttons come *before* the details in the row, so appearing on hover
    // pushes nothing: the row is anchored by its right edge, so they open out
    // to the left.
    Row {
      id: details
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: wifiRow.detailGap

      // Joining takes seconds; saying nothing for them reads as a click that
      // did not land, and invites a second one.
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: wifiRow.connecting
        text: strings.t("wifirow.text.1", "Connecting…")
        color: Local.Palette.accent
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        anchors.verticalCenter: parent.verticalCenter
        visible: wifiRow.active && !wifiRow.connecting
        text: strings.t("wifirow.text.2", "Disconnect")
        bordered: true
        foreground: Local.Palette.foreground
        accent: Local.Palette.accent
        fontFamily: Local.Palette.fontFamily
        fontSize: Style.font.caption
        onClicked: wifiRow.disconnectRequested()
      }

      Button {
        anchors.verticalCenter: parent.verticalCenter
        // Under the keyboard cursor as well as under the mouse: the row is
        // reachable both ways, so its actions have to be visible both ways.
        visible: wifiRow.saved && !wifiRow.active && !wifiRow.connecting
          && (wifiMouse.containsMouse || nav.current)
        text: strings.t("wifirow.text.3", "Forget")
        bordered: true
        foreground: Local.Palette.foreground
        accent: Local.Palette.accent
        fontFamily: Local.Palette.fontFamily
        fontSize: Style.font.caption
        onClicked: wifiRow.forgetRequested()
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: !wifiRow.connecting
        text: wifiRow.signalText
        color: Local.Palette.foreground
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: !wifiRow.connecting && wifiRow.dbmText !== ""
        text: wifiRow.dbmText
        color: Local.Palette.muted
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: wifiRow.band !== ""
        text: wifiRow.band
        color: Local.Palette.muted
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: wifiRow.saved && !wifiRow.connecting
        text: strings.t("wifirow.text.4", "Saved")
        color: Local.Palette.accent
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      // The padlock that used to sit beside the name is gone: "Open" is a fact
      // worth naming, and the absence of a padlock is not.
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: !wifiRow.connecting && wifiRow.security !== ""
        text: wifiRow.security
        color: Local.Palette.muted
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Row {
    width: parent.width
    visible: wifiRow.prompting
    spacing: Style.space(8)

    // Opening the prompt is the whole of the intention to type in it, so the
    // field takes the keyboard rather than asking for a second click. It comes
    // up empty each time: a passphrase left over from a rejected attempt is a
    // passphrase that gets submitted again unread.
    onVisibleChanged: if (visible) {
      passwordField.text = ""
      passwordField.forceActiveFocus()
    }

    TextField {
      id: passwordField
      width: parent.width - connectButton.width - Style.space(8)
      placeholderText: strings.t("wifirow.passwordFor", "Password for %1")
        .arg(wifiRow.ssid)
      password: true
      foreground: Local.Palette.foreground
      accent: Local.Palette.accent

      // A delegate rebuilt while the prompt is open comes up already visible,
      // so the handler above never fires for it and the field would sit there
      // waiting for a click it should not need.
      Component.onCompleted: if (wifiRow.prompting) forceActiveFocus()

      // Enter is handled and *accepted* here. `accepted` fires without
      // accepting the event, so an Enter left to bubble reaches the window,
      // which reads it as "activate this row" and drops straight back into the
      // prompt just left. Escape is the way out — without it the row holds the
      // keyboard with nothing to release it.
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (passwordField.text !== "") wifiRow.connectRequested(passwordField.text)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          wifiRow.promptToggled()
          event.accepted = true
        }
      }
    }

    Button {
      id: connectButton
      anchors.verticalCenter: parent.verticalCenter
      text: strings.t("wifirow.text.5", "Connect")
      bordered: true
      // Nothing to send yet, and a button that answers a click with silence
      // is worse than one that says it is not ready.
      enabled: passwordField.text !== ""
      opacity: enabled ? 1 : 0.45
      foreground: Local.Palette.foreground
      accent: Local.Palette.accent
      fontFamily: Local.Palette.fontFamily
      onClicked: if (passwordField.text !== "") wifiRow.connectRequested(passwordField.text)
    }
  }
  }
}
