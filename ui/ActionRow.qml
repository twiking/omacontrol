import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// A row whose setting lives behind someone else's flow: the state is shown,
// and the button hands off to the command that owns it.
Local.SettingRow {
  id: actionRow
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property string buttonText: ""
  signal triggered()

  // A button that cannot do anything yet says so rather than failing when
  // pressed: a form that accepts a press and answers with an error has let
  // the reader make a mistake it knew about before they made it.
  property bool actionEnabled: true

  // The row has one button, so activating the row presses it.
  navKeys: [{ key: "\u21b5", label: strings.t("actionrow.label.1", "Open")}]

  onNavActivate: if (actionRow.actionEnabled) actionRow.triggered()

  Button {
    anchors.right: parent.right
    enabled: actionRow.actionEnabled
    opacity: actionRow.actionEnabled ? 1 : 0.4
    text: actionRow.buttonText
    bordered: true
    foreground: Local.Palette.foreground
    accent: Local.Palette.accent
    fontFamily: Local.Palette.fontFamily
    onClicked: if (actionRow.actionEnabled) actionRow.triggered()
  }
}
