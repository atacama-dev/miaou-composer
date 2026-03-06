(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Widget registry: constructors that create widget_box from parameters.

    Each function takes simple OCaml values (strings, bools, ints) and returns a
    Widget_box.widget_box with all closures properly captured. *)

open Widget_box
module Button_widget = Miaou_widgets_input.Button_widget
module Checkbox_widget = Miaou_widgets_input.Checkbox_widget
module Textbox_widget = Miaou_widgets_input.Textbox_widget
module Textarea_widget = Miaou_widgets_input.Textarea_widget
module Select_widget = Miaou_widgets_input.Select_widget
module Radio_button_widget = Miaou_widgets_input.Radio_button_widget
module Switch_widget = Miaou_widgets_input.Switch_widget
module Pager_widget = Miaou_widgets_display.Pager_widget
module List_widget = Miaou_widgets_display.List_widget
module Description_list = Miaou_widgets_display.Description_list
module Key_event = Miaou_interfaces.Key_event

let _default_size = { LTerm_geom.rows = 24; cols = 80 }

(* --- Input widgets --- *)

let box_button ~label ?(disabled = false) () =
  let clicked = ref false in
  let w =
    Button_widget.create ~disabled ~label
      ~on_click:(fun () -> clicked := true)
      ()
  in
  Box
    {
      type_name = "button";
      widget = (w, clicked);
      render = (fun (w, _) ~focus ~size:_ -> Button_widget.render w ~focus);
      on_key =
        (fun (w, clicked) ~key ->
          clicked := false;
          let w', handled = Button_widget.handle_key w ~key in
          ((w', clicked), handled));
      query =
        (fun (w, _) ->
          ignore w;
          `Assoc [ ("label", `String label); ("disabled", `Bool disabled) ]);
      update =
        (fun (w, c) _patch ->
          (* Button is mostly immutable from outside *)
          (w, c));
      detect_events =
        (fun (_old_w, old_c) (_new_w, new_c) ->
          let was_clicked = !old_c <> !new_c || !new_c in
          if was_clicked then [ ("click", `Null) ] else []);
      focusable = not disabled;
    }

let box_checkbox ?(label = "") ?(checked = false) ?(disabled = false) () =
  let w = Checkbox_widget.create ~label ~checked_:checked ~disabled () in
  Box
    {
      type_name = "checkbox";
      widget = w;
      render = (fun w ~focus ~size:_ -> Checkbox_widget.render w ~focus);
      on_key =
        (fun w ~key ->
          let w', result = Checkbox_widget.on_key w ~key in
          (w', Key_event.to_bool result));
      query =
        (fun w ->
          `Assoc
            [
              ("label", `String label);
              ("checked", `Bool (Checkbox_widget.is_checked w));
            ]);
      update =
        (fun w patch ->
          match patch with
          | `Assoc fields ->
              let w =
                match List.assoc_opt "checked" fields with
                | Some (`Bool v) -> Checkbox_widget.set_checked w v
                | _ -> w
              in
              w
          | _ -> w);
      detect_events =
        (fun old_w new_w ->
          if
            Checkbox_widget.is_checked old_w <> Checkbox_widget.is_checked new_w
          then [ ("toggle", `Bool (Checkbox_widget.is_checked new_w)) ]
          else []);
      focusable = not disabled;
    }

let box_textbox ?(title = "") ?(width = 30) ?(initial = "") ?placeholder
    ?(mask = false) () =
  let mk_widget title_opt text =
    let ph = Some (Option.value placeholder ~default:"") in
    match title_opt with
    | None ->
        Textbox_widget.create ~width ~initial:text ~placeholder:ph ~mask ()
    | Some t ->
        Textbox_widget.create ~title:t ~width ~initial:text ~placeholder:ph
          ~mask ()
  in
  let w = mk_widget (if title = "" then None else Some title) initial in
  Box
    {
      type_name = "textbox";
      widget = w;
      render = (fun w ~focus ~size:_ -> Textbox_widget.render w ~focus);
      on_key =
        (fun w ~key ->
          let w', result = Textbox_widget.on_key w ~key in
          (w', Key_event.to_bool result));
      query =
        (fun w ->
          `Assoc
            [
              ("text", `String (Textbox_widget.get_text w));
              ("cursor", `Int (Textbox_widget.cursor w));
            ]);
      update =
        (fun w patch ->
          match patch with
          | `Assoc fields -> (
              let w =
                match List.assoc_opt "text" fields with
                | Some (`String v) -> Textbox_widget.set_text w v
                | _ -> w
              in
              match List.assoc_opt "title" fields with
              | Some (`String new_title) -> (
                  let text = Textbox_widget.get_text w in
                  let w_width = Textbox_widget.width w in
                  let title_opt =
                    if new_title = "" then None else Some new_title
                  in
                  match title_opt with
                  | None ->
                      Textbox_widget.create ~width:w_width ~initial:text ()
                  | Some t ->
                      Textbox_widget.create ~title:t ~width:w_width
                        ~initial:text ())
              | _ -> w)
          | _ -> w);
      detect_events =
        (fun old_w new_w ->
          if Textbox_widget.get_text old_w <> Textbox_widget.get_text new_w then
            [ ("change", `String (Textbox_widget.get_text new_w)) ]
          else []);
      focusable = true;
    }

let box_textarea ?(title = "") ?(width = 40) ?(height = 5) ?(initial = "")
    ?placeholder () =
  let w =
    Textarea_widget.create ~title ~width ~height ~initial ?placeholder ()
  in
  Box
    {
      type_name = "textarea";
      widget = w;
      render = (fun w ~focus ~size:_ -> Textarea_widget.render w ~focus);
      on_key =
        (fun w ~key ->
          let w', result = Textarea_widget.on_key w ~key in
          (w', Key_event.to_bool result));
      query =
        (fun w -> `Assoc [ ("text", `String (Textarea_widget.get_text w)) ]);
      update =
        (fun w patch ->
          match patch with
          | `Assoc fields ->
              let w =
                match List.assoc_opt "text" fields with
                | Some (`String v) -> Textarea_widget.set_text w v
                | _ -> w
              in
              w
          | _ -> w);
      detect_events =
        (fun old_w new_w ->
          if Textarea_widget.get_text old_w <> Textarea_widget.get_text new_w
          then [ ("change", `String (Textarea_widget.get_text new_w)) ]
          else []);
      focusable = true;
    }

let box_select ~title ~items ?(max_visible = 10) () =
  let w =
    Select_widget.open_centered ~title ~items ~to_string:Fun.id ~max_visible ()
  in
  Box
    {
      type_name = "select";
      widget = w;
      render =
        (fun w ~focus ~size -> Select_widget.render_with_size w ~focus ~size);
      on_key =
        (fun w ~key ->
          let w', result = Select_widget.on_key w ~key in
          (w', Key_event.to_bool result));
      query =
        (fun w ->
          `Assoc
            [
              ( "selection",
                match Select_widget.get_selection w with
                | Some s -> `String s
                | None -> `Null );
            ]);
      update =
        (fun w patch ->
          match patch with
          | `Assoc fields -> (
              match List.assoc_opt "items" fields with
              | Some (`List raw) ->
                  let strs =
                    List.filter_map
                      (function `String s -> Some s | _ -> None)
                      raw
                  in
                  Select_widget.open_centered ~title ~items:strs
                    ~to_string:Fun.id ~max_visible ()
              | _ -> w)
          | _ -> w);
      detect_events =
        (fun old_w new_w ->
          let old_sel = Select_widget.get_selection old_w in
          let new_sel = Select_widget.get_selection new_w in
          if old_sel <> new_sel then
            [
              ( "select",
                match new_sel with Some s -> `String s | None -> `Null );
            ]
          else []);
      focusable = true;
    }

let box_radio ?(label = "") ?(selected = false) ?(disabled = false) () =
  let w = Radio_button_widget.create ~label ~selected ~disabled () in
  Box
    {
      type_name = "radio";
      widget = w;
      render = (fun w ~focus ~size:_ -> Radio_button_widget.render w ~focus);
      on_key =
        (fun w ~key ->
          let w', result = Radio_button_widget.on_key w ~key in
          (w', Key_event.to_bool result));
      query =
        (fun w ->
          `Assoc
            [
              ("label", `String label);
              ("selected", `Bool (Radio_button_widget.is_selected w));
            ]);
      update =
        (fun w patch ->
          match patch with
          | `Assoc fields -> (
              match List.assoc_opt "selected" fields with
              | Some (`Bool v) -> Radio_button_widget.set_selected w v
              | _ -> w)
          | _ -> w);
      detect_events =
        (fun old_w new_w ->
          if
            Radio_button_widget.is_selected old_w
            <> Radio_button_widget.is_selected new_w
          then [ ("select", `Bool (Radio_button_widget.is_selected new_w)) ]
          else []);
      focusable = not disabled;
    }

let box_switch ?(label = "") ?(on = false) ?(disabled = false) () =
  let w = Switch_widget.create ~label ~on ~disabled () in
  Box
    {
      type_name = "switch";
      widget = w;
      render = (fun w ~focus ~size:_ -> Switch_widget.render w ~focus);
      on_key =
        (fun w ~key ->
          let w', result = Switch_widget.on_key w ~key in
          (w', Key_event.to_bool result));
      query =
        (fun w ->
          `Assoc
            [ ("label", `String label); ("on", `Bool (Switch_widget.is_on w)) ]);
      update =
        (fun w patch ->
          match patch with
          | `Assoc fields -> (
              match List.assoc_opt "on" fields with
              | Some (`Bool v) -> Switch_widget.set_on w v
              | _ -> w)
          | _ -> w);
      detect_events =
        (fun old_w new_w ->
          if Switch_widget.is_on old_w <> Switch_widget.is_on new_w then
            [ ("toggle", `Bool (Switch_widget.is_on new_w)) ]
          else []);
      focusable = not disabled;
    }

(* --- Display widgets --- *)

let box_pager ?(title = "") ~text ?(focusable = true) () =
  let w = Pager_widget.open_text ~title text in
  Box
    {
      type_name = "pager";
      widget = w;
      render =
        (fun w ~focus ~size ->
          Pager_widget.render ~cols:size.cols ~win:size.rows w ~focus);
      on_key =
        (fun w ~key ->
          let w', handled = Pager_widget.handle_key w ~key in
          (w', handled));
      query =
        (fun w ->
          `Assoc
            [
              ("offset", `Int w.offset);
              ("line_count", `Int (List.length w.lines));
            ]);
      update =
        (fun _w patch ->
          match patch with
          | `Assoc fields -> (
              match List.assoc_opt "text" fields with
              | Some (`String t) -> Pager_widget.open_text ~title t
              | Some `Null -> Pager_widget.open_text ~title ""
              | _ -> _w)
          | _ -> _w);
      detect_events = (fun _old _new -> []);
      focusable;
    }

let box_list ~items ?(item_overrides : List_widget.item list option)
    ?(indent = 2) ?(expand_all = false) () =
  let actual_items =
    match item_overrides with
    | Some defs -> defs
    | None -> List.map (fun s -> List_widget.item s) items
  in
  let w = List_widget.create ~indent ~expand_all actual_items in
  Box
    {
      type_name = "list";
      widget = w;
      render = (fun w ~focus ~size:_ -> List_widget.render w ~focus);
      on_key =
        (fun w ~key ->
          let w' = List_widget.handle_key w ~key in
          (* Report handled only when the widget state actually changed *)
          (w', not (w' == w)));
      query =
        (fun w ->
          `Assoc
            [
              ( "selected",
                match List_widget.selected w with
                | Some item -> `String item.label
                | None -> `Null );
              ("cursor", `Int (List_widget.cursor_index w));
            ]);
      update =
        (fun w patch ->
          match patch with
          | `Assoc fields -> (
              match List.assoc_opt "items" fields with
              | Some (`List raw) ->
                  let strs =
                    List.filter_map
                      (function `String s -> Some s | _ -> None)
                      raw
                  in
                  List_widget.set_items w (List.map List_widget.item strs)
              | _ -> w)
          | _ -> w);
      detect_events =
        (fun old_w new_w ->
          let old_sel = List_widget.selected old_w in
          let new_sel = List_widget.selected new_w in
          let old_label =
            Option.map (fun (i : List_widget.item) -> i.label) old_sel
          in
          let new_label =
            Option.map (fun (i : List_widget.item) -> i.label) new_sel
          in
          if old_label <> new_label then
            [
              ( "select",
                match new_sel with Some i -> `String i.label | None -> `Null );
            ]
          else []);
      focusable = true;
    }

let box_description_list ?(title = "") ~items () =
  let w =
    Description_list.create ~title ~items:(List.map (fun s -> (s, "")) items) ()
  in
  Box
    {
      type_name = "description_list";
      widget = w;
      render = (fun w ~focus ~size:_ -> Description_list.render w ~focus);
      on_key = (fun w ~key:_ -> (w, false));
      query = (fun _w -> `Assoc []);
      update =
        (fun w patch ->
          match patch with
          | `Assoc fields -> (
              match List.assoc_opt "items" fields with
              | Some (`List raw) ->
                  let strs =
                    List.filter_map
                      (function `String s -> Some s | _ -> None)
                      raw
                  in
                  Description_list.set_items w
                    (List.map (fun s -> (s, "")) strs)
              | _ -> w)
          | _ -> w);
      detect_events = (fun _old _new -> []);
      focusable = false;
    }
