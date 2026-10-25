import QtQuick
import qs.Commons
import "." as Local

// One Bluetooth device: what it is, how it is doing, and the actions that
// apply to it. A device you own can be connected or forgotten; one the
// adapter merely saw can only be paired.
Item {
  id: deviceRow
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  property string address: ""
  property string name: ""
  property string kind: ""
  property bool paired: false
  property bool connected: false
  property int battery: -1
  // dBm as BlueZ reports it while it can hear the device; -200 stands for
  // "not heard", which is every device we are not currently scanning.
  property int rssi: -200

  signal connectRequested()
  signal disconnectRequested()
  signal pairRequested()
  signal forgetRequested()

  // The same thing clicking the row does, which depends on what the device is.
  Local.NavCursor {
    id: nav
    anchors.fill: parent
    searchText: deviceRow.title + " " + deviceRow.address + " " + deviceRow.kind
    navKeys: deviceRow.connected ? [{ key: "Space", label: strings.t("devicerow.label.1", "Disconnect")}]
      : (deviceRow.paired ? [{ key: "Space", label: strings.t("devicerow.label.2", "Connect")}]
                          : [{ key: "Space", label: strings.t("devicerow.label.3", "Pair")}])
    onNavActivate: {
      if (deviceRow.connected) deviceRow.disconnectRequested()
      else if (deviceRow.paired) deviceRow.connectRequested()
      else deviceRow.pairRequested()
    }
  }

  // Falling back to the address keeps a nameless device identifiable rather
  // than blank.
  readonly property string title: name !== "" ? name : address

  readonly property var batteryIcons: ["\udb80\udc7a", "\udb80\udc7b", "\udb80\udc7c", "\udb80\udc7d",
                                       "\udb80\udc7e", "\udb80\udc7f", "\udb80\udc80", "\udb80\udc81",
                                       "\udb80\udc82", "\udb80\udc79"]
  // Bluetooth has no percentage of its own, so the usable span is mapped to
  // the one SignalBars already draws: about -50 dBm is as close as a thing
  // gets, -95 is the edge of hearing.
  readonly property int signalStrength:
    Math.max(0, Math.min(100, Math.round((deviceRow.rssi + 95) * 100 / 45)))

  readonly property string batteryIcon:
    batteryIcons[Math.max(0, Math.min(9, Math.floor(deviceRow.battery / 10)))]

  visible: !nav.searchHidden
  width: parent ? parent.width : 0
  implicitHeight: Style.spacing.controlHeight + Style.space(4)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: deviceRow.connected
      ? Qt.rgba(Local.Palette.accent.r, Local.Palette.accent.g, Local.Palette.accent.b, 0.14)
      // The forget mark takes the pointer off the row's own area, so the row
      // has to count it as hover of its own or the band blinks out from under
      // the cursor.
      : (deviceMouse.containsMouse || forgetMouse.containsMouse ? Local.Palette.hover : "transparent")
  }

  MouseArea {
    id: deviceMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (deviceRow.connected) deviceRow.disconnectRequested()
      else if (deviceRow.paired) deviceRow.connectRequested()
      else deviceRow.pairRequested()
    }
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      // BlueZ reports a freedesktop icon name; these are the kinds that
      // actually turn up, and anything else gets the generic mark.
      text: deviceRow.kind.indexOf("keyboard") !== -1 ? ""
          : deviceRow.kind.indexOf("mouse") !== -1 ? ""
          : deviceRow.kind.indexOf("headset") !== -1 || deviceRow.kind.indexOf("headphone") !== -1 ? ""
          : deviceRow.kind.indexOf("audio") !== -1 ? ""
          : deviceRow.kind.indexOf("phone") !== -1 ? ""
          : deviceRow.kind.indexOf("watch") !== -1 ? ""
          : ""
      color: deviceRow.connected ? Local.Palette.accent : Local.Palette.muted
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.body
      width: Style.space(20)
    }

    Local.SignalBars {
      anchors.verticalCenter: parent.verticalCenter
      visible: deviceRow.rssi > -200 && !deviceRow.paired
      strength: deviceRow.signalStrength
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: deviceRow.title
      color: Local.Palette.foreground
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.body
      font.bold: deviceRow.connected
    }

  }

  Row {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: deviceRow.battery >= 0
      // The same ten-step set the bar's power plugin draws a battery with, so
      // a peripheral's charge reads the way the machine's own does.
      text: deviceRow.batteryIcon + " " + deviceRow.battery + "%"
      // A device about to die is worth noticing before it dies.
      color: deviceRow.battery <= 20 ? Local.Palette.urgent : Local.Palette.muted
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.caption
    }

    // No Connect / Disconnect / Pair button: the row already does whatever the
    // device is asking for, and a button repeating it is a second target for
    // one action. Forget is the exception — it is not what a click does, so it
    // needs somewhere of its own, and it wears the mark the bar's own
    // Bluetooth panel gives it.
    Item {
      anchors.verticalCenter: parent.verticalCenter
      visible: deviceRow.paired
      opacity: deviceMouse.containsMouse || forgetMouse.containsMouse ? 1 : 0
      implicitWidth: Style.spacing.controlHeight
      implicitHeight: Style.spacing.controlHeight

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "\udb80\udd59"
        color: forgetMouse.containsMouse ? Local.Palette.accent : Local.Palette.muted
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.subtitle
      }

      MouseArea {
        id: forgetMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: deviceRow.forgetRequested()
      }
    }
  }
}
