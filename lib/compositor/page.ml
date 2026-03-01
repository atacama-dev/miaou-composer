(** A live page: layout tree + widget store + focus ring + wirings + modals. *)

module Focus_ring = Miaou_internals.Focus_ring
module Flex_layout = Miaou_widgets_layout.Flex_layout
module Grid_layout = Miaou_widgets_layout.Grid_layout
module Box_widget = Miaou_widgets_layout.Box_widget
module Card_widget = Miaou_widgets_layout.Card_widget

type state_scope = Ephemeral | Persistent

type state_var = {
  key : string;
  typ : [ `String | `Bool | `Int | `Float | `Json ];
  default : Yojson.Safe.t;
  scope : state_scope;
}

type state_binding = {
  key : string;
  widget_id : string;
  prop : string;
}

type t = {
  id : string;
  mutable layout : Layout_tree.t;
  widgets : (string, Widget_box.widget_box) Hashtbl.t;
  mutable focus_ring : Focus_ring.t;
  wirings : Wiring.t;
  mutable size : LTerm_geom.size;
  mutable state_schema : state_var list;
  mutable state_bindings : state_binding list;
  state : (string, Yojson.Safe.t) Hashtbl.t;
}

type emit_event = { name : string; snapshot : Yojson.Safe.t }

let create ~id ~layout ~size =
  let widgets = Hashtbl.create 16 in
  let wirings = Wiring.create () in
  let focus_ring = Focus_ring.create [] in
  let state = Hashtbl.create 8 in
  {
    id;
    layout;
    widgets;
    focus_ring;
    wirings;
    size;
    state_schema = [];
    state_bindings = [];
    state;
  }

let persistent_state_path page = page.id ^ ".state.json"

let save_persistent_state page =
  let path = persistent_state_path page in
  let pairs =
    List.filter_map
      (fun (sv : state_var) ->
        if sv.scope = Persistent then
          match Hashtbl.find_opt page.state sv.key with
          | Some v -> Some (sv.key, v)
          | None -> None
        else None)
      page.state_schema
  in
  if pairs <> [] then
    (try Yojson.Safe.to_file path (`Assoc pairs) with _ -> ())

let init_state page =
  List.iter
    (fun (sv : state_var) -> Hashtbl.replace page.state sv.key sv.default)
    page.state_schema;
  let path = persistent_state_path page in
  (try
     match Yojson.Safe.from_file path with
     | `Assoc fields ->
         List.iter
           (fun (sv : state_var) ->
             if sv.scope = Persistent then
               match List.assoc_opt sv.key fields with
               | Some v -> Hashtbl.replace page.state sv.key v
               | None -> ())
           page.state_schema
     | _ -> ()
   with _ -> ())

let rebuild_focus page =
  page.focus_ring <-
    Focus_manager.rebuild ~layout_tree:page.layout ~widgets:page.widgets

let add_widget page ~id ~widget_box ~path ~position =
  if Hashtbl.mem page.widgets id then Error ("Duplicate widget ID: " ^ id)
  else
    let basis = Layout_tree.Auto in
    let leaf = Layout_tree.Leaf { id; basis } in
    if Layout_tree.add_child_at page.layout ~path ~position leaf then begin
      Hashtbl.replace page.widgets id widget_box;
      rebuild_focus page;
      Ok ()
    end
    else Error "Invalid parent path"

let remove_widget page ~id =
  if not (Hashtbl.mem page.widgets id) then Error ("Widget not found: " ^ id)
  else begin
    ignore (Layout_tree.remove_leaf_by_id page.layout id);
    Hashtbl.remove page.widgets id;
    Wiring.remove_by_widget page.wirings ~widget_id:id;
    Wiring.remove_by_target page.wirings ~target_id:id;
    rebuild_focus page;
    Ok ()
  end

let update_widget page ~id ~patch =
  match Hashtbl.find_opt page.widgets id with
  | None -> Error ("Widget not found: " ^ id)
  | Some wb ->
      Hashtbl.replace page.widgets id (Widget_box.update wb patch);
      Ok ()

let set_state_value page ~key ~value =
  Hashtbl.replace page.state key value;
  List.iter
    (fun (b : state_binding) ->
      if b.key = key then
        ignore
          (update_widget page ~id:b.widget_id
             ~patch:(`Assoc [ (b.prop, value) ])))
    page.state_bindings;
  (match
     List.find_opt (fun (sv : state_var) -> sv.key = key) page.state_schema
   with
  | Some sv when sv.scope = Persistent -> save_persistent_state page
  | _ -> ())

let reset_page_state page =
  List.iter
    (fun (sv : state_var) ->
      if sv.scope = Ephemeral then
        set_state_value page ~key:sv.key ~value:sv.default)
    page.state_schema

let render page =
  let rec render_node node =
    match node with
    | Layout_tree.Leaf { id; _ } -> (
        match Hashtbl.find_opt page.widgets id with
        | Some wb ->
            let is_focused =
              match Focus_ring.current page.focus_ring with
              | Some fid -> fid = id
              | None -> false
            in
            Widget_box.render wb ~focus:is_focused ~size:page.size
        | None -> "")
    | Layout_tree.Flex { direction; gap; children; padding; _ } ->
        let dir =
          match direction with
          | Layout_tree.Row -> Flex_layout.Row
          | Layout_tree.Column -> Flex_layout.Column
        in
        let flex_children =
          List.map
            (fun child ->
              {
                Flex_layout.render = (fun ~size:_ -> render_node child);
                basis = Flex_layout.Auto;
                cross = None;
              })
            children
        in
        let flex_padding =
          {
            Flex_layout.left = padding.left;
            right = padding.right;
            top = padding.top;
            bottom = padding.bottom;
          }
        in
        let layout =
          Flex_layout.create ~direction:dir
            ~gap:{ Flex_layout.h = gap; v = gap }
            ~padding:flex_padding flex_children
        in
        Flex_layout.render layout ~size:page.size
    | Layout_tree.Grid { rows; cols; row_gap; col_gap; children } ->
        let convert_track = function
          | Layout_tree.TPx n -> Grid_layout.Px n
          | Layout_tree.TFr f -> Grid_layout.Fr f
          | Layout_tree.TPercent f -> Grid_layout.Percent f
          | Layout_tree.TAuto -> Grid_layout.Auto
          | Layout_tree.TMinMax (a, b) -> Grid_layout.MinMax (a, b)
        in
        let grid_children =
          List.map
            (fun (p, child) ->
              Grid_layout.span ~row:p.Layout_tree.row ~col:p.col
                ~row_span:p.row_span ~col_span:p.col_span (fun ~size:_ ->
                  render_node child))
            children
        in
        let layout =
          Grid_layout.create
            ~rows:(List.map convert_track rows)
            ~cols:(List.map convert_track cols)
            ~row_gap ~col_gap grid_children
        in
        Grid_layout.render layout ~size:page.size
    | Layout_tree.Boxed { title; style; padding; child } ->
        let content = match child with Some c -> render_node c | None -> "" in
        let box_style =
          match style with
          | Layout_tree.None_ -> Box_widget.None_
          | Layout_tree.Single -> Box_widget.Single
          | Layout_tree.Double -> Box_widget.Double
          | Layout_tree.Rounded -> Box_widget.Rounded
          | Layout_tree.Ascii -> Box_widget.Ascii
          | Layout_tree.Heavy -> Box_widget.Heavy
        in
        Box_widget.render ?title ~style:box_style
          ~padding:
            {
              Box_widget.left = padding.left;
              right = padding.right;
              top = padding.top;
              bottom = padding.bottom;
            }
          ~width:page.size.cols content
    | Layout_tree.Card { title; footer; child; _ } ->
        let body = match child with Some c -> render_node c | None -> "" in
        let card = Card_widget.create ?title ?footer ~body () in
        Card_widget.render card ~cols:page.size.cols
  in
  render_node page.layout

(** Execute a single action on the page. Returns emitted events. *)
let rec execute_action page (action : Action.t) : emit_event list =
  match action with
  | Set_text { target; value } ->
      ignore
        (update_widget page ~id:target
           ~patch:(`Assoc [ ("text", `String value) ]));
      []
  | Set_checked { target; value } ->
      ignore
        (update_widget page ~id:target
           ~patch:(`Assoc [ ("checked", `Bool value) ]));
      []
  | Toggle { target } -> (
      match Hashtbl.find_opt page.widgets target with
      | Some wb ->
          let state = Widget_box.query wb in
          let current =
            match state with
            | `Assoc fields -> (
                match List.assoc_opt "checked" fields with
                | Some (`Bool b) -> b
                | _ -> (
                    match List.assoc_opt "on" fields with
                    | Some (`Bool b) -> b
                    | _ -> false))
            | _ -> false
          in
          let patch_key =
            match state with
            | `Assoc fields ->
                if List.mem_assoc "checked" fields then "checked" else "on"
            | _ -> "checked"
          in
          ignore
            (update_widget page ~id:target
               ~patch:(`Assoc [ (patch_key, `Bool (not current)) ]));
          []
      | None -> [])
  | Append_text { target; value } -> (
      match Hashtbl.find_opt page.widgets target with
      | Some wb ->
          let state = Widget_box.query wb in
          let current_text =
            match state with
            | `Assoc fields -> (
                match List.assoc_opt "text" fields with
                | Some (`String s) -> s
                | _ -> "")
            | _ -> ""
          in
          ignore
            (update_widget page ~id:target
               ~patch:(`Assoc [ ("text", `String (current_text ^ value)) ]));
          []
      | None -> [])
  | Focus { target } ->
      page.focus_ring <- Focus_ring.focus page.focus_ring target;
      []
  | Set_disabled { target; value } ->
      ignore
        (update_widget page ~id:target
           ~patch:(`Assoc [ ("disabled", `Bool value) ]));
      []
  | Set_visible { target = _; value = _ } ->
      (* Visibility not yet supported at widget level *)
      []
  | Set_items { target; items } ->
      ignore
        (update_widget page ~id:target
           ~patch:
             (`Assoc [ ("items", `List (List.map (fun s -> `String s) items)) ]));
      []
  | Emit { event } ->
      let snapshot = query_all_state page in
      [ { name = event; snapshot } ]
  | Push_modal _ ->
      (* Modal handling is done at the session/MCP level *)
      []
  | Close_modal _ -> []
  | Navigate _ -> []
  | Back -> []
  | Quit -> []
  | Set_state { key; value } ->
      set_state_value page ~key ~value;
      []
  | Copy_widget_to_state { key; source } ->
      (match Hashtbl.find_opt page.widgets source with
      | Some wb ->
          let wstate = Widget_box.query wb in
          let value =
            match wstate with
            | `Assoc fields -> (
                match List.assoc_opt "text" fields with
                | Some v -> v
                | None -> (
                    match List.assoc_opt "value" fields with
                    | Some v -> v
                    | None -> (
                        match List.assoc_opt "checked" fields with
                        | Some v -> v
                        | None -> `String "")))
            | _ -> `String ""
          in
          set_state_value page ~key ~value
      | None -> ());
      []
  | Inc_state { key; by } ->
      let current =
        match Hashtbl.find_opt page.state key with
        | Some (`Int n) -> float_of_int n
        | Some (`Float f) -> f
        | _ -> 0.0
      in
      let new_val = current +. by in
      let value =
        match
          List.find_opt (fun (sv : state_var) -> sv.key = key)
            page.state_schema
        with
        | Some sv when sv.typ = `Int -> `Int (int_of_float new_val)
        | _ -> `Float new_val
      in
      set_state_value page ~key ~value;
      []
  | Reset_state { key } ->
      (match
         List.find_opt (fun (sv : state_var) -> sv.key = key)
           page.state_schema
       with
      | Some sv -> set_state_value page ~key ~value:sv.default
      | None -> ());
      []

and query_all_state page =
  let widgets =
    Hashtbl.fold
      (fun id wb acc ->
        ( id,
          `Assoc
            [
              ("type", `String (Widget_box.type_name wb));
              ("state", Widget_box.query wb);
            ] )
        :: acc)
      page.widgets []
  in
  `Assoc widgets

(** Send a key to the focused widget, detect events, execute wirings. Returns
    (emitted_events). *)
let send_key page ~key =
  let emitted = ref [] in
  (* Handle Tab/Shift-Tab for focus cycling *)
  (match key with
  | "Tab" | "S-Tab" ->
      let ring', _result = Focus_ring.handle_key page.focus_ring ~key in
      page.focus_ring <- ring'
  | _ -> (
      match Focus_ring.current page.focus_ring with
      | None -> ()
      | Some focused_id -> (
          match Hashtbl.find_opt page.widgets focused_id with
          | None -> ()
          | Some wb ->
              let wb', _handled, events =
                Widget_box.on_key_with_events wb ~key
              in
              Hashtbl.replace page.widgets focused_id wb';
              (* Process events through wirings *)
              List.iter
                (fun (event_name, _event_data) ->
                  match
                    Wiring.find page.wirings ~source:focused_id
                      ~event:event_name
                  with
                  | Some action ->
                      let evts = execute_action page action in
                      emitted := !emitted @ evts
                  | None -> ())
                events)));
  !emitted

let query_focus page =
  let current = Focus_ring.current page.focus_ring in
  let index =
    match Focus_ring.current_index page.focus_ring with
    | Some i -> i
    | None -> -1
  in
  let total = Focus_ring.focusable_count page.focus_ring in
  (current, index, total)
