# MCP Tool Contracts: Miaou Composer

**Branch**: `001-miaou-composer` | **Date**: 2026-03-01

All tools are exposed via the MCP protocol (JSON-RPC 2.0 over stdio). Tool names are namespaced under `miaou/`.

---

## Discovery Tools

### `miaou/list_widgets`

Returns the full widget catalog.

**Input**: (none)

**Output**:
```json
{
  "widgets": [
    {
      "name": "button",
      "category": "input",
      "params": [
        { "name": "label", "type": "string", "required": true },
        { "name": "disabled", "type": "bool", "required": false, "default": false }
      ],
      "events": ["click"],
      "queryable": [{ "name": "label", "type": "string" }],
      "focusable": true
    }
  ]
}
```

### `miaou/list_actions`

Returns all available wiring action types.

**Input**: (none)

**Output**:
```json
{
  "actions": [
    {
      "name": "set_text",
      "params": [
        { "name": "target", "type": "widget_id", "required": true },
        { "name": "value", "type": "string", "required": true }
      ]
    }
  ]
}
```

### `miaou/list_layout_types`

Returns all available layout container types.

**Input**: (none)

**Output**:
```json
{
  "layouts": [
    {
      "name": "flex",
      "params": [
        { "name": "direction", "type": "row|column", "required": false, "default": "column" },
        { "name": "gap", "type": "int", "required": false, "default": 0 },
        { "name": "padding", "type": "padding", "required": false },
        { "name": "justify", "type": "start|center|end|space_between|space_around", "required": false, "default": "start" },
        { "name": "align_items", "type": "start|center|end|stretch", "required": false, "default": "stretch" }
      ]
    }
  ]
}
```

---

## Composition Tools

### `miaou/create_page`

Create a new page from a layout definition.

**Input**:
```json
{
  "page_id": "my_page",
  "size": { "rows": 24, "cols": 80 },
  "layout": { <layout_node> },
  "focus_ring": ["widget_id_1", "widget_id_2"],
  "wirings": [
    { "source": "btn1", "event": "click", "action": { "type": "emit", "event": "btn1_clicked" } }
  ]
}
```

**Output**:
```json
{
  "page_id": "my_page",
  "render": "<ANSI string of initial frame>"
}
```

**Errors**: duplicate page_id, invalid layout definition

### `miaou/add_widget`

Add a widget to an existing page at a specified location in the layout tree.

**Input**:
```json
{
  "page_id": "my_page",
  "parent_path": ".layout.children[1]",
  "position": 0,
  "widget": {
    "type": "textbox",
    "id": "name_field",
    "title": "Name",
    "initial": "",
    "placeholder": "Enter name"
  },
  "basis": "auto"
}
```

**Output**:
```json
{
  "widget_id": "name_field",
  "render": "<ANSI string of updated frame>"
}
```

**Errors**: duplicate widget_id, invalid parent_path, unknown widget type

### `miaou/remove_widget`

Remove a widget from a page.

**Input**:
```json
{
  "page_id": "my_page",
  "widget_id": "name_field"
}
```

**Output**:
```json
{
  "removed": true,
  "render": "<ANSI string of updated frame>"
}
```

**Errors**: widget_id not found

### `miaou/move_widget`

Move a widget to a different location in the layout tree.

**Input**:
```json
{
  "page_id": "my_page",
  "widget_id": "name_field",
  "new_parent_path": ".layout.children[0]",
  "position": 2
}
```

**Output**:
```json
{
  "moved": true,
  "render": "<ANSI string of updated frame>"
}
```

### `miaou/update_widget`

Patch widget properties/state.

**Input**:
```json
{
  "page_id": "my_page",
  "widget_id": "name_field",
  "patch": {
    "title": "Full Name",
    "text": "John Doe"
  }
}
```

**Output**:
```json
{
  "updated": true,
  "render": "<ANSI string of updated frame>"
}
```

---

## Wiring Tools

### `miaou/wire`

Add or replace a wiring rule.

**Input**:
```json
{
  "page_id": "my_page",
  "source": "save_btn",
  "event": "click",
  "action": {
    "type": "emit",
    "event": "save_requested"
  }
}
```

**Output**:
```json
{
  "wired": true,
  "replaced": false
}
```

### `miaou/unwire`

Remove a wiring rule.

**Input**:
```json
{
  "page_id": "my_page",
  "source": "save_btn",
  "event": "click"
}
```

**Output**:
```json
{
  "unwired": true
}
```

### `miaou/list_wirings`

List all wirings on a page.

**Input**:
```json
{
  "page_id": "my_page"
}
```

**Output**:
```json
{
  "wirings": [
    { "source": "save_btn", "event": "click", "action": { "type": "emit", "event": "save_requested" } },
    { "source": "cancel_btn", "event": "click", "action": { "type": "back" } }
  ]
}
```

---

## Interaction Tools

### `miaou/send_key`

Send a single keystroke to the active page.

**Input**:
```json
{
  "page_id": "my_page",
  "key": "Enter"
}
```

**Output**:
```json
{
  "render": "<ANSI string after key processing>",
  "events": [
    { "name": "save_requested", "state": { "name_field": { "text": "John" } } }
  ],
  "navigation": null
}
```

Key names follow Miaou conventions: `"Up"`, `"Down"`, `"Left"`, `"Right"`, `"Enter"`, `"Escape"`, `"Tab"`, `"S-Tab"`, `"C-a"`, `"C-c"`, `"Backspace"`, `"Delete"`, `"Home"`, `"End"`, `"PageUp"`, `"PageDown"`, `"F1"`–`"F12"`, or literal characters like `"a"`, `"Z"`, `"1"`.

### `miaou/send_keys`

Send a sequence of keystrokes.

**Input**:
```json
{
  "page_id": "my_page",
  "keys": ["H", "e", "l", "l", "o", "Tab", "Enter"]
}
```

**Output**: Same as `send_key` but reflects state after all keys processed. Events accumulated.

### `miaou/tick`

Advance one render cycle without input. Useful for observing timer/service effects.

**Input**:
```json
{
  "page_id": "my_page"
}
```

**Output**:
```json
{
  "render": "<ANSI string>"
}
```

### `miaou/focus`

Move focus to a specific widget by ID.

**Input**:
```json
{
  "page_id": "my_page",
  "widget_id": "email_field"
}
```

**Output**:
```json
{
  "focused": true,
  "render": "<ANSI string>"
}
```

### `miaou/resize`

Change viewport dimensions.

**Input**:
```json
{
  "page_id": "my_page",
  "rows": 30,
  "cols": 120
}
```

**Output**:
```json
{
  "render": "<ANSI string at new size>"
}
```

---

## Modal Tools

### `miaou/push_modal`

Push a modal dialog onto the page's modal stack.

**Input**:
```json
{
  "page_id": "my_page",
  "modal": {
    "title": "Confirm",
    "dim_background": true,
    "max_width": { "type": "fixed", "value": 40 },
    "layout": { <layout_node> },
    "focus_ring": ["yes_btn", "no_btn"]
  }
}
```

**Output**:
```json
{
  "modal_depth": 1,
  "render": "<ANSI string with modal overlay>"
}
```

### `miaou/close_modal`

Close the topmost modal.

**Input**:
```json
{
  "page_id": "my_page",
  "outcome": "commit"
}
```

**Output**:
```json
{
  "modal_depth": 0,
  "modal_state": { "yes_btn": {}, "no_btn": {} },
  "render": "<ANSI string without modal>"
}
```

---

## Inspection Tools

### `miaou/capture`

Get the current rendered frame.

**Input**:
```json
{
  "page_id": "my_page"
}
```

**Output**:
```json
{
  "render": "<ANSI string>",
  "size": { "rows": 24, "cols": 80 }
}
```

### `miaou/get_region`

Extract a rectangular region from the rendered frame.

**Input**:
```json
{
  "page_id": "my_page",
  "top": 2,
  "left": 5,
  "height": 3,
  "width": 20
}
```

**Output**:
```json
{
  "region": "<extracted text>"
}
```

### `miaou/query_widget`

Query the state of a specific widget.

**Input**:
```json
{
  "page_id": "my_page",
  "widget_id": "name_field"
}
```

**Output**:
```json
{
  "widget_id": "name_field",
  "type": "textbox",
  "state": {
    "text": "John Doe",
    "cursor": 8
  }
}
```

### `miaou/query_focus`

Query which widget currently has focus.

**Input**:
```json
{
  "page_id": "my_page"
}
```

**Output**:
```json
{
  "focused_widget": "name_field",
  "focus_index": 0,
  "total_focusable": 4
}
```

### `miaou/query_modal`

Query modal stack state.

**Input**:
```json
{
  "page_id": "my_page"
}
```

**Output**:
```json
{
  "has_modal": true,
  "depth": 1,
  "top_title": "Confirm",
  "stack": [
    { "title": "Confirm", "dim_background": true }
  ]
}
```

### `miaou/query_all_state`

Dump all widget states on a page.

**Input**:
```json
{
  "page_id": "my_page"
}
```

**Output**:
```json
{
  "page_id": "my_page",
  "focused": "name_field",
  "has_modal": false,
  "widgets": {
    "name_field": { "type": "textbox", "state": { "text": "John", "cursor": 4 } },
    "save_btn": { "type": "button", "state": { "label": "Save", "disabled": false } },
    "notify_cb": { "type": "checkbox", "state": { "label": "Notify", "checked": true } }
  }
}
```

---

## Validation Tool

### `miaou/validate_page`

Validate a page definition without instantiating it.

**Input**:
```json
{
  "page_def": { <same format as create_page input> }
}
```

**Output**:
```json
{
  "valid": false,
  "errors": [
    { "path": ".layout.children[2]", "code": "unknown_widget_type", "message": "Unknown widget type 'buttton'. Valid types: button, checkbox, textbox, ..." }
  ],
  "warnings": [
    { "path": ".focus_ring", "code": "missing_focusable", "message": "Widget 'cancel_btn' is not in the focus ring but is focusable" }
  ]
}
```

---

## Export Tool

### `miaou/export_json`

Export the current page state as a portable JSON document.

**Input**:
```json
{
  "page_id": "my_page"
}
```

**Output**:
```json
{
  "page_def": {
    "page_id": "my_page",
    "size": { "rows": 24, "cols": 80 },
    "layout": { <layout_node tree with widget definitions inline> },
    "focus_ring": ["name_field", "save_btn"],
    "wirings": [
      { "source": "save_btn", "event": "click", "action": { "type": "emit", "event": "save" } }
    ]
  }
}
```

---

## JSON Format: Layout Node

Layout nodes are recursive JSON objects used in `create_page`, `push_modal`, and `export_json`.

### Widget Leaf
```json
{
  "type": "button",
  "id": "save_btn",
  "label": "Save",
  "disabled": false,
  "basis": "auto"
}
```

### Flex Container
```json
{
  "type": "flex",
  "direction": "column",
  "gap": 1,
  "padding": { "top": 1, "left": 2, "right": 2, "bottom": 1 },
  "justify": "start",
  "align_items": "stretch",
  "children": [ <layout_node>, ... ]
}
```

### Grid Container
```json
{
  "type": "grid",
  "rows": [{ "type": "auto" }, { "type": "fr", "value": 1.0 }],
  "cols": [{ "type": "px", "value": 20 }, { "type": "fr", "value": 1.0 }],
  "row_gap": 0,
  "col_gap": 1,
  "children": [
    { "row": 0, "col": 0, "node": <layout_node> },
    { "row": 0, "col": 1, "row_span": 2, "node": <layout_node> }
  ]
}
```

### Box Container
```json
{
  "type": "box",
  "title": "Settings",
  "style": "rounded",
  "padding": { "top": 0, "left": 1, "right": 1, "bottom": 0 },
  "child": <layout_node>
}
```

### Card Container
```json
{
  "type": "card",
  "title": "Summary",
  "footer": "Last updated: now",
  "accent": 33,
  "child": <layout_node>
}
```
