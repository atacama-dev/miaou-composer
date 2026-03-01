(** Mutable layout tree. Interior nodes are layout containers, leaves reference
    widgets by ID (looked up in the widget store at render time). *)

type basis = Auto | Px of int | Fill | Ratio of float | Percent of float
type direction = Row | Column
type justify = Start | Center | End | Space_between | Space_around
type align = Start_align | Center_align | End_align | Stretch
type padding = { left : int; right : int; top : int; bottom : int }
type border_style = None_ | Single | Double | Rounded | Ascii | Heavy

type grid_track =
  | TPx of int
  | TFr of float
  | TPercent of float
  | TAuto
  | TMinMax of int * int

type grid_placement = { row : int; col : int; row_span : int; col_span : int }

type t =
  | Leaf of { id : string; basis : basis }
  | Flex of {
      direction : direction;
      gap : int;
      padding : padding;
      justify : justify;
      align_items : align;
      mutable children : t list;
    }
  | Grid of {
      rows : grid_track list;
      cols : grid_track list;
      row_gap : int;
      col_gap : int;
      mutable children : (grid_placement * t) list;
    }
  | Boxed of {
      title : string option;
      style : border_style;
      padding : padding;
      mutable child : t option;
    }
  | Card of {
      title : string option;
      footer : string option;
      accent : int option;
      mutable child : t option;
    }

let no_padding = { left = 0; right = 0; top = 0; bottom = 0 }
let default_padding = { left = 0; right = 0; top = 0; bottom = 0 }

(** Collect all widget IDs from the tree in order (depth-first). *)
let rec collect_ids node =
  match node with
  | Leaf { id; _ } -> [ id ]
  | Flex { children; _ } -> List.concat_map collect_ids children
  | Grid { children; _ } ->
      List.concat_map (fun (_, n) -> collect_ids n) children
  | Boxed { child = Some c; _ } -> collect_ids c
  | Boxed { child = None; _ } -> []
  | Card { child = Some c; _ } -> collect_ids c
  | Card { child = None; _ } -> []

(** Find and remove a leaf with the given ID. Returns true if found. *)
let rec remove_leaf_by_id node id =
  match node with
  | Leaf _ -> false
  | Flex f ->
      let before = List.length f.children in
      f.children <-
        List.filter
          (fun c -> match c with Leaf l -> l.id <> id | _ -> true)
          f.children;
      if List.length f.children < before then true
      else List.exists (fun c -> remove_leaf_by_id c id) f.children
  | Grid g ->
      let before = List.length g.children in
      g.children <-
        List.filter
          (fun (_, c) -> match c with Leaf l -> l.id <> id | _ -> true)
          g.children;
      if List.length g.children < before then true
      else List.exists (fun (_, c) -> remove_leaf_by_id c id) g.children
  | Boxed b -> (
      match b.child with
      | Some (Leaf l) when l.id = id ->
          b.child <- None;
          true
      | Some c -> remove_leaf_by_id c id
      | None -> false)
  | Card ca -> (
      match ca.child with
      | Some (Leaf l) when l.id = id ->
          ca.child <- None;
          true
      | Some c -> remove_leaf_by_id c id
      | None -> false)

(** Add a child at a given position in a container node. [path] is a list of
    integer indices navigating into nested containers. An empty path means "add
    to the root node itself". *)
let add_child_at root ~path ~position child =
  let rec navigate node remaining_path =
    match (node, remaining_path) with
    | _, [] -> (
        match node with
        | Flex f ->
            let pos = min position (List.length f.children) in
            let before, after =
              ( List.filteri (fun i _ -> i < pos) f.children,
                List.filteri (fun i _ -> i >= pos) f.children )
            in
            f.children <- before @ [ child ] @ after;
            true
        | Grid g ->
            let placement = { row = 0; col = 0; row_span = 1; col_span = 1 } in
            g.children <- g.children @ [ (placement, child) ];
            true
        | Boxed b ->
            b.child <- Some child;
            true
        | Card ca ->
            ca.child <- Some child;
            true
        | Leaf _ -> false)
    | Flex f, idx :: rest -> (
        match List.nth_opt f.children idx with
        | Some target -> navigate target rest
        | None -> false)
    | Grid g, idx :: rest -> (
        match List.nth_opt g.children idx with
        | Some (_, target) -> navigate target rest
        | None -> false)
    | Boxed { child = Some c; _ }, 0 :: rest -> navigate c rest
    | Card { child = Some c; _ }, 0 :: rest -> navigate c rest
    | _ -> false
  in
  navigate root path
