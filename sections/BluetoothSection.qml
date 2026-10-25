pragma ComponentBehavior: Bound
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

  readonly property var bluetooth: app.bluetooth
  readonly property var devices: bluetooth.devices !== undefined ? bluetooth.devices : []

  // Three states, three lists. They answer different questions — what am I
  // using, what do I own, what else is here — so they are not one list with
  // a sort order you have to infer.
  function devicesWhere(test) {
    var out = []
    for (var i = 0; i < devices.length; i++)
      if (test(devices[i])) out.push(devices[i])
    return out
  }

  readonly property var connectedDevices: devicesWhere(function(d) { return d.connected === true })
  readonly property var pairedDevices: devicesWhere(function(d) { return d.paired === true && d.connected !== true })
  readonly property var nearbyDevices: devicesWhere(function(d) { return d.paired !== true })

  // The adapter governs the whole page, so its switch sits beside the page
  // name and the summary replaces the file path under it.
  property Component headerControl: Component {
    ToggleSwitch {
      checked: page.bluetooth.powered === true
      foreground: Ui.Palette.foreground
      accent: Ui.Palette.accent
      onToggled: page.app.run(["bluetooth", "power", page.bluetooth.powered === true ? "off" : "on"])
    }
  }

  // The lists below say what is connected; the header only says whether the
  // adapter is on at all.
  readonly property string headerNote: {
    if (bluetooth.available === false) return strings.t("bluetoothsection.noAdapter", "No adapter")
    return bluetooth.powered === true ? "" : strings.t("bluetoothsection.off", "Off")
  }

  // Devices come and go while you are looking at them, and discovery is a
  // mode the adapter has to be held in, so the page holds it — but only
  // while it is the page on screen and the window is open.
  Timer {
    interval: 5000
    running: page.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: page.app.pollBluetooth()
  }

  Ui.SettingGroup {
    rowSpacing: Style.space(2)
    title: strings.t("bluetoothsection.title.1", "Connected")
    visible: !searchEmpty && page.bluetooth.powered === true && page.connectedDevices.length > 0

    Repeater {
      model: page.connectedDevices
      delegate: DeviceDelegate {}
    }
  }

  Ui.SettingGroup {
    rowSpacing: Style.space(2)
    title: strings.t("bluetoothsection.title.2", "Paired")
    visible: !searchEmpty && page.bluetooth.powered === true && page.pairedDevices.length > 0

    Repeater {
      model: page.pairedDevices
      delegate: DeviceDelegate {}
    }
  }

  Ui.SettingGroup {
    rowSpacing: Style.space(2)
    title: strings.t("bluetoothsection.title.3", "Nearby")
    visible: !searchEmpty && page.bluetooth.powered === true

    Repeater {
      model: page.nearbyDevices
      delegate: DeviceDelegate {}
    }
  }

  // At the foot rather than the top: pairing usually starts from this
  // machine, and only the other direction needs this.
  Ui.SettingGroup {
    title: strings.t("bluetoothsection.title.4", "This computer")
    visible: !searchEmpty && page.bluetooth.powered === true

    Ui.SwitchRow {
      label: strings.t("bluetoothsection.label.1", "Let other devices find this one")
      description: page.bluetooth.adapter !== undefined && page.bluetooth.adapter !== ""
        ? strings.t("bluetoothsection.discoverableSeeAs",
            "Phones and headsets pairing from their own side see it as \u201c%1\u201d.")
            .arg(page.bluetooth.adapter)
        : strings.t("bluetoothsection.discoverableNeeded",
            "Needed only when the other device is doing the pairing.")
      + strings.t("bluetoothsection.discoverableTail",
          " Switches itself off again after a few minutes.")
      checked: page.bluetooth.discoverable === true
      onRequested: function(next) { page.app.run(["bluetooth", "discoverable", next ? "on" : "off"]) }
    }
  }

  // The three lists differ only in what they hold, so the row they hold is
  // written once.
  component DeviceDelegate: Ui.DeviceRow {
    required property var modelData

    width: parent ? parent.width : 0
    address: modelData.address
    name: modelData.name
    kind: modelData.icon
    paired: modelData.paired === true
    connected: modelData.connected === true
    battery: modelData.battery !== null && modelData.battery !== undefined ? Number(modelData.battery) : -1
    rssi: modelData.rssi !== null && modelData.rssi !== undefined ? Number(modelData.rssi) : -200
    onConnectRequested: page.app.run(["bluetooth", "connect", modelData.address])
    onDisconnectRequested: page.app.run(["bluetooth", "disconnect", modelData.address])
    onPairRequested: page.app.run(["bluetooth", "pair", modelData.address])
    onForgetRequested: page.app.run(["bluetooth", "forget", modelData.address])
  }
}
