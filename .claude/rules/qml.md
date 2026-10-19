---
paths:
  - "*.qml"
  - "ui/*.qml"
  - "sections/*.qml"
  - "ui/*.js"
---

# QML traps that cost real time here

> **Read this when:** you edit any `.qml` file — `SettingsWindow.qml`, `Panel.qml`, `Service.qml`, `ui/` or `sections/`.

## QML traps that cost real time here

- **Don't import `QtQuick.Controls` alongside `qs.Ui`.** Both export `Button`
  and `TextField`; the ambiguity fails the whole file, and the shell reports it
  as the useless "File name case mismatch".
- **Never write a bare `Color`.** Qt 6.12 gave QtQuick a `Color` value type,
  and an unversioned `import QtQuick` wins the name over `qs.Commons`'s
  singleton: every colour comes back undefined, the window draws black on
  black, and the journal says only `Cannot read property 'text' of undefined`.
  Pages and `ui/` read colours from `Palette`; `Palette.qml` and `Panel.qml`
  read the theme as `Commons.Color`, through `import qs.Commons as Commons`.
  On Qt 6.11 the bare name still works, so nothing here will show it.
- **The `Palette` singleton needs an explicit directory import.** Files in
  `ui/` use `import "." as Local` and `Local.Palette.foreground`; the implicit
  directory import does not resolve it here.
- **Pages get `app` through `Loader.setSource(url, { app: root })`**, not a
  plain `source` assignment — otherwise every binding evaluates against a null
  window on load.
- **`summon` on a bar-widget+panel plugin routes to the widget**, not the panel.
  That is why the window is not a `panel` entry point: it lives in the service,
  and the bar widget stands in for it with `open`/`close`/`opened`.
- **Icon glyphs are not guaranteed.** Signal-strength codepoints render as tofu
  in this Nerd Font, so signal bars are drawn with rectangles. Omarchy's own
  icon font is resolved by *file* — `fc-list ":family=$family" file` lists the
  candidates and `fc-query -f '%{charset}'` scores each one against the
  codepoints the live menu actually asks for — and loaded with a `FontLoader`,
  because more than one file can claim the family and only some of them have
  the glyphs.
- **`forceActiveFocus()` on a `FocusScope` gives focus back to the child that
  had it last** — which, when a field has just finished editing, is that field.
  The scope holds a `keySink` Item for focus to land on instead.
- **A `TextField` emits `accepted` without accepting the event.** An Enter left
  to bubble reaches the window, which reads it as "activate this row" and drops
  straight back into the field just left. Handle Enter at the field and accept
  it there.
- **A `Repeater` is a visible child with no height**, sitting among the rows it
  made. Counting children to decide whether a group is empty must skip it, or
  every heading survives a search that removed everything under it.
- **A binding read from inside its own change handler is the previous value.**
  `onSearchTermChanged` reading `sidebarRows` got the list for the term before,
  and switched to a page that no longer matched. Recompute from the source, not
  from the binding you are invalidating.
- **A property whose name begins with "on" collides with the signal-handler
  syntax.** `property var onYes` on the confirm dialog took its assignment and
  kept null: the dialog opened, Enter closed it, and the thing it was asking
  about never happened — which looks exactly like a confirm that worked.
- **A property named `<x>Changed` collides with `<x>`'s change signal.**
  `hyprChanged` beside `hypr` is a duplicated name; Qt 6's qmllint catches it,
  Qt 5's does not.
- **A child anchored to a parent that sizes itself from its children is a
  binding loop.** Row content anchored to `verticalCenter` of a holder whose
  `implicitHeight` is `childrenRect.height` loops silently — it shows up in the
  journal, not in the lint.
- **`hyprctl keyword` does nothing on a Lua config.** It answers "keyword can't
  work with non-legacy parsers. Use eval." — on stderr, while still exiting 0,
  so a setting looks applied and is not. `hypr_apply_live` sends
  `hyprctl eval 'hl.config({...})'` instead, with the keyword form kept for
  setups still on `.conf`. Per-device settings go the same way, as
  `hl.device({ name = ..., ... })`.
- `qmllint` on `PATH` is Qt 5's (`qt5-declarative`), and Quickshell is Qt 6.
  It cannot parse a typed function signature — `function show(): void`, which
  `IpcHandler` requires — and exits 255 with no output when it meets one, so
  `Panel.qml` never gets linted by it. It also passes nearly everything else
  regardless of merit, which makes a clean run from it worth nothing. Use the
  Qt 6 binary, and give it the `qs.*` root, which Quickshell aliases to the
  shell directory:

  ```bash
  mkdir -p /tmp/qsimports && ln -sfn /usr/share/omarchy/shell /tmp/qsimports/qs
  /usr/lib/qt6/bin/qmllint -I /tmp/qsimports SettingsWindow.qml sections/*.qml
  ```

  Two warnings are expected and are not yours to fix: `Property "state"
  already exists in base type` (the window has carried it from the start) and
  `Type PanelWindow is not creatable`, which Omarchy's own bar and menu raise
  on the same type. Unqualified-access and missing-property notes on `Style`
  and `Color` are singletons qmllint cannot follow.

  Even so, the authoritative check is the shell loading the file.


## Which screen it opens on

A layer surface goes to the screen it is given, and given none it goes to the
first one — so on two monitors the settings could open on the one you are not
looking at. Hyprland knows which monitor has the focus and Quickshell knows
the screens by name; `focusedScreen()` matches the two, and `show()` pins the
result for that opening.

Pinned, not bound: a window that hops to another screen because the focus
moved is worse than one that stays where it was opened. This machine has one
monitor, so the choice is verified by what it resolves rather than by where
it lands.

