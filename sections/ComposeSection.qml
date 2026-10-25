pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null
  Ui.SettingGroup {
    title: strings.t("composesection.title.1", "Add a sequence")
    note: strings.t("composesection.note.1", "The compose key first, then the keys to press after it. Write the compose key as <Multi_key>.")

    Row {
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: keysField
        width: (parent.width - addButton.width - Style.space(16)) * 0.45
        placeholderText: strings.t("composesection.placeholderText.1", "<Multi_key> <s> <e>")
        foreground: page.app.foreground
        accent: page.app.accent
      }

      TextField {
        id: textField
        width: (parent.width - addButton.width - Style.space(16)) * 0.55
        placeholderText: strings.t("composesection.placeholderText.2", "text it types")
        foreground: page.app.foreground
        accent: page.app.accent
      }

      Button {
        id: addButton
        text: strings.t("composesection.text.1", "Add")
        bordered: true
        foreground: page.app.foreground
        accent: page.app.accent
        anchors.verticalCenter: parent.verticalCenter
        onClicked: {
          if (keysField.text.trim() === "" || textField.text === "") return
          page.app.run(["compose", "add", keysField.text.trim(), textField.text])
          keysField.text = ""
          textField.text = ""
        }
      }
    }
  }

  Ui.SettingGroup {
    title: strings.t("composesection.title.2", "Your sequences")
    note: page.app.composeEntries.length === 0 ? strings.t("composesection.noneDefined", "Nothing defined yet.") : ""

    Repeater {
      model: page.app.composeEntries
      delegate: Item {
        id: composeEntry
        required property var modelData
        width: parent.width
        implicitHeight: Style.spacing.controlHeight

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.45
          elide: Text.ElideRight
          text: composeEntry.modelData.keys
          color: page.app.foreground
          font.family: page.app.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: parent.width * 0.47
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.4
          elide: Text.ElideRight
          text: composeEntry.modelData.text
          color: page.app.muted
          font.family: page.app.fontFamily
          font.pixelSize: Style.font.body
        }

        PanelActionButton {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf00d"
          tooltipText: strings.t("composesection.tooltipText.1", "Remove")
          foreground: page.app.foreground
          onClicked: page.app.run(["compose", "remove", composeEntry.modelData.keys])
        }
      }
    }
  }
}
