pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../ui" as Ui

// Injected by the window when the page is loaded: the state every
// row reads, and the calls every control makes.
//
// What the coding agent on this machine has been spending. None of it is
// computed here or in lib/: `omarchy-agent-usage-<provider>` already collects
// the whole picture and prints it as one record, and Omarchy's own agents
// panel reads exactly that. A second opinion about someone's rate limits is
// worse than no opinion.
Ui.SectionBody {
  id: page
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property var app: null

  readonly property var limits: app.usage.limits !== undefined ? app.usage.limits : []
  readonly property var days: app.usage.days !== undefined ? app.usage.days : []
  readonly property var models: app.usage.models !== undefined ? app.usage.models : []

  // The busiest day the bars are measured against. On the page root and not on
  // the Item that draws them: a QML binding resolves names against its own
  // object and the root of its file, so a property on an intermediate parent
  // is reachable only by walking `parent.parent.parent`, which is unreadable
  // and breaks the moment anything is nested differently.
  readonly property real busiestDay: {
    var top = 0
    for (var i = 0; i < days.length; i++) top = Math.max(top, Number(days[i].tokens))
    return top
  }

  // The provider gives an instant; what the reader wants is how long they
  // have. Anything past a day becomes a date, because "in 31 hours" is
  // arithmetic they would then have to do themselves.
  function resetWording(iso) {
    var at = Date.parse(iso)
    if (isNaN(at)) return ""
    var minutes = Math.round((at - Date.now()) / 60000)
    if (minutes <= 0) return strings.t("usagesection.resetNow", "now")
    if (minutes < 90) return strings.t("usagesection.resetInMinutes", "in %1 min").arg(minutes)
    if (minutes < 1440) return strings.t("usagesection.resetInHours", "in %1 h").arg(Math.round(minutes / 60))
    return Qt.formatDateTime(new Date(at), "ddd HH:mm")
  }

  readonly property string headerNote: {
    if (app.usage.name === undefined || app.usage.name === "") return ""
    var parts = [app.usage.name]
    if (app.usage.tier !== "") parts.push(app.usage.tier)
    return parts.join(" · ")
  }

  property Component headerControl: Component {
    Ui.Chip {
      text: strings.t("usagesection.text.1", "Refresh")
      onClicked: page.app.run(["usage", "refresh"])
    }
  }

  // Limits move while you watch them, and the whole reason to open this page
  // is to find out whether you are about to run into one.
  Timer {
    interval: 30000
    running: page.app.shown
    repeat: true
    triggeredOnStart: true
    onTriggered: page.app.pollUsage()
  }

  Ui.SettingGroup {
    visible: !searchEmpty && page.app.usage.provider !== undefined && page.app.usage.provider === ""

    Ui.ReadingRow {
      label: strings.t("usagesection.label.1", "No agent usage to report")
      description: strings.t("usagesection.description.1", "Nothing on this machine collects it. Omarchy ships collectors for Claude Code, Codex and Fireworks.")
    }
  }

  // First, because it is the only thing on the page with a deadline attached.
  //
  // A table rather than rows with meters hand-placed in them: a row carrying
  // both a value and a bar needs the two positioned against each other, and
  // the only way to do that in a SettingRow was a hardcoded margin that any
  // change to the text would break. The table already lines up columns.
  Ui.SettingGroup {
    title: strings.t("usagesection.title.1", "Limits")
    note: page.app.usage.updatedAt !== undefined && page.app.usage.updatedAt !== ""
      ? strings.t("usagesection.limitsRead", "The provider's own figures, read %1.")
      .arg(page.app.usage.updatedAt.slice(11, 16)) : ""
    visible: !searchEmpty && page.limits.length > 0

    Ui.DataTable {
      columns: [
        { title: strings.t("usagesection.title.4", "Limit"), weight: 2 },
        { title: strings.t("usagesection.title.5", "Used"), weight: 2 },
        { title: strings.t("usagesection.title.6", "Resets"), weight: 1.4, align: "right" }
      ]
      rows: {
        var out = []
        for (var i = 0; i < page.limits.length; i++) {
          var l = page.limits[i]
          out.push({ cells: [
            { text: l.label, strong: true },
            { text: l.percent + " %", meter: Number(l.percent) / 100,
              // Past four fifths of a limit is the point at which it is worth
              // knowing about rather than merely true.
              warn: Number(l.percent) >= 80 },
            { text: resetWording(l.resetsAt), align: "right" }
          ] })
        }
        return out
      }
    }
  }

  Ui.SettingGroup {
    title: strings.t("usagesection.title.2", "Last 7 days")
    note: page.app.usage.prompts !== null && page.app.usage.prompts !== undefined
      ? strings.t("usagesection.promptsAllTold", "%1 prompts all told ·")
      .arg(page.app.usage.prompts) + strings.t("usagesection.tokensWord", "%1 tokens")
      .arg(page.app.formatTokens(page.app.usage.tokens))
      : ""
    visible: !searchEmpty && page.days.length > 0

    // A bar per day. Tokens rather than messages: a message is not a unit of
    // anything comparable — one can be a word, one can be a repository — and
    // the limits above are counted in tokens too.
    // implicitHeight, not height: a group works out whether a search emptied
    // it by asking its children what they ask for, and a plain Item with only
    // an explicit height asks for nothing — so the whole chart vanished the
    // moment anyone typed in the search box.
    Item {
      width: parent.width
      implicitHeight: Style.space(90)
      height: implicitHeight

      Row {
        anchors.fill: parent
        spacing: Style.space(8)

        Repeater {
          model: page.days

          Item {
            required property var modelData
            width: (parent.width - (page.days.length - 1) * Style.space(8)) / Math.max(1, page.days.length)
            height: parent.height

            Text {
              id: figure
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              text: Number(modelData.tokens) > 0 ? page.app.formatTokens(modelData.tokens) : ""
              color: Ui.Palette.muted
              font.family: Ui.Palette.fontFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              anchors.bottom: label.top
              anchors.bottomMargin: Style.space(4)
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width
              // Measured from the busiest day rather than from a ceiling
              // nobody set: the question is which day was heavy.
              height: {
                var top = page.busiestDay
                var room = parent.height - label.height - figure.height - Style.space(8)
                if (top <= 0) return Style.spacing.hairline
                return Math.max(Style.spacing.hairline, room * Number(modelData.tokens) / top)
              }
              radius: Style.space(2)
              color: Ui.Palette.accent
            }

            Text {
              id: label
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              text: Qt.formatDateTime(new Date(modelData.date + "T12:00:00"), "ddd")
              color: Ui.Palette.muted
              font.family: Ui.Palette.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }
      }
    }
  }

  Ui.SettingGroup {
    title: strings.t("usagesection.title.3", "By model")
    visible: !searchEmpty && page.models.length > 0

    Ui.DataTable {
      columns: [
        { title: strings.t("usagesection.title.7", "Model"), weight: 2.4 },
        { title: strings.t("usagesection.title.8", "Tokens"), weight: 1.2, align: "right" },
        { title: strings.t("usagesection.title.9", "Share"), weight: 1.4 }
      ]
      rows: {
        var out = []
        var busiest = 0
        for (var h = 0; h < page.models.length; h++) busiest = Math.max(busiest, Number(page.models[h].tokens))
        for (var i = 0; i < page.models.length; i++) {
          var m = page.models[i]
          out.push({ cells: [
            { text: m.model, strong: true },
            { text: page.app.formatTokens(m.tokens), align: "right" },
            { text: m.share + " %", meter: busiest > 0 ? Number(m.tokens) / busiest : 0 }
          ] })
        }
        return out
      }
    }
  }
}
