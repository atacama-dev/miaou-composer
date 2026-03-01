(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-32-34-37-69"]

module Clib = Miaou_composer_lib
module Cbridge = Miaou_composer_bridge
module Cpage = Miaou_composer_lib.Page
module Csession = Miaou_composer_lib.Session
module Clayout = Miaou_composer_lib.Layout_tree
module Cwiring = Miaou_composer_lib.Wiring
module Cwbox = Miaou_composer_lib.Widget_box
module Cfactory = Miaou_composer_bridge.Widget_factory
module Ccodec = Miaou_composer_bridge.Page_codec
module Caction = Miaou_composer_bridge.Action_codec
module FB = Miaou_widgets_layout.File_browser_widget
module LW = Miaou_widgets_display.List_widget

type mode = Design | Preview

type pane = PalettePane | TreePane | PropertiesPane | StatePane

type modal_kind =
  | File_path of { label : string; on_confirm : string -> t -> t }
  | File_browser of { fb : FB.t; on_confirm : string -> t -> t }
  | Error_msg of { message : string }

and modal_state = { mk : modal_kind; input : string }

and t = {
  mode : mode;
  session : Csession.t;
  page_id : string;
  widget_counter : int;
  wiring_counter : int;
  focused_widget : string option;
  menu : Menu.t;
  form : Form.t option;
  modal : modal_state option;
  palette : LW.t;
  layout_tree : LW.t;
  properties_form : Form.t option;
  active_pane : pane;
  widget_params : (string, Yojson.Safe.t) Hashtbl.t;
  (* Current insert target: path into the layout tree where new items go *)
  insert_path : int list;
  (* State pane UI *)
  state_cursor : int;
  state_form : Form.t option;
  state_editing_idx : int option;
}

let make_root_layout () =
  Clayout.Flex
    {
      direction = Clayout.Column;
      gap = 1;
      padding = { Clayout.left = 0; right = 0; top = 0; bottom = 0 };
      justify = Clayout.Start;
      align_items = Clayout.Stretch;
      children = [];
    }

let make_palette_items () =
  let catalog = Miaou_composer_lib.Catalog.widget_catalog () in
  let input_types =
    [ "button"; "checkbox"; "textbox"; "textarea"; "select"; "radio"; "switch" ]
  in
  let display_types = [ "pager"; "list"; "description_list" ] in
  let layout_types = [ "flex-row"; "flex-col"; "box"; "card" ] in
  let make_widget_item wtype =
    let exists =
      List.exists (fun e -> e.Miaou_composer_lib.Catalog.name = wtype) catalog
    in
    if exists then Some (LW.item ~id:wtype ~selectable:true wtype) else None
  in
  let input_items = List.filter_map make_widget_item input_types in
  let display_items = List.filter_map make_widget_item display_types in
  let layout_items =
    List.map (fun lt -> LW.item ~id:lt ~selectable:true lt) layout_types
  in
  [
    LW.group ~selectable:false "Input" input_items;
    LW.group ~selectable:false "Display" display_items;
    LW.group ~selectable:false "Layout" layout_items;
  ]

let refresh_layout_tree t =
  let cpage =
    match Csession.get_page t.session ~page_id:t.page_id with
    | Some p -> p
    | None -> failwith "refresh_layout_tree: page not found"
  in
  let nodes = Clayout.collect_display_nodes cpage.Cpage.layout in
  let items =
    List.map
      (fun (n : Clayout.display_node) ->
        let indent = String.make (n.depth * 2) ' ' in
        let icon = if n.is_container then "" else "  " in
        let label = indent ^ icon ^ n.label in
        LW.item ~id:n.id ~selectable:true label)
      nodes
  in
  let old_cursor = LW.cursor_index t.layout_tree in
  let new_lw = LW.set_items t.layout_tree items in
  let n = LW.visible_count new_lw in
  let clamped = if n = 0 then 0 else min old_cursor (n - 1) in
  { t with layout_tree = LW.set_cursor_index new_lw clamped }

let refresh_properties_form t =
  match t.focused_widget with
  | None -> { t with properties_form = None }
  | Some id ->
      let widget_type =
        match Csession.get_page t.session ~page_id:t.page_id with
        | None -> ""
        | Some cpage -> (
            match Hashtbl.find_opt cpage.Cpage.widgets id with
            | Some wb -> Cwbox.type_name wb
            | None -> "")
      in
      if widget_type = "" then { t with properties_form = None }
      else
        let params_json =
          match Hashtbl.find_opt t.widget_params id with
          | Some j -> j
          | None -> `Assoc []
        in
        let form = Form.make_for_existing_widget id widget_type params_json in
        { t with properties_form = form }

let select_widget t ~id =
  let t' = { t with focused_widget = Some id; active_pane = PropertiesPane } in
  refresh_properties_form t'

let select_container t ~container_id =
  match Clayout.path_of_container_id container_id with
  | None -> t
  | Some path ->
      { t with insert_path = path; active_pane = PalettePane }

let insert_path_label t =
  match t.insert_path with
  | [] -> "root"
  | path ->
      let cpage =
        match Csession.get_page t.session ~page_id:t.page_id with
        | Some p -> p
        | None -> failwith "insert_path_label: page not found"
      in
      Clayout.node_label_at cpage.Cpage.layout path

let create () =
  let session = Csession.create () in
  let page_id = "page_1" in
  let layout = make_root_layout () in
  let cpage =
    Cpage.create ~id:page_id ~layout ~size:{ LTerm_geom.rows = 20; cols = 50 }
  in
  ignore (Csession.add_page session cpage);
  (* Start palette cursor on first selectable item (skip group header) *)
  let palette =
    LW.handle_key
      (LW.create ~expand_all:true (make_palette_items ()))
      ~key:"Down"
  in
  {
    mode = Design;
    session;
    page_id;
    widget_counter = 0;
    wiring_counter = 0;
    focused_widget = None;
    menu = Menu.create ();
    form = None;
    modal = None;
    palette;
    layout_tree = LW.create [];
    properties_form = None;
    active_pane = PalettePane;
    widget_params = Hashtbl.create 16;
    insert_path = [];
    state_cursor = 0;
    state_form = None;
    state_editing_idx = None;
  }

let get_page t =
  match Csession.get_page t.session ~page_id:t.page_id with
  | Some p -> p
  | None -> failwith ("Designer: page not found: " ^ t.page_id)

let get_widget_ids t =
  let cpage = get_page t in
  Clayout.collect_ids cpage.Cpage.layout

let get_wiring_count t =
  let cpage = get_page t in
  List.length (Cwiring.to_list cpage.Cpage.wirings)

let get_wirings_display t =
  let cpage = get_page t in
  List.map
    (fun (src, evt, action) ->
      let action_str = Yojson.Safe.to_string (Caction.action_to_json action) in
      (src, evt, action_str))
    (Cwiring.to_list cpage.Cpage.wirings)

let next_widget_id t widget_type =
  let counter = t.widget_counter + 1 in
  let id = Printf.sprintf "%s_%d" widget_type counter in
  (id, { t with widget_counter = counter })

let add_widget t ~widget_type ~params_json =
  let cpage = get_page t in
  let id =
    match Yojson.Safe.Util.member "id" params_json with
    | `String s when s <> "" -> s
    | _ ->
        let id, _ = next_widget_id t widget_type in
        id
  in
  let full_json =
    match params_json with
    | `Assoc fields ->
        let has_type = List.mem_assoc "type" fields in
        let has_id = List.mem_assoc "id" fields in
        let extra =
          (if has_type then [] else [ ("type", `String widget_type) ])
          @ if has_id then [] else [ ("id", `String id) ]
        in
        `Assoc (extra @ fields)
    | _ -> `Assoc [ ("type", `String widget_type); ("id", `String id) ]
  in
  match Cfactory.create_widget full_json with
  | Error msg -> Error msg
  | Ok (widget_id, widget_box) ->
      let position =
        Clayout.count_children_at cpage.Cpage.layout t.insert_path
      in
      (match
         Cpage.add_widget cpage ~id:widget_id ~widget_box ~path:t.insert_path
           ~position
       with
      | Error msg -> Error msg
      | Ok () ->
          let new_counter = t.widget_counter + 1 in
          Ok { t with widget_counter = new_counter })

(** Build default params_json for a widget type. *)
let default_params_for widget_type =
  match widget_type with
  | "button" -> `Assoc [ ("label", `String "Button") ]
  | "pager" -> `Assoc [ ("text", `String "Text content here...") ]
  | "select" ->
      `Assoc
        [
          ("title", `String "Select");
          ("items", `List [ `String "Option 1"; `String "Option 2" ]);
        ]
  | "description_list" ->
      `Assoc [ ("items", `List [ `String "Key: Value" ]) ]
  | "list" ->
      `Assoc [ ("items", `List [ `String "Item 1"; `String "Item 2" ]) ]
  | _ -> `Assoc []

let add_widget_with_defaults t ~widget_type =
  let params_json = default_params_for widget_type in
  let id =
    let counter = t.widget_counter + 1 in
    Printf.sprintf "%s_%d" widget_type counter
  in
  let params_with_id =
    match params_json with
    | `Assoc fields -> `Assoc (("id", `String id) :: fields)
    | _ -> `Assoc [ ("id", `String id) ]
  in
  match add_widget t ~widget_type ~params_json:params_with_id with
  | Error msg -> Error msg
  | Ok t' ->
      Hashtbl.replace t'.widget_params id params_json;
      let t'' = refresh_layout_tree t' in
      (* Stay in PalettePane so the user can keep adding widgets *)
      Ok t''

let add_container t ~container_type =
  let cpage = get_page t in
  let counter = t.widget_counter + 1 in
  let no_pad = Clayout.{ left = 0; right = 0; top = 0; bottom = 0 } in
  let node =
    match container_type with
    | "flex-row" ->
        Clayout.Flex
          {
            direction = Clayout.Row;
            gap = 1;
            padding = no_pad;
            justify = Clayout.Start;
            align_items = Clayout.Stretch;
            children = [];
          }
    | "flex-col" ->
        Clayout.Flex
          {
            direction = Clayout.Column;
            gap = 1;
            padding = no_pad;
            justify = Clayout.Start;
            align_items = Clayout.Stretch;
            children = [];
          }
    | "box" ->
        Clayout.Boxed
          { title = None; style = Clayout.Single; padding = no_pad; child = None }
    | "card" ->
        Clayout.Card { title = None; footer = None; accent = None; child = None }
    | _ -> failwith ("Unknown container type: " ^ container_type)
  in
  let n_before =
    Clayout.count_children_at cpage.Cpage.layout t.insert_path
  in
  ignore
    (Clayout.add_child_at cpage.Cpage.layout ~path:t.insert_path
       ~position:n_before node);
  let new_path = t.insert_path @ [ n_before ] in
  let t' = { t with widget_counter = counter; insert_path = new_path } in
  Ok (refresh_layout_tree t')

let apply_properties_form t form =
  match t.focused_widget with
  | None -> t
  | Some id ->
      let cpage = get_page t in
      let widget_type =
        match Hashtbl.find_opt cpage.Cpage.widgets id with
        | Some wb -> Cwbox.type_name wb
        | None -> ""
      in
      if widget_type = "" then t
      else begin
        (* Find the widget's original location in the layout tree *)
        let orig_path, orig_pos =
          match Clayout.find_widget_parent_info cpage.Cpage.layout id with
          | Some (p, i) -> (p, i)
          | None ->
              (* Fallback: flat index at root *)
              let ids = Clayout.collect_ids cpage.Cpage.layout in
              let pos =
                match
                  List.fold_left
                    (fun (acc, i) wid ->
                      if wid = id then (Some i, i + 1) else (acc, i + 1))
                    (None, 0) ids
                with
                | Some pos, _ -> pos
                | None, _ -> List.length ids
              in
              ([], pos)
        in
        (match Cpage.remove_widget cpage ~id with
        | Error _ -> ()
        | Ok () -> ());
        let params_json = Form.to_json form in
        let new_id = Form.get_id form in
        let actual_id = if new_id = "" then id else new_id in
        let full_json =
          match params_json with
          | `Assoc fields ->
              let fields_no_id =
                List.filter (fun (k, _) -> k <> "id") fields
              in
              `Assoc
                ([ ("type", `String widget_type); ("id", `String actual_id) ]
                @ fields_no_id)
          | _ ->
              `Assoc
                [ ("type", `String widget_type); ("id", `String actual_id) ]
        in
        (match Cfactory.create_widget full_json with
        | Error _ -> ()
        | Ok (wid, wbox) ->
            ignore
              (Cpage.add_widget cpage ~id:wid ~widget_box:wbox ~path:orig_path
                 ~position:orig_pos));
        Hashtbl.replace t.widget_params actual_id params_json;
        let t' = { t with focused_widget = Some actual_id } in
        let t'' = refresh_layout_tree t' in
        refresh_properties_form t''
      end

let remove_widget t ~id =
  let cpage = get_page t in
  match Cpage.remove_widget cpage ~id with
  | Error msg -> Error msg
  | Ok () ->
      Hashtbl.remove t.widget_params id;
      let t' =
        if t.focused_widget = Some id then
          { t with focused_widget = None; properties_form = None }
        else t
      in
      Ok (refresh_layout_tree t')

let add_wiring t ~source ~event ~action =
  let cpage = get_page t in
  ignore (Cwiring.add cpage.Cpage.wirings ~source ~event ~action);
  Ok { t with wiring_counter = t.wiring_counter + 1 }

let remove_wiring_by_index t ~index =
  let cpage = get_page t in
  let wirings = Cwiring.to_list cpage.Cpage.wirings in
  match List.nth_opt wirings index with
  | None -> Error (Printf.sprintf "Wiring index %d not found" index)
  | Some (src, evt, _) ->
      ignore (Cwiring.remove cpage.Cpage.wirings ~source:src ~event:evt);
      Ok t

let switch_mode t =
  match t.mode with
  | Design -> { t with mode = Preview; form = None; modal = None }
  | Preview -> { t with mode = Design }

let open_file_path_modal t label on_confirm =
  let modal = { mk = File_path { label; on_confirm }; input = "" } in
  { t with modal = Some modal }

let open_import_browser t on_confirm =
  let cwd = try Sys.getcwd () with _ -> "/" in
  let fb =
    FB.open_centered ~path:cwd ~dirs_only:false ~require_writable:false
      ~select_dirs:false ~show_hidden:false ()
  in
  let modal = { mk = File_browser { fb; on_confirm }; input = "" } in
  { t with modal = Some modal }

let open_error_modal t message =
  let modal = { mk = Error_msg { message }; input = "" } in
  { t with modal = Some modal }

let close_modal t = { t with modal = None }

let modal_input_append t ch =
  match t.modal with
  | None -> t
  | Some m -> { t with modal = Some { m with input = m.input ^ ch } }

let modal_input_backspace t =
  match t.modal with
  | None -> t
  | Some m ->
      let s = m.input in
      let len = String.length s in
      let new_input = if len > 0 then String.sub s 0 (len - 1) else "" in
      { t with modal = Some { m with input = new_input } }

let modal_confirm t =
  match t.modal with
  | None -> t
  | Some { mk = File_path { on_confirm; _ }; input } ->
      let t' = close_modal t in
      on_confirm input t'
  | Some { mk = Error_msg _; _ } -> close_modal t
  | Some { mk = File_browser _; _ } -> t

let update_file_browser t fb =
  match t.modal with
  | Some ({ mk = File_browser { on_confirm; _ }; _ } as m) ->
      { t with modal = Some { m with mk = File_browser { fb; on_confirm } } }
  | _ -> t

let export_page t path =
  let cpage = get_page t in
  let json = Ccodec.page_to_json cpage in
  try
    Yojson.Safe.to_file path json;
    Ok t
  with Sys_error msg -> Error msg

let import_page t path =
  try
    let json = Yojson.Safe.from_file path in
    match Ccodec.page_of_json json with
    | Error msg -> Error msg
    | Ok new_cpage ->
        ignore (Csession.remove_page t.session ~page_id:t.page_id);
        let new_page_id = new_cpage.Cpage.id in
        ignore (Csession.add_page t.session new_cpage);
        let new_params = Hashtbl.create 16 in
        List.iter
          (fun widget_id ->
            (match Hashtbl.find_opt new_cpage.Cpage.widgets widget_id with
            | Some wb ->
                let wtype = Cwbox.type_name wb in
                let params = default_params_for wtype in
                Hashtbl.replace new_params widget_id params
            | None -> ()))
          (Clayout.collect_ids new_cpage.Cpage.layout);
        let t' =
          {
            t with
            page_id = new_page_id;
            widget_counter = 0;
            wiring_counter = 0;
            focused_widget = None;
            properties_form = None;
            active_pane = PalettePane;
            widget_params = new_params;
            insert_path = [];
            state_cursor = 0;
            state_form = None;
            state_editing_idx = None;
          }
        in
        Ok (refresh_layout_tree t')
  with
  | Sys_error msg -> Error msg
  | Yojson.Json_error msg -> Error ("Invalid JSON: " ^ msg)

let cycle_pane t =
  let next =
    match t.active_pane with
    | PalettePane -> TreePane
    | TreePane -> PropertiesPane
    | PropertiesPane -> StatePane
    | StatePane -> PalettePane
  in
  { t with active_pane = next }

let cycle_pane_back t =
  let prev =
    match t.active_pane with
    | PalettePane -> StatePane
    | TreePane -> PalettePane
    | PropertiesPane -> TreePane
    | StatePane -> PropertiesPane
  in
  { t with active_pane = prev }

(* ---- State schema / binding helpers ---- *)

let get_state_schema t =
  let cpage = get_page t in
  cpage.Cpage.state_schema

let get_state_bindings t =
  let cpage = get_page t in
  cpage.Cpage.state_bindings

let add_state_var t (sv : Clib.Page.state_var) =
  let cpage = get_page t in
  cpage.Cpage.state_schema <- cpage.Cpage.state_schema @ [ sv ];
  Clib.Page.init_state cpage;
  t

let remove_state_var t ~index =
  let cpage = get_page t in
  let schema = cpage.Cpage.state_schema in
  if index < 0 || index >= List.length schema then
    Error (Printf.sprintf "State var index %d not found" index)
  else begin
    cpage.Cpage.state_schema <-
      List.filteri (fun i _ -> i <> index) schema;
    Ok { t with state_cursor = max 0 (index - 1) }
  end

let add_state_binding t (sb : Clib.Page.state_binding) =
  let cpage = get_page t in
  cpage.Cpage.state_bindings <- cpage.Cpage.state_bindings @ [ sb ];
  t

let remove_state_binding t ~index =
  let cpage = get_page t in
  let bindings = cpage.Cpage.state_bindings in
  if index < 0 || index >= List.length bindings then
    Error (Printf.sprintf "State binding index %d not found" index)
  else begin
    cpage.Cpage.state_bindings <-
      List.filteri (fun i _ -> i <> index) bindings;
    Ok t
  end
