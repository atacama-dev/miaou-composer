(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** canvas_tool — stateful canvas companion for the miaou-composer JSON runner.

    Manages a list of canvas widgets with type-aware schemas.
    Reads/writes its state from a JSON file (default: canvas_tool_state.json).
    Outputs a JSON object to stdout with state updates for the runner:
      { "canvas_def": {...}, "canvas_selected": "...", "prop_label": "...", "prop_info": "..." }

    CLI:
      canvas_tool [--state <path>] sync
      canvas_tool [--state <path>] add    --type  <type>
      canvas_tool [--state <path>] remove --id    <id>
      canvas_tool [--state <path>] update --id    <id>  --key <prop> --value <val>
      canvas_tool [--state <path>] query  [--id   <id>]
      canvas_tool [--state <path>] clear
      canvas_tool [--state <path>] export [--output <file>]
*)

(* ---------------------------------------------------------------------------
   Widget schemas
   --------------------------------------------------------------------------- *)

type prop_type = PString | PBool | PInt | PStringList

type prop_schema = {
  pname : string;
  ptype : prop_type;
  pdefault : string;
  plabel : string;
}

type widget_schema = { type_name : string; props : prop_schema list }

let mk_str n lbl def =
  { pname = n; ptype = PString; pdefault = def; plabel = lbl }

let mk_bool n lbl def =
  {
    pname = n;
    ptype = PBool;
    pdefault = (if def then "true" else "false");
    plabel = lbl;
  }

let mk_int n lbl def =
  { pname = n; ptype = PInt; pdefault = string_of_int def; plabel = lbl }

let mk_list n lbl =
  { pname = n; ptype = PStringList; pdefault = ""; plabel = lbl }

let schemas : widget_schema list =
  [
    {
      type_name = "button";
      props =
        [ mk_str "label" "Label" "Button"; mk_bool "disabled" "Disabled" false ];
    };
    {
      type_name = "checkbox";
      props =
        [
          mk_str "label" "Label" "";
          mk_bool "checked" "Checked" false;
          mk_bool "disabled" "Disabled" false;
        ];
    };
    {
      type_name = "textbox";
      props =
        [
          mk_str "title" "Title" "";
          mk_int "width" "Width" 30;
          mk_str "initial" "Initial" "";
          mk_str "placeholder" "Placeholder" "";
          mk_bool "mask" "Mask" false;
        ];
    };
    {
      type_name = "textarea";
      props =
        [
          mk_str "title" "Title" "";
          mk_int "width" "Width" 40;
          mk_int "height" "Height" 5;
          mk_str "initial" "Initial" "";
          mk_str "placeholder" "Placeholder" "";
        ];
    };
    {
      type_name = "select";
      props =
        [
          mk_str "title" "Title" "";
          mk_list "items" "Items";
          mk_int "max_visible" "Max visible" 10;
        ];
    };
    {
      type_name = "radio";
      props =
        [
          mk_str "label" "Label" "";
          mk_bool "selected" "Selected" false;
          mk_bool "disabled" "Disabled" false;
        ];
    };
    {
      type_name = "switch";
      props =
        [
          mk_str "label" "Label" "";
          mk_bool "on" "On" false;
          mk_bool "disabled" "Disabled" false;
        ];
    };
    {
      type_name = "pager";
      props =
        [
          mk_str "title" "Title" "";
          mk_str "text" "Text" "";
          mk_bool "focusable" "Focusable" true;
        ];
    };
    {
      type_name = "list";
      props =
        [
          mk_list "items" "Items";
          mk_int "indent" "Indent" 2;
          mk_bool "expand_all" "Expand all" false;
        ];
    };
    {
      type_name = "description_list";
      props = [ mk_str "title" "Title" ""; mk_list "items" "Items" ];
    };
  ]

let find_schema type_name =
  List.find_opt (fun s -> s.type_name = type_name) schemas

(* ---------------------------------------------------------------------------
   State model
   --------------------------------------------------------------------------- *)

type widget_instance = {
  wi_id : string;
  wi_type : string;
  wi_props : (string * string) list;
}

type canvas_state = {
  mutable widgets : widget_instance list;
  mutable counters : (string * int) list;
}

let empty_state () = { widgets = []; counters = [] }

(* ---------------------------------------------------------------------------
   State serialization (internal format: canvas_tool_state.json)
   --------------------------------------------------------------------------- *)

let state_to_json state : Yojson.Safe.t =
  `Assoc
    [
      ( "widgets",
        `List
          (List.map
             (fun w ->
               `Assoc
                 [
                   ("id", `String w.wi_id);
                   ("type", `String w.wi_type);
                   ( "props",
                     `Assoc (List.map (fun (k, v) -> (k, `String v)) w.wi_props)
                   );
                 ])
             state.widgets) );
      ("counters", `Assoc (List.map (fun (t, n) -> (t, `Int n)) state.counters));
    ]

let get_str fields key =
  match List.assoc_opt key fields with Some (`String s) -> s | _ -> ""

let state_of_json json =
  match json with
  | `Assoc fields ->
      let widgets =
        match List.assoc_opt "widgets" fields with
        | Some (`List ws) ->
            List.filter_map
              (fun w ->
                match w with
                | `Assoc wf ->
                    let id = get_str wf "id" in
                    let wtype = get_str wf "type" in
                    let props =
                      match List.assoc_opt "props" wf with
                      | Some (`Assoc ps) ->
                          List.filter_map
                            (fun (k, v) ->
                              match v with
                              | `String s -> Some (k, s)
                              | _ -> None)
                            ps
                      | _ -> []
                    in
                    if id <> "" && wtype <> "" then
                      Some { wi_id = id; wi_type = wtype; wi_props = props }
                    else None
                | _ -> None)
              ws
        | _ -> []
      in
      let counters =
        match List.assoc_opt "counters" fields with
        | Some (`Assoc cs) ->
            List.filter_map
              (fun (k, v) -> match v with `Int n -> Some (k, n) | _ -> None)
              cs
        | _ -> []
      in
      { widgets; counters }
  | _ -> empty_state ()

(* ---------------------------------------------------------------------------
   State I/O
   --------------------------------------------------------------------------- *)

let load_state path =
  if not (Sys.file_exists path) then empty_state ()
  else
    try
      let json = Yojson.Safe.from_file path in
      state_of_json json
    with _ -> empty_state ()

let save_state path state =
  let json = state_to_json state in
  let content = Yojson.Safe.pretty_to_string json ^ "\n" in
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc

(* ---------------------------------------------------------------------------
   Build canvas_def JSON for the runner
   --------------------------------------------------------------------------- *)

let prop_to_json ps v_str : Yojson.Safe.t =
  match ps.ptype with
  | PString -> `String v_str
  | PBool -> `Bool (v_str = "true")
  | PInt -> (
      try `Int (int_of_string v_str)
      with _ -> ( try `Int (int_of_string ps.pdefault) with _ -> `Int 0))
  | PStringList ->
      let items =
        if v_str = "" then []
        else
          String.split_on_char ',' v_str
          |> List.map String.trim
          |> List.filter (fun s -> s <> "")
      in
      `List (List.map (fun s -> `String s) items)

let widget_to_canvas_json w =
  match find_schema w.wi_type with
  | None -> `Assoc [ ("type", `String w.wi_type); ("id", `String w.wi_id) ]
  | Some schema ->
      let fields =
        [ ("type", `String w.wi_type); ("id", `String w.wi_id) ]
        @ List.map
            (fun ps ->
              let v =
                Option.value ~default:ps.pdefault
                  (List.assoc_opt ps.pname w.wi_props)
              in
              (ps.pname, prop_to_json ps v))
            schema.props
      in
      `Assoc fields

let canvas_def_json state : Yojson.Safe.t =
  let children = List.map widget_to_canvas_json state.widgets in
  `Assoc
    [
      ("id", `String "canvas");
      ( "layout",
        `Assoc
          [
            ("type", `String "flex");
            ("direction", `String "column");
            ("gap", `Int 1);
            ("children", `List children);
          ] );
      ("size", `Assoc [ ("rows", `Int 20); ("cols", `Int 60) ]);
    ]

(* ---------------------------------------------------------------------------
   Operations
   --------------------------------------------------------------------------- *)

let next_id state wtype =
  let n = Option.value ~default:0 (List.assoc_opt wtype state.counters) in
  let id = Printf.sprintf "%s_%d" wtype n in
  let counters =
    if List.mem_assoc wtype state.counters then
      List.map
        (fun (t, c) -> if t = wtype then (t, n + 1) else (t, c))
        state.counters
    else state.counters @ [ (wtype, 1) ]
  in
  (id, { state with counters })

let add_widget state wtype =
  match find_schema wtype with
  | None -> Error (Printf.sprintf "Unknown widget type: %s" wtype)
  | Some schema ->
      let id, state = next_id state wtype in
      let props =
        List.filter_map
          (fun ps ->
            if ps.pdefault <> "" then Some (ps.pname, ps.pdefault) else None)
          schema.props
      in
      let w = { wi_id = id; wi_type = wtype; wi_props = props } in
      Ok (id, { state with widgets = state.widgets @ [ w ] })

let remove_widget state widget_id =
  {
    state with
    widgets = List.filter (fun w -> w.wi_id <> widget_id) state.widgets;
  }

let update_widget_prop state widget_id prop_key prop_val =
  {
    state with
    widgets =
      List.map
        (fun w ->
          if w.wi_id <> widget_id then w
          else
            let props =
              if List.mem_assoc prop_key w.wi_props then
                List.map
                  (fun (k, v) -> if k = prop_key then (k, prop_val) else (k, v))
                  w.wi_props
              else w.wi_props @ [ (prop_key, prop_val) ]
            in
            { w with wi_props = props })
        state.widgets;
  }

let find_widget state widget_id =
  List.find_opt (fun w -> w.wi_id = widget_id) state.widgets

(* ---------------------------------------------------------------------------
   Output formatting
   --------------------------------------------------------------------------- *)

let prop_info_text w =
  match find_schema w.wi_type with
  | None -> Printf.sprintf "id:   %s\ntype: %s" w.wi_id w.wi_type
  | Some schema ->
      let header = Printf.sprintf "id:   %s\ntype: %s" w.wi_id w.wi_type in
      let sep = "──────────────────" in
      let prop_lines =
        List.filter_map
          (fun ps ->
            if ps.ptype = PStringList then None
            else
              let v =
                Option.value ~default:ps.pdefault
                  (List.assoc_opt ps.pname w.wi_props)
              in
              Some (Printf.sprintf "%-12s %s" (ps.plabel ^ ":") v))
          schema.props
      in
      String.concat "\n" ([ header; sep ] @ prop_lines)

let prop_slot_count = 5

let prop_empty_slots () =
  List.init prop_slot_count (fun i ->
      [
        (Printf.sprintf "prop_%d_key" i, `String "");
        (Printf.sprintf "prop_%d_val" i, `String "");
      ])
  |> List.concat

let prop_slot_fields w =
  match find_schema w.wi_type with
  | None -> prop_empty_slots ()
  | Some schema ->
      let editable =
        List.filter (fun ps -> ps.ptype <> PStringList) schema.props
      in
      List.init prop_slot_count (fun i ->
          match List.nth_opt editable i with
          | None ->
              [
                (Printf.sprintf "prop_%d_key" i, `String "");
                (Printf.sprintf "prop_%d_val" i, `String "");
              ]
          | Some ps ->
              let v =
                Option.value ~default:ps.pdefault
                  (List.assoc_opt ps.pname w.wi_props)
              in
              [
                (Printf.sprintf "prop_%d_key" i, `String ps.pname);
                (Printf.sprintf "prop_%d_val" i, `String v);
              ])
      |> List.concat

let output_response state selected_id =
  let canvas_def = canvas_def_json state in
  let prop_info, canvas_selected, slots =
    match selected_id with
    | "" -> ("Select a canvas\nwidget to edit", "", prop_empty_slots ())
    | id -> (
        match find_widget state id with
        | None -> ("(widget not found)", id, prop_empty_slots ())
        | Some w -> (prop_info_text w, id, prop_slot_fields w))
  in
  let result =
    `Assoc
      ([
         ("canvas_def", canvas_def);
         ("canvas_selected", `String canvas_selected);
         ("prop_info", `String prop_info);
       ]
      @ slots)
  in
  print_string (Yojson.Safe.to_string result);
  print_newline ()

(* ---------------------------------------------------------------------------
   CLI argument helpers
   --------------------------------------------------------------------------- *)

let get_flag args flag =
  let rec loop = function
    | [] -> None
    | f :: v :: _ when f = flag -> Some v
    | _ :: rest -> loop rest
  in
  loop args

let has_word args word = List.mem word args

(* ---------------------------------------------------------------------------
   Main
   --------------------------------------------------------------------------- *)

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  (* Strip --state <path> first *)
  let state_file = ref "canvas_tool_state.json" in
  let args =
    let rec strip acc = function
      | "--state" :: path :: rest ->
          state_file := path;
          strip acc rest
      | x :: rest -> strip (acc @ [ x ]) rest
      | [] -> acc
    in
    strip [] args
  in
  let state = load_state !state_file in
  (* Dispatch on first word that isn't a flag *)
  let cmd = List.find_opt (fun s -> s.[0] <> '-') args in
  match cmd with
  | None | Some "sync" -> output_response state ""
  | Some "clear" ->
      let new_state = { state with widgets = [] } in
      save_state !state_file new_state;
      output_response new_state ""
  | Some "add" -> (
      let wtype = Option.value ~default:"" (get_flag args "--type") in
      if wtype = "" then
        (* No type selected — output current state unchanged *)
        output_response state ""
      else
        match add_widget state wtype with
        | Error msg ->
            Printf.eprintf "canvas_tool: %s\n" msg;
            exit 1
        | Ok (new_id, new_state) ->
            save_state !state_file new_state;
            output_response new_state new_id)
  | Some "remove" ->
      let id = Option.value ~default:"" (get_flag args "--id") in
      if id = "" then begin
        Printf.eprintf "canvas_tool remove: missing --id\n";
        exit 1
      end
      else begin
        let new_state = remove_widget state id in
        save_state !state_file new_state;
        output_response new_state ""
      end
  | Some "update" ->
      let id = Option.value ~default:"" (get_flag args "--id") in
      let key = Option.value ~default:"" (get_flag args "--key") in
      let value = Option.value ~default:"" (get_flag args "--value") in
      if id = "" || key = "" then begin
        Printf.eprintf "canvas_tool update: missing --id or --key\n";
        exit 1
      end
      else begin
        let new_state = update_widget_prop state id key value in
        save_state !state_file new_state;
        output_response new_state id
      end
  | Some "query" ->
      let id =
        match get_flag args "--id" with
        | Some id -> id
        | None -> ( match state.widgets with w :: _ -> w.wi_id | [] -> "")
      in
      output_response state id
  | Some "export" ->
      let output_file =
        match get_flag args "--output" with
        | Some f -> f
        | None -> "canvas_export.json"
      in
      let canvas_def = canvas_def_json state in
      let content = Yojson.Safe.pretty_to_string canvas_def ^ "\n" in
      (try
         let oc = open_out_bin output_file in
         output_string oc content;
         close_out oc
       with e ->
         Printf.eprintf "canvas_tool export: %s\n" (Printexc.to_string e));
      (* Still output the response so the runner can sync display *)
      let selected = match state.widgets with w :: _ -> w.wi_id | [] -> "" in
      output_response state
        (if has_word args "--no-select" then "" else selected)
  | Some other ->
      Printf.eprintf "canvas_tool: unknown command '%s'\n" other;
      exit 1
