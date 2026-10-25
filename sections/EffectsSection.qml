import QtQuick
import qs.Commons
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// The three things Hyprland draws around and behind windows. Each has a master
// switch, and the settings under it stay visible but inert while it is off —
// they are what the switch turns on, so hiding them would hide the point.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property bool blurOn: app.hyprValue("blur", false) === true
  readonly property bool shadowOn: app.hyprValue("shadow", false) === true
  readonly property bool glowOn: app.hyprValue("glow", false) === true

  Ui.SettingGroup {
    title: strings.t("effectssection.title.1", "Blur")
    note: strings.t("effectssection.note.1", "Blurs whatever is behind translucent windows and layers. Costs GPU.")

    // "Enabled", not the effect's own name: the heading above has already
    // said which effect this is, and a row repeating it read as a second,
    // different Blur.
    Ui.SwitchRow {
      label: strings.t("effectssection.label.1", "Enabled")
      checked: page.blurOn
      onRequested: function(next) { page.app.setHypr("blur", next ? "true" : "false") }
      changed: page.app.isChanged("blur")
      onResetRequested: page.app.resetSetting("blur")
    }

    Ui.NumberRow {
      label: strings.t("effectssection.label.2", "Size")
      description: strings.t("effectssection.description.1", "Blur radius.")
      enabled: page.blurOn
      value: page.app.hyprValue("blur-size", 8)
      from: 1
      to: 20
      onCommitted: function(next) { page.app.setHypr("blur-size", next) }
      changed: page.app.isChanged("blur-size")
      onResetRequested: page.app.resetSetting("blur-size")
    }

    Ui.NumberRow {
      label: strings.t("effectssection.label.3", "Passes")
      description: strings.t("effectssection.description.2", "More passes is smoother and slower. 3 is a good ceiling.")
      enabled: page.blurOn
      value: page.app.hyprValue("blur-passes", 1)
      from: 1
      to: 5
      onCommitted: function(next) { page.app.setHypr("blur-passes", next) }
      changed: page.app.isChanged("blur-passes")
      onResetRequested: page.app.resetSetting("blur-passes")
    }

    Ui.FactorRow {
      label: strings.t("effectssection.label.4", "Noise")
      description: strings.t("effectssection.description.3", "Grain mixed into the blur to hide banding.")
      enabled: page.blurOn
      minimum: 0
      maximum: 0.2
      value: page.app.hyprValue("blur-noise", 0.02)
      onCommitted: function(next) { page.app.setHypr("blur-noise", next) }
      changed: page.app.isChanged("blur-noise")
      onResetRequested: page.app.resetSetting("blur-noise")
    }

    Ui.FactorRow {
      label: strings.t("effectssection.label.5", "Contrast")
      enabled: page.blurOn
      minimum: 0
      maximum: 2
      value: page.app.hyprValue("blur-contrast", 1)
      onCommitted: function(next) { page.app.setHypr("blur-contrast", next) }
      changed: page.app.isChanged("blur-contrast")
      onResetRequested: page.app.resetSetting("blur-contrast")
    }

    Ui.FactorRow {
      label: strings.t("effectssection.label.6", "Brightness")
      enabled: page.blurOn
      minimum: 0
      maximum: 2
      value: page.app.hyprValue("blur-brightness", 1)
      onCommitted: function(next) { page.app.setHypr("blur-brightness", next) }
      changed: page.app.isChanged("blur-brightness")
      onResetRequested: page.app.resetSetting("blur-brightness")
    }

    Ui.PercentRow {
      label: strings.t("effectssection.label.7", "Vibrancy")
      description: strings.t("effectssection.description.4", "Saturation boost for the blurred image.")
      enabled: page.blurOn
      value: page.app.hyprValue("blur-vibrancy", 0.17)
      onCommitted: function(next) { page.app.setHypr("blur-vibrancy", next) }
      changed: page.app.isChanged("blur-vibrancy")
      onResetRequested: page.app.resetSetting("blur-vibrancy")
    }

    Ui.PercentRow {
      label: strings.t("effectssection.label.8", "Vibrancy darkness")
      description: strings.t("effectssection.description.5", "How much vibrancy applies to dark areas.")
      enabled: page.blurOn
      value: page.app.hyprValue("blur-vibrancy-darkness", 0)
      onCommitted: function(next) { page.app.setHypr("blur-vibrancy-darkness", next) }
      changed: page.app.isChanged("blur-vibrancy-darkness")
      onResetRequested: page.app.resetSetting("blur-vibrancy-darkness")
    }

    Ui.SwitchRow {
      label: strings.t("effectssection.label.9", "X-ray")
      description: strings.t("effectssection.description.6", "Blurs the wallpaper instead of the windows underneath.")
      enabled: page.blurOn
      checked: page.app.hyprValue("blur-xray", false) === true
      onRequested: function(next) { page.app.setHypr("blur-xray", next ? "true" : "false") }
      changed: page.app.isChanged("blur-xray")
      onResetRequested: page.app.resetSetting("blur-xray")
    }

    Ui.SwitchRow {
      label: strings.t("effectssection.label.10", "Special workspace")
      description: strings.t("effectssection.description.7", "Blurs behind special workspaces.")
      enabled: page.blurOn
      checked: page.app.hyprValue("blur-special", false) === true
      onRequested: function(next) { page.app.setHypr("blur-special", next ? "true" : "false") }
      changed: page.app.isChanged("blur-special")
      onResetRequested: page.app.resetSetting("blur-special")
    }

    Ui.SwitchRow {
      label: strings.t("effectssection.label.11", "Popups")
      description: strings.t("effectssection.description.8", "Blurs behind menus and tooltips.")
      enabled: page.blurOn
      checked: page.app.hyprValue("blur-popups", false) === true
      onRequested: function(next) { page.app.setHypr("blur-popups", next ? "true" : "false") }
      changed: page.app.isChanged("blur-popups")
      onResetRequested: page.app.resetSetting("blur-popups")
    }
  }

  Ui.SettingGroup {
    title: strings.t("effectssection.title.2", "Shadow")
    note: strings.t("effectssection.note.2", "Drop shadow cast by windows.")

    // "Enabled", not the effect's own name: the heading above has already
    // said which effect this is, and a row repeating it read as a second,
    // different Blur.
    Ui.SwitchRow {
      label: strings.t("effectssection.label.12", "Enabled")
      checked: page.shadowOn
      onRequested: function(next) { page.app.setHypr("shadow", next ? "true" : "false") }
      changed: page.app.isChanged("shadow")
      onResetRequested: page.app.resetSetting("shadow")
    }

    Ui.NumberRow {
      label: strings.t("effectssection.label.13", "Range")
      description: strings.t("effectssection.description.9", "How far the shadow reaches.")
      suffix: "px"
      enabled: page.shadowOn
      value: page.app.hyprValue("shadow-range", 4)
      from: 0
      to: 50
      onCommitted: function(next) { page.app.setHypr("shadow-range", next) }
      changed: page.app.isChanged("shadow-range")
      onResetRequested: page.app.resetSetting("shadow-range")
    }

    Ui.NumberRow {
      label: strings.t("effectssection.label.14", "Falloff")
      description: strings.t("effectssection.description.10", "How sharply the shadow fades out.")
      enabled: page.shadowOn
      value: page.app.hyprValue("shadow-render-power", 3)
      from: 1
      to: 4
      onCommitted: function(next) { page.app.setHypr("shadow-render-power", next) }
      changed: page.app.isChanged("shadow-render-power")
      onResetRequested: page.app.resetSetting("shadow-render-power")
    }

    Ui.PercentRow {
      label: strings.t("effectssection.label.15", "Scale")
      description: strings.t("effectssection.description.11", "Size of the shadow relative to the window.")
      enabled: page.shadowOn
      value: page.app.hyprValue("shadow-scale", 1)
      onCommitted: function(next) { page.app.setHypr("shadow-scale", next) }
      changed: page.app.isChanged("shadow-scale")
      onResetRequested: page.app.resetSetting("shadow-scale")
    }

    Ui.SwitchRow {
      label: strings.t("effectssection.label.16", "Sharp")
      description: strings.t("effectssection.description.12", "Hard-edged shadow with no gradient.")
      enabled: page.shadowOn
      checked: page.app.hyprValue("shadow-sharp", false) === true
      onRequested: function(next) { page.app.setHypr("shadow-sharp", next ? "true" : "false") }
      changed: page.app.isChanged("shadow-sharp")
      onResetRequested: page.app.resetSetting("shadow-sharp")
    }
  }

  Ui.SettingGroup {
    title: strings.t("effectssection.title.3", "Glow")
    note: strings.t("effectssection.note.3", "Halo around the focused window. Its colour is a separate Hyprland option this page leaves alone.")

    // "Enabled", not the effect's own name: the heading above has already
    // said which effect this is, and a row repeating it read as a second,
    // different Blur.
    Ui.SwitchRow {
      label: strings.t("effectssection.label.17", "Enabled")
      checked: page.glowOn
      onRequested: function(next) { page.app.setHypr("glow", next ? "true" : "false") }
      changed: page.app.isChanged("glow")
      onResetRequested: page.app.resetSetting("glow")
    }

    Ui.NumberRow {
      label: strings.t("effectssection.label.18", "Range")
      description: strings.t("effectssection.description.13", "How far the glow reaches.")
      suffix: "px"
      enabled: page.glowOn
      value: page.app.hyprValue("glow-range", 10)
      from: 0
      to: 50
      onCommitted: function(next) { page.app.setHypr("glow-range", next) }
      changed: page.app.isChanged("glow-range")
      onResetRequested: page.app.resetSetting("glow-range")
    }

    Ui.NumberRow {
      label: strings.t("effectssection.label.19", "Falloff")
      description: strings.t("effectssection.description.14", "How sharply the glow fades out.")
      enabled: page.glowOn
      value: page.app.hyprValue("glow-render-power", 3)
      from: 1
      to: 4
      onCommitted: function(next) { page.app.setHypr("glow-render-power", next) }
      changed: page.app.isChanged("glow-render-power")
      onResetRequested: page.app.resetSetting("glow-render-power")
    }
  }
}
