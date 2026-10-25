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

  readonly property var power: app.power
  readonly property var reading: power.battery !== undefined ? power.battery : ({})

  // Power profiles are named for machines, not people. The icons are the
  // bar's own, from its power widget: the same three glyphs for the same
  // three profiles, since the bar is where most people meet them and two
  // pictures for one profile is one too many.
  function profileOptions() {
    var labels = { "power-saver": strings.t("powersection.profilePowerSaver", "Power saver"),
                   "balanced": strings.t("powersection.profileBalanced", "Balanced"),
                   "performance": strings.t("powersection.profilePerformance", "Performance") }
    var icons = { "power-saver": "\udb80\udf2a", "balanced": "\udb80\ude9a", "performance": "\udb81\udcc5" }
    var list = power.profiles !== undefined ? power.profiles : []
    var out = []
    for (var i = 0; i < list.length; i++)
      out.push({ value: String(list[i]), label: labels[list[i]] || String(list[i]),
                 icon: icons[list[i]] || "" })
    return out
  }

  readonly property string sourceLabel: onBattery ? strings.t("powersection.onBattery", "On battery")
                                                   : strings.t("powersection.pluggedIn", "Plugged in")

  // On the mains the battery's own word for itself is not a state anyone
  // recognises: a full pack on a dock reports `discharging` while it trickles
  // a few hundredths of a watt out, so the card read "100% Discharging" on a
  // laptop that was plainly done charging. What the reader means by the
  // question is whether energy is going in, and on the mains that is answered
  // by the charge rather than by the flag — full is full, and anything short
  // of it with nothing going in is a battery being held there, which is what
  // a charge limit does.
  readonly property string stateLabel: {
    var state = String(reading.state || "")
    var percentage = Number(reading.percentage || 0)
    if (state === "empty") return strings.t("powersection.empty", "Empty")
    // The rate belongs to the word for what is happening, not to a clause of
    // its own: "Charging at 2.2 W" is one fact, where "Charging" and then
    // "2.2 W" two lines later is the reader assembling it.
    if (onBattery) return state === "discharging" || state === "pending-discharge"
      ? strings.t("powersection.discharging", "Discharging") + page.atRate()
      : strings.t("powersection.onBattery", "On battery")
    if (state === "charging" || state === "pending-charge") return strings.t("powersection.charging", "Charging") + page.atRate()
    if (state === "fully-charged" || percentage >= 99) return strings.t("powersection.fullyCharged", "Fully charged")
    return strings.t("powersection.notCharging", "Not charging")
  }

  function atRate() {
    if (reading.watts === null || reading.watts === undefined) return ""
    return " at " + Number(reading.watts).toFixed(1) + " W"
  }

  // Whether the machine is running off the battery, which is the first thing
  // anyone opening this page wants to know and the one thing a percentage on
  // its own does not say.
  readonly property bool onBattery: power.onBattery === true

  // Under the headline: how long it has at this rate. An estimate of how long
  // the battery lasts is about running on it, so on the mains it answers a
  // question nobody asked — and how fast it is going is a reading like the
  // others, so it sits with them rather than in the headline.
  readonly property string batterySummary: {
    var parts = []
    var left = page.roundedTime(String(reading.remaining || ""))
    if (left !== "" && (onBattery || reading.state === "charging"))
      parts.push(reading.state === "charging"
        ? strings.t("powersection.untilFull", "%1 until full").arg(left)
        : strings.t("powersection.left", "%1 left").arg(left))
    return parts.join("  ·  ")
  }

  // upower answers in tenths — "49.6 minutes", "3.1 hours" — and a tenth of
  // an hour is six minutes of a figure that is an estimate to begin with.
  // Whole units, and the unit named in the singular when it is one of them.
  // Seconds included: upower only reaches for them under a minute, and that
  // is the one moment the exact number is worth having.
  function roundedTime(text) {
    var match = /^([0-9.]+)\s+(\w+)$/.exec(String(text || "").trim())
    if (!match) return String(text || "")
    var amount = Math.round(Number(match[1]))
    if (!isFinite(amount) || amount <= 0) return String(text || "")
    var unit = match[2]
    if (amount === 1 && unit.charAt(unit.length - 1) === "s") unit = unit.slice(0, -1)
    return amount + " " + unit
  }

  // Red, amber, green, on the thresholds a battery indicator has always used:
  // under a fifth left is the one worth a colour that alarms, under a half is
  // worth noticing, and the rest is fine. Charging is green whatever the
  // level, because the number is on its way up and a red icon over a battery
  // that is filling is a warning about nothing.
  readonly property color levelColor: {
    if (!onBattery || reading.state === "charging") return Ui.Palette.good
    var percentage = Number(reading.percentage || 0)
    if (percentage <= 20) return Ui.Palette.bad
    if (percentage <= 50) return Ui.Palette.caution
    return Ui.Palette.good
  }

  readonly property var batteryFacts: {
    // Four facts, one row, all the same weight: what is in it against what it
    // holds, what it was sold as holding, the two compared, and how many
    // cycles got it there. Charge and capacity share a cell because on a full
    // battery they are the same number, and two columns of it read as the
    // card repeating itself.
    var out = [
      { key: "charge", label: strings.t("powersection.label.3", "Charge / capacity")},
      { key: "rated", label: strings.t("powersection.label.4", "Rated capacity")},
      { key: "health", label: strings.t("powersection.label.5", "Health")},
      { key: "cycles", label: strings.t("powersection.label.6", "Charge cycles")}
    ]
    // Only ever on a bad day: UPower answers "none" the rest of the time, and
    // a cell reading "Warning: none" trains people not to read it.
    if (String(reading.warning || "") !== "")
      out.push({ rule: true }, { key: "warning", label: strings.t("powersection.label.7", "Warning")})
    return out
  }

  readonly property var batteryValues: {
    var levels = { "low": strings.t("powersection.levelLow", "Low"),
                   "critical": strings.t("powersection.levelCritical", "Critical"),
                   "action": strings.t("powersection.levelAction", "About to shut down") }
    var warning = String(reading.warning || "")
    return {
      charge: reading.energy > 0 && reading.energyFull > 0
        ? Number(reading.energy).toFixed(1) + " / " + Number(reading.energyFull).toFixed(1) + " Wh"
        : "—",
      health: reading.health !== null && reading.health !== undefined
        ? strings.t("powersection.ofRated", "%1 % of rated").arg(reading.health) : "—",
      // Manufacturers specify conservatively and the gauge recalibrates as it
      // learns the pack, so a healthy battery measures a little above this.
      rated: reading.energyDesign > 0 ? Number(reading.energyDesign).toFixed(1) + " Wh" : "—",
      cycles: reading.cycles !== null && reading.cycles !== undefined
        ? String(reading.cycles) : strings.t("powersection.notCounted", "Not counted"),
      warning: levels[warning] !== undefined ? levels[warning] : warning
    }
  }

  Ui.SettingGroup {
    framed: true
    visible: !searchEmpty && page.power.hasBattery === true

    Item {
      width: parent.width
      implicitHeight: Math.max(glyph.implicitHeight, identity.implicitHeight, source.implicitHeight)

      // Drawn rather than set in a font: a glyph steps through ten levels in
      // one colour, where this fills to the charge and takes the colour the
      // level has earned. While charging it fills itself over and over, which
      // is the only way a still picture of a battery says that something is
      // happening to it.
      Ui.BatteryGauge {
        id: glyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        // Exactly as tall as the lines beside it, so the two read as one
        // block rather than as a picture with some text near it — and so a
        // state with nothing under it (plugged in and full) does not leave a
        // gauge towering over one line.
        height: identity.implicitHeight
        width: Math.round(height * 2.1)
        level: Number(page.reading.percentage || 0) / 100
        charging: String(page.reading.state || "") === "charging"
        fill: page.levelColor
      }

      Column {
        id: identity
        anchors.left: glyph.right
        anchors.leftMargin: Style.space(14)
        anchors.right: source.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        // "100% Fully charged" as one line, the number carrying it. A
        // percentage is what the reader is here for and it is the thing they
        // can take in without reading — so it is the size of the headline,
        // and the words sit on its baseline rather than above or below it.
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: level
            textFormat: Text.PlainText
            text: page.reading.percentage !== null && page.reading.percentage !== undefined
              ? page.reading.percentage + "%" : "\u2014"
            color: Ui.Palette.foreground
            font.family: Ui.Palette.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            anchors.baseline: level.baseline
            text: page.stateLabel
            elide: Text.ElideRight
            color: Ui.Palette.muted
            font.family: Ui.Palette.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          visible: page.batterySummary !== ""
          text: page.batterySummary
          elide: Text.ElideRight
          color: Ui.Palette.muted
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      // Where the power comes from is a different question from what the pack
      // is doing — a docked laptop at 100% reports discharging while plainly
      // on the mains — so it is a badge of its own rather than another clause.
      Ui.Tag {
        id: source
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: page.sourceLabel
        accented: !page.onBattery
      }
    }

    Ui.FactGrid {
      layout: page.batteryFacts
      values: page.batteryValues
    }

    // Enough to stop a healthy battery looking broken — it holds more than
    // its rating, and Health sits at 100% anyway — and not a word more.
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: strings.t("powersection.text.1", "Capacity is what the battery holds today. Rated capacity is what the manufacturer specified, usually lower than the actual capacity.")
      wrapMode: Text.WordWrap
      color: Ui.Palette.muted
      font.family: Ui.Palette.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Under the battery rather than on the Processes page as well, because the
  // question "what is draining it" is asked here, on the page that says how
  // long is left.
  Ui.SettingGroup {
    title: strings.t("powersection.title.1", "Profile")

    Ui.ChoiceRow {
      label: strings.t("powersection.label.1", "On battery")
      value: page.power.forBattery !== undefined ? String(page.power.forBattery) : ""
      options: page.profileOptions()
      onPicked: function(next) { page.app.run(["power", "profile", "battery", next]) }
    }

    Ui.ChoiceRow {
      label: strings.t("powersection.label.2", "Plugged in")
      value: page.power.ac !== undefined ? String(page.power.ac) : ""
      options: page.profileOptions()
      onPicked: function(next) { page.app.run(["power", "profile", "ac", next]) }
    }
  }
}
