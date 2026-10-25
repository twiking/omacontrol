import QtQuick
import qs.Commons
import "." as Local

// A row that is entirely a link: the whole width is the target, with whatever
// the source calls the date at the far end. For lists where every row goes
// somewhere and none of them has a second thing you could do to it — a button
// per row would be one button per row doing what the row already does.
Local.NavRow {
  id: linkRow
  Translations { id: strings; directory: Qt.resolvedUrl("../i18n") }
  property string value: ""
  // Unread rows carry a star. It is both the mark and the way to clear it:
  // there is nothing else a reader would want to do to a star, so making it
  // the button saves a second control that would mean the same thing.
  property bool unread: false
  signal triggered()
  signal starred()

  // Not Space: the window routes Space and Enter to the same signal, so a
  // legend offering "Space — Mark read" would open the article instead. The
  // step keys are the ones a row can tell apart.
  navKeys: linkRow.unread
    ? [{ key: "↵", label: strings.t("linkrow.label.1", "Open")}, { key: "→", label: strings.t("linkrow.label.2", "Mark read")}]
    : [{ key: "↵", label: strings.t("linkrow.label.3", "Open")}]
  onNavActivate: linkRow.triggered()
  onNavStep: function(delta) { if (delta > 0 && linkRow.unread) linkRow.starred() }

  implicitHeight: Math.max(title.implicitHeight, stamp.implicitHeight) + Style.space(10)

  // Both states carry a mark, so the headlines all start in the same place: a
  // column of titles that shifts by ten pixels depending on whether you have
  // read them is worse than a wasted indent. An empty slot did that job too,
  // but it left the eye no confirmation that a row *was* read, only the
  // absence of a star — and absence reads as "not loaded yet" as easily as it
  // reads as "done".
  //
  // The two are deliberately unalike in weight: the star is the accent and is
  // a button; the article is dim and inert. Same size, so the column stays a
  // column.
  Text {
    id: mark
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(16)
    text: linkRow.unread ? "\uf005" : "\uf1ea"
    color: linkRow.unread
      ? (markMouse.containsMouse ? Local.Palette.foreground : Local.Palette.accent)
      : Local.Palette.shade(0.32)
    font.family: Local.Palette.fontFamily
    // A notch above caption. The star is a solid shape and reads at any size;
    // the article has ruled lines inside it and turns into a smudge at ten
    // pixels. The larger of the two sizes governs, so the column stays even.
    font.pixelSize: Style.font.bodySmall

    MouseArea {
      id: markMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      // Only the star does anything. The article is a state, not a control —
      // there is no reason to want a headline back as unread.
      enabled: linkRow.unread
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: linkRow.starred()
    }
  }

  Text {
    id: title
    textFormat: Text.PlainText
    anchors.left: mark.right
    anchors.right: stamp.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    text: linkRow.label
    elide: Text.ElideRight
    color: mouse.containsMouse ? Local.Palette.accent : Local.Palette.foreground
    // An unread headline is the only bold thing in the list, which is what
    // makes "two new" legible without counting stars.
    font.family: Local.Palette.fontFamily
    font.pixelSize: Style.font.body
    font.bold: linkRow.unread
    font.underline: mouse.containsMouse
  }

  Text {
    id: stamp
    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: linkRow.value
    color: Local.Palette.muted
    font.family: Local.Palette.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  MouseArea {
    id: mouse
    // From the title onward. Filling the whole row would put this over the
    // star and take its clicks, since the later sibling wins.
    anchors.left: title.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: linkRow.triggered()
  }
}
