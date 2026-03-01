# Feature Specification: Page Designer TUI

**Feature Branch**: `002-page-designer-tui`
**Created**: 2026-03-01
**Status**: Draft
**Input**: User description: "v0.2: Miaou-Composer Page Designer TUI — a Miaou-based interactive application that lets humans visually compose TUI pages using menus and live preview. It should use the miaou-composer MCP server as its backend to create/modify pages, add widgets, define wirings, and render previews. The designer should let users: browse the widget catalog, add widgets to a page via menus, configure widget parameters, define event wirings between widgets, preview the rendered page live, and export/import page definitions as JSON."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Build a Page with Widgets (Priority: P1)

A designer opens the Page Designer TUI. They see an empty canvas area and a sidebar menu. They select "Add Widget" from the menu, browse the catalog of available widget types (button, checkbox, textbox, select, etc.), pick one, fill in its parameters (label, initial value, etc.) via a form, and see the widget appear in the live preview. They repeat this to add more widgets. They can also remove or reorder widgets.

**Why this priority**: Without the ability to add widgets to a page, the designer has no purpose. This is the core value proposition.

**Independent Test**: Can be tested by launching the designer, adding 3 different widget types, and verifying they appear in the live preview.

**Acceptance Scenarios**:

1. **Given** the designer is open with an empty page, **When** the user selects "Add Widget" → "button" and enters label "Submit", **Then** a button labeled "Submit" appears in the live preview panel.
2. **Given** a page with two widgets, **When** the user selects a widget and chooses "Remove Widget", **Then** the widget disappears from the preview and the remaining widget is still displayed correctly.
3. **Given** the designer is open, **When** the user browses the widget catalog, **Then** all 10 widget types are listed with their category (input/display).

---

### User Story 2 — Wire Events Between Widgets (Priority: P2)

After adding widgets, the designer selects "Add Wiring" from the menu. They pick a source widget, choose an event (e.g., "click" for a button), then define an action (e.g., "toggle" targeting a checkbox). The wiring is saved and the user can see a list of all wirings. In the live preview, pressing Enter on the focused button triggers the wiring and toggles the checkbox.

**Why this priority**: Wirings make pages interactive. Without them, the designer only produces static layouts. This is the second most valuable capability.

**Independent Test**: Can be tested by creating a page with a button and checkbox, adding a click→toggle wiring, then verifying the wiring works via keyboard interaction in the preview.

**Acceptance Scenarios**:

1. **Given** a page with a button "Go" and a checkbox "Accept", **When** the user adds a wiring (source: "Go", event: "click", action: toggle "Accept"), **Then** the wiring appears in the wirings list.
2. **Given** a wired page in preview mode, **When** the user focuses the button and presses Enter, **Then** the checkbox toggles its checked state.
3. **Given** a page with wirings, **When** the user selects "Remove Wiring", **Then** the wiring is removed and no longer triggers.

---

### User Story 3 — Export and Import Page Definitions (Priority: P3)

The designer provides an "Export" action that serializes the current page (layout, widgets, wirings) to a JSON file on disk. The user can also "Import" a JSON file to load a previously saved page definition. This enables saving work and sharing page designs.

**Why this priority**: Persistence is essential for practical use but not needed to demonstrate the core compose-and-wire workflow.

**Independent Test**: Can be tested by building a page, exporting to JSON, clearing the page, importing the JSON, and verifying the page is restored identically.

**Acceptance Scenarios**:

1. **Given** a page with widgets and wirings, **When** the user selects "Export" and enters a filename, **Then** a valid JSON file is written to disk containing the complete page definition.
2. **Given** an exported JSON file, **When** the user selects "Import" and picks the file, **Then** the page is loaded with all widgets, layout, and wirings restored.
3. **Given** an invalid or corrupted JSON file, **When** the user tries to import it, **Then** the designer shows a clear error message and the current page is unchanged.

---

### User Story 4 — Live Preview with Focus Navigation (Priority: P2)

The designer has a dedicated preview panel that shows the rendered page as it would appear in a real terminal. The user can switch between "design mode" (sidebar menu active) and "preview mode" (focus is inside the rendered page). In preview mode, Tab cycles through focusable widgets and keys are forwarded to the focused widget.

**Why this priority**: Live preview is what makes the designer feel real-time. It runs alongside wiring (US2) to provide the full interactive experience.

**Independent Test**: Can be tested by adding widgets, switching to preview mode, and verifying Tab/Enter/Space interact with widgets correctly.

**Acceptance Scenarios**:

1. **Given** a page with 3 focusable widgets, **When** the user enters preview mode and presses Tab, **Then** focus cycles through widgets in layout order.
2. **Given** preview mode with a textbox focused, **When** the user types characters, **Then** the text appears in the textbox in the preview.
3. **Given** preview mode, **When** the user presses Escape, **Then** they return to design mode with the sidebar menu active.

---

### Edge Cases

- What happens when the user tries to add a widget with a duplicate ID? The designer MUST prevent this and show an error.
- What happens when the user wires an event to a widget that is later removed? The wiring MUST be automatically cleaned up.
- What happens when the page has no widgets and the user enters preview mode? The preview MUST show an empty page with a helpful hint.
- What happens when the terminal is too small to render the preview? The designer MUST gracefully handle small sizes without crashing.
- What happens when the user imports a JSON file that references unknown widget types? The designer MUST show a validation error listing the problems.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The designer MUST display a split layout with a sidebar menu on the left and a live preview on the right.
- **FR-002**: The sidebar MUST present a main menu with options: Add Widget, Remove Widget, Add Wiring, Remove Wiring, List Wirings, Preview Mode, Export, Import, Quit.
- **FR-003**: "Add Widget" MUST present a submenu listing all 10 widget types grouped by category (input: button, checkbox, textbox, textarea, select, radio, switch; display: pager, list, description_list).
- **FR-004**: After selecting a widget type, the designer MUST present a parameter form for that widget's configurable properties (as defined in the widget catalog).
- **FR-005**: Each widget MUST be assigned a unique ID. The designer MUST auto-generate IDs (e.g., "button_1", "checkbox_2") but allow the user to override.
- **FR-006**: The live preview panel MUST re-render after every mutation (add, remove, wiring change).
- **FR-007**: "Add Wiring" MUST present sequential menus: select source widget → select event → select action type → configure action parameters (target widget, value, etc.).
- **FR-008**: "List Wirings" MUST display all active wirings in a readable format showing source, event, and action.
- **FR-009**: Users MUST be able to switch between design mode and preview mode using a keyboard shortcut.
- **FR-010**: In preview mode, all key presses except the exit key (Escape) MUST be forwarded to the compositor's send_key function.
- **FR-011**: "Export" MUST serialize the current page to a JSON file at a user-specified path.
- **FR-012**: "Import" MUST load a page definition from a JSON file, replacing the current page.
- **FR-013**: Import MUST validate the JSON using the validator before loading. Invalid files MUST show errors without modifying the current page.
- **FR-014**: The designer MUST show the current page state in a status bar: page ID, widget count, wiring count, focused widget.
- **FR-015**: The designer MUST support terminal resize events, updating both the sidebar and preview panel dimensions.

### Key Entities

- **Designer State**: The top-level application state containing the current mode (design/preview), sidebar menu state, preview page reference, and status information.
- **Page Definition**: The JSON representation of a complete page (layout tree, widget parameters, wirings, focus ring). Round-trips through the compositor's page_codec.
- **Widget Catalog Entry**: Static metadata about a widget type (name, category, parameters with types/defaults, events, queryable fields). Used to generate the parameter form.
- **Wiring**: A triple of (source widget ID, event name, action definition) that connects widget behavior.

### Assumptions

- The designer runs as a standalone terminal application (not inside another miaou app).
- The designer communicates with the compositor engine directly via OCaml function calls (same process), not via the MCP protocol over stdio.
- The initial layout is always a single column flex container. The user adds widgets as children of this root container.
- Widget parameter forms use textbox inputs for strings, checkbox inputs for booleans, and textbox inputs for integers (with validation).
- File paths for export/import are entered via a textbox modal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can build a page with 5 widgets and 3 wirings in under 5 minutes using only keyboard navigation.
- **SC-002**: The live preview updates within 1 second of any mutation (add/remove widget, add/remove wiring).
- **SC-003**: Exported JSON can be successfully imported back, producing an identical page (round-trip fidelity).
- **SC-004**: All 10 widget types can be added and configured through the designer menus.
- **SC-005**: A first-time user can understand the interface and add their first widget within 30 seconds, guided by visible menu labels and key hints.
