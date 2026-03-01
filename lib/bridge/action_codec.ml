(** JSON serialization for Action.t *)

open Miaou_composer_lib

let action_to_json (a : Action.t) : Yojson.Safe.t =
  match a with
  | Set_text { target; value } ->
      `Assoc
        [
          ("type", `String "set_text");
          ("target", `String target);
          ("value", `String value);
        ]
  | Set_checked { target; value } ->
      `Assoc
        [
          ("type", `String "set_checked");
          ("target", `String target);
          ("value", `Bool value);
        ]
  | Toggle { target } ->
      `Assoc [ ("type", `String "toggle"); ("target", `String target) ]
  | Append_text { target; value } ->
      `Assoc
        [
          ("type", `String "append_text");
          ("target", `String target);
          ("value", `String value);
        ]
  | Push_modal { modal_def } ->
      `Assoc [ ("type", `String "push_modal"); ("modal_def", modal_def) ]
  | Close_modal { outcome } ->
      `Assoc
        [
          ("type", `String "close_modal");
          ( "outcome",
            `String
              (match outcome with
              | Action.Commit -> "commit"
              | Cancel -> "cancel") );
        ]
  | Navigate { target } ->
      `Assoc [ ("type", `String "navigate"); ("target", `String target) ]
  | Back -> `Assoc [ ("type", `String "back") ]
  | Quit -> `Assoc [ ("type", `String "quit") ]
  | Focus { target } ->
      `Assoc [ ("type", `String "focus"); ("target", `String target) ]
  | Emit { event } ->
      `Assoc [ ("type", `String "emit"); ("event", `String event) ]
  | Set_disabled { target; value } ->
      `Assoc
        [
          ("type", `String "set_disabled");
          ("target", `String target);
          ("value", `Bool value);
        ]
  | Set_visible { target; value } ->
      `Assoc
        [
          ("type", `String "set_visible");
          ("target", `String target);
          ("value", `Bool value);
        ]
  | Set_items { target; items } ->
      `Assoc
        [
          ("type", `String "set_items");
          ("target", `String target);
          ("items", `List (List.map (fun s -> `String s) items));
        ]
  | Set_state { key; value } ->
      `Assoc
        [ ("type", `String "set_state"); ("key", `String key); ("value", value) ]
  | Copy_widget_to_state { key; source } ->
      `Assoc
        [
          ("type", `String "copy_widget_to_state");
          ("key", `String key);
          ("source", `String source);
        ]
  | Inc_state { key; by } ->
      `Assoc
        [
          ("type", `String "inc_state");
          ("key", `String key);
          ("by", `Float by);
        ]
  | Reset_state { key } ->
      `Assoc [ ("type", `String "reset_state"); ("key", `String key) ]

let get_string fields key =
  match List.assoc_opt key fields with Some (`String s) -> s | _ -> ""

let get_bool fields key =
  match List.assoc_opt key fields with Some (`Bool b) -> b | _ -> false

let get_string_list fields key =
  match List.assoc_opt key fields with
  | Some (`List items) ->
      List.filter_map
        (fun j -> match j with `String s -> Some s | _ -> None)
        items
  | _ -> []

let get_float fields key ~default =
  match List.assoc_opt key fields with
  | Some (`Float f) -> f
  | Some (`Int n) -> float_of_int n
  | _ -> default

let get_json fields key =
  match List.assoc_opt key fields with Some v -> v | None -> `Null

let action_of_json (json : Yojson.Safe.t) : (Action.t, string) result =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt "type" fields with
      | Some (`String "set_text") ->
          Ok
            (Set_text
               {
                 target = get_string fields "target";
                 value = get_string fields "value";
               })
      | Some (`String "set_checked") ->
          Ok
            (Set_checked
               {
                 target = get_string fields "target";
                 value = get_bool fields "value";
               })
      | Some (`String "toggle") ->
          Ok (Toggle { target = get_string fields "target" })
      | Some (`String "append_text") ->
          Ok
            (Append_text
               {
                 target = get_string fields "target";
                 value = get_string fields "value";
               })
      | Some (`String "push_modal") ->
          let modal_def =
            match List.assoc_opt "modal_def" fields with
            | Some j -> j
            | None -> `Null
          in
          Ok (Push_modal { modal_def })
      | Some (`String "close_modal") ->
          let outcome =
            match get_string fields "outcome" with
            | "cancel" -> Action.Cancel
            | _ -> Action.Commit
          in
          Ok (Close_modal { outcome })
      | Some (`String "navigate") ->
          Ok (Navigate { target = get_string fields "target" })
      | Some (`String "back") -> Ok Back
      | Some (`String "quit") -> Ok Quit
      | Some (`String "focus") ->
          Ok (Focus { target = get_string fields "target" })
      | Some (`String "emit") -> Ok (Emit { event = get_string fields "event" })
      | Some (`String "set_disabled") ->
          Ok
            (Set_disabled
               {
                 target = get_string fields "target";
                 value = get_bool fields "value";
               })
      | Some (`String "set_visible") ->
          Ok
            (Set_visible
               {
                 target = get_string fields "target";
                 value = get_bool fields "value";
               })
      | Some (`String "set_items") ->
          Ok
            (Set_items
               {
                 target = get_string fields "target";
                 items = get_string_list fields "items";
               })
      | Some (`String "set_state") ->
          Ok
            (Set_state
               {
                 key = get_string fields "key";
                 value = get_json fields "value";
               })
      | Some (`String "copy_widget_to_state") ->
          Ok
            (Copy_widget_to_state
               {
                 key = get_string fields "key";
                 source = get_string fields "source";
               })
      | Some (`String "inc_state") ->
          Ok
            (Inc_state
               {
                 key = get_string fields "key";
                 by = get_float fields "by" ~default:1.0;
               })
      | Some (`String "reset_state") ->
          Ok (Reset_state { key = get_string fields "key" })
      | Some (`String t) -> Error ("Unknown action type: " ^ t)
      | _ -> Error "Action must have a 'type' field")
  | _ -> Error "Action must be an object"
