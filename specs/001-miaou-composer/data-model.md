# Data Model: Miaou Composer

**Branch**: `001-miaou-composer` | **Date**: 2026-03-01

## Entity Relationship Overview

```
Session 1──* Page 1──1 Layout Tree
                  1──* Widget (stored by ID)
                  1──1 Focus Ring
                  1──* Wiring
                  1──* Modal (stack)
```

## Entities

### Session

The top-level runtime container. One session per MCP connection.

| Field      | Type                   | Description                     |
| ---------- | ---------------------- | ------------------------------- |
| id         | string                 | Auto-generated session ID       |
| pages      | (string, Page) map     | Live pages keyed by page ID     |
| created_at | timestamp              | Session creation time           |

**Invariants**:
- Page IDs are unique within a session
- At least one page must exist for interaction commands to work

### Page

A live UI composition with its own widget state, layout, and modal stack.

| Field       | Type                          | Description                          |
| ----------- | ----------------------------- | ------------------------------------ |
| id          | string                        | User-assigned page ID                |
| layout_tree | layout_node                   | Mutable tree of layout + widgets     |
| widgets     | (string, widget_box) hashtbl  | Widget instances keyed by ID         |
| focus_ring  | Focus_ring.t                  | Tab-order focus management           |
| wirings     | (string * string, action) map | (source_id, event) → action          |
| modal_stack | modal_entry list              | Stack of active modals               |
| size        | int * int                     | Viewport rows × cols                 |

**Invariants**:
- Widget IDs are unique within a page
- Focus ring contains only IDs of focusable widgets present in the widget store
- Wiring source and target IDs reference existing widgets (or are cleaned up on removal)

### Widget Box (Existential)

Type-erased widget with uniform interface for render, key handling, state query, and state update.

| Field   | Type                                             | Description                       |
| ------- | ------------------------------------------------ | --------------------------------- |
| widget  | 'a (existential)                                 | Concrete widget state             |
| render  | 'a → focus:bool → size → string                  | Render to ANSI string             |
| on_key  | 'a → key:string → 'a × key_result                | Handle keystroke                   |
| query   | 'a → json                                        | Serialize state to JSON            |
| update  | 'a → json → 'a                                   | Patch state from JSON              |
| events  | 'a → 'a → (string × json) list                   | Diff old/new state → fired events  |

**Invariants**:
- All closures capture the widget's concrete type at construction time
- No unsafe casts (Obj.magic) — type safety enforced by the existential

### Layout Node

A node in the mutable layout tree. Interior nodes are containers, leaves reference widgets.

| Variant | Fields                                                     | Description              |
| ------- | ---------------------------------------------------------- | ------------------------ |
| Leaf    | id: string, basis: basis                                   | Widget reference + sizing hint |
| Flex    | direction, gap, padding, justify, align, children (mutable) | Flex container           |
| Grid    | rows, cols, row_gap, col_gap, children (mutable)           | Grid container           |
| Boxed   | title?, style, padding, child (mutable)                    | Bordered wrapper         |
| Card    | title?, footer?, accent?, child (mutable)                  | Card wrapper             |

**Invariants**:
- Every Leaf.id must correspond to an entry in the page's widget store
- A widget ID appears in at most one Leaf node in the tree

### Wiring

A rule that maps a widget event to a compositor action.

| Field      | Type   | Description                      |
| ---------- | ------ | -------------------------------- |
| source_id  | string | Widget that fires the event      |
| event_name | string | Event type (click, toggle, etc.) |
| action     | action | What to do when event fires      |

### Action (Closed Variant)

| Variant       | Parameters                        | Description                      |
| ------------- | --------------------------------- | -------------------------------- |
| Set_text      | target: string, value: string     | Set text on target widget        |
| Set_checked   | target: string, value: bool       | Set checked state                |
| Toggle        | target: string                    | Toggle boolean state             |
| Append_text   | target: string, value: string     | Append text to target            |
| Push_modal    | modal_def: page_def               | Push a modal page                |
| Close_modal   | outcome: commit \| cancel          | Close topmost modal              |
| Navigate      | target: string                    | Switch to another page           |
| Back          | (none)                            | Navigate back                    |
| Quit          | (none)                            | Quit the session                 |
| Focus         | target: string                    | Move focus to target widget      |
| Emit          | event: string                     | Notify the MCP client            |
| Set_disabled  | target: string, value: bool       | Enable/disable a widget          |
| Set_visible   | target: string, value: bool       | Show/hide a widget               |
| Set_items     | target: string, items: string list | Update list/select items         |

### Widget Catalog Entry

Static metadata for each widget type (not per-instance).

| Field      | Type                                    | Description                 |
| ---------- | --------------------------------------- | --------------------------- |
| name       | string                                  | Widget type name            |
| category   | input \| display \| layout               | Classification              |
| params     | (name, type, required, default) list    | Constructor parameters      |
| events     | string list                             | Events this widget can fire |
| queryable  | (name, type) list                       | Gettable state properties   |
| focusable  | bool                                    | Whether it enters focus ring|

### Modal Entry

| Field     | Type        | Description                           |
| --------- | ----------- | ------------------------------------- |
| page      | Page        | The modal's own page (nested session) |
| ui        | modal_ui    | Title, width, dim_background, etc.    |
| on_close  | callback    | Invoked with final state + outcome    |

## State Transitions

### Page Lifecycle

```
Created → Active → (widgets added/removed/mutated) → Active → Exported/Destroyed
                          ↕
                    Modal Pushed/Popped
```

### Widget Lifecycle

```
Instantiated (from JSON params) → Added to page → (state mutated by keys/wirings) → Removed from page
```

### Focus Transitions

```
Widget added → Focus ring rebuilt → (Tab/Shift+Tab cycles) → Widget removed → Focus ring rebuilt
```

### Wiring Execution

```
Key pressed → Widget on_key → Diff state → Event detected?
  ├── No → Done
  └── Yes → Look up wiring → Execute action → Mutate target → Done
```
