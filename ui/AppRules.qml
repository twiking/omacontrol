import QtQuick
import qs.Commons
import "." as Local

// Everything this desktop can be told about one application: where it opens,
// how it shows, whether it starts at login. It is a component rather than a
// page because two pages ask for it — the application's own page, and the
// workspace picker that sends you there — and a setting written in two places
// is a setting that disagrees with itself in one of them.
//
// Every row writes through `workspaces set <class>`, which creates the rule
// on the first write: there is nothing to add first.
SettingGroup {
  id: appRules
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null
  property var displays: []

  function workspaceOptions() {
    var out = [{ value: "", label: strings.t("apprules.label.13", "Wherever it was last open")}]
    for (var i = 1; i <= 10; i++) out.push({ value: String(i), label: strings.t("apprules.workspace", "Workspace %1").arg(i) })
    out.push({ value: "special", label: strings.t("apprules.label.14", "Scratchpad")})
    return out
  }

  // Displays are named by what they say about themselves, so a rule follows
  // the screen rather than the socket it happens to be in.
  function displayOptions(noneLabel) {
    return [{ value: "", label: noneLabel }].concat(displays.map(function(m) {
      return { value: String(m.name), label: String(m.label || m.name) }
    }))
  }

  property var modelData: ({})

  readonly property string cls: String(modelData.class)
  readonly property string name: String(modelData.name || modelData.class)
  readonly property bool ours: modelData.ours === true
  readonly property bool theirs: modelData.theirs === true
  readonly property bool onWorkspace: String(modelData.workspace || "") !== ""
  readonly property bool floating: modelData.shown === "floating"

  width: parent ? parent.width : 0
  title: name

  Local.PickerRow {
    label: strings.t("apprules.label.1", "Opens on")
    value: String(appRules.modelData.workspace || "")
    options: appRules.workspaceOptions()
    onPicked: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "workspace", next]) }
  }

  Local.SwitchRow {
    label: strings.t("apprules.label.2", "Open in the background")
    description: strings.t("apprules.description.1", "Send the window to its workspace without switching to it.")
    visible: appRules.onWorkspace
    checked: appRules.modelData.silent === true
    onRequested: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "silent", next ? "true" : "false"]) }
  }

  Local.PickerRow {
    label: strings.t("apprules.label.3", "Open on display")
    visible: appRules.displays.length > 1
    value: String(appRules.modelData.monitor || "")
    options: appRules.displayOptions(strings.t("apprules.displayFocus",
                                             "Whichever has the focus"))
    onPicked: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "monitor", next]) }
  }

  // One choice, not two switches: a fullscreen window is neither tiled nor
  // floating in any way you can see, so offering both was offering a
  // combination with no meaning.
  Local.ChoiceRow {
    label: strings.t("apprules.label.4", "Shown as")
    description: strings.t("apprules.description.2", "Floating opens a free window rather than one tiled into the layout.")
    options: [
      { value: "tiled", label: strings.t("apprules.label.15", "Tiled")},
      { value: "floating", label: strings.t("apprules.label.16", "Floating")},
      { value: "fullscreen", label: strings.t("apprules.label.17", "Fullscreen")}
    ]
    value: String(appRules.modelData.shown || "tiled")
    onPicked: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "shown", next]) }
  }

  // What only a floating window can do sits under Floating, and goes away
  // with it — Hyprland ignores a pin on a tiled window rather than saying so.
  // A share of the screen rather than pixels, so one rule fits every
  // display. Empty hands the size back to the application.
  Local.TextRow {
    label: strings.t("apprules.label.5", "Width")
    description: strings.t("apprules.description.3", "Percent of the screen. Leave empty to let the application decide.")
    visible: appRules.floating
    value: Number(appRules.modelData.width) > 0 ? String(appRules.modelData.width) : ""
    placeholder: "e.g. 60"
    onCommitted: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "width", next.trim()]) }
  }

  Local.TextRow {
    label: strings.t("apprules.label.6", "Height")
    description: strings.t("apprules.description.4", "Percent of the screen.")
    visible: appRules.floating
    value: Number(appRules.modelData.height) > 0 ? String(appRules.modelData.height) : ""
    placeholder: "e.g. 60"
    onCommitted: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "height", next.trim()]) }
  }

  Local.SwitchRow {
    label: strings.t("apprules.label.7", "Centred")
    description: strings.t("apprules.description.5", "Opens in the middle of the screen.")
    visible: appRules.floating
    checked: appRules.modelData.center === true
    onRequested: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "center", next ? "true" : "false"]) }
  }

  Local.SwitchRow {
    label: strings.t("apprules.label.8", "Pinned")
    description: strings.t("apprules.description.6", "Stays on screen whichever workspace you switch to.")
    visible: appRules.floating
    checked: appRules.modelData.pin === true
    onRequested: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "pin", next ? "true" : "false"]) }
  }

  // Only for an application with a desktop entry: that is what says how
  // to launch it. A bare window class has no command to start.
  Local.SwitchRow {
    label: strings.t("apprules.label.9", "Start when you log in")
    visible: String(appRules.modelData.desktop || "") !== ""
    checked: appRules.modelData.autostart === true
    onRequested: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "autostart", next ? String(appRules.modelData.desktop) : ""]) }
  }

  Local.SwitchRow {
    label: strings.t("apprules.label.10", "Don't take focus when opening")
    description: strings.t("apprules.description.7", "The window appears without pulling you away from what you were doing.")
    checked: appRules.modelData.noInitialFocus === true
    onRequested: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "no_initial_focus", next ? "true" : "false"]) }
  }

  Local.SwitchRow {
    label: strings.t("apprules.label.11", "Keep the screen awake")
    description: strings.t("apprules.description.8", "No dimming or locking while a window of this application is open.")
    checked: appRules.modelData.idleInhibit === true
    onRequested: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "idle_inhibit", next ? "true" : "false"]) }
  }

  Local.SwitchRow {
    label: strings.t("apprules.label.12", "Hide from screen sharing")
    description: strings.t("apprules.description.9", "Shows as a black rectangle to anyone you share your screen with.")
    checked: appRules.modelData.noScreenShare === true
    onRequested: function(next) { appRules.app.run(["workspaces", "set", appRules.cls, "no_screen_share", next ? "true" : "false"]) }
  }
}
