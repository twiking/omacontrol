import QtQuick
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// OmaControl's own settings, apart from the desktop's. They still live where
// Omarchy keeps a bar widget's settings — the gear's entry in shell.json — so
// `omarchy bar set` reaches them too.
Ui.SectionBody {
  id: page
  property var app: null

  readonly property string widgetId: "io.github.twiking.omacontrol"

  // A widget's settings are keys of its layout entry, so with the gear out of
  // the bar there is nowhere for them to go.
  readonly property bool inBar: {
    var layout = app.barState.layout !== undefined ? app.barState.layout : ({})
    var sections = (typeof Util.barSections !== "undefined" ? Util.barSections : ["left", "center", "right"])
    for (var s = 0; s < sections.length; s++) {
      var list = layout[sections[s]] || []
      for (var i = 0; i < list.length; i++)
        if (String(list[i]) === widgetId) return true
    }
    return false
  }

  readonly property var gear: app.barState.gear !== undefined ? app.barState.gear : ({})

  Ui.SettingGroup {
    title: "Bar button"
    note: page.inBar ? "" : "Add OmaControl to the bar to use these."

    Ui.SwitchRow {
      label: "Show active-switch count"
      description: "Counts Night light, Do not disturb and Stay awake on the gear."
      enabled: page.inBar
      checked: page.gear.activeSwitchCount !== false
      onRequested: function(next) { page.app.set("bar-active-switch-count", next ? "true" : "false") }
      changed: page.app.isChanged("bar-active-switch-count")
      onResetRequested: page.app.resetSetting("bar-active-switch-count")
    }

    Ui.SwitchRow {
      label: "Show network warning"
      description: "Marks the gear when there is no network at all. A click then opens Network."
      enabled: page.inBar
      checked: page.gear.networkWarning !== false
      onRequested: function(next) { page.app.set("bar-network-warning", next ? "true" : "false") }
      changed: page.app.isChanged("bar-network-warning")
      onResetRequested: page.app.resetSetting("bar-network-warning")
    }

    Ui.SwitchRow {
      label: "Show battery warnings"
      description: "Marks the gear when the laptop or a Bluetooth device is at 10 % or under. A click then opens Power or Bluetooth."
      enabled: page.inBar
      checked: page.gear.batteryWarnings !== false
      onRequested: function(next) { page.app.set("bar-battery-warnings", next ? "true" : "false") }
      changed: page.app.isChanged("bar-battery-warnings")
      onResetRequested: page.app.resetSetting("bar-battery-warnings")
    }
  }
}
