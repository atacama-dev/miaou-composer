# Research: Miaou Composer

**Branch**: `001-miaou-composer` | **Date**: 2026-03-01

## R1: MCP Protocol Implementation Strategy

**Decision**: Use the existing `ocaml-mcp` library by Thibaut Mattio rather than implementing JSON-RPC from scratch.

**Rationale**: A fully compliant OCaml MCP SDK already exists (`tmattio/ocaml-mcp`) with Eio-based transport (stdio, socket, memory), type-safe tool/resource registration, and dynamic JSON schema generation. Since Miaou already uses Eio, this is a natural fit. Implementing MCP from scratch would duplicate significant effort (capability negotiation, message framing, error handling) with no benefit.

**Alternatives considered**:
- **Hand-rolled JSON-RPC**: Simpler dependency tree but 500+ lines of boilerplate for protocol compliance, error codes, capability negotiation.
- **bmorphism/ocaml-mcp-sdk**: Uses Jane Street's oxcaml_effect, heavier dependency chain than needed.

**Dependencies**: `mcp`, `mcp-eio`, `mcp-sdk` opam packages.

## R2: JSON Serialization Library

**Decision**: Use `yojson` for JSON parsing/generation.

**Rationale**: Most popular OCaml JSON library, fast, well-maintained, already a transitive dependency of most OCaml projects. The `Yojson.Safe.t` type provides a good balance between safety and ergonomics for the widget descriptor format.

**Alternatives considered**:
- **Jsonm/Ezjsonm**: Streaming-oriented, overkill for our message sizes.
- **Ocplib-json-typed**: Adds typed layer but more complex API for no clear benefit here.

## R3: Widget Boxing Strategy (Existential GADT)

**Decision**: Use a record-based existential type (`widget_box`) that erases widget types behind a uniform interface of render/on_key/query/update closures.

**Rationale**: Miaou widgets have heterogeneous types (`Button_widget.t`, `Textbox_widget.t`, etc.) but the compositor needs to store them in a single hashtable keyed by string ID. The existential record pattern captures each widget's specific operations at construction time and hides the concrete type. This is the same pattern already used in miaou-core for type-safe witnesses.

**Design**:
```ocaml
type widget_box = Box : {
  widget : 'a;
  render : 'a -> focus:bool -> size:LTerm_geom.size -> string;
  on_key : 'a -> key:string -> 'a * Miaou_interfaces.Key_event.result;
  query  : 'a -> Yojson.Safe.t;
  update : 'a -> Yojson.Safe.t -> 'a;
  events : 'a -> string -> bool; (* did this key trigger an event? *)
} -> widget_box
```

**Alternatives considered**:
- **First-class modules**: More idiomatic but harder to store in collections without additional wrapping.
- **Obj.magic**: Unsafe, explicitly forbidden by project conventions.

## R4: Select Widget Polymorphism

**Decision**: For the compositor, `Select_widget` is always instantiated as `string Select_widget.t`. The JSON bridge converts all items to strings.

**Rationale**: The select widget is polymorphic (`'a Select_widget.t`) but the compositor receives items as JSON strings. Rather than trying to preserve polymorphism across the JSON boundary, we monomorphize to strings. The `to_string` function becomes `Fun.id`. This is the simplest approach and sufficient for the MCP use case — the AI agent works with string labels, not typed OCaml values.

**Alternatives considered**:
- **Parameterize by a tagged union type**: Overly complex for the use case.
- **Store items as `Yojson.Safe.t`**: Leaks JSON into the widget layer.

## R5: Layout Tree Representation

**Decision**: Use a mutable tree where interior nodes are layout containers and leaves reference widget IDs (looked up in the widget store at render time).

**Rationale**: The layout tree needs to support incremental mutations (add/remove/move children) without rebuilding the entire structure. Interior nodes hold layout parameters (direction, gap, padding) and children hold either nested layout nodes or widget ID references. At render time, the tree is walked to produce nested `Flex_layout.create` / `Grid_layout.create` calls with render closures that look up the widget by ID.

**Design**:
```ocaml
type layout_node =
  | Leaf of { id : string; basis : Flex_layout.basis }
  | Flex of { direction : Flex_layout.direction; gap : int; children : layout_node list ref; ... }
  | Grid of { rows : Grid_layout.track list; cols : Grid_layout.track list; children : (Grid_layout.placement * layout_node) list ref; ... }
  | Boxed of { title : string option; style : Box_widget.border_style; child : layout_node ref }
  | Card of { title : string option; footer : string option; child : layout_node ref }
```

## R6: Wiring Execution Model

**Decision**: Wirings are checked synchronously after each `on_key` call. If a widget event fires, the wiring table is consulted and actions are executed in the same tick before the next render.

**Rationale**: Deterministic execution — the AI agent can send a key and get a frame that reflects all wiring side effects. No async delays, no race conditions. This matches the headless driver's synchronous model.

**Flow**:
1. `send_key` → route to focused widget → `on_key`
2. Check if the key triggered a known event (click for button, toggle for checkbox, etc.)
3. Look up `(widget_id, event_name)` in wiring table
4. Execute action (mutate target widget, push modal, emit notification, etc.)
5. Render frame
6. Return frame + any emitted events

## R7: Headless Driver Integration

**Decision**: Use `Headless_driver.Stateful` for the compositor's rendering backend. Each page session initializes its own stateful driver instance.

**Rationale**: The stateful API (`init`, `send_key`, `get_screen_content`) maps directly to the compositor's needs. However, the compositor needs to intercept key handling to process wirings, so it wraps the page's `on_key` rather than delegating directly to the driver.

**Consideration**: The compositor creates a dynamic `PAGE_SIG` module per page. This module's `on_key` handler routes keys to the focused widget in the compositor's widget store, checks wirings, and returns the updated state. The headless driver then renders this page normally.

## R8: Event Detection Per Widget Type

**Decision**: Each widget type has a known set of events. Event detection is based on comparing widget state before and after `on_key`.

**Rationale**: Miaou widgets don't have an explicit event system — they return updated state from `on_key`. The compositor detects events by diffing:
- **Button**: `on_key` returns `(t, true)` via `handle_key` → click event
- **Checkbox**: `is_checked` changed → toggle event
- **Switch**: `is_on` changed → toggle event
- **Radio**: `is_selected` changed → select event
- **Textbox/Textarea**: `get_text` changed → change event
- **Select**: `get_selection` changed → select event

This is widget-specific logic in the boxing layer, not a general mechanism.
