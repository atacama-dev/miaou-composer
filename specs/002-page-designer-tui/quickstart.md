# Quickstart: Page Designer TUI

**Feature**: 002-page-designer-tui
**Date**: 2026-03-01

## Overview

The Page Designer TUI is a standalone terminal application in the `miaou-composer` repo that lets users interactively compose Miaou TUI pages. It lives at `bin/designer/` and is built as a Miaou application implementing `PAGE_SIG`.

## Prerequisites

1. **OCaml 5.3.0** with local opam switch at `miaou-composer/_opam/`
2. **miaou-core** pinned from local repo (already done)
3. **miaou-runner** pinned from local repo (new — see Setup below)

## Setup: Pin miaou-runner

The designer needs `miaou-runner.tui` which is not yet pinned. Run:

```bash
cd /home/mathias/dev/miaou-composer
eval $(opam env)
opam pin add miaou-driver-term git+file:///home/mathias/dev/miaou#main --no-action
opam pin add miaou-driver-matrix git+file:///home/mathias/dev/miaou#main --no-action
opam pin add miaou-runner git+file:///home/mathias/dev/miaou#main --no-action
opam install miaou-driver-term miaou-driver-matrix miaou-runner
```

Then add to `dune-project` depends and `miaou-composer.opam`:
- `miaou-runner` (>= 0.4)

## Build

```bash
cd /home/mathias/dev/miaou-composer
eval $(opam env)
dune build
```

The designer executable: `_build/default/bin/designer/main.exe`

## Run

```bash
./_build/default/bin/designer/main.exe
```

Or after install:
```bash
miaou-composer-designer
```

## Directory Layout

```
bin/designer/
├── designer_state.ml   # State type + transitions
├── menu.ml             # Menu state and navigation
├── form.ml             # Parameter form state
├── preview.ml          # Preview panel rendering
├── page.ml             # PAGE_SIG implementation
├── main.ml             # Entry point: Eio_main.run + Runner_tui.run
└── dune                # (library miaou_composer_designer) + (executable designer)

test/
└── test_designer.ml    # Alcotest tests for designer state machine
```

## Key Design Decisions

1. **PAGE_SIG direct implementation**: `Designer_page` in `page.ml` implements all required PAGE_SIG values. The `view` function composes sidebar + preview using `Sidebar_widget.render`.

2. **Compositor in-process**: `designer_state.ml` holds a live `Session.t` and calls compositor functions directly. The preview renders via `Page.render` which returns an ANSI string.

3. **Menu stack**: Menu navigation uses a stack of `Menu_level.t`. Pressing `Enter` on an item either pushes a new level or triggers an action. `Escape` pops the stack.

4. **Two-phase key handling**:
   - `Design` mode: `on_key` dispatches to `Menu.handle_key` or `Form.handle_key` depending on what is active.
   - `Preview` mode: `on_key` calls `Page.send_key session page_id key` and re-renders.

5. **Status bar**: Always visible at the bottom. Shows `[page_id] | widgets: N | wirings: M | mode: DESIGN/PREVIEW`.

## Testing

```bash
dune test
```

New tests in `test/test_designer.ml`:
- `menu_navigation` — arrow keys, Enter, Escape on menu stack
- `form_validation` — required fields, duplicate IDs, int parsing
- `mode_switching` — Design ↔ Preview transitions
- `add_remove_widget` — state after add/remove
- `wiring_lifecycle` — add wiring, remove wiring, cleanup on widget removal
- `export_import_roundtrip` — page_to_json → page_of_json identity
