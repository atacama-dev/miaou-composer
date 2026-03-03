(** Wiring table: maps (source_widget_id, event_name) to an action. *)

type wiring_key = { source : string; event : string }

type t = (string, Action.t) Hashtbl.t
(** Key is "source:event" *)

let create () : t = Hashtbl.create 16
let make_key source event = source ^ ":" ^ event

let add (t : t) ~source ~event ~action =
  let key = make_key source event in
  let replaced = Hashtbl.mem t key in
  Hashtbl.replace t key action;
  replaced

let remove (t : t) ~source ~event =
  let key = make_key source event in
  let existed = Hashtbl.mem t key in
  Hashtbl.remove t key;
  existed

let find (t : t) ~source ~event = Hashtbl.find_opt t (make_key source event)

let to_list (t : t) =
  Hashtbl.fold
    (fun key action acc ->
      match String.split_on_char ':' key with
      | source :: rest ->
          let event = String.concat ":" rest in
          (source, event, action) :: acc
      | _ -> acc)
    t []

let remove_by_widget (t : t) ~widget_id =
  let to_remove =
    Hashtbl.fold
      (fun key _action acc ->
        if String.starts_with ~prefix:(widget_id ^ ":") key then key :: acc
        else acc)
      t []
  in
  List.iter (Hashtbl.remove t) to_remove

let remove_by_target (t : t) ~target_id =
  let to_remove =
    Hashtbl.fold
      (fun key action acc ->
        let targets_widget =
          match action with
          | Action.Set_text { target; _ } -> target = target_id
          | Set_checked { target; _ } -> target = target_id
          | Toggle { target } -> target = target_id
          | Append_text { target; _ } -> target = target_id
          | Focus { target } -> target = target_id
          | Set_disabled { target; _ } -> target = target_id
          | Set_visible { target; _ } -> target = target_id
          | Set_items { target; _ } -> target = target_id
          | Push_modal _ | Close_modal _ | Navigate _ | Back | Quit | Emit _
          | Set_state _ | Copy_widget_to_state _ | Inc_state _ | Reset_state _
          | Sequence _ | Call_tool _ ->
              false
        in
        if targets_widget then key :: acc else acc)
      t []
  in
  List.iter (Hashtbl.remove t) to_remove
