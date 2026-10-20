import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
Ui.SectionBody {
  property var app: null

  // Read when the page opens: an unlock screen changes when somebody changes
  // it, so there is nothing here for a timer to watch.
  Component.onCompleted: app.readUnlocks()

  // The unlock screen is a look, so it is chosen by looking — the same
  // pictures the Theme page uses, and the same ones Omarchy's own switcher
  // shows. Setting one needs root and a new initramfs, so the click opens a
  // terminal with its own password prompt; the ring moves when the list comes
  // back saying it took.
  Ui.SettingGroup {
    title: "Unlock animation"
    note: "Shown while the machine starts up and while it unlocks."
    visible: !searchEmpty && app.unlockList.length > 0

    Ui.PictureGrid {
      items: {
        var out = []
        var list = app.unlockList
        for (var i = 0; i < list.length; i++)
          out.push({ source: list[i].preview, title: list[i].title, value: list[i].name,
                     current: app.unlockPending !== "" ? list[i].name === app.unlockPending
                                                       : list[i].current === true })
        return out
      }
      columns: 2
      onChose: function(name) { app.setUnlock(name) }
    }
  }
}
