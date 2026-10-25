pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// Every application the launcher and the Omarchy menu show, and what this
// desktop has been told to do with each — the workspace it opens on, whether
// it starts at login, the role it fills. None of that is set here: it is set
// on the page that owns it, and this page is where you find out that anything
// is set at all, which is the question no other page answers.
//
// It reports rather than configures, so it polls for itself and is not in the
// state document, like Disk and Processes.
Ui.SectionBody {
  id: root
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property var items: app.apps !== undefined && app.apps !== null ? app.apps : []

  property int selectedApp: -1

  // The one application being looked at, by window class. Empty is the list.
  //
  // A drill-in rather than a panel over the table: twelve settings inline
  // would open forty rows down a list of sixty-five, and the reader would
  // lose the row they came from. Opening the application instead gives the
  // settings the whole page, which is the shape every other page here has.
  property string openClass: ""

  readonly property var openApp: {
    for (var i = 0; i < items.length; i++)
      if (String(items[i].class) === openClass) return items[i]
    return null
  }

  // The rule as the state document holds it — every field, defaulted — so a
  // application with no rule yet opens on the same rows as one that has one.
  readonly property var openRule: {
    if (openClass === "") return null
    var rules = app.workspaceRules
    for (var i = 0; i < rules.length; i++)
      if (String(rules[i].class) === openClass) return rules[i]
    return { "class": openClass,
             name: openApp !== null ? openApp.name : openClass,
             workspace: "", silent: false, shown: "tiled", monitor: "",
             pin: false, width: 0, height: 0, center: false,
             noInitialFocus: false, idleInhibit: false, noScreenShare: false,
             desktop: openApp !== null ? openApp.id + ".desktop" : "",
             autostart: false, ours: false, theirs: false }
  }

  // Uninstalling is the one thing on this page that a second click cannot
  // undo, and the bin is a small target beside a gear — so it asks first, and
  // names what it is about to remove. pacman asks again in the terminal, with
  // the list of what goes with it; this one is about having clicked the wrong
  // icon on the wrong row.
  function askUninstall(entry) {
    if (entry === null || entry === undefined) return
    var made = entry.kind === "web" || entry.kind === "tui"
    app.askConfirm((made ? strings.t("appssection.deleteAsk", "Delete %1?")
                         : strings.t("appssection.uninstallAsk", "Uninstall %1?")).arg(entry.name),
                   made ? strings.t("appssection.delete", "Delete")
                        : strings.t("appssection.uninstall", "Uninstall"), function() {
      app.run(["apps", "remove", entry.id])
      // A launcher made here is a file and an icon: nothing to type, nothing
      // to approve, so the window stays and the list simply loses a row.
      // A package needs a terminal, and this window holds the keyboard.
      if (!made) app.hide()
      else openClass = ""
    })
  }

  readonly property var displays: (app.monitors !== undefined ? app.monitors : [])
    .filter(function(m) { return m.connected !== false })

  // Every application, always. A filter over a list this shape was three
  // chips to say what one glance down the table already says.
  readonly property var shown: items


  // The header is where you are, so on an application it is the application,
  // with the way back beside its name.
  // The name comes from the rule when the list has not come back yet — a poll
  // arrives after the page is built, and a header that reads "aether" for a
  // second before becoming "Aether" is the window looking like it is guessing.
  readonly property string headerTitle: creating === "webapp"
    ? strings.t("appssection.newWebApp", "New web app")
    : creating === "tui" ? strings.t("appssection.newTui", "New TUI")
    : openClass === "" ? ""
    : (openApp !== null ? String(openApp.name)
       : (openRule !== null && String(openRule.name || "") !== "" ? String(openRule.name)
          : openClass))
  readonly property bool headerBack: openClass !== "" || creating !== ""
  function headerBackTriggered() { openClass = ""; creating = "" }

  // Only on an application, where it says something the list cannot: a count
  // of what is on screen is a count the reader can see.
  // Asked here rather than in a terminal. Omarchy's own scripts prompt when
  // given nothing and take every answer as an argument when given everything,
  // so the window can ask in its own fields and still leave the making of the
  // launcher — the favicon fetch, the icon cache, the desktop entry and its
  // escaping — to them.
  //
  // "webapp", "tui", or empty for the list. It shares the drill-in with an
  // open application: they are the same thing, one page showing one subject.
  property string creating: ""

  property string newStyle: "float"
  // Most sites have an icon worth using, and the script fetches it, so asking
  // for one is asking for something the reader rarely has to answer.
  property bool newSiteIcon: true

  // Every rule the fields carry, asked of all of them at once.
  readonly property bool newValid: creating === ""
    || (nameField.error === ""
        && (creating === "webapp"
            ? urlField.error === "" && (newSiteIcon || iconField.error === "")
            : commandField.error === "" && iconField.error === ""))

  // A field says what is wrong with it once it has been left. Pressing a dead
  // button is the other way of being finished with all of them.
  function touchAll() {
    nameField.touched = true
    urlField.touched = true
    commandField.touched = true
    iconField.touched = true
  }

  function startCreating(kind) {
    openClass = ""
    nameField.text = ""; urlField.text = ""; commandField.text = ""; iconField.text = ""
    nameField.touched = false; urlField.touched = false
    commandField.touched = false; iconField.touched = false
    newStyle = "float"
    newSiteIcon = true
    creating = kind
  }

  property Component headerControl: Component {
    Row {
      spacing: Style.space(8)

      Ui.Chip {
        visible: root.openClass === "" && root.creating === ""
        text: strings.t("appssection.text.1", "New web app")
        onClicked: startCreating("webapp")
      }

      Ui.Chip {
        visible: root.openClass === "" && root.creating === ""
        text: strings.t("appssection.text.2", "New TUI")
        onClicked: startCreating("tui")
      }
    }
  }

  readonly property string headerNote: creating !== "" ? ""
    : openClass !== "" && openApp !== null
    && openApp.running === true ? strings.t("appssection.runningNow", "running now") : ""


  Timer {
    interval: 5000
    running: root.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: root.app.pollApps()
  }

  // ---------------------------------------------------------- a new one
  //
  // A form, not a page of settings. Settings rows put the label on the left
  // and the control on the right because each row is one thing you change;
  // filling in four blanks in order is the other shape — label over field,
  // fields the width of the form, one button at the foot.
  //
  // Each field carries its own rule and says what is wrong under itself, once
  // it has been left; the button is dead until every rule is satisfied, so a
  // wrong form cannot be sent at all.
  Ui.SettingGroup {
    visible: root.creating !== ""

    Column {
      width: parent.width
      spacing: Style.space(16)

      Ui.FormField {
        id: nameField
        label: strings.t("appssection.label.1", "Name")
        placeholder: root.creating === "webapp" ? "Linear" : "Lazydocker"
        error: text.trim() === "" ? strings.t("appssection.errNameEmpty", "Give it a name.")
          : text.indexOf("/") >= 0 ? strings.t("appssection.errNameSlash", "A name cannot contain a slash.")
          : ""
        onAccepted: root.creating === "webapp" ? urlField.focusInput() : commandField.focusInput()
      }

      Ui.FormField {
        id: urlField
        visible: root.creating === "webapp"
        label: strings.t("appssection.label.2", "Address")
        placeholder: "https://example.com"
        error: text.trim() === "" ? strings.t("appssection.errAddressEmpty", "Give it an address.")
          : /\s/.test(text.trim()) ? strings.t("appssection.errAddressSpaces", "An address cannot contain spaces.")
          : ""
        onAccepted: root.newSiteIcon ? createButton.clicked() : iconField.focusInput()
      }

      Ui.FormField {
        id: commandField
        visible: root.creating === "tui"
        label: strings.t("appssection.label.3", "Command")
        placeholder: "lazydocker"
        error: text.trim() === "" ? strings.t("appssection.errCommandEmpty", "Give it a command to run.") : ""
        onAccepted: iconField.focusInput()
      }

      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: root.creating === "tui"

        Text {
          textFormat: Text.PlainText
          text: strings.t("appssection.text.3", "Shown as")
          color: Ui.Palette.foreground
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ButtonGroup {
          options: [
            { value: "float", label: strings.t("appssection.label.11", "Floating")},
            { value: "tile", label: strings.t("appssection.label.12", "Tiled")}
          ]
          value: root.newStyle
          foreground: Ui.Palette.foreground
          accent: Ui.Palette.accent
          onChanged: function(next) { root.newStyle = next }
        }
      }

      // Above the field it governs, so the field appearing under it reads as
      // what switching it off asked for.
      //
      // The bare switch, not the kit's Toggle: that one is a whole settings
      // row and draws its own bordered surface, which in a form reads as a
      // box around one question among four that have none.
      Row {
        spacing: Style.space(10)
        visible: root.creating === "webapp"

        ToggleSwitch {
          id: siteIconSwitch
          checked: root.newSiteIcon
          foreground: Ui.Palette.foreground
          accent: Ui.Palette.accent
          onToggled: root.newSiteIcon = !root.newSiteIcon
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: siteIconSwitch.verticalCenter
          text: strings.t("appssection.text.4", "Use the icon from the site")
          color: Ui.Palette.foreground
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.bodySmall

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.newSiteIcon = !root.newSiteIcon
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: root.creating === "tui" || !root.newSiteIcon

        Ui.FormField {
          id: iconField
          label: strings.t("appssection.label.4", "Icon")
          placeholder: "https://…/icon.png"
          error: text.trim() === "" ? strings.t("appssection.errIconEmpty", "Give it an icon.") : ""
          onAccepted: createButton.clicked()
        }

        Text {
          textFormat: Text.PlainText
          text: strings.t("appssection.text.5", "Find icons at dashboardicons.com")
          color: Ui.Palette.accent
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.caption
          font.underline: linkMouse.containsMouse

          MouseArea {
            id: linkMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.app.run(["apps", "icons"]); root.app.hide() }
          }
        }
      }

      Row {
        spacing: Style.space(10)

        Button {
          id: createButton
          text: root.creating === "webapp"
            ? strings.t("appssection.createWebApp", "Create web app")
            : strings.t("appssection.createTui", "Create TUI")
          bordered: true
          enabled: root.newValid
          opacity: enabled ? 1 : 0.4
          foreground: Ui.Palette.foreground
          accent: Ui.Palette.accent
          fontFamily: Ui.Palette.fontFamily
          onClicked: {
            // Pressing an empty form marks every field, which is what turns a
            // dead button into an answer rather than a wall.
            if (!enabled) { touchAll(); return }
            if (root.creating === "webapp")
              root.app.run(["apps", "create", "webapp", nameField.text.trim(), urlField.text.trim(),
                       root.newSiteIcon ? "" : iconField.text.trim()])
            else
              root.app.run(["apps", "create", "tui", nameField.text.trim(), commandField.text.trim(),
                       root.newStyle, iconField.text.trim()])
            root.creating = ""
          }
        }

        Button {
          text: strings.t("appssection.text.6", "Cancel")
          foreground: Ui.Palette.foreground
          accent: Ui.Palette.accent
          fontFamily: Ui.Palette.fontFamily
          onClicked: root.creating = ""
        }
      }
    }
  }

  // What a launcher made here was made with. A packaged application has none
  // of this — there is no address behind Firefox — so the group is only for
  // the two kinds this window can make, and each row saves by running the
  // installer again with the rest as they stand.
  Ui.SettingGroup {
    id: madeGroup
    visible: root.openClass !== "" && root.openApp !== null
      && (root.openApp.kind === "web" || root.openApp.kind === "tui")
    title: root.openApp !== null && root.openApp.kind === "web"
      ? strings.t("appssection.webApp", "Web app") : strings.t("appssection.tui", "TUI")

    // Read through the group's id rather than `parent`: a row's parent is the
    // group's content item, not the group.
    readonly property var made: root.openApp !== null && root.openApp.madeWith !== undefined
      && root.openApp.madeWith !== null ? root.openApp.madeWith : ({})

    // Each carries its own Save. A setting row commits when it loses focus,
    // which is right for a switch-sized change and wrong here: nothing on
    // screen says an address has been written, and an address half typed and
    // clicked away from would be written as it stood.
    Ui.TextRow {
      label: strings.t("appssection.label.5", "Address")
      visible: !searchHidden && root.openApp !== null && root.openApp.kind === "web"
      buttonText: strings.t("appssection.buttonText.1", "Save")
      value: String(madeGroup.made.url || "")
      onCommitted: function(next) {
        if (next.trim() !== "") root.app.run(["apps", "edit", root.openApp.id, "url", next.trim()])
      }
    }

    Ui.TextRow {
      label: strings.t("appssection.label.6", "Command")
      visible: !searchHidden && root.openApp !== null && root.openApp.kind === "tui"
      buttonText: strings.t("appssection.buttonText.2", "Save")
      value: String(madeGroup.made.command || "")
      onCommitted: function(next) {
        if (next.trim() !== "") root.app.run(["apps", "edit", root.openApp.id, "command", next.trim()])
      }
    }

    Ui.ChoiceRow {
      label: strings.t("appssection.label.7", "Shown as")
      visible: !searchHidden && root.openApp !== null && root.openApp.kind === "tui"
      options: [
        { value: "float", label: strings.t("appssection.label.13", "Floating")},
        { value: "tile", label: strings.t("appssection.label.14", "Tiled")}
      ]
      value: String(madeGroup.made.style || "float")
      onPicked: function(next) { root.app.run(["apps", "edit", root.openApp.id, "style", next]) }
    }

    Ui.TextRow {
      label: strings.t("appssection.label.8", "Icon")
      description: strings.t("appssection.description.1", "A name, or the address of an image to fetch.")
      buttonText: strings.t("appssection.buttonText.3", "Save")
      value: String(madeGroup.made.icon || "")
      onCommitted: function(next) {
        if (next.trim() !== "") root.app.run(["apps", "edit", root.openApp.id, "icon", next.trim()])
      }
    }
  }

  // What the launcher is comes before what the window manager does with it —
  // the address behind a web app is the application, and a workspace rule is
  // a preference about it. A line rather than only a heading, because the two
  // halves are different kinds of thing.
  Rectangle {
    visible: root.openClass !== "" && root.openApp !== null
      && (root.openApp.kind === "web" || root.openApp.kind === "tui")
    width: parent.width
    height: 1
    color: Ui.Palette.hairline
  }

  // ------------------------------------------------------------- one app
  Ui.SettingGroup {
    visible: root.openClass !== ""

    Ui.ActionRow {
      label: strings.t("appssection.label.9", "Open it now")
      visible: !searchHidden && root.openApp !== null && root.openApp.running !== true
      buttonText: strings.t("appssection.buttonText.4", "Open")
      onTriggered: if (root.openApp !== null) { root.app.run(["apps", "launch", root.openApp.id]); root.app.hide() }
    }

    // Uninstalling asks for a password and names every package going with it,
    // so it is pacman's own prompt in a terminal that asks — this window never
    // makes that decision on a button press.
    Ui.ActionRow {
      label: strings.t("appssection.label.10", "The application itself")
      description: root.openApp !== null && (root.openApp.kind === "web" || root.openApp.kind === "tui")
        ? strings.t("appssection.deleteLauncherDesc", "Deletes the launcher and its icon. Nothing else is removed.")
        : strings.t("appssection.uninstallPackageDesc", "Removes the package it came from, with whatever else depends on it.")
      buttonText: root.openApp !== null && (root.openApp.kind === "web" || root.openApp.kind === "tui")
        ? strings.t("appssection.deleteButton", "Delete…")
        : strings.t("appssection.uninstallButton", "Uninstall…")
      onTriggered: askUninstall(root.openApp)
    }
  }

  Ui.AppRules {
    visible: root.openClass !== ""
    app: root.app
    displays: root.displays
    modelData: root.openRule !== null ? root.openRule : ({})
    // The header carries the application's name; a group titled with it again
    // would say it twice, a line apart.
    title: ""
    note: strings.t("appssection.note.1", "Applies to every window this application opens.")
  }

  // ---------------------------------------------------------- every app
  Ui.SettingGroup {
    visible: root.openClass === "" && root.creating === ""
    // No heading and no note: the page name says what these are, and the
    // dot explains itself the moment the reader opens a row that has one.

    Ui.DataTable {
      columns: [
        { title: strings.t("appssection.title.1", "Application"), weight: 2.6 },
        { title: strings.t("appssection.title.2", "Type"), weight: 0.9 },
        { title: strings.t("appssection.title.3", "Version"), weight: 1 },
        { title: strings.t("appssection.title.4", "Opens on"), weight: 1.2 },
        { title: strings.t("appssection.title.5", "At login"), weight: 1 },
        { title: strings.t("appssection.title.6", "Default for"), weight: 1.4 }
      ]
      navigable: true
      rowActionLabel: strings.t("appssection.rowActionLabel.1", "Open")
      rowActions: [
        { id: "open", icon: "\uf013", label: strings.t("appssection.label.15", "Settings")},
        { id: "uninstall", icon: "\uf1f8", label: strings.t("appssection.label.16", "Uninstall")}
      ]
      onRowAction: function(index, id) {
        if (index < 0 || index >= root.shown.length) return
        if (id === "uninstall") { askUninstall(root.shown[index]); return }
        root.selectedApp = index
        root.openClass = String(root.shown[index].class)
      }
      currentRow: root.selectedApp
      emptyNote: strings.t("appssection.emptyNote.1", "Looking for applications…")
      rows: {
        var out = []
        for (var i = 0; i < root.shown.length; i++) {
          var a = root.shown[i]
          out.push({ cells: [
            // The dot rides with the name: most of what can be set for an
            // application shows in no column here — a floating size, a pin, no
            // screen share — so this says that anything was, beside the thing
            // it is about rather than in a column of its own.
            //
            // A role is not a setting made here: being the default browser
            // says nothing about how the window opens, so the dot follows the
            // rule rather than `bound`.
            { text: a.name, strong: true, icon: a.icon,
              mark: (a.ruled === true || a.autostart === true) ? "\u25cf" : "" },
            // Only for the two kinds this window can make: a packaged
            // application has nothing to say here, and "Native" on sixty rows
            // would be a column saying nothing sixty times.
            { text: a.kind === "web" ? strings.t("appssection.webApp", "Web app")
                     : a.kind === "tui" ? strings.t("appssection.tui", "TUI") : "" },
            { text: a.version !== undefined && a.version !== null ? a.version : "" },
            { text: a.workspace !== "" ? strings.t("appssection.workspace", "Workspace %1").arg(a.workspace) : "" },
            { text: a.autostart === true ? strings.t("appssection.starts", "Starts") : "" },
            { text: (a.roles !== undefined ? a.roles : []).join(", ") }
          ] })
        }
        return out
      }
      // Opening the application is what a row does, so a click and Enter both
      // go there; the gear says so, and the bin beside it is the only other
      // thing a row can do.
      onActivated: function(index) {
        root.selectedApp = index
        if (index >= 0 && index < root.shown.length) root.openClass = String(root.shown[index].class)
      }
    }
  }
}
