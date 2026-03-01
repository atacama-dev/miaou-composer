(** JSON-driven page runner.

    Loads a composer page definition from a JSON file (argv[1] or
    "pages/composer.json"). The canvas area is a live sub-flex layout inside the
    compositor page — widgets are added directly into it, not rendered to a string.

    Emitted events:
    - "$quit"       → quit the application
    - "$back"       → navigate back
    - "$navigate"   → navigate to a named page
    - "add_widget"  → add the selected palette type into the canvas flex container
*)

open Miaou_composer_lib
open Miaou_composer_bridge
module Direct = Miaou_core.Direct_page

(* ---------------------------------------------------------------------------
   The canvas container lives at this path in the layout tree.
   Layout:  flex-row [0=left-panel, 1=canvas-box, 2=info-box]
              canvas-box is Boxed; path [1;0] navigates into its child flex-col.
   --------------------------------------------------------------------------- *)

let canvas_path = [ 1; 0 ]

type state = { composer : Page.t }

(* ---------------------------------------------------------------------------
   Helpers
   --------------------------------------------------------------------------- *)

let composer_file () =
  if Array.length Sys.argv > 1 then Sys.argv.(1) else "pages/composer.json"

let load_page path =
  let json = Yojson.Safe.from_file path in
  match Page_codec.page_of_json json with
  | Ok p -> p
  | Error e -> failwith ("Failed to load page '" ^ path ^ "': " ^ e)

let canvas_widget_count s =
  Layout_tree.count_children_at s.composer.Page.layout canvas_path

(** Update the "info" pager with current widget count and selected type. *)
let refresh_info s =
  if Hashtbl.mem s.composer.Page.widgets "info" then begin
    let n = canvas_widget_count s in
    let selected =
      match Hashtbl.find_opt s.composer.Page.state "selected_type" with
      | Some (`String t) when t <> "" -> t
      | _ -> "(none)"
    in
    let text =
      Printf.sprintf
        "Canvas widgets: %d\nSelected: %s\n\n Keys:\n [Tab]    Next pane\n [q]      Quit"
        n selected
    in
    ignore
      (Page.execute_action s.composer
         (Action.Set_text { target = "info"; value = text }))
  end

(** Add a widget of the given type into the canvas sub-flex container. *)
let add_widget_to_canvas s wtype =
  let n = canvas_widget_count s in
  let wid = Printf.sprintf "%s_%d" wtype n in
  let json = `Assoc [ ("type", `String wtype); ("id", `String wid) ] in
  match Widget_factory.create_widget json with
  | Error _ -> ()
  | Ok (id, wb) -> (
      match Page.add_widget s.composer ~id ~widget_box:wb ~path:canvas_path ~position:n with
      | Ok () -> refresh_info s
      | Error _ -> ())

(** Handle emitted events from send_key / execute_action. *)
let handle_events s events =
  List.iter
    (fun (ev : Page.emit_event) ->
      match ev.name with
      | "$quit" -> Direct.quit ()
      | "$back" -> Direct.go_back ()
      | "$navigate" -> (
          match ev.snapshot with
          | `String tgt -> Direct.navigate tgt
          | _ -> ())
      | "add_widget" -> (
          (* Query palette widget directly for current selection; fall back to
             state store in case the widget was removed from the page. *)
          let wtype =
            match Hashtbl.find_opt s.composer.Page.widgets "palette" with
            | Some wb -> (
                match Widget_box.query wb with
                | `Assoc fields -> (
                    match List.assoc_opt "selected" fields with
                    | Some (`String t) when t <> "" -> t
                    | _ -> "")
                | _ -> "")
            | None -> (
                match Hashtbl.find_opt s.composer.Page.state "selected_type" with
                | Some (`String t) -> t
                | _ -> "")
          in
          if wtype <> "" then add_widget_to_canvas s wtype)
      | _ -> ())
    events

(* ---------------------------------------------------------------------------
   Direct_page.REQUIRED implementation
   --------------------------------------------------------------------------- *)

let init () =
  let composer = load_page (composer_file ()) in
  let s = { composer } in
  refresh_info s;
  s

let render_status_bar s cols =
  let n = canvas_widget_count s in
  let selected =
    match Hashtbl.find_opt s.composer.Page.state "selected_type" with
    | Some (`String t) when t <> "" -> t
    | _ -> "(none)"
  in
  let bar =
    Printf.sprintf
      " [COMPOSER] %d widgets | selected: %s | [Tab] Next pane | [q] Quit"
      n selected
  in
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
  let events = Page.send_key s.composer ~key in
  handle_events s events;
  s
