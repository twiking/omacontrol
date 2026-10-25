import QtQuick
import qs.Commons
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null
  Ui.SettingGroup {
    title: strings.t("defaultssection.title.1", "Applications")
    note: strings.t("defaultssection.note.1", "An app you have not installed yet is set up the first time you pick it.")

    Ui.PickerRow {
      label: strings.t("defaultssection.label.1", "Browser")
      value: page.app.group("browser").current
      options: page.app.groupOptions("browser")
      onPicked: function(next) { page.app.run(["menu", "run", "setup.default.browser." + next]) }
    }

    Ui.PickerRow {
      label: strings.t("defaultssection.label.2", "Terminal")
      value: page.app.group("terminal").current
      options: page.app.groupOptions("terminal")
      onPicked: function(next) { page.app.run(["menu", "run", "setup.default.terminal." + next]) }
    }

    Ui.PickerRow {
      label: strings.t("defaultssection.label.3", "Editor")
      value: page.app.group("editor").current
      options: page.app.groupOptions("editor")
      onPicked: function(next) { page.app.run(["menu", "run", "setup.default.editor." + next]) }
    }

    Ui.PickerRow {
      label: strings.t("defaultssection.label.4", "Coding agent")
      value: page.app.agentsState.current !== undefined ? String(page.app.agentsState.current) : ""
      options: page.app.agentOptions()
      onPicked: function(next) { page.app.run(["agents", "run", next]) }
    }
  }
}
