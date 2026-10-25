import QtQuick
import qs.Commons
import qs.Ui
import "." as Local

// Three ways to set one piece of branding, the way the menu offers them:
// type it, point at an image, or put the shipped one back.
Local.SettingRow {
  id: brandingRow
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  // "text", "image" or "default" — the caller decides what each one runs.
  signal chose(string variant)

  Row {
    anchors.right: parent.right
    spacing: Style.space(8)

    Button {
      text: strings.t("brandingrow.text.1", "Text…")
      bordered: true
      foreground: Local.Palette.foreground
      accent: Local.Palette.accent
      fontFamily: Local.Palette.fontFamily
      onClicked: brandingRow.chose("text")
    }

    Button {
      text: strings.t("brandingrow.text.2", "Image…")
      bordered: true
      foreground: Local.Palette.foreground
      accent: Local.Palette.accent
      fontFamily: Local.Palette.fontFamily
      onClicked: brandingRow.chose("image")
    }

    Button {
      text: strings.t("brandingrow.text.3", "Reset")
      bordered: true
      foreground: Local.Palette.foreground
      accent: Local.Palette.accent
      fontFamily: Local.Palette.fontFamily
      onClicked: brandingRow.chose("default")
    }
  }
}
