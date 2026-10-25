pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../ui" as Ui
import "../ui/displays.js" as Geometry

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  // A display you own is not always plugged in, and Hyprland matches its
  // monitor rules again every time it is: a display can be set up here before
  // the cable is in, and keeps what it was given.
  readonly property var displays: app.monitors !== undefined ? app.monitors : []

  readonly property var arrangeable: {
    var out = []
    for (var i = 0; i < displays.length; i++) {
      var d = displays[i]
      // A display that is off, mirroring another or not here at all has no
      // place in the layout — Hyprland gives it none either.
      if (d.connected === false || d.off === true || String(d.mirror || "") !== "") continue
      if (Number(d.width) <= 0 || Number(d.height) <= 0) continue
      var position = String(d.position || "").split("x")
      out.push({ name: String(d.name), label: String(d.label || d.name),
                 output: String(d.output || ""),
                 focused: d.focused === true,
                 x: Number(position[0] || 0), y: Number(position[1] || 0),
                 width: Number(d.width), height: Number(d.height),
                 scale: Number(d.scale) || 1, transform: Number(d.transform) || 0 })
    }
    return out
  }

  // Brightness is not in the state document, so the page asks for it — while
  // it is the page on screen and the window is open, like every other reading
  // this window shows.
  Timer {
    interval: 5000
    running: page.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: page.app.pollBrightness()
  }

  // Where the displays are relative to one another, as a picture. The same
  // fact as a pair of coordinates per display and the only form anybody can
  // read it in: "is the laptop left of the monitor" is a question about a
  // shape. Only with two to arrange — one display is not an arrangement.
  Ui.SettingGroup {
    title: strings.t("displayssection.title.1", "Arrangement")
    visible: !searchEmpty && page.arrangeable.length > 1

    Ui.DisplayCanvas {
      items: page.arrangeable
      // Only the displays that actually moved: re-anchoring the layout can
      // shift every one of them, and a write per display per drag would be
      // three state reads to say what one of them already said.
      onArranged: function(positions) {
        for (var i = 0; i < positions.length; i++) {
          var wanted = positions[i].x + "x" + positions[i].y
          var was = ""
          for (var j = 0; j < page.arrangeable.length; j++)
            if (page.arrangeable[j].name === positions[i].name)
              was = page.arrangeable[j].x + "x" + page.arrangeable[j].y
          if (wanted !== was) page.app.set("monitor:" + positions[i].name + ":position", wanted)
        }
      }
    }
  }

  // Every display gets its own group, titled with its name, so what a control
  // writes is never in doubt. A display carries its resolution and its scale;
  // both mean nothing without saying which screen they are about.
  Repeater {
    model: page.displays

    delegate: Ui.SettingGroup {
      id: displayGroup
      required property var modelData

      // The identity a setting is written against: the display's own
      // description where it has one, so what is set here stays with the screen
      // rather than with the socket it happened to be in. `label` is what to
      // call it, since the identity itself reads as machinery.
      readonly property string name: String(modelData.name)
      readonly property string label: String(modelData.label || modelData.name)
      readonly property bool connected: modelData.connected !== false
      readonly property bool off: modelData.off === true
      readonly property var settings: modelData.settings || ({})
      readonly property var modes: modelData.modes || []
      readonly property string output: String(modelData.output || "")

      // The two halves of a mode. Hyprland takes them as one string, and
      // nobody picks a resolution and a refresh rate as one decision.
      readonly property string mode: String(modelData.mode)
      readonly property string resolution: mode.indexOf("@") > 0 ? mode.split("@")[0] : mode
      readonly property string refresh: mode.indexOf("@") > 0 ? mode.split("@")[1] : ""

      readonly property var resolutions: {
        var seen = {}
        var out = []
        for (var i = 0; i < modes.length; i++) {
          var size = String(modes[i]).split("@")[0]
          if (seen[size]) continue
          seen[size] = true
          out.push({ value: size, label: size.split("x").join(" × ") })
        }
        return out
      }

      readonly property var refreshRates: {
        var out = []
        for (var i = 0; i < modes.length; i++) {
          var parts = String(modes[i]).split("@")
          if (parts[0] !== resolution || parts.length < 2) continue
          out.push({ value: parts[1], label: Math.round(Number(parts[1])) + " Hz" })
        }
        return out
      }

      // What the page can offer to mirror: every other display that is here.
      // Mirroring names an output rather than a display, which is Hyprland's
      // own rule and the one place a connector is the right answer.
      readonly property var mirrorOptions: {
        var out = [{ value: "", label: strings.t("displayssection.label.11", "Off")}]
        for (var i = 0; i < page.displays.length; i++) {
          var other = page.displays[i]
          if (other.name === name || other.connected === false) continue
          if (String(other.output || "") === "") continue
          out.push({ value: String(other.output), label: String(other.label || other.name) })
        }
        return out
      }

      readonly property int brightness: {
        var all = page.app.displayBrightness
        return output !== "" && all[output] !== undefined ? Number(all[output]) : -1
      }

      width: parent.width
      title: label + (connected ? ""
                               : " " + strings.t("devices.notConnected", " (not connected)"))

      // The title says which screen this is. The connector is the part you
      // cannot tell from that, and the part that changes between docks — so it
      // is shown, and nothing is written against it.
      Ui.ReadingRow {
        label: strings.t("displayssection.label.1", "Connector")
        visible: !searchHidden && displayGroup.connected && displayGroup.output !== ""
        value: displayGroup.output
      }

      // What the display does when it is on can be set while it is off — a
      // resolution or a scale chosen now is what it comes back to, and
      // needing to turn a screen on to tell it how to come on is a loop.
      Ui.SwitchRow {
        label: strings.t("displayssection.label.2", "Enabled")
        visible: !searchHidden && displayGroup.connected
        checked: !displayGroup.off
        onRequested: function(next) {
          page.app.set("monitor:" + displayGroup.name + ":disabled", next ? "false" : "true")
        }
        changed: page.app.isChanged("monitor:" + displayGroup.name + ":disabled")
        onResetRequested: page.app.resetSetting("monitor:" + displayGroup.name + ":disabled")
      }

      Ui.PickerRow {
        label: strings.t("displayssection.label.3", "Resolution")
        // A display that is not here reports no modes, so what it was given is
        // the only option there is to show.
        description: displayGroup.connected ? ""
          : strings.t("displayssection.appliedOnReturn", "Applied when the display comes back.")
        visible: !searchHidden
        value: displayGroup.resolution
        options: {
          var listed = displayGroup.resolutions
          if (displayGroup.resolution !== "preferred"
              && !listed.some(function(item) { return item.value === displayGroup.resolution }))
            listed = [{ value: displayGroup.resolution, label: displayGroup.resolution.split("x").join(" × ") }].concat(listed)
          return [{ value: "preferred", label: strings.t("displayssection.label.12", "Preferred (what the display asks for)")}].concat(listed)
        }
        // A resolution is picked as a resolution, so the fastest rate the
        // display can do at it comes with it rather than being a second
        // decision the reader did not know they had made.
        onPicked: function(next) {
          if (next === "preferred") { page.app.set("monitor:" + displayGroup.name + ":mode", "preferred"); return }
          var fastest = ""
          for (var i = 0; i < displayGroup.modes.length; i++) {
            var parts = String(displayGroup.modes[i]).split("@")
            if (parts[0] !== next || parts.length < 2) continue
            if (fastest === "" || Number(parts[1]) > Number(fastest)) fastest = parts[1]
          }
          page.app.set("monitor:" + displayGroup.name + ":mode", fastest === "" ? next : next + "@" + fastest)
        }
        changed: page.app.isChanged("monitor:" + displayGroup.name + ":mode")
        onResetRequested: page.app.resetSetting("monitor:" + displayGroup.name + ":mode")
      }

      Ui.PickerRow {
        label: strings.t("displayssection.label.4", "Refresh rate")
        visible: !searchHidden && displayGroup.refreshRates.length > 1
        value: displayGroup.refresh
        options: displayGroup.refreshRates
        onPicked: function(next) { page.app.set("monitor:" + displayGroup.name + ":mode", displayGroup.resolution + "@" + next) }
      }

      // Hyprland only takes a scale where the mode divides into whole logical
      // pixels, and silently rounds anything else — so a slider offered a
      // hundred numbers of which a handful were real, and showed the one that
      // was asked for rather than the one in force. The choices are computed
      // from the resolution instead, and there are few enough to sit side by
      // side.
      readonly property var scaleOptions: {
        var size = resolution.split("x")
        var width = Number(size[0]) || Number(modelData.width) || 0
        var height = Number(size[1]) || Number(modelData.height) || 0
        var presets = ["1", "1.25", "1.5", "1.6", "2", "3"]
        var clean = width > 0 && height > 0
          ? Geometry.availableScales(presets, width, height) : presets
        // Whatever the display is actually on belongs among the choices even
        // when no preset lands there — a row that cannot show its own value
        // reads as a setting that is off.
        var current = Geometry.normalizeScale(modelData.scale)
        if (current !== "" && clean.indexOf(current) < 0)
          clean = clean.concat([current]).sort(function(a, b) { return Number(a) - Number(b) })
        return clean.map(function(value) { return { value: value, label: value + "\u00d7" } })
      }

      Ui.ChoiceRow {
        label: strings.t("displayssection.label.5", "Scale")
        visible: !searchHidden
        value: Geometry.normalizeScale(displayGroup.modelData.scale)
        options: displayGroup.scaleOptions
        onPicked: function(next) { page.app.set("monitor:" + displayGroup.name + ":scale", next) }
        changed: page.app.isChanged("monitor:" + displayGroup.name + ":scale")
        onResetRequested: page.app.resetSetting("monitor:" + displayGroup.name + ":scale")
      }

      Ui.ChoiceRow {
        label: strings.t("displayssection.label.6", "Rotation")
        visible: !searchHidden
        value: String(Number(displayGroup.modelData.transform) || 0)
        options: [
          { value: "0", label: strings.t("displayssection.label.13", "None")},
          { value: "1", label: strings.t("displayssection.label.14", "90°")},
          { value: "2", label: strings.t("displayssection.label.15", "180°")},
          { value: "3", label: strings.t("displayssection.label.16", "270°")}
        ]
        onPicked: function(next) { page.app.set("monitor:" + displayGroup.name + ":transform", next) }
        changed: page.app.isChanged("monitor:" + displayGroup.name + ":transform")
        onResetRequested: page.app.resetSetting("monitor:" + displayGroup.name + ":transform")
      }

      Ui.ChoiceRow {
        label: strings.t("displayssection.label.7", "Variable refresh")
        // The range is the display's own answer to whether this is worth
        // turning on, and it is not anywhere else on the desktop.
        description: String(displayGroup.modelData.vrrRange || "") !== ""
          ? strings.t("displayssection.vrrRange", "This display varies between %1 Hz.")
              .arg(displayGroup.modelData.vrrRange)
          : strings.t("displayssection.vrrDesc",
              "Lets the display follow what is being drawn instead of its own clock.")
        visible: !searchHidden && displayGroup.connected
        value: String(Number(displayGroup.modelData.vrr) || 0)
        options: [
          { value: "0", label: strings.t("displayssection.label.17", "Off")},
          { value: "1", label: strings.t("displayssection.label.18", "On")},
          { value: "2", label: strings.t("displayssection.label.19", "Fullscreen only")}
        ]
        onPicked: function(next) { page.app.set("monitor:" + displayGroup.name + ":vrr", next) }
        changed: page.app.isChanged("monitor:" + displayGroup.name + ":vrr")
        onResetRequested: page.app.resetSetting("monitor:" + displayGroup.name + ":vrr")
      }

      // Only for a display that says it can: a switch that cannot do anything
      // is worse than no switch, because it gives no reason why.
      Ui.SwitchRow {
        label: strings.t("displayssection.label.8", "HDR")
        description: strings.t("displayssection.description.1", "Wide colour and ten-bit output. Everything that is not HDR is mapped into it, which some desktops render washed out.")
        visible: !searchHidden && displayGroup.modelData.hdrCapable === true
        checked: displayGroup.modelData.hdr === true
        onRequested: function(next) {
          page.app.set("monitor:" + displayGroup.name + ":hdr", next ? "true" : "false")
        }
        changed: page.app.isChanged("monitor:" + displayGroup.name + ":hdr")
        onResetRequested: page.app.resetSetting("monitor:" + displayGroup.name + ":hdr")
      }

      Ui.PickerRow {
        label: strings.t("displayssection.label.9", "Mirror")
        description: strings.t("displayssection.description.2", "Show what another display is showing.")
        visible: !searchHidden && displayGroup.connected && displayGroup.mirrorOptions.length > 1
        value: String(displayGroup.modelData.mirror || "")
        options: displayGroup.mirrorOptions
        onPicked: function(next) { page.app.set("monitor:" + displayGroup.name + ":mirror", next) }
        changed: page.app.isChanged("monitor:" + displayGroup.name + ":mirror")
        onResetRequested: page.app.resetSetting("monitor:" + displayGroup.name + ":mirror")
      }

      // The backlight on a laptop panel, DDC over the cable on a desktop
      // monitor — and nothing at all where neither answers, which is most
      // docks. The one row that does go with the display being off, because
      // a screen that is not lit has no brightness to read or to set. No
      // change mark either: this is the screen in front of you rather than a
      // setting this window keeps.
      Ui.PercentRow {
        label: strings.t("displayssection.label.10", "Brightness")
        visible: !searchHidden && !displayGroup.off && displayGroup.brightness >= 0
        value: displayGroup.brightness / 100
        onCommitted: function(next) {
          page.app.run(["display", "brightness", displayGroup.name, String(Math.round(next * 100))])
        }
      }

      // Only once there is something to forget: for a display sitting in front
      // of you with nothing set, there is nothing this would undo.
      Ui.ActionRow {
        visible: !searchHidden && (Object.keys(displayGroup.settings).length > 0 || !displayGroup.connected)
        buttonText: strings.t("displayssection.buttonText.1", "Forget Display")
        onTriggered: page.app.set("monitor-forget", displayGroup.name)
      }
    }
  }
}
