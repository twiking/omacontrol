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

  readonly property var language: app.state.language !== undefined ? app.state.language : ({})
  readonly property var languages: language.languages !== undefined ? language.languages : []
  // A language file missing or unreadable is a machine on English, the same
  // answer omarchy-language prints for one.
  readonly property string current: language.current !== undefined ? String(language.current) : "en"

  Ui.CalloutCard {
    width: parent.width
    label: strings.t("languagesection.label.1", "Session language")
    detail: strings.t("languagesection.description.1", "The language of Omarchy and of this window. Switching generates the locale, writes the session's LANG and restarts the shell; apps already open keep theirs until they restart.")
  }

  // The list is what omarchy-language itself accepts, so a language the
  // registry dropped never appears again. One pick in itself: the shell
  // restart the switch asks for closes this window, so there is no pending
  // mark to hold.
  Ui.SettingGroup {
    visible: !searchEmpty

    Repeater {
      model: page.languages

      delegate: Ui.PickableRow {
        required property var modelData
        width: parent.width
        label: String(modelData.name)
        // The English name beside the native one: a reader after 日本語 who
        // cannot read "日本語" needs the word they already have.
        detail: String(modelData.englishName)
        selected: String(modelData.code) === page.current
        onPicked: page.app.run(["language", "set", String(modelData.code)])
      }
    }
  }
}
