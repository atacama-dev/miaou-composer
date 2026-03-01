# Research: Page Designer TUI

**Feature**: 002-page-designer-tui
**Date**: 2026-03-01
**Phase**: 0 — Outline & Research

## Decision Log

### D-001: TUI Runner Strategy

**Decision**: Pin `miaou-runner`, `miaou-driver-term`, and `miaou-driver-matrix` from the local miaou repo (`/home/mathias/dev/miaou`) and build the designer as a standard Miaou app implementing `PAGE_SIG`.

**Rationale**: The spec requires a "standard miaou app like the demos in miaou". `miaou-runner.tui` provides `Runner_tui.run` which is the canonical way to launch a Miaou terminal application. All three packages (`miaou-runner`, `miaou-driver-term`, `miaou-driver-matrix`) exist in the local miaou repo and have only the deps already installed (`eio`, `eio_main`, `miaou-core`, `lambda-term`). Pinning from `git+file:///home/mathias/dev/miaou#main` follows the same pattern as `miaou-core`.

**Alternatives considered**:
- Use lambda-term directly: possible but low-level, would require reimplementing the event loop, resize handling, and focus management that tui_driver_common already provides.
- Use only `miaou-core.runner-common`: already installed but still needs a driver backend (Lambda_term_driver or Matrix_driver) which live in the unpinned packages.
- Vendor runner code into miaou-composer: would duplicate miaou code and violate YAGNI.

**Action**: Add pins to `dune-project` and `miaou-composer.opam`:
```
(pin
  (url "git+file:///home/mathias/dev/miaou#main")
  (packages miaou-runner miaou-driver-term miaou-driver-matrix))
```
And add `miaou-runner` to `depends` in the opam file.

### D-002: Designer Page Architecture

**Decision**: Implement `PAGE_SIG` directly as a module `Designer_page` in `bin/designer/page.ml`. Do NOT use the `Demo_page.Make` functor — that is for tutorial/demo pages with sidebars and markdown content.

**Rationale**: `PAGE_SIG` is the minimal interface the runner needs. A direct implementation is simpler and gives full control over the designer's state machine. The demo functor adds tutorial overhead (tutorial_title, tutorial_markdown, service_select, etc.) that the designer does not need.

**Alternatives considered**:
- Demo_page.Make: Over-engineered for a standalone tool. Adds unused tutorial/service fields.

### D-003: Layout Strategy

**Decision**: Use `Miaou_widgets_layout.Sidebar_widget` for the side panel + preview split. The sidebar contains the menu/form UI; the main area contains the rendered preview.

**Rationale**: `Sidebar_widget` is already in `miaou-core.widgets.layout`, takes `sidebar:string` and `main:string`, and handles auto-collapse when terminal is too narrow. It renders both panels as ANSI strings with `render ~cols`. This avoids building a custom split-pane layout.

### D-004: Menu Navigation

**Decision**: Use a custom menu state (list of `(label, action)`) rendered with `List_widget` or a hand-formatted ANSI string. No third-party menu library needed.

**Rationale**: The designer menus are simple hierarchical option lists. `List_widget` can render them. State is a `string list` with a cursor index. Arrow keys and Enter navigate/select. This matches the V. Simplicity principle.

### D-005: Compositor Integration

**Decision**: The designer links directly to the `miaou-composer` library and calls compositor functions (`Session`, `Page`, `Widget_registry`) in-process. The preview renders via `Page.render` which returns an ANSI string embedded in the `view` function.

**Rationale**: The spec explicitly states "direct OCaml function calls (same process), not via the MCP protocol". This is simpler and faster than spawning the MCP server process from within the designer.

### D-006: Parameter Forms

**Decision**: Parameter forms use OCaml-side state with `Textbox_widget` for string/int fields and `Checkbox_widget` for booleans. Forms are rendered as a structured ANSI string in the sidebar.

**Rationale**: All widget parameter types are string, int, or bool (from catalog.ml). Textbox handles string and int (with validation). Checkbox handles bool. Lambda-term provides the key input for editing.

### D-007: Export/Import

**Decision**: Use `Miaou_composer_bridge.Page_codec` (`page_to_json` / `page_of_json`) for serialization. File I/O uses OCaml stdlib `In_channel`/`Out_channel`. Path input via a textbox modal.

**Rationale**: Page_codec already implements the round-trip (Constitution principle II). Re-using it in the designer ensures consistency between the MCP server and designer export formats.

### D-008: Testing

**Decision**: Add a `test/test_designer.ml` with alcotest tests for the designer state machine: menu navigation transitions, form field validation, mode switching, wiring add/remove. No integration tests that require a real terminal (those would require a pty).

**Rationale**: Constitution III requires alcotest tests on the round-trip path. The designer state machine is pure OCaml and can be unit-tested without a terminal. End-to-end terminal tests are not required.

## Technical Context (Resolved)

| Item | Value |
|------|-------|
| Language | OCaml 5.3.0 |
| Build | dune 3.0+ |
| Testing | alcotest |
| Formatting | ocamlformat 0.28.1 |
| New deps to pin | miaou-runner, miaou-driver-term, miaou-driver-matrix |
| TUI runner | `Miaou_runner_tui.Runner_tui.run` |
| Compositor access | direct OCaml calls (same process) |
| Layout | Sidebar_widget from miaou-core.widgets.layout |
| Serialization | Page_codec from miaou-composer bridge |
| Target platform | Linux/macOS terminal |
