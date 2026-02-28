# Feature Specification: Miaou Composer

**Feature Branch**: `001-miaou-composer`
**Created**: 2026-03-01
**Status**: Draft
**Input**: User description: "Miaou Composer — A live, dynamic UI compositor for Miaou-based TUI applications, exposed as both an MCP server (for AI agents) and a Miaou-based page designer TUI (for humans)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - AI Agent Composes a Page via MCP (Priority: P1)

An AI agent (e.g., Claude via MCP) connects to the Miaou Composer MCP server and builds a TUI page interactively. The agent queries the widget catalog to discover available widgets, creates a page with a layout, adds widgets incrementally, wires button actions, sends keystrokes to interact, and captures rendered frames to verify the result — all without recompiling or restarting anything.

**Why this priority**: This is the core value proposition. The compositor engine and MCP server together form the minimum viable product. Without this, nothing else works.

**Independent Test**: Can be fully tested by connecting an MCP client (or raw JSON-RPC over stdio), sending create_page / add_widget / send_key / capture commands, and verifying rendered output matches expectations.

**Acceptance Scenarios**:

1. **Given** the MCP server is running, **When** the agent calls `list_widgets`, **Then** it receives a structured catalog of all available widget types grouped by category (input, display, layout) with their parameters, events, and queryable properties.
2. **Given** the MCP server is running, **When** the agent calls `create_page` with a layout definition containing a textbox and a button, **Then** the server returns a rendered frame showing both widgets in the specified layout.
3. **Given** a page exists with a textbox and a button, **When** the agent calls `add_widget` to insert a checkbox, **Then** the next `capture` call returns a frame showing all three widgets, and the focus ring includes the new widget.
4. **Given** a page with a button, **When** the agent calls `wire` to bind the button's click event to an `emit` action, then calls `send_key "Enter"` while the button is focused, **Then** the server sends a notification back with the emitted event name and current widget states.
5. **Given** a page exists, **When** the agent calls `query_focus`, **Then** it receives the ID of the currently focused widget.

---

### User Story 2 - Live Widget Mutation Without Reload (Priority: P1)

A user (AI or human via MCP) modifies a live page by adding, removing, updating, or moving widgets at runtime. Changes take effect immediately on the next render — no page teardown, no state loss, no recompilation.

**Why this priority**: This is the "live compositor" differentiator. Without incremental mutation, it's just a static page renderer.

**Independent Test**: Create a page, capture its frame, mutate it (add/remove/update widgets), capture again, and verify the diff matches the expected change.

**Acceptance Scenarios**:

1. **Given** a page with two buttons, **When** the agent calls `add_widget` to insert a textbox between them, **Then** the rendered frame shows the textbox in the correct position and existing widget states are preserved.
2. **Given** a page with a textbox containing user-entered text, **When** the agent calls `remove_widget` on an unrelated button, **Then** the textbox retains its text content and focus state.
3. **Given** a page with a checkbox, **When** the agent calls `update_widget` to change its label, **Then** the next frame shows the updated label while preserving the checked/unchecked state.
4. **Given** a page with a widget inside a flex column, **When** the agent calls `move_widget` to reparent it into a different layout container, **Then** the widget appears in its new location with state preserved.

---

### User Story 3 - Wiring Widget Events to Actions (Priority: P1)

A user wires widget events (click, toggle, change) to compositor actions (set value on another widget, push a modal, emit an event, navigate, etc.). Wirings can be added, replaced, and removed at runtime. When a user interacts with a wired widget, the action fires automatically.

**Why this priority**: Wiring is what makes the compositor interactive rather than just a layout tool. It's the "event loop" that the AI agent or designer drives.

**Independent Test**: Wire a button click to set_text on a textbox, press Enter on the button, and verify the textbox content changed.

**Acceptance Scenarios**:

1. **Given** a button and a textbox on a page, **When** the agent wires button.click to `set_text(target: textbox, value: "Hello")` and then sends Enter while the button is focused, **Then** `query_widget(textbox)` returns `{ text: "Hello" }`.
2. **Given** a button wired to `emit("save_clicked")`, **When** the user activates the button, **Then** the MCP server sends a notification containing the event name `"save_clicked"` and a snapshot of all widget states.
3. **Given** a button wired to `push_modal` with a confirmation dialog definition, **When** the user activates the button, **Then** `query_modal` reports an active modal with the specified title and content.
4. **Given** an existing wiring on a button, **When** the agent calls `wire` again with a different action for the same event, **Then** the old wiring is replaced and the new action fires on the next interaction.
5. **Given** a wiring exists, **When** the agent calls `unwire` for that source/event pair, **Then** activating the widget no longer triggers any action.

---

### User Story 4 - Page Validation and Sanitization (Priority: P2)

Before instantiating a page, the user can submit a page definition for validation. The validator checks for structural correctness (valid widget types, required parameters, unique IDs), semantic correctness (focus ring references existing focusable widgets, layout constraints are satisfiable), and returns detailed errors and warnings with paths pointing to the offending nodes.

**Why this priority**: Validation prevents cryptic runtime errors and helps AI agents self-correct. Important for usability but not required for core functionality.

**Independent Test**: Submit a deliberately malformed page definition and verify the returned errors match expected issues.

**Acceptance Scenarios**:

1. **Given** a page definition with a misspelled widget type, **When** the agent calls `validate_page`, **Then** the response includes an error with the JSON path to the offending node and a message listing valid widget types.
2. **Given** a page definition with duplicate widget IDs, **When** validated, **Then** the response includes an error identifying both occurrences.
3. **Given** a page definition where the focus ring references a non-existent widget ID, **When** validated, **Then** the response includes an error identifying the invalid reference.
4. **Given** a valid page definition, **When** validated, **Then** the response indicates success with no errors.
5. **Given** a page definition with a textbox missing a required `id` field, **When** validated, **Then** the response includes an error for the missing field.

---

### User Story 5 - Export Page Definition as JSON (Priority: P2)

After composing a page interactively (adding widgets, wiring actions, tuning layout), the user can export the current page state as a portable JSON document. This JSON can be saved, version-controlled, shared, and later re-imported to recreate the exact same page.

**Why this priority**: Export closes the loop — without it, composed pages are ephemeral and lost when the session ends.

**Independent Test**: Create a page, add widgets, wire actions, export to JSON, create a new session, import the JSON, and verify the rendered output and wirings match.

**Acceptance Scenarios**:

1. **Given** a page with widgets, layout, and wirings, **When** the agent calls `export_json`, **Then** the response contains a complete JSON document describing the page structure, all widget states, and all wirings.
2. **Given** an exported JSON document, **When** used as input to `create_page`, **Then** the resulting page renders identically to the original.
3. **Given** a page with a modal definition, **When** exported, **Then** the modal definitions are included in the JSON output.

---

### User Story 6 - Widget Catalog Discovery (Priority: P2)

An AI agent or tool queries the compositor for the complete catalog of available widgets, layout types, and wiring actions. The catalog provides enough information for the agent to construct valid page definitions without external documentation.

**Why this priority**: Self-describing API enables autonomous AI usage. Without it, the agent needs hardcoded knowledge of widget parameters.

**Independent Test**: Call `list_widgets`, `list_actions`, `list_layout_types` and verify all known types are returned with correct parameter metadata.

**Acceptance Scenarios**:

1. **Given** the MCP server is running, **When** the agent calls `list_widgets`, **Then** the response includes every supported widget type with: name, category, parameters (name, type, required/optional, default), events, and queryable properties.
2. **Given** the MCP server is running, **When** the agent calls `list_actions`, **Then** the response lists all wiring action types with their required and optional parameters.
3. **Given** the MCP server is running, **When** the agent calls `list_layout_types`, **Then** the response lists all layout container types with their configuration options.

---

### Edge Cases

- What happens when a widget is removed while it holds focus? The focus ring advances to the next available widget.
- What happens when all widgets are removed from a page? The page renders as empty, focus ring becomes empty, capture returns a blank frame.
- What happens when a wired target widget is removed? The wiring is automatically cleaned up.
- What happens when a modal is pushed on a page that already has a modal? Modals stack; the topmost modal receives input.
- What happens when `send_key` is called on a page with no focusable widgets? The key is silently ignored or bubbles to page-level key handlers.
- What happens when `create_page` is called with the same ID as an existing page? The server returns an error (IDs must be unique within a session).
- What happens when the layout tree becomes deeply nested (e.g., 50 levels)? The system handles it gracefully up to a reasonable depth limit.
- What happens when `export_json` is called on a page with unsaved modal state? The export captures the base page state; modals are transient.

## Requirements *(mandatory)*

### Functional Requirements

#### Compositor Engine

- **FR-001**: System MUST maintain a live, mutable widget state graph where widgets are stored by string ID and can be added, removed, updated, and moved without rebuilding the page.
- **FR-002**: System MUST support heterogeneous widget storage using type-safe existential boxing (no unsafe casts).
- **FR-003**: System MUST support these input widget types: button, checkbox, textbox, select, textarea, radio button, switch.
- **FR-004**: System MUST support these display widget types: text/pager, list (hierarchical), table, description list.
- **FR-005**: System MUST support these layout types: flex (row/column), grid, box (bordered container), card.
- **FR-006**: System MUST automatically rebuild the focus ring when widgets are added, removed, or have their focusable property changed.
- **FR-007**: System MUST support a wiring table that maps (source_widget_id, event_name) pairs to compositor actions.
- **FR-008**: System MUST support these wiring actions: set_text, set_checked, toggle, append_text, push_modal, close_modal, navigate, back, quit, focus, emit, set_disabled, set_visible, set_items.
- **FR-009**: System MUST render pages using the headless driver, producing ANSI string output for a configurable viewport size.
- **FR-010**: System MUST support modal stacking — multiple modals can be pushed, and the topmost modal receives key input.
- **FR-011**: System MUST support multiple concurrent page sessions, each with independent widget state, focus, and modal stack.
- **FR-012**: System MUST clean up dangling wirings when a target widget is removed.

#### MCP Server

- **FR-013**: System MUST implement the MCP protocol (JSON-RPC over stdio) for communication with AI agents and tools.
- **FR-014**: System MUST expose discovery tools: `list_widgets`, `list_actions`, `list_layout_types`.
- **FR-015**: System MUST expose composition tools: `create_page`, `add_widget`, `remove_widget`, `move_widget`, `update_widget`.
- **FR-016**: System MUST expose wiring tools: `wire`, `unwire`, `list_wirings`.
- **FR-017**: System MUST expose interaction tools: `send_key`, `send_keys`, `tick`, `focus`, `resize`.
- **FR-018**: System MUST expose modal tools: `push_modal`, `close_modal`.
- **FR-019**: System MUST expose inspection tools: `capture`, `get_region`, `query_widget`, `query_focus`, `query_modal`, `query_all_state`.
- **FR-020**: System MUST expose validation tool: `validate_page`.
- **FR-021**: System MUST expose export tool: `export_json`.
- **FR-022**: System MUST send MCP notifications when an `emit` wiring action fires, including the event name and current widget state snapshot.

#### Validation

- **FR-023**: System MUST validate page definitions for: valid widget types, required parameters present, unique widget IDs, valid focus ring references, and valid wiring targets.
- **FR-024**: Validation errors MUST include the JSON path to the offending node and a human-readable message.
- **FR-025**: Validation MUST distinguish between errors (blocking) and warnings (advisory).

#### Export

- **FR-026**: System MUST export the current page state (layout tree, widget parameters, widget states, wirings) as a self-contained JSON document.
- **FR-027**: Exported JSON MUST be re-importable via `create_page` to produce an equivalent page.

### Key Entities

- **Session**: A runtime container holding one or more live pages. Each MCP connection operates within a session.
- **Page**: A named, live UI composition with a layout tree, widget store, focus ring, wiring table, and modal stack.
- **Widget**: An individual UI element (button, textbox, etc.) with a unique string ID, typed state, and render/key-handling capabilities.
- **Layout Node**: A container in the layout tree (flex, grid, box, card) that arranges its children spatially.
- **Wiring**: A rule mapping a (source_widget_id, event_name) pair to a compositor action with parameters.
- **Widget Catalog**: Static metadata describing all available widget types, their parameters, events, and queryable properties.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An AI agent can create a page with 5+ widgets, wire actions between them, and verify the rendered output — all within a single MCP session without any recompilation or restart.
- **SC-002**: Adding, removing, or updating a widget on an existing page preserves the state of all other widgets (zero state loss on mutation).
- **SC-003**: The widget catalog provides sufficient metadata for an AI agent to construct valid page definitions without external documentation (self-describing API).
- **SC-004**: Exported JSON can be re-imported to produce a visually identical page with all wirings intact (round-trip fidelity).
- **SC-005**: Page validation catches all structural errors (invalid types, missing params, duplicate IDs) and returns actionable error messages with paths.
- **SC-006**: The compositor supports at least 50 widgets per page without noticeable rendering delays (under 100ms per frame on standard hardware).
- **SC-007**: Wiring an action and triggering it produces the expected side effect within a single render cycle (deterministic, no timing dependencies).

## Assumptions

- The project depends on `miaou-core` as an opam package. The public API surface of miaou-core (widgets, layout, focus_ring, modal_manager, headless_driver, direct_page, navigation, style) is sufficient for the compositor's needs.
- The headless driver (`miaou-core.lib_miaou_internal`) is available as a public library dependency.
- The MCP protocol is implemented directly (newline-delimited JSON-RPC over stdio) without an external SDK, since no OCaml MCP SDK exists.
- The designer TUI (Layer 3) is explicitly out of scope for v0.1 and will be addressed in a future version.
- OCaml code export is out of scope for v0.1; only JSON export is included.
- Mouse events are not supported in v0.1; all interaction is keyboard-driven via `send_key`.

## Scope

### In Scope (v0.1)

- Compositor engine library with widget store, layout tree, wiring, focus management, validation, rendering
- All input widgets: button, checkbox, textbox, select, textarea, radio, switch
- All display widgets: text/pager, list, table, description_list
- All layout types: flex, grid, box, card
- Full wiring action set
- MCP server binary with all tool categories
- Widget catalog generation
- Page validation/sanitization
- JSON export and re-import
- Multiple concurrent page sessions

### Out of Scope (v0.1)

- Page Designer TUI (v0.2)
- OCaml code export (v0.2)
- Mouse event support
- Theming/style customization via MCP (pages use default theme)
- Widget animation or transition effects
- Persistent storage (pages live only for the session duration)
- Network transport for MCP (only stdio)
