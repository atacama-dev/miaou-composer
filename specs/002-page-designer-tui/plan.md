# Implementation Plan: Page Designer TUI

**Branch**: `002-page-designer-tui` | **Date**: 2026-03-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-page-designer-tui/spec.md`

## Summary

Build a standalone terminal application (`bin/designer/`) in the miaou-composer repo that lets users interactively compose Miaou TUI pages via keyboard-driven menus and a live split-pane preview. The designer implements `Miaou_core.Tui_page.PAGE_SIG` and runs via `Runner_tui.run`. It links directly to the compositor library for in-process page mutation, uses `Sidebar_widget` for the split layout, and `Page_codec` for JSON export/import. Three new opam pins are required: `miaou-driver-term`, `miaou-driver-matrix`, and `miaou-runner`.

## Technical Context

**Language/Version**: OCaml 5.3.0 with local opam switch (`_opam/`)
**Primary Dependencies**: miaou-core 0.4.1 (pinned), miaou-runner (new pin), miaou-driver-term (new pin), miaou-driver-matrix (new pin), yojson 2.0+, eio 1.0+, alcotest (test)
**Storage**: JSON files on disk (export/import only)
**Testing**: alcotest (`dune test`)
**Target Platform**: Linux/macOS terminal
**Project Type**: standalone TUI desktop application
**Performance Goals**: preview re-renders within 1s of any mutation (SC-002)
**Constraints**: keyboard-only navigation; graceful handling of small terminals; no MCP protocol in designer
**Scale/Scope**: single user; pages up to ~20 widgets; design-time tool only

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Type-Safe Composition | ✅ PASS | Designer uses compositor API only; no new GADT boxing needed |
| II. JSON Bridge Symmetry | ✅ PASS | Export/import uses existing `Page_codec`; no new codec needed |
| III. Test-First Verification | ✅ PASS | `test/test_designer.ml` covers state machine, form validation, round-trip |
| IV. Miaou-Core Compatibility | ✅ PASS | Uses fully-qualified names; implements modern PAGE_SIG (`on_key`, `key_hints`) with deprecated stubs |
| V. Simplicity & YAGNI | ✅ PASS | No abstraction layers beyond what PAGE_SIG requires; menu is a plain stack of item arrays |

*Post-design re-check*: All principles hold. The `bin/designer/` addition is a new executable, not a new library — no new opam package. The opam pins follow the same pattern as the existing `miaou-core` pin.

## Project Structure

### Documentation (this feature)

```text
specs/002-page-designer-tui/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── designer_page_sig.md
│   └── compositor_api.md
└── tasks.md             # Phase 2 output (/speckit.tasks — not yet created)
```

### Source Code (repository root)

```text
bin/
├── mcp_server/          # existing
│   └── ...
└── designer/            # NEW
    ├── designer_state.ml  # top-level state type + state transitions
    ├── menu.ml            # menu stack navigation (push/pop/select)
    ├── form.ml            # parameter form state + validation
    ├── preview.ml         # preview panel: calls Page.render, handles send_key
    ├── page.ml            # PAGE_SIG implementation (view, on_key, has_modal, etc.)
    ├── main.ml            # Eio_main.run + Runner_tui.run (module Designer_page)
    └── dune               # (library miaou_composer_designer) + (executable designer)

lib/
├── compositor/          # existing — used directly by designer
│   └── ...
└── bridge/              # existing — Page_codec used for export/import
    └── ...

test/
├── test_compositor.ml   # existing
└── test_designer.ml     # NEW — alcotest tests for designer state machine
```

**Structure Decision**: Single project extension. The designer is a new executable under `bin/designer/`. A thin internal library (`miaou_composer_designer`) wraps the state modules so `test_designer.ml` can import them without depending on the executable. The existing `lib/compositor/` and `lib/bridge/` are consumed as-is — no changes required.

## Complexity Tracking

> No constitution violations detected.
