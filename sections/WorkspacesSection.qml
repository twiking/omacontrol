pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property var rules: app.workspaceRules
  readonly property var setups: app.workspaceSetups
  readonly property var displays: (app.monitors !== undefined ? app.monitors : []).filter(function(m) {
    return m.connected !== false
  })

  readonly property var unsetWorkspaces: {
    var out = []
    for (var i = 1; i <= 10; i++) {
      var id = String(i)
      if (!setups.some(function(s) { return String(s.id) === id })) out.push(id)
    }
    return out
  }

  // Displays are named by what they say about themselves, so a rule follows
  // the screen rather than the socket it happens to be in.
  function displayOptions(noneLabel) {
    return [{ value: "", label: noneLabel }].concat(displays.map(function(m) {
      return { value: String(m.name), label: String(m.label || m.name) }
    }))
  }

  // ---------------------------------------------------------- applications
  //
  // The rules themselves live on Applications, one page per application. They
  // were here first, and here they were a second place writing the same Lua:
  // a reader who had set Slack from one page found the other saying it too,
  // with no way to tell which was the one that counted. What is left is the
  // way in, since an application bound to a workspace is a thing people come
  // to this page looking for.
  Ui.SettingGroup {
    title: strings.t("workspacessection.title.1", "Applications")
    note: page.rules.length === 0
      ? strings.t("workspacessection.rulesNone", "No application is bound to a workspace yet.")
      : strings.tn("workspacessection.rulesOpen", page.rules.length,
                   "One application opens somewhere of its own.").arg(page.rules.length)

    Ui.ActionRow {
      label: strings.t("workspacessection.label.1", "Where applications open")
      description: strings.t("workspacessection.description.1", "Which workspace an application opens on, how it shows, and whether it starts at login.")
      buttonText: strings.t("workspacessection.buttonText.1", "Apps")
      onTriggered: page.app.pageId = "apps.list"
    }
  }

  // ------------------------------------------------------------ workspaces
  //
  // A rule for the place, not for what opens there — a different kind of
  // thing, so a line rather than only a heading marks where one ends.
  Rectangle {
    width: parent.width
    height: 1
    color: Ui.Palette.hairline
  }

  Ui.SettingGroup {
    title: strings.t("workspacessection.title.2", "Workspace settings")
    note: page.unsetWorkspaces.length === 0 ? strings.t("workspacessection.everySet", "Every workspace is set up.") : ""

    Ui.PickerRow {
      label: strings.t("workspacessection.label.2", "Set up a workspace")
      visible: page.unsetWorkspaces.length > 0
      description: strings.t("workspacessection.description.2", "Its display, name, layout, and whether it stays when empty.")
      value: ""
      options: [{ value: "", label: strings.t("workspacessection.label.9", "Pick a workspace…")}].concat(page.unsetWorkspaces.map(function(id) {
        return { value: id, label: strings.t("workspacessection.workspace", "Workspace %1").arg(id) }
      }))
      onPicked: function(next) { if (next !== "") page.app.run(["workspaces", "setup", "add", next]) }
    }
  }
  //
  // The place rather than what opens there. Only a workspace with something
  // set gets a group, so ten empty groups do not bury the applications above.
  Repeater {
    model: page.setups

    delegate: Ui.SettingGroup {
      id: setupGroup
      required property var modelData

      readonly property string id: String(modelData.id)
      readonly property bool ours: modelData.ours === true
      readonly property bool theirs: modelData.theirs === true

      width: parent.width
      title: strings.t("workspacessection.workspace", "Workspace %1").arg(id)

      Ui.TextRow {
        label: strings.t("workspacessection.label.3", "Name")
        description: strings.t("workspacessection.description.3", "Shown in the bar instead of the number.")
        value: String(setupGroup.modelData.name || "")
        placeholder: setupGroup.id
        onCommitted: function(next) { page.app.run(["workspaces", "setup", "set", setupGroup.id, "name", next]) }
      }

      Ui.PickerRow {
        label: strings.t("workspacessection.label.4", "Display")
        visible: page.displays.length > 1
        value: String(setupGroup.modelData.monitor || "")
        options: page.displayOptions("Any")
        onPicked: function(next) { page.app.run(["workspaces", "setup", "set", setupGroup.id, "monitor", next]) }
      }

      Ui.SwitchRow {
        label: strings.t("workspacessection.label.5", "Default on its display")
        description: strings.t("workspacessection.description.4", "The workspace a display shows when it is plugged in.")
        visible: String(setupGroup.modelData.monitor || "") !== ""
        checked: setupGroup.modelData.default === true
        onRequested: function(next) { page.app.run(["workspaces", "setup", "set", setupGroup.id, "default", next ? "true" : "false"]) }
      }

      Ui.SwitchRow {
        label: strings.t("workspacessection.label.6", "Keep when empty")
        description: strings.t("workspacessection.description.5", "Stays in the bar with no windows on it.")
        checked: setupGroup.modelData.persistent === true
        onRequested: function(next) { page.app.run(["workspaces", "setup", "set", setupGroup.id, "persistent", next ? "true" : "false"]) }
      }

      Ui.ChoiceRow {
        label: strings.t("workspacessection.label.7", "Layout")
        options: [
          { value: "", label: strings.t("workspacessection.label.10", "Default")},
          { value: "dwindle", label: strings.t("workspacessection.label.11", "Dwindle")},
          { value: "master", label: strings.t("workspacessection.label.12", "Master")},
          { value: "scrolling", label: strings.t("workspacessection.label.13", "Scrolling")}
        ]
        value: String(setupGroup.modelData.layout || "")
        onPicked: function(next) { page.app.run(["workspaces", "setup", "set", setupGroup.id, "layout", next]) }
      }

      Ui.SwitchRow {
        label: strings.t("workspacessection.label.8", "Borderless, no gaps")
        description: strings.t("workspacessection.description.6", "Windows edge to edge with no borders, rounding or decorations.")
        checked: setupGroup.modelData.minimal === true
        onRequested: function(next) { page.app.run(["workspaces", "setup", "set", setupGroup.id, "minimal", next ? "true" : "false"]) }
      }

      Ui.ActionRow {
        buttonText: strings.t("workspacessection.buttonText.2", "Remove")
        onTriggered: page.app.run(["workspaces", "setup", "remove", setupGroup.id])
      }
    }
  }

}
