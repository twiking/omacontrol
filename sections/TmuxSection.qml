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
    title: strings.t("tmuxsection.title.1", "Keys")

    Ui.TextRow {
      label: strings.t("tmuxsection.label.1", "Prefix")
      description: strings.t("tmuxsection.description.1", "tmux spelling: C-Space, C-b, M-a.")
      placeholder: "C-b"
      value: String(page.app.tmuxValue("prefix", "C-b"))
      onCommitted: function(next) { page.app.setTmux("prefix", next) }
      changed: page.app.isChanged("tmux:prefix")
      onResetRequested: page.app.resetSetting("tmux:prefix")
    }

    Ui.PickerRow {
      label: strings.t("tmuxsection.label.2", "Copy mode keys")
      value: String(page.app.tmuxValue("mode-keys", "emacs"))
      options: [
        { value: "vi", label: strings.t("tmuxsection.label.13", "Vi")},
        { value: "emacs", label: strings.t("tmuxsection.label.14", "Emacs")}
      ]
      onPicked: function(next) { page.app.setTmux("mode-keys", next) }
      changed: page.app.isChanged("tmux:mode-keys")
      onResetRequested: page.app.resetSetting("tmux:mode-keys")
    }

    Ui.ActionRow {
      label: strings.t("tmuxsection.label.3", "Every shortcut")
      description: strings.t("tmuxsection.description.2", "The full list, as tmux has it.")
      buttonText: strings.t("tmuxsection.buttonText.1", "Show…")
      onTriggered: page.app.run(["menu", "run", "learn.tmux-keybindings"])
    }
  }

  Ui.SettingGroup {
    title: strings.t("tmuxsection.title.2", "Status bar")

    Ui.PickerRow {
      label: strings.t("tmuxsection.label.4", "Position")
      value: String(page.app.tmuxValue("status-position", "bottom"))
      options: [
        { value: "top", label: strings.t("tmuxsection.label.15", "Top")},
        { value: "bottom", label: strings.t("tmuxsection.label.16", "Bottom")}
      ]
      onPicked: function(next) { page.app.setTmux("status-position", next) }
      changed: page.app.isChanged("tmux:status-position")
      onResetRequested: page.app.resetSetting("tmux:status-position")
    }
  }

  Ui.SettingGroup {
    title: strings.t("tmuxsection.title.3", "Windows and panes")

    Ui.NumberRow {
      label: strings.t("tmuxsection.label.5", "First window number")
      value: Number(page.app.tmuxValue("base-index", 0))
      from: 0
      to: 1
      onCommitted: function(next) { page.app.setTmux("base-index", next) }
      changed: page.app.isChanged("tmux:base-index")
      onResetRequested: page.app.resetSetting("tmux:base-index")
    }

    Ui.NumberRow {
      label: strings.t("tmuxsection.label.6", "First pane number")
      value: Number(page.app.tmuxValue("pane-base-index", 0))
      from: 0
      to: 1
      onCommitted: function(next) { page.app.setTmux("pane-base-index", next) }
      changed: page.app.isChanged("tmux:pane-base-index")
      onResetRequested: page.app.resetSetting("tmux:pane-base-index")
    }

    Ui.SwitchRow {
      label: strings.t("tmuxsection.label.7", "Renumber when one closes")
      checked: page.app.tmuxValue("renumber-windows", false) === true
      onRequested: function(next) { page.app.setTmux("renumber-windows", next ? "true" : "false") }
      changed: page.app.isChanged("tmux:renumber-windows")
      onResetRequested: page.app.resetSetting("tmux:renumber-windows")
    }
  }

  Ui.SettingGroup {
    title: strings.t("tmuxsection.title.4", "Behaviour")

    Ui.SwitchRow {
      label: strings.t("tmuxsection.label.8", "Mouse")
      description: strings.t("tmuxsection.description.3", "Click to focus a pane, drag to resize, scroll to page back.")
      checked: page.app.tmuxValue("mouse", false) === true
      onRequested: function(next) { page.app.setTmux("mouse", next ? "true" : "false") }
      changed: page.app.isChanged("tmux:mouse")
      onResetRequested: page.app.resetSetting("tmux:mouse")
    }

    Ui.NumberRow {
      label: strings.t("tmuxsection.label.9", "Scrollback")
      suffix: "lines"
      value: Number(page.app.tmuxValue("history-limit", 2000))
      from: 1000
      to: 100000
      step: 1000
      onCommitted: function(next) { page.app.setTmux("history-limit", next) }
      changed: page.app.isChanged("tmux:history-limit")
      onResetRequested: page.app.resetSetting("tmux:history-limit")
    }

    Ui.NumberRow {
      label: strings.t("tmuxsection.label.10", "Escape delay")
      suffix: "ms"
      description: strings.t("tmuxsection.description.4", "Low values keep Esc snappy in Vim; zero can break some terminals.")
      value: Number(page.app.tmuxValue("escape-time", 500))
      from: 0
      to: 500
      step: 10
      onCommitted: function(next) { page.app.setTmux("escape-time", next) }
      changed: page.app.isChanged("tmux:escape-time")
      onResetRequested: page.app.resetSetting("tmux:escape-time")
    }

    Ui.PickerRow {
      label: strings.t("tmuxsection.label.11", "Clipboard")
      description: strings.t("tmuxsection.description.5", "Whether tmux hands copied text to the outer terminal.")
      value: String(page.app.tmuxValue("set-clipboard", "external"))
      options: [
        { value: "on", label: strings.t("tmuxsection.label.17", "On")},
        { value: "external", label: strings.t("tmuxsection.label.18", "External only")},
        { value: "off", label: strings.t("tmuxsection.label.19", "Off")}
      ]
      onPicked: function(next) { page.app.setTmux("set-clipboard", next) }
      changed: page.app.isChanged("tmux:set-clipboard")
      onResetRequested: page.app.resetSetting("tmux:set-clipboard")
    }
  }

  Ui.SettingGroup {
    title: strings.t("tmuxsection.title.5", "Beyond these settings")

    Ui.ActionRow {
      label: strings.t("tmuxsection.label.12", "The rest of the config")
      description: strings.t("tmuxsection.description.6", "Open tmux.conf for bindings, styling, and plugins.")
      buttonText: strings.t("tmuxsection.buttonText.2", "Edit…")
      onTriggered: page.app.editConfig("$HOME/.config/tmux/tmux.conf")
    }
  }
}
