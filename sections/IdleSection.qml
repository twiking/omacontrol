import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  // Read when the page opens: an unlock screen changes when somebody changes
  // it, so there is nothing here for a timer to watch.
  Component.onCompleted: app.readUnlocks()
  Ui.SettingGroup {
    title: strings.t("idlesection.title.1", "Timeouts")

    Ui.MinutesRow {
      label: strings.t("idlesection.label.1", "Screensaver after")
      seconds: page.app.idleState.screensaver !== undefined ? Number(page.app.idleState.screensaver) : 150
      onCommitted: function(mins) { page.app.set("idle-screensaver", mins * 60) }
      changed: page.app.isChanged("idle-screensaver")
      onResetRequested: page.app.resetSetting("idle-screensaver")
    }

    Ui.MinutesRow {
      label: strings.t("idlesection.label.2", "Lock after")
      seconds: page.app.idleState.lock !== undefined ? Number(page.app.idleState.lock) : 300
      onCommitted: function(mins) { page.app.set("idle-lock", mins * 60) }
      changed: page.app.isChanged("idle-lock")
      onResetRequested: page.app.resetSetting("idle-lock")
    }
  }

  // The unlock screen is a look, so it is chosen by looking — the same
  // pictures the Theme page uses, and the same ones Omarchy's own switcher
  // shows. Setting one needs root and a new initramfs, so the click opens a
  // terminal with its own password prompt; the ring moves when the list comes
  // back saying it took.
  Ui.SettingGroup {
    title: strings.t("idlesection.title.2", "Unlock animation")
    note: strings.t("idlesection.note.1", "Shown while the machine starts up and while it unlocks.")
    visible: !searchEmpty && page.app.unlockList.length > 0

    Ui.PictureGrid {
      items: {
        var out = []
        var list = page.app.unlockList
        for (var i = 0; i < list.length; i++)
          out.push({ source: list[i].preview, title: list[i].title, value: list[i].name,
                     current: page.app.unlockPending !== "" ? list[i].name === page.app.unlockPending
                                                       : list[i].current === true })
        return out
      }
      columns: 2
      onChose: function(name) { page.app.setUnlock(name) }
    }
  }
}
