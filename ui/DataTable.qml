pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "." as Local

// The design's one table, used for mounts, for processes and for snapshots.
//
// A table and not a list of rows because the reader is comparing down a
// column — which partition is fullest, what is eating the CPU — and that only
// works if the figures line up. Every column is a share of the width rather
// than a fixed size, so the same table holds a page of process names and a
// page of mount points without either being cut off.
//
// A row is `{ cells: [...] }`, and a cell is either `{ text: }` or
// `{ text:, meter: }` — a figure with the bar that makes it comparable at a
// glance. `strong` marks the cell that names the row, `icon` puts the thing's
// own picture in front of its name, and `mark` is a dot after it: a state that
// belongs to the thing rather than a value of its own, which is why it travels
// with the name instead of taking a column and a heading to explain itself.
//
// `tag` is the same thought when the state needs a word — a grey pill after
// the name, in the size the window puts a reported fact in everywhere else.
// It says what a dot cannot and costs no column: on a list where four rows in
// five carry one, a column would be that word printed a thousand times under
// a heading asking a question nobody had.
// `tagIcon` puts a glyph in the pill before the word, where the kind of
// thing it names is worth recognising before reading it, and `tagIconColor`
// gives the glyph a colour of its own.
//
// A cell can also be a control rather than a reading — `{ action: "Update",
// id:, actionEnabled: }` draws a button in the column and `{ toggle: true,
// on:, id: }` draws a switch, both reporting through `rowAction`. Actions
// otherwise go under the table and act on the selected row, because five
// rows each carrying four buttons is twenty buttons about rows nobody is
// looking at. A control in a cell is for the other case: one thing to do, to
// every row, in the column that is already about it — a switch under State
// says what the state is and sets it, where the word plus a hover icon
// somewhere else on the row said it twice.
Column {
  id: table
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }

  // `{ title:, weight:, align: }`. Weight defaults to 1, align to left;
  // "right" for figures being compared down the column, "center" for a column
  // headed by a mark rather than a word, where there is no word to line the
  // figures up with.
  property var columns: []
  property var rows: []
  // What the cursor is on, and what happens when it is acted on. A table with
  // no `activated` handler is a table you read rather than one you use.
  property int currentRow: -1
  signal activated(int index)
  // Named for the legend at the foot of the window: "End process", "Mount".
  property string actionLabel: ""

  // A column that says `sort: "<key>"` can be pressed to order the table by
  // it. The table never sorts anything — it holds rows someone else built, in
  // whatever order they were handed over, and only the page knows whether a
  // column is bytes, a version or a word. So this reports the press and draws
  // the arrow for whatever the page then says is current.
  property string sortKey: ""
  property bool sortAscending: false
  signal sortRequested(string key)

  // Whether the keyboard can walk the rows.
  //
  // Off for the tables that are readings with an action underneath: there the
  // cursor belongs to the buttons, and sixty rows of process would be sixty
  // stops before the reader reached them. On for a table whose rows are the
  // way into something, where mouse-only would make the page unreachable from
  // the keyboard this window is otherwise driven by.
  property bool navigable: false
  // What ⏎ does to a row, for the legend.
  property string rowActionLabel: strings.t("datatable.rowActionLabel.1", "Open")
  // Drawn at the right of the row the pointer is on, or of the row the cursor
  // is on: the affordance the mouse needs, where a mouse is already looking.
  // The first is a hint and never the only way in — the whole row takes the
  // click, and the keyboard reaches it with ⏎. Any further one is a second
  // action on that row, which nothing else offers: `{ id:, icon:, label: }`,
  // reported through `rowAction`.
  // These draw over the end of the row, which is also where a cell control
  // in the last column sits: a table wants one or the other, or the icons
  // land on top of the button on exactly the rows that have one.
  property var rowActions: []
  signal rowAction(int index, string id)
  property string emptyNote: strings.t("datatable.emptyNote.1", "Nothing here.")

  // A cell given `tree: { depth, lines, last, folded }` draws btop's guides
  // in front of its text: an elbow into the row from its parent, and a line
  // down through it for every ancestor with a sibling still to come (`lines`,
  // one per level above the row's own). `folded` is true or false on a row
  // with children and absent on one without, and the chevron it draws reports
  // the press here — the table never hides a row itself, because what a
  // folded row stands for is the page's to say.
  signal foldRequested(int index)

  width: parent ? parent.width : 0
  spacing: 0

  // The row delegates are slots that outlive the rows in them. Handed the
  // array directly, the Repeater threw away and rebuilt every row on every
  // change, which a list re-read every two seconds pays for in full each
  // time — six hundred rows of a process tree, every poll.
  // Slots only come and go at the end, so a poll that changes figures and
  // not the count rebuilds nothing.
  ListModel { id: slots }

  function syncSlots() {
    var want = table.rows ? table.rows.length : 0
    if (slots.count > want) slots.remove(want, slots.count - want)
    while (slots.count < want) slots.append({ slot: slots.count })
  }

  onRowsChanged: syncSlots()
  Component.onCompleted: syncSlots()

  readonly property real totalWeight: {
    var total = 0
    for (var i = 0; i < columns.length; i++) total += (columns[i].weight || 1)
    return Math.max(1, total)
  }

  readonly property real gap: Style.space(12)
  readonly property real pad: Style.space(14)

  // Anything painted over the card here is mixed down to an opaque colour
  // first. Both ends of the table are drawn in two pieces — rounded where
  // they carry the card's corner, square where they meet the rest of it — and
  // a translucent colour drawn twice is not the same colour: the overlap came
  // out a shade off, which read as a band with a lid on it. It is the header
  // as much as the last row; the header's seam was simply fainter.
  function overCard(colour) {
    return Qt.tint(Qt.tint(Local.Palette.background, Local.Palette.card), colour)
  }

  function rowFill(alpha) { return overCard(Local.Palette.tint(alpha)) }

  // A table whose columns come and go with what it is showing has a frame
  // where the rows have changed and the headings have not, or the other way
  // about, and a cell then asks about a column that is not there. Nothing
  // reaches the reader either way; unguarded it is a type error per cell per
  // frame, in the journal, which is the only place they show up at all.
  function columnWidth(index) {
    var column = columns[index]
    if (column === undefined) return 0
    var available = table.width - table.pad * 2 - table.gap * (columns.length - 1)
    return Math.max(0, available * (column.weight || 1) / table.totalWeight)
  }

  // Header and rows share one rounded outline, so the header reads as the top
  // of the table rather than as a band floating above it.
  //
  // `clip` is not what keeps them inside it. Clipping is to the bounding box
  // and knows nothing about a radius, so a filled header and a hovered last
  // row both painted square into the rounded corners — the card's outline ran
  // *behind* a block of colour at each end. The two ends round themselves
  // instead, and square off the edge that meets the rest of the table.
  Rectangle {
    width: table.width
    implicitHeight: header.height + body.implicitHeight
    radius: Local.Palette.cardRadius
    color: Local.Palette.card
    border.width: Style.spacing.hairline
    border.color: Local.Palette.divider
    clip: true

    Rectangle {
      id: header
      width: parent.width
      height: Style.space(26)
      radius: Local.Palette.cardRadius
      color: table.overCard(Local.Palette.shade(0.05))

      // Square again where the first row meets it.
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.radius
        color: parent.color
      }

      Row {
        anchors.left: parent.left
        anchors.leftMargin: table.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: table.gap

        Repeater {
          model: table.columns

          delegate: Item {
            id: headerCell
            required property var modelData
            required property int index

            readonly property string sortBy: String(modelData.sort || "")
            readonly property bool sorted: sortBy !== "" && sortBy === table.sortKey

            width: table.columnWidth(index)
            height: header.height

            // The arrow rides inside the heading rather than beside it, so a
            // column that is being sorted by does not step sideways when the
            // direction changes — and so the heading keeps the width the
            // figures under it were lined up against.
            Text {
              textFormat: Text.PlainText
              anchors.fill: parent
              anchors.verticalCenter: parent.verticalCenter
              // On a right-aligned heading the arrow goes in front of the
              // word: the column's right edge is what the figures under it
              // are lined up against, and an arrow hanging off it reads as
              // belonging to the heading beside it instead.
              text: {
                if (!headerCell.sorted) return headerCell.modelData.title || ""
                var arrow = table.sortAscending ? "\u2191" : "\u2193"
                return headerCell.modelData.align === "right"
                  ? arrow + "  " + (headerCell.modelData.title || "")
                  : (headerCell.modelData.title || "") + "  " + arrow
              }
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: headerCell.modelData.align === "right" ? Text.AlignRight
                : headerCell.modelData.align === "center" ? Text.AlignHCenter : Text.AlignLeft
              color: headerCell.sorted || headerPress.containsMouse
                ? Local.Palette.foreground : Local.Palette.muted
              font.family: Local.Palette.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.capitalization: Font.AllUppercase
              font.letterSpacing: Style.space(1)
            }

            MouseArea {
              id: headerPress
              anchors.fill: parent
              enabled: headerCell.sortBy !== ""
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: table.sortRequested(headerCell.sortBy)
            }
          }
        }
      }
    }

    Column {
      id: body
      y: header.height
      width: parent.width
      spacing: 0

      Repeater {
        model: slots

        delegate: Rectangle {
          id: tableRow
          required property int index
          readonly property var rowData: table.rows[index] !== undefined ? table.rows[index] : ({})

          readonly property bool current: index === table.currentRow

          width: body.width
          implicitHeight: Style.space(30)
          height: implicitHeight
          // The last row carries the bottom of the card, so its band is
          // rounded there and nowhere else.
          radius: index === table.rows.length - 1 ? Local.Palette.cardRadius : 0
          color: current ? table.rowFill(0.16)
                         : (rowMouse.containsMouse ? table.rowFill(0.08) : "transparent")

          // Square again where the row above meets it. Declared first so the
          // divider between rows still draws over it.
          Rectangle {
            visible: parent.radius > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: parent.radius
            color: parent.color
          }

          // Between rows, not around them: a border on every row would draw
          // a line above the first one, immediately under the header's own
          // edge, and the two together read as a double rule.
          Rectangle {
            visible: tableRow.index > 0
            width: parent.width
            height: Style.spacing.hairline
            color: Local.Palette.divider
          }

          // Above the row's own click area, which is declared last and would
          // otherwise take every press: a cell holding a button has to be
          // pressable, and nothing else in here accepts a click, so the rest
          // of the row goes on behaving as one target.
          Row {
            z: 1
            anchors.left: parent.left
            anchors.leftMargin: table.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: table.gap

            // By column rather than by cell, for the same reason the rows are
            // slots: a cell delegate keyed to the row's array would be rebuilt
            // whenever the row is, which is every poll.
            Repeater {
              model: table.columns.length

              delegate: Item {
                id: cell
                required property int index
                readonly property var cellData: {
                  var cells = tableRow.rowData.cells
                  return cells !== undefined && cells[index] !== undefined && cells[index] !== null
                    ? cells[index] : ({})
                }

                readonly property var column: table.columns[index] !== undefined
                  ? table.columns[index] : ({})
                readonly property var tree: cellData.tree !== undefined && cellData.tree !== null
                  ? cellData.tree : null

                width: table.columnWidth(index)
                // By the text even where the cell holds a button, which is
                // taller: a Row is as tall as its tallest child and lines the
                // rest up at the top of it, so one measured cell would leave
                // every figure beside it riding above the button's centre.
                // The button overflows its cell instead, evenly, and the row
                // has the height for it.
                implicitHeight: Math.max(cellText.implicitHeight,
                                         cellTag.visible ? cellTag.implicitHeight : 0)

                // The full height of the row rather than of the cell, so a
                // line carried down through a row meets the one in the next
                // and the tree reads as one drawing rather than as a stack of
                // separate marks.
                Item {
                  id: cellTree
                  readonly property real step: Style.space(14)
                  readonly property int depth: cell.tree !== null ? Number(cell.tree.depth) : 0
                  visible: cell.tree !== null
                  anchors.left: parent.left
                  y: (parent.height - tableRow.height) / 2
                  height: tableRow.height
                  // A column for every level, then one for the chevron, kept
                  // on a leaf too so that siblings' names start together.
                  width: visible ? (depth + 1) * step : 0

                  Repeater {
                    model: cellTree.depth

                    delegate: Item {
                      required property int index
                      readonly property bool own: index === cellTree.depth - 1
                      readonly property bool through: {
                        var tree = cell.tree
                        if (tree === null) return false
                        if (own) return tree.last !== true
                        return tree.lines !== undefined && tree.lines[index] === true
                      }

                      x: index * cellTree.step
                      width: cellTree.step
                      height: cellTree.height

                      Rectangle {
                        visible: parent.own || parent.through
                        x: Math.round(parent.width / 2)
                        width: Style.spacing.hairline
                        height: parent.through ? parent.height : Math.round(parent.height / 2)
                        color: Local.Palette.shade(0.3)
                      }

                      Rectangle {
                        visible: parent.own
                        x: Math.round(parent.width / 2)
                        y: Math.round(parent.height / 2)
                        width: parent.width - x
                        height: Style.spacing.hairline
                        color: Local.Palette.shade(0.3)
                      }
                    }
                  }

                  Local.GlyphIcon {
                    readonly property bool foldable: cell.tree !== null
                      && cell.tree.folded !== undefined && cell.tree.folded !== null
                    visible: foldable
                    x: cellTree.depth * cellTree.step
                    anchors.verticalCenter: parent.verticalCenter
                    width: cellTree.step
                    height: cellTree.step
                    glyph: foldable && cell.tree.folded === true ? "" : ""
                    size: Style.font.caption
                    color: foldMouse.containsMouse ? Local.Palette.accent : Local.Palette.muted

                    // Its own click, taken before the row's: folding a branch
                    // is not choosing the process it hangs from.
                    MouseArea {
                      id: foldMouse
                      anchors.fill: parent
                      anchors.margins: -Style.space(3)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function(mouse) {
                        mouse.accepted = true
                        table.foldRequested(tableRow.index)
                      }
                    }
                  }
                }

                // The figure first, then the bar in what is left of the
                // column. Stacked, the two sat a few pixels apart in a row
                // this short and the bar read as a strikethrough across its
                // own number.
                // An application's icon is how it is recognised — faster than
                // its name, and the reason a list of sixty-five can be scanned
                // at all. A missing one leaves the gap rather than a
                // placeholder, so the names stay in one column.
                Image {
                  id: cellIcon
                  visible: String(cell.cellData.icon || "") !== ""
                  anchors.left: cellTree.right
                  anchors.leftMargin: cell.cellData.indent === true ? Style.space(16) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  width: visible ? Style.space(18) : 0
                  height: width
                  sourceSize.width: width * 2
                  sourceSize.height: width * 2
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  source: {
                    var name = String(cell.cellData.icon || "")
                    if (name === "") return ""
                    if (name.charAt(0) === "/") return "file://" + name
                    return Quickshell.iconPath(name, true)
                  }
                }

                Text {
                  id: cellText
                  textFormat: Text.PlainText
                  readonly property real lead: cellTree.width + cellIcon.width + anchors.leftMargin
                  anchors.left: cellIcon.visible ? cellIcon.right : cellTree.right
                  // A cell that belongs to the row above is stepped in from
                  // it, which says so without a word and without a column of
                  // its own. Indentation is the only thing in a table that
                  // can say "part of that" at a glance.
                  anchors.leftMargin: cellIcon.visible ? Style.space(8)
                    : (cell.cellData.indent === true ? Style.space(16)
                       : (cellTree.visible ? Style.space(4) : 0))
                  anchors.verticalCenter: parent.verticalCenter
                  // A figure with a bar beside it is sized to the figure;
                  // one on its own has the column.
                  width: Math.max(0, meter.visible ? Math.min(implicitWidth + Style.space(4),
                                                              parent.width * 0.45)
                    : (String(cell.cellData.mark || "") !== "" || cellTag.visible
                       ? Math.min(implicitWidth, parent.width - lead - Style.space(14)
                                  - (cellTag.visible ? cellTag.width : 0))
                       : parent.width - lead))
                  text: cell.cellData.text !== undefined ? String(cell.cellData.text) : ""
                  elide: Text.ElideRight
                  horizontalAlignment: cell.column.align === "right" ? Text.AlignRight
                    : cell.column.align === "center" ? Text.AlignHCenter : Text.AlignLeft
                  color: cell.cellData.strong === true || tableRow.current
                    ? Local.Palette.foreground : Local.Palette.muted
                  font.family: Local.Palette.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: cell.cellData.strong === true
                }

                Local.Tag {
                  id: cellTag
                  visible: String(cell.cellData.tag || "") !== ""
                  anchors.left: cellText.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(cell.cellData.tag || "")
                  icon: String(cell.cellData.tagIcon || "")
                  iconColor: cell.cellData.tagIconColor !== undefined ? cell.cellData.tagIconColor : null
                  // Whatever the name beside it leaves, with the name always
                  // keeping up to half the cell: a short name gives the tag
                  // the room to be read whole, and a long one is not crowded
                  // out by it.
                  width: {
                    var room = parent.width - cellText.lead - Style.space(14)
                    var name = Math.min(cellText.implicitWidth, room / 2)
                    return Math.min(implicitWidth, Math.max(Style.space(48), room - name))
                  }
                  // The machine is reporting it, not the reader having done
                  // something: grey, not the accent.
                  accented: false
                }

                Text {
                  textFormat: Text.PlainText
                  visible: String(cell.cellData.mark || "") !== ""
                  anchors.left: cellText.right
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(cell.cellData.mark || "")
                  color: Local.Palette.accent
                  font.family: Local.Palette.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Meter {
                  id: meter
                  anchors.left: cellText.right
                  anchors.leftMargin: Style.space(7)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  visible: cell.cellData.meter !== undefined && cell.cellData.meter !== null
                  value: cell.cellData.meter !== undefined && cell.cellData.meter !== null
                    ? cell.cellData.meter : 0
                  warn: cell.cellData.warn === true
                }

                // The two controls are loaded only into the cells that hold
                // one. Every other cell of every table carried both, built
                // and hidden, which on a tree of six hundred rows was two
                // thousand switches and buttons nobody could see.
                //
                // The same switch the pages use for a setting, at the size
                // it is everywhere else: a table row has the height for it,
                // and a scaled-down one lands its track and knob on
                // fractional pixels.
                Loader {
                  active: cell.cellData.toggle === true
                  // Where the column says, the way a figure in it would be:
                  // a column of switches only reads as a column if they all
                  // start at the same edge.
                  x: cell.column.align === "right" ? parent.width - width : 0
                  anchors.verticalCenter: parent.verticalCenter
                  sourceComponent: ToggleSwitch {
                    checked: cell.cellData.on === true
                    foreground: Local.Palette.foreground
                    accent: Local.Palette.accent
                    // The hover ring is drawn outside the track, so at the
                    // kit's own padding the control stands taller than the
                    // row and the ring crosses the rules above and below it.
                    cursorPad: Style.space(3)
                    onToggled: table.rowAction(tableRow.index, String(cell.cellData.id || ""))
                  }
                }

                // The same button the pages use for an action anywhere else,
                // so one that turns up in a table is recognised as the thing
                // it already is. Tighter than the kit's own padding, because
                // it has to sit inside a row height the figures set.
                Loader {
                  active: String(cell.cellData.action || "") !== ""
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  sourceComponent: Button {
                    enabled: cell.cellData.actionEnabled !== false
                    opacity: enabled ? 1 : 0.4
                    text: String(cell.cellData.action || "")
                    bordered: true
                    foreground: Local.Palette.foreground
                    accent: Local.Palette.accent
                    fontFamily: Local.Palette.fontFamily
                    fontSize: Style.font.caption
                    verticalPadding: Style.space(3)
                    onClicked: table.rowAction(tableRow.index, String(cell.cellData.id || ""))
                  }
                }
              }
            }
          }

          // Hover on a table row is already the row's own highlight, so the
          // icon appears rather than fades: half-visible chrome on a row that
          // is not the one being pointed at reads as a disabled control.
          Row {
            visible: table.navigable && table.rowActions.length > 0
              && (rowMouse.containsMouse || tableRow.current)
            // Above the row's own click area, which is declared after it and
            // would otherwise take every press: a sibling later in the file is
            // a sibling on top, and the icons would look live and do nothing.
            z: 1
            anchors.right: parent.right
            anchors.rightMargin: table.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Repeater {
              model: table.rowActions

              delegate: Item {
                id: actionCell
                required property var modelData

                width: Style.space(22)
                height: Style.space(22)

                Local.GlyphIcon {
                  anchors.fill: parent
                  glyph: String(actionCell.modelData.icon || "")
                  size: Style.font.bodySmall
                  color: iconMouse.containsMouse ? Local.Palette.accent
                    : (tableRow.current ? Local.Palette.foreground : Local.Palette.muted)
                }

                // Its own click, taken before the row's: the icon is the one
                // place on the row that does something other than open it.
                MouseArea {
                  id: iconMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    mouse.accepted = true
                    table.rowAction(tableRow.index, String(actionCell.modelData.id || ""))
                  }
                }
              }
            }
          }

          // Only where the keyboard walks the rows. A cursor registers itself
          // with the window whether or not it is enabled, and the window
          // re-sorts its rows on every registration — paid once per row of a
          // table that was never going to take the cursor at all.
          Loader {
            anchors.fill: parent
            z: -1
            active: table.navigable
            sourceComponent: Local.NavCursor {
              navKeys: [{ key: "⏎", label: table.rowActionLabel }]
              searchText: {
                var cells = tableRow.rowData.cells || []
                return cells.length > 0 ? String(cells[0].text || "") : ""
              }
              // The window sets `current` on a registered row itself, so this
              // follows the cursor rather than declaring where it is: a
              // binding here would be overwritten the first time the keyboard
              // moved, and the row under the cursor would look like no row at
              // all.
              onCurrentChanged: if (current) table.currentRow = tableRow.index
              onNavActivate: {
                table.currentRow = tableRow.index
                table.activated(tableRow.index)
              }
            }
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              table.currentRow = tableRow.index
              table.activated(tableRow.index)
            }
          }
        }
      }

      // An empty table still has to say so, or the outline reads as a table
      // that has not loaded.
      Text {
        textFormat: Text.PlainText
        visible: table.rows.length === 0
        width: body.width - table.pad * 2
        x: table.pad
        topPadding: Style.space(10)
        bottomPadding: Style.space(10)
        text: table.emptyNote
        wrapMode: Text.WordWrap
        color: Local.Palette.muted
        font.family: Local.Palette.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
