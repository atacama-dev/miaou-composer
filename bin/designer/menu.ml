(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-32-34-37-69"]

(** Menu state: a stack of menu levels. Each level has a title, items, and a
    cursor position. Pure state + navigation — no UI rendering. *)

type action =
  | GoSubmenu of string
  | AddWidget of string
  | RemoveWidget
  | AddWiringStep1
  | AddWiringStep2 of string
  | AddWiringStep3 of string * string
  | AddWiringFinish of string * string * string
  | RemoveWiring of int
  | ListWirings
  | PreviewMode
  | Export
  | Import
  | Quit

type item = { label : string; hint : string; action : action }
type level = { title : string; items : item array; mutable cursor : int }

type t = { stack : level list }
(** Head of stack = current level. Never empty. *)

let make_item label hint action = { label; hint; action }

let root_level () =
  {
    title = "Page Designer";
    items =
      [|
        make_item "Add Widget" "a" (GoSubmenu "add_widget");
        make_item "Remove Widget" "r" RemoveWidget;
        make_item "Add Wiring" "w" AddWiringStep1;
        make_item "Remove Wiring" "W" (GoSubmenu "remove_wiring");
        make_item "List Wirings" "l" ListWirings;
        make_item "Preview Mode" "p" PreviewMode;
        make_item "Export" "e" Export;
        make_item "Import" "i" Import;
        make_item "Quit" "q" Quit;
      |];
    cursor = 0;
  }

let widget_catalog_level () =
  {
    title = "Add Widget";
    items =
      [|
        make_item "button" "" (AddWidget "button");
        make_item "checkbox" "" (AddWidget "checkbox");
        make_item "textbox" "" (AddWidget "textbox");
        make_item "textarea" "" (AddWidget "textarea");
        make_item "select" "" (AddWidget "select");
        make_item "radio" "" (AddWidget "radio");
        make_item "switch" "" (AddWidget "switch");
        make_item "pager" "" (AddWidget "pager");
        make_item "list" "" (AddWidget "list");
        make_item "description_list" "" (AddWidget "description_list");
      |];
    cursor = 0;
  }

let create () = { stack = [ root_level () ] }
let current_level t = List.hd t.stack
let push_level t level = { stack = level :: t.stack }

let pop t =
  match t.stack with
  | [] | [ _ ] -> { stack = [ root_level () ] }
  | _ :: rest -> { stack = rest }

let move_cursor t delta =
  let level = current_level t in
  let n = Array.length level.items in
  if n = 0 then t
  else begin
    let new_cursor = (((level.cursor + delta) mod n) + n) mod n in
    level.cursor <- new_cursor;
    t
  end

let current_item t =
  let level = current_level t in
  if Array.length level.items = 0 then None else Some level.items.(level.cursor)

let wiring_list_level wirings =
  let items =
    List.mapi
      (fun i (src, evt, action_str) ->
        make_item
          (Printf.sprintf "%s.%s -> %s" src evt action_str)
          "" (RemoveWiring i))
      wirings
  in
  {
    title = "Wirings (Enter to remove)";
    items = Array.of_list items;
    cursor = 0;
  }

let remove_wiring_level wirings =
  let items =
    List.mapi
      (fun i (src, evt, action_str) ->
        make_item
          (Printf.sprintf "%s.%s -> %s" src evt action_str)
          "" (RemoveWiring i))
      wirings
  in
  { title = "Remove Wiring"; items = Array.of_list items; cursor = 0 }

let wiring_step1_level widget_ids =
  let items =
    List.map (fun id -> make_item id "" (AddWiringStep2 id)) widget_ids
  in
  {
    title = "Add Wiring: Select Source Widget";
    items = Array.of_list items;
    cursor = 0;
  }

let wiring_step2_level source events =
  let items =
    List.map (fun evt -> make_item evt "" (AddWiringStep3 (source, evt))) events
  in
  {
    title = Printf.sprintf "Add Wiring: Select Event (%s)" source;
    items = Array.of_list items;
    cursor = 0;
  }

let wiring_step3_level source event =
  let action_types =
    [
      "toggle";
      "set_text";
      "set_checked";
      "append_text";
      "focus";
      "set_disabled";
      "navigate";
      "back";
      "quit";
    ]
  in
  let items =
    List.map
      (fun at -> make_item at "" (AddWiringFinish (source, event, at)))
      action_types
  in
  {
    title = Printf.sprintf "Add Wiring: Select Action (%s.%s)" source event;
    items = Array.of_list items;
    cursor = 0;
  }

let render t ~width =
  let level = current_level t in
  let title_line =
    let padded = Printf.sprintf "  %s" level.title in
    let line = String.make width '-' in
    padded ^ "\n" ^ line ^ "\n"
  in
  let items_lines =
    Array.to_list
      (Array.mapi
         (fun i item ->
           let prefix = if i = level.cursor then "> " else "  " in
           let hint =
             if item.hint <> "" then Printf.sprintf " [%s]" item.hint else ""
           in
           Printf.sprintf "%s%s%s" prefix item.label hint)
         level.items)
  in
  title_line ^ String.concat "\n" items_lines
