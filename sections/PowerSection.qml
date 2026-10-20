import QtQuick
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
Ui.SectionBody {
  id: page
  property var app: null

  readonly property var power: app.power
  readonly property var reading: power.battery !== undefined ? power.battery : ({})
  readonly property var idle: app.idleState
  readonly property bool hasBattery: power.hasBattery === true
  readonly property var charge: power.chargeThreshold !== undefined && power.chargeThreshold !== null
    ? power.chargeThreshold : null

  // Power profiles are named for machines, not people. The icons are the
  // bar's own, from its power widget: the same three glyphs for the same
  // three profiles, since the bar is where most people meet them and two
  // pictures for one profile is one too many.
  function profileOptions() {
    var labels = { "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" }
    var icons = { "power-saver": "\udb80\udf2a", "balanced": "\udb80\ude9a", "performance": "\udb81\udcc5" }
    var list = power.profiles !== undefined ? power.profiles : []
    var out = []
    for (var i = 0; i < list.length; i++)
      out.push({ value: String(list[i]), label: labels[list[i]] || String(list[i]),
                 icon: icons[list[i]] || "" })
    return out
  }

  readonly property string sourceLabel: onBattery ? "On battery" : "Plugged in"

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
    if (state === "empty") return "Empty"
    // The rate belongs to the word for what is happening, not to a clause of
    // its own: "Charging at 2.2 W" is one fact, where "Charging" and then
    // "2.2 W" two lines later is the reader assembling it.
    if (onBattery) return state === "discharging" || state === "pending-discharge"
      ? "Discharging" + page.atRate() : "On battery"
    if (state === "charging" || state === "pending-charge") return "Charging" + page.atRate()
    if (state === "fully-charged" || percentage >= 99) return "Fully charged"
    return "Not charging"
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
      parts.push(reading.state === "charging" ? left + " until full" : left + " left")
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
      { key: "charge", label: "Charge / capacity" },
      { key: "rated", label: "Rated capacity" },
      { key: "health", label: "Health" },
      { key: "cycles", label: "Charge cycles" }
    ]
    // Only ever on a bad day: UPower answers "none" the rest of the time, and
    // a cell reading "Warning: none" trains people not to read it.
    if (String(reading.warning || "") !== "")
      out.push({ rule: true }, { key: "warning", label: "Warning" })
    return out
  }

  readonly property var batteryValues: {
    var levels = { "low": "Low", "critical": "Critical", "action": "About to shut down" }
    var warning = String(reading.warning || "")
    return {
      charge: reading.energy > 0 && reading.energyFull > 0
        ? Number(reading.energy).toFixed(1) + " / " + Number(reading.energyFull).toFixed(1) + " Wh"
        : "—",
      health: reading.health !== null && reading.health !== undefined
        ? reading.health + "% of rated" : "—",
      // Manufacturers specify conservatively and the gauge recalibrates as it
      // learns the pack, so a healthy battery measures a little above this.
      rated: reading.energyDesign > 0 ? Number(reading.energyDesign).toFixed(1) + " Wh" : "—",
      cycles: reading.cycles !== null && reading.cycles !== undefined
        ? String(reading.cycles) : "Not counted",
      warning: levels[warning] !== undefined ? levels[warning] : warning
    }
  }

  Ui.SettingGroup {
    framed: true
    visible: !searchEmpty && power.hasBattery === true

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
        level: Number(reading.percentage || 0) / 100
        charging: String(reading.state || "") === "charging"
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
            text: reading.percentage !== null && reading.percentage !== undefined
              ? reading.percentage + "%" : "\u2014"
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
      text: "Capacity is what the battery holds today. Rated capacity is what the manufacturer specified, usually lower than the actual capacity."
      wrapMode: Text.WordWrap
      color: Ui.Palette.muted
      font.family: Ui.Palette.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Ui.SettingGroup {
    title: "Charge limit"
    note: "Keeps the battery from charging past a chosen level. Applies until the next reboot."
    visible: !searchEmpty && hasBattery

    Ui.PercentRow {
      label: "Stop charging at"
      description: "The level the battery stops charging at, to keep it healthy."
      value: charge !== null && charge.end !== null ? charge.end / 100 : 1
      enabled: charge !== null && charge.supported === true
      tooltip: charge !== null && charge.supported === true
        ? "" : "This battery does not expose a charge limit"
      onCommitted: function(next) { app.run(["power", "charge", "end", String(Math.round(next * 100))]) }
    }

    Ui.PercentRow {
      label: "Begin charging below"
      description: "Charging resumes once the battery has dropped under this level."
      visible: !searchHidden && charge !== null && charge.startSupported === true
      value: charge !== null && charge.start !== null ? charge.start / 100 : 0
      enabled: charge !== null && charge.supported === true
      tooltip: charge !== null && charge.supported === true
        ? "" : "This battery does not expose a charge limit"
      onCommitted: function(next) { app.run(["power", "charge", "start", String(Math.round(next * 100))]) }
    }
  }

  Ui.SettingGroup {
    title: "Timeouts"

    Ui.MinutesRow {
      label: "Screensaver after"
      seconds: idle.screensaver !== undefined ? Number(idle.screensaver) : 150
      onCommitted: function(mins) { app.set("idle-screensaver", mins * 60) }
      changed: app.isChanged("idle-screensaver")
      onResetRequested: app.resetSetting("idle-screensaver")
    }

    Ui.MinutesRow {
      label: "Lock after"
      seconds: idle.lock !== undefined ? Number(idle.lock) : 300
      onCommitted: function(mins) { app.set("idle-lock", mins * 60) }
      changed: app.isChanged("idle-lock")
      onResetRequested: app.resetSetting("idle-lock")
    }

    Ui.MinutesRow {
      label: "Sleep after"
      description: "Suspend the computer once it has been idle this long."
      allowOff: true
      seconds: idle.suspend !== undefined ? Number(idle.suspend) : 0
      enabled: power.suspendAvailable === true
      tooltip: power.suspendAvailable === true
        ? "" : "Suspend is not available on this computer"
      onCommitted: function(mins) { app.set("idle-suspend", mins * 60) }
      changed: app.isChanged("idle-suspend")
      onResetRequested: app.resetSetting("idle-suspend")
    }

    Ui.MinutesRow {
      label: "Hibernate after"
      description: "Hibernate the computer once it has been idle this long."
      allowOff: true
      seconds: idle.hibernate !== undefined ? Number(idle.hibernate) : 0
      enabled: power.hibernateAvailable === true
      tooltip: power.hibernateAvailable === true
        ? "" : "Hibernate is not available on this computer"
      onCommitted: function(mins) { app.set("idle-hibernate", mins * 60) }
      changed: app.isChanged("idle-hibernate")
      onResetRequested: app.resetSetting("idle-hibernate")
    }
  }

  Ui.ChoiceRow {
    label: "Lid close"
    description: "What the laptop does when you close the lid."
    visible: !searchHidden && power.hasLid === true
    value: power.lidAction !== undefined ? String(power.lidAction) : "suspend"
    options: {
      var out = [
        { value: "nothing", label: "Nothing" },
        { value: "lock", label: "Lock" }
      ]
      if (power.suspendAvailable === true) out.push({ value: "suspend", label: "Suspend" })
      if (power.hibernateAvailable === true) out.push({ value: "hibernate", label: "Hibernate" })
      return out
    }
    onPicked: function(next) { app.set("lid-action", next) }
    changed: app.isChanged("lid-action")
    onResetRequested: app.resetSetting("lid-action")
  }

  // Under the battery rather than on the Processes page as well, because the
  // question "what is draining it" is asked here, on the page that says how
  // long is left.
  Ui.SettingGroup {
    title: "Profile"

    Ui.ChoiceRow {
      label: "On battery"
      value: power.forBattery !== undefined ? String(power.forBattery) : ""
      options: profileOptions()
      onPicked: function(next) { app.run(["power", "profile", "battery", next]) }
    }

    Ui.ChoiceRow {
      label: "Plugged in"
      value: power.ac !== undefined ? String(power.ac) : ""
      options: profileOptions()
      onPicked: function(next) { app.run(["power", "profile", "ac", next]) }
    }
  }
}
