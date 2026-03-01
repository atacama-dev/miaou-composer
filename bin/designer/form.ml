(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-32-34-37-69"]

(** Parameter form state for widget configuration. Pure state + validation — no
    UI rendering beyond string output. *)

open Miaou_composer_lib

type field_kind = Text of string | Bool of bool | Int of string

type field = {
  name : string;
  label : string;
  kind : field_kind;
  required : bool;
  placeholder : string;
}

type t = {
  title : string;
  fields : field array;
  focused : int;
  errors : (int * string) list;
  submitted : bool;
}

let make_text_field name label ?(required = false) ?(placeholder = "") default =
  { name; label; kind = Text default; required; placeholder }

let make_bool_field name label default =
  { name; label; kind = Bool default; required = false; placeholder = "" }

let make_int_field name label ?(required = false) default_int =
  {
    name;
    label;
    kind = Int (string_of_int default_int);
    required;
    placeholder = "";
  }

let param_to_field (p : Catalog.param) : field =
  let default_str j = match j with Some (`String s) -> s | _ -> "" in
  let default_bool j = match j with Some (`Bool b) -> b | _ -> false in
  let default_int j = match j with Some (`Int n) -> n | _ -> 0 in
  match p.typ with
  | Catalog.Bool -> make_bool_field p.name p.name (default_bool p.default)
  | Catalog.Int ->
      make_int_field p.name p.name ~required:p.required (default_int p.default)
  | Catalog.String | Catalog.Float ->
      make_text_field p.name p.name ~required:p.required
        ~placeholder:(if p.required then "(required)" else "")
        (default_str p.default)
  | Catalog.String_list ->
      make_text_field p.name p.name ~required:p.required
        ~placeholder:"comma-separated values"
        (match p.default with
        | Some (`List items) ->
            String.concat ", "
              (List.filter_map
                 (function `String s -> Some s | _ -> None)
                 items)
        | _ -> "")
  | Catalog.Enum choices ->
      make_text_field p.name p.name ~required:p.required
        ~placeholder:(String.concat "|" choices)
        (default_str p.default)

let make_for_widget_type widget_type =
  let catalog = Catalog.widget_catalog () in
  match List.find_opt (fun e -> e.Catalog.name = widget_type) catalog with
  | None -> None
  | Some entry ->
      let id_field =
        make_text_field "id" "Widget ID" ~required:true
          ~placeholder:(Printf.sprintf "%s_1" widget_type)
          ""
      in
      let param_fields = List.map param_to_field entry.params in
      Some
        {
          title = Printf.sprintf "Add %s" widget_type;
          fields = Array.of_list (id_field :: param_fields);
          focused = 0;
          errors = [];
          submitted = false;
        }

let make_for_existing_widget widget_id widget_type params_json =
  let catalog = Catalog.widget_catalog () in
  match List.find_opt (fun e -> e.Catalog.name = widget_type) catalog with
  | None -> None
  | Some entry ->
      let get_str key fallback =
        match Yojson.Safe.Util.member key params_json with
        | `String s -> s
        | _ -> fallback
      in
      let get_bool key fallback =
        match Yojson.Safe.Util.member key params_json with
        | `Bool b -> b
        | _ -> fallback
      in
      let get_int key fallback =
        match Yojson.Safe.Util.member key params_json with
        | `Int n -> n
        | _ -> fallback
      in
      let id_field =
        make_text_field "id" "Widget ID" ~required:true
          ~placeholder:(Printf.sprintf "%s_1" widget_type)
          widget_id
      in
      let param_field_with_value (p : Catalog.param) : field =
        let base = param_to_field p in
        let new_kind =
          match p.typ with
          | Catalog.Bool -> Bool (get_bool p.name (match base.kind with Bool b -> b | _ -> false))
          | Catalog.Int ->
              let n = get_int p.name (match base.kind with Int s -> (match int_of_string_opt s with Some n -> n | None -> 0) | _ -> 0) in
              Int (string_of_int n)
          | Catalog.String | Catalog.Float ->
              Text (get_str p.name (match base.kind with Text s -> s | _ -> ""))
          | Catalog.String_list ->
              let s =
                match Yojson.Safe.Util.member p.name params_json with
                | `List items ->
                    String.concat ", "
                      (List.filter_map
                         (function `String s -> Some s | _ -> None)
                         items)
                | `String s -> s
                | _ -> (match base.kind with Text s -> s | _ -> "")
              in
              Text s
          | Catalog.Enum _ ->
              Text (get_str p.name (match base.kind with Text s -> s | _ -> ""))
        in
        { base with kind = new_kind }
      in
      let param_fields = List.map param_field_with_value entry.params in
      Some
        {
          title = Printf.sprintf "Edit %s" widget_type;
          fields = Array.of_list (id_field :: param_fields);
          focused = 0;
          errors = [];
          submitted = false;
        }

let make_wiring_action_form action_type widget_ids =
  let is_state_action =
    match action_type with
    | "set_state" | "copy_widget_to_state" | "inc_state" | "reset_state" ->
        true
    | _ -> false
  in
  if is_state_action then
    let key_field =
      make_text_field "key" "State Key" ~required:true ~placeholder:"e.g. count"
        ""
    in
    let extra_fields =
      match action_type with
      | "set_state" ->
          [
            make_text_field "value" "Value (JSON)" ~required:true
              ~placeholder:"e.g. 0 or \"hello\"" "";
          ]
      | "copy_widget_to_state" ->
          [
            make_text_field "source" "Source Widget ID" ~required:true
              ~placeholder:(String.concat "|" widget_ids)
              (List.nth_opt widget_ids 0 |> Option.value ~default:"");
          ]
      | "inc_state" ->
          [ make_text_field "by" "Increment By" ~required:false ~placeholder:"1" "1" ]
      | "reset_state" -> []
      | _ -> []
    in
    {
      title = Printf.sprintf "Configure: %s" action_type;
      fields = Array.of_list (key_field :: extra_fields);
      focused = 0;
      errors = [];
      submitted = false;
    }
  else
    let needs_target =
      match action_type with "back" | "quit" -> false | _ -> true
    in
    let needs_value =
      match action_type with
      | "set_text" | "append_text" | "navigate" -> true
      | "set_checked" | "set_disabled" -> true
      | _ -> false
    in
    let target_field =
      if needs_target then
        [
          make_text_field "target" "Target Widget ID" ~required:true
            ~placeholder:(String.concat "|" widget_ids)
            (List.nth_opt widget_ids 0 |> Option.value ~default:"");
        ]
      else []
    in
    let value_field =
      if needs_value then
        [ make_text_field "value" "Value" ~required:true ~placeholder:"" "" ]
      else []
    in
    {
      title = Printf.sprintf "Configure: %s" action_type;
      fields = Array.of_list (target_field @ value_field);
      focused = 0;
      errors = [];
      submitted = false;
    }

(** Make a form for adding/editing a state variable. *)
let make_state_var_form ?(key = "") ?(typ = "int") ?(default = "0")
    ?(scope = "ephemeral") () =
  {
    title = "State Variable";
    fields =
      [|
        make_text_field "key" "Key" ~required:true ~placeholder:"e.g. count" key;
        make_text_field "type" "Type" ~required:false
          ~placeholder:"string|bool|int|float|json" typ;
        make_text_field "default" "Default (JSON)" ~required:false
          ~placeholder:"e.g. 0 or \"\"" default;
        make_text_field "scope" "Scope" ~required:false
          ~placeholder:"ephemeral|persistent" scope;
      |];
    focused = 0;
    errors = [];
    submitted = false;
  }

(** Parse a state variable form into a Page.state_var. *)
let form_to_state_var t =
  let get name =
    match
      Array.find_opt (fun f -> f.name = name) t.fields
    with
    | Some { kind = Text s; _ } -> s
    | _ -> ""
  in
  let key = get "key" in
  if key = "" then None
  else
    let typ_str = get "type" in
    let typ =
      match typ_str with
      | "bool" -> `Bool
      | "int" -> `Int
      | "float" -> `Float
      | "json" -> `Json
      | _ -> `String
    in
    let default_str = get "default" in
    let default =
      (* Try to parse as JSON; fall back to string or null *)
      (try Yojson.Safe.from_string default_str
       with _ ->
         if default_str = "" then `Null else `String default_str)
    in
    let scope_str = get "scope" in
    let scope =
      if scope_str = "persistent" then Miaou_composer_lib.Page.Persistent
      else Miaou_composer_lib.Page.Ephemeral
    in
    Some { Miaou_composer_lib.Page.key; typ; default; scope }

let move_focus t delta =
  let n = Array.length t.fields in
  if n = 0 then t
  else
    let new_focused = (((t.focused + delta) mod n) + n) mod n in
    { t with focused = new_focused }

let update_focused_field t key =
  if t.focused >= Array.length t.fields then t
  else
    let field = t.fields.(t.focused) in
    let new_kind =
      match (field.kind, key) with
      | Text s, "Backspace" ->
          let len = String.length s in
          Text (if len > 0 then String.sub s 0 (len - 1) else "")
      | Text s, k when String.length k = 1 -> Text (s ^ k)
      | Bool b, " " -> Bool (not b)
      | Int s, "Backspace" ->
          let len = String.length s in
          Int (if len > 0 then String.sub s 0 (len - 1) else "")
      | Int s, k
        when String.length k = 1
             && ((k.[0] >= '0' && k.[0] <= '9') || (k = "-" && s = "")) ->
          Int (s ^ k)
      | _, _ -> field.kind
    in
    let updated_field = { field with kind = new_kind } in
    let new_fields = Array.copy t.fields in
    new_fields.(t.focused) <- updated_field;
    { t with fields = new_fields; errors = [] }

let validate t ~existing_ids =
  let errors = ref [] in
  Array.iteri
    (fun i field ->
      match field.kind with
      | Text "" when field.required ->
          errors := (i, Printf.sprintf "%s is required" field.label) :: !errors
      | Text s when field.name = "id" && s <> "" ->
          if List.mem s existing_ids then
            errors := (i, Printf.sprintf "ID '%s' already in use" s) :: !errors
      | Int s when field.required && s = "" ->
          errors := (i, Printf.sprintf "%s is required" field.label) :: !errors
      | Int s when s <> "" -> (
          match int_of_string_opt s with
          | None ->
              errors :=
                (i, Printf.sprintf "%s must be an integer" field.label)
                :: !errors
          | Some _ -> ())
      | _ -> ())
    t.fields;
  let errs = !errors in
  if errs = [] then Ok () else Error (List.rev errs)

let to_json t =
  let pairs =
    Array.to_list
      (Array.map
         (fun field ->
           let v =
             match field.kind with
             | Text s -> `String s
             | Bool b -> `Bool b
             | Int s -> (
                 match int_of_string_opt s with
                 | Some n -> `Int n
                 | None -> `String s)
           in
           (field.name, v))
         t.fields)
  in
  `Assoc pairs

let get_id t =
  match Array.find_opt (fun f -> f.name = "id") t.fields with
  | Some { kind = Text s; _ } -> s
  | _ -> ""

let get_action_target t =
  match Array.find_opt (fun f -> f.name = "target") t.fields with
  | Some { kind = Text s; _ } -> s
  | _ -> ""

let get_action_value t =
  match Array.find_opt (fun f -> f.name = "value") t.fields with
  | Some { kind = Text s; _ } -> s
  | _ -> ""

let get_field t name =
  match Array.find_opt (fun f -> f.name = name) t.fields with
  | Some { kind = Text s; _ } -> s
  | _ -> ""

let render t ~width =
  let title_line =
    let line = String.make width '-' in
    Printf.sprintf "  %s\n%s\n" t.title line
  in
  let field_lines =
    Array.to_list
      (Array.mapi
         (fun i field ->
           let focused_mark = if i = t.focused then ">" else " " in
           let value_str =
             match field.kind with
             | Text s ->
                 if s = "" then Printf.sprintf "[%s]" field.placeholder else s
             | Bool b -> if b then "[x]" else "[ ]"
             | Int s -> if s = "" then "0" else s
           in
           let error_str =
             match List.assoc_opt i t.errors with
             | Some msg -> Printf.sprintf " <- %s" msg
             | None -> ""
           in
           Printf.sprintf "%s %-16s %s%s" focused_mark field.label value_str
             error_str)
         t.fields)
  in
  let submit_line =
    let mark = if t.submitted then ">" else " " in
    Printf.sprintf "%s [Submit]  [Esc] Cancel" mark
  in
  title_line ^ String.concat "\n" field_lines ^ "\n\n" ^ submit_line
