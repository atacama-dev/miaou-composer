(** Page definition validation. *)

type severity = Error | Warning

type diagnostic = {
  path : string;
  severity : severity;
  code : string;
  message : string;
}

type result = {
  valid : bool;
  errors : diagnostic list;
  warnings : diagnostic list;
}

let valid_widget_types =
  [
    "button";
    "checkbox";
    "textbox";
    "textarea";
    "select";
    "radio";
    "switch";
    "pager";
    "list";
    "description_list";
  ]

let valid_layout_types = [ "flex"; "grid"; "box"; "card" ]

let diagnostic_to_json d =
  `Assoc
    [
      ("path", `String d.path);
      ("code", `String d.code);
      ("message", `String d.message);
    ]

let result_to_json r =
  `Assoc
    [
      ("valid", `Bool r.valid);
      ("errors", `List (List.map diagnostic_to_json r.errors));
      ("warnings", `List (List.map diagnostic_to_json r.warnings));
    ]

(** Validate a page definition JSON. *)
let validate_page_def (json : Yojson.Safe.t) : result =
  let diags = ref [] in
  let add sev path code message =
    diags := { path; severity = sev; code; message } :: !diags
  in
  let seen_ids = Hashtbl.create 16 in
  (* Walk the layout tree *)
  let rec walk_node path (node : Yojson.Safe.t) =
    match node with
    | `Assoc fields -> (
        match List.assoc_opt "type" fields with
        | None ->
            add Error path "missing_type"
              "Node is missing required 'type' field"
        | Some (`String typ) ->
            if List.mem typ valid_widget_types then begin
              (* It's a widget leaf — check ID *)
              match List.assoc_opt "id" fields with
              | None ->
                  add Error path "missing_id"
                    ("Widget of type '" ^ typ
                   ^ "' is missing required 'id' field")
              | Some (`String id) ->
                  if Hashtbl.mem seen_ids id then
                    add Error path "duplicate_id"
                      ("Duplicate widget ID: '" ^ id ^ "'")
                  else Hashtbl.replace seen_ids id path
              | Some _ ->
                  add Error path "invalid_id" "Widget 'id' must be a string"
            end
            else if List.mem typ valid_layout_types then begin
              (* It's a layout container — walk children *)
              match typ with
              | "flex" -> (
                  match List.assoc_opt "children" fields with
                  | Some (`List children) ->
                      List.iteri
                        (fun i child ->
                          walk_node
                            (Printf.sprintf "%s.children[%d]" path i)
                            child)
                        children
                  | Some _ ->
                      add Error path "invalid_children"
                        "Flex 'children' must be an array"
                  | None ->
                      add Warning path "empty_container"
                        "Flex container has no children")
              | "grid" -> (
                  match List.assoc_opt "children" fields with
                  | Some (`List children) ->
                      List.iteri
                        (fun i child ->
                          let child_node =
                            match child with
                            | `Assoc cf -> (
                                match List.assoc_opt "node" cf with
                                | Some n -> n
                                | None -> child)
                            | _ -> child
                          in
                          walk_node
                            (Printf.sprintf "%s.children[%d]" path i)
                            child_node)
                        children
                  | _ -> ())
              | "box" | "card" -> (
                  match List.assoc_opt "child" fields with
                  | Some child -> walk_node (path ^ ".child") child
                  | None -> ())
              | _ -> ()
            end
            else
              add Error path "unknown_type"
                (Printf.sprintf
                   "Unknown type '%s'. Valid widget types: %s. Valid layout \
                    types: %s"
                   typ
                   (String.concat ", " valid_widget_types)
                   (String.concat ", " valid_layout_types))
        | Some _ -> add Error path "invalid_type" "'type' must be a string")
    | _ -> add Error path "invalid_node" "Layout node must be an object"
  in
  (* Validate layout *)
  (match json with
  | `Assoc fields -> (
      (match List.assoc_opt "layout" fields with
      | Some layout -> walk_node ".layout" layout
      | None ->
          add Error "" "missing_layout" "Page definition is missing 'layout'");
      (* Validate focus_ring references *)
      match List.assoc_opt "focus_ring" fields with
      | Some (`List ring_ids) ->
          List.iteri
            (fun i id_json ->
              match id_json with
              | `String id ->
                  if not (Hashtbl.mem seen_ids id) then
                    add Error
                      (Printf.sprintf ".focus_ring[%d]" i)
                      "invalid_focus_ref"
                      (Printf.sprintf
                         "Focus ring references widget '%s' which does not \
                          exist in the layout"
                         id)
              | _ ->
                  add Error
                    (Printf.sprintf ".focus_ring[%d]" i)
                    "invalid_focus_entry" "Focus ring entries must be strings")
            ring_ids
      | Some _ ->
          add Error ".focus_ring" "invalid_focus_ring"
            "focus_ring must be an array"
      | None -> ())
  | _ -> add Error "" "invalid_page_def" "Page definition must be an object");
  let all_diags = List.rev !diags in
  let errors = List.filter (fun d -> d.severity = Error) all_diags in
  let warnings = List.filter (fun d -> d.severity = Warning) all_diags in
  { valid = errors = []; errors; warnings }
