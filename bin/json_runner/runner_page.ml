(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** JSON-driven page runner.

    Loads a composer page definition from a JSON file (argv[1] or
    "pages/composer.json"). All app logic (canvas tools, git tools, etc.) is
    declared in the JSON page definition; the runner is a pure interpreter.

    Emitted events:
    - "$quit" → quit the application
    - "$back" → navigate back
    - "$navigate" → navigate to a named page
    - "$tool_call" → invoke a named tool (builtin or process/shell) *)

open Miaou_composer_lib
open Miaou_composer_bridge
module Direct = Miaou_core.Direct_page
module Sys_cap = Miaou_interfaces.System

(* ---------------------------------------------------------------------------
   Canvas sub-flex path — internal detail of the canvas builtins.
   Layout:  flex-row [0=left-panel, 1=canvas-box, 2=info-box]
              canvas-box is Boxed; path [1;0] navigates into its child flex-col.
   --------------------------------------------------------------------------- *)

let canvas_path = [ 1; 0 ]

(* ---------------------------------------------------------------------------
   Runner state
   --------------------------------------------------------------------------- *)

type state = {
  composer : Page.t;
  mutable canvas_page : Page.t option;
      (* decoded cache of canvas_def; None = needs rebuild *)
}

(* ---------------------------------------------------------------------------
   Helpers
   --------------------------------------------------------------------------- *)

let composer_file () =
  if Array.length Sys.argv > 1 then Sys.argv.(1)
  else
    match Sys.getenv_opt "COMPOSER_FILE" with
    | Some f -> f
    | None -> "pages/composer.json"

let load_page path =
  let json = Yojson.Safe.from_file path in
  match Page_codec.page_of_json json with
  | Ok p -> p
  | Error e -> failwith ("Failed to load page '" ^ path ^ "': " ^ e)

(* ---------------------------------------------------------------------------
   Arg interpolation: replace $state.KEY and $args.KEY in strings.
   --------------------------------------------------------------------------- *)

let interpolate (state_tbl : (string, Yojson.Safe.t) Hashtbl.t)
    (call_args : (string * string) list) s =
  (* Inline substitution of $state.KEY and $args.KEY anywhere in string. *)
  let len = String.length s in
  let buf = Buffer.create len in
  let i = ref 0 in
  while !i < len do
    if s.[!i] = '$' then begin
      let matched = ref false in
      let try_prefix prefix lookup =
        let plen = String.length prefix in
        if (not !matched) && !i + plen <= len && String.sub s !i plen = prefix
        then begin
          let j = ref (!i + plen) in
          while
            !j < len
            &&
            let c = s.[!j] in
            c = '_'
            || (c >= 'a' && c <= 'z')
            || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9')
          do
            incr j
          done;
          let key = String.sub s (!i + plen) (!j - !i - plen) in
          if key <> "" then begin
            Buffer.add_string buf (lookup key);
            i := !j;
            matched := true
          end
        end
      in
      try_prefix "$state." (fun key ->
          match Hashtbl.find_opt state_tbl key with
          | Some (`String v) -> v
          | Some (`Int n) -> string_of_int n
          | Some (`Float f) -> string_of_float f
          | Some (`Bool b) -> string_of_bool b
          | _ -> "");
      try_prefix "$args." (fun key ->
          match List.assoc_opt key call_args with Some v -> v | None -> "");
      if not !matched then begin
        Buffer.add_char buf s.[!i];
        incr i
      end
    end
    else begin
      Buffer.add_char buf s.[!i];
      incr i
    end
  done;
  Buffer.contents buf

(* ---------------------------------------------------------------------------
   Canvas state management
   --------------------------------------------------------------------------- *)

let empty_canvas_def () : Yojson.Safe.t =
  `Assoc
    [
      ("id", `String "canvas");
      ( "layout",
        `Assoc
          [
            ("type", `String "flex");
            ("direction", `String "column");
            ("gap", `Int 1);
            ("children", `List []);
          ] );
      ("size", `Assoc [ ("rows", `Int 20); ("cols", `Int 60) ]);
    ]

let get_canvas_def s =
  match Hashtbl.find_opt s.composer.Page.state "canvas_def" with
  | Some (`Assoc _ as json) -> json
  | _ -> empty_canvas_def ()

let rebuild_canvas s =
  let json = get_canvas_def s in
  match Page_codec.page_of_json json with
  | Ok p -> s.canvas_page <- Some p
  | Error _ -> s.canvas_page <- None

(** Count children in canvas_def layout. *)
let canvas_def_child_count canvas_def =
  match canvas_def with
  | `Assoc fields -> (
      match List.assoc_opt "layout" fields with
      | Some (`Assoc lf) -> (
          match List.assoc_opt "children" lf with
          | Some (`List ch) -> List.length ch
          | _ -> 0)
      | _ -> 0)
  | _ -> 0

(** Append a widget JSON to canvas_def layout children. Returns updated json. *)
let append_widget_to_canvas_json canvas_def wtype =
  let count = canvas_def_child_count canvas_def in
  let wid = Printf.sprintf "%s_%d" wtype count in
  let widget_json = `Assoc [ ("type", `String wtype); ("id", `String wid) ] in
  match canvas_def with
  | `Assoc fields -> (
      match List.assoc_opt "layout" fields with
      | Some (`Assoc lf) ->
          let old_children =
            match List.assoc_opt "children" lf with
            | Some (`List ch) -> ch
            | _ -> []
          in
          let new_children = old_children @ [ widget_json ] in
          let new_layout =
            `Assoc
              (List.map
                 (fun (k, v) ->
                   if k = "children" then (k, `List new_children) else (k, v))
                 lf)
          in
          `Assoc
            (List.map
               (fun (k, v) -> if k = "layout" then (k, new_layout) else (k, v))
               fields)
      | _ -> canvas_def)
  | _ -> canvas_def

(** Find a widget spec by id in canvas_def layout children. *)
let find_widget_in_canvas_json canvas_def widget_id =
  match canvas_def with
  | `Assoc fields -> (
      match List.assoc_opt "layout" fields with
      | Some (`Assoc lf) -> (
          match List.assoc_opt "children" lf with
          | Some (`List ch) ->
              List.find_opt
                (fun child ->
                  match child with
                  | `Assoc cf -> (
                      match List.assoc_opt "id" cf with
                      | Some (`String id) -> id = widget_id
                      | _ -> false)
                  | _ -> false)
                ch
          | _ -> None)
      | _ -> None)
  | _ -> None

(** Patch a single property in a widget spec inside canvas_def. *)
let update_widget_prop_in_canvas_json canvas_def widget_id prop_key prop_val =
  match canvas_def with
  | `Assoc fields -> (
      match List.assoc_opt "layout" fields with
      | Some (`Assoc lf) -> (
          match List.assoc_opt "children" lf with
          | Some (`List ch) ->
              let new_children =
                List.map
                  (fun child ->
                    match child with
                    | `Assoc cf -> (
                        match List.assoc_opt "id" cf with
                        | Some (`String id) when id = widget_id ->
                            let updated =
                              if List.exists (fun (k, _) -> k = prop_key) cf
                              then
                                List.map
                                  (fun (k, v) ->
                                    if k = prop_key then (k, `String prop_val)
                                    else (k, v))
                                  cf
                              else cf @ [ (prop_key, `String prop_val) ]
                            in
                            `Assoc updated
                        | _ -> child)
                    | _ -> child)
                  ch
              in
              let new_layout =
                `Assoc
                  (List.map
                     (fun (k, v) ->
                       if k = "children" then (k, `List new_children) else (k, v))
                     lf)
              in
              `Assoc
                (List.map
                   (fun (k, v) ->
                     if k = "layout" then (k, new_layout) else (k, v))
                   fields)
          | _ -> canvas_def)
      | _ -> canvas_def)
  | _ -> canvas_def

(** Remove a widget by id from canvas_def layout children. *)
let remove_widget_from_canvas_json canvas_def widget_id =
  match canvas_def with
  | `Assoc fields -> (
      match List.assoc_opt "layout" fields with
      | Some (`Assoc lf) ->
          let old_children =
            match List.assoc_opt "children" lf with
            | Some (`List ch) -> ch
            | _ -> []
          in
          let new_children =
            List.filter
              (fun child ->
                match child with
                | `Assoc cf -> (
                    match List.assoc_opt "id" cf with
                    | Some (`String id) -> id <> widget_id
                    | _ -> true)
                | _ -> true)
              old_children
          in
          let new_layout =
            `Assoc
              (List.map
                 (fun (k, v) ->
                   if k = "children" then (k, `List new_children) else (k, v))
                 lf)
          in
          `Assoc
            (List.map
               (fun (k, v) -> if k = "layout" then (k, new_layout) else (k, v))
               fields)
      | _ -> canvas_def)
  | _ -> canvas_def

(** Collect direct leaf IDs at the given path in the layout tree. *)
let canvas_leaf_ids layout path =
  let rec nav node p =
    match (node, p) with
    | Layout_tree.Flex { children; _ }, [] ->
        List.filter_map
          (function Layout_tree.Leaf { id; _ } -> Some id | _ -> None)
          children
    | Layout_tree.Flex { children; _ }, i :: rest -> (
        match List.nth_opt children i with Some c -> nav c rest | None -> [])
    | Layout_tree.Boxed { child = Some c; _ }, 0 :: rest -> nav c rest
    | Layout_tree.Card { child = Some c; _ }, 0 :: rest -> nav c rest
    | _ -> []
  in
  nav layout path

(** Sync the visual canvas (sub-flex in composer layout) from canvas_def. *)
let sync_visual_canvas s =
  (* Remove all current children from the canvas sub-flex *)
  let ids_to_remove = canvas_leaf_ids s.composer.Page.layout canvas_path in
  List.iter (fun id -> ignore (Page.remove_widget s.composer ~id)) ids_to_remove;
  (* Add widgets from canvas_def *)
  let canvas_def = get_canvas_def s in
  let children =
    match canvas_def with
    | `Assoc fields -> (
        match List.assoc_opt "layout" fields with
        | Some (`Assoc lf) -> (
            match List.assoc_opt "children" lf with
            | Some (`List ch) -> ch
            | _ -> [])
        | _ -> [])
    | _ -> []
  in
  List.iteri
    (fun i child_json ->
      match Widget_factory.create_widget child_json with
      | Ok (id, wb) ->
          ignore
            (Page.add_widget s.composer ~id ~widget_box:wb ~path:canvas_path
               ~position:i)
      | Error _ -> ())
    children

(* ---------------------------------------------------------------------------
   Builtin tool registry
   --------------------------------------------------------------------------- *)

let builtin_handlers :
    (string, state -> (string * string) list -> unit) Hashtbl.t =
  Hashtbl.create 8

let () =
  (* canvas_add { widget_type } *)
  Hashtbl.add builtin_handlers "canvas_add" (fun s call_args ->
      let wtype =
        match List.assoc_opt "widget_type" call_args with
        | Some t when t <> "" -> t
        | _ -> (
            (* fall back to selected_type state *)
            let from_state =
              match Hashtbl.find_opt s.composer.Page.state "selected_type" with
              | Some (`String t) -> t
              | _ -> ""
            in
            if from_state <> "" then from_state
            else
              (* last resort: query palette widget directly *)
              match Hashtbl.find_opt s.composer.Page.widgets "palette" with
              | Some wb -> (
                  match Widget_box.query wb with
                  | `Assoc fields -> (
                      match List.assoc_opt "selected" fields with
                      | Some (`String t) when t <> "" -> t
                      | _ -> "")
                  | _ -> "")
              | None -> "")
      in
      if wtype <> "" then begin
        let old_def = get_canvas_def s in
        let new_def = append_widget_to_canvas_json old_def wtype in
        Page.set_state_value s.composer ~key:"canvas_def" ~value:new_def;
        rebuild_canvas s;
        sync_visual_canvas s
      end);
  (* canvas_remove { id } *)
  Hashtbl.add builtin_handlers "canvas_remove" (fun s call_args ->
      let widget_id =
        match List.assoc_opt "id" call_args with Some v -> v | None -> ""
      in
      if widget_id <> "" then begin
        let old_def = get_canvas_def s in
        let new_def = remove_widget_from_canvas_json old_def widget_id in
        Page.set_state_value s.composer ~key:"canvas_def" ~value:new_def;
        rebuild_canvas s;
        sync_visual_canvas s
      end);
  (* canvas_clear *)
  Hashtbl.add builtin_handlers "canvas_clear" (fun s _call_args ->
      Page.set_state_value s.composer ~key:"canvas_def"
        ~value:(empty_canvas_def ());
      s.canvas_page <- None;
      sync_visual_canvas s);
  (* canvas_export { path? } *)
  Hashtbl.add builtin_handlers "canvas_export" (fun s call_args ->
      let path =
        match List.assoc_opt "path" call_args with
        | Some p when p <> "" -> p
        | _ -> s.composer.Page.id ^ "_canvas_export.json"
      in
      let canvas_def = get_canvas_def s in
      let json_str = Yojson.Safe.pretty_to_string canvas_def ^ "\n" in
      match Sys_cap.get () with
      | Some sys -> ignore (sys.write_file path json_str)
      | None -> ());
  (* canvas_select { id } *)
  Hashtbl.add builtin_handlers "canvas_select" (fun s call_args ->
      let widget_id =
        match List.assoc_opt "id" call_args with Some v -> v | None -> ""
      in
      Page.set_state_value s.composer ~key:"canvas_selected"
        ~value:(`String widget_id));
  (* canvas_query_widget { id? } — reads widget spec and populates prop_* state *)
  Hashtbl.add builtin_handlers "canvas_query_widget" (fun s call_args ->
      let widget_id =
        match List.assoc_opt "id" call_args with
        | Some v when v <> "" -> v
        | _ -> (
            match Hashtbl.find_opt s.composer.Page.state "canvas_selected" with
            | Some (`String id) when id <> "" -> id
            | _ -> "")
      in
      if widget_id <> "" then begin
        let canvas_def = get_canvas_def s in
        match find_widget_in_canvas_json canvas_def widget_id with
        | Some (`Assoc cf) ->
            let get_str keys =
              List.find_map
                (fun k ->
                  match List.assoc_opt k cf with
                  | Some (`String v) -> Some v
                  | _ -> None)
                keys
              |> Option.value ~default:""
            in
            let wtype = get_str [ "type" ] in
            let label = get_str [ "label"; "text"; "title" ] in
            Page.set_state_value s.composer ~key:"prop_label"
              ~value:(`String label);
            Page.set_state_value s.composer ~key:"prop_info"
              ~value:
                (`String (Printf.sprintf "id:   %s\ntype: %s" widget_id wtype))
        | _ ->
            Page.set_state_value s.composer ~key:"prop_label"
              ~value:(`String "");
            Page.set_state_value s.composer ~key:"prop_info"
              ~value:(`String "(widget not found)")
      end
      else begin
        Page.set_state_value s.composer ~key:"prop_label" ~value:(`String "");
        Page.set_state_value s.composer ~key:"prop_info"
          ~value:(`String "Select a canvas\nwidget to edit")
      end);
  (* canvas_update { id, key, value } — patches canvas_def and syncs visual *)
  Hashtbl.add builtin_handlers "canvas_update" (fun s call_args ->
      let widget_id =
        match List.assoc_opt "id" call_args with Some v -> v | None -> ""
      in
      let prop_key =
        match List.assoc_opt "key" call_args with Some v -> v | None -> ""
      in
      let prop_val =
        match List.assoc_opt "value" call_args with Some v -> v | None -> ""
      in
      if widget_id <> "" && prop_key <> "" then begin
        let old_def = get_canvas_def s in
        let new_def =
          update_widget_prop_in_canvas_json old_def widget_id prop_key prop_val
        in
        Page.set_state_value s.composer ~key:"canvas_def" ~value:new_def;
        rebuild_canvas s;
        sync_visual_canvas s
      end)

(* ---------------------------------------------------------------------------
   JSON fields capture: parse stdout as JSON object, update state keys,
   auto-rebuild canvas if canvas_def changed.
   --------------------------------------------------------------------------- *)

let apply_json_fields s stdout_str =
  match try Some (Yojson.Safe.from_string stdout_str) with _ -> None with
  | Some (`Assoc output_fields) ->
      let canvas_changed = ref false in
      List.iter
        (fun (key, value) ->
          if key = "canvas_def" then begin
            let old_val = Hashtbl.find_opt s.composer.Page.state "canvas_def" in
            Page.set_state_value s.composer ~key ~value;
            let new_val = Hashtbl.find_opt s.composer.Page.state "canvas_def" in
            if old_val <> new_val then canvas_changed := true
          end
          else Page.set_state_value s.composer ~key ~value)
        output_fields;
      if !canvas_changed then begin
        rebuild_canvas s;
        sync_visual_canvas s
      end
  | _ -> ()

(* ---------------------------------------------------------------------------
   Tool executor
   --------------------------------------------------------------------------- *)

let rec execute_tool s tool_name (call_args : (string * string) list) =
  let page = s.composer in
  (* Find tool in page.tools *)
  let tool_opt =
    List.find_opt (fun t -> Tool_def.name t = tool_name) page.Page.tools
  in
  match tool_opt with
  | None -> (
      (* Check builtin registry *)
      match Hashtbl.find_opt builtin_handlers tool_name with
      | Some handler -> handler s call_args
      | None -> () (* unknown tool: silently ignore *))
  | Some (Tool_def.Builtin _) -> (
      match Hashtbl.find_opt builtin_handlers tool_name with
      | Some handler -> handler s call_args
      | None -> ())
  | Some
      (Tool_def.Process
         {
           bin;
           argv;
           cwd;
           capture_stdout;
           capture_stdout_lines;
           capture_json_fields;
           on_exit;
           _;
         }) -> (
      let interp = interpolate page.Page.state call_args in
      let resolved_argv = List.map interp (bin :: argv) in
      let resolved_cwd = Option.map interp cwd in
      match Sys_cap.get () with
      | None -> ()
      | Some sys -> (
          match sys.run_command ~argv:resolved_argv ~cwd:resolved_cwd with
          | Error _ -> ()
          | Ok result -> (
              (match capture_stdout with
              | Some key ->
                  Page.set_state_value page ~key ~value:(`String result.stdout)
              | None -> ());
              (match capture_stdout_lines with
              | Some key ->
                  let lines =
                    String.split_on_char '\n' (String.trim result.stdout)
                    |> List.filter (fun s -> s <> "")
                    |> List.map (fun s -> `String s)
                  in
                  Page.set_state_value page ~key ~value:(`List lines)
              | None -> ());
              if capture_json_fields then apply_json_fields s result.stdout;
              match on_exit with
              | Some action ->
                  let events = Page.execute_action page action in
                  handle_events_list s events
              | None -> ())))
  | Some
      (Tool_def.Shell
         {
           cmd;
           cwd;
           capture_stdout;
           capture_stdout_lines;
           capture_json_fields;
           on_exit;
           _;
         }) -> (
      let interp = interpolate page.Page.state call_args in
      let resolved_cmd = interp cmd in
      let resolved_cwd = Option.map interp cwd in
      match Sys_cap.get () with
      | None -> ()
      | Some sys -> (
          match
            sys.run_command ~argv:[ "sh"; "-c"; resolved_cmd ] ~cwd:resolved_cwd
          with
          | Error _ -> ()
          | Ok result -> (
              (match capture_stdout with
              | Some key ->
                  Page.set_state_value page ~key ~value:(`String result.stdout)
              | None -> ());
              (match capture_stdout_lines with
              | Some key ->
                  let lines =
                    String.split_on_char '\n' (String.trim result.stdout)
                    |> List.filter (fun s -> s <> "")
                    |> List.map (fun s -> `String s)
                  in
                  Page.set_state_value page ~key ~value:(`List lines)
              | None -> ());
              if capture_json_fields then apply_json_fields s result.stdout;
              match on_exit with
              | Some action ->
                  let events = Page.execute_action page action in
                  handle_events_list s events
              | None -> ())))

and handle_events_list s events =
  List.iter
    (fun (ev : Page.emit_event) ->
      match ev.name with
      | "$quit" -> Direct.quit ()
      | "$back" -> Direct.go_back ()
      | "$navigate" -> (
          match ev.snapshot with `String tgt -> Direct.navigate tgt | _ -> ())
      | "$tool_call" -> (
          match ev.snapshot with
          | `Assoc fields ->
              let tool_name =
                match List.assoc_opt "tool_name" fields with
                | Some (`String n) -> n
                | _ -> ""
              in
              let call_args =
                match List.assoc_opt "args" fields with
                | Some (`Assoc pairs) ->
                    List.filter_map
                      (fun (k, v) ->
                        match v with `String s -> Some (k, s) | _ -> None)
                      pairs
                | _ -> []
              in
              if tool_name <> "" then execute_tool s tool_name call_args
          | _ -> ())
      | _ -> ())
    events

(* ---------------------------------------------------------------------------
   Direct_page.REQUIRED implementation
   --------------------------------------------------------------------------- *)

let init () =
  let composer = load_page (composer_file ()) in
  let s = { composer; canvas_page = None } in
  (* Ensure canvas_def state var is initialized *)
  if not (Hashtbl.mem composer.Page.state "canvas_def") then
    Hashtbl.replace composer.Page.state "canvas_def" (empty_canvas_def ());
  rebuild_canvas s;
  (* Sync visual canvas from persisted/loaded canvas_def *)
  sync_visual_canvas s;
  (* Run init_actions *)
  let init_events =
    List.concat_map
      (fun a -> Page.execute_action composer a)
      composer.Page.init_actions
  in
  handle_events_list s init_events;
  s

let render_status_bar s cols =
  let page_id = s.composer.Page.id in
  let focused =
    match Miaou_internals.Focus_ring.current s.composer.Page.focus_ring with
    | Some id -> id
    | None -> "-"
  in
  let bar = Printf.sprintf " [%s] focus: %s | [q] quit" page_id focused in
  let padded =
    let len = String.length bar in
    if len >= cols then String.sub bar 0 cols
    else bar ^ String.make (cols - len) ' '
  in
  "\027[7m" ^ padded ^ "\027[0m"

let view s ~focus:_ ~size =
  s.composer.Page.size <-
    { LTerm_geom.rows = size.LTerm_geom.rows - 1; cols = size.LTerm_geom.cols };
  let rendered = Page.render s.composer in
  rendered ^ "\n" ^ render_status_bar s size.LTerm_geom.cols

let on_key s key ~size:_ =
  let prev_focus =
    Miaou_internals.Focus_ring.current s.composer.Page.focus_ring
  in
  let events = Page.send_key s.composer ~key in
  handle_events_list s events;
  (* Auto-select canvas widget when focus moves to one *)
  let new_focus =
    Miaou_internals.Focus_ring.current s.composer.Page.focus_ring
  in
  if new_focus <> prev_focus then begin
    match new_focus with
    | Some id
      when List.mem id (canvas_leaf_ids s.composer.Page.layout canvas_path) ->
        Page.set_state_value s.composer ~key:"canvas_selected"
          ~value:(`String id);
        execute_tool s "canvas_query_widget" [ ("id", id) ]
    | Some _ ->
        (* Moved focus away from canvas — clear if desired *)
        ()
    | None -> ()
  end;
  s
