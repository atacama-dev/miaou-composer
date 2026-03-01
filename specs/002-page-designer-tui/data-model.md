# Data Model: Page Designer TUI

**Feature**: 002-page-designer-tui
**Date**: 2026-03-01
**Phase**: 1 — Design

## Entities

### 1. Designer State (`Designer_state.t`)

Top-level application state. Wraps all sub-states.

| Field | Type | Description |
|-------|------|-------------|
| `mode` | `Mode.t` | Current mode: `Design` or `Preview` |
| `menu` | `Menu_state.t` | Active menu navigation state |
| `form` | `Form_state.t option` | Active parameter form, if any |
| `preview_session` | `Session.t` | Compositor session for the preview page |
| `preview_page_id` | `string` | ID of the page being designed |
| `widget_counter` | `int` | Auto-increment for ID generation |
| `wiring_counter` | `int` | Auto-increment for wiring list index |
| `status` | `Status_info.t` | Info for the status bar |
| `modal` | `Modal_state.t option` | Active modal (e.g., file path input) |

**Invariants**:
- `preview_session` always contains exactly one page with ID = `preview_page_id`
- `widget_counter` > number of widgets (monotonically increasing)
- When `mode = Preview`, `form = None` and `modal = None`

---

### 2. Mode (`Mode.t`)

```ocaml
type t = Design | Preview
```

- `Design`: sidebar menu active, key events processed by designer
- `Preview`: key events forwarded to compositor's `send_key`

**Transitions**:
- `Design → Preview`: user presses `F5` or selects "Preview Mode" from menu
- `Preview → Design`: user presses `Escape`

---

### 3. Menu State (`Menu_state.t`)

Hierarchical menu navigation.

| Field | Type | Description |
|-------|------|-------------|
| `stack` | `Menu_level.t list` | Stack of menu levels (head = current) |

**Menu Level** (`Menu_level.t`):

| Field | Type | Description |
|-------|------|-------------|
| `title` | `string` | Display title for this menu level |
| `items` | `Menu_item.t array` | Items in this level |
| `cursor` | `int` | Index of focused item |

**Menu Item** (`Menu_item.t`):
```ocaml
type t = {
  label : string;
  hint : string;  (* keyboard shortcut hint *)
  action : menu_action;
}
```

**Menu Actions**:
- `Submenu of Menu_level.t` — push new level onto stack
- `AddWidget of widget_type` — open parameter form for widget type
- `RemoveWidget` — open widget selection for removal
- `AddWiring` — open wiring wizard step 1
- `RemoveWiring` — open wiring selection for removal
- `ListWirings` — show wirings list
- `SwitchPreview` — toggle preview mode
- `Export` — open export path modal
- `Import` — open import path modal
- `Quit` — exit

**Validation**:
- `cursor` must be in range `[0, Array.length items - 1]`
- `stack` is never empty (root menu always present)

---

### 4. Form State (`Form_state.t`)

Parameter input form for widget configuration.

| Field | Type | Description |
|-------|------|-------------|
| `widget_type` | `string` | Widget type being configured |
| `fields` | `Form_field.t array` | Parameter fields |
| `focused_field` | `int` | Currently focused field index |
| `errors` | `(int * string) list` | Validation errors: (field_index, message) |
| `is_submitting` | `bool` | True when Enter pressed on submit button |

**Form Field** (`Form_field.t`):
```ocaml
type field_kind = Text of Textbox.t | Bool of bool | Int of string (* raw input *)
type t = {
  name : string;
  label : string;
  kind : field_kind;
  required : bool;
}
```

**Validation Rules**:
- `id` field: must be non-empty, no spaces, unique across existing widgets
- `int` fields: must parse as valid integer
- `required` fields: must be non-empty

---

### 5. Modal State (`Modal_state.t`)

Overlay for single-input dialogs (file path, confirmation).

```ocaml
type modal_kind = FilePath of { on_confirm : string -> Designer_state.t -> Designer_state.t }
                | Confirm of { message : string; on_yes : Designer_state.t -> Designer_state.t }
                | Error of { message : string }

type t = {
  kind : modal_kind;
  input : Textbox.t;  (* for FilePath *)
}
```

---

### 6. Status Info (`Status_info.t`)

Data for the status bar display.

| Field | Type | Description |
|-------|------|-------------|
| `page_id` | `string` | Current page ID |
| `widget_count` | `int` | Number of widgets on page |
| `wiring_count` | `int` | Number of wirings |
| `focused_widget` | `string option` | ID of focused widget in preview |
| `mode` | `Mode.t` | Current mode |

---

### 7. Wiring Wizard State

Multi-step wizard for "Add Wiring". Embedded in `Menu_state` as a special menu flow.

**Steps**:
1. Select source widget (from list of widget IDs)
2. Select event (from widget's event list in catalog)
3. Select action type (set_value, toggle, submit, navigate)
4. Configure action parameters (target widget ID, value)

**Intermediate state**: stored as `wiring_step` in the form state during wizard flow.

---

## State Transitions

```
Initial: Designer_state with empty session, Design mode, root menu

Add Widget flow:
  menu: root → widget type submenu → [type selected]
  form: None → Some(Form for type) → None (on submit)
  session: unchanged → add_widget called on submit

Preview mode:
  mode: Design → Preview (F5 / menu)
  mode: Preview → Design (Escape)

Export flow:
  modal: None → Some(FilePath) → None (on confirm)
  file: page_to_json written to path

Import flow:
  modal: None → Some(FilePath) → None (on confirm)
  session: replaced with page_of_json result
```

---

## Entity Relationships

```
Designer_state
  ├── Mode (enum)
  ├── Menu_state
  │   └── Menu_level[] (stack)
  │       └── Menu_item[]
  ├── Form_state? (when editing params or wiring)
  │   └── Form_field[]
  ├── Modal_state? (when file path input active)
  └── Session (compositor) — owns the live page
      └── Page
          ├── Layout_tree (flex root)
          ├── Widget_box[] (hashtable)
          └── Wiring[]
```
