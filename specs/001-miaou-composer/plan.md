# Implementation Plan: Miaou Composer

**Branch**: `001-miaou-composer` | **Date**: 2026-03-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-miaou-composer/spec.md`

## Summary

Miaou Composer is a live, dynamic UI compositor for Miaou-based TUI applications. It provides a compositor engine library that bridges JSON descriptions to live Miaou widget instances, supporting incremental mutations, event wiring, and headless rendering. An MCP server binary exposes the compositor via JSON-RPC/stdio for AI agents. The design uses existential GADT boxing for heterogeneous widget storage, a mutable layout tree for incremental composition, and synchronous wiring execution for deterministic behavior.

## Technical Context

**Language/Version**: OCaml 5.x
**Primary Dependencies**: miaou-core (widgets, internals, layout, style, headless driver), ocaml-mcp (MCP protocol SDK with Eio transport), yojson (JSON serialization)
**Storage**: N/A (in-memory only, pages live for session duration)
**Testing**: Alcotest (unit tests), MCP integration tests via stdio
**Target Platform**: Linux/macOS terminal
**Project Type**: Library + CLI binary (MCP server)
**Performance Goals**: <100ms per frame render with 50 widgets
**Constraints**: No unsafe casts (Obj.magic), deterministic single-tick wiring execution
**Scale/Scope**: Up to 50 widgets per page, multiple concurrent pages per session

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

No constitution file exists for this project yet. Gate passes by default. Constitution to be established as the project matures.

**Post-Phase 1 re-check**: Design is straightforward — library + binary, no excessive abstraction layers, no over-engineering. The existential GADT pattern is the minimum viable approach for heterogeneous widget storage (alternatives are unsafe or overly complex).

## Project Structure

### Documentation (this feature)

```text
specs/001-miaou-composer/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: technology decisions
├── data-model.md        # Phase 1: entity model
├── quickstart.md        # Phase 1: setup and usage guide
├── contracts/           # Phase 1: MCP tool contracts
│   └── mcp-tools.md    # All tool input/output schemas
├── checklists/          # Quality checklists
│   └── requirements.md # Spec validation checklist
└── tasks.md             # Phase 2: implementation tasks (via /speckit.tasks)
```

### Source Code (repository root)

```text
lib/
├── compositor/                 # Core compositor engine (miaou_composer_lib)
│   ├── widget_box.ml           # Existential widget boxing type
│   ├── widget_registry.ml      # Widget type → constructor/boxer registry
│   ├── layout_tree.ml          # Mutable layout tree (flex, grid, box, card, leaf)
│   ├── wiring.ml               # Event→action wiring table + execution
│   ├── action.ml               # Closed action variant type
│   ├── focus_manager.ml        # Focus ring rebuild on widget add/remove
│   ├── page.ml                 # Page state (widgets, layout, focus, wirings, modals)
│   ├── session.ml              # Multi-page session management
│   ├── catalog.ml              # Widget catalog metadata generation
│   ├── validator.ml            # Page definition validation
│   ├── event_detect.ml         # Per-widget-type event detection (state diffing)
│   └── dune                    # Library stanza: miaou_composer_lib
├── bridge/                     # JSON↔OCaml conversion (miaou_composer_bridge)
│   ├── widget_factory.ml       # JSON params → widget_box constructors
│   ├── layout_codec.ml         # JSON ↔ layout_tree serialization
│   ├── action_codec.ml         # JSON ↔ action serialization
│   ├── page_codec.ml           # JSON ↔ full page definition
│   └── dune                    # Library stanza: miaou_composer_bridge
└── export/                     # Export functionality (miaou_composer_export)
    ├── json_export.ml          # Live page → JSON document
    └── dune                    # Library stanza: miaou_composer_export

bin/
└── mcp_server/                 # MCP server binary (miaou-composer-mcp)
    ├── main.ml                 # Entry point: Eio stdio transport + MCP server init
    ├── tools.ml                # MCP tool definitions (input schemas, handlers)
    ├── tool_handlers.ml        # Tool handler implementations
    └── dune                    # Executable stanza

test/
├── test_widget_box.ml          # Widget boxing round-trip tests
├── test_layout_tree.ml         # Layout tree mutation tests
├── test_wiring.ml              # Wiring execution tests
├── test_page.ml                # Page lifecycle tests
├── test_session.ml             # Multi-page session tests
├── test_validator.ml           # Validation error detection tests
├── test_bridge.ml              # JSON↔OCaml round-trip tests
├── test_mcp_integration.ml     # End-to-end MCP tool tests
└── dune                        # Test stanzas
```

**Structure Decision**: OCaml library + binary layout following standard dune conventions. Three internal libraries (`compositor`, `bridge`, `export`) keep concerns separated while allowing fine-grained dependency control. The MCP server binary depends on all three.

## Complexity Tracking

No constitution violations to track.
