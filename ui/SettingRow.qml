import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// A setting: its name on the left, the control that sets it on the right —
// the shape every row of every page shares. What makes it navigable is
// NavRow underneath; this is only the layout.
NavRow {
  id: settingRow
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  default property alias control: controlHolder.data

  // A slot before the name, for a control that decides what the row *is*
  // rather than what its setting is worth — which section a widget belongs
  // to, say. Those read as part of the name, so they sit with it rather than
  // across the row among the controls.
  //
  // It sizes itself from what it holds and is nothing at all when empty, so
  // every row that puts nothing here is laid out exactly as before. Whatever
  // goes in must not anchor to it: a child anchored to a parent that measures
  // its children is a binding loop.
  property alias leading: leadingHolder.data

  // Rows whose leading controls differ in width — Disable on one, Remove on
  // the next — would each start their name in a different place, and a column
  // of names that nearly lines up is worse than one that plainly does not. A
  // page that leads with controls gives them one width for the whole list.
  property real leadingWidth: -1

  Item {
    id: leadingHolder
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: childrenRect.width
    implicitHeight: childrenRect.height
    width: settingRow.leadingWidth >= 0 ? settingRow.leadingWidth : implicitWidth
    height: implicitHeight
  }

  Column {
    id: labelColumn
    anchors.left: leadingHolder.right
    anchors.leftMargin: leadingHolder.width > 0 ? Style.space(12) : 0
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width * 0.5
    spacing: Style.space(2)

    // A setting this window has changed says so on its own title line: the
    // mark ahead of the name, the way out after it.
    Row {
      spacing: Style.space(6)

      // A Row lines its children up by the top, which leaves the smaller
      // (reset) floating above the name it belongs to. Both sit on the
      // name's baseline instead, so the three read as one line.
      Text {
        textFormat: Text.PlainText
        anchors.baseline: titleText.baseline
        visible: settingRow.changed
        text: "\u25cf"
        color: Local.Palette.accent
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: titleText
        textFormat: Text.PlainText
        text: settingRow.label
        color: Local.Palette.foreground
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.subtitle
        // Regular: the group heading is the bold thing on the page, and a
        // column of bold labels under it flattens that back out.
      }

      Text {
        id: resetLink
        textFormat: Text.PlainText
        anchors.baseline: titleText.baseline
        visible: settingRow.changed
        text: strings.t("settingrow.text.1", "(reset)")
        color: resetMouse.containsMouse ? Local.Palette.accent : Local.Palette.muted
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.caption
        font.underline: resetMouse.containsMouse

        MouseArea {
          id: resetMouse
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: settingRow.resetRequested()
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: settingRow.description !== ""
      width: parent.width
      text: settingRow.description
      wrapMode: Text.WordWrap
      color: Local.Palette.muted
      font.family: Local.Palette.fontFamily
      font.pixelSize: Style.font.caption
    }

    // Under the label rather than beside the control: it belongs to what the
    // setting is, not to what it is set to, and there is room here for the
    // way out to say what it does.
  }

  Item {
    id: controlHolder
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width * 0.46
    // Measured from what the controls ask for, not from where they ended up.
    // `childrenRect` is the tempting way to write this and the wrong one: the
    // row's height is built from this value (see implicitHeight above), and
    // this holder centres its children against that same height, so reading
    // their laid-out geometry closes the circle and Qt freezes the row at
    // whatever height it happened to have. Implicit sizes are what a control
    // wants before anyone has placed it, so asking for those stays outside
    // the loop.
    implicitHeight: {
      var tallest = 0
      for (var i = 0; i < children.length; i++)
        tallest = Math.max(tallest, children[i].implicitHeight)
      return tallest
    }
  }
}
