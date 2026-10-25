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

    Ui.PercentRow {
      label: strings.t("pointersection.label.1", "Sensitivity")
      description: strings.t("pointersection.description.1", "How far the pointer travels for the same hand movement.")
      value: (Number(page.app.hyprValue("sensitivity", 0)) + 1) / 2
      onCommitted: function(next) { page.app.setHypr("sensitivity", (next * 2 - 1).toFixed(2)) }
      changed: page.app.isChanged("sensitivity")
      onResetRequested: page.app.resetSetting("sensitivity")
    }

    Ui.PickerRow {
      label: strings.t("pointersection.label.2", "Acceleration")
      value: String(page.app.hyprValue("accel-profile", ""))
      options: [
        { value: "", label: strings.t("pointersection.label.15", "Default (adaptive)")},
        { value: "flat", label: strings.t("pointersection.label.16", "Flat — no acceleration")},
        { value: "adaptive", label: strings.t("pointersection.label.17", "Adaptive")}
      ]
      onPicked: function(next) { page.app.setHypr("accel-profile", next) }
      changed: page.app.isChanged("accel-profile")
      onResetRequested: page.app.resetSetting("accel-profile")
    }

    Ui.PickerRow {
      label: strings.t("pointersection.label.3", "Focus follows mouse")
      value: String(page.app.hyprValue("follow-mouse", 1))
      options: [
        { value: "0", label: strings.t("pointersection.label.18", "Off — click to focus")},
        { value: "1", label: strings.t("pointersection.label.19", "On")},
        { value: "2", label: strings.t("pointersection.label.20", "On, but keyboard stays")},
        { value: "3", label: strings.t("pointersection.label.21", "On, without raising")}
      ]
      onPicked: function(next) { page.app.setHypr("follow-mouse", next) }
      changed: page.app.isChanged("follow-mouse")
      onResetRequested: page.app.resetSetting("follow-mouse")
    }
  }

  Ui.SettingGroup {
    title: strings.t("pointersection.title.1", "Touchpad")

    Ui.SwitchRow {
      label: strings.t("pointersection.label.4", "Natural scrolling")
      checked: page.app.hyprValue("natural-scroll", false) === true
      onRequested: function(next) { page.app.setHypr("natural-scroll", next ? "true" : "false") }
      changed: page.app.isChanged("natural-scroll")
      onResetRequested: page.app.resetSetting("natural-scroll")
    }

    Ui.SwitchRow {
      label: strings.t("pointersection.label.5", "Tap to click")
      checked: page.app.hyprValue("tap-to-click", true) === true
      onRequested: function(next) { page.app.setHypr("tap-to-click", next ? "true" : "false") }
      changed: page.app.isChanged("tap-to-click")
      onResetRequested: page.app.resetSetting("tap-to-click")
    }

    Ui.SwitchRow {
      label: strings.t("pointersection.label.6", "Two-finger right click")
      description: strings.t("pointersection.description.2", "Off uses the lower-right corner instead.")
      checked: page.app.hyprValue("clickfinger", false) === true
      onRequested: function(next) { page.app.setHypr("clickfinger", next ? "true" : "false") }
      changed: page.app.isChanged("clickfinger")
      onResetRequested: page.app.resetSetting("clickfinger")
    }

    Ui.SwitchRow {
      label: strings.t("pointersection.label.7", "Disable while typing")
      checked: page.app.hyprValue("disable-while-typing", true) === true
      onRequested: function(next) { page.app.setHypr("disable-while-typing", next ? "true" : "false") }
      changed: page.app.isChanged("disable-while-typing")
      onResetRequested: page.app.resetSetting("disable-while-typing")
    }

    Ui.FactorRow {
      label: strings.t("pointersection.label.8", "Scroll speed")
      value: Number(page.app.hyprValue("scroll-factor", 1))
      onCommitted: function(next) { page.app.setHypr("scroll-factor", next) }
      changed: page.app.isChanged("scroll-factor")
      onResetRequested: page.app.resetSetting("scroll-factor")
    }
  }

  // Every pointer that can depart from the settings above gets its own group,
  // so what a control writes is never in doubt: the ones under a device name
  // write that device, the ones above write every device.
  //
  // A device shows the value in force for it — what was set here, else what
  // the user's own config gives it, else the global setting above.

  // A device is only worth a group of its own once it departs from the
  // settings above. The rest are one dropdown away, so a page with five
  // devices and no overrides stays a page about settings, not a list of
  // hardware.
  property var opened: []

  function isCustomised(device) {
    return Object.keys(device.settings || ({})).length > 0
      || Object.keys(device.configured || ({})).length > 0
      || opened.indexOf(String(device.name)) !== -1
  }

  readonly property var allDevices: app.devices.pointers !== undefined ? app.devices.pointers : []
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
      // The page's scroll settings are the touchpad's, and Hyprland applies
      // them to nothing else: a mouse with no setting of its own scrolls by
      // the plain input ones.
      readonly property bool touchpad: modelData.touchpad === true

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
      title: strings.t("pointersection.deviceTitle", "Device: %1").arg(name)
        + (modelData.connected === false ? " " + strings.t("devices.notConnected", " (not connected)") : "")
      note: Object.keys(configured).length > 0 && !ours
        ? strings.t("pointersection.setInHyprland", "Set in your own Hyprland config.")
        : ""

      Ui.PercentRow {
        label: strings.t("pointersection.label.9", "Sensitivity")
        value: (Number(deviceGroup.inForce("sensitivity", page.app.hyprValue("sensitivity", 0))) + 1) / 2
        onCommitted: function(next) { page.app.setDevice(deviceGroup.name, "sensitivity", (next * 2 - 1).toFixed(2), "pointer") }
        changed: page.app.isChanged("device:" + deviceGroup.name + ":sensitivity")
        onResetRequested: page.app.resetSetting("device:" + deviceGroup.name + ":sensitivity")
      }

      Ui.PickerRow {
        label: strings.t("pointersection.label.10", "Acceleration")
        value: String(deviceGroup.inForce("accel_profile", page.app.hyprValue("accel-profile", "")))
        options: [
          { value: "", label: strings.t("pointersection.label.22", "Default (adaptive)")},
          { value: "flat", label: strings.t("pointersection.label.23", "Flat — no acceleration")},
          { value: "adaptive", label: strings.t("pointersection.label.24", "Adaptive")}
        ]
        onPicked: function(next) { page.app.setDevice(deviceGroup.name, "accel_profile", next, "pointer") }
        changed: page.app.isChanged("device:" + deviceGroup.name + ":accel_profile")
        onResetRequested: page.app.resetSetting("device:" + deviceGroup.name + ":accel_profile")
      }

      Ui.SwitchRow {
        label: strings.t("pointersection.label.11", "Natural scrolling")
        checked: deviceGroup.inForce("natural_scroll", page.app.hyprValue(deviceGroup.touchpad ? "natural-scroll" : "mouse-natural-scroll", false)) === true
        onRequested: function(next) { page.app.setDevice(deviceGroup.name, "natural_scroll", next ? "true" : "false", "pointer") }
        changed: page.app.isChanged("device:" + deviceGroup.name + ":natural_scroll")
        onResetRequested: page.app.resetSetting("device:" + deviceGroup.name + ":natural_scroll")
      }

      Ui.SwitchRow {
        label: strings.t("pointersection.label.12", "Left handed")
        checked: deviceGroup.inForce("left_handed", false) === true
        onRequested: function(next) { page.app.setDevice(deviceGroup.name, "left_handed", next ? "true" : "false", "pointer") }
        changed: page.app.isChanged("device:" + deviceGroup.name + ":left_handed")
        onResetRequested: page.app.resetSetting("device:" + deviceGroup.name + ":left_handed")
      }

      Ui.FactorRow {
        label: strings.t("pointersection.label.13", "Scroll speed")
        minimum: 0.1
        maximum: 3
        value: Number(deviceGroup.inForce("scroll_factor", page.app.hyprValue(deviceGroup.touchpad ? "scroll-factor" : "mouse-scroll-factor", 1)))
        onCommitted: function(next) { page.app.setDevice(deviceGroup.name, "scroll_factor", next, "pointer") }
        changed: page.app.isChanged("device:" + deviceGroup.name + ":scroll_factor")
        onResetRequested: page.app.resetSetting("device:" + deviceGroup.name + ":scroll_factor")
      }

      // No label: what the button removes is the group it sits in, and how
      // that is undone in a config file is not the reader's problem.
      Ui.ActionRow {
        readonly property bool theirs: Object.keys(deviceGroup.configured).length > 0

        buttonText: strings.t("pointersection.buttonText.1", "Remove Device")
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
      label: strings.t("pointersection.label.14", "Settings for one device")
      description: strings.t("pointersection.description.3", "Give a single mouse or touchpad its own settings, apart from the ones above.")
      value: ""
      options: [{ value: "", label: strings.t("pointersection.label.25", "Pick a device…")}].concat(page.untouched.map(function(device) {
        return {
          value: String(device.name),
          label: String(device.name) + (device.connected === false ? strings.t("devices.notConnected", " (not connected)") : "")
        }
      }))
      onPicked: function(next) { if (next !== "") page.openDevice(next) }
    }
  }
}
