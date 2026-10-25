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

  readonly property var wifi: app.wifi
  readonly property var link: app.wifiLink
  readonly property bool hasRadio: wifi.available !== false && String(wifi.device !== undefined ? wifi.device : "") !== ""
  readonly property bool radioOn: hasRadio && wifi.enabled === true
  readonly property bool connected: wifi.connected !== ""

  // The radio governs the whole page, so its switch sits beside the page name
  // rather than as the first of a card of one row — and the page then opens on
  // the connection, which is what anyone comes here for.
  property Component headerControl: Component {
    Row {
      spacing: Style.space(16)

      // The same glyph and the same wording the bar's network panel uses for
      // this, so the two read as one feature rather than two — and the words
      // as well as the icon, since a lone glyph in a header is a guess until
      // you hover it.
      Button {
        anchors.verticalCenter: parent.verticalCenter
        visible: page.connected
        iconText: "\udb81\udc32"
        text: strings.t("networksection.text.1", "Show QR code")
        bordered: true
        foreground: Ui.Palette.foreground
        accent: Ui.Palette.accent
        fontFamily: Ui.Palette.fontFamily
        fontSize: Style.font.caption
        // Its own breathing room before the radio label: the two are unrelated
        // controls that happen to share a strip.
        rightPadding: Style.space(14)
        onClicked: page.app.run(["menu", "run", "setup.network.qr"])
      }

      // The panel's own glyph and wording again. It hands off to Omarchy's
      // speed-test panel rather than measuring anything here: a second opinion
      // about someone's bandwidth is worse than none, and that panel already
      // draws the result.
      Button {
        anchors.verticalCenter: parent.verticalCenter
        visible: page.connected
        iconText: "\udb81\udcc5"
        text: strings.t("networksection.text.2", "Run speed test")
        bordered: true
        foreground: Ui.Palette.foreground
        accent: Ui.Palette.accent
        fontFamily: Ui.Palette.fontFamily
        fontSize: Style.font.caption
        rightPadding: Style.space(14)
        onClicked: page.app.run(["wifi", "speedtest", page.wifi.connected])
      }

      // A switch on its own in a window header is a switch for the page, and
      // on a page called Network that could be the radio, the connection or
      // the interface. Named, it is the radio.
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: page.hasRadio
        text: strings.t("networksection.text.3", "Wi-Fi")
        color: Ui.Palette.foreground
        font.family: Ui.Palette.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        visible: page.hasRadio
        checked: page.wifi.enabled === true
        foreground: Ui.Palette.foreground
        accent: Ui.Palette.accent
        onToggled: page.app.run(["wifi", "radio", page.wifi.enabled === true ? "off" : "on"])
      }
    }
  }

  // Which network you are on is in the card below; the header only says
  // whether there is a radio at all and whether it is on.
  readonly property string headerNote: {
    if (wifi.available === false) return strings.t("networksection.noNetworkManager", "NetworkManager is not running")
    if (!hasRadio) return strings.t("networksection.noRadio", "No wireless hardware")
    return wifi.enabled === true ? "" : strings.t("networksection.off", "Off")
  }

  // "3 927", as the mockup writes it.
  function grouped(n) {
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  }

  function reading(value) {
    return value === undefined || value === null || value === "" ? "—" : String(value)
  }

  // One line under the name, in the order someone would say it. Each part
  // drops out rather than printing a blank: a network that does not advertise
  // its generation is not a network with an unknown one.
  readonly property string linkSummary: {
    var parts = []
    // Not "Online": this card is only drawn for a connection that exists, so
    // the word was on screen whenever it could be read and told nobody
    // anything. The signal leads instead, since it is the part that changes.
    if (link.signalDbm !== undefined && link.signalDbm !== null) {
      var phrase = link.signalDbm >= -60 ? strings.t("networksection.signalStrong", "Strong signal")
                 : link.signalDbm >= -72 ? strings.t("networksection.signalFair", "Fair signal")
                 : strings.t("networksection.signalWeak", "Weak signal")
      // The words say what to make of it, the number says how much room there
      // is above or below. It is NetworkManager's percentage, the same one the
      // bars beside it are drawn from, so the three cannot disagree.
      var net = app.activeNetwork
      if (net !== null && net.signal !== undefined)
        phrase += " (" + Number(net.signal) + "%)"
      parts.push(phrase)
    }
    var net = app.activeNetwork
    if (net !== null && net.securityLabel) parts.push(String(net.securityLabel))
    if (link.generation) parts.push("Wi-Fi " + link.generation)
    if (app.wifiBand.current) parts.push(app.wifiBand.current + " GHz")
    return parts.join(" · ")
  }

  // Thirteen facts about one connection, in columns. As rows they were
  // thirteen lines of name-on-the-left and value-on-the-right, which is the
  // wrong shape for a block describing a single thing: the reader is hunting
  // for one of them rather than reading down.
  //
  // The shape is fixed and only the values move, so the grid is built once and
  // updated in place. Rebuilding it each poll took the page's height with it
  // and threw a reader at the foot of the page back to the top.
  readonly property var factLayout: [
    // The address the world sees leads, then the one this machine holds on the
    // network — and both say which they are, since "IP address" beside a
    // second address is the reader's problem to work out.
    { key: "publicip", label: strings.t("networksection.label.4", "Public IP")},
    { key: "ip", label: strings.t("networksection.label.5", "Local IP")},
    { key: "gateway", label: strings.t("networksection.label.6", "Gateway")},
    // One column is enough now that the servers are stacked rather than run
    // together, so the addressing row is four cells wide and nothing wraps.
    { key: "dns", label: strings.t("networksection.label.7", "Name servers")},
    // Where you are on the network, then everything about the link. The three
    // above are what someone copies out of this card; the rest is what they
    // read, so it sits under a rule and a size down.
    { rule: true },
    { key: "channel", label: strings.t("networksection.label.8", "Channel"), small: true },
    { key: "iface", label: strings.t("networksection.label.9", "Interface"), small: true },
    { key: "connectedFor", label: strings.t("networksection.label.10", "Connected for"), small: true },
    { key: "apFor", label: strings.t("networksection.label.11", "On this access point"), small: true },
    { key: "rx", label: strings.t("networksection.label.12", "Receiving"), small: true },
    { key: "tx", label: strings.t("networksection.label.13", "Sending"), small: true },
    { key: "ping", label: strings.t("networksection.label.14", "Ping to router"), small: true },
    { key: "session", label: strings.t("networksection.label.15", "This session"), small: true },
    { key: "boot", label: strings.t("networksection.label.16", "Since boot"), small: true },
    { key: "retries", label: strings.t("networksection.label.17", "Frames retried"), small: true },
    { key: "beacons", label: strings.t("networksection.label.18", "Beacons missed"), small: true }
  ]

  readonly property var factValues: {
    var dns = app.wifiConnection.dns !== undefined ? app.wifiConnection.dns : []
    return {
      ip: app.wifiConnection.ip
        ? String(app.wifiConnection.ip) + (app.wifiConnection.prefix ? "/" + app.wifiConnection.prefix : "")
        : "—",
      gateway: reading(app.wifiConnection.gateway),
      // Just the address. The datacentre code that answered is a fact about
      // Cloudflare's routing rather than about this connection, and an age
      // beside it asks the reader to think about a number that changes maybe
      // twice a year.
      publicip: app.publicIp.ip ? String(app.publicIp.ip) : "—",
      // One per line. Two addresses joined by a comma read as one long number
      // with a comma in it, which is exactly what an address must not look
      // like.
      dns: dns.length > 0 ? dns.join("\n") : "—",
      channel: link.channel
        ? "ch " + link.channel + (link.width ? " · " + link.width + " MHz" : "") : "—",
      iface: reading(link.iface),
      // The connection, then the association. Keeping only the second and
      // calling it "Connected for" said 12 minutes while the network had been
      // up nearly nine hours: a roam between two radios of the same name
      // resets the driver's clock, and on this mesh that happens all day.
      connectedFor: link.connectedSince
        ? app.formatSpan(Math.floor(Date.now() / 1000) - link.connectedSince) : "—",
      apFor: link.apFor !== undefined && link.apFor !== null
        ? app.formatSpan(link.apFor) : "—",
      rx: app.formatRate(app.wifiRxRate),
      tx: app.formatRate(app.wifiTxRate),
      ping: link.routerPingMs !== undefined && link.routerPingMs !== null
        ? link.routerPingMs.toFixed(link.routerPingMs < 10 ? 1 : 0) + " ms" : "—",
      session: link.sessionRx !== undefined && link.sessionRx !== null
        ? app.formatBytes(link.sessionRx + (link.sessionTx ? link.sessionTx : 0)) : "—",
      // Two figures in one cell, so each says which way it went. A slash left
      // the reader to guess, and the guess is even between "down / up" and
      // "in / out". Plain arrows, not icon-font glyphs, which are not
      // guaranteed to be in the font.
      boot: link.rx !== undefined && link.rx !== null
        ? "\u2193 " + app.formatBytes(link.rx) + "   \u2191 " + app.formatBytes(link.tx) : "—",
      // A share, not the count the driver prints. A count only ever climbs,
      // and it climbs beside a packet count climbing faster: the same
      // unchanged connection read 21 % of frames one minute and 10 % the next.
      retries: link.retryShare !== undefined && link.retryShare !== null
        ? link.retryShare.toFixed(0) + " %" : "—",
      beacons: reading(link.beaconLoss)
    }
  }

  // A strong signal with a fifth of its frames retried is a busy channel
  // rather than a weak one, which is the difference between moving the laptop
  // and moving the router.
  readonly property bool channelBusy: connected
    && link.retryShare !== undefined && link.retryShare !== null && link.retryShare >= 15
    && link.signalDbm !== undefined && link.signalDbm !== null && link.signalDbm > -70

  // Everything on this page moves by the second, and it runs whenever the page
  // is open rather than only while connected: the wired row is a reading too.
  // Asked when the page is built, and again when the window comes back with
  // this page already on it — that second case is the common one, and without
  // it the address would be however old the last visit left it.
  Component.onCompleted: { app.readPublicIp(); app.pollHosts() }
  Connections {
    target: page.app
    function onShownChanged() { if (page.app.shown) { page.app.readPublicIp(); page.app.pollHosts() } }
  }

  Timer {
    interval: 2000
    running: page.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: { page.app.pollWifiLink(); page.app.pollWifiWired() }
  }

  // The networks themselves, which used to arrive with the state document and
  // now have no other source: NetworkManager is asked by this page while it is
  // on screen, and by nothing else. Slower than the link readings above,
  // because a scan is rate-limited and the list moves by the minute rather
  // than by the second.
  Timer {
    interval: 5000
    running: page.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: page.app.pollWifi()
  }

  // ---- what you are on -----------------------------------------------------
  // The name, what the link is, and Disconnect all live *inside* the card with
  // the readings, rather than as a group heading above it: they describe the
  // same one thing, and a heading outside the box read as a label for a
  // separate block that happened to follow.
  Ui.SettingGroup {
    framed: true
    visible: page.connected
      && (page.app.searching !== true
          || page.app.rowMatches(page.wifi.connected + " " + page.linkSummary, "", ""))

    Item {
      width: parent.width
      implicitHeight: Math.max(identity.implicitHeight, leave.implicitHeight)

      Ui.SignalBars {
        id: strength
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        strength: page.app.activeNetwork !== null ? Number(page.app.activeNetwork.signal) : 0
        accented: true
        unit: 1.4
      }

      Column {
        id: identity
        anchors.left: strength.right
        anchors.leftMargin: Style.space(12)
        anchors.right: leave.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: page.wifi.connected !== undefined ? page.wifi.connected : ""
          elide: Text.ElideRight
          color: Ui.Palette.foreground
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: page.linkSummary
          elide: Text.ElideRight
          color: Ui.Palette.muted
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Button {
        id: leave
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: strings.t("networksection.text.4", "Disconnect")
        bordered: true
        foreground: Ui.Palette.foreground
        accent: Ui.Palette.accent
        fontFamily: Ui.Palette.fontFamily
        fontSize: Style.font.caption
        onClicked: page.app.run(["wifi", "disconnect"])
      }
    }

    Rectangle {
      width: parent.width
      implicitHeight: Style.spacing.hairline
      color: Ui.Palette.divider
    }

    Ui.FactGrid {
      layout: page.factLayout
      values: page.factValues
    }
  }

  // Shown only when the link is actually misbehaving.
  //
  // A strip rather than a row with a warning glyph: this is not one of the
  // page's settings and it is not a notice about the machine, it is a remark
  // about the card above it. It was a NoticeRow, which put a warning triangle
  // at icon size out in the page margin and left the sentence floating beside
  // it — a lot of alarm for something the reader can do nothing about except
  // understand it.
  Rectangle {
    id: busy
    visible: page.channelBusy && page.app.searching !== true
    width: parent.width
    implicitHeight: busyText.implicitHeight + Style.space(20)
    radius: Ui.Palette.cardRadius
    // The same card surface as every other block on the page, as the mockup
    // has it — the tint made this the loudest thing on screen.
    color: Ui.Palette.card
    border.width: Style.spacing.hairline
    border.color: Ui.Palette.divider

    Text {
      id: busyText
      anchors.left: parent.left
      anchors.leftMargin: Style.space(14)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.WordWrap
      // The name of the problem leads, in bold rather than in a pill, and the
      // share rather than the count — the same figure the grid above already
      // prints as "Frames retried", so the strip and the card agree.
      textFormat: Text.StyledText
      text: page.link.retryShare !== undefined && page.link.retryShare !== null
        ? strings.t("networksection.channelBusy", "<b>Channel busy</b> \u2014 pages may stall: ")
          + strings.t("networksection.framesRetried",
              "%1 % of frames were retried even though the signal is strong. ")
              .arg(page.link.retryShare.toFixed(0))
          + strings.t("networksection.channelUsed",
              "Something else is using channel %1.").arg(page.link.channel)
        : ""
      color: Ui.Palette.foreground
      font.family: Ui.Palette.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---- the reason people open this page ------------------------------------
  Ui.SettingGroup {
    rowSpacing: Style.space(2)
    framed: page.app.otherNetworks.length > 0
    title: page.connected ? strings.t("networksection.otherNetworks", "Other networks")
                          : strings.t("networksection.networks", "Networks")
    // Nothing while there is a list — the list is the answer. "Looking" only
    // until the first scan lands, and once the network we are on proves one
    // has, an empty list means there is genuinely nothing else here.
    note: !page.radioOn || page.app.otherNetworks.length > 0 ? ""
      : page.app.wifiNetworks.length > 0 ? strings.t("networksection.nothingInRange", "Nothing else in range.")
                                    : strings.t("networksection.looking", "Looking for networks…")
    visible: !searchEmpty && page.radioOn
    // No card around nothing: an empty rounded box reads as a list that failed
    // to load, where the note above it has already given the answer.

    Repeater {
      model: page.radioOn ? page.app.otherNetworks : []
      delegate: Ui.WifiRow {
        required property var modelData
        width: parent.width
        ssid: modelData.ssid
        signalStrength: Number(modelData.signal)
        secured: modelData.secured === true
        band: modelData.band !== undefined ? String(modelData.band) : ""
        security: modelData.securityLabel !== undefined ? String(modelData.securityLabel) : ""
        dbm: modelData.dbm !== undefined && modelData.dbm !== null ? Number(modelData.dbm) : 0
        saved: modelData.saved === true
        active: modelData.active === true
        connecting: page.app.wifiConnecting === modelData.ssid
        prompting: page.app.wifiPrompting === modelData.ssid
        onPromptToggled: page.app.wifiPrompting = (page.app.wifiPrompting === modelData.ssid ? "" : modelData.ssid)
        onConnectRequested: function(password) { page.app.connectWifi(modelData.ssid, password) }
        onDisconnectRequested: page.app.run(["wifi", "disconnect"])
        onForgetRequested: page.app.run(["wifi", "forget", modelData.ssid])
      }
    }
  }

  // ---- settings ------------------------------------------------------------
  Ui.SettingGroup {
    title: strings.t("networksection.title.1", "Wi-Fi")

    Ui.PickerRow {
      label: strings.t("networksection.label.1", "Band")
      visible: !searchHidden && page.connected && page.app.bandOptions().length > 1
      value: page.app.wifiBand.selected !== undefined ? String(page.app.wifiBand.selected) : "auto"
      options: page.app.bandOptions()
      onPicked: function(next) { page.app.run(["wifi", "band", next]) }
    }

    Ui.ChoiceRow {
      label: strings.t("networksection.label.2", "DNS provider")
      value: page.app.group("dns").current
      options: page.app.groupOptions("dns")
      onPicked: function(next) { page.app.run(["menu", "run", "setup.network.dns." + next]) }
    }

  }

  // ---- wired ---------------------------------------------------------------
  // Read, never written: a cable is plugged in or it is not, and nothing here
  // configures one. It earns a place because a page called Network that knows
  // only about Wi-Fi has nothing to say on a docked laptop.
  // Only when something is actually plugged in. A laptop with an empty socket
  // has no wired connection to report, and a row saying so is a row that is
  // there every day to say nothing.
  readonly property var wiredPlugged: {
    var out = []
    for (var i = 0; i < app.wifiWired.length; i++)
      if (app.wifiWired[i].plugged === true) out.push(app.wifiWired[i])
    return out
  }

  Ui.SettingGroup {
    title: strings.t("networksection.title.2", "Wired")
    visible: !searchEmpty && page.wiredPlugged.length > 0

    Repeater {
      model: page.wiredPlugged

      delegate: Ui.ReadingRow {
        required property var modelData
        width: parent.width
        label: String(modelData.device)
        description: modelData.speedMbit
          ? strings.t("networksection.linkAt", "Link at %1 Mbit/s").arg(modelData.speedMbit)
          : strings.t("networksection.cableConnected", "Cable connected")
        value: modelData.connection ? String(modelData.connection) : String(modelData.state)
      }
    }
  }

  // ---- hosts file ----------------------------------------------------------
  // Read here and edited in the reader's own editor. It is root's and
  // hand-written, so this window never writes it.
  readonly property var hostEntries: app.hosts.entries !== undefined ? app.hosts.entries : []
  readonly property int hostTotal: app.hosts.total !== undefined ? app.hosts.total : 0

  Ui.SettingGroup {
    title: strings.t("networksection.title.3", "Hosts file")
    note: page.hostTotal > page.hostEntries.length
      ? strings.t("networksection.showingFirst", "Showing the first %1 of %2.")
          .arg(page.hostEntries.length).arg(page.hostTotal) : ""

    Ui.ActionRow {
      label: strings.t("networksection.label.3", "Local names")
      description: strings.t("networksection.description.1", "Resolved locally, before DNS. An entry here overrides what any DNS server returns.")
      buttonText: strings.t("networksection.buttonText.1", "Edit hosts file…")
      onTriggered: { page.app.run(["hosts", "edit"]); page.app.hide() }
    }

    Ui.DataTable {
      visible: page.hostEntries.length > 0
      columns: [
        { title: strings.t("networksection.title.4", "Name"), weight: 3 },
        { title: strings.t("networksection.title.5", "Address"), weight: 1 }
      ]
      rows: {
        var out = []
        for (var i = 0; i < page.hostEntries.length; i++) {
          var h = page.hostEntries[i]
          out.push({ cells: [
            { text: String(h.name), strong: true },
            { text: String(h.address) }
          ] })
        }
        return out
      }
    }
  }
}
