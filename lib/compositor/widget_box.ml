(** Existential GADT for type-erased widget storage.

    Each widget type (button, textbox, etc.) has a different OCaml type. The
    compositor needs to store them all in a single hashtable keyed by string ID.
    This module provides the existential wrapper that erases the concrete type
    while preserving type-safe operations. *)

type widget_box =
  | Box : {
      type_name : string;
      widget : 'a;
      render : 'a -> focus:bool -> size:LTerm_geom.size -> string;
      on_key : 'a -> key:string -> 'a * bool;
          (** Returns (new_state, handled). *)
      query : 'a -> Yojson.Safe.t;
          (** Serialize current state to JSON for inspection. *)
      update : 'a -> Yojson.Safe.t -> 'a;
          (** Patch state from JSON (partial update). *)
      detect_events : 'a -> 'a -> (string * Yojson.Safe.t) list;
          (** Compare old and new state, return list of (event_name,
              event_data). *)
      focusable : bool;
    }
      -> widget_box

let type_name (Box b) = b.type_name
let render (Box b) ~focus ~size = b.render b.widget ~focus ~size

let on_key (Box b) ~key =
  let widget', handled = b.on_key b.widget ~key in
  (Box { b with widget = widget' }, handled)

let on_key_with_events (Box b) ~key =
  let old_widget = b.widget in
  let widget', handled = b.on_key b.widget ~key in
  let events = b.detect_events old_widget widget' in
  (Box { b with widget = widget' }, handled, events)

let query (Box b) = b.query b.widget
let update (Box b) patch = Box { b with widget = b.update b.widget patch }
let is_focusable (Box b) = b.focusable
