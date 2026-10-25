pragma Singleton

import QtQuick
import qs.Commons
// Named as well: Qt 6.12 gave QtQuick a `Color` value type of its own, and an
// unversioned `import QtQuick` wins a bare `Color` — every colour here came
// back undefined and the window drew black on black.
import qs.Commons as Commons

// One place for the colours and type the window is drawn in.
//
// OmaControl tracks the foundational palette rather than a themable surface of
// its own, so it renders consistently under every theme. The design it follows
// is drawn in a warm palette of its own; what is taken from that drawing is the
// *hierarchy* — which surface sits on which, how far apart two greys are — and
// those are expressed here as alphas over the theme's own foreground, so a
// Catppuccin desktop and a Gruvbox one each get the design in their own colours.
QtObject {
  id: palette

  // Omarchy renamed its theme singleton `ShellColor`, and shells still give
  // it the old name under the same version number. A name a shell lacks
  // reads as undefined, so naming one alone drew black on black under the other.
  readonly property var theme: Commons.ShellColor || Commons.Color

  readonly property color foreground: theme.popups.text
  // Popup surfaces are allowed to be translucent; a window full of text is
  // not, so the same colour is taken at full opacity.
  readonly property color background: Qt.rgba(theme.popups.background.r, theme.popups.background.g, theme.popups.background.b, 1)
  readonly property color accent: theme.accent
  readonly property color urgent: theme.urgent

  // A charge level is red, amber or green in every window that has ever shown
  // one, and a theme supplies only the red. The other two are struck from that
  // red — its saturation and lightness kept, the hue moved — so a muted theme
  // gets a muted green and a loud one gets a loud one, and none of it is a
  // colour typed into a page.
  function statusHue(hue) {
    return Qt.hsla(hue, urgent.hslSaturation, urgent.hslLightness, 1)
  }
  readonly property color bad: urgent
  readonly property color caution: statusHue(0.11)
  readonly property color good: statusHue(0.33)
  // Docker's blue, the same way: a brand's colour is how its mark is
  // recognised, and struck from the theme's red it still sits in the theme.
  readonly property color docker: statusHue(0.57)
  readonly property color muted: shade(0.6)
  readonly property color hairline: shade(0.16)
  readonly property color hover: shade(0.08)
  readonly property color selected: tint(0.18)
  readonly property string fontFamily: Style.font.family

  function shade(alpha) { return Qt.rgba(foreground.r, foreground.g, foreground.b, alpha) }
  function tint(alpha) { return Qt.rgba(accent.r, accent.g, accent.b, alpha) }

  // A surface coloured by what it *says* rather than by what is under it — the
  // amber box over a kernel arriving. Still the theme's own colour: the ambers
  // and greens here are its red with the hue moved, and this only decides how
  // much of one there is.
  function washOf(colour, alpha) { return Qt.rgba(colour.r, colour.g, colour.b, alpha) }

  // ---------------- surfaces ------------------------------------------------
  // Three steps, no more: the window, the rail beside it, and the cards on it.
  // The design draws the sidebar a shade off the window and the cards a shade
  // off again; anything finer than that stops being visible once a theme
  // supplies the colours.
  readonly property color surface: shade(0.04)
  readonly property color card: shade(0.03)
  // Between rows inside a card, where a full hairline would stripe the card.
  readonly property color divider: shade(0.10)

  // The strip of chrome above the window and the keyhint bar below it are the
  // same surface: they frame the window rather than belonging to either column.
  readonly property color chrome: shade(0.07)

  // ---------------- text on accent ------------------------------------------
  // A selected row fills with the accent, so its label can no longer be the
  // window's foreground. Which of the two reads on a given accent depends on
  // the theme, so it is measured rather than assumed.
  readonly property color onAccent: accent.hslLightness > 0.55 ? background : Qt.rgba(1, 1, 1, 0.96)

  // A wash *on top of* an accent fill — the badge behind an icon, the track of
  // a switch. It has to be struck from whatever reads on that accent rather
  // than from white: on a light accent a white wash is invisible, which is how
  // a themed window loses half a control without erroring.
  function onAccentWash(alpha) {
    return Qt.rgba(onAccent.r, onAccent.g, onAccent.b, alpha)
  }

  // ---------------- shape ---------------------------------------------------
  // Every surface follows the theme's rounding, the way Omarchy's own kit
  // does: square on a square theme, round on a round one. Nothing here
  // floors the value a shape needs rounded, despite what it stands for.
  readonly property int cardRadius: Style.cornerRadius
  readonly property int chipRadius: Style.cornerRadius
  readonly property int iconRadius: Style.cornerRadius
  readonly property int pillRadius: Style.cornerRadius

  // ---------------- slice colours -------------------------------------------
  // One bar cut into what is holding a disk, and the key under it.
  //
  // Four different colours, because that is what tells four things apart.
  // Shades of one accent do not: on a theme where the accent and the
  // foreground are the same — this machine's is — they collapse into one
  // grey, and even when they do not, two steps of one ramp are two shades of
  // the same thing.
  //
  // Still not a colour typed into a page. `statusHue` already builds the
  // green and the amber of a charge level out of the theme's own red by
  // keeping its saturation and lightness and moving the hue; these are the
  // same trick with more hues, so a muted theme gets muted slices and a loud
  // one gets loud ones.
  readonly property var sliceHues: [0.58, 0.33, 0.11, 0.80, 0.50, 0.92]

  function sliceColour(step) {
    return statusHue(sliceHues[step % sliceHues.length])
  }
}
