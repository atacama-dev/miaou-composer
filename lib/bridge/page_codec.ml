(** Encode/decode complete page definitions from/to JSON.

    A page definition JSON looks like:
    {
      "id": "login",
      "layout": { ... layout tree ... },
      "wirings": [ { "source": ..., "event": ..., "action": {...} } ],
      "focus_ring": ["id1", "id2"],
      "size": { "rows": 24, "cols": 80 }
    }
*)

open Miaou_composer_lib

let get_string fields key =
  match List.assoc_opt key fields with Some (`String s) -> s | _ -> ""

let get_int fields key ~default =
  match List.assoc_opt key fields with Some (`Int n) -> n | _ -> default

let parse_state_scope s =
  match s with "persistent" -> Page.Persistent | _ -> Page.Ephemeral

let parse_state_typ s =
  match s with
  | "bool" -> `Bool
  | "int" -> `Int
  | "float" -> `Float
  | "json" -> `Json
  | "string_list" -> `String_list
  | _ -> `String

let parse_state_var (j : Yojson.Safe.t) : Page.state_var option =
  match j with
  | `Assoc fields ->
      let key = get_string fields "key" in
      if key = "" then None
      else
        let typ = parse_state_typ (get_string fields "type") in
        let default =
          match List.assoc_opt "default" fields with
          | Some v -> v
          | None -> `Null
        in
        let scope = parse_state_scope (get_string fields "scope") in
        Some { Page.key; typ; default; scope }
  | _ -> None

let parse_state_binding (j : Yojson.Safe.t) : Page.state_binding option =
  match j with
  | `Assoc fields ->
      let key = get_string fields "key" in
      let widget_id = get_string fields "widget_id" in
      let prop = get_string fields "prop" in
      if key = "" || widget_id = "" || prop = "" then None
      else Some { Page.key; widget_id; prop }
  | _ -> None

let state_var_to_json (sv : Page.state_var) : Yojson.Safe.t =
  let scope_str =
    match sv.scope with
    | Page.Ephemeral -> "ephemeral"
    | Page.Persistent -> "persistent"
  in
  let typ_str =
    match sv.typ with
    | `String -> "string"
    | `Bool -> "bool"
    | `Int -> "int"
    | `Float -> "float"
    | `Json -> "json"
    | `String_list -> "string_list"
  in
  `Assoc
    [
      ("key", `String sv.key);
      ("type", `String typ_str);
      ("default", sv.default);
      ("scope", `String scope_str);
    ]

let state_binding_to_json (sb : Page.state_binding) : Yojson.Safe.t =
  `Assoc
    [
      ("key", `String sb.key);
      ("widget_id", `String sb.widget_id);
      ("prop", `String sb.prop);
    ]

(** Decode a complete page definition from JSON. Returns a Page.t with all
    widgets instantiated and wirings connected. *)
let page_of_json (json : Yojson.Safe.t) : (Page.t, string) result =
  match json with
  | `Assoc fields -> (
      let id = get_string fields "id" in
      if id = "" then Error "Page definition missing 'id'"
      else
        (* Parse size *)
        let rows, cols =
          match List.assoc_opt "size" fields with
          | Some (`Assoc sf) ->
              (get_int sf "rows" ~default:24, get_int sf "cols" ~default:80)
          | _ -> (24, 80)
        in
        let size = { LTerm_geom.rows; cols } in
        (* Parse layout tree *)
        match List.assoc_opt "layout" fields with
        | None -> Error "Page definition missing 'layout'"
        | Some layout_json -> (
            match Layout_codec.layout_of_json layout_json with
            | Error e -> Error ("Layout parse error: " ^ e)
            | Ok (layout_tree, widget_defs) ->
                (* Create the page *)
                let page = Page.create ~id ~layout:layout_tree ~size in
                (* Instantiate all widgets found in the layout *)
                let widget_errors =
                  List.filter_map
                    (fun (wid, wjson) ->
                      match Widget_factory.create_widget wjson with
                      | Ok (created_id, wb) ->
                          if created_id <> wid then
                            Some
                              (Printf.sprintf
                                 "Widget ID mismatch: layout has '%s' but \
                                  widget declares '%s'"
                                 wid created_id)
                          else begin
                            Hashtbl.replace page.Page.widgets wid wb;
                            None
                          end
                      | Error e -> Some (Printf.sprintf "Widget '%s': %s" wid e))
                    widget_defs
                in
                if widget_errors <> [] then
                  Error (String.concat "; " widget_errors)
                else begin
                  (* Parse wirings *)
                  (match List.assoc_opt "wirings" fields with
                  | Some (`List wiring_jsons) ->
                      List.iter
                        (fun wj ->
                          match wj with
                          | `Assoc wf -> (
                              let source = get_string wf "source" in
                              let event = get_string wf "event" in
                              match List.assoc_opt "action" wf with
                              | Some action_json -> (
                                  match
                                    Action_codec.action_of_json action_json
                                  with
                                  | Ok action ->
                                      ignore
                                        (Wiring.add page.wirings ~source ~event
                                           ~action)
                                  | Error _ -> ())
                              | None -> ())
                          | _ -> ())
                        wiring_jsons
                  | _ -> ());
                  (* Rebuild focus ring *)
                  Page.rebuild_focus page;
                  (* Apply custom focus ring order if provided *)
                  (match List.assoc_opt "focus_ring" fields with
                  | Some (`List ids) ->
                      let ring_ids =
                        List.filter_map
                          (fun j ->
                            match j with `String s -> Some s | _ -> None)
                          ids
                      in
                      if ring_ids <> [] then
                        page.focus_ring <-
                          Miaou_internals.Focus_ring.create ring_ids
                  | _ -> ());
                  (* Parse state schema *)
                  (match List.assoc_opt "state_schema" fields with
                  | Some (`List items) ->
                      page.Page.state_schema <-
                        List.filter_map parse_state_var items
                  | _ -> ());
                  (* Parse state bindings *)
                  (match List.assoc_opt "state_bindings" fields with
                  | Some (`List items) ->
                      page.Page.state_bindings <-
                        List.filter_map parse_state_binding items
                  | _ -> ());
                  (* Parse key handlers *)
                  (match List.assoc_opt "key_handlers" fields with
                  | Some (`List items) ->
                      let handlers =
                        List.filter_map
                          (fun j ->
                            match j with
                            | `Assoc kf -> (
                                let key = get_string kf "key" in
                                if key = "" then None
                                else
                                  match List.assoc_opt "action" kf with
                                  | Some action_json -> (
                                      match
                                        Action_codec.action_of_json action_json
                                      with
                                      | Ok action -> Some (key, action)
                                      | Error _ -> None)
                                  | None -> None)
                            | _ -> None)
                          items
                      in
                      page.Page.key_handlers <- handlers
                  | _ -> ());
                  (* Parse tools *)
                  (match List.assoc_opt "tools" fields with
                  | Some (`List items) ->
                      let tools =
                        List.filter_map
                          (fun j ->
                            match Tool_codec.tool_def_of_json j with
                            | Ok t -> Some t
                            | Error _ -> None)
                          items
                      in
                      page.Page.tools <- tools
                  | _ -> ());
                  (* Parse init_actions *)
                  (match List.assoc_opt "init_actions" fields with
                  | Some (`List items) ->
                      let actions =
                        List.filter_map
                          (fun j ->
                            match Action_codec.action_of_json j with
                            | Ok a -> Some a
                            | Error _ -> None)
                          items
                      in
                      page.Page.init_actions <- actions
                  | _ -> ());
                  (* Initialize runtime state from schema *)
                  Page.init_state page;
                  Ok page
                end))
  | _ -> Error "Page definition must be a JSON object"

(** Encode a live page to JSON. *)
let page_to_json (page : Page.t) : Yojson.Safe.t =
  let widget_to_json id =
    match Hashtbl.find_opt page.widgets id with
    | Some wb ->
        let state = Widget_box.query wb in
        let type_name = Widget_box.type_name wb in
        Some
          (match state with
          | `Assoc state_fields ->
              `Assoc
                ([ ("type", `String type_name); ("id", `String id) ]
                @ state_fields)
          | _ -> `Assoc [ ("type", `String type_name); ("id", `String id) ])
    | None -> None
  in
  let layout_json = Layout_codec.layout_to_json page.layout ~widget_to_json in
  let wirings_json =
    `List
      (List.map
         (fun (source, event, action) ->
           `Assoc
             [
               ("source", `String source);
               ("event", `String event);
               ("action", Action_codec.action_to_json action);
             ])
         (Wiring.to_list page.wirings))
  in
  (* Collect focusable widget IDs from layout order *)
  let all_ids = Layout_tree.collect_ids page.layout in
  let focus_ids =
    List.filter
      (fun id ->
        match Hashtbl.find_opt page.widgets id with
        | Some wb -> Widget_box.is_focusable wb
        | None -> false)
      all_ids
  in
  let state_schema_json =
    `List (List.map state_var_to_json page.Page.state_schema)
  in
  let state_bindings_json =
    `List (List.map state_binding_to_json page.Page.state_bindings)
  in
  let key_handlers_json =
    `List
      (List.map
         (fun (key, action) ->
           `Assoc
             [
               ("key", `String key);
               ("action", Action_codec.action_to_json action);
             ])
         page.Page.key_handlers)
  in
  let tools_json =
    `List (List.map Tool_codec.tool_def_to_json page.Page.tools)
  in
  let init_actions_json =
    `List (List.map Action_codec.action_to_json page.Page.init_actions)
  in
  `Assoc
    [
      ("id", `String page.id);
      ("layout", layout_json);
      ("wirings", wirings_json);
      ("focus_ring", `List (List.map (fun s -> `String s) focus_ids));
      ( "size",
        `Assoc [ ("rows", `Int page.size.rows); ("cols", `Int page.size.cols) ]
      );
      ("state_schema", state_schema_json);
      ("state_bindings", state_bindings_json);
      ("key_handlers", key_handlers_json);
      ("tools", tools_json);
      ("init_actions", init_actions_json);
    ]
