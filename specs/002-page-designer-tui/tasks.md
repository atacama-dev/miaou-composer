# Tasks: Page Designer TUI

**Input**: Design documents from `/specs/002-page-designer-tui/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Tests**: Included — required by Constitution III (new features MUST include alcotest tests).

**Organization**: Tasks grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4)

---

## Phase 1: Setup

**Purpose**: Pin new opam packages and create the `bin/designer/` scaffold.

- [ ] T001 Pin `miaou-driver-term`, `miaou-driver-matrix`, and `miaou-runner` from `git+file:///home/mathias/dev/miaou#main` in `dune-project` and `miaou-composer.opam`; run `opam install miaou-driver-term miaou-driver-matrix miaou-runner`
- [ ] T002 Create `bin/designer/dune` with an `(executable (name main) ...)` stanza linking `miaou_composer_compositor`, `miaou_composer_bridge`, `miaou_runner_tui`, `eio_main`, `yojson`
- [ ] T003 [P] Create empty stub source files: `bin/designer/designer_state.ml`, `bin/designer/menu.ml`, `bin/designer/form.ml`, `bin/designer/preview.ml`, `bin/designer/page.ml`, `bin/designer/main.ml` with minimal `let () = ()` or type stubs so `dune build` passes

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core state types and test skeleton that ALL user story phases depend on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T004 Implement `Designer_state.t` core type in `bin/designer/designer_state.ml`: `Mode.t` (Design|Preview), `Status_info.t`, and the base `Designer_state.t` record with fields `mode`, `preview_session`, `preview_page_id`, `widget_counter`, `wiring_counter`, `status`, and stubs for `menu`, `form`, `modal` (use `unit` placeholders until Phase 3 fills them)
- [ ] T005 [P] Implement `Menu_state` types in `bin/designer/menu.ml`: `menu_action` variant, `Menu_item.t`, `Menu_level.t` (title, items array, cursor), `Menu_state.t` (stack), `create_root_menu` returning the top-level menu, `push`, `pop`, `move_cursor`, `current_item` functions
- [ ] T006 [P] Implement `Form_state` types in `bin/designer/form.ml`: `field_kind` variant (Text/Bool/Int), `Form_field.t`, `Form_state.t` (widget_type, fields array, focused_field, errors, is_submitting), `make_form_for_widget_type : string -> Form_state.t option` using `Miaou_composer_compositor.Catalog.params_for`
- [ ] T007 Add `test/test_designer.ml` with the alcotest test module skeleton (imports, `let () = Alcotest.run "designer" [...]` stub), and add a `(test (name test_designer) (libraries miaou_composer_designer alcotest))` stanza to `test/dune`
- [ ] T008 Verify `dune build && dune test` passes with stubs (no logic yet, just structure)

**Checkpoint**: Foundation ready — designer state types defined, test file compiles.

---

## Phase 3: User Story 1 — Build a Page with Widgets (Priority: P1) 🎯 MVP

**Goal**: User can add any of the 10 widget types via menus, configure parameters in a form, see the widget in the live preview, and remove widgets.

**Independent Test**: Launch the designer, add a button labeled "Submit", a checkbox "Accept", and a textbox "Name"; verify all three appear in the preview panel. Remove the checkbox; verify only the button and textbox remain.

### Implementation for User Story 1

- [ ] T009 [P] [US1] Implement full root menu and widget catalog submenu in `bin/designer/menu.ml`: `create_root_menu` returns items (Add Widget, Remove Widget, Add Wiring, Remove Wiring, List Wirings, Preview Mode, Export, Import, Quit); `create_widget_catalog_menu` returns input group (button, checkbox, textbox, textarea, select, radio, switch) and display group (pager, list, description_list)
- [ ] T010 [P] [US1] Complete `bin/designer/form.ml`: implement `make_form_for_widget_type` for all 10 widget types using catalog params; implement `move_focus`, `update_field`, `validate_form : Designer_state.t -> Form_state.t -> (string * Yojson.Safe.t) list result` (returns param key-value pairs or validation errors)
- [ ] T011 [US1] Implement `add_widget` and `remove_widget` in `bin/designer/designer_state.ml`: `add_widget : t -> widget_type:string -> params:Yojson.Safe.t -> (t, string) result` calls `Miaou_composer_compositor.Page.add_widget`; `remove_widget : t -> id:string -> (t, string) result` calls `Page.remove_widget`; both increment `widget_counter` and update `status`
- [ ] T012 [US1] Implement `bin/designer/preview.ml`: `render_preview : Designer_state.t -> cols:int -> rows:int -> string` calls `Page.render session page_id ~cols ~rows`; handle empty page with hint text "No widgets yet. Press 'a' to add one."
- [ ] T013 [US1] Implement `bin/designer/page.ml` Design-mode `on_key` dispatch: menu key handling (Up/Down move cursor, Enter selects, Escape pops stack); form key handling (Tab moves focus between fields, character keys update focused text field, Space toggles bool fields, Enter submits form, Escape cancels); `q` key from root menu triggers `Navigation.quit`
- [ ] T014 [US1] Implement `bin/designer/page.ml` `view` function: render sidebar (menu items with cursor highlight, or form fields with validation errors) as ANSI string; render preview via `Preview.render_preview`; compose both via `Miaou_widgets_layout.Sidebar_widget.render ~cols:size.cols`; append status bar line (`[page_id] | widgets: N | wirings: M | mode: DESIGN`)
- [ ] T015 [US1] Implement `bin/designer/main.ml`: `let () = Eio_main.run @@ fun _env -> Miaou_runner_tui.Runner_tui.run (module Designer_page)` where `Designer_page` is the module from `page.ml`; implement all deprecated PAGE_SIG stubs (`handle_key`, `handle_modal_key`, `keymap`, `move`, `service_select`, `service_cycle`, `back`, `handled_keys`) as pass-through stubs
- [ ] T016 [US1] Add alcotest tests for US1 in `test/test_designer.ml`: `add_widget_increases_count` — create state, call `add_widget`, assert widget_counter incremented and `get_widget_ids` returns the new ID; `remove_widget_decreases_list` — add then remove, assert ID gone; `duplicate_id_rejected` — add widget, attempt add with same ID, assert `Error`; `menu_navigation` — push catalog submenu, move cursor, pop back to root

**Checkpoint**: `dune build && dune test` passes. Run `_build/default/bin/designer/main.exe` and add 3 widgets manually.

---

## Phase 4: User Story 4 — Live Preview with Focus Navigation (Priority: P2)

**Goal**: User can enter Preview mode (F5), Tab through focusable widgets, interact with them (Enter/Space/type), and press Escape to return to Design mode.

**Independent Test**: Add 3 focusable widgets (button, checkbox, textbox); press F5 to enter Preview mode; Tab should cycle focus; type in the textbox; press Space to toggle the checkbox; Escape should return to Design mode.

### Implementation for User Story 4

- [ ] T017 [P] [US4] Implement `Mode.switch : Designer_state.t -> Designer_state.t` in `bin/designer/designer_state.ml`: toggles between `Design` and `Preview`; when switching to Preview, update `status.mode`; F5 key in `page.ml` on_key calls this
- [ ] T018 [P] [US4] Implement `bin/designer/preview.ml` `send_key : Designer_state.t -> string -> Designer_state.t`: calls `Miaou_composer_compositor.Page.send_key session page_id key_str`; re-renders preview after key; returns updated state
- [ ] T019 [US4] Implement Preview-mode `on_key` in `bin/designer/page.ml`: when `state.mode = Preview`, route all keys except Escape to `Preview.send_key`; Escape calls `Mode.switch` back to Design; update `key_hints` to return preview-specific hints `[{key="Tab"; help="Next widget"}; {key="Esc"; help="Back to design"}]`
- [ ] T020 [US4] Wire F5 keybinding in `bin/designer/page.ml` Design-mode `on_key`: pressing F5 calls `Mode.switch`; add `{key="F5"; help="Preview"}` to design-mode `key_hints`
- [ ] T021 [US4] Add alcotest tests for US4 in `test/test_designer.ml`: `mode_switch_design_to_preview` — assert state.mode = Preview after switch; `mode_switch_preview_to_design` — assert state.mode = Design after Escape; `preview_mode_rejects_menu_keys` — in Preview mode, verify Up/Down do not change menu cursor

**Checkpoint**: `dune test` passes. F5 enters preview, Tab/Enter/Escape work in preview.

---

## Phase 5: User Story 2 — Wire Events Between Widgets (Priority: P2)

**Goal**: User can add a wiring (source widget → event → action) via a 3-step wizard, list all wirings, remove a wiring; wirings auto-clean when the source or target widget is removed.

**Independent Test**: Create a button "Go" and checkbox "Accept"; add wiring (source: Go, event: click, action: toggle Accept); verify wiring in List Wirings view; in Preview mode, press Enter on the focused button; verify the checkbox toggles. Remove the wiring; verify it no longer triggers.

### Implementation for User Story 2

- [ ] T022 [P] [US2] Implement 3-step wiring wizard menu levels in `bin/designer/menu.ml`: step 1 = widget ID list (source selection); step 2 = event list (from `Catalog.params_for` / widget events); step 3 = action type list (set_value, toggle, submit, navigate); `create_wiring_step1_menu`, `create_wiring_step2_menu`, `create_wiring_step3_menu` each return a `Menu_level.t`
- [ ] T023 [P] [US2] Implement wiring action form in `bin/designer/form.ml`: `make_wiring_action_form : action_type:string -> widget_ids:string list -> Form_state.t` creates the appropriate fields (target widget ID select, value textbox for set_value, etc.)
- [ ] T024 [US2] Implement `add_wiring` and `remove_wiring` in `bin/designer/designer_state.ml`: `add_wiring : t -> source:string -> event:string -> action:Action.t -> (t, string) result` calls `Page.add_wiring`; `remove_wiring : t -> index:int -> (t, string) result`; both update `status.wiring_count`
- [ ] T025 [US2] Implement `remove_widget` wiring auto-cleanup in `bin/designer/designer_state.ml`: after calling `Page.remove_widget`, iterate `Page.get_wirings` and remove any wiring referencing the deleted widget ID (source or target)
- [ ] T026 [US2] Implement "List Wirings" display in `bin/designer/menu.ml`: `create_wirings_list_menu : Wiring.t list -> Menu_level.t` renders each wiring as `"{source}.{event} → {action_type}({target})"` in a read-only menu level (no action, Escape to return)
- [ ] T027 [US2] Wire wiring wizard flow into `bin/designer/page.ml` `on_key`: when menu action is `AddWiring`, push step1 menu; on step1 selection push step2 with source captured; on step2 selection push step3; on step3 selection open wiring action form; on form submit call `add_wiring`; when action is `ListWirings` push wirings list menu; when action is `RemoveWiring` push widget wiring selection menu
- [ ] T028 [US2] Add alcotest tests for US2 in `test/test_designer.ml`: `add_wiring_appears_in_list` — add wiring, assert `Page.get_wirings` returns it; `remove_wiring_removes_from_list` — add then remove wiring, assert list empty; `remove_widget_cleans_up_wirings` — add widget + wiring targeting it, remove widget, assert wiring gone

**Checkpoint**: `dune test` passes. Wiring wizard works; List Wirings shows active wirings; wiring triggers in Preview mode.

---

## Phase 6: User Story 3 — Export and Import Page Definitions (Priority: P3)

**Goal**: User can export the current page to a JSON file and import it back; invalid JSON shows an error without modifying the current page.

**Independent Test**: Build a page with 2 widgets and 1 wiring; select Export and enter `/tmp/test_page.json`; quit; re-open designer; select Import and enter `/tmp/test_page.json`; verify the page is restored with both widgets and the wiring.

### Implementation for User Story 3

- [ ] T029 [P] [US3] Implement `Modal_state.t` and modal rendering in `bin/designer/designer_state.ml`: `modal_kind` variant (`FilePath of {label; on_confirm}` | `Error of {message}`); `Modal_state.t` with `kind` and `input : string` (text buffer); `open_filepath_modal`, `open_error_modal`, `close_modal` helper functions
- [ ] T030 [P] [US3] Implement `export_page : Designer_state.t -> path:string -> (unit, string) result` in `bin/designer/designer_state.ml`: calls `Miaou_composer_bridge.Page_codec.page_to_json session page_id`, serializes via `Yojson.Safe.to_file`
- [ ] T031 [US3] Implement `import_page : Designer_state.t -> path:string -> (Designer_state.t, string) result` in `bin/designer/designer_state.ml`: reads file via `Yojson.Safe.from_file`, calls `Page_codec.page_of_json`, validates via `Miaou_composer_compositor.Validator.validate_page`; on success replaces `preview_session`; on error returns `Error msg` without mutating state
- [ ] T032 [US3] Implement modal `on_key` handling in `bin/designer/page.ml`: when `has_modal` is true, `on_modal_key` routes keys to `Modal.handle_key`; character keys append to `modal.input`; Backspace deletes last char; Enter calls `on_confirm modal.input`; Escape closes modal; `has_modal` returns `state.modal <> None`
- [ ] T033 [US3] Wire Export and Import menu actions in `bin/designer/page.ml`: Export action calls `open_filepath_modal` with `on_confirm = export_page`; Import action calls `open_filepath_modal` with `on_confirm = import_page` (error result opens error modal)
- [ ] T034 [US3] Implement modal display in `bin/designer/page.ml` `view`: when `has_modal`, render an overlay box over the sidebar with the modal prompt, current input text, and `[Enter] confirm  [Esc] cancel` hint
- [ ] T035 [US3] Add alcotest tests for US3 in `test/test_designer.ml`: `export_creates_valid_json` — export to temp file, read back, assert valid JSON with widget/wiring data; `import_roundtrip` — export then import, assert widget IDs match; `import_invalid_json_shows_error` — import a file with `{}` (no valid page), assert state unchanged and error result returned

**Checkpoint**: `dune test` passes. Export writes JSON file; Import restores page exactly; bad file shows error modal.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, resize handling, and final build validation.

- [ ] T036 [P] Handle terminal resize in `bin/designer/page.ml`: detect `LTerm_geom.size` change between `view` calls; update `Sidebar_widget` dimensions accordingly; verify preview re-renders at new size without crash
- [ ] T037 [P] Add empty preview hint in `bin/designer/preview.ml`: when `Page.get_widget_ids session page_id = []`, return centered hint string `"No widgets yet — press 'a' to add one"` styled with `themed_text`
- [ ] T038 [P] Enforce unique widget IDs in `bin/designer/form.ml` `validate_form`: check proposed ID against `Page.get_widget_ids`; if duplicate, add error `"ID already in use: {id}"` to form errors
- [ ] T039 [P] Add Quit confirmation in `bin/designer/menu.ml`/`page.ml`: when user selects Quit, open a `Confirm` modal; on Yes call `Navigation.quit`; on No close modal
- [ ] T040 Run `dune fmt --auto-promote` across all new files in `bin/designer/` and `test/test_designer.ml`; verify `dune build && dune test` passes clean with no warnings
- [ ] T041 Commit all changes on branch `002-page-designer-tui` with message `feat(designer): add Page Designer TUI`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (opam packages installed, dune file created)
- **US1 (Phase 3)**: Depends on Phase 2 — **MVP**
- **US4 (Phase 4)**: Depends on Phase 3 (needs working preview render + mode field in state)
- **US2 (Phase 5)**: Depends on Phase 3 (needs add_widget, compositor session, menu stack)
- **US3 (Phase 6)**: Depends on Phase 3 (needs compositor session and page_codec)
- **Polish (Phase 7)**: Depends on all story phases complete

### User Story Dependencies

- **US1 (P1)**: Blocks US2, US4 (both need the working composite state)
- **US2 (P2)**: Independent of US4; needs US1 compositor session
- **US4 (P2)**: Independent of US2; needs US1 preview render
- **US3 (P3)**: Independent of US2, US4; needs US1 compositor session only

### Parallel Opportunities Within US1

Tasks T009, T010 (menu + form) can run in parallel before T011 (add_widget) integrates them:

```
T009 (menu catalog) ─┐
                      ├─→ T011 (add_widget) → T012 → T013 → T014 → T015
T010 (form fields)  ─┘
```

### Parallel Opportunities Within US2

```
T022 (wizard menus) ─┐
T023 (action form)  ─┼─→ T024 (add_wiring) → T025 → T026 → T027
                      └─→ T028 (tests, parallel)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (pin packages, create scaffold)
2. Complete Phase 2: Foundational (state types, test skeleton)
3. Complete Phase 3: US1 (add/remove widgets, menu, form, preview, full page render)
4. **STOP and VALIDATE**: Run `_build/default/bin/designer/main.exe`, add 3 widgets, verify live preview
5. Proceed to Phase 4 (US4 — preview interaction) which is the second highest value add

### Incremental Delivery

1. Setup + Foundation → `dune build` passes
2. US1 → terminal app launches, widgets visible in preview (MVP!)
3. US4 → preview is interactive (Tab/Enter/Escape work)
4. US2 → wirings connect widgets
5. US3 → save/load pages
6. Polish → resize, edge cases, final commit

---

## Notes

- All OCaml files in `bin/designer/` use fully-qualified miaou-core module names (e.g. `Miaou_widgets_layout.Sidebar_widget`, `Miaou_internals.Focus_ring`)
- Copyright header required on all new `.ml` files (MIT, Nomadic Labs 2026)
- `[@@@warning "-32-34-37-69"]` on files with unused types (same pattern as existing widgets)
- `dune fmt --auto-promote` before every commit (Constitution V. Development Workflow)
- `dune build && dune test` must pass before every commit (Constitution III)
- Deprecated PAGE_SIG stubs (`handle_key`, `move`, `service_select`, etc.) are never called by `Runner_tui` — implement as `let handle_key s _ ~size:_ = s` etc.
