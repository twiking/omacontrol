pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import qs.Commons
import "." as Local

// A wall of pictures to choose one from: themes, wallpapers.
//
// A theme is a look, and the one description of a look that helps nobody is
// its name. Twenty-five words in a dropdown made picking a theme a matter of
// remembering which one "Ristretto" was; twenty-five pictures makes it a
// matter of looking.
//
// An item is `{ source:, title:, value:, current: }` — `value` is what the
// caller acts on (a theme's name, a wallpaper's path) and defaults to title. The tiles are a fixed aspect so
// the grid stays a grid whatever the images are — a preview is 16:9 and a
// wallpaper can be anything, and a row of mixed heights reads as a mistake.
Item {
  id: grid
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  property var items: []
  property real tileWidth: Style.space(190)
  property real aspect: 16 / 10
  signal chose(string value)

  width: parent ? parent.width : 0
  implicitHeight: flow.implicitHeight

  // How many fit, unless the caller says how many it wants: a theme preview is
  // a screenshot of a whole desktop, and at four across you are judging a
  // thumbnail of a thumbnail.
  property int columns: Math.max(1, Math.floor((width + spacing) / (tileWidth + spacing)))
  readonly property real spacing: Style.space(12)
  // The last column ends where the card does rather than leaving a ragged
  // strip of air: the tiles take whatever the division left over.
  readonly property real cell: columns > 0
    ? (width - spacing * (columns - 1)) / columns : width

  Flow {
    id: flow
    width: parent.width
    spacing: grid.spacing

    Repeater {
      model: grid.items

      delegate: Item {
        id: tile
        required property var modelData
        width: grid.cell
        implicitHeight: picture.height + caption.implicitHeight + Style.space(6)

        Rectangle {
          id: picture
          width: parent.width
          height: Math.round(width / grid.aspect)
          radius: Local.Palette.cardRadius
          color: Local.Palette.card
          border.width: tile.modelData.current ? Style.space(2) : Style.spacing.hairline
          border.color: tile.modelData.current ? Local.Palette.accent
            : (tileMouse.containsMouse ? Local.Palette.shade(0.30) : Local.Palette.divider)
          clip: true

          // Masked to the card's own radius, not merely clipped to its box.
          // `clip: true` clips to the bounding rectangle and knows nothing
          // about `radius`, so a photograph's square corners sat outside the
          // rounded border — most visible on the selected tile, where the
          // border is thick enough to see past.
          Item {
            id: shape
            anchors.fill: parent
            anchors.margins: tile.modelData.current ? Style.space(2) : Style.spacing.hairline
            layer.enabled: true
            // A layer is a texture, and Qt sizes it in logical pixels — so on
            // a 1.5x screen the mask pass rendered 854 px of picture into 569
            // px of texture and scaled it back up. Sharp decoding upstream
            // cannot survive a soft layer downstream.
            layer.textureSize: Qt.size(Math.round(width * Screen.devicePixelRatio),
                                       Math.round(height * Screen.devicePixelRatio))
            layer.smooth: true
            layer.effect: MultiEffect {
              maskEnabled: true
              maskSource: mask
              maskThresholdMin: 0.5
              maskSpreadAtMin: 1.0
            }

            Image {
              anchors.fill: parent
              source: tile.modelData.source !== "" ? "file://" + tile.modelData.source : ""
              fillMode: Image.PreserveAspectCrop
              // Decoded at the size it is drawn *in device pixels*, rather
              // than at the size it was saved: twenty-five 4K wallpapers at
              // full resolution is a window that takes a second to open and a
              // lot of memory to keep open.
              //
              // In device pixels because the two are not the same number. This
              // was a fixed multiple of the tile width, so two columns asked
              // for 380 px and drew 854 — every preview upscaled, and a wall
              // of screenshots is where that shows worst.
              sourceSize.width: Math.round(picture.width * Screen.devicePixelRatio)
              asynchronous: true
              cache: true
            }
          }

          // The shape the picture is cut to: the card's radius, less whatever
          // the border occupies, so the mask follows the frame rather than
          // crossing it.
          Item {
            id: mask
            anchors.fill: shape
            layer.enabled: true
            // The mask is sampled against the layer above, so it is rendered
            // at the same resolution: a 1x mask on a 2x texture softens every
            // edge it cuts.
            layer.textureSize: Qt.size(Math.round(width * Screen.devicePixelRatio),
                                       Math.round(height * Screen.devicePixelRatio))
            layer.smooth: true
            visible: false

            Rectangle {
              anchors.fill: parent
              radius: Local.Palette.cardRadius - Style.space(2)
              color: "black"
            }
          }

          // A theme with no preview and no backgrounds still has to be
          // pickable, so the tile says its name rather than showing a hole.
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: tile.modelData.source === ""
            text: strings.t("picturegrid.text.1", "No preview")
            color: Local.Palette.muted
            font.family: Local.Palette.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: grid.chose(tile.modelData.value !== undefined
              ? tile.modelData.value : tile.modelData.title)
          }
        }

        Text {
          id: caption
          textFormat: Text.PlainText
          anchors.top: picture.bottom
          anchors.topMargin: Style.space(6)
          width: parent.width
          text: tile.modelData.title
          elide: Text.ElideRight
          color: tile.modelData.current ? Local.Palette.accent : Local.Palette.foreground
          font.family: Local.Palette.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: tile.modelData.current
        }
      }
    }
  }
}
