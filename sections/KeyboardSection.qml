pragma ComponentBehavior: Bound
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
    title: strings.t("keyboardsection.title.1", "Layout")
    note: strings.t("keyboardsection.note.1", "Add several layouts separated by commas, then set a shortcut to switch under Options.")

    Ui.TextRow {
      label: strings.t("keyboardsection.label.1", "Layouts")
      placeholder: "us,se"
      value: String(page.app.hyprValue("kb-layout", ""))
      onCommitted: function(next) { page.app.setHypr("kb-layout", next) }
      changed: page.app.isChanged("kb-layout")
      onResetRequested: page.app.resetSetting("kb-layout")
    }

    Ui.TextRow {
      label: strings.t("keyboardsection.label.2", "Variant")
      placeholder: "intl"
      value: String(page.app.hyprValue("kb-variant", ""))
      onCommitted: function(next) { page.app.setHypr("kb-variant", next) }
      changed: page.app.isChanged("kb-variant")
      onResetRequested: page.app.resetSetting("kb-variant")
    }

    Ui.TextRow {
      label: strings.t("keyboardsection.label.3", "Options")
      placeholder: "compose:caps,grp:alts_toggle"
      value: String(page.app.hyprValue("kb-options", ""))
      onCommitted: function(next) { page.app.setHypr("kb-options", next) }
      changed: page.app.isChanged("kb-options")
      onResetRequested: page.app.resetSetting("kb-options")
    }
  }

  Ui.SettingGroup {
    title: strings.t("keyboardsection.title.2", "Repeat")

    Ui.NumberRow {
      label: strings.t("keyboardsection.label.4", "Repeat rate")
      suffix: "keys/s"
      value: page.app.hyprValue("repeat-rate", 25)
      from: 1
      to: 100
      onCommitted: function(next) { page.app.setHypr("repeat-rate", next) }
      changed: page.app.isChanged("repeat-rate")
      onResetRequested: page.app.resetSetting("repeat-rate")
    }

    Ui.NumberRow {
      label: strings.t("keyboardsection.label.5", "Repeat delay")
      suffix: "ms"
      value: page.app.hyprValue("repeat-delay", 600)
      from: 100
      to: 1000
      step: 50
      onCommitted: function(next) { page.app.setHypr("repeat-delay", next) }
      changed: page.app.isChanged("repeat-delay")
      onResetRequested: page.app.resetSetting("repeat-delay")
    }

    Ui.SwitchRow {
      label: strings.t("keyboardsection.label.6", "Num lock on at login")
      checked: page.app.hyprValue("numlock", false) === true
      onRequested: function(next) { page.app.setHypr("numlock", next ? "true" : "false") }
      changed: page.app.isChanged("numlock")
      onResetRequested: page.app.resetSetting("numlock")
    }
  }

  // One group per keyboard, for the ones that should not follow the settings
  // above — an external board on a different layout, say.

  // A device is only worth a group of its own once it departs from the
  // settings above. The rest are one dropdown away, so a page with five
  // devices and no overrides stays a page about keyboards, not a list of
  // hardware.
  property var opened: []

  function isCustomised(device) {
    return Object.keys(device.settings || ({})).length > 0
      || Object.keys(device.configured || ({})).length > 0
      || opened.indexOf(String(device.name)) !== -1
  }

  readonly property var allDevices: app.devices.keyboards !== undefined ? app.devices.keyboards : []
  readonly property var customised: allDevices.filter(isCustomised)
  readonly property var untouched: allDevices.filter(function(device) { return !isCustomised(device) })

  function openDevice(name) {
    var next = opened.slice()
    next.push(String(name))
    opened = next
  }

  // Closing a group that was only opened to look at it: nothing was written,
  // so nothing has to be removed.
  function closeDevice(name) {
    opened = opened.filter(function(entry) { return entry !== String(name) })
  }

  Repeater {
    model: page.customised

    delegate: Ui.SettingGroup {
      id: deviceGroup
      required property var modelData

      readonly property string name: String(modelData.name)
      readonly property var settings: modelData.settings || ({})
      readonly property var configured: modelData.configured || ({})
      readonly property bool ours: Object.keys(settings).length > 0

      // Not called `value`: inside a row, that name resolves to the row's own
      // value property rather than to this.
      function inForce(key, fallback) {
        if (settings[key] !== undefined && settings[key] !== null) return settings[key]
        if (configured[key] !== undefined && configured[key] !== null) return configured[key]
        return fallback
      }

      width: parent.width
      // Named as a device so the heading cannot be mistaken for another
      // group of settings.
      title: strings.t("keyboardsection.deviceTitle", "Device: %1").arg(name)
        + (modelData.connected === false
           ? strings.t("devices.notConnected", " (not connected)") : "")
      note: Object.keys(configured).length > 0 && !ours
        ? strings.t("keyboardsection.setInHyprland", "Set in your own Hyprland config.")
        : ""

      Ui.TextRow {
        label: strings.t("keyboardsection.label.7", "Layouts")
        placeholder: String(page.app.hyprValue("kb-layout", ""))
        value: String(deviceGroup.inForce("kb_layout", page.app.hyprValue("kb-layout", "")))
        onCommitted: function(next) { page.app.setDevice(deviceGroup.name, "kb_layout", next, "keyboard") }
        changed: page.app.isChanged("kb-layout")
        onResetRequested: page.app.resetSetting("kb-layout")
      }

      Ui.TextRow {
        label: strings.t("keyboardsection.label.8", "Variant")
        value: String(deviceGroup.inForce("kb_variant", page.app.hyprValue("kb-variant", "")))
        onCommitted: function(next) { page.app.setDevice(deviceGroup.name, "kb_variant", next, "keyboard") }
        changed: page.app.isChanged("kb-variant")
        onResetRequested: page.app.resetSetting("kb-variant")
      }

      Ui.TextRow {
        label: strings.t("keyboardsection.label.9", "Options")
        value: String(deviceGroup.inForce("kb_options", page.app.hyprValue("kb-options", "")))
        onCommitted: function(next) { page.app.setDevice(deviceGroup.name, "kb_options", next, "keyboard") }
        changed: page.app.isChanged("kb-options")
        onResetRequested: page.app.resetSetting("kb-options")
      }

      Ui.NumberRow {
        label: strings.t("keyboardsection.label.10", "Repeat rate")
        suffix: "keys/s"
        from: 1
        to: 100
        value: Number(deviceGroup.inForce("repeat_rate", page.app.hyprValue("repeat-rate", 25)))
        onCommitted: function(next) { page.app.setDevice(deviceGroup.name, "repeat_rate", next, "keyboard") }
        changed: page.app.isChanged("repeat-rate")
        onResetRequested: page.app.resetSetting("repeat-rate")
      }

      Ui.NumberRow {
        label: strings.t("keyboardsection.label.11", "Repeat delay")
        suffix: "ms"
        from: 100
        to: 1000
        step: 50
        value: Number(deviceGroup.inForce("repeat_delay", page.app.hyprValue("repeat-delay", 600)))
        onCommitted: function(next) { page.app.setDevice(deviceGroup.name, "repeat_delay", next, "keyboard") }
        changed: page.app.isChanged("repeat-delay")
        onResetRequested: page.app.resetSetting("repeat-delay")
      }

      // No label: what the button removes is the group it sits in, and how
      // that is undone in a config file is not the reader's problem.
      Ui.ActionRow {
        readonly property bool theirs: Object.keys(deviceGroup.configured).length > 0

        buttonText: strings.t("keyboardsection.buttonText.1", "Remove Device")
        onTriggered: {
          if (theirs) page.app.removeDevice(deviceGroup.name)
          else if (deviceGroup.ours) page.app.clearDevice(deviceGroup.name)
          else page.closeDevice(deviceGroup.name)
        }
      }
    }
  }

  Ui.SettingGroup {
    visible: !searchEmpty && page.untouched.length > 0

    Ui.PickerRow {
      label: strings.t("keyboardsection.label.12", "Settings for one keyboard")
      description: strings.t("keyboardsection.description.1", "Give a single keyboard its own settings, apart from the ones above.")
      value: ""
      options: [{ value: "", label: strings.t("keyboardsection.label.13", "Pick a keyboard…")}].concat(page.untouched.map(function(device) {
        return {
          value: String(device.name),
          label: String(device.name)
            + (device.connected === false ? strings.t("devices.notConnected", " (not connected)") : "")
        }
      }))
      onPicked: function(next) { if (next !== "") page.openDevice(next) }
    }
  }
}
