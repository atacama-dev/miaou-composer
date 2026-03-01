(** Basic tests for the compositor core. *)

open Miaou_composer_lib
open Miaou_composer_bridge

let test_create_page () =
  let json =
    Yojson.Safe.from_string
      {|{
        "id": "test_page",
        "layout": {
          "type": "flex",
          "direction": "column",
          "children": [
            { "type": "button", "id": "btn1", "label": "Click me" }
          ]
        }
      }|}
  in
  match Page_codec.page_of_json json with
  | Ok page ->
      Alcotest.(check string) "page id" "test_page" page.id;
      Alcotest.(check bool) "has btn1" true (Hashtbl.mem page.widgets "btn1")
  | Error e -> Alcotest.fail ("Failed to create page: " ^ e)

let test_query_widget () =
  let json =
    Yojson.Safe.from_string
      {|{
        "id": "test_query",
        "layout": {
          "type": "flex",
          "direction": "column",
          "children": [
            { "type": "checkbox", "id": "cb1", "label": "Check me", "checked": false }
          ]
        }
      }|}
  in
  match Page_codec.page_of_json json with
  | Ok page -> (
      match Hashtbl.find_opt page.widgets "cb1" with
      | Some wb -> (
          let state = Widget_box.query wb in
          match state with
          | `Assoc fields -> (
              match List.assoc_opt "checked" fields with
              | Some (`Bool false) -> ()
              | _ -> Alcotest.fail "Expected checked=false")
          | _ -> Alcotest.fail "Expected assoc")
      | None -> Alcotest.fail "Widget cb1 not found")
  | Error e -> Alcotest.fail ("Failed to create page: " ^ e)

let test_wiring () =
  let json =
    Yojson.Safe.from_string
      {|{
        "id": "test_wiring",
        "layout": {
          "type": "flex",
          "direction": "column",
          "children": [
            { "type": "button", "id": "btn1", "label": "Go" },
            { "type": "checkbox", "id": "cb1", "label": "Target" }
          ]
        },
        "wirings": [
          {
            "source": "btn1",
            "event": "click",
            "action": { "type": "toggle", "target": "cb1" }
          }
        ]
      }|}
  in
  match Page_codec.page_of_json json with
  | Ok page -> (
      match Wiring.find page.wirings ~source:"btn1" ~event:"click" with
      | Some (Action.Toggle { target }) ->
          Alcotest.(check string) "wiring target" "cb1" target
      | _ -> Alcotest.fail "Expected Toggle wiring")
  | Error e -> Alcotest.fail ("Failed to create page: " ^ e)

let test_action_codec () =
  let action = Action.Set_text { target = "t1"; value = "hello" } in
  let json = Action_codec.action_to_json action in
  match Action_codec.action_of_json json with
  | Ok (Action.Set_text { target; value }) ->
      Alcotest.(check string) "target" "t1" target;
      Alcotest.(check string) "value" "hello" value
  | _ -> Alcotest.fail "Action round-trip failed"

let test_layout_codec () =
  let json =
    Yojson.Safe.from_string
      {|{
        "type": "flex",
        "direction": "row",
        "gap": 2,
        "children": [
          { "type": "button", "id": "b1", "label": "A" },
          { "type": "button", "id": "b2", "label": "B" }
        ]
      }|}
  in
  match Layout_codec.layout_of_json json with
  | Ok (Layout_tree.Flex { direction = Row; gap = 2; children; _ }, widgets) ->
      Alcotest.(check int) "children count" 2 (List.length children);
      Alcotest.(check int) "widget defs count" 2 (List.length widgets)
  | Ok _ -> Alcotest.fail "Expected Flex node"
  | Error e -> Alcotest.fail ("Layout parse error: " ^ e)

let test_validator () =
  let json =
    Yojson.Safe.from_string
      {|{
        "layout": {
          "type": "flex",
          "children": [
            { "type": "button", "id": "btn1", "label": "OK" },
            { "type": "button", "label": "Missing ID" }
          ]
        }
      }|}
  in
  let result = Validator.validate_page_def json in
  Alcotest.(check bool) "not valid" false result.valid;
  Alcotest.(check bool) "has errors" true (List.length result.errors > 0)

let () =
  Alcotest.run "miaou-compositor"
    [
      ( "page",
        [
          Alcotest.test_case "create page" `Quick test_create_page;
          Alcotest.test_case "query widget" `Quick test_query_widget;
          Alcotest.test_case "wiring" `Quick test_wiring;
        ] );
      ( "codecs",
        [
          Alcotest.test_case "action round-trip" `Quick test_action_codec;
          Alcotest.test_case "layout round-trip" `Quick test_layout_codec;
        ] );
      ( "validator",
        [ Alcotest.test_case "validation errors" `Quick test_validator ] );
    ]
