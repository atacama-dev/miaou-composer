(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

open Miaou_composer_designer

(* ---- Helpers ---- *)

let fresh () = Designer_state.create ()

(* ---- US1: Widget add/remove ---- *)

let test_add_widget_increases_count () =
  let t = fresh () in
  let params =
    `Assoc [ ("label", `String "Click me"); ("id", `String "btn_1") ]
  in
  match
    Designer_state.add_widget t ~widget_type:"button" ~params_json:params
  with
  | Error msg -> Alcotest.failf "add_widget failed: %s" msg
  | Ok t' ->
      let ids = Designer_state.get_widget_ids t' in
      Alcotest.(check (list string)) "has btn_1" [ "btn_1" ] ids

let test_remove_widget () =
  let t = fresh () in
  let params = `Assoc [ ("label", `String "X"); ("id", `String "btn_1") ] in
  let t' =
    match
      Designer_state.add_widget t ~widget_type:"button" ~params_json:params
    with
    | Ok s -> s
    | Error e -> Alcotest.failf "add: %s" e
  in
  let t'' =
    match Designer_state.remove_widget t' ~id:"btn_1" with
    | Ok s -> s
    | Error e -> Alcotest.failf "remove: %s" e
  in
  let ids = Designer_state.get_widget_ids t'' in
  Alcotest.(check (list string)) "empty after remove" [] ids

let test_duplicate_id_rejected () =
  let t = fresh () in
  let params = `Assoc [ ("label", `String "X"); ("id", `String "btn_1") ] in
  let t' =
    match
      Designer_state.add_widget t ~widget_type:"button" ~params_json:params
    with
    | Ok s -> s
    | Error e -> Alcotest.failf "first add: %s" e
  in
  match
    Designer_state.add_widget t' ~widget_type:"button" ~params_json:params
  with
  | Ok _ -> Alcotest.fail "Expected duplicate ID error"
  | Error msg ->
      Alcotest.(check bool)
        "contains 'Duplicate'" true
        (let lower = String.lowercase_ascii msg in
         let re = Str.regexp_string "duplicate" in
         try
           ignore (Str.search_forward re lower 0);
           true
         with Not_found -> false)

(* ---- US4: Mode switching ---- *)

let test_mode_switch_to_preview () =
  let t = fresh () in
  let t' = Designer_state.switch_mode t in
  Alcotest.(check bool) "preview mode" true (t'.mode = Designer_state.Preview)

let test_mode_switch_back_to_design () =
  let t = fresh () in
  let t' = Designer_state.switch_mode t in
  let t'' = Designer_state.switch_mode t' in
  Alcotest.(check bool) "design mode" true (t''.mode = Designer_state.Design)

(* ---- US2: Wirings ---- *)

let test_add_wiring () =
  let t = fresh () in
  let params_btn = `Assoc [ ("label", `String "Go"); ("id", `String "btn") ] in
  let params_chk =
    `Assoc [ ("id", `String "chk"); ("label", `String "Accept") ]
  in
  let t' =
    match
      Designer_state.add_widget t ~widget_type:"button" ~params_json:params_btn
    with
    | Ok s -> s
    | Error e -> Alcotest.failf "add btn: %s" e
  in
  let t'' =
    match
      Designer_state.add_widget t' ~widget_type:"checkbox"
        ~params_json:params_chk
    with
    | Ok s -> s
    | Error e -> Alcotest.failf "add chk: %s" e
  in
  let action = Miaou_composer_lib.Action.Toggle { target = "chk" } in
  let t''' =
    match
      Designer_state.add_wiring t'' ~source:"btn" ~event:"click" ~action
    with
    | Ok s -> s
    | Error e -> Alcotest.failf "add wiring: %s" e
  in
  Alcotest.(check int) "one wiring" 1 (Designer_state.get_wiring_count t''')

let test_remove_wiring () =
  let t = fresh () in
  let params_btn = `Assoc [ ("label", `String "Go"); ("id", `String "btn") ] in
  let params_chk =
    `Assoc [ ("id", `String "chk"); ("label", `String "Accept") ]
  in
  let t' =
    match
      Designer_state.add_widget t ~widget_type:"button" ~params_json:params_btn
    with
    | Ok s -> s
    | Error e -> Alcotest.failf "%s" e
  in
  let t'' =
    match
      Designer_state.add_widget t' ~widget_type:"checkbox"
        ~params_json:params_chk
    with
    | Ok s -> s
    | Error e -> Alcotest.failf "%s" e
  in
  let action = Miaou_composer_lib.Action.Toggle { target = "chk" } in
  let t''' =
    match
      Designer_state.add_wiring t'' ~source:"btn" ~event:"click" ~action
    with
    | Ok s -> s
    | Error e -> Alcotest.failf "%s" e
  in
  let t4 =
    match Designer_state.remove_wiring_by_index t''' ~index:0 with
    | Ok s -> s
    | Error e -> Alcotest.failf "remove wiring: %s" e
  in
  Alcotest.(check int) "zero wirings" 0 (Designer_state.get_wiring_count t4)

(* ---- US3: Export/Import ---- *)

let test_export_import_roundtrip () =
  let t = fresh () in
  let params = `Assoc [ ("label", `String "Hello"); ("id", `String "btn_1") ] in
  let t' =
    match
      Designer_state.add_widget t ~widget_type:"button" ~params_json:params
    with
    | Ok s -> s
    | Error e -> Alcotest.failf "add: %s" e
  in
  let tmp_path = Filename.temp_file "designer_test" ".json" in
  (match Designer_state.export_page t' tmp_path with
  | Error e -> Alcotest.failf "export: %s" e
  | Ok _ -> ());
  let t_fresh = fresh () in
  (match Designer_state.import_page t_fresh tmp_path with
  | Error e -> Alcotest.failf "import: %s" e
  | Ok t'' ->
      let ids = Designer_state.get_widget_ids t'' in
      Alcotest.(check bool) "has btn_1" true (List.mem "btn_1" ids));
  Sys.remove tmp_path

(* ---- Menu navigation ---- *)

let test_menu_cursor_moves () =
  let menu = Menu.create () in
  let menu' = Menu.move_cursor menu 1 in
  let level = Menu.current_level menu' in
  Alcotest.(check int) "cursor at 1" 1 level.Menu.cursor

let test_menu_push_pop () =
  let menu = Menu.create () in
  let catalog = Menu.widget_catalog_level () in
  let menu' = Menu.push_level menu catalog in
  Alcotest.(check string)
    "title after push" "Add Widget" (Menu.current_level menu').Menu.title;
  let menu'' = Menu.pop menu' in
  Alcotest.(check string)
    "title after pop" "Page Designer" (Menu.current_level menu'').Menu.title

(* ---- Form validation ---- *)

let test_form_empty_required_field_rejected () =
  match Form.make_for_widget_type "button" with
  | None -> Alcotest.fail "No form for button"
  | Some form -> (
      match Form.validate form ~existing_ids:[] with
      | Ok () ->
          Alcotest.fail "Expected validation error for empty required field"
      | Error _ -> ())

let test_form_duplicate_id_rejected () =
  match Form.make_for_widget_type "button" with
  | None -> Alcotest.fail "No form for button"
  | Some form -> (
      (* Type "btn_1" into the ID field (focused = 0) *)
      let form' = Form.update_focused_field form "b" in
      let form' = Form.update_focused_field form' "t" in
      let form' = Form.update_focused_field form' "n" in
      let form' = Form.update_focused_field form' "_" in
      let form' = Form.update_focused_field form' "1" in
      match Form.validate form' ~existing_ids:[ "btn_1" ] with
      | Ok () -> Alcotest.fail "Expected duplicate ID error"
      | Error _ -> ())

(* ---- US5: Page state ---- *)

module Page = Miaou_composer_lib.Page
module Bridge = Miaou_composer_bridge
module Action = Miaou_composer_lib.Action

let make_state_page_json () =
  {|{
    "id": "sp",
    "size": {"rows": 24, "cols": 80},
    "state_schema": [
      {"key": "count",   "type": "int",  "default": 0,     "scope": "ephemeral"},
      {"key": "name",    "type": "string","default": "",   "scope": "persistent"},
      {"key": "enabled", "type": "bool", "default": false, "scope": "ephemeral"}
    ],
    "state_bindings": [
      {"key": "enabled", "widget_id": "chk", "prop": "checked"}
    ],
    "layout": {
      "type": "flex",
      "direction": "column",
      "children": [
        {"type": "button",   "id": "btn", "label": "Inc"},
        {"type": "checkbox", "id": "chk", "label": "Active", "checked": false}
      ]
    },
    "wirings": [],
    "focus_ring": []
  }|}

let test_state_schema_parsed () =
  let json = Yojson.Safe.from_string (make_state_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      Alcotest.(check int)
        "three state vars" 3
        (List.length page.Page.state_schema);
      let sv = List.hd page.Page.state_schema in
      Alcotest.(check string) "first key is count" "count" sv.Page.key;
      Alcotest.(check bool)
        "first scope is ephemeral" true
        (sv.Page.scope = Page.Ephemeral)

let test_set_state_action () =
  let json = Yojson.Safe.from_string (make_state_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      ignore
        (Page.execute_action page
           (Action.Set_state { key = "count"; value = `Int 42 }));
      let v = Hashtbl.find_opt page.Page.state "count" in
      Alcotest.(check bool) "state updated" true (v = Some (`Int 42))

let test_state_binding_sync () =
  let json = Yojson.Safe.from_string (make_state_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      (* Binding: enabled -> chk.checked *)
      ignore
        (Page.execute_action page
           (Action.Set_state { key = "enabled"; value = `Bool true }));
      (* State key updated *)
      let state_val = Hashtbl.find_opt page.Page.state "enabled" in
      Alcotest.(check bool)
        "state key updated" true
        (state_val = Some (`Bool true));
      (* Widget chk.checked should be true *)
      let chk_state =
        match Hashtbl.find_opt page.Page.widgets "chk" with
        | Some wb -> Miaou_composer_lib.Widget_box.query wb
        | None -> `Null
      in
      let checked_val =
        match chk_state with
        | `Assoc fields -> (
            match List.assoc_opt "checked" fields with
            | Some v -> v
            | None -> `Null)
        | _ -> `Null
      in
      Alcotest.(check bool)
        "bound widget updated" true
        (checked_val = `Bool true)

let test_inc_state_action () =
  let json = Yojson.Safe.from_string (make_state_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      ignore
        (Page.execute_action page
           (Action.Inc_state { key = "count"; by = 1.0 }));
      let v = Hashtbl.find_opt page.Page.state "count" in
      (* count is `Int type; 0 + 1 = 1 *)
      Alcotest.(check bool) "inc_state updated" true (v = Some (`Int 1))

let test_reset_state_action () =
  let json = Yojson.Safe.from_string (make_state_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      ignore
        (Page.execute_action page
           (Action.Set_state { key = "count"; value = `Int 99 }));
      ignore (Page.execute_action page (Action.Reset_state { key = "count" }));
      let v = Hashtbl.find_opt page.Page.state "count" in
      Alcotest.(check bool) "reset to default" true (v = Some (`Int 0))

let test_state_roundtrip () =
  let json = Yojson.Safe.from_string (make_state_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      let out_json = Bridge.Page_codec.page_to_json page in
      let schema_field =
        match out_json with
        | `Assoc fields -> List.assoc_opt "state_schema" fields
        | _ -> None
      in
      Alcotest.(check bool)
        "state_schema in output" true
        (match schema_field with
        | Some (`List items) -> List.length items = 3
        | _ -> false)

let test_designer_state_var_add_remove () =
  let t = fresh () in
  let sv : Miaou_composer_lib.Page.state_var =
    {
      key = "counter";
      typ = `Int;
      default = `Int 0;
      scope = Miaou_composer_lib.Page.Ephemeral;
    }
  in
  let t' = Designer_state.add_state_var t sv in
  let schema = Designer_state.get_state_schema t' in
  Alcotest.(check int) "one state var" 1 (List.length schema);
  let t'' =
    match Designer_state.remove_state_var t' ~index:0 with
    | Ok s -> s
    | Error e -> Alcotest.failf "remove_state_var: %s" e
  in
  let schema2 = Designer_state.get_state_schema t'' in
  Alcotest.(check int) "zero state vars" 0 (List.length schema2)

(* ---- US6: key_handlers + navigation events ---- *)

let make_key_handler_page_json () =
  {|{
    "id": "kh",
    "size": {"rows": 24, "cols": 80},
    "layout": {
      "type": "flex",
      "direction": "column",
      "children": [
        {"type": "button", "id": "btn", "label": "OK"}
      ]
    },
    "wirings": [],
    "focus_ring": ["btn"],
    "key_handlers": [
      {"key": "q", "action": {"type": "quit"}},
      {"key": "n", "action": {"type": "navigate", "target": "page2"}}
    ]
  }|}

let test_key_handlers_parsed () =
  let json = Yojson.Safe.from_string (make_key_handler_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      Alcotest.(check int)
        "two key handlers" 2
        (List.length page.Page.key_handlers);
      let keys = List.map fst page.Page.key_handlers in
      Alcotest.(check bool) "has q" true (List.mem "q" keys);
      Alcotest.(check bool) "has n" true (List.mem "n" keys)

let test_quit_key_emits_system_event () =
  let json = Yojson.Safe.from_string (make_key_handler_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      let events = Page.send_key page ~key:"q" in
      Alcotest.(check int) "one event" 1 (List.length events);
      let ev = List.hd events in
      Alcotest.(check string) "event is $quit" "$quit" ev.Page.name

let test_navigate_key_emits_system_event () =
  let json = Yojson.Safe.from_string (make_key_handler_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      let events = Page.send_key page ~key:"n" in
      Alcotest.(check int) "one event" 1 (List.length events);
      let ev = List.hd events in
      Alcotest.(check string) "event is $navigate" "$navigate" ev.Page.name;
      Alcotest.(check bool)
        "snapshot has target" true
        (ev.Page.snapshot = `String "page2")

let test_key_handler_blocks_tab () =
  (* Tab is wired as a key_handler; it should NOT cycle focus *)
  let json =
    Yojson.Safe.from_string
      {|{
        "id": "t",
        "size": {"rows": 24, "cols": 80},
        "layout": {
          "type": "flex",
          "direction": "row",
          "children": [
            {"type": "button", "id": "a", "label": "A"},
            {"type": "button", "id": "b", "label": "B"}
          ]
        },
        "wirings": [],
        "focus_ring": ["a", "b"],
        "key_handlers": [
          {"key": "Tab", "action": {"type": "emit", "event": "tab_pressed"}}
        ]
      }|}
  in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page ->
      let focused_before =
        Miaou_internals.Focus_ring.current page.Page.focus_ring
      in
      let events = Page.send_key page ~key:"Tab" in
      let focused_after =
        Miaou_internals.Focus_ring.current page.Page.focus_ring
      in
      (* focus should NOT have changed because key_handler consumed Tab *)
      Alcotest.(check bool)
        "focus unchanged" true
        (focused_before = focused_after);
      Alcotest.(check int) "one event" 1 (List.length events);
      Alcotest.(check string)
        "emits tab_pressed" "tab_pressed" (List.hd events).Page.name

let test_key_handlers_roundtrip () =
  let json = Yojson.Safe.from_string (make_key_handler_page_json ()) in
  match Bridge.Page_codec.page_of_json json with
  | Error e -> Alcotest.failf "page_of_json failed: %s" e
  | Ok page -> (
      let exported = Bridge.Page_codec.page_to_json page in
      match exported with
      | `Assoc fields -> (
          match List.assoc_opt "key_handlers" fields with
          | Some (`List khs) ->
              Alcotest.(check int)
                "two key_handlers in export" 2 (List.length khs)
          | _ -> Alcotest.fail "key_handlers missing from export")
      | _ -> Alcotest.fail "export is not an object")

(* ---- US7 tests ---- *)

let test_sequence_runs_all_actions () =
  (* Use Set_state actions: no widget needed, clearly verifiable *)
  let json =
    `Assoc
      [
        ("id", `String "p");
        ( "layout",
          `Assoc
            [
              ("type", `String "flex");
              ("direction", `String "column");
              ("gap", `Int 0);
              ("children", `List []);
            ] );
        ( "state_schema",
          `List
            [
              `Assoc
                [
                  ("key", `String "a");
                  ("type", `String "string");
                  ("default", `String "");
                  ("scope", `String "ephemeral");
                ];
              `Assoc
                [
                  ("key", `String "b");
                  ("type", `String "string");
                  ("default", `String "");
                  ("scope", `String "ephemeral");
                ];
            ] );
      ]
  in
  let page =
    match Miaou_composer_bridge.Page_codec.page_of_json json with
    | Ok p -> p
    | Error e -> Alcotest.failf "parse: %s" e
  in
  let action =
    Miaou_composer_lib.Action.Sequence
      [
        Miaou_composer_lib.Action.Set_state
          { key = "a"; value = `String "hello" };
        Miaou_composer_lib.Action.Set_state
          { key = "b"; value = `String "world" };
      ]
  in
  let events = Miaou_composer_lib.Page.execute_action page action in
  Alcotest.(check int) "no events from set_state" 0 (List.length events);
  let va = Hashtbl.find_opt page.Miaou_composer_lib.Page.state "a" in
  let vb = Hashtbl.find_opt page.Miaou_composer_lib.Page.state "b" in
  let json_str = function
    | None -> "none"
    | Some j -> Yojson.Safe.to_string j
  in
  Alcotest.(check string) "state a" "\"hello\"" (json_str va);
  Alcotest.(check string) "state b" "\"world\"" (json_str vb)

let make_empty_page () =
  Miaou_composer_lib.Page.create ~id:"p"
    ~layout:
      (Miaou_composer_lib.Layout_tree.Flex
         {
           direction = Miaou_composer_lib.Layout_tree.Column;
           gap = 0;
           padding =
             {
               Miaou_composer_lib.Layout_tree.left = 0;
               right = 0;
               top = 0;
               bottom = 0;
             };
           justify = Miaou_composer_lib.Layout_tree.Start;
           align_items = Miaou_composer_lib.Layout_tree.Stretch;
           children = [];
           basis = Miaou_composer_lib.Layout_tree.Auto;
         })
    ~size:{ LTerm_geom.rows = 10; cols = 40 }

let test_call_tool_emits_event () =
  let page = make_empty_page () in
  let action =
    Miaou_composer_lib.Action.Call_tool { name = "my_tool"; args = [] }
  in
  let events = Miaou_composer_lib.Page.execute_action page action in
  Alcotest.(check int) "one event" 1 (List.length events);
  let ev = List.hd events in
  Alcotest.(check string)
    "event name is $tool_call" "$tool_call" ev.Miaou_composer_lib.Page.name;
  match ev.snapshot with
  | `Assoc fields -> (
      match List.assoc_opt "tool_name" fields with
      | Some (`String name) ->
          Alcotest.(check string) "tool_name in snapshot" "my_tool" name
      | _ -> Alcotest.fail "tool_name not in snapshot")
  | _ -> Alcotest.fail "snapshot not an object"

let test_call_tool_resolves_state () =
  let page = make_empty_page () in
  Hashtbl.replace page.Miaou_composer_lib.Page.state "selected_file"
    (`String "src/foo.ml");
  let action =
    Miaou_composer_lib.Action.Call_tool
      { name = "git_diff"; args = [ ("file", "$state.selected_file") ] }
  in
  let events = Miaou_composer_lib.Page.execute_action page action in
  let ev = List.hd events in
  match ev.snapshot with
  | `Assoc fields -> (
      match List.assoc_opt "args" fields with
      | Some (`Assoc args) -> (
          match List.assoc_opt "file" args with
          | Some (`String v) ->
              Alcotest.(check string) "$state resolved" "src/foo.ml" v
          | _ -> Alcotest.fail "arg 'file' not found")
      | _ -> Alcotest.fail "args not found")
  | _ -> Alcotest.fail "snapshot not object"

let test_init_actions_roundtrip () =
  let json =
    `Assoc
      [
        ("id", `String "p");
        ( "layout",
          `Assoc
            [
              ("type", `String "flex");
              ("direction", `String "column");
              ("gap", `Int 0);
              ("children", `List []);
            ] );
        ( "init_actions",
          `List
            [
              `Assoc
                [
                  ("type", `String "call_tool");
                  ("name", `String "git_status");
                  ("args", `Assoc []);
                ];
              `Assoc
                [
                  ("type", `String "call_tool");
                  ("name", `String "git_log");
                  ("args", `Assoc []);
                ];
            ] );
      ]
  in
  let page =
    match Miaou_composer_bridge.Page_codec.page_of_json json with
    | Ok p -> p
    | Error e -> Alcotest.failf "parse: %s" e
  in
  Alcotest.(check int)
    "2 init_actions" 2
    (List.length page.Miaou_composer_lib.Page.init_actions);
  let out_json = Miaou_composer_bridge.Page_codec.page_to_json page in
  let page2 =
    match Miaou_composer_bridge.Page_codec.page_of_json out_json with
    | Ok p -> p
    | Error e -> Alcotest.failf "re-parse: %s" e
  in
  Alcotest.(check int)
    "2 init_actions after roundtrip" 2
    (List.length page2.Miaou_composer_lib.Page.init_actions)

let test_string_list_binding () =
  let json =
    `Assoc
      [
        ("id", `String "p");
        ( "layout",
          `Assoc
            [
              ("type", `String "flex");
              ("direction", `String "column");
              ("gap", `Int 0);
              ( "children",
                `List
                  [
                    `Assoc
                      [
                        ("type", `String "list");
                        ("id", `String "files_list");
                        ("items", `List []);
                      ];
                  ] );
            ] );
        ( "state_schema",
          `List
            [
              `Assoc
                [
                  ("key", `String "status_files");
                  ("type", `String "string_list");
                  ("default", `List []);
                  ("scope", `String "ephemeral");
                ];
            ] );
        ( "state_bindings",
          `List
            [
              `Assoc
                [
                  ("key", `String "status_files");
                  ("widget_id", `String "files_list");
                  ("prop", `String "items");
                ];
            ] );
      ]
  in
  let page =
    match Miaou_composer_bridge.Page_codec.page_of_json json with
    | Ok p -> p
    | Error e -> Alcotest.failf "parse: %s" e
  in
  Miaou_composer_lib.Page.set_state_value page ~key:"status_files"
    ~value:(`List [ `String "M src/foo.ml"; `String "?? new.ml" ]);
  let wb = Hashtbl.find page.Miaou_composer_lib.Page.widgets "files_list" in
  let q = Miaou_composer_lib.Widget_box.query wb in
  match q with
  | `Assoc fields -> (
      match List.assoc_opt "cursor" fields with
      | Some (`Int _) -> ()
      | _ -> Alcotest.fail "list widget query missing cursor")
  | _ -> Alcotest.fail "list widget query not assoc"

let test_tool_codec_process_roundtrip () =
  let tool =
    Miaou_composer_lib.Tool_def.Process
      {
        name = "git_diff";
        bin = "git";
        argv = [ "diff"; "--"; "$state.selected_file" ];
        stdin = None;
        cwd = Some "$state.repo_path";
        capture_stdout = Some "diff_text";
        capture_stdout_lines = None;
        capture_json_fields = false;
        on_exit =
          Some
            (Miaou_composer_lib.Action.Call_tool { name = "refresh"; args = [] });
      }
  in
  let json = Miaou_composer_bridge.Tool_codec.tool_def_to_json tool in
  match Miaou_composer_bridge.Tool_codec.tool_def_of_json json with
  | Error e -> Alcotest.failf "decode failed: %s" e
  | Ok tool2 -> (
      Alcotest.(check string)
        "name preserved" "git_diff"
        (Miaou_composer_lib.Tool_def.name tool2);
      match tool2 with
      | Miaou_composer_lib.Tool_def.Process
          { bin; argv; cwd; capture_stdout; on_exit; _ } -> (
          Alcotest.(check string) "bin" "git" bin;
          Alcotest.(check int) "argv len" 3 (List.length argv);
          Alcotest.(check (option string)) "cwd" (Some "$state.repo_path") cwd;
          Alcotest.(check (option string))
            "capture_stdout" (Some "diff_text") capture_stdout;
          match on_exit with
          | Some (Miaou_composer_lib.Action.Call_tool { name; _ }) ->
              Alcotest.(check string) "on_exit tool name" "refresh" name
          | _ -> Alcotest.fail "on_exit not Call_tool")
      | _ -> Alcotest.fail "not a Process tool")

(* ---- Runner ---- *)

let () =
  Alcotest.run "designer"
    [
      ( "US1: widget lifecycle",
        [
          Alcotest.test_case "add widget" `Quick test_add_widget_increases_count;
          Alcotest.test_case "remove widget" `Quick test_remove_widget;
          Alcotest.test_case "duplicate id rejected" `Quick
            test_duplicate_id_rejected;
        ] );
      ( "US4: mode switching",
        [
          Alcotest.test_case "switch to preview" `Quick
            test_mode_switch_to_preview;
          Alcotest.test_case "switch back to design" `Quick
            test_mode_switch_back_to_design;
        ] );
      ( "US2: wirings",
        [
          Alcotest.test_case "add wiring" `Quick test_add_wiring;
          Alcotest.test_case "remove wiring" `Quick test_remove_wiring;
        ] );
      ( "US3: export/import",
        [ Alcotest.test_case "roundtrip" `Quick test_export_import_roundtrip ]
      );
      ( "menu navigation",
        [
          Alcotest.test_case "cursor moves" `Quick test_menu_cursor_moves;
          Alcotest.test_case "push/pop" `Quick test_menu_push_pop;
        ] );
      ( "form validation",
        [
          Alcotest.test_case "empty required rejected" `Quick
            test_form_empty_required_field_rejected;
          Alcotest.test_case "duplicate id rejected" `Quick
            test_form_duplicate_id_rejected;
        ] );
      ( "US5: page state",
        [
          Alcotest.test_case "schema parsed" `Quick test_state_schema_parsed;
          Alcotest.test_case "set_state action" `Quick test_set_state_action;
          Alcotest.test_case "binding sync" `Quick test_state_binding_sync;
          Alcotest.test_case "inc_state action" `Quick test_inc_state_action;
          Alcotest.test_case "reset_state action" `Quick test_reset_state_action;
          Alcotest.test_case "roundtrip state_schema" `Quick
            test_state_roundtrip;
          Alcotest.test_case "designer add/remove var" `Quick
            test_designer_state_var_add_remove;
        ] );
      ( "US6: key_handlers",
        [
          Alcotest.test_case "handlers parsed" `Quick test_key_handlers_parsed;
          Alcotest.test_case "quit key emits $quit" `Quick
            test_quit_key_emits_system_event;
          Alcotest.test_case "navigate key emits $navigate" `Quick
            test_navigate_key_emits_system_event;
          Alcotest.test_case "handler blocks Tab" `Quick
            test_key_handler_blocks_tab;
          Alcotest.test_case "roundtrip key_handlers" `Quick
            test_key_handlers_roundtrip;
        ] );
      ( "US7: tool system",
        [
          Alcotest.test_case "Sequence runs all sub-actions" `Quick
            test_sequence_runs_all_actions;
          Alcotest.test_case "Call_tool emits $tool_call" `Quick
            test_call_tool_emits_event;
          Alcotest.test_case "Call_tool resolves $state.KEY" `Quick
            test_call_tool_resolves_state;
          Alcotest.test_case "init_actions roundtrip" `Quick
            test_init_actions_roundtrip;
          Alcotest.test_case "string_list type bound to list" `Quick
            test_string_list_binding;
          Alcotest.test_case "tool_codec process roundtrip" `Quick
            test_tool_codec_process_roundtrip;
        ] );
    ]
