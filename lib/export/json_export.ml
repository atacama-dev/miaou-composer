(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Export live page state to JSON documents. *)

open Miaou_composer_lib

(** Export a page's full state as a JSON document. *)
let export_page_state (page : Page.t) : Yojson.Safe.t =
  let widgets =
    Hashtbl.fold
      (fun id wb acc ->
        let entry =
          `Assoc
            [
              ("id", `String id);
              ("type", `String (Widget_box.type_name wb));
              ("focusable", `Bool (Widget_box.is_focusable wb));
              ("state", Widget_box.query wb);
            ]
        in
        entry :: acc)
      page.widgets []
  in
  let current_focus, focus_index, focus_total = Page.query_focus page in
  `Assoc
    [
      ("page_id", `String page.id);
      ( "focus",
        `Assoc
          [
            ( "current",
              match current_focus with Some id -> `String id | None -> `Null );
            ("index", `Int focus_index);
            ("total", `Int focus_total);
          ] );
      ("widgets", `List widgets);
      ( "size",
        `Assoc [ ("rows", `Int page.size.rows); ("cols", `Int page.size.cols) ]
      );
    ]

(** Export rendered output as a JSON document with the frame. *)
let export_rendered (page : Page.t) : Yojson.Safe.t =
  let frame = Page.render page in
  `Assoc
    [
      ("page_id", `String page.id);
      ("frame", `String frame);
      ( "size",
        `Assoc [ ("rows", `Int page.size.rows); ("cols", `Int page.size.cols) ]
      );
    ]

(** Export a session summary. *)
let export_session_summary (session : Session.t) : Yojson.Safe.t =
  let pages = Session.list_pages session in
  `Assoc
    [
      ("page_count", `Int (List.length pages));
      ("pages", `List (List.map (fun id -> `String id) pages));
    ]
