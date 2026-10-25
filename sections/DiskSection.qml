pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// What the disks are holding. Nothing on this page is a setting — a partition
// is not something you set — so it leads with the one figure everyone came
// for and offers the handful of things there are to *do* as actions.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property var mounts: app.disk.mounts !== undefined ? app.disk.mounts : []
  readonly property var health: app.disk.health !== undefined ? app.disk.health : ({})
  readonly property var drives: app.disk.drives !== undefined ? app.disk.drives : []
  readonly property var root: app.disk.root !== undefined ? app.disk.root : ({})
  readonly property var swap: app.disk.swap !== undefined ? app.disk.swap : []
  readonly property var snapshots: app.disk.snapshots !== undefined ? app.disk.snapshots : []
  readonly property var breakdown: app.diskBreakdown !== null ? app.diskBreakdown : []

  property int selectedMount: -1

  // On the page root, not on the card that reads it: a QML binding resolves
  // names against its own object and the root of the file it is in, and
  // nothing in between. Declared on the Column, this was a ReferenceError that
  // only showed up as a note that never appeared.
  readonly property bool breakdownHasHome: {
    for (var i = 0; i < breakdown.length; i++)
      if (breakdown[i].label === "Home") return true
    return false
  }

  function breakdownLabel(label) {
    return label === "System" ? strings.t("disksection.bkSystem", "System")
       : label === "Packages" ? strings.t("disksection.bkPackages", "Packages")
       : label === "Home" ? strings.t("disksection.bkHome", "Home")
       : label === "Snapshots" ? strings.t("disksection.bkSnapshots", "Snapshots")
       : label
  }


  // How much of a drive is in use, summed over the filesystems on it.
  //
  // Free comes from the filesystems rather than from subtracting used from
  // the drive's capacity: btrfs keeps metadata in reserve and a 1.0 TB drive
  // with 259 GB used has 720 GB free, not 741. The figure has to be the one
  // `df` would give, because that is the one every other tool gives.
  function driveSpace(drive) {
    var used = 0
    var free = 0
    var known = false
    for (var i = 0; i < mounts.length; i++) {
      var m = mounts[i]
      if (String(m.disk || "") !== String(drive.device)) continue
      if (m.used === null || m.used === undefined) continue
      used += Number(m.used)
      free += Number(m.free || 0)
      known = true
    }
    return { used: used, free: free, total: used + free, known: known }
  }

  // Spelled the way the socket is named rather than the way the kernel spells
  // it: "nvme" on a row that also says SATA reads as jargon.
  function connectionLabel(drive) {
    var names = { "nvme": "NVMe", "sata": "SATA", "usb": "USB", "ata": "ATA",
                  "sas": "SAS", "mmc": "SD / eMMC" }
    var tran = String(drive.transport || "")
    if (tran === "") return drive.removable === true ? strings.t("disksection.removable", "Removable") : "\u2014"
    var label = names[tran] !== undefined ? names[tran] : tran.toUpperCase()
    return drive.removable === true ? label + strings.t("disksection.removableSuffix", "  \u00b7  removable") : label
  }

  // What the drive is, then what it is doing, then the two figures that only
  // mean anything against a whole session.
  //
  // Capacity, connection and kind are facts that never move, so they are
  // facts rather than a line under the drive's name: a card's title should
  // name the thing, and everything that merely describes it reads better in a
  // grid where the reader can find the one they want by its label.
  //
  // Busy is the figure that answers "is the disk why this feels slow": a
  // drive can sit at 100 % while moving almost nothing, which is what
  // thousands of small files look like.
  readonly property var driveFacts: [
    { key: "capacity", label: strings.t("disksection.label.6", "Capacity")},
    { key: "connection", label: strings.t("disksection.label.7", "Connection")},
    { key: "kind", label: strings.t("disksection.label.8", "Kind")},
    { key: "encryption", label: strings.t("disksection.label.9", "Encryption")},
    { rule: true },
    { key: "reading", label: strings.t("disksection.label.10", "Reading")},
    { key: "writing", label: strings.t("disksection.label.11", "Writing")},
    { key: "busy", label: strings.t("disksection.label.12", "Busy")},
    // One cell, beside what it is the history of. Read and written are the
    // same measurement over a longer window, and two cells on a rule of their
    // own gave a pair of background figures a third of the card.
    { key: "totals", label: strings.t("disksection.label.13", "Since start-up"), small: true }
  ]

  function driveValues(drive) {
    return {
      capacity: drive.size !== undefined && Number(drive.size) > 0
        ? app.formatBytes(drive.size) : "—",
      connection: connectionLabel(drive),
      kind: drive.rotational === true ? strings.t("disksection.hardDisk", "Hard disk")
                              : strings.t("disksection.solidState", "Solid state"),
      // The answer people want is yes or no, so it is said that way and the
      // word "encrypted" is left to do its job.
      encryption: drive.encrypted === true ? strings.t("disksection.encrypted", "Encrypted")
                                 : strings.t("disksection.notEncrypted", "Not encrypted"),
      reading: drive.read !== null && drive.read !== undefined
        ? app.formatRate(Number(drive.read)) : "—",
      writing: drive.write !== null && drive.write !== undefined
        ? app.formatRate(Number(drive.write)) : "—",
      busy: drive.busy !== null && drive.busy !== undefined
        ? Number(drive.busy) + " %" : "—",
      totals: drive.readTotal !== null && drive.readTotal !== undefined
        ? strings.t("disksection.ioTotals", "%1 read  ·  %2 written")
          .arg(app.formatBytes(drive.readTotal)).arg(app.formatBytes(drive.writeTotal))
        : "—"
    }
  }

  // Whether unmounting this is something a person would ever mean.
  //
  // Yes for what you can take away — a stick, a card, a USB disk — and for
  // anything mounted where a file manager or a hand puts it. No for the
  // filesystems the running system is built out of, whatever drive they are
  // on: a laptop with its home on a second internal disk still cannot have
  // that disk pulled out from under it.
  function canUnmount(row) {
    if (row.removable === true) return true
    var mount = String(row.mount || "")
    if (mount === "") return false
    var places = row.mounts !== undefined ? row.mounts : [mount]
    for (var i = 0; i < places.length; i++) {
      var at = String(places[i])
      if (at === "/" || at === "/home" || at === "/boot" || at === "/boot/efi"
          || at === "/var" || at === "/usr" || at === "/nix") return false
      // Everything the system needs is named above; what is left is worth
      // unmounting only where the mounting happened outside fstab.
      if (!(at.indexOf("/run/media/") === 0 || at.indexOf("/media/") === 0
            || at.indexOf("/mnt/") === 0)) return false
    }
    return true
  }

  // The table's rows, which are not one-to-one with the filesystems.
  //
  // A btrfs layout mounts one filesystem in several places — `/`, `/home`,
  // the log and package directories — and they share a single pool. Printed
  // as four rows they were four drives that happened to be the same size and
  // the same 26 % full, which is the opposite of what is true. Printed as one
  // row with the paths run together they were unreadable.
  //
  // So the filesystem is the row that carries the figures, and the other
  // places it is mounted are stepped in underneath it with no figures of
  // their own — the indent says they are part of the row above, and the empty
  // Size column says the space has already been counted.
  readonly property var mountRows: {
    var out = []
    for (var i = 0; i < mounts.length; i++) {
      var m = mounts[i]
      out.push({ mount: String(m.mount || ""), source: m, child: false })
      var places = m.mounts !== undefined ? m.mounts : []
      for (var j = 1; j < places.length; j++)
        out.push({ mount: String(places[j]), source: m, child: true })
    }
    return out
  }

  // Nothing in the header. It carried the drive's name and how full it was,
  // which is now the first thing inside the card a few lines below — and a
  // header that repeats the page is a header nobody reads twice.

  // Mounting a stick is something that happens while you are looking at the
  // page, so the page keeps itself current — but the figures move slowly, and
  // five seconds is often enough for a `df`.
  Timer {
    interval: 5000
    running: page.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: page.app.pollDisk()
  }

  // Asked once, when the page opens. Walking directories is the only way to
  // answer it, and doing that on the poll would spin the disk for as long as
  // the reader looks at the page.
  Component.onCompleted: app.fetchDiskBreakdown()

  // One card per drive, in the shape the battery and the connected network
  // use: what the thing is, said in its own name across the top, how full it
  // is under that, and the readings about it below a rule — rather than a
  // heading outside a box, which reads as a label for a separate block that
  // happened to follow.
  //
  // The space belongs *in* the card. Standing on its own above them, "720 GB
  // free" was a figure with no subject: on a machine with a second drive
  // there was nothing to say which one it was about.
  //
  // Per drive and not per machine for the same reason. A laptop with an SSD
  // for the system and a second disk for everything else is two answers to
  // "is the disk busy", and one figure covering both hides the drive that is
  // grinding behind the one that is idle. On the usual machine there is one
  // card and it reads as the page's own summary.
  Repeater {
    model: page.drives

    delegate: Ui.SettingGroup {
      required property var modelData

      readonly property var drive: modelData
      readonly property var space: page.driveSpace(modelData)
      // The breakdown answers for the root filesystem, so it is only ever
      // drawn on the drive the system is on. Another drive gets the one thing
      // that is true of it: how much of it is gone.
      readonly property var slices: modelData.system === true ? page.breakdown : []
      // Free is in the key as well as in the bar. The bar's last stretch is
      // the answer to the question people actually came with, and leaving it
      // as the only unlabelled thing on the card made it read as a gap rather
      // than as space.
      readonly property var legend: slices.length > 0
        ? slices.concat([{ label: strings.t("disksection.label.14", "Free"), bytes: space.free, free: true }]) : []

      framed: true
      visible: !searchEmpty

      Item {
        width: parent.width
        implicitHeight: Math.max(identity.implicitHeight, badge.implicitHeight)

        // The same shape the battery card opens with: the thing pictured, its
        // name beside it, and a badge saying which one it is. What the drive
        // *is* — how big, how attached, whether it spins — moved down to the
        // facts, where a fact that never changes belongs; the name is the only
        // part of it anyone uses to mean this drive rather than that one.
        Ui.GlyphIcon {
          id: mark
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          glyph: ""
          size: Style.font.iconLarge
          color: Ui.Palette.muted
        }

        Column {
          id: identity
          anchors.left: mark.right
          anchors.leftMargin: Style.space(12)
          anchors.right: badge.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          // The drive's own name, because that is what is printed on it and
          // what a shop, a receipt and a warranty all call it. A drive with
          // no model to give falls back to the name the kernel uses.
          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: String(drive.model || "") !== "" ? String(drive.model) : String(drive.device)
            elide: Text.ElideRight
            color: Ui.Palette.foreground
            font.family: Ui.Palette.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
        }

        // Which drive this is, in the only terms that matter on a machine
        // with two: the one the system is on, or one you can unplug.
        Ui.Tag {
          id: badge
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: drive.system === true ? strings.t("disksection.systemDrive", "System drive")
              : (drive.removable === true ? strings.t("disksection.removable", "Removable")
                                            : String(drive.device))
          accented: drive.system === true
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(12)

        // Over the bar and small, because it is the bar's caption rather than
        // the card's headline — the card is named by the drive now, and a
        // second display-sized figure under that name competed with it.
        //
        // "Usable", because this total is not the Capacity in the facts below
        // and the two sitting a centimetre apart otherwise read as the card
        // contradicting itself. A filesystem keeps some of a drive for
        // itself — btrfs holds its metadata in duplicate, ext4 reserves a
        // share for root — and that part is neither your files nor space you
        // can put a file in. On this drive it is 19 GB of a terabyte.
        Text {
          textFormat: Text.PlainText
          text: space.known
            ? strings.t("disksection.usedOf", "%1 used of %2 usable")
                .arg(page.app.formatBytes(space.used))
                .arg(page.app.formatBytes(space.total))
            : strings.t("disksection.notMounted", "Nothing on this drive is mounted")
          color: Ui.Palette.muted
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        // The walk takes tens of seconds on a home directory of any size, and
        // a headline figure with an empty gap under it for that long reads as
        // a card that has finished loading and has nothing more to say.
        Text {
          textFormat: Text.PlainText
          visible: drive.system === true && page.app.diskBreakdown === null
          text: strings.t("disksection.text.1", "Working out what is using the space…")
          color: Ui.Palette.muted
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        // One bar divided into what is holding the space, rather than five
        // bars or a pie: the question is what share of one drive each thing
        // has, and shares of one thing read best as one length cut up.
        Row {
          id: bar
          width: parent.width
          height: Style.space(14)
          visible: space.known
          // The card showing through between the slices. Two neighbouring
          // steps of one ramp can always be mistaken for one block; a gap
          // cannot, and it costs a pixel of a bar that is a thousand wide.
          spacing: Style.space(2)

          // The gaps come out of the bar before anything is scaled to it, or
          // the last slice is pushed off the end by the width of all of them.
          readonly property int gaps: slices.length
          readonly property real span: space.total > 0
            ? Math.max(0, width - gaps * spacing) / Number(space.total) : 0

          Repeater {
            model: slices

            Rectangle {
              required property var modelData
              required property int index

              width: bar.span * Math.max(0, Number(modelData.bytes))
              height: parent.height
              color: Ui.Palette.sliceColour(index)
            }
          }

          // A drive with no breakdown to draw still has a used share, and it
          // is drawn in one piece rather than left as an empty track.
          Rectangle {
            visible: slices.length === 0
            width: bar.span * Math.max(0, Number(space.used))
            height: parent.height
            color: Ui.Palette.sliceColour(0)
          }

          // Whatever the named slices do not account for is free.
          Rectangle {
            width: Math.max(0, parent.width - bar.gaps * bar.spacing - accounted)
            height: parent.height
            color: Ui.Palette.shade(0.12)

            readonly property real accounted: {
              if (slices.length === 0) return bar.span * Math.max(0, Number(space.used))
              var total = 0
              for (var i = 0; i < slices.length; i++)
                total += bar.span * Math.max(0, Number(slices[i].bytes))
              return total
            }
          }
        }

        // The key under the bar, not on it: a slice thin enough to matter is
        // never wide enough to hold its own name.
        Flow {
          width: parent.width
          spacing: Style.space(14)
          visible: legend.length > 0

          Repeater {
            model: legend

            Row {
              required property var modelData
              required property int index
              spacing: Style.space(6)

              // A swatch rather than a dot: a colour is easier to match
              // against the bar over a shape with some area to it.
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(14)
                height: Style.space(10)
                radius: Style.space(2)
                color: modelData.free === true ? Ui.Palette.shade(0.12)
                     : Ui.Palette.sliceColour(index)
              }

              Text {
                textFormat: Text.PlainText
                text: page.breakdownLabel(modelData.label) + " " + page.app.formatBytes(modelData.bytes)
                color: Ui.Palette.muted
                font.family: Ui.Palette.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
        }

        // Said rather than left to be inferred from a slice that is not
        // there. A `du` that ran out of time is not a small number, it is no
        // number, and the space it could not account for is in System.
        Text {
          textFormat: Text.PlainText
          visible: drive.system === true && page.app.diskBreakdown !== null
            && slices.length > 0 && !page.breakdownHasHome
          width: parent.width
          text: strings.t("disksection.text.2", "Your home directory took too long to measure, so its space is counted under System.")
          wrapMode: Text.WordWrap
          color: Ui.Palette.muted
          font.family: Ui.Palette.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        width: parent.width
        implicitHeight: Style.spacing.hairline
        color: Ui.Palette.divider
      }

      Ui.FactGrid {
        layout: page.driveFacts
        values: page.driveValues(drive)
      }
    }
  }

  Ui.SettingGroup {
    title: strings.t("disksection.title.1", "Mounts")

    Ui.DataTable {
      columns: [
        { title: strings.t("disksection.title.5", "Mount"), weight: 2.2 },
        { title: strings.t("disksection.title.6", "Device"), weight: 1.6 },
        { title: strings.t("disksection.title.7", "Size"), weight: 1, align: "right" },
        { title: strings.t("disksection.title.8", "Used"), weight: 1.3 },
        { title: strings.t("disksection.title.9", "Type"), weight: 1 }
      ]
      currentRow: page.selectedMount
      emptyNote: strings.t("disksection.emptyNote.1", "Nothing mounted that this window can see.")
      rows: {
        var out = []
        for (var i = 0; i < page.mountRows.length; i++) {
          var m = page.mountRows[i].source
          var mounted = String(m.mount || "") !== ""
          var pct = m.percent !== null && m.percent !== undefined ? Number(m.percent) : null

          // The same filesystem, one directory further in. Named and placed,
          // and nothing else: every figure on it belongs to the row above.
          if (page.mountRows[i].child) {
            out.push({ cells: [
              { text: page.mountRows[i].mount, indent: true },
              { text: "" },
              { text: "" },
              { text: "" },
              // Said in the word btrfs itself uses, because that is the word
              // anyone who goes looking for it will find.
              { text: m.fstype === "btrfs" ? "subvolume"
                                           : strings.t("disksection.alsoMounted", "also mounted") }
            ] })
            continue
          }

          out.push({ cells: [
            // A partition with no mount point has its label to go by, and
            // failing that its device — it is still the row the reader is
            // looking for, so it is named rather than left blank.
            { text: mounted ? page.mountRows[i].mount
                            : (String(m.label || "") !== "" ? m.label : m.device),
              strong: true },
            { text: m.device, strong: mounted },
            { text: page.app.formatBytes(m.size), align: "right" },
            mounted && pct !== null
              ? { text: pct + " %", meter: pct / 100, warn: pct >= 90 }
              : { text: strings.t("disksection.text.5", "not mounted")},
            { text: m.fstype }
          ] })
        }
        return out
      }
      onActivated: function(index) { page.selectedMount = index }
    }

    // The actions the table's selection governs, under it rather than one per
    // row: five rows each carrying four buttons is twenty buttons, nineteen
    // of which are about a row the reader is not looking at.
    Row {
      spacing: Style.space(8)

      Ui.Chip {
        readonly property var picked: page.selectedMount >= 0 && page.selectedMount < page.mountRows.length
          ? page.mountRows[page.selectedMount] : null
        // Not offered on a subvolume. Unmounting one takes a directory out
        // from under whatever is using it while the drive it is on stays
        // mounted, which is not what "Unmount" means to anyone reading it.
        //
        // And not offered on the filesystems the machine is running from.
        // Nobody unmounts `/`: udisks refuses it, and `/boot` comes away
        // without complaint and leaves the next kernel update with nowhere to
        // write. A button whose best outcome is an error it cannot show is
        // worse than no button.
        visible: picked !== null && !picked.child
          && (String(picked.mount || "") === "" || page.canUnmount(picked.source))
        text: picked !== null && String(picked.mount || "") !== "" ? strings.t("disksection.unmount", "Unmount") : strings.t("disksection.mount", "Mount")
        onClicked: {
          if (picked === null) return
          page.app.run(["disk", String(picked.mount || "") !== "" ? "unmount" : "mount",
                   picked.source.path])
        }
      }

      Ui.Chip {
        readonly property var picked: page.selectedMount >= 0 && page.selectedMount < page.mountRows.length
          ? page.mountRows[page.selectedMount] : null
        visible: picked !== null && String(picked.mount || "") !== ""
        text: strings.t("disksection.text.3", "Open in files")
        onClicked: if (picked !== null) page.app.run(["disk", "open", picked.mount])
      }
    }
  }

  // Swap earns a place on a *disk* page because on most machines that is
  // where it is: a swap file is part of the used space in the bar at the top
  // of this page. On a machine using zram it is compressed memory and takes
  // no disk at all, which is the distinction the Kind column is there to make.
  Ui.SettingGroup {
    title: strings.t("disksection.title.2", "Swap")
    visible: !searchEmpty && page.swap.length > 0
    note: strings.t("disksection.note.1", "Space the system uses when memory runs short.")

    Ui.DataTable {
      columns: [
        { title: strings.t("disksection.title.10", "Where"), weight: 2.4 },
        { title: strings.t("disksection.title.11", "Kind"), weight: 1.8 },
        { title: strings.t("disksection.title.12", "Size"), weight: 1, align: "right" },
        { title: strings.t("disksection.title.13", "Used"), weight: 1.3 }
      ]
      rows: {
        var out = []
        for (var i = 0; i < page.swap.length; i++) {
          var s = page.swap[i]
          var pct = Number(s.size) > 0 ? Number(s.used) / Number(s.size) * 100 : 0
          out.push({ cells: [
            { text: String(s.name || ""), strong: true },
            { text: s.zram === true ? strings.t("disksection.compressedMemory", "Compressed memory")
                                    : (s.kind === "file"
                                       ? strings.t("disksection.fileOnDrive", "File on the drive")
                                       : strings.t("disksection.partition", "Partition")) },
            { text: page.app.formatBytes(s.size), align: "right" },
            { text: Math.round(pct) + " %", meter: pct / 100, warn: pct >= 90 }
          ] })
        }
        return out
      }
    }
  }

  // Only when the drive answered. A health panel that is always empty — which
  // is what a machine where smartctl needs a password gives you — teaches the
  // reader to stop looking at it.
  Ui.SettingGroup {
    title: strings.t("disksection.title.3", "Health")
    visible: !searchEmpty && page.health.passed !== undefined && page.health.passed !== null

    Ui.ReadingRow {
      label: strings.t("disksection.label.1", "SMART")
      value: page.health.passed === true ? strings.t("disksection.smartPassed", "Passed") : strings.t("disksection.smartFailing", "Failing")
    }

    Ui.ReadingRow {
      visible: page.health.temperature !== undefined && page.health.temperature !== null
      label: strings.t("disksection.label.2", "Temperature")
      value: page.health.temperature + " °C"
    }

    Ui.ReadingRow {
      visible: page.health.wear !== undefined && page.health.wear !== null
      label: strings.t("disksection.label.3", "Wear")
      description: strings.t("disksection.description.1", "How much of the drive's rated write life is used up.")
      value: page.health.wear + " %"
    }

    Ui.ReadingRow {
      visible: page.health.hours !== undefined && page.health.hours !== null
      label: strings.t("disksection.label.4", "Powered on")
      value: page.app.formatDuration(Number(page.health.hours) * 3600)
    }

    Ui.ReadingRow {
      visible: page.health.written !== undefined && page.health.written !== null
      label: strings.t("disksection.label.5", "Written")
      value: page.app.formatBytes(page.health.written)
    }
  }

  Ui.SettingGroup {
    title: strings.t("disksection.title.4", "Snapshots")
    visible: !searchEmpty && page.snapshots.length > 0
    note: strings.t("disksection.note.2", "Taken by snapper, and by Omarchy before it updates packages.")

    Ui.DataTable {
      columns: [
        { title: strings.t("disksection.title.14", "No."), weight: 0.6 },
        { title: strings.t("disksection.title.15", "Kind"), weight: 1 },
        { title: strings.t("disksection.title.16", "Description"), weight: 2.6 },
        { title: strings.t("disksection.title.17", "Taken"), weight: 1.4, align: "right" }
      ]
      rows: {
        var out = []
        for (var i = 0; i < page.snapshots.length; i++)
          out.push({ cells: [
            { text: "#" + page.snapshots[i].number, strong: true },
            { text: page.snapshots[i].kind },
            { text: page.snapshots[i].description },
            { text: page.snapshots[i].date, align: "right" }
          ] })
        return out
      }
    }

    Ui.Chip {
      text: strings.t("disksection.text.4", "Snapshot now")
      onClicked: page.app.run(["disk", "snapshot"])
    }
  }
}
