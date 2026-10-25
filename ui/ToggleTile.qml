import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// One switch, as a tile: icon, name over what it is doing, then the switch —
// all on one line. Four across.
//
// Why a tile and not a row. These are the things flipped several times a day,
// and the question asked of them is *which of these are on right now* — asked
// of the whole set at once, from across the desk. A column of rows answers it
// with four small knobs in a vertical line, all in the same place, so the
// answer has to be read one row at a time. A tile that fills with the accent
// when it is on answers it in one glance and at any distance.
//
// So the fill is the state, and the switch is only the affordance. That is also
// why the whole tile is clickable: a target the size of a tile is one you can
// hit without looking, which is the point of putting these on the front page.
//
// Everything on one line rather than stacked, because these sit above the
// page's real content and a two-line tile pushed it off the fold. They are a
// strip of chrome across the top, not the subject of the page.
Local.NavRow {
  id: tile
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  property string glyph: ""
  property string note: ""
  property bool checked: false
  signal requested(bool next)

  // The grid sets the width, so the row's own full-width binding has to go.
  width: undefined
  // And the cursor is a ring around the tile rather than a band across it.
  showBand: false

  onNavActivate: tile.requested(!tile.checked)
  navKeys: [{ key: "Space", label: strings.t("toggletile.label.1", "Toggle")}]

  implicitHeight: Math.max(badge.height, control.height) + Style.space(18)

  Rectangle {
    id: surface
    anchors.fill: parent
    radius: Local.Palette.cardRadius
    color: tile.checked ? Local.Palette.accent
                        : (mouse.containsMouse ? Local.Palette.hover : Local.Palette.card)
    // An accent-filled tile needs no outline; an empty one is only a card.
    border.width: tile.checked ? 0 : Style.spacing.hairline
    border.color: Local.Palette.divider

    // The keyboard cursor, drawn just inside the edge so a tile under the
    // cursor reads the same whether it is filled or not.
    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.spacing.hairline
      radius: parent.radius
      color: "transparent"
      border.width: Style.normalBorderWidth
      border.color: tile.checked ? Local.Palette.onAccent : Local.Palette.accent
      visible: tile.current
    }
  }

  Rectangle {
    id: badge
    anchors.left: parent.left
    anchors.leftMargin: Style.space(11)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(28)
    height: Style.space(28)
    radius: width / 2
    color: tile.checked ? Local.Palette.onAccentWash(0.20) : Local.Palette.shade(0.12)

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: tile.glyph
      color: tile.checked ? Local.Palette.onAccent : Local.Palette.foreground
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.iconSmall
    }
  }

  Column {
    anchors.left: badge.right
    anchors.leftMargin: Style.space(9)
    anchors.right: control.left
    anchors.rightMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: tile.label
      elide: Text.ElideRight
      color: tile.checked ? Local.Palette.onAccent : Local.Palette.foreground
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      visible: tile.note !== ""
      width: parent.width
      text: tile.note
      elide: Text.ElideRight
      color: tile.checked ? Local.Palette.onAccent : Local.Palette.muted
      opacity: tile.checked ? 0.9 : 1
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  ToggleSwitch {
    id: control
    anchors.right: parent.right
    anchors.rightMargin: Style.space(11)
    anchors.verticalCenter: parent.verticalCenter
    checked: tile.checked
    // The tile owns the click, so the switch does not take the cursor.
    interactive: false
    foreground: tile.checked ? Local.Palette.onAccent : Local.Palette.foreground
    // On a filled tile the accent track would vanish into the fill.
    accent: tile.checked ? Local.Palette.onAccentWash(0.35) : Local.Palette.accent
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.requested(!tile.checked)
  }
}
