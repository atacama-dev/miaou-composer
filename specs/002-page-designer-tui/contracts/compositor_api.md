# Contract: Compositor API (Designer's view)

**Feature**: 002-page-designer-tui
**Date**: 2026-03-01

## Used by the Designer

The Page Designer TUI calls these compositor functions directly (same process, OCaml function calls).

### Session Management

```ocaml
(* Create a session with one page *)
val Session.create : unit -> Session.t
val Session.create_page : Session.t -> id:string -> Page.t

(* Get existing page *)
val Session.get_page : Session.t -> string -> Page.t option
```

### Page Mutation

```ocaml
(* Add widget to page root flex container *)
val Page.add_widget : Page.t -> widget_type:string -> params:Yojson.Safe.t -> (unit, string) result

(* Remove widget by ID *)
val Page.remove_widget : Page.t -> id:string -> (unit, string) result

(* Add wiring *)
val Page.add_wiring : Page.t -> source:string -> event:string -> action:Action.t -> (unit, string) result

(* Remove wiring by index *)
val Page.remove_wiring : Page.t -> index:int -> (unit, string) result

(* Query wirings *)
val Page.get_wirings : Page.t -> Wiring.t list

(* Query widget IDs *)
val Page.get_widget_ids : Page.t -> string list
```

### Rendering

```ocaml
(* Render page to ANSI string *)
val Page.render : Page.t -> cols:int -> rows:int -> string

(* Send key to focused widget (preview mode) *)
val Page.send_key : Page.t -> string -> unit
```

### Catalog

```ocaml
(* Get all widget types *)
val Catalog.all_entries : unit -> widget_entry list

(* Get params for a widget type *)
val Catalog.params_for : string -> param list option
```

### Export/Import (via Bridge)

```ocaml
(* Serialize page to JSON *)
val Page_codec.page_to_json : Page.t -> Yojson.Safe.t

(* Deserialize page from JSON *)
val Page_codec.page_of_json : Session.t -> Yojson.Safe.t -> (Page.t, string) result
```

### Error Handling

All mutating operations return `(unit, string) result`. The designer converts errors to:
- Form validation errors: shown in form
- Modal errors: shown as `Error` modal
- Import errors: shown as `Error` modal with list of problems
