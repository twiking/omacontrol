import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

// The bar's way into OmaControl: a gear that opens the window.
//
// Nothing but the button lives here. The window and the IPC route are the
// service's (Service.qml), which runs whenever the plugin is enabled, with or
// without a bar entry — so removing the button from the bar costs you the
// button and nothing else.
BarWidget {
  id: root
  moduleName: "io.github.twiking.omacontrol"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  // Shape contract for shell.summon/hide/toggle routing: Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root, so the widget stands in
  // for the window it does not own.
  readonly property bool opened: service ? service.opened : false

  // A replacement bar hands its widgets a facade scoped to the bar plugin, so
  // serviceFor() answers null and a gear forwarding only to the service did
  // nothing at all. The IPC route is the service's own and answers under any
  // bar, so it stands in when the direct path is not there.
  function ipc(args) { Quickshell.execDetached(["omarchy-shell", "omacontrol"].concat(args)) }

  function show() { if (service) service.show(); else ipc(["show"]) }
  function showPage(page) { if (service) service.showPage(page); else ipc(["showPage", String(page || "")]) }
  function hide() { if (service) service.hide(); else ipc(["hide"]) }
  function open() { show() }
  function close() { hide() }
  function toggle() { if (service) service.toggle(); else ipc(["toggle"]) }

  // What the Overview page switches, kept current by the service so that one
  // watcher serves every bar. The gear says it is here, and gone, so the
  // watcher runs only while something is showing the badge.
  readonly property var switches: service && service.switches ? service.switches : ({})
  readonly property var switchedOn: {
    var on = []
    if (switches.nightlight === true) on.push("Night light")
    if (switches.dnd === true) on.push("Do not disturb")
    if (switches.awake === true) on.push("Stay awake")
    return on
  }

  // Keep the tooltip complete when the bar already has a Stay awake indicator.
  readonly property bool showStayAwakeBadge: setting("showStayAwakeBadge", true) !== false
  readonly property int badgeCount: switchedOn.length
    - (!showStayAwakeBadge && switches.awake === true ? 1 : 0)

  // Offline outranks the count: it is the one thing on the badge that is a
  // problem rather than a choice. Null means NetworkManager could not be
  // asked, which says nothing about the connection, so it marks nothing.
  readonly property bool offline: switches.online === false
  // The laptop's own battery, by Omarchy's rule for its "Time to recharge!"
  // warning (BatteryModel.js in its battery service): present, on battery,
  // discharging, and at 10 % or under. Read from UPower directly, as that
  // service does — Quickshell's binding is live and gated to nobody, so this
  // half needs no watcher at all. A desktop has no battery present and never
  // shows it.
  readonly property var battery: UPower.displayDevice
  readonly property int batteryLevel: battery && battery.isPresent
    ? Math.round(Number(battery.percentage || 0) * 100) : -1
  readonly property bool batteryLow: batteryLevel >= 0 && UPower.onBattery
    && battery.state === UPowerDeviceState.Discharging && batteryLevel <= 10

  // Bluetooth devices about to run flat, from the same list the Overview page
  // warns from. After the laptop's own battery, which takes the whole machine
  // down with it; before the count, since a choice is never as urgent as a
  // keyboard about to drop off.
  readonly property var lowDevices: Array.isArray(switches.lowDevices) ? switches.lowDevices : []

  property var watching: null
  onServiceChanged: {
    if (watching) watching.watchSwitches(false)
    watching = service
    if (watching) watching.watchSwitches(true)
  }
  Component.onDestruction: if (watching) watching.watchSwitches(false)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A gear, because that is what anyone looks for when they want settings,
    // named as the app is: "Settings" could be any of a dozen things on a
    // desktop. Sliders were tried and read as an audio mixer beside the sound
    // widget.
    text: "\uf013"
    tooltipText: {
      var parts = []
      if (root.offline) parts.push("No network")
      if (root.batteryLow) parts.push("Battery at " + root.batteryLevel + " %")
      for (var i = 0; i < root.lowDevices.length; i++)
        parts.push(root.lowDevices[i].name + " at " + root.lowDevices[i].percent + " %")
      if (root.switchedOn.length > 0) parts.push(root.switchedOn.join(", ") + " on")
      return parts.length > 0 ? "OmaControl — " + parts.join(" · ") : "OmaControl"
    }
    active: root.opened
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.bar.run("omarchy-menu")
      // A problem on the badge sends the click where it can be fixed.
      else if (root.offline && !root.opened) root.showPage("network")
      else if (root.batteryLow && !root.opened) root.showPage("power")
      else if (root.lowDevices.length > 0 && !root.opened) root.showPage("bluetooth")
      else root.toggle()
    }
  }

  // How many are on, in the shape OmaIndicators uses beside it so the bar has
  // one kind of badge. Over the glyph's top edge rather than beside it: the
  // bar gives a widget one icon slot, and widening it for a badge would shove
  // the whole section sideways every time one came on.
  Rectangle {
    visible: root.offline || root.batteryLow || root.lowDevices.length > 0 || root.badgeCount > 0
    anchors.top: button.top
    anchors.left: button.horizontalCenter
    anchors.leftMargin: Style.space(1)
    width: Math.max(height, count.implicitWidth + Style.space(8))
    height: Style.space(16)
    radius: height / 2
    color: Color.bar.active

    Text {
      id: count
      anchors.centerIn: parent
      // nf-md-wifi_off, U+F05AA, as its surrogate pair: the solid one, since
      // the outlined Wi-Fi-off thins to nothing at a badge's size.
      // nf-md-battery_alert (U+F0083) for the laptop, and its Bluetooth
      // variant (U+F094B) for a device, so the two read apart at a glance.
      text: root.offline ? "\udb81\uddaa"
        : root.batteryLow ? "\udb80\udc83"
        : root.lowDevices.length > 0 ? "\udb82\udd4b"
        : String(root.badgeCount)
      textFormat: Text.PlainText
      color: Color.bar.background
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}

