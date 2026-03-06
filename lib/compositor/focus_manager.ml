(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Rebuild Focus_ring from the layout tree's widget IDs. *)

let rebuild ~layout_tree ~widgets =
  let ids = Layout_tree.collect_ids layout_tree in
  let focusable_ids =
    List.filter
      (fun id ->
        match Hashtbl.find_opt widgets id with
        | Some wb -> Widget_box.is_focusable wb
        | None -> false)
      ids
  in
  Miaou_internals.Focus_ring.create focusable_ids
