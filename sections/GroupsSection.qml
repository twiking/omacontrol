import QtQuick
import qs.Commons
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// The tab strip drawn on grouped windows. Its colours come from the theme.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property bool barOn: app.hyprValue("groupbar", true) === true

  Ui.SettingGroup {
    title: strings.t("groupssection.title.1", "Group bar")

    Ui.SwitchRow {
      label: strings.t("groupssection.label.1", "Group bar")
      description: strings.t("groupssection.description.1", "Shows the tab strip on grouped windows.")
      checked: page.barOn
      onRequested: function(next) { page.app.setHypr("groupbar", next ? "true" : "false") }
      changed: page.app.isChanged("groupbar")
      onResetRequested: page.app.resetSetting("groupbar")
    }

    Ui.NumberRow {
      label: strings.t("groupssection.label.2", "Height")
      suffix: "px"
      enabled: page.barOn
      value: page.app.hyprValue("groupbar-height", 14)
      from: 0
      to: 40
      onCommitted: function(next) { page.app.setHypr("groupbar-height", next) }
      changed: page.app.isChanged("groupbar-height")
      onResetRequested: page.app.resetSetting("groupbar-height")
    }

    Ui.NumberRow {
      label: strings.t("groupssection.label.3", "Font size")
      suffix: "px"
      enabled: page.barOn
      value: page.app.hyprValue("groupbar-font-size", 8)
      from: 6
      to: 24
      onCommitted: function(next) { page.app.setHypr("groupbar-font-size", next) }
      changed: page.app.isChanged("groupbar-font-size")
      onResetRequested: page.app.resetSetting("groupbar-font-size")
    }

    Ui.SwitchRow {
      label: strings.t("groupssection.label.4", "Show titles")
      description: strings.t("groupssection.description.2", "Draws window titles in the tabs.")
      enabled: page.barOn
      checked: page.app.hyprValue("groupbar-render-titles", true) === true
      onRequested: function(next) { page.app.setHypr("groupbar-render-titles", next ? "true" : "false") }
      changed: page.app.isChanged("groupbar-render-titles")
      onResetRequested: page.app.resetSetting("groupbar-render-titles")
    }

    Ui.NumberRow {
      label: strings.t("groupssection.label.5", "Indicator height")
      description: strings.t("groupssection.description.3", "Thickness of the active-tab indicator.")
      suffix: "px"
      enabled: page.barOn
      value: page.app.hyprValue("groupbar-indicator-height", 3)
      from: 0
      to: 12
      onCommitted: function(next) { page.app.setHypr("groupbar-indicator-height", next) }
      changed: page.app.isChanged("groupbar-indicator-height")
      onResetRequested: page.app.resetSetting("groupbar-indicator-height")
    }

    Ui.NumberRow {
      label: strings.t("groupssection.label.6", "Rounding")
      description: strings.t("groupssection.description.4", "Corner radius of the tabs.")
      suffix: "px"
      enabled: page.barOn
      value: page.app.hyprValue("groupbar-rounding", 1)
      from: 0
      to: 20
      onCommitted: function(next) { page.app.setHypr("groupbar-rounding", next) }
      changed: page.app.isChanged("groupbar-rounding")
      onResetRequested: page.app.resetSetting("groupbar-rounding")
    }

    Ui.SwitchRow {
      label: strings.t("groupssection.label.7", "Gradients")
      description: strings.t("groupssection.description.5", "Fades the tab backgrounds.")
      enabled: page.barOn
      checked: page.app.hyprValue("groupbar-gradients", false) === true
      onRequested: function(next) { page.app.setHypr("groupbar-gradients", next ? "true" : "false") }
      changed: page.app.isChanged("groupbar-gradients")
      onResetRequested: page.app.resetSetting("groupbar-gradients")
    }

    Ui.SwitchRow {
      label: strings.t("groupssection.label.8", "Stacked")
      description: strings.t("groupssection.description.6", "Lays the tabs out vertically.")
      enabled: page.barOn
      checked: page.app.hyprValue("groupbar-stacked", false) === true
      onRequested: function(next) { page.app.setHypr("groupbar-stacked", next ? "true" : "false") }
      changed: page.app.isChanged("groupbar-stacked")
      onResetRequested: page.app.resetSetting("groupbar-stacked")
    }

    Ui.SwitchRow {
      label: strings.t("groupssection.label.9", "Hide when alone")
      description: strings.t("groupssection.description.7", "Hides the strip when the group has one window.")
      enabled: page.barOn
      checked: page.app.hyprValue("groupbar-disable-when-only", false) === true
      onRequested: function(next) { page.app.setHypr("groupbar-disable-when-only", next ? "true" : "false") }
      changed: page.app.isChanged("groupbar-disable-when-only")
      onResetRequested: page.app.resetSetting("groupbar-disable-when-only")
    }
  }
}
