(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-32-34-37-69"]

open Miaou_core
module Navigation = Miaou_core.Navigation
module Keys = Miaou_core.Keys
module Key_event = Miaou_interfaces.Key_event
module FB = Miaou_widgets_layout.File_browser_widget
module Flex = Miaou_widgets_layout.Flex_layout
module LW = Miaou_widgets_display.List_widget
module Catalog = Miaou_composer_lib.Catalog
module Action = Miaou_composer_lib.Action
module Clayout = Miaou_composer_lib.Layout_tree

let container_types = [ "flex-row"; "flex-col"; "box"; "card" ]
let left_w = 28
let right_w = 34

(* ---- Status bar ---- *)

let render_status_bar (t : Designer_state.t) cols =
  let mode_str =
    match t.mode with
    | Designer_state.Design -> "DESIGN"
    | Designer_state.Preview -> "PREVIEW"
  in
  let wiring_count = Designer_state.get_wiring_count t in
  let widget_count = List.length (Designer_state.get_widget_ids t) in
  let focused =
    match Preview.get_focused_widget t with Some id -> id | None -> "-"
  in
  let insert_lbl = Designer_state.insert_path_label t in
  let pane_str =
    match t.active_pane with
    | Designer_state.PalettePane -> "Palette"
    | Designer_state.TreePane -> "Tree"
    | Designer_state.PropertiesPane -> "Properties"
    | Designer_state.StatePane -> "State"
    | Designer_state.ToolsPane -> "Tools"
  in
  let bar =
    Printf.sprintf
      " [%s] %s | %d widgets | %d wirings | pane: %s | focus: %s | in: %s"
      mode_str t.page_id widget_count wiring_count pane_str focused insert_lbl
  in
  let padded =
    let len = String.length bar in
    if len >= cols then String.sub bar 0 cols
    else bar ^ String.make (cols - len) ' '
  in
  "\027[7m" ^ padded ^ "\027[0m"

(* ---- Wiring helpers ---- *)

let finish_wiring (t : Designer_state.t) ~source ~event ~action_type ~form =
  let target = Form.get_action_target form in
  let value = Form.get_action_value form in
  let action_opt : Action.t option =
    match action_type with
    | "toggle" -> Some (Action.Toggle { target })
    | "set_text" -> Some (Action.Set_text { target; value })
    | "append_text" -> Some (Action.Append_text { target; value })
    | "set_checked" ->
        let v = value = "true" || value = "1" in
        Some (Action.Set_checked { target; value = v })
    | "focus" -> Some (Action.Focus { target })
    | "set_disabled" ->
        let v = value = "true" || value = "1" in
        Some (Action.Set_disabled { target; value = v })
    | "navigate" -> Some (Action.Navigate { target = value })
    | "back" -> Some Action.Back
    | "quit" -> Some Action.Quit
    | "set_state" ->
        let key = Form.get_field form "key" in
        let value_str = Form.get_field form "value" in
        let json_val =
          try Yojson.Safe.from_string value_str
          with _ -> if value_str = "" then `Null else `String value_str
        in
        if key = "" then None
        else Some (Action.Set_state { key; value = json_val })
    | "copy_widget_to_state" ->
        let key = Form.get_field form "key" in
        let source_id = Form.get_field form "source" in
        if key = "" then None
        else Some (Action.Copy_widget_to_state { key; source = source_id })
    | "inc_state" ->
        let key = Form.get_field form "key" in
        let by_str = Form.get_field form "by" in
        let by = try float_of_string by_str with _ -> 1.0 in
        if key = "" then None else Some (Action.Inc_state { key; by })
    | "reset_state" ->
        let key = Form.get_field form "key" in
        if key = "" then None else Some (Action.Reset_state { key })
    | _ -> None
  in
  match action_opt with
  | None -> t
  | Some act -> (
      match Designer_state.add_wiring t ~source ~event ~action:act with
      | Ok t' -> { t' with menu = Menu.pop t'.menu; form = None }
      | Error msg -> Designer_state.open_error_modal t msg)

(* ---- Form submission ---- *)

let submit_add_widget (t : Designer_state.t) form widget_type =
  let existing_ids = Designer_state.get_widget_ids t in
  match Form.validate form ~existing_ids with
  | Error errors ->
      let form' = { form with Form.errors } in
      { t with form = Some form' }
  | Ok () -> (
      let params_json = Form.to_json form in
      match Designer_state.add_widget t ~widget_type ~params_json with
      | Error msg -> Designer_state.open_error_modal t msg
      | Ok t' -> { t' with form = None; menu = Menu.pop t'.menu })

(* ---- Handle menu action (kept for old menu path / wiring flow) ---- *)

let handle_menu_action (t : Designer_state.t) action =
  match action with
  | Menu.GoSubmenu "add_widget" ->
      { t with menu = Menu.push_level t.menu (Menu.widget_catalog_level ()) }
  | Menu.GoSubmenu s
    when String.length s > 10 && String.sub s 0 10 = "__remove__" -> (
      let id = String.sub s 11 (String.length s - 11) in
      match Designer_state.remove_widget t ~id with
      | Error msg -> Designer_state.open_error_modal t msg
      | Ok t' -> { t' with menu = Menu.pop t'.menu })
  | Menu.GoSubmenu _ -> t
  | Menu.AddWidget wtype -> (
      match Form.make_for_widget_type wtype with
      | None -> t
      | Some form ->
          {
            t with
            form = Some form;
            menu = Menu.push_level t.menu (Menu.widget_catalog_level ());
          })
  | Menu.RemoveWidget ->
      let ids = Designer_state.get_widget_ids t in
      let items =
        List.map
          (fun id ->
            Menu.
              { label = id; hint = ""; action = GoSubmenu ("__remove__:" ^ id) })
          ids
      in
      let level =
        Menu.
          { title = "Remove Widget"; items = Array.of_list items; cursor = 0 }
      in
      { t with menu = Menu.push_level t.menu level }
  | Menu.AddWiringStep1 ->
      let ids = Designer_state.get_widget_ids t in
      if ids = [] then
        Designer_state.open_error_modal t
          "No widgets to wire. Add widgets first."
      else
        { t with menu = Menu.push_level t.menu (Menu.wiring_step1_level ids) }
  | Menu.AddWiringStep2 source ->
      let page = Designer_state.get_page t in
      let catalog = Catalog.widget_catalog () in
      let widget_type =
        match Hashtbl.find_opt page.Miaou_composer_lib.Page.widgets source with
        | Some wb -> Miaou_composer_lib.Widget_box.type_name wb
        | None -> ""
      in
      let events =
        match List.find_opt (fun e -> e.Catalog.name = widget_type) catalog with
        | Some entry -> entry.events
        | None -> [ "click"; "change"; "toggle"; "select" ]
      in
      {
        t with
        menu = Menu.push_level t.menu (Menu.wiring_step2_level source events);
      }
  | Menu.AddWiringStep3 (source, event) ->
      {
        t with
        menu = Menu.push_level t.menu (Menu.wiring_step3_level source event);
      }
  | Menu.AddWiringFinish (source, event, action_type) ->
      let widget_ids = Designer_state.get_widget_ids t in
      if action_type = "back" || action_type = "quit" then
        let dummy_form = Form.make_wiring_action_form action_type [] in
        finish_wiring t ~source ~event ~action_type ~form:dummy_form
      else
        let form = Form.make_wiring_action_form action_type widget_ids in
        let form' =
          {
            form with
            Form.title =
              Printf.sprintf "Wiring: %s.%s -> %s" source event action_type;
          }
        in
        {
          t with
          form = Some form';
          menu =
            Menu.push_level t.menu Menu.{ title = ""; items = [||]; cursor = 0 };
        }
  | Menu.RemoveWiring i -> (
      match Designer_state.remove_wiring_by_index t ~index:i with
      | Error msg -> Designer_state.open_error_modal t msg
      | Ok t' -> { t' with menu = Menu.pop t'.menu })
  | Menu.ListWirings ->
      let wirings = Designer_state.get_wirings_display t in
      { t with menu = Menu.push_level t.menu (Menu.wiring_list_level wirings) }
  | Menu.PreviewMode -> Designer_state.switch_mode t
  | Menu.Export ->
      let on_confirm path t' =
        match Designer_state.export_page t' path with
        | Ok t'' -> t''
        | Error msg -> Designer_state.open_error_modal t' msg
      in
      Designer_state.open_file_path_modal t "Export to file:" on_confirm
  | Menu.Import ->
      let on_confirm path t' =
        match Designer_state.import_page t' path with
        | Ok t'' -> t''
        | Error msg -> Designer_state.open_error_modal t' msg
      in
      Designer_state.open_import_browser t on_confirm
  | Menu.Quit -> t

(* ---- Modal key handler ---- *)

and handle_modal_key (t : Designer_state.t) (key : Keys.t) =
  match t.modal with
  | Some { mk = Designer_state.File_browser { fb; on_confirm }; _ } -> (
      let key_str =
        match key with Keys.Escape -> "Esc" | _ -> Keys.to_string key
      in
      let fb' = FB.handle_key fb ~key:key_str in
      if FB.is_cancelled fb' then Designer_state.close_modal t
      else
        match FB.get_pending_selection fb' with
        | Some path ->
            let t' = Designer_state.close_modal t in
            on_confirm path t'
        | None -> Designer_state.update_file_browser t fb')
  | _ -> (
      match key with
      | Keys.Escape -> Designer_state.close_modal t
      | Keys.Enter -> Designer_state.modal_confirm t
      | Keys.Backspace -> Designer_state.modal_input_backspace t
      | Keys.Char c -> Designer_state.modal_input_append t c
      | _ -> t)

(* ---- Legacy form key handler (wiring forms use t.form) ---- *)

and handle_legacy_form_key (t : Designer_state.t) form (key : Keys.t) =
  match key with
  | Keys.Escape -> { t with Designer_state.form = None; menu = Menu.pop t.menu }
  | Keys.Tab ->
      let form' = Form.move_focus form 1 in
      { t with form = Some form' }
  | Keys.ShiftTab ->
      let form' = Form.move_focus form (-1) in
      { t with form = Some form' }
  | Keys.Enter ->
      let title = form.Form.title in
      let is_widget_form =
        String.length title > 4 && String.sub title 0 4 = "Add "
      in
      let is_wiring_form =
        String.length title > 8 && String.sub title 0 8 = "Wiring: "
      in
      if is_widget_form then
        let widget_type = String.sub title 4 (String.length title - 4) in
        submit_add_widget t form widget_type
      else if is_wiring_form then begin
        let body = String.sub title 8 (String.length title - 8) in
        match String.split_on_char ' ' body with
        | src_evt :: "->" :: act :: _ -> (
            match String.index_opt src_evt '.' with
            | None -> t
            | Some dot_pos ->
                let source = String.sub src_evt 0 dot_pos in
                let event =
                  String.sub src_evt (dot_pos + 1)
                    (String.length src_evt - dot_pos - 1)
                in
                finish_wiring t ~source ~event ~action_type:act ~form)
        | _ -> t
      end
      else t
  | Keys.Backspace ->
      let form' = Form.update_focused_field form "Backspace" in
      { t with form = Some form' }
  | Keys.Char c ->
      let form' = Form.update_focused_field form c in
      { t with form = Some form' }
  | _ -> t

(* ---- Three-pane render helpers ---- *)

let render_palette (t : Designer_state.t) ~size:_ =
  LW.render t.palette ~focus:(t.active_pane = Designer_state.PalettePane)

let render_layout_tree (t : Designer_state.t) ~size:_ =
  let title = "─ Layout Tree " ^ String.make 14 '-' in
  title ^ "\n"
  ^ LW.render t.layout_tree ~focus:(t.active_pane = Designer_state.TreePane)

let render_left_pane (t : Designer_state.t) ~size =
  match t.modal with
  | Some { mk = Designer_state.File_path { label; _ }; input } ->
      ignore size;
      Printf.sprintf "\n  %s\n  > %s_\n\n  [Enter] confirm  [Esc] cancel" label
        input
  | Some { mk = Designer_state.File_browser { fb; _ }; _ } ->
      FB.render_with_size fb ~focus:true
        ~size:{ LTerm_geom.rows = size.LTerm_geom.rows; cols = left_w }
  | Some { mk = Designer_state.Error_msg { message }; _ } ->
      ignore size;
      Printf.sprintf "\n  Error:\n  %s\n\n  [Esc] dismiss" message
  | None -> (
      match t.form with
      | Some form -> Form.render form ~width:left_w
      | None ->
          (* Palette + layout tree stacked in a column flex *)
          let palette_rows = max 1 (size.LTerm_geom.rows * 6 / 10) in
          let tree_rows = max 1 (size.LTerm_geom.rows - palette_rows) in
          let palette_size =
            { LTerm_geom.rows = palette_rows; cols = left_w }
          in
          let tree_size = { LTerm_geom.rows = tree_rows; cols = left_w } in
          let layout =
            Flex.create ~direction:Flex.Column ~align_items:Flex.Stretch
              [
                {
                  Flex.render = (fun ~size -> render_palette t ~size);
                  basis = Flex.Ratio 0.6;
                  cross = None;
                };
                {
                  Flex.render = (fun ~size -> render_layout_tree t ~size);
                  basis = Flex.Ratio 0.4;
                  cross = None;
                };
              ]
          in
          ignore (palette_size, tree_size);
          Flex.render layout ~size)

let render_canvas (t : Designer_state.t) ~size =
  Preview.render_preview t ~cols:size.LTerm_geom.cols ~rows:size.LTerm_geom.rows

let render_state_pane (t : Designer_state.t) ~width =
  let schema = Designer_state.get_state_schema t in
  let bindings = Designer_state.get_state_bindings t in
  let header =
    Printf.sprintf "State Variables (%d)\n" (List.length schema)
    ^ String.make width '-' ^ "\n"
  in
  let var_lines =
    List.mapi
      (fun i (sv : Miaou_composer_lib.Page.state_var) ->
        let cursor_mark = if i = t.state_cursor then ">" else " " in
        let scope_str =
          match sv.scope with
          | Miaou_composer_lib.Page.Ephemeral -> "eph"
          | Miaou_composer_lib.Page.Persistent -> "per"
        in
        let typ_str =
          match sv.typ with
          | `String -> "str"
          | `Bool -> "bool"
          | `Int -> "int"
          | `Float -> "flt"
          | `Json -> "json"
          | `String_list -> "lst"
        in
        let default_str = Yojson.Safe.to_string sv.default in
        Printf.sprintf "%s %-14s %-4s %s %s" cursor_mark sv.key typ_str
          scope_str default_str)
      schema
  in
  let vars_section =
    if schema = [] then "  (no state vars)\n"
    else String.concat "\n" var_lines ^ "\n"
  in
  let bindings_section =
    if bindings = [] then ""
    else
      let hdr = "\n  Bindings:\n" in
      let rows =
        List.map
          (fun (b : Miaou_composer_lib.Page.state_binding) ->
            Printf.sprintf "  %s -> %s.%s" b.key b.widget_id b.prop)
          bindings
      in
      hdr ^ String.concat "\n" rows ^ "\n"
  in
  let form_section =
    match t.state_form with
    | Some form -> "\n" ^ String.make width '-' ^ "\n" ^ Form.render form ~width
    | None -> "\n  [a] Add  [d] Del  [Enter] Edit\n"
  in
  header ^ vars_section ^ bindings_section ^ form_section

let render_tools_pane (t : Designer_state.t) ~width =
  let tools = Designer_state.get_tools t in
  let init_actions = Designer_state.get_init_actions t in
  let header =
    Printf.sprintf "Tools (%d)\n" (List.length tools)
    ^ String.make width '-' ^ "\n"
  in
  let tool_lines =
    List.mapi
      (fun i (tool : Miaou_composer_lib.Tool_def.t) ->
        let cursor_mark = if i = t.tool_cursor then ">" else " " in
        let name = Miaou_composer_lib.Tool_def.name tool in
        let typ_str =
          match tool with
          | Miaou_composer_lib.Tool_def.Builtin _ -> "builtin"
          | Miaou_composer_lib.Tool_def.Process _ -> "process"
          | Miaou_composer_lib.Tool_def.Shell _ -> "shell"
        in
        Printf.sprintf "%s %-20s %s" cursor_mark name typ_str)
      tools
  in
  let tools_section =
    if tools = [] then "  (no tools)\n"
    else String.concat "\n" tool_lines ^ "\n"
  in
  let ia_header =
    Printf.sprintf "\nInit Actions (%d)\n" (List.length init_actions)
    ^ String.make width '-' ^ "\n"
  in
  let ia_lines =
    List.mapi
      (fun i action ->
        let cursor_mark = if i = t.init_action_cursor then ">" else " " in
        let action_json =
          Miaou_composer_bridge.Action_codec.action_to_json action
        in
        let action_str = Yojson.Safe.to_string action_json in
        Printf.sprintf "%s %s" cursor_mark action_str)
      init_actions
  in
  let ia_section =
    if init_actions = [] then "  (no init actions)\n"
    else String.concat "\n" ia_lines ^ "\n"
  in
  let hint = "\n  [a] Add tool  [d] Del tool\n  [t] Focus tools pane\n" in
  header ^ tools_section ^ ia_header ^ ia_section ^ hint

let render_info_panel (t : Designer_state.t) ~width =
  let widget_count = List.length (Designer_state.get_widget_ids t) in
  let wiring_count = Designer_state.get_wiring_count t in
  let insert_lbl = Designer_state.insert_path_label t in
  let info =
    Printf.sprintf
      "  Page: %s\n\
      \  Insert into: %s\n\n\
      \  Widgets: %d  Wirings: %d\n\n\
      \  Keys:\n\
      \  [Enter]  Add / select\n\
      \  [Esc]    Reset insert target\n\
      \  [p]  Preview\n\
      \  [i]  Import\n\
      \  [e]  Export\n\
      \  [w]  Wire\n\
      \  [s]  State vars\n\
      \  [t]  Tools\n\
      \  [q]  Quit\n\
      \  [Tab]  Next pane\n\
      \  [Del]  Remove widget"
      t.page_id insert_lbl widget_count wiring_count
  in
  ignore width;
  info

let render_right_pane (t : Designer_state.t) ~size =
  let width = size.LTerm_geom.cols in
  if t.active_pane = Designer_state.StatePane then render_state_pane t ~width
  else if t.active_pane = Designer_state.ToolsPane then
    render_tools_pane t ~width
  else
    match t.properties_form with
    | Some form ->
        let title_line = "Properties\n" ^ String.make width '-' ^ "\n" in
        title_line ^ Form.render form ~width
    | None -> render_info_panel t ~width

(* ---- Three-pane view ---- *)

(* Prepend \027[0m to every line so each column resets any lingering ANSI state
   from the previous column before rendering its own content. This prevents
   selection highlights from bleeding across column boundaries. *)
let with_column_reset render_fn ~size =
  let raw = render_fn ~size in
  raw |> String.split_on_char '\n'
  |> List.map (fun line -> "\027[0m" ^ line)
  |> String.concat "\n"

let view pstate ~focus:_ ~size =
  let t = pstate.Navigation.s in
  let content =
    { size with LTerm_geom.rows = max 1 (size.LTerm_geom.rows - 2) }
  in
  let layout =
    Flex.create ~direction:Flex.Row ~align_items:Flex.Stretch
      [
        {
          Flex.render = (fun ~size -> render_left_pane t ~size);
          basis = Flex.Px left_w;
          cross = None;
        };
        {
          Flex.render = with_column_reset (fun ~size -> render_canvas t ~size);
          basis = Flex.Fill;
          cross = None;
        };
        {
          Flex.render =
            with_column_reset (fun ~size -> render_right_pane t ~size);
          basis = Flex.Px right_w;
          cross = None;
        };
      ]
  in
  Flex.render layout ~size:content
  ^ "\n"
  ^ render_status_bar t size.LTerm_geom.cols

(* ---- Key handlers for three-pane design mode ---- *)

let handle_palette_key (t : Designer_state.t) (key : Keys.t) =
  match key with
  | Keys.Up ->
      let p = LW.handle_key t.palette ~key:"Up" in
      { t with Designer_state.palette = p }
  | Keys.Down ->
      let p = LW.handle_key t.palette ~key:"Down" in
      { t with Designer_state.palette = p }
  | Keys.Left ->
      let p = LW.handle_key t.palette ~key:"Left" in
      { t with Designer_state.palette = p }
  | Keys.Right ->
      let p = LW.handle_key t.palette ~key:"Right" in
      { t with Designer_state.palette = p }
  | Keys.Enter -> (
      match LW.selected t.palette with
      | None -> t
      | Some item -> (
          if not item.LW.selectable then
            (* group header — toggle expand *)
            { t with Designer_state.palette = LW.toggle t.palette }
          else
            let widget_type = Option.value ~default:item.LW.label item.LW.id in
            if List.mem widget_type container_types then
              (* Layout container — add to layout tree *)
              match
                Designer_state.add_container t ~container_type:widget_type
              with
              | Error msg -> Designer_state.open_error_modal t msg
              | Ok t' -> t'
            else
              (* Leaf widget — add at current insert target *)
              match Designer_state.add_widget_with_defaults t ~widget_type with
              | Error msg -> Designer_state.open_error_modal t msg
              | Ok t' -> t'))
  | _ -> t

let handle_tree_key (t : Designer_state.t) (key : Keys.t) =
  match key with
  | Keys.Up ->
      let lw = LW.handle_key t.layout_tree ~key:"Up" in
      { t with Designer_state.layout_tree = lw }
  | Keys.Down ->
      let lw = LW.handle_key t.layout_tree ~key:"Down" in
      { t with Designer_state.layout_tree = lw }
  | Keys.Enter -> (
      match LW.selected t.layout_tree with
      | None -> t
      | Some item ->
          let id = Option.value ~default:item.LW.label item.LW.id in
          if Clayout.is_container_id id then
            (* Select container as insert target, switch to palette *)
            Designer_state.select_container t ~container_id:id
          else
            (* Select leaf widget to edit properties *)
            Designer_state.select_widget t ~id)
  | Keys.Escape ->
      (* Reset insert target to root, return to palette *)
      {
        t with
        Designer_state.insert_path = [];
        Designer_state.active_pane = Designer_state.PalettePane;
      }
  | Keys.Delete | Keys.Backspace -> (
      match LW.selected t.layout_tree with
      | None -> t
      | Some item -> (
          let id = Option.value ~default:item.LW.label item.LW.id in
          if Clayout.is_container_id id then t (* TODO: container removal *)
          else
            match Designer_state.remove_widget t ~id with
            | Error msg -> Designer_state.open_error_modal t msg
            | Ok t' -> t'))
  | _ -> t

let handle_state_key (t : Designer_state.t) (key : Keys.t) =
  match t.state_form with
  | Some form -> (
      (* Form is open: route keys to it *)
      match key with
      | Keys.Escape -> { t with state_form = None; state_editing_idx = None }
      | Keys.Tab -> { t with state_form = Some (Form.move_focus form 1) }
      | Keys.ShiftTab ->
          { t with state_form = Some (Form.move_focus form (-1)) }
      | Keys.Enter -> (
          match Form.form_to_state_var form with
          | None -> t
          | Some sv ->
              let t' =
                match t.state_editing_idx with
                | Some idx ->
                    (* Replace existing var *)
                    let cpage = Designer_state.get_page t in
                    let schema = cpage.Miaou_composer_lib.Page.state_schema in
                    let new_schema =
                      List.mapi (fun i v -> if i = idx then sv else v) schema
                    in
                    cpage.Miaou_composer_lib.Page.state_schema <- new_schema;
                    t
                | None -> Designer_state.add_state_var t sv
              in
              { t' with state_form = None; state_editing_idx = None })
      | Keys.Backspace ->
          {
            t with
            state_form = Some (Form.update_focused_field form "Backspace");
          }
      | Keys.Char c ->
          { t with state_form = Some (Form.update_focused_field form c) }
      | _ -> t)
  | None -> (
      let schema = Designer_state.get_state_schema t in
      let n = List.length schema in
      match key with
      | Keys.Up ->
          let c = if t.state_cursor > 0 then t.state_cursor - 1 else 0 in
          { t with state_cursor = c }
      | Keys.Down ->
          let c =
            if t.state_cursor < n - 1 then t.state_cursor + 1
            else t.state_cursor
          in
          { t with state_cursor = c }
      | Keys.Char "a" ->
          let form = Form.make_state_var_form () in
          { t with state_form = Some form; state_editing_idx = None }
      | Keys.Char "d" | Keys.Delete -> (
          if n = 0 then t
          else
            match Designer_state.remove_state_var t ~index:t.state_cursor with
            | Ok t' -> t'
            | Error msg -> Designer_state.open_error_modal t msg)
      | Keys.Enter ->
          if n = 0 then t
          else
            let sv = List.nth schema t.state_cursor in
            let typ_str =
              match sv.Miaou_composer_lib.Page.typ with
              | `String -> "string"
              | `Bool -> "bool"
              | `Int -> "int"
              | `Float -> "float"
              | `Json -> "json"
              | `String_list -> "string_list"
            in
            let scope_str =
              match sv.Miaou_composer_lib.Page.scope with
              | Miaou_composer_lib.Page.Ephemeral -> "ephemeral"
              | Miaou_composer_lib.Page.Persistent -> "persistent"
            in
            let default_str =
              Yojson.Safe.to_string sv.Miaou_composer_lib.Page.default
            in
            let form =
              Form.make_state_var_form ~key:sv.Miaou_composer_lib.Page.key
                ~typ:typ_str ~default:default_str ~scope:scope_str ()
            in
            {
              t with
              state_form = Some form;
              state_editing_idx = Some t.state_cursor;
            }
      | Keys.Escape -> { t with active_pane = Designer_state.PalettePane }
      | _ -> t)

let handle_properties_key (t : Designer_state.t) (key : Keys.t) =
  match t.properties_form with
  | None -> t
  | Some form -> (
      match key with
      | Keys.Escape ->
          {
            t with
            focused_widget = None;
            properties_form = None;
            active_pane = Designer_state.PalettePane;
          }
      | Keys.Tab ->
          let form' = Form.move_focus form 1 in
          { t with properties_form = Some form' }
      | Keys.ShiftTab ->
          let form' = Form.move_focus form (-1) in
          { t with properties_form = Some form' }
      | Keys.Enter ->
          let t' = Designer_state.apply_properties_form t form in
          t'
      | Keys.Backspace ->
          let form' = Form.update_focused_field form "Backspace" in
          { t with properties_form = Some form' }
      | Keys.Char c ->
          let form' = Form.update_focused_field form c in
          { t with properties_form = Some form' }
      | _ -> t)

let handle_tools_key (t : Designer_state.t) (key : Keys.t) =
  let tools = Designer_state.get_tools t in
  let tool_count = List.length tools in
  let init_actions = Designer_state.get_init_actions t in
  let ia_count = List.length init_actions in
  match key with
  | Keys.Up -> { t with tool_cursor = max 0 (t.tool_cursor - 1) }
  | Keys.Down ->
      if tool_count > 0 then
        { t with tool_cursor = min (tool_count - 1) (t.tool_cursor + 1) }
      else t
  | Keys.Char "a" ->
      (* Add a basic builtin tool *)
      let tool = Miaou_composer_lib.Tool_def.Builtin { name = "new_tool" } in
      Designer_state.add_tool t tool
  | Keys.Char "d" ->
      if tool_count > 0 then
        match Designer_state.remove_tool t ~index:t.tool_cursor with
        | Ok t' -> t'
        | Error _ -> t
      else t
  | Keys.Char "A" ->
      (* Add a call_tool init action *)
      let action =
        Miaou_composer_lib.Action.Call_tool { name = ""; args = [] }
      in
      let t' = Designer_state.add_init_action t action in
      { t' with init_action_cursor = ia_count }
  | Keys.Char "D" ->
      if ia_count > 0 then
        match
          Designer_state.remove_init_action t ~index:t.init_action_cursor
        with
        | Ok t' -> t'
        | Error _ -> t
      else t
  | _ -> t

(* ---- on_key ---- *)

let on_key pstate key ~size:_ =
  let t = pstate.Navigation.s in
  match t.Designer_state.mode with
  | Designer_state.Preview -> (
      match key with
      | Keys.Escape ->
          let t' = Designer_state.switch_mode t in
          (Navigation.update (fun _ -> t') pstate, Key_event.Handled)
      | Keys.Char c ->
          Preview.send_key t ~key:c;
          (pstate, Key_event.Handled)
      | Keys.Tab ->
          Preview.send_key t ~key:"Tab";
          (pstate, Key_event.Handled)
      | Keys.ShiftTab ->
          Preview.send_key t ~key:"S-Tab";
          (pstate, Key_event.Handled)
      | Keys.Enter ->
          Preview.send_key t ~key:"Enter";
          (pstate, Key_event.Handled)
      | Keys.Backspace ->
          Preview.send_key t ~key:"Backspace";
          (pstate, Key_event.Handled)
      | Keys.Up ->
          Preview.send_key t ~key:"Up";
          (pstate, Key_event.Handled)
      | Keys.Down ->
          Preview.send_key t ~key:"Down";
          (pstate, Key_event.Handled)
      | Keys.Left ->
          Preview.send_key t ~key:"Left";
          (pstate, Key_event.Handled)
      | Keys.Right ->
          Preview.send_key t ~key:"Right";
          (pstate, Key_event.Handled)
      | _ -> (pstate, Key_event.Bubble))
  | Designer_state.Design -> (
      match t.Designer_state.modal with
      | Some _ ->
          let t' = handle_modal_key t key in
          (Navigation.update (fun _ -> t') pstate, Key_event.Handled)
      | None -> (
          (* Legacy form (wiring forms) take priority *)
          match t.Designer_state.form with
          | Some form ->
              let t' = handle_legacy_form_key t form key in
              (Navigation.update (fun _ -> t') pstate, Key_event.Handled)
          | None ->
              (* When in PropertiesPane with an open form, all keys go to the form
                 handler — this prevents global shortcuts (p/e/i/w) and Tab
                 from interfering while the user is typing / navigating fields. *)
              let t' =
                if
                  t.Designer_state.active_pane = Designer_state.PropertiesPane
                  && t.Designer_state.properties_form <> None
                then handle_properties_key t key
                else if
                  t.Designer_state.active_pane = Designer_state.StatePane
                  && t.Designer_state.state_form <> None
                then handle_state_key t key
                else
                  match key with
                  | Keys.Tab -> Designer_state.cycle_pane t
                  | Keys.ShiftTab -> Designer_state.cycle_pane_back t
                  | Keys.Char "p" -> Designer_state.switch_mode t
                  | Keys.Char "e" -> handle_menu_action t Menu.Export
                  | Keys.Char "i" -> handle_menu_action t Menu.Import
                  | Keys.Char "w" -> handle_menu_action t Menu.AddWiringStep1
                  | Keys.Char "s" when t.active_pane <> Designer_state.StatePane
                    ->
                      { t with active_pane = Designer_state.StatePane }
                  | Keys.Char "t" when t.active_pane <> Designer_state.ToolsPane
                    ->
                      { t with active_pane = Designer_state.ToolsPane }
                  | Keys.Char "q" -> t (* handled below *)
                  | _ -> (
                      (* Delegate to active pane *)
                      match t.active_pane with
                      | Designer_state.PalettePane -> handle_palette_key t key
                      | Designer_state.TreePane -> handle_tree_key t key
                      | Designer_state.PropertiesPane ->
                          handle_properties_key t key
                      | Designer_state.StatePane -> handle_state_key t key
                      | Designer_state.ToolsPane -> handle_tools_key t key)
              in
              let is_quit = key = Keys.Char "q" && t' == t in
              if is_quit then (Navigation.quit pstate, Key_event.Handled)
              else (Navigation.update (fun _ -> t') pstate, Key_event.Handled)))

(* ---- PAGE_SIG ---- *)

type state = Designer_state.t
type msg = unit

let init () =
  let s = Designer_state.create () in
  Navigation.make s

let update pstate _msg = pstate
let on_modal_key pstate key ~size = on_key pstate key ~size

let has_modal pstate =
  let t = pstate.Navigation.s in
  t.Designer_state.modal <> None

let key_hints pstate =
  let _t = pstate.Navigation.s in
  []

let refresh pstate = pstate

(* Deprecated stubs *)
type key_binding = state Tui_page.key_binding_desc
type pstate = state Navigation.t

let handle_key pstate _s ~size:_ = pstate
let handle_modal_key pstate _s ~size:_ = pstate
let keymap _pstate = []
let move pstate _n = pstate
let service_select pstate _n = pstate
let service_cycle pstate _n = pstate
let back pstate = pstate
let handled_keys () = []
