# Tasks: Miaou Composer

**Input**: Design documents from `/specs/001-miaou-composer/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/mcp-tools.md

**Tests**: Not explicitly requested — test tasks omitted. Tests can be added incrementally.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization, build system, dependencies

- [ ] T001 Create dune-project with project name, opam package definitions, and OCaml version in dune-project
- [ ] T002 Create miaou-composer.opam with dependencies: miaou-core, yojson, alcotest (dev), eio, eio_main in miaou-composer.opam
- [ ] T003 Create directory structure: lib/compositor/, lib/bridge/, lib/export/, bin/mcp_server/, test/
- [ ] T004 [P] Create lib/compositor/dune with library stanza (name miaou_composer_lib) depending on miaou-core.core, miaou-core.internals, miaou-core.widgets.input, miaou-core.widgets.display, miaou-core.widgets.layout, miaou-core.widgets.navigation, miaou-core.style, miaou-core.lib_miaou_internal, yojson
- [ ] T005 [P] Create lib/bridge/dune with library stanza (name miaou_composer_bridge) depending on miaou_composer_lib, yojson
- [ ] T006 [P] Create lib/export/dune with library stanza (name miaou_composer_export) depending on miaou_composer_lib, miaou_composer_bridge, yojson
- [ ] T007 [P] Create bin/mcp_server/dune with executable stanza (name main, public_name miaou-composer-mcp) depending on miaou_composer_lib, miaou_composer_bridge, miaou_composer_export, eio, eio_main, yojson
- [ ] T008 [P] Create test/dune with test stanzas depending on alcotest, miaou_composer_lib, miaou_composer_bridge, miaou_composer_export, yojson
- [ ] T009 Verify project builds with `dune build` (may need stub files in each library)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core compositor engine types and bridge layer that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

### Core Types

- [ ] T010 Define widget_box existential GADT type with render/on_key/query/update/events closures in lib/compositor/widget_box.ml
- [ ] T011 [P] Define action closed variant type (Set_text, Set_checked, Toggle, Append_text, Push_modal, Close_modal, Navigate, Back, Quit, Focus, Emit, Set_disabled, Set_visible, Set_items) in lib/compositor/action.ml
- [ ] T012 [P] Define layout_node mutable tree type (Leaf, Flex, Grid, Boxed, Card) with add_child, remove_child, find_node, move_child operations in lib/compositor/layout_tree.ml
- [ ] T013 [P] Define event_detect module with per-widget-type event detection by state diffing (button click, checkbox toggle, textbox change, select change, switch toggle, radio select) in lib/compositor/event_detect.ml

### Widget Registry

- [ ] T014 Implement widget_registry with box_button, box_checkbox, box_textbox, box_textarea, box_radio, box_switch constructors — each wrapping the miaou widget in a widget_box with appropriate render/on_key/query/update/events closures in lib/compositor/widget_registry.ml
- [ ] T015 Add box_select (monomorphized to string), box_pager, box_list, box_table, box_description_list to widget_registry in lib/compositor/widget_registry.ml

### Focus & Wiring

- [ ] T016 Implement focus_manager: rebuild_focus_ring (walk layout_tree, collect focusable widget IDs in order, create Focus_ring.t) in lib/compositor/focus_manager.ml
- [ ] T017 Implement wiring module: add/remove/replace/lookup wirings by (source_id, event_name), execute_action function that mutates page state per action type in lib/compositor/wiring.ml

### Page & Session

- [ ] T018 Implement page type holding layout_tree, widgets hashtable, focus_ring, wirings, modal_stack, size — with create, render, send_key (route to focused widget → detect events → execute wirings → re-render), add_widget, remove_widget, move_widget, update_widget operations in lib/compositor/page.ml
- [ ] T019 Implement session type holding pages map — with create_session, add_page, get_page, remove_page operations in lib/compositor/session.ml

### JSON Bridge

- [ ] T020 [P] Implement action_codec: action_to_json and action_of_json for all 14 action variants in lib/bridge/action_codec.ml
- [ ] T021 [P] Implement layout_codec: layout_node_to_json and layout_node_of_json (recursive tree walk, widget leaf params extraction) in lib/bridge/layout_codec.ml
- [ ] T022 Implement widget_factory: create_widget_box function taking widget type name string + Yojson params → widget_box, dispatching to widget_registry constructors in lib/bridge/widget_factory.ml
- [ ] T023 Implement page_codec: page_def_to_json and page_def_of_json using layout_codec + action_codec + widget_factory, including focus_ring and wirings arrays in lib/bridge/page_codec.ml

**Checkpoint**: Foundation ready — all user stories can now proceed

---

## Phase 3: User Story 1 — AI Agent Composes a Page via MCP (Priority: P1) MVP

**Goal**: An AI agent connects via MCP, queries the catalog, creates a page, adds widgets, sends keys, and captures rendered frames

**Independent Test**: Connect via stdio JSON-RPC, send create_page + send_key + capture, verify rendered output

### MCP Server Core

- [ ] T024 [US1] Implement MCP server entry point with Eio stdio transport, initialize/initialized handshake, tools/list and tools/call dispatch in bin/mcp_server/main.ml
- [ ] T025 [US1] Define all MCP tool schemas (inputSchema for each of the 22 tools per contracts/mcp-tools.md) as JSON Schema objects in bin/mcp_server/tools.ml

### Composition Tool Handlers

- [ ] T026 [US1] Implement miaou/create_page handler: parse page_def via page_codec, instantiate page, add to session, render initial frame, return render string in bin/mcp_server/tool_handlers.ml
- [ ] T027 [US1] Implement miaou/add_widget handler: parse widget def + parent_path, call page.add_widget, rebuild focus, render, return frame in bin/mcp_server/tool_handlers.ml
- [ ] T028 [US1] Implement miaou/remove_widget handler: call page.remove_widget, clean up wirings, rebuild focus, render, return frame in bin/mcp_server/tool_handlers.ml
- [ ] T029 [US1] Implement miaou/move_widget handler: call page.move_widget with new_parent_path + position, rebuild focus, render in bin/mcp_server/tool_handlers.ml
- [ ] T030 [US1] Implement miaou/update_widget handler: parse patch JSON, call page.update_widget, render in bin/mcp_server/tool_handlers.ml

### Interaction Tool Handlers

- [ ] T031 [US1] Implement miaou/send_key handler: call page.send_key, collect emitted events from wirings, return render + events + navigation in bin/mcp_server/tool_handlers.ml
- [ ] T032 [US1] Implement miaou/send_keys handler: iterate send_key for each key in sequence, accumulate events, return final frame in bin/mcp_server/tool_handlers.ml
- [ ] T033 [P] [US1] Implement miaou/tick handler: re-render without key input in bin/mcp_server/tool_handlers.ml
- [ ] T034 [P] [US1] Implement miaou/focus handler: call Focus_ring.focus on page, re-render in bin/mcp_server/tool_handlers.ml
- [ ] T035 [P] [US1] Implement miaou/resize handler: update page.size, re-render in bin/mcp_server/tool_handlers.ml

### Inspection Tool Handlers

- [ ] T036 [P] [US1] Implement miaou/capture handler: render page, return ANSI string + size in bin/mcp_server/tool_handlers.ml
- [ ] T037 [P] [US1] Implement miaou/get_region handler: render page, extract substring rectangle from ANSI output in bin/mcp_server/tool_handlers.ml
- [ ] T038 [P] [US1] Implement miaou/query_widget handler: look up widget by ID, call query closure, return type + state JSON in bin/mcp_server/tool_handlers.ml
- [ ] T039 [P] [US1] Implement miaou/query_focus handler: return Focus_ring.current + index + total count in bin/mcp_server/tool_handlers.ml
- [ ] T040 [P] [US1] Implement miaou/query_modal handler: return modal stack depth + top title + stack info in bin/mcp_server/tool_handlers.ml
- [ ] T041 [P] [US1] Implement miaou/query_all_state handler: iterate all widgets, call query on each, return combined JSON in bin/mcp_server/tool_handlers.ml

### Modal Tool Handlers

- [ ] T042 [P] [US1] Implement miaou/push_modal handler: parse modal layout def, create nested page, push to modal stack, render overlay in bin/mcp_server/tool_handlers.ml
- [ ] T043 [P] [US1] Implement miaou/close_modal handler: pop modal stack with outcome, return modal final state + re-render base page in bin/mcp_server/tool_handlers.ml

**Checkpoint**: US1 complete — AI agent can create pages, add widgets, interact via keys, inspect state, use modals via MCP

---

## Phase 4: User Story 2 — Live Widget Mutation Without Reload (Priority: P1)

**Goal**: Widgets can be added, removed, updated, and moved on a live page with zero state loss on other widgets

**Independent Test**: Create page with widgets, send keys to enter text, mutate (add/remove/move), verify text preserved

**Depends on**: Phase 3 (US1) for MCP server infrastructure

### Implementation for User Story 2

- [ ] T044 [US2] Add state preservation logic to page.add_widget: verify existing widget states are untouched after insertion, focus ring correctly rebuilt with new widget included in lib/compositor/page.ml
- [ ] T045 [US2] Add state preservation logic to page.remove_widget: verify remaining widget states preserved, focus advances if removed widget was focused, dangling wirings cleaned up in lib/compositor/page.ml
- [ ] T046 [US2] Add state preservation logic to page.move_widget: verify widget state preserved after reparenting, layout tree correctly updated, focus ring rebuilt in lib/compositor/page.ml
- [ ] T047 [US2] Implement page.update_widget with partial patch semantics: only update specified fields (e.g., change label without resetting text content) in lib/compositor/page.ml
- [ ] T048 [US2] Handle edge case: removing all widgets from page leaves empty render, empty focus ring in lib/compositor/page.ml
- [ ] T049 [US2] Handle edge case: adding widget with duplicate ID returns error in lib/compositor/page.ml

**Checkpoint**: US2 complete — live mutations preserve state, focus management is correct, edge cases handled

---

## Phase 5: User Story 3 — Wiring Widget Events to Actions (Priority: P1)

**Goal**: Widget events (click, toggle, change) fire compositor actions (set_text, emit, push_modal, etc.) automatically via wirings

**Independent Test**: Wire button.click → set_text on textbox, press Enter, verify textbox content changed

**Depends on**: Phase 2 (Foundation) for wiring engine

### Implementation for User Story 3

- [ ] T050 [US3] Implement miaou/wire handler: add wiring to page, replace if same source+event already exists in bin/mcp_server/tool_handlers.ml
- [ ] T051 [US3] Implement miaou/unwire handler: remove wiring from page in bin/mcp_server/tool_handlers.ml
- [ ] T052 [US3] Implement miaou/list_wirings handler: return all wirings as JSON array in bin/mcp_server/tool_handlers.ml
- [ ] T053 [US3] Implement wiring action executor for Set_text: look up target widget, call update closure with new text in lib/compositor/wiring.ml
- [ ] T054 [US3] Implement wiring action executor for Set_checked, Toggle, Append_text, Set_disabled, Set_visible, Set_items in lib/compositor/wiring.ml
- [ ] T055 [US3] Implement wiring action executor for Push_modal: parse modal def from action params, create nested page, push to stack in lib/compositor/wiring.ml
- [ ] T056 [US3] Implement wiring action executor for Close_modal, Navigate, Back, Quit, Focus in lib/compositor/wiring.ml
- [ ] T057 [US3] Implement wiring action executor for Emit: collect event name + snapshot all widget states as JSON, add to pending notifications list in lib/compositor/wiring.ml
- [ ] T058 [US3] Integrate wiring execution into page.send_key flow: after on_key, diff state, detect events, look up wirings, execute actions, collect emit notifications in lib/compositor/page.ml
- [ ] T059 [US3] Wire MCP notification delivery: when send_key returns emitted events, include them in the MCP response JSON in bin/mcp_server/tool_handlers.ml

**Checkpoint**: US3 complete — wirings work end-to-end, all action types execute correctly, emit notifications flow to MCP client

---

## Phase 6: User Story 4 — Page Validation and Sanitization (Priority: P2)

**Goal**: Page definitions can be validated before instantiation, returning structured errors and warnings with JSON paths

**Independent Test**: Submit malformed page def, verify errors include correct paths and messages

### Implementation for User Story 4

- [ ] T060 [P] [US4] Implement validator module with validate_page_def function returning (errors, warnings) lists in lib/compositor/validator.ml
- [ ] T061 [US4] Add validation rules: valid widget types (check against widget_registry), required params per widget type, unique widget IDs across page in lib/compositor/validator.ml
- [ ] T062 [US4] Add validation rules: focus_ring references must exist as focusable widgets, wiring source/target IDs must reference existing widgets in lib/compositor/validator.ml
- [ ] T063 [US4] Add JSON path tracking: each error/warning includes dotted path to offending node (e.g., ".layout.children[2].id") in lib/compositor/validator.ml
- [ ] T064 [US4] Add error vs warning distinction: missing required param = error, missing focusable widget from focus_ring = warning in lib/compositor/validator.ml
- [ ] T065 [US4] Implement miaou/validate_page handler: parse page_def JSON, run validator, return structured response with valid flag + errors + warnings in bin/mcp_server/tool_handlers.ml

**Checkpoint**: US4 complete — validation catches all structural errors with actionable messages

---

## Phase 7: User Story 5 — Export Page Definition as JSON (Priority: P2)

**Goal**: Live page state exported as portable JSON that can be re-imported to recreate the exact same page

**Independent Test**: Create page, add widgets, wire actions, export, re-import via create_page, verify identical render

### Implementation for User Story 5

- [ ] T066 [P] [US5] Implement json_export.export_page: walk page's layout_tree, serialize each widget's current state via query closure, include all wirings, produce complete page_def JSON in lib/export/json_export.ml
- [ ] T067 [US5] Ensure widget query closures capture full reconstructable state: textbox includes text + cursor, checkbox includes checked + label, select includes items + selection, etc. — update widget_registry if needed in lib/compositor/widget_registry.ml
- [ ] T068 [US5] Implement round-trip test path: export_page → page_codec.page_def_of_json → create page → render → compare with original render in lib/export/json_export.ml
- [ ] T069 [US5] Implement miaou/export_json handler: call json_export.export_page, return page_def JSON in bin/mcp_server/tool_handlers.ml

**Checkpoint**: US5 complete — exported JSON round-trips faithfully

---

## Phase 8: User Story 6 — Widget Catalog Discovery (Priority: P2)

**Goal**: AI agent queries catalog to discover all available widgets, actions, and layout types with their parameters

**Independent Test**: Call list_widgets, list_actions, list_layout_types and verify all types returned with correct metadata

### Implementation for User Story 6

- [ ] T070 [P] [US6] Implement catalog module: generate_widget_catalog returning list of widget_catalog_entry records (name, category, params, events, queryable, focusable) for all 11 widget types in lib/compositor/catalog.ml
- [ ] T071 [P] [US6] Implement catalog.generate_action_catalog returning list of action descriptors (name, params with types and required flags) for all 14 action types in lib/compositor/catalog.ml
- [ ] T072 [P] [US6] Implement catalog.generate_layout_catalog returning list of layout type descriptors (name, params) for flex/grid/box/card in lib/compositor/catalog.ml
- [ ] T073 [US6] Implement miaou/list_widgets handler: call catalog, serialize to JSON per contracts/mcp-tools.md schema in bin/mcp_server/tool_handlers.ml
- [ ] T074 [P] [US6] Implement miaou/list_actions handler: call catalog, serialize to JSON in bin/mcp_server/tool_handlers.ml
- [ ] T075 [P] [US6] Implement miaou/list_layout_types handler: call catalog, serialize to JSON in bin/mcp_server/tool_handlers.ml

**Checkpoint**: US6 complete — catalog is self-describing, AI agent can discover all capabilities

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T076 Add error handling: MCP error responses for invalid page_id, widget_id not found, invalid JSON params across all tool handlers in bin/mcp_server/tool_handlers.ml
- [ ] T077 Add edge case handling: deeply nested layout trees (depth limit), empty pages, concurrent page access in lib/compositor/page.ml
- [ ] T078 Verify quickstart.md scenario works end-to-end (login form example) by manual MCP session
- [ ] T079 Run `dune fmt` and fix any formatting issues across all source files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — first MCP-connected story
- **US2 (Phase 4)**: Depends on Phase 2 (core page operations) — can start in parallel with US1 for compositor-only work, MCP handlers need US1
- **US3 (Phase 5)**: Depends on Phase 2 (wiring engine) — can start in parallel with US1 for compositor-only work, MCP handlers need US1
- **US4 (Phase 6)**: Depends on Phase 2 (bridge layer for parsing) — MCP handler needs US1
- **US5 (Phase 7)**: Depends on Phase 2 (bridge + widget_registry query closures) — MCP handler needs US1
- **US6 (Phase 8)**: Depends on Phase 2 (widget_registry for type metadata) — MCP handler needs US1
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — No dependencies on other stories
- **US2 (P1)**: Core logic can start after Phase 2 — MCP handlers depend on US1 server being up
- **US3 (P1)**: Core logic can start after Phase 2 — MCP handlers depend on US1 server being up
- **US4 (P2)**: Can start after Phase 2 — MCP handler depends on US1 server
- **US5 (P2)**: Can start after Phase 2 — MCP handler depends on US1 server
- **US6 (P2)**: Can start after Phase 2 — MCP handler depends on US1 server

### Within Each User Story

- Compositor engine code before MCP handlers
- MCP handlers depend on compositor operations being implemented
- Edge cases after core functionality

### Parallel Opportunities

- T004–T008: All dune files can be written in parallel
- T010–T013: Core types can be defined in parallel (different files)
- T020–T021: Action and layout codecs in parallel
- T033–T043: Inspection/modal tools in parallel (independent handlers)
- T060–T062: Validation rules in parallel within validator
- T070–T072: Catalog generators in parallel
- US4, US5, US6 can all proceed in parallel once US1 is complete

---

## Parallel Example: Foundation Phase

```
# Launch core type definitions together:
Task: "Define widget_box type in lib/compositor/widget_box.ml"
Task: "Define action type in lib/compositor/action.ml"
Task: "Define layout_tree type in lib/compositor/layout_tree.ml"
Task: "Define event_detect module in lib/compositor/event_detect.ml"

# Launch codec definitions together:
Task: "Implement action_codec in lib/bridge/action_codec.ml"
Task: "Implement layout_codec in lib/bridge/layout_codec.ml"
```

## Parallel Example: P2 Stories

```
# After US1 complete, launch all P2 stories in parallel:
Task: "Implement validator in lib/compositor/validator.ml" (US4)
Task: "Implement json_export in lib/export/json_export.ml" (US5)
Task: "Implement catalog in lib/compositor/catalog.ml" (US6)
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: US1 (MCP server with all tool categories)
4. **STOP and VALIDATE**: Test by running the quickstart.md login form scenario
5. Deploy/demo if ready

### Incremental Delivery

1. Phase 1 + Phase 2 → Foundation ready
2. Add US1 → Test MCP end-to-end → **MVP!**
3. Add US2 → Verify state preservation on mutations
4. Add US3 → Verify wiring execution
5. Add US4 → Verify validation catches errors
6. Add US5 → Verify export round-trip
7. Add US6 → Verify catalog completeness
8. Each story adds value without breaking previous stories

### Suggested MVP Scope

**US1 alone is the MVP**. It includes creating pages, adding widgets, sending keys, capturing frames, and inspecting state. US2 and US3 refine and extend the mutation and wiring capabilities that are already partially present in US1's foundation.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- The ocaml-mcp library handles MCP protocol compliance — focus implementation effort on compositor logic and tool handlers
