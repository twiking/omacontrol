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
    title: strings.t("herdrsection.title.1", "Appearance")

    Ui.PickerRow {
      label: strings.t("herdrsection.label.1", "Theme")
      value: String(page.app.herdrValue("theme.name", "catppuccin"))
      options: [
        { value: "terminal", label: strings.t("herdrsection.label.26", "Terminal palette")},
        { value: "catppuccin", label: strings.t("herdrsection.label.27", "Catppuccin")},
        { value: "tokyo-night", label: strings.t("herdrsection.label.28", "Tokyo Night")},
        { value: "dracula", label: strings.t("herdrsection.label.29", "Dracula")},
        { value: "nord", label: strings.t("herdrsection.label.30", "Nord")},
        { value: "gruvbox", label: strings.t("herdrsection.label.31", "Gruvbox")},
        { value: "one-dark", label: strings.t("herdrsection.label.32", "One Dark")},
        { value: "solarized", label: strings.t("herdrsection.label.33", "Solarized")},
        { value: "kanagawa", label: strings.t("herdrsection.label.34", "Kanagawa")},
        { value: "rose-pine", label: strings.t("herdrsection.label.35", "Rosé Pine")},
        { value: "vesper", label: strings.t("herdrsection.label.36", "Vesper")}
      ]
      onPicked: function(next) { page.app.setHerdr("theme.name", next) }
      changed: page.app.isChanged("herdr:theme.name")
      onResetRequested: page.app.resetSetting("herdr:theme.name")
    }

    Ui.TextRow {
      label: strings.t("herdrsection.label.2", "Accent")
      description: strings.t("herdrsection.description.1", "A colour name, #rrggbb, or rgb(r,g,b).")
      placeholder: "cyan"
      value: String(page.app.herdrValue("ui.accent", "cyan"))
      onCommitted: function(next) { page.app.setHerdr("ui.accent", next) }
      changed: page.app.isChanged("herdr:ui.accent")
      onResetRequested: page.app.resetSetting("herdr:ui.accent")
    }

    Ui.PickerRow {
      label: strings.t("herdrsection.label.3", "Tab bar")
      value: String(page.app.herdrValue("ui.tab_bar_position", "top"))
      options: [
        { value: "top", label: strings.t("herdrsection.label.37", "Top")},
        { value: "bottom", label: strings.t("herdrsection.label.38", "Bottom")}
      ]
      onPicked: function(next) { page.app.setHerdr("ui.tab_bar_position", next) }
      changed: page.app.isChanged("herdr:ui.tab_bar_position")
      onResetRequested: page.app.resetSetting("herdr:ui.tab_bar_position")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.4", "Hide the tab bar with one tab")
      checked: page.app.herdrValue("ui.hide_tab_bar_when_single_tab", false) === true
      onRequested: function(next) { page.app.setHerdr("ui.hide_tab_bar_when_single_tab", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.hide_tab_bar_when_single_tab")
      onResetRequested: page.app.resetSetting("herdr:ui.hide_tab_bar_when_single_tab")
    }
  }

  Ui.SettingGroup {
    title: strings.t("herdrsection.title.2", "Panes")

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.5", "Borders")
      checked: page.app.herdrValue("ui.pane_borders", true) === true
      onRequested: function(next) { page.app.setHerdr("ui.pane_borders", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.pane_borders")
      onResetRequested: page.app.resetSetting("herdr:ui.pane_borders")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.6", "Outer border")
      description: strings.t("herdrsection.description.2", "Off gives tmux-style splitters with no frame around the edge.")
      checked: page.app.herdrValue("ui.pane_outer_borders", true) === true
      onRequested: function(next) { page.app.setHerdr("ui.pane_outer_borders", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.pane_outer_borders")
      onResetRequested: page.app.resetSetting("herdr:ui.pane_outer_borders")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.7", "Gaps between panes")
      checked: page.app.herdrValue("ui.pane_gaps", true) === true
      onRequested: function(next) { page.app.setHerdr("ui.pane_gaps", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.pane_gaps")
      onResetRequested: page.app.resetSetting("herdr:ui.pane_gaps")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.8", "Scrollbars")
      checked: page.app.herdrValue("ui.pane_scrollbars", true) === true
      onRequested: function(next) { page.app.setHerdr("ui.pane_scrollbars", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.pane_scrollbars")
      onResetRequested: page.app.resetSetting("herdr:ui.pane_scrollbars")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.9", "Agent labels on borders")
      description: strings.t("herdrsection.description.3", "Shown when a pane has no name of its own.")
      checked: page.app.herdrValue("ui.show_agent_labels_on_pane_borders", false) === true
      onRequested: function(next) { page.app.setHerdr("ui.show_agent_labels_on_pane_borders", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.show_agent_labels_on_pane_borders")
      onResetRequested: page.app.resetSetting("herdr:ui.show_agent_labels_on_pane_borders")
    }
  }

  Ui.SettingGroup {
    title: strings.t("herdrsection.title.3", "Sidebar")

    Ui.NumberRow {
      label: strings.t("herdrsection.label.10", "Width")
      suffix: "columns"
      value: Number(page.app.herdrValue("ui.sidebar_width", 26))
      from: 12
      to: 60
      onCommitted: function(next) { page.app.setHerdr("ui.sidebar_width", next) }
      changed: page.app.isChanged("herdr:ui.sidebar_width")
      onResetRequested: page.app.resetSetting("herdr:ui.sidebar_width")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.11", "Start collapsed")
      description: strings.t("herdrsection.description.4", "Takes effect the next time Herdr launches.")
      checked: page.app.herdrValue("ui.sidebar_start_collapsed", false) === true
      onRequested: function(next) { page.app.setHerdr("ui.sidebar_start_collapsed", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.sidebar_start_collapsed")
      onResetRequested: page.app.resetSetting("herdr:ui.sidebar_start_collapsed")
    }

    Ui.PickerRow {
      label: strings.t("herdrsection.label.12", "When collapsed")
      value: String(page.app.herdrValue("ui.sidebar_collapsed_mode", "compact"))
      options: [
        { value: "compact", label: strings.t("herdrsection.label.39", "Keep the status rail")},
        { value: "hidden", label: strings.t("herdrsection.label.40", "Hide it completely")}
      ]
      onPicked: function(next) { page.app.setHerdr("ui.sidebar_collapsed_mode", next) }
      changed: page.app.isChanged("herdr:ui.sidebar_collapsed_mode")
      onResetRequested: page.app.resetSetting("herdr:ui.sidebar_collapsed_mode")
    }
  }

  Ui.SettingGroup {
    title: strings.t("herdrsection.title.4", "Behaviour")

    Ui.PickerRow {
      label: strings.t("herdrsection.label.13", "New panes open in")
      value: String(page.app.herdrValue("terminal.new_cwd", "follow"))
      options: [
        { value: "follow", label: strings.t("herdrsection.label.41", "The folder you were in")},
        { value: "home", label: strings.t("herdrsection.label.42", "Your home folder")},
        { value: "current", label: strings.t("herdrsection.label.43", "Herdr's own folder")}
      ]
      onPicked: function(next) { page.app.setHerdr("terminal.new_cwd", next) }
      changed: page.app.isChanged("herdr:terminal.new_cwd")
      onResetRequested: page.app.resetSetting("herdr:terminal.new_cwd")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.14", "Capture the mouse")
      description: strings.t("herdrsection.description.5", "Off lets the terminal handle clicks, so links stay clickable.")
      checked: page.app.herdrValue("ui.mouse_capture", true) === true
      onRequested: function(next) { page.app.setHerdr("ui.mouse_capture", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.mouse_capture")
      onResetRequested: page.app.resetSetting("herdr:ui.mouse_capture")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.15", "Copy on selection")
      checked: page.app.herdrValue("ui.copy_on_select", true) === true
      onRequested: function(next) { page.app.setHerdr("ui.copy_on_select", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.copy_on_select")
      onResetRequested: page.app.resetSetting("herdr:ui.copy_on_select")
    }

    Ui.NumberRow {
      label: strings.t("herdrsection.label.16", "Scroll step")
      suffix: "lines"
      value: Number(page.app.herdrValue("ui.mouse_scroll_lines", 3))
      from: 1
      to: 10
      onCommitted: function(next) { page.app.setHerdr("ui.mouse_scroll_lines", next) }
      changed: page.app.isChanged("herdr:ui.mouse_scroll_lines")
      onResetRequested: page.app.resetSetting("herdr:ui.mouse_scroll_lines")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.17", "Confirm before closing")
      checked: page.app.herdrValue("ui.confirm_close", true) === true
      onRequested: function(next) { page.app.setHerdr("ui.confirm_close", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.confirm_close")
      onResetRequested: page.app.resetSetting("herdr:ui.confirm_close")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.18", "Ask for a tab name")
      checked: page.app.herdrValue("ui.prompt_new_tab_name", true) === true
      onRequested: function(next) { page.app.setHerdr("ui.prompt_new_tab_name", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.prompt_new_tab_name")
      onResetRequested: page.app.resetSetting("herdr:ui.prompt_new_tab_name")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.19", "Ask for a workspace name")
      checked: page.app.herdrValue("ui.prompt_new_workspace_name", false) === true
      onRequested: function(next) { page.app.setHerdr("ui.prompt_new_workspace_name", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.prompt_new_workspace_name")
      onResetRequested: page.app.resetSetting("herdr:ui.prompt_new_workspace_name")
    }
  }

  Ui.SettingGroup {
    title: strings.t("herdrsection.title.5", "Notifications")

    Ui.PickerRow {
      label: strings.t("herdrsection.label.20", "Pop-ups")
      value: String(page.app.herdrValue("ui.toast.delivery", "off"))
      options: [
        { value: "off", label: strings.t("herdrsection.label.44", "None")},
        { value: "herdr", label: strings.t("herdrsection.label.45", "Inside Herdr")},
        { value: "terminal", label: strings.t("herdrsection.label.46", "Through the terminal")},
        { value: "system", label: strings.t("herdrsection.label.47", "Desktop notifications")}
      ]
      onPicked: function(next) { page.app.setHerdr("ui.toast.delivery", next) }
      changed: page.app.isChanged("herdr:ui.toast.delivery")
      onResetRequested: page.app.resetSetting("herdr:ui.toast.delivery")
    }

    Ui.SwitchRow {
      label: strings.t("herdrsection.label.21", "Sounds")
      description: strings.t("herdrsection.description.6", "Played when an agent changes state in a background workspace.")
      checked: page.app.herdrValue("ui.sound.enabled", true) === true
      onRequested: function(next) { page.app.setHerdr("ui.sound.enabled", next ? "true" : "false") }
      changed: page.app.isChanged("herdr:ui.sound.enabled")
      onResetRequested: page.app.resetSetting("herdr:ui.sound.enabled")
    }
  }

  Ui.SettingGroup {
    title: strings.t("herdrsection.title.6", "Keys")

    Ui.TextRow {
      label: strings.t("herdrsection.label.22", "Prefix")
      description: strings.t("herdrsection.description.7", "Every prefix+… shortcut starts with this.")
      placeholder: "ctrl+b"
      value: String(page.app.herdrValue("keys.prefix", "ctrl+b"))
      onCommitted: function(next) { page.app.setHerdr("keys.prefix", next) }
      changed: page.app.isChanged("herdr:keys.prefix")
      onResetRequested: page.app.resetSetting("herdr:keys.prefix")
    }

    Ui.ActionRow {
      label: strings.t("herdrsection.label.23", "Every shortcut")
      description: strings.t("herdrsection.description.8", "The full list, as Herdr has it.")
      buttonText: strings.t("herdrsection.buttonText.1", "Show…")
      onTriggered: page.app.run(["menu", "run", "learn.herdr-keybindings"])
    }

    Ui.ActionRow {
      label: strings.t("herdrsection.label.24", "The rest of the config")
      description: strings.t("herdrsection.description.9", "Open config.toml for the settings this page does not cover.")
      buttonText: strings.t("herdrsection.buttonText.2", "Edit…")
      onTriggered: page.app.editConfig("$HOME/.config/herdr/config.toml")
    }
  }

  Ui.SettingGroup {
    title: strings.t("herdrsection.title.7", "Window title")

    Ui.TextRow {
      label: strings.t("herdrsection.label.25", "Title")
      description: strings.t("herdrsection.description.10", "Tokens: {hostname}, {workspace}, {tab}, {pane}, {terminal_title}.")
      placeholder: "{hostname}: {workspace}"
      value: String(page.app.herdrValue("ui.window_title", ""))
      onCommitted: function(next) { page.app.setHerdr("ui.window_title", next) }
      changed: page.app.isChanged("herdr:ui.window_title")
      onResetRequested: page.app.resetSetting("herdr:ui.window_title")
    }
  }
}
