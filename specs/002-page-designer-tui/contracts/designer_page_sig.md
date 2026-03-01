# Contract: Designer Page (PAGE_SIG Implementation)

**Feature**: 002-page-designer-tui
**Date**: 2026-03-01

## Module: Designer_page

Implements `Miaou_core.Tui_page.PAGE_SIG`.

### State

```ocaml
type state = Designer_state.t
type msg = unit  (* unused — all mutations go through on_key *)
type pstate = state Navigation.t
```

### init

```ocaml
val init : unit -> pstate
```

Creates an empty designer state:
- New compositor session with one empty page (flex column root)
- Design mode
- Root menu level active
- No form, no modal

### view

```ocaml
val view : pstate -> focus:bool -> size:LTerm_geom.size -> string
```

Renders the full terminal UI:
1. Get `state = Navigation.inner pstate`
2. Render sidebar content: menu items or form fields (ANSI string)
3. Render preview: `Page.render session page_id ~size:(preview_size size)`
4. Compose: `Sidebar_widget.render {sidebar; main=preview; ...} ~cols:size.cols`
5. Append status bar line at bottom

**Sidebar width**: 30 columns (fixed)
**Preview area**: `cols - 30 - 1` columns (minus separator)

### on_key

```ocaml
val on_key : pstate -> Keys.t -> size:LTerm_geom.size -> pstate * Key_event.result
```

Dispatch:
- Mode = Preview: forward to `Preview.handle_key pstate key`
- Mode = Design, modal active: forward to `Modal.handle_key pstate key`
- Mode = Design, form active: forward to `Form.handle_key pstate key`
- Mode = Design, menu active: forward to `Menu.handle_key pstate key`

Returns `(new_pstate, Handled)` always (designer consumes all keys).
`Quit` via `Navigation.quit` when user selects Quit from menu.

### on_modal_key

```ocaml
val on_modal_key : pstate -> Keys.t -> size:LTerm_geom.size -> pstate * Key_event.result
```

Called when `has_modal pstate = true`. Delegates to `Modal.handle_key`.

### has_modal

```ocaml
val has_modal : pstate -> bool
```

Returns `true` when `(Navigation.inner pstate).modal <> None`.

### key_hints

```ocaml
val key_hints : pstate -> key_hint list
```

Returns mode-appropriate hints:
- Design mode: `[{key="↑↓"; help="Navigate"}; {key="Enter"; help="Select"}; {key="Esc"; help="Back"}; {key="F5"; help="Preview"}; {key="q"; help="Quit"}]`
- Preview mode: `[{key="Tab"; help="Next widget"}; {key="Esc"; help="Back to design"}]`

### Deprecated Stubs

All deprecated PAGE_SIG values (`handle_key`, `handle_modal_key`, `keymap`, `move`, `service_select`, `service_cycle`, `back`, `handled_keys`) are implemented as pass-through stubs or return empty lists. They are never called by the modern `Runner_tui`.
