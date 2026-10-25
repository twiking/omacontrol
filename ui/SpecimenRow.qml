import QtQuick
import qs.Commons
import "." as Local

// One font, shown in itself: its name, set large in the face.
//
// A sample line under the name was one line too many. Fifty rows of the same
// sentence is a wall of identical text that has to be compared word by word,
// while the name — which is different on every row and already has to be read
// — shows the letterforms on its own once it is big enough to see.
//
// It joins the keyboard cursor like every other list row here, so a font can
// be walked to and chosen without the mouse.
Item {
  id: specimen
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  property string family: ""
  property bool current: false
  signal chose()

  Local.NavCursor {
    id: nav
    anchors.fill: parent
    searchText: specimen.family
    navKeys: [{ key: "Space", label: strings.t("specimenrow.label.1", "Use this font")}]
    onNavActivate: specimen.chose()
  }

  visible: !nav.searchHidden
  width: parent ? parent.width : 0
  implicitHeight: lines.implicitHeight + Style.space(14)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: specimen.current
      ? Qt.rgba(Local.Palette.accent.r, Local.Palette.accent.g, Local.Palette.accent.b, 0.14)
      : (specimenMouse.containsMouse ? Local.Palette.hover : "transparent")
    border.width: specimen.current ? Style.spacing.hairline : 0
    border.color: Local.Palette.accent
  }

  MouseArea {
    id: specimenMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: specimen.chose()
  }

  Column {
    id: lines
    anchors.left: parent.left
    anchors.leftMargin: Style.space(12)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: specimen.family
      elide: Text.ElideRight
      color: specimen.current ? Local.Palette.accent : Local.Palette.foreground
      // The name in its own face, which is the whole point of the row.
      font.family: specimen.family
      font.pixelSize: Style.font.heading
    }

  }
}
