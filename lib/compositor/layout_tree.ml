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
      basis : basis;
    }
  | Grid of {
      rows : grid_track list;
      cols : grid_track list;
      row_gap : int;
      col_gap : int;
      mutable children : (grid_placement * t) list;
      basis : basis;
    }
  | Boxed of {
      title : string option;
      style : border_style;
      padding : padding;
      mutable child : t option;
      basis : basis;
    }
  | Card of {
      title : string option;
      footer : string option;
      accent : int option;
      mutable child : t option;
      basis : basis;
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

(** Display node for the designer's tree pane. *)
type display_node = {
  depth : int;
  label : string;
  id : string;  (** widget id for leaves; "~kind~path" key for containers *)
  is_container : bool;
  path : int list;
}

(** Collect nodes for the tree pane.  The root Flex is the implicit page
    container and is skipped — only its children are listed. *)
let collect_display_nodes root =
  let path_to_key path =
    String.concat "." (List.map string_of_int path)
  in
  let rec aux node path depth =
    match node with
    | Leaf { id; _ } ->
        [ { depth; label = id; id; is_container = false; path } ]
    | Flex { direction; children; _ } ->
        let lbl =
          match direction with Row -> "→ flex-row" | Column -> "↓ flex-col"
        in
        let key = "~flex~" ^ path_to_key path in
        let self = { depth; label = lbl; id = key; is_container = true; path } in
        let child_nodes =
          List.concat
            (List.mapi (fun i c -> aux c (path @ [ i ]) (depth + 1)) children)
        in
        self :: child_nodes
    | Grid { children; _ } ->
        let key = "~grid~" ^ path_to_key path in
        let self =
          { depth; label = "⊞ grid"; id = key; is_container = true; path }
        in
        let child_nodes =
          List.concat
            (List.mapi
               (fun i (_, c) -> aux c (path @ [ i ]) (depth + 1))
               children)
        in
        self :: child_nodes
    | Boxed { title; child; _ } ->
        let lbl =
          match title with Some t -> "□ " ^ t | None -> "□ box"
        in
        let key = "~box~" ^ path_to_key path in
        let self =
          { depth; label = lbl; id = key; is_container = true; path }
        in
        let child_nodes =
          match child with
          | Some c -> aux c (path @ [ 0 ]) (depth + 1)
          | None -> []
        in
        self :: child_nodes
    | Card { title; child; _ } ->
        let lbl =
          match title with Some t -> "▣ " ^ t | None -> "▣ card"
        in
        let key = "~card~" ^ path_to_key path in
        let self =
          { depth; label = lbl; id = key; is_container = true; path }
        in
        let child_nodes =
          match child with
          | Some c -> aux c (path @ [ 0 ]) (depth + 1)
          | None -> []
        in
        self :: child_nodes
  in
  (* Skip the root container — it is the implicit page Flex *)
  match root with
  | Flex { children; _ } ->
      List.concat (List.mapi (fun i c -> aux c [ i ] 0) children)
  | _ -> aux root [] 0

(** Decode a container ID of the form "~kind~i.j..." back to a layout path.
    Returns [None] if the string is not a valid container ID. *)
let path_of_container_id id =
  match String.split_on_char '~' id with
  | [ ""; _kind; "" ] -> Some []
  | [ ""; _kind; path_str ] ->
      let parts = String.split_on_char '.' path_str in
      let indices = List.filter_map int_of_string_opt parts in
      if List.length indices = List.length parts then Some indices else None
  | _ -> None

let is_container_id id = String.length id > 0 && id.[0] = '~'

(** Count direct children of the container node reached by following [path]. *)
let count_children_at layout path =
  let rec nav node p =
    match (node, p) with
    | Flex f, [] -> List.length f.children
    | Grid g, [] -> List.length g.children
    | (Boxed _ | Card _), [] -> 0
    | Flex f, i :: rest -> (
        match List.nth_opt f.children i with
        | Some c -> nav c rest
        | None -> 0)
    | Grid g, i :: rest -> (
        match List.nth_opt g.children i with
        | Some (_, c) -> nav c rest
        | None -> 0)
    | Boxed { child = Some c; _ }, 0 :: rest -> nav c rest
    | Card { child = Some c; _ }, 0 :: rest -> nav c rest
    | _ -> 0
  in
  nav layout path

(** Return the (parent_path, position_in_parent) of the leaf with [widget_id].
    Returns [None] if the widget is not found. *)
let find_widget_parent_info layout widget_id =
  let rec aux node path =
    match node with
    | Leaf _ -> None
    | Flex f ->
        let direct =
          List.find_mapi
            (fun i child ->
              match child with
              | Leaf { id; _ } when id = widget_id -> Some (path, i)
              | _ -> None)
            f.children
        in
        if direct <> None then direct
        else
          List.find_map
            (fun (i, child) -> aux child (path @ [ i ]))
            (List.mapi (fun i c -> (i, c)) f.children)
    | Grid g ->
        let direct =
          List.find_mapi
            (fun i (_, child) ->
              match child with
              | Leaf { id; _ } when id = widget_id -> Some (path, i)
              | _ -> None)
            g.children
        in
        if direct <> None then direct
        else
          List.find_map
            (fun (i, (_, child)) -> aux child (path @ [ i ]))
            (List.mapi (fun i c -> (i, c)) g.children)
    | Boxed { child = Some c; _ } -> (
        match c with
        | Leaf { id; _ } when id = widget_id -> Some (path, 0)
        | _ -> aux c (path @ [ 0 ]))
    | Card { child = Some c; _ } -> (
        match c with
        | Leaf { id; _ } when id = widget_id -> Some (path, 0)
        | _ -> aux c (path @ [ 0 ]))
    | _ -> None
  in
  aux layout []

(** Human-readable label for the node at [path]. *)
let node_label_at layout path =
  let rec nav node p =
    match (node, p) with
    | _, [] -> (
        match node with
        | Flex { direction; _ } -> (
            match direction with Row -> "→ flex-row" | Column -> "↓ flex-col")
        | Grid _ -> "⊞ grid"
        | Boxed { title; _ } -> (
            match title with Some t -> "□ " ^ t | None -> "□ box")
        | Card { title; _ } -> (
            match title with Some t -> "▣ " ^ t | None -> "▣ card")
        | Leaf { id; _ } -> id)
    | Flex f, i :: rest -> (
        match List.nth_opt f.children i with
        | Some c -> nav c rest
        | None -> "?")
    | Grid g, i :: rest -> (
        match List.nth_opt g.children i with
        | Some (_, c) -> nav c rest
        | None -> "?")
    | Boxed { child = Some c; _ }, 0 :: rest -> nav c rest
    | Card { child = Some c; _ }, 0 :: rest -> nav c rest
    | _ -> "?"
  in
  nav layout path
