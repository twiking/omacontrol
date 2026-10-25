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
    title: strings.t("datetimesection.title.1", "Clock")

    Ui.ActionRow {
      label: strings.t("datetimesection.label.1", "Timezone")
      description: page.app.datetime.timezone ? String(page.app.datetime.timezone) : strings.t("datetimesection.unknown", "Unknown")
      buttonText: strings.t("datetimesection.buttonText.1", "Change…")
      onTriggered: page.app.run(["menu", "run", "update.timezone"])
    }

    Ui.ActionRow {
      label: strings.t("datetimesection.label.2", "System time")
      description: (page.app.datetime.now ? String(page.app.datetime.now) : "")
        + (page.app.datetime.ntp === true
           ? (page.app.datetime.synchronized === true
              ? strings.t("datetimesection.synced", " · synchronized")
              : strings.t("datetimesection.syncing", " · syncing"))
           : strings.t("datetimesection.syncOff", " · automatic sync off"))
      buttonText: strings.t("datetimesection.buttonText.2", "Resync…")
      onTriggered: page.app.run(["menu", "run", "update.time"])
    }
  }
}
