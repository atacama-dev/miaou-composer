(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Create widget_box instances from JSON parameters.

    Dispatches on the "type" field and extracts typed parameters for each widget
    constructor in Widget_registry. *)

open Miaou_composer_lib

let get_string fields key =
  match List.assoc_opt key fields with Some (`String s) -> s | _ -> ""

let get_string_opt fields key =
  match List.assoc_opt key fields with Some (`String s) -> Some s | _ -> None

let get_bool fields key ~default =
  match List.assoc_opt key fields with Some (`Bool b) -> b | _ -> default

let get_int fields key ~default =
  match List.assoc_opt key fields with Some (`Int n) -> n | _ -> default

let get_string_list fields key =
  match List.assoc_opt key fields with
  | Some (`List items) ->
      List.filter_map
        (fun j -> match j with `String s -> Some s | _ -> None)
        items
  | _ -> []

(** Create a widget_box from a JSON widget definition. The JSON must have a
    "type" and "id" field. *)
let create_widget (json : Yojson.Safe.t) :
    (string * Widget_box.widget_box, string) result =
  match json with
  | `Assoc fields -> (
      let typ = get_string fields "type" in
      let id = get_string fields "id" in
      if id = "" then Error "Widget missing 'id' field"
      else
        match typ with
        | "button" ->
            let label = get_string fields "label" in
            let disabled = get_bool fields "disabled" ~default:false in
            Ok (id, Widget_registry.box_button ~label ~disabled ())
        | "checkbox" ->
            let label = get_string fields "label" in
            let checked = get_bool fields "checked" ~default:false in
            let disabled = get_bool fields "disabled" ~default:false in
            Ok (id, Widget_registry.box_checkbox ~label ~checked ~disabled ())
        | "textbox" ->
            let title = get_string fields "title" in
            let width = max 1 (get_int fields "width" ~default:30) in
            let initial = get_string fields "initial" in
            let placeholder = get_string_opt fields "placeholder" in
            let mask = get_bool fields "mask" ~default:false in
            Ok
              ( id,
                Widget_registry.box_textbox ~title ~width ~initial ?placeholder
                  ~mask () )
        | "textarea" ->
            let title = get_string fields "title" in
            let width = max 1 (get_int fields "width" ~default:40) in
            let height = max 1 (get_int fields "height" ~default:5) in
            let initial = get_string fields "initial" in
            let placeholder = get_string_opt fields "placeholder" in
            Ok
              ( id,
                Widget_registry.box_textarea ~title ~width ~height ~initial
                  ?placeholder () )
        | "select" ->
            let title = get_string fields "title" in
            let items = get_string_list fields "items" in
            let max_visible = get_int fields "max_visible" ~default:10 in
            Ok (id, Widget_registry.box_select ~title ~items ~max_visible ())
        | "radio" ->
            let label = get_string fields "label" in
            let selected = get_bool fields "selected" ~default:false in
            let disabled = get_bool fields "disabled" ~default:false in
            Ok (id, Widget_registry.box_radio ~label ~selected ~disabled ())
        | "switch" ->
            let label = get_string fields "label" in
            let on = get_bool fields "on" ~default:false in
            let disabled = get_bool fields "disabled" ~default:false in
            Ok (id, Widget_registry.box_switch ~label ~on ~disabled ())
        | "pager" ->
            let title = get_string fields "title" in
            let text = get_string fields "text" in
            let focusable = get_bool fields "focusable" ~default:true in
            Ok (id, Widget_registry.box_pager ~title ~text ~focusable ())
        | "list" ->
            let items = get_string_list fields "items" in
            let indent = get_int fields "indent" ~default:2 in
            let expand_all = get_bool fields "expand_all" ~default:false in
            let item_overrides =
              match List.assoc_opt "groups" fields with
              | Some (`List groups) ->
                  let module LW = Miaou_widgets_display.List_widget in
                  Some
                    (List.concat_map
                       (fun g ->
                         match g with
                         | `Assoc gf ->
                             let label = get_string gf "label" in
                             let citems = get_string_list gf "items" in
                             [
                               LW.group label
                                 (List.map
                                    (fun s -> LW.item ~id:s ~selectable:true s)
                                    citems);
                             ]
                         | _ -> [])
                       groups)
              | _ -> None
            in
            Ok
              ( id,
                Widget_registry.box_list ~items ?item_overrides ~indent
                  ~expand_all () )
        | "description_list" ->
            let title = get_string fields "title" in
            let items = get_string_list fields "items" in
            Ok (id, Widget_registry.box_description_list ~title ~items ())
        | "" -> Error "Widget missing 'type' field"
        | _ -> Error ("Unknown widget type: " ^ typ))
  | _ -> Error "Widget definition must be a JSON object"
