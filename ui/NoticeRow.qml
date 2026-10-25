import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// Something the window is telling you that you did not ask about: a partition
// filling up, a peripheral about to die, an update waiting. An icon to say how
// much it matters, what it is, what to do about it, and a way to say "not now".
//
// The dismiss sits *after* the action and is drawn as a glyph rather than a
// button, because the two are not equals. The action is what the notice is
// for; dismissing is a way to stop reading it. Two buttons of the same weight
// at the same end of a row makes that a coin toss.
Local.NavRow {
  id: notice
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  property string glyph: ""
  property bool urgent: false
  property string actionText: ""
  property bool dismissable: false
  signal triggered()
  signal dismissed()

  // The action is what Enter does here; dismissing is deliberate, so it is
  // not on a key that could be leaned on. A notice with nothing to do about it
  // offers no key at all, rather than a keycap with an empty label on it.
  navKeys: notice.actionText !== "" ? [{ key: "↵", label: notice.actionText }] : []
  onNavActivate: if (notice.actionText !== "") notice.triggered()

  implicitHeight: Math.max(labels.implicitHeight, controls.height) + Style.space(12)

  Text {
    id: mark
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.top: labels.top
    text: notice.glyph
    color: notice.urgent ? Local.Palette.urgent : Local.Palette.muted
    font.family: Local.Palette.fontFamily
    font.pixelSize: Style.font.iconLarge
  }

  Column {
    id: labels
    anchors.left: mark.right
    anchors.leftMargin: Style.space(12)
    anchors.right: controls.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: notice.label
      wrapMode: Text.WordWrap
      color: Local.Palette.foreground
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      visible: notice.description !== ""
      width: parent.width
      text: notice.description
      wrapMode: Text.WordWrap
      color: notice.urgent ? Local.Palette.urgent : Local.Palette.muted
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Row {
    id: controls
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Button {
      anchors.verticalCenter: parent.verticalCenter
      visible: notice.actionText !== ""
      text: notice.actionText
      bordered: true
      foreground: Local.Palette.foreground
      accent: Local.Palette.accent
      fontFamily: Local.Palette.fontFamily
      fontSize: Style.font.caption
      onClicked: notice.triggered()
    }

    // A glyph, not a button: it undoes nothing and configures nothing, it just
    // stops the row being shown for a day.
    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      visible: notice.dismissable
      text: strings.t("noticerow.text.1", "")
      color: dismissMouse.containsMouse ? Local.Palette.foreground : Local.Palette.shade(0.35)
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.body
      rightPadding: Style.space(2)
      leftPadding: Style.space(6)

      MouseArea {
        id: dismissMouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: notice.dismissed()
      }
    }
  }
}
