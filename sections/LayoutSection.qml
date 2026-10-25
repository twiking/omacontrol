import QtQuick
import qs.Commons
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// The tiling engine, and the knobs belonging to whichever one is running.
// Showing all three engines' settings at once would mostly show settings that
// do nothing, so each group appears only when its engine is the active one.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property string engine: String(app.hyprValue("layout", "dwindle"))

  Ui.SettingGroup {
    title: strings.t("layoutsection.title.1", "Engine")

    Ui.ChoiceRow {
      label: strings.t("layoutsection.label.1", "Layout")
      description: strings.t("layoutsection.description.1", "Scrolling gives you niri-style side-scrolling columns.")
      value: page.engine
      options: [
        { value: "dwindle", label: strings.t("layoutsection.label.12", "Dwindle")},
        { value: "master", label: strings.t("layoutsection.label.13", "Master")},
        { value: "scrolling", label: strings.t("layoutsection.label.14", "Scrolling")}
      ]
      onPicked: function(next) { page.app.setHypr("layout", next) }
      changed: page.app.isChanged("layout")
      onResetRequested: page.app.resetSetting("layout")
    }
  }

  Ui.SettingGroup {
    title: strings.t("layoutsection.title.2", "Dwindle")
    visible: !searchEmpty && page.engine === "dwindle"

    Ui.SwitchRow {
      label: strings.t("layoutsection.label.2", "Preserve split")
      description: strings.t("layoutsection.description.2", "Keeps the split direction when a window closes.")
      checked: page.app.hyprValue("dwindle-preserve-split", true) === true
      onRequested: function(next) { page.app.setHypr("dwindle-preserve-split", next ? "true" : "false") }
      changed: page.app.isChanged("dwindle-preserve-split")
      onResetRequested: page.app.resetSetting("dwindle-preserve-split")
    }

    Ui.SwitchRow {
      label: strings.t("layoutsection.label.3", "Smart split")
      description: strings.t("layoutsection.description.3", "Picks the split direction from where in the window you drop.")
      checked: page.app.hyprValue("dwindle-smart-split", false) === true
      onRequested: function(next) { page.app.setHypr("dwindle-smart-split", next ? "true" : "false") }
      changed: page.app.isChanged("dwindle-smart-split")
      onResetRequested: page.app.resetSetting("dwindle-smart-split")
    }

    Ui.ChoiceRow {
      label: strings.t("layoutsection.label.4", "Split side")
      description: strings.t("layoutsection.description.4", "Where a new window lands.")
      value: String(page.app.hyprValue("dwindle-force-split", 0))
      options: [
        { value: "0", label: strings.t("layoutsection.label.15", "Cursor")},
        { value: "1", label: strings.t("layoutsection.label.16", "Before")},
        { value: "2", label: strings.t("layoutsection.label.17", "After")}
      ]
      onPicked: function(next) { page.app.setHypr("dwindle-force-split", next) }
      changed: page.app.isChanged("dwindle-force-split")
      onResetRequested: page.app.resetSetting("dwindle-force-split")
    }

    Ui.FactorRow {
      label: strings.t("layoutsection.label.5", "Split bias")
      description: strings.t("layoutsection.description.5", "Above 1.0 favours splitting side by side.")
      minimum: 0.5
      maximum: 2
      value: page.app.hyprValue("dwindle-split-width-multiplier", 1)
      onCommitted: function(next) { page.app.setHypr("dwindle-split-width-multiplier", next) }
      changed: page.app.isChanged("dwindle-split-width-multiplier")
      onResetRequested: page.app.resetSetting("dwindle-split-width-multiplier")
    }

    Ui.FactorRow {
      label: strings.t("layoutsection.label.6", "Split ratio")
      description: strings.t("layoutsection.description.6", "Size of a new split relative to its sibling.")
      minimum: 0.5
      maximum: 1.5
      value: page.app.hyprValue("dwindle-default-split-ratio", 1)
      onCommitted: function(next) { page.app.setHypr("dwindle-default-split-ratio", next) }
      changed: page.app.isChanged("dwindle-default-split-ratio")
      onResetRequested: page.app.resetSetting("dwindle-default-split-ratio")
    }
  }

  Ui.SettingGroup {
    title: strings.t("layoutsection.title.3", "Master")
    visible: !searchEmpty && page.engine === "master"

    Ui.PercentRow {
      label: strings.t("layoutsection.label.7", "Master size")
      description: strings.t("layoutsection.description.7", "Fraction of the screen the master window takes.")
      value: page.app.hyprValue("master-mfact", 0.55)
      onCommitted: function(next) { page.app.setHypr("master-mfact", next) }
      changed: page.app.isChanged("master-mfact")
      onResetRequested: page.app.resetSetting("master-mfact")
    }

    Ui.ChoiceRow {
      label: strings.t("layoutsection.label.8", "Master side")
      description: strings.t("layoutsection.description.8", "Which edge the master window occupies.")
      value: String(page.app.hyprValue("master-orientation", "left"))
      options: [
        { value: "left", label: strings.t("layoutsection.label.18", "Left")},
        { value: "right", label: strings.t("layoutsection.label.19", "Right")},
        { value: "top", label: strings.t("layoutsection.label.20", "Top")},
        { value: "bottom", label: strings.t("layoutsection.label.21", "Bottom")},
        { value: "center", label: strings.t("layoutsection.label.22", "Center")}
      ]
      onPicked: function(next) { page.app.setHypr("master-orientation", next) }
      changed: page.app.isChanged("master-orientation")
      onResetRequested: page.app.resetSetting("master-orientation")
    }

    Ui.ChoiceRow {
      label: strings.t("layoutsection.label.9", "New windows")
      description: strings.t("layoutsection.description.9", "Where a newly opened window goes.")
      value: String(page.app.hyprValue("master-new-status", "master"))
      options: [
        { value: "master", label: strings.t("layoutsection.label.23", "Master")},
        { value: "slave", label: strings.t("layoutsection.label.24", "Slave")},
        { value: "inherit", label: strings.t("layoutsection.label.25", "Inherit")}
      ]
      onPicked: function(next) { page.app.setHypr("master-new-status", next) }
      changed: page.app.isChanged("master-new-status")
      onResetRequested: page.app.resetSetting("master-new-status")
    }
  }

  Ui.SettingGroup {
    title: strings.t("layoutsection.title.4", "Scrolling")
    visible: !searchEmpty && page.engine === "scrolling"

    Ui.PercentRow {
      label: strings.t("layoutsection.label.10", "Column width")
      description: strings.t("layoutsection.description.10", "Fraction of the screen one column takes. 97% shows one at a time.")
      value: page.app.hyprValue("scrolling-column-width", 0.5)
      onCommitted: function(next) { page.app.setHypr("scrolling-column-width", next) }
      changed: page.app.isChanged("scrolling-column-width")
      onResetRequested: page.app.resetSetting("scrolling-column-width")
    }

    Ui.SwitchRow {
      label: strings.t("layoutsection.label.11", "Fill on one column")
      description: strings.t("layoutsection.description.11", "Lets a lone column use the whole screen.")
      checked: page.app.hyprValue("scrolling-fullscreen-on-one-column", false) === true
      onRequested: function(next) { page.app.setHypr("scrolling-fullscreen-on-one-column", next ? "true" : "false") }
      changed: page.app.isChanged("scrolling-fullscreen-on-one-column")
      onResetRequested: page.app.resetSetting("scrolling-fullscreen-on-one-column")
    }
  }
}
