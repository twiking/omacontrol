import QtQuick
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  Component.onCompleted: app.readWallpapers()

  Ui.SettingGroup {
    // The wallpapers of the theme in force, plus any you dropped into
    // ~/.config/omarchy/backgrounds for it — the two places Omarchy's own
    // "next background" walks, in its order.
    title: ""
    note: page.app.wallpaperList.length === 0
      ? strings.t("wallpapersection.noBackgrounds", "This theme ships no backgrounds.") : ""

    Ui.PictureGrid {
      items: page.wallpaperTiles
      // Two, as the themes are: a wallpaper is judged on what it looks like,
      // and four across is a thumbnail of a thumbnail.
      columns: 2
      aspect: 16 / 9
      onChose: function(path) { page.app.run(["theme", "bg", path]) }
    }
  }

  readonly property var wallpaperTiles: {
    var out = []
    var list = app.wallpaperList
    for (var i = 0; i < list.length; i++)
      out.push({ source: list[i].path, title: list[i].title,
                 value: list[i].path, current: list[i].current === true })
    return out
  }
}
