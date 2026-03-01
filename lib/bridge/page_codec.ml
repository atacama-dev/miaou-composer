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
  `Assoc
    [
      ("id", `String page.id);
      ("layout", layout_json);
      ("wirings", wirings_json);
      ("focus_ring", `List (List.map (fun s -> `String s) focus_ids));
      ( "size",
        `Assoc [ ("rows", `Int page.size.rows); ("cols", `Int page.size.cols) ]
      );
    ]
