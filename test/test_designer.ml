(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
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
        "three state vars" 3 (List.length page.Page.state_schema);
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
      Alcotest.(check bool) "state key updated" true
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
      Alcotest.(check bool) "bound widget updated" true
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
      ignore
        (Page.execute_action page (Action.Reset_state { key = "count" }));
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
          Alcotest.test_case "reset_state action" `Quick
            test_reset_state_action;
          Alcotest.test_case "roundtrip state_schema" `Quick
            test_state_roundtrip;
          Alcotest.test_case "designer add/remove var" `Quick
            test_designer_state_var_add_remove;
        ] );
    ]
