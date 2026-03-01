(** MCP tool call handlers. Each handler receives the session and arguments, and
    returns a JSON result. *)

open Miaou_composer_lib
open Miaou_composer_bridge
open Miaou_composer_export

let get_string args key =
  match List.assoc_opt key args with Some (`String s) -> Some s | _ -> None

let get_int args key =
  match List.assoc_opt key args with Some (`Int n) -> Some n | _ -> None

let require_string args key =
  match get_string args key with
  | Some s -> Ok s
  | None -> Error (Printf.sprintf "Missing required parameter: %s" key)

let require_page session args =
  match require_string args "page_id" with
  | Error e -> Error e
  | Ok page_id -> (
      match Session.get_page session ~page_id with
      | Some page -> Ok page
      | None -> Error (Printf.sprintf "Page not found: %s" page_id))

let ok_result json = Ok (`Assoc [ ("result", json) ])

let handle_tool (session : Session.t) ~tool_name
    ~(args : (string * Yojson.Safe.t) list) : (Yojson.Safe.t, string) result =
  match tool_name with
  | "create_page" -> (
      match List.assoc_opt "page_def" args with
      | None -> Error "Missing required parameter: page_def"
      | Some page_def -> (
          match Page_codec.page_of_json page_def with
          | Error e -> Error ("Failed to create page: " ^ e)
          | Ok page -> (
              match Session.add_page session page with
              | Error e -> Error e
              | Ok () ->
                  ok_result
                    (`Assoc
                       [
                         ("page_id", `String page.id);
                         ("message", `String "Page created successfully");
                       ]))))
  | "delete_page" -> (
      match require_string args "page_id" with
      | Error e -> Error e
      | Ok page_id -> (
          match Session.remove_page session ~page_id with
          | Error e -> Error e
          | Ok () ->
              ok_result
                (`Assoc [ ("message", `String ("Page deleted: " ^ page_id)) ])))
  | "list_pages" -> ok_result (Json_export.export_session_summary session)
  | "add_widget" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match List.assoc_opt "widget_def" args with
          | None -> Error "Missing required parameter: widget_def"
          | Some widget_def -> (
              match Widget_factory.create_widget widget_def with
              | Error e -> Error ("Failed to create widget: " ^ e)
              | Ok (id, wb) ->
                  let path =
                    match List.assoc_opt "path" args with
                    | Some (`List indices) ->
                        List.filter_map
                          (fun j -> match j with `Int n -> Some n | _ -> None)
                          indices
                    | _ -> []
                  in
                  let position =
                    match get_int args "position" with
                    | Some n -> n
                    | None -> 999
                  in
                  Hashtbl.replace page.Page.widgets id wb;
                  let leaf = Layout_tree.Leaf { id; basis = Auto } in
                  if Layout_tree.add_child_at page.layout ~path ~position leaf
                  then begin
                    Page.rebuild_focus page;
                    ok_result
                      (`Assoc
                         [
                           ("widget_id", `String id);
                           ("message", `String "Widget added");
                         ])
                  end
                  else begin
                    Hashtbl.remove page.widgets id;
                    Error "Invalid parent path"
                  end)))
  | "remove_widget" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match require_string args "widget_id" with
          | Error e -> Error e
          | Ok widget_id -> (
              match Page.remove_widget page ~id:widget_id with
              | Error e -> Error e
              | Ok () ->
                  ok_result
                    (`Assoc
                       [ ("message", `String ("Widget removed: " ^ widget_id)) ])
              )))
  | "update_widget" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match require_string args "widget_id" with
          | Error e -> Error e
          | Ok widget_id -> (
              match List.assoc_opt "patch" args with
              | None -> Error "Missing required parameter: patch"
              | Some patch -> (
                  match Page.update_widget page ~id:widget_id ~patch with
                  | Error e -> Error e
                  | Ok () ->
                      ok_result
                        (`Assoc
                           [
                             ( "message",
                               `String ("Widget updated: " ^ widget_id) );
                           ])))))
  | "query_widget" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match require_string args "widget_id" with
          | Error e -> Error e
          | Ok widget_id -> (
              match Hashtbl.find_opt page.widgets widget_id with
              | None -> Error ("Widget not found: " ^ widget_id)
              | Some wb ->
                  ok_result
                    (`Assoc
                       [
                         ("widget_id", `String widget_id);
                         ("type", `String (Widget_box.type_name wb));
                         ("state", Widget_box.query wb);
                         ("focusable", `Bool (Widget_box.is_focusable wb));
                       ]))))
  | "add_wiring" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match
            ( require_string args "source",
              require_string args "event",
              List.assoc_opt "action" args )
          with
          | Ok source, Ok event, Some action_json -> (
              match Action_codec.action_of_json action_json with
              | Error e -> Error ("Invalid action: " ^ e)
              | Ok action ->
                  let replaced =
                    Wiring.add page.wirings ~source ~event ~action
                  in
                  ok_result
                    (`Assoc
                       [
                         ( "message",
                           `String
                             (if replaced then "Wiring replaced"
                              else "Wiring added") );
                       ]))
          | Error e, _, _ | _, Error e, _ -> Error e
          | _, _, None -> Error "Missing required parameter: action"))
  | "remove_wiring" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match (require_string args "source", require_string args "event") with
          | Ok source, Ok event ->
              let existed = Wiring.remove page.wirings ~source ~event in
              if existed then
                ok_result (`Assoc [ ("message", `String "Wiring removed") ])
              else Error "Wiring not found"
          | Error e, _ | _, Error e -> Error e))
  | "list_wirings" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page ->
          let wirings =
            List.map
              (fun (source, event, action) ->
                `Assoc
                  [
                    ("source", `String source);
                    ("event", `String event);
                    ("action", Action_codec.action_to_json action);
                  ])
              (Wiring.to_list page.wirings)
          in
          ok_result (`Assoc [ ("wirings", `List wirings) ]))
  | "send_key" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match require_string args "key" with
          | Error e -> Error e
          | Ok key ->
              let events = Page.send_key page ~key in
              ok_result
                (`Assoc
                   [
                     ( "events",
                       `List
                         (List.map
                            (fun (e : Page.emit_event) ->
                              `Assoc
                                [ ("name", `String e.name); ("state", e.state) ])
                            events) );
                   ])))
  | "render" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> ok_result (Json_export.export_rendered page))
  | "get_state" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> ok_result (Json_export.export_page_state page))
  | "execute_action" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match List.assoc_opt "action" args with
          | None -> Error "Missing required parameter: action"
          | Some action_json -> (
              match Action_codec.action_of_json action_json with
              | Error e -> Error ("Invalid action: " ^ e)
              | Ok action ->
                  let events = Page.execute_action page action in
                  ok_result
                    (`Assoc
                       [
                         ( "events",
                           `List
                             (List.map
                                (fun (e : Page.emit_event) ->
                                  `Assoc
                                    [
                                      ("name", `String e.name);
                                      ("state", e.state);
                                    ])
                                events) );
                       ]))))
  | "validate_page" -> (
      match List.assoc_opt "page_def" args with
      | None -> Error "Missing required parameter: page_def"
      | Some page_def ->
          let result = Validator.validate_page_def page_def in
          ok_result (Validator.result_to_json result))
  | "get_catalog" ->
      let widgets = Catalog.widget_catalog () in
      let actions = Catalog.action_catalog () in
      let layouts = Catalog.layout_catalog () in
      ok_result
        (`Assoc
           [
             ("widgets", `List (List.map Catalog.entry_to_json widgets));
             ("actions", `List (List.map Catalog.action_to_json actions));
             ("layouts", `List (List.map Catalog.layout_to_json layouts));
           ])
  | "resize" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match (get_int args "rows", get_int args "cols") with
          | Some rows, Some cols ->
              page.size <- { LTerm_geom.rows; cols };
              ok_result
                (`Assoc
                   [
                     ( "message",
                       `String (Printf.sprintf "Resized to %dx%d" cols rows) );
                   ])
          | _ -> Error "Missing required parameters: rows, cols"))
  | "focus" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> (
          match require_string args "widget_id" with
          | Error e -> Error e
          | Ok widget_id ->
              page.focus_ring <-
                Miaou_internals.Focus_ring.focus page.focus_ring widget_id;
              ok_result
                (`Assoc [ ("message", `String ("Focused: " ^ widget_id)) ])))
  | "get_focus" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page ->
          let current, index, total = Page.query_focus page in
          ok_result
            (`Assoc
               [
                 ( "current",
                   match current with Some id -> `String id | None -> `Null );
                 ("index", `Int index);
                 ("total", `Int total);
               ]))
  | _ -> Error ("Unknown tool: " ^ tool_name)
