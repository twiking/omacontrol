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
    title: strings.t("nvimsection.title.1", "The gutter")

    Ui.SwitchRow {
      label: strings.t("nvimsection.label.1", "Line numbers")
      checked: page.app.nvimValue("number", true) === true
      onRequested: function(next) { page.app.setNvim("number", next ? "true" : "false") }
      changed: page.app.isChanged("nvim:number")
      onResetRequested: page.app.resetSetting("nvim:number")
    }

    Ui.SwitchRow {
      label: strings.t("nvimsection.label.2", "Relative line numbers")
      checked: page.app.nvimValue("relativenumber", true) === true
      onRequested: function(next) { page.app.setNvim("relativenumber", next ? "true" : "false") }
      changed: page.app.isChanged("nvim:relativenumber")
      onResetRequested: page.app.resetSetting("nvim:relativenumber")
    }

    Ui.PickerRow {
      label: strings.t("nvimsection.label.3", "Sign column")
      description: strings.t("nvimsection.description.1", "Where git marks and diagnostics appear.")
      value: String(page.app.nvimValue("signcolumn", "yes"))
      options: [
        { value: "yes", label: strings.t("nvimsection.label.13", "Always")},
        { value: "auto", label: strings.t("nvimsection.label.14", "Only when needed")},
        { value: "no", label: strings.t("nvimsection.label.15", "Never")}
      ]
      onPicked: function(next) { page.app.setNvim("signcolumn", next) }
      changed: page.app.isChanged("nvim:signcolumn")
      onResetRequested: page.app.resetSetting("nvim:signcolumn")
    }
  }

  Ui.SettingGroup {
    title: strings.t("nvimsection.title.2", "The text")

    Ui.SwitchRow {
      label: strings.t("nvimsection.label.4", "Wrap long lines")
      checked: page.app.nvimValue("wrap", false) === true
      onRequested: function(next) { page.app.setNvim("wrap", next ? "true" : "false") }
      changed: page.app.isChanged("nvim:wrap")
      onResetRequested: page.app.resetSetting("nvim:wrap")
    }

    Ui.SwitchRow {
      label: strings.t("nvimsection.label.5", "Highlight the current line")
      checked: page.app.nvimValue("cursorline", true) === true
      onRequested: function(next) { page.app.setNvim("cursorline", next ? "true" : "false") }
      changed: page.app.isChanged("nvim:cursorline")
      onResetRequested: page.app.resetSetting("nvim:cursorline")
    }

    Ui.TextRow {
      label: strings.t("nvimsection.label.6", "Column guide")
      description: strings.t("nvimsection.description.2", "A column number, or empty for none.")
      placeholder: "100"
      value: String(page.app.nvimValue("colorcolumn", ""))
      onCommitted: function(next) { page.app.setNvim("colorcolumn", next) }
      changed: page.app.isChanged("nvim:colorcolumn")
      onResetRequested: page.app.resetSetting("nvim:colorcolumn")
    }

    Ui.NumberRow {
      label: strings.t("nvimsection.label.7", "Keep visible above and below")
      suffix: "lines"
      value: Number(page.app.nvimValue("scrolloff", 4))
      from: 0
      to: 20
      onCommitted: function(next) { page.app.setNvim("scrolloff", next) }
      changed: page.app.isChanged("nvim:scrolloff")
      onResetRequested: page.app.resetSetting("nvim:scrolloff")
    }

    Ui.SwitchRow {
      label: strings.t("nvimsection.label.8", "Spell checking")
      checked: page.app.nvimValue("spell", false) === true
      onRequested: function(next) { page.app.setNvim("spell", next ? "true" : "false") }
      changed: page.app.isChanged("nvim:spell")
      onResetRequested: page.app.resetSetting("nvim:spell")
    }
  }

  Ui.SettingGroup {
    title: strings.t("nvimsection.title.3", "Indentation")

    Ui.SwitchRow {
      label: strings.t("nvimsection.label.9", "Spaces instead of tabs")
      checked: page.app.nvimValue("expandtab", true) === true
      onRequested: function(next) { page.app.setNvim("expandtab", next ? "true" : "false") }
      changed: page.app.isChanged("nvim:expandtab")
      onResetRequested: page.app.resetSetting("nvim:expandtab")
    }

    Ui.NumberRow {
      label: strings.t("nvimsection.label.10", "Indent width")
      suffix: "spaces"
      value: Number(page.app.nvimValue("shiftwidth", 2))
      from: 1
      to: 8
      onCommitted: function(next) { page.app.setNvim("shiftwidth", next) }
      changed: page.app.isChanged("nvim:shiftwidth")
      onResetRequested: page.app.resetSetting("nvim:shiftwidth")
    }

    Ui.NumberRow {
      label: strings.t("nvimsection.label.11", "Tab width")
      suffix: "spaces"
      value: Number(page.app.nvimValue("tabstop", 2))
      from: 1
      to: 8
      onCommitted: function(next) { page.app.setNvim("tabstop", next) }
      changed: page.app.isChanged("nvim:tabstop")
      onResetRequested: page.app.resetSetting("nvim:tabstop")
    }
  }

  Ui.SettingGroup {
    title: strings.t("nvimsection.title.4", "Beyond these settings")
    note: strings.t("nvimsection.note.1", "Changes here apply the next time Neovim starts.")

    Ui.ActionRow {
      label: strings.t("nvimsection.label.12", "The rest of the config")
      description: strings.t("nvimsection.description.3", "Open options.lua for anything this page does not cover.")
      buttonText: strings.t("nvimsection.buttonText.1", "Edit…")
      onTriggered: page.app.editConfig("$HOME/.config/nvim/lua/config/options.lua")
    }
  }
}
