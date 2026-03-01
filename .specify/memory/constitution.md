<!--
Sync Impact Report
===================
Version change: N/A → 1.0.0 (initial ratification)
Added principles:
  - I. Type-Safe Composition
  - II. JSON Bridge Symmetry
  - III. Test-First Verification
  - IV. Miaou-Core Compatibility
  - V. Simplicity & YAGNI
Added sections:
  - Technology Stack
  - Development Workflow
  - Governance
Templates requiring updates:
  - plan-template.md: ✅ Constitution Check section already present
  - spec-template.md: ✅ No changes needed
  - tasks-template.md: ✅ No changes needed
Follow-up TODOs: None
-->

# Miaou-Composer Constitution

## Core Principles

### I. Type-Safe Composition

All heterogeneous widget storage MUST use existential GADT boxing
(`widget_box`) to preserve type safety. Direct use of `Obj.magic` or
unsafe casts is forbidden. Each widget type MUST expose its operations
through closures captured at box creation time: `render`, `on_key`,
`query`, `update`, `detect_events`.

**Rationale**: The compositor stores widgets of different OCaml types in
a single hashtable. The GADT pattern ensures type errors are caught at
compile time, not at runtime.

### II. JSON Bridge Symmetry

Every codec (`*_codec.ml`, `*_factory.ml`) MUST round-trip: encoding
then decoding MUST produce an equivalent value. New widget types,
actions, or layout nodes MUST be added to all three layers
simultaneously: compositor lib, bridge codec, and MCP tool handlers.

**Rationale**: The MCP server is the primary interface. If the bridge
loses information during serialization, the AI agent receives corrupted
state and cannot reliably compose UIs.

### III. Test-First Verification

New features MUST include alcotest tests that exercise the round-trip
path: JSON input → compositor operation → JSON output. Tests MUST pass
before committing. `dune build && dune test` MUST succeed on every
commit.

**Rationale**: The compositor is a runtime that AI agents depend on.
Silent regressions in serialization or widget behavior break the entire
agent loop.

### IV. Miaou-Core Compatibility

Miaou-core libraries are wrapped — modules MUST be accessed via their
fully qualified names (e.g., `Miaou_widgets_input.Button_widget`,
`Miaou_internals.Focus_ring`). Widget registry constructors MUST use
the public API only. When miaou-core deprecates an API (e.g.,
`handle_key` → `on_key`), the compositor SHOULD migrate but MUST NOT
break.

**Rationale**: Miaou-composer depends on miaou-core as an opam
package. Breaking changes in how we call miaou-core APIs cause build
failures that block all downstream work.

### V. Simplicity & YAGNI

Features MUST be implemented in the simplest way that satisfies the
current requirement. No abstraction layers, feature flags, or
configurability beyond what is actively used. Three similar lines of
code are preferred over a premature abstraction.

**Rationale**: The project is young. Over-engineering now creates
maintenance burden and cognitive overhead for a codebase that will
evolve rapidly.

## Technology Stack

- **Language**: OCaml 5.3.0 with local opam switch
- **Build**: dune 3.0+
- **Testing**: alcotest
- **Formatting**: ocamlformat 0.28.1
- **Dependencies**: miaou-core (>= 0.4), yojson (>= 2.0), lambda-term
- **Protocol**: MCP (Model Context Protocol) via JSON-RPC 2.0 over stdio
- **Target**: Linux/macOS terminal applications

## Development Workflow

1. **Format before commit**: Run `dune fmt --auto-promote` before every
   commit. Unformatted code MUST NOT be committed.
2. **Build + test gate**: `dune build && dune test` MUST pass before
   every commit.
3. **Commit regularly**: Commit after each logical unit of work, not
   in large batches.
4. **Branch per feature**: Each feature uses a numbered branch
   (`NNN-short-name`) with specs in `specs/NNN-short-name/`.
5. **No secrets**: `.gitignore` MUST exclude `_opam/`, `_build/`,
   `.claude/`, and credential files.

## Governance

This constitution defines the non-negotiable rules for the
miaou-composer project. All code contributions MUST comply with the
core principles above.

- **Amendments** require updating this file, incrementing the version,
  and documenting changes in the Sync Impact Report header.
- **Version policy**: MAJOR for principle removal/redefinition, MINOR
  for new principles or sections, PATCH for clarifications.
- **Compliance**: Every PR and code review SHOULD verify adherence to
  the core principles. Violations MUST be justified in the commit
  message or PR description.

**Version**: 1.0.0 | **Ratified**: 2026-03-01 | **Last Amended**: 2026-03-01
