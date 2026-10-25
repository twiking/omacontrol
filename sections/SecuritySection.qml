import QtQuick
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// What can reach this machine, and how you sign in to it. Nothing here is
// written by this window. The firewall is read, never changed: that takes
// root, and Omarchy has no command of its own to hand it to. The ways of
// signing in are Omarchy's own setup and remove scripts, which edit PAM and
// ask for a password in a terminal of their own.
//
// The table exists for one question nothing else on the desktop answers: is
// anything still behind the ports that were opened? A rule outlives the
// program it was opened for, and a port open to the network with nothing
// listening is a door left unlocked for whatever listens there next. Omarchy's
// own SSH removal closes `limit 22/tcp` and nothing else, so a port 22 opened
// any other way is exactly the rule that stays behind.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property var security: app.security
  readonly property var rules: security.rules !== undefined ? security.rules : []
  readonly property var signIn: security.signIn !== undefined ? security.signIn : ({})
  readonly property bool polled: security.installed !== undefined
  readonly property bool firewallOn: security.enabled === true
  readonly property bool letsAllIn: security.incoming === "ACCEPT"
  readonly property string otherFirewall: security.otherFirewall !== undefined ? security.otherFirewall : ""
  readonly property bool showsRules: security.installed === true && (firewallOn || otherFirewall === "")

  function way(id) {
    return signIn[id] !== undefined ? signIn[id]
      : ({ available: false, active: false, canSetup: false, canRemove: false })
  }

  // The menu entry the button runs, and whether there is one to run.
  function entryFor(id) { return (way(id).active ? "remove" : "setup") + ".security." + id }
  function canRun(id) { return way(id).active ? way(id).canRemove === true : way(id).canSetup === true }

  // A program that bound the port opens and closes it as it starts and stops,
  // and setting up a way in finishes in a terminal this page cannot watch.
  Timer {
    interval: 5000
    running: page.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: page.app.pollSecurity()
  }

  // The name a reader knows a port by. Only the ones an Omarchy machine
  // opens or is likely to: anything else is a number the reader opened
  // themselves and already has a name for.
  readonly property var portNames: ({
    "22": "SSH",
    "53": "DNS",
    "80": "Web",
    "443": "Web",
    "53317": "LocalSend"
  })

  function protocols(list) {
    if (list.indexOf("any") !== -1 || list.length > 1) return "TCP + UDP"
    return list.length === 1 ? String(list[0]).toUpperCase() : ""
  }

  function listeningText(rule) {
    if (rule.container === true) return strings.t("securitysection.containerAt", "Container at %1").arg(rule.to)
    if (rule.by.length > 0) return rule.by.join(", ")
    if (rule.otherUser === true) return strings.t("securitysection.otherUserProgram", "Another user's program")
    if (rule.unnamed === true) return strings.t("securitysection.systemService", "A system service")
    if (rule.localOnly === true) return strings.t("securitysection.onlyThisMachine", "Only this machine")
    return strings.t("securitysection.nothing", "Nothing")
  }

  Ui.SettingGroup {
    title: strings.t("securitysection.title.1", "Firewall")
    visible: !searchEmpty && page.polled

    // What the rules below sit on top of. A firewall that is off, or one
    // whose default lets everything in, makes the list of open ports
    // meaningless, so that is said here rather than under the table.
    Ui.ReadingRow {
      label: strings.t("securitysection.label.1", "Incoming connections")
      description: {
        if (!page.firewallOn && page.otherFirewall !== "") return strings.t("securitysection.otherFirewallRules", "Its rules can only be read with an administrator's password.")
        if (!page.firewallOn) return strings.t("securitysection.everyReachable", "Every program listening on the network can be reached by anyone on it.")
        var parts = []
        if (page.letsAllIn) parts.push(strings.t("securitysection.anythingLetIn", "Anything a rule below does not turn away is let in."))
        if (page.security.dockerOpen === true)
          parts.push(strings.t("securitysection.dockerOpen", "Ports Docker publishes for its containers are open to the network whatever is listed here."))
        return parts.join(" ")
      }
      value: !page.firewallOn && page.otherFirewall !== "" ? strings.t("securitysection.managedBy", "Managed by %1").arg(page.otherFirewall)
        : page.security.installed !== true ? strings.t("securitysection.allNoFirewall", "All · no firewall")
        : !page.firewallOn ? strings.t("securitysection.allFirewallOff", "All · firewall off")
        : page.letsAllIn ? strings.t("securitysection.allAllowed", "All") : ""
    }

    Ui.DataTable {
      visible: page.showsRules
      columns: [
        { title: strings.t("securitysection.title.3", "Port"), weight: 1 },
        { title: strings.t("securitysection.title.4", "For"), weight: 1.4 },
        { title: strings.t("securitysection.title.5", "Protocol"), weight: 1 },
        { title: strings.t("securitysection.title.6", "Allowed from"), weight: 1.6 },
        { title: strings.t("securitysection.title.7", "Listening"), weight: 1.4 }
      ]
      emptyNote: page.security.rulesReadable === false
        ? strings.t("securitysection.rulesUnreadable", "The firewall's rules could not be read.")
        : strings.t("securitysection.noPorts", "No ports are open.")
      rows: {
        var out = []
        for (var i = 0; i < page.rules.length; i++) {
          var r = page.rules[i]
          var from = r.from === "any" ? strings.t("securitysection.anywhere", "Anywhere") : String(r.from)
          if (r.interface !== "") from = r.from === "any" ? strings.t("securitysection.over", "Over %1").arg(r.interface) : strings.t("securitysection.overTwo", "%1 over %2").arg(from).arg(r.interface)
          // Rate-limited: six attempts in thirty seconds from one address and
          // the rest are dropped, which is what keeps a password-guesser off.
          if (r.action === "limit") from += strings.t("securitysection.rateLimited", ", rate-limited")
          out.push({ cells: [
            { text: r.port === "any" ? strings.t("securitysection.allPorts", "All")
                : String(r.port).replace(/:/g, "\u2013").replace(/,/g, ", "), strong: true },
            { text: r.container === true ? strings.t("securitysection.container", "Container")
                : r.app !== "" ? String(r.app)
                : (page.portNames[r.port] !== undefined ? page.portNames[r.port] : ""),
              tag: String(r.comment || "") },
            { text: page.protocols(r.protos) },
            { text: from },
            { text: page.listeningText(r) }
          ] })
        }
        return out
      }
    }
  }

  Ui.SettingGroup {
    title: strings.t("securitysection.title.2", "Signing in")
    visible: !searchEmpty && page.polled

    // Only where there is a reader: the setup cannot do anything without
    // one, and a row offering it on a desktop is a row that can only fail.
    Ui.ActionRow {
      label: strings.t("securitysection.label.2", "Fingerprint")
      visible: !searchHidden && (page.way("fingerprint").available || page.way("fingerprint").active)
        && (page.way("fingerprint").canSetup || page.way("fingerprint").canRemove)
      description: page.way("fingerprint").active
        ? strings.t("securitysection.fingerprintActive", "Set up · unlocks the screen and approves admin prompts")
        : strings.t("securitysection.fingerprintInactive", "Not set up · the reader here can unlock the screen and approve admin prompts")
      buttonText: page.way("fingerprint").active ? strings.t("securitysection.removeButton", "Remove…") : strings.t("securitysection.setupButton", "Set up…")
      actionEnabled: page.canRun("fingerprint")
      onTriggered: { page.app.run(["menu", "run", page.entryFor("fingerprint")]); page.app.hide() }
    }

    Ui.ActionRow {
      label: strings.t("securitysection.label.3", "FIDO2 security key")
      visible: !searchHidden && (page.way("fido2").canSetup || page.way("fido2").canRemove)
      description: page.way("fido2").active
        ? strings.t("securitysection.fido2Active", "Set up · a touch of the key approves admin prompts")
        : strings.t("securitysection.fido2Inactive", "Not set up · a touch of a key can approve admin prompts")
      buttonText: page.way("fido2").active ? strings.t("securitysection.removeButton", "Remove…") : strings.t("securitysection.setupButton", "Set up…")
      actionEnabled: page.canRun("fido2")
      onTriggered: { page.app.run(["menu", "run", page.entryFor("fido2")]); page.app.hide() }
    }

    // Whether it takes a password is the half that matters: a server that
    // takes keys only cannot be guessed into. When a config file in the way
    // could not be read, the page says the server is on and stops there.
    Ui.ActionRow {
      label: strings.t("securitysection.label.4", "SSH server")
      visible: !searchHidden && (page.way("sshd").canSetup || page.way("sshd").canRemove || page.way("sshd").active)
      description: !page.way("sshd").active
        ? strings.t("securitysection.sshdOff", "Off · lets another computer sign in to this one with a key you authorize, and opens its port")
        : page.way("sshd").passwords === false ? strings.t("securitysection.sshdKeysOnly", "On · accepts sign-ins from authorized keys only")
        : page.way("sshd").passwords === true ? strings.t("securitysection.sshdPassword", "On · accepts a password as well as a key")
        : strings.t("securitysection.sshdOn", "On · accepts sign-ins from other computers")
      buttonText: page.way("sshd").active ? strings.t("securitysection.turnOffButton", "Turn off…") : strings.t("securitysection.setupButton", "Set up…")
      actionEnabled: page.canRun("sshd")
      onTriggered: { page.app.run(["menu", "run", page.entryFor("sshd")]); page.app.hide() }
    }
  }
}
