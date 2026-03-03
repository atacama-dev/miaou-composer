(** MCP tool call handlers. Each handler receives the session and arguments, and
    returns a JSON result. *)

open Miaou_composer_lib
open Miaou_composer_bridge
open Miaou_composer_export

(* ── Headless session table ─────────────────────────────────────────────── *)

type headless_session = { ic : in_channel; oc : out_channel; pid : int }

let headless_sessions : (string, headless_session) Hashtbl.t = Hashtbl.create 4
let headless_id_counter = ref 0

let fresh_session_id () =
  incr headless_id_counter;
  Printf.sprintf "hs%d" !headless_id_counter

(** Send a JSON command to a headless session and read back one JSON line.
    Returns [Error msg] if the process has closed its end. *)
let headless_rpc (s : headless_session) (cmd : Yojson.Safe.t) :
    (Yojson.Safe.t, string) result =
  (try
     output_string s.oc (Yojson.Safe.to_string cmd);
     output_char s.oc '\n';
     flush s.oc
   with Sys_error e -> raise (Sys_error e));
  try
    let line = input_line s.ic in
    Ok (Yojson.Safe.from_string line)
  with
  | End_of_file -> Error "Headless process closed its output"
  | Yojson.Json_error e -> Error ("Bad JSON from headless process: " ^ e)

let frame_of_json json =
  match json with
  | `Assoc pairs -> (
      match List.assoc_opt "type" pairs with
      | Some (`String "frame") -> (
          match List.assoc_opt "text" pairs with
          | Some (`String text) -> Ok text
          | _ -> Error "Missing 'text' in frame response")
      | Some (`String "nav") ->
          let action =
            match List.assoc_opt "action" pairs with
            | Some (`String a) -> a
            | _ -> "unknown"
          in
          Ok (Printf.sprintf "[navigation: %s]" action)
      | Some (`String "error") ->
          let msg =
            match List.assoc_opt "message" pairs with
            | Some (`String m) -> m
            | _ -> "unknown error"
          in
          Error ("Headless error: " ^ msg)
      | _ -> Error "Unexpected response from headless process")
  | _ -> Error "Non-object JSON from headless process"

let require_session args key =
  match List.assoc_opt key args with
  | Some (`String id) -> (
      match Hashtbl.find_opt headless_sessions id with
      | Some s -> Ok s
      | None -> Error (Printf.sprintf "Headless session not found: %s" id))
  | _ -> Error (Printf.sprintf "Missing required parameter: %s" key)

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
                                [
                                  ("name", `String e.name); ("state", e.snapshot);
                                ])
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
                                      ("state", e.snapshot);
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
      (* Enrich compositor widgets with mli from the registry *)
      let enrich_widget_json json name =
        match Miaou_registry.find ~name with
        | None -> json
        | Some entry -> (
            match json with
            | `Assoc pairs -> `Assoc (pairs @ [ ("mli", `String entry.mli) ])
            | other -> other)
      in
      let widget_jsons =
        List.map
          (fun e -> enrich_widget_json (Catalog.entry_to_json e) e.Catalog.name)
          widgets
      in
      (* Append registry-only widgets (not in compositor catalog) *)
      let catalog_names = List.map (fun e -> e.Catalog.name) widgets in
      let registry_only =
        List.filter_map
          (fun (entry : Miaou_registry.entry) ->
            if List.mem entry.name catalog_names then None
            else
              Some
                (`Assoc
                   [ ("name", `String entry.name); ("mli", `String entry.mli) ]))
          (Miaou_registry.list ())
      in
      ok_result
        (`Assoc
           [
             ("widgets", `List (widget_jsons @ registry_only));
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
  | "export_page" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page -> ok_result (Page_codec.page_to_json page))
  | "render_text" -> (
      match require_page session args with
      | Error e -> Error e
      | Ok page ->
          let rendered = Json_export.export_rendered page in
          let text =
            match rendered with
            | `String s -> Ansi_strip.strip s
            | _ -> Ansi_strip.strip (Yojson.Safe.to_string rendered)
          in
          ok_result (`String text))
  | "headless_init" -> (
      match require_string args "binary" with
      | Error e -> Error e
      | Ok binary -> (
          let rows =
            match get_int args "rows" with Some n -> n | None -> 24
          in
          let cols =
            match get_int args "cols" with Some n -> n | None -> 80
          in
          let viewer_port = get_int args "viewer_port" in
          (* Build environment: current env + MIAOU_DRIVER=headless + extras *)
          let base_env = Unix.environment () in
          let extra_env =
            match List.assoc_opt "env" args with
            | Some (`Assoc pairs) ->
                List.filter_map
                  (fun (k, v) ->
                    match v with `String s -> Some (k ^ "=" ^ s) | _ -> None)
                  pairs
            | _ -> []
          in
          let viewer_env =
            match viewer_port with
            | Some p -> [ Printf.sprintf "MIAOU_WEB_VIEWER_PORT=%d" p ]
            | None -> []
          in
          let env =
            Array.append base_env
              (Array.of_list
                 ([
                    "MIAOU_DRIVER=headless";
                    Printf.sprintf "MIAOU_HEADLESS_ROWS=%d" rows;
                    Printf.sprintf "MIAOU_HEADLESS_COLS=%d" cols;
                  ]
                 @ viewer_env @ extra_env))
          in
          let ic_read, ic_write = Unix.pipe () in
          let oc_read, oc_write = Unix.pipe () in
          let er_read, er_write = Unix.pipe () in
          try
            let pid =
              Unix.create_process_env binary [| binary |] env oc_read ic_write
                er_write
            in
            Unix.close oc_read;
            Unix.close ic_write;
            Unix.close er_write;
            Unix.close er_read;
            let ic = Unix.in_channel_of_descr ic_read in
            let oc = Unix.out_channel_of_descr oc_write in
            let s = { ic; oc; pid } in
            (* Send initial resize *)
            let init_cmd =
              `Assoc
                [
                  ("cmd", `String "resize");
                  ("rows", `Int rows);
                  ("cols", `Int cols);
                ]
            in
            match headless_rpc s init_cmd with
            | Error e ->
                Unix.close ic_read;
                Unix.close oc_write;
                Error ("Failed to initialize headless session: " ^ e)
            | Ok json -> (
                match frame_of_json json with
                | Error e ->
                    Unix.close ic_read;
                    Unix.close oc_write;
                    Error e
                | Ok text ->
                    let sid = fresh_session_id () in
                    Hashtbl.replace headless_sessions sid s;
                    let viewer_url =
                      match viewer_port with
                      | Some p ->
                          [
                            ( "viewer_url",
                              `String
                                (Printf.sprintf "http://127.0.0.1:%d/viewer" p)
                            );
                          ]
                      | None -> []
                    in
                    ok_result
                      (`Assoc
                         ([
                            ("session", `String sid);
                            ("text", `String text);
                            ("rows", `Int rows);
                            ("cols", `Int cols);
                          ]
                         @ viewer_url)))
          with Unix.Unix_error (err, _, _) ->
            Unix.close ic_read;
            Unix.close ic_write;
            Unix.close oc_read;
            Unix.close oc_write;
            Unix.close er_read;
            Unix.close er_write;
            Error ("Failed to launch headless binary: " ^ Unix.error_message err)
          ))
  | "headless_key" -> (
      match require_session args "session" with
      | Error e -> Error e
      | Ok s -> (
          match require_string args "key" with
          | Error e -> Error e
          | Ok key -> (
              let cmd =
                `Assoc [ ("cmd", `String "key"); ("key", `String key) ]
              in
              match headless_rpc s cmd with
              | Error e -> Error e
              | Ok json -> (
                  match frame_of_json json with
                  | Error e -> Error e
                  | Ok text -> ok_result (`String text)))))
  | "headless_keys" -> (
      match require_session args "session" with
      | Error e -> Error e
      | Ok s -> (
          match List.assoc_opt "keys" args with
          | Some (`List key_jsons) ->
              let keys =
                List.filter_map
                  (fun j -> match j with `String k -> Some k | _ -> None)
                  key_jsons
              in
              if keys = [] then Error "Empty keys array"
              else
                let delay_s =
                  let ms =
                    match get_int args "delay_ms" with
                    | Some n -> n
                    | None -> 50
                  in
                  Float.of_int ms /. 1000.0
                in
                let rec send_keys = function
                  | [] -> Error "Empty keys array"
                  | [ k ] ->
                      let cmd =
                        `Assoc [ ("cmd", `String "key"); ("key", `String k) ]
                      in
                      headless_rpc s cmd
                  | k :: rest ->
                      let cmd =
                        `Assoc [ ("cmd", `String "key"); ("key", `String k) ]
                      in
                      (match headless_rpc s cmd with
                      | Error e -> Error e
                      | Ok json -> (
                          match frame_of_json json with
                          | Error e -> Error e
                          | Ok _text ->
                              Unix.sleepf delay_s;
                              send_keys rest))
                in
                (match send_keys keys with
                | Error e -> Error e
                | Ok json -> (
                    match frame_of_json json with
                    | Error e -> Error e
                    | Ok text -> ok_result (`String text)))
          | _ -> Error "Missing required parameter: keys (array)"))
  | "headless_click" -> (
      match require_session args "session" with
      | Error e -> Error e
      | Ok s -> (
          let row = match get_int args "row" with Some n -> n | None -> 0 in
          let col = match get_int args "col" with Some n -> n | None -> 0 in
          let button =
            match get_string args "button" with Some b -> b | None -> "left"
          in
          let cmd =
            `Assoc
              [
                ("cmd", `String "click");
                ("row", `Int row);
                ("col", `Int col);
                ("button", `String button);
              ]
          in
          match headless_rpc s cmd with
          | Error e -> Error e
          | Ok json -> (
              match frame_of_json json with
              | Error e -> Error e
              | Ok text -> ok_result (`String text))))
  | "headless_tick" -> (
      match require_session args "session" with
      | Error e -> Error e
      | Ok s -> (
          let n = match get_int args "n" with Some n -> n | None -> 1 in
          let cmd = `Assoc [ ("cmd", `String "tick"); ("n", `Int n) ] in
          match headless_rpc s cmd with
          | Error e -> Error e
          | Ok json -> (
              match frame_of_json json with
              | Error e -> Error e
              | Ok text -> ok_result (`String text))))
  | "headless_render" -> (
      match require_session args "session" with
      | Error e -> Error e
      | Ok s -> (
          let cmd = `Assoc [ ("cmd", `String "render") ] in
          match headless_rpc s cmd with
          | Error e -> Error e
          | Ok json -> (
              match frame_of_json json with
              | Error e -> Error e
              | Ok text -> ok_result (`String text))))
  | "headless_stop" -> (
      match require_session args "session" with
      | Error e -> Error e
      | Ok s ->
          let sid =
            match List.assoc_opt "session" args with
            | Some (`String id) -> id
            | _ -> ""
          in
          let cmd = `Assoc [ ("cmd", `String "quit") ] in
          (try ignore (headless_rpc s cmd) with _ -> ());
          (try close_in_noerr s.ic with _ -> ());
          (try close_out_noerr s.oc with _ -> ());
          (try ignore (Unix.waitpid [] s.pid) with _ -> ());
          Hashtbl.remove headless_sessions sid;
          ok_result (`Assoc [ ("message", `String "Session stopped") ]))
  | _ -> Error ("Unknown tool: " ^ tool_name)
