(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** JSON serialization for Layout_tree.t *)

open Miaou_composer_lib

let get_string fields key =
  match List.assoc_opt key fields with Some (`String s) -> s | _ -> ""

let get_string_opt fields key =
  match List.assoc_opt key fields with Some (`String s) -> Some s | _ -> None

let get_int fields key ~default =
  match List.assoc_opt key fields with Some (`Int n) -> n | _ -> default

let get_int_opt fields key =
  match List.assoc_opt key fields with Some (`Int n) -> Some n | _ -> None

let padding_of_json fields =
  match List.assoc_opt "padding" fields with
  | Some (`Assoc pf) ->
      {
        Layout_tree.left = get_int pf "left" ~default:0;
        right = get_int pf "right" ~default:0;
        top = get_int pf "top" ~default:0;
        bottom = get_int pf "bottom" ~default:0;
      }
  | _ -> Layout_tree.no_padding

let padding_to_json (p : Layout_tree.padding) =
  `Assoc
    [
      ("left", `Int p.left);
      ("right", `Int p.right);
      ("top", `Int p.top);
      ("bottom", `Int p.bottom);
    ]

let border_style_of_string = function
  | "none" -> Layout_tree.None_
  | "single" -> Single
  | "double" -> Double
  | "rounded" -> Rounded
  | "ascii" -> Ascii
  | "heavy" -> Heavy
  | _ -> Single

let border_style_to_string = function
  | Layout_tree.None_ -> "none"
  | Single -> "single"
  | Double -> "double"
  | Rounded -> "rounded"
  | Ascii -> "ascii"
  | Heavy -> "heavy"

let direction_of_string = function
  | "row" -> Layout_tree.Row
  | _ -> Layout_tree.Column

let direction_to_string = function
  | Layout_tree.Row -> "row"
  | Layout_tree.Column -> "column"

let justify_of_string = function
  | "center" -> Layout_tree.Center
  | "end" -> Layout_tree.End
  | "space_between" -> Layout_tree.Space_between
  | "space_around" -> Layout_tree.Space_around
  | _ -> Layout_tree.Start

let justify_to_string = function
  | Layout_tree.Start -> "start"
  | Center -> "center"
  | End -> "end"
  | Space_between -> "space_between"
  | Space_around -> "space_around"

let align_of_string = function
  | "start" -> Layout_tree.Start_align
  | "center" -> Layout_tree.Center_align
  | "end" -> Layout_tree.End_align
  | _ -> Layout_tree.Stretch

let align_to_string = function
  | Layout_tree.Start_align -> "start"
  | Center_align -> "center"
  | End_align -> "end"
  | Stretch -> "stretch"

let basis_of_json = function
  | `String "auto" -> Layout_tree.Auto
  | `String "fill" -> Layout_tree.Fill
  | `Int n -> Layout_tree.Px n
  | `Float f -> Layout_tree.Ratio f
  | `Assoc [ ("type", `String "px"); ("value", `Int n) ] -> Layout_tree.Px n
  | `Assoc [ ("type", `String "percent"); ("value", `Float f) ] ->
      Layout_tree.Percent f
  | _ -> Layout_tree.Auto

let basis_to_json = function
  | Layout_tree.Auto -> `String "auto"
  | Fill -> `String "fill"
  | Px n -> `Assoc [ ("type", `String "px"); ("value", `Int n) ]
  | Ratio f -> `Float f
  | Percent f -> `Assoc [ ("type", `String "percent"); ("value", `Float f) ]

let track_of_json = function
  | `Assoc [ ("type", `String "px"); ("value", `Int n) ] -> Layout_tree.TPx n
  | `Assoc [ ("type", `String "fr"); ("value", `Float f) ] -> Layout_tree.TFr f
  | `Assoc [ ("type", `String "percent"); ("value", `Float f) ] ->
      Layout_tree.TPercent f
  | `Assoc [ ("type", `String "auto") ] -> Layout_tree.TAuto
  | `String "auto" -> Layout_tree.TAuto
  | _ -> Layout_tree.TAuto

let track_to_json = function
  | Layout_tree.TPx n -> `Assoc [ ("type", `String "px"); ("value", `Int n) ]
  | TFr f -> `Assoc [ ("type", `String "fr"); ("value", `Float f) ]
  | TPercent f -> `Assoc [ ("type", `String "percent"); ("value", `Float f) ]
  | TAuto -> `Assoc [ ("type", `String "auto") ]
  | TMinMax (a, b) ->
      `Assoc [ ("type", `String "minmax"); ("min", `Int a); ("max", `Int b) ]

(** Parse a JSON layout node. Returns the layout tree node and a list of
    (widget_id, widget_json) pairs for widgets found in leaves. *)
let rec layout_of_json (json : Yojson.Safe.t) :
    (Layout_tree.t * (string * Yojson.Safe.t) list, string) result =
  match json with
  | `Assoc fields -> (
      match List.assoc_opt "type" fields with
      | Some (`String "flex") ->
          let direction = direction_of_string (get_string fields "direction") in
          let gap = get_int fields "gap" ~default:0 in
          let padding = padding_of_json fields in
          let justify = justify_of_string (get_string fields "justify") in
          let align_items = align_of_string (get_string fields "align_items") in
          let basis =
            match List.assoc_opt "basis" fields with
            | Some b -> basis_of_json b
            | None -> Layout_tree.Auto
          in
          let children_json =
            match List.assoc_opt "children" fields with
            | Some (`List l) -> l
            | _ -> []
          in
          let children_results = List.map layout_of_json children_json in
          let errors =
            List.filter_map
              (fun r -> match r with Error e -> Some e | Ok _ -> None)
              children_results
          in
          if errors <> [] then Error (String.concat "; " errors)
          else
            let children, widget_lists =
              List.split
                (List.filter_map
                   (fun r -> match r with Ok v -> Some v | Error _ -> None)
                   children_results)
            in
            Ok
              ( Flex
                  {
                    direction;
                    gap;
                    padding;
                    justify;
                    align_items;
                    children;
                    basis;
                  },
                List.concat widget_lists )
      | Some (`String "grid") ->
          let rows =
            match List.assoc_opt "rows" fields with
            | Some (`List l) -> List.map track_of_json l
            | _ -> []
          in
          let cols =
            match List.assoc_opt "cols" fields with
            | Some (`List l) -> List.map track_of_json l
            | _ -> []
          in
          let row_gap = get_int fields "row_gap" ~default:0 in
          let col_gap = get_int fields "col_gap" ~default:0 in
          let basis =
            match List.assoc_opt "basis" fields with
            | Some b -> basis_of_json b
            | None -> Layout_tree.Auto
          in
          let children_json =
            match List.assoc_opt "children" fields with
            | Some (`List l) -> l
            | _ -> []
          in
          let children_results =
            List.map
              (fun child_json ->
                match child_json with
                | `Assoc cf -> (
                    let row = get_int cf "row" ~default:0 in
                    let col = get_int cf "col" ~default:0 in
                    let row_span = get_int cf "row_span" ~default:1 in
                    let col_span = get_int cf "col_span" ~default:1 in
                    let node_json =
                      match List.assoc_opt "node" cf with
                      | Some n -> n
                      | None -> child_json
                    in
                    match layout_of_json node_json with
                    | Ok (node, widgets) ->
                        let placement =
                          Layout_tree.{ row; col; row_span; col_span }
                        in
                        Ok ((placement, node), widgets)
                    | Error e -> Error e)
                | _ -> Error "Grid child must be an object")
              children_json
          in
          let errors =
            List.filter_map
              (fun r -> match r with Error e -> Some e | Ok _ -> None)
              children_results
          in
          if errors <> [] then Error (String.concat "; " errors)
          else
            let children, widget_lists =
              List.split
                (List.filter_map
                   (fun r -> match r with Ok v -> Some v | Error _ -> None)
                   children_results)
            in
            Ok
              ( Grid { rows; cols; row_gap; col_gap; children; basis },
                List.concat widget_lists )
      | Some (`String "box") -> (
          let title = get_string_opt fields "title" in
          let style = border_style_of_string (get_string fields "style") in
          let padding = padding_of_json fields in
          let basis =
            match List.assoc_opt "basis" fields with
            | Some b -> basis_of_json b
            | None -> Layout_tree.Auto
          in
          match List.assoc_opt "child" fields with
          | Some child_json -> (
              match layout_of_json child_json with
              | Ok (child, widgets) ->
                  Ok
                    ( Boxed { title; style; padding; child = Some child; basis },
                      widgets )
              | Error e -> Error e)
          | None -> Ok (Boxed { title; style; padding; child = None; basis }, [])
          )
      | Some (`String "card") -> (
          let title = get_string_opt fields "title" in
          let footer = get_string_opt fields "footer" in
          let accent = get_int_opt fields "accent" in
          let basis =
            match List.assoc_opt "basis" fields with
            | Some b -> basis_of_json b
            | None -> Layout_tree.Auto
          in
          match List.assoc_opt "child" fields with
          | Some child_json -> (
              match layout_of_json child_json with
              | Ok (child, widgets) ->
                  Ok
                    ( Card { title; footer; accent; child = Some child; basis },
                      widgets )
              | Error e -> Error e)
          | None -> Ok (Card { title; footer; accent; child = None; basis }, [])
          )
      | Some (`String typ) ->
          (* Must be a widget leaf *)
          let id = get_string fields "id" in
          let basis =
            match List.assoc_opt "basis" fields with
            | Some b -> basis_of_json b
            | None -> Layout_tree.Auto
          in
          if id = "" then Error ("Widget of type '" ^ typ ^ "' missing 'id'")
          else Ok (Leaf { id; basis }, [ (id, json) ])
      | _ -> Error "Node must have a 'type' field")
  | _ -> Error "Layout node must be a JSON object"

(** Serialize a layout tree back to JSON. The widget_to_json function is called
    for leaf nodes to serialize the widget's current state. *)
let rec layout_to_json node ~widget_to_json =
  match node with
  | Layout_tree.Leaf { id; basis } -> (
      match widget_to_json id with
      | Some json -> (
          (* Merge basis into widget JSON *)
          match json with
          | `Assoc fields -> `Assoc (fields @ [ ("basis", basis_to_json basis) ])
          | other -> other)
      | None -> `Assoc [ ("type", `String "unknown"); ("id", `String id) ])
  | Flex { direction; gap; padding; justify; align_items; children; basis } ->
      let base =
        [
          ("type", `String "flex");
          ("direction", `String (direction_to_string direction));
          ("gap", `Int gap);
          ("padding", padding_to_json padding);
          ("justify", `String (justify_to_string justify));
          ("align_items", `String (align_to_string align_items));
          ( "children",
            `List
              (List.map (fun c -> layout_to_json c ~widget_to_json) children) );
        ]
      in
      let base =
        match basis with
        | Layout_tree.Auto -> base
        | b -> base @ [ ("basis", basis_to_json b) ]
      in
      `Assoc base
  | Grid { rows; cols; row_gap; col_gap; children; basis } ->
      let base =
        [
          ("type", `String "grid");
          ("rows", `List (List.map track_to_json rows));
          ("cols", `List (List.map track_to_json cols));
          ("row_gap", `Int row_gap);
          ("col_gap", `Int col_gap);
          ( "children",
            `List
              (List.map
                 (fun (p, c) ->
                   `Assoc
                     [
                       ("row", `Int p.Layout_tree.row);
                       ("col", `Int p.col);
                       ("row_span", `Int p.row_span);
                       ("col_span", `Int p.col_span);
                       ("node", layout_to_json c ~widget_to_json);
                     ])
                 children) );
        ]
      in
      let base =
        match basis with
        | Layout_tree.Auto -> base
        | b -> base @ [ ("basis", basis_to_json b) ]
      in
      `Assoc base
  | Boxed { title; style; padding; child; basis } ->
      let fields =
        [ ("type", `String "box") ]
        @ (match title with Some t -> [ ("title", `String t) ] | None -> [])
        @ [
            ("style", `String (border_style_to_string style));
            ("padding", padding_to_json padding);
          ]
        @ (match basis with
          | Layout_tree.Auto -> []
          | b -> [ ("basis", basis_to_json b) ])
        @
        match child with
        | Some c -> [ ("child", layout_to_json c ~widget_to_json) ]
        | None -> []
      in
      `Assoc fields
  | Card { title; footer; accent; child; basis } ->
      let fields =
        [ ("type", `String "card") ]
        @ (match title with Some t -> [ ("title", `String t) ] | None -> [])
        @ (match footer with Some f -> [ ("footer", `String f) ] | None -> [])
        @ (match accent with Some a -> [ ("accent", `Int a) ] | None -> [])
        @ (match basis with
          | Layout_tree.Auto -> []
          | b -> [ ("basis", basis_to_json b) ])
        @
        match child with
        | Some c -> [ ("child", layout_to_json c ~widget_to_json) ]
        | None -> []
      in
      `Assoc fields
