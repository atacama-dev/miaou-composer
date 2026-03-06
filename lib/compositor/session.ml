(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Multi-page session management. One session per MCP connection. *)

type t = { pages : (string, Page.t) Hashtbl.t }

let create () = { pages = Hashtbl.create 4 }

let add_page t page =
  if Hashtbl.mem t.pages page.Page.id then
    Error ("Duplicate page ID: " ^ page.Page.id)
  else begin
    Hashtbl.replace t.pages page.Page.id page;
    Ok ()
  end

let get_page t ~page_id = Hashtbl.find_opt t.pages page_id

let remove_page t ~page_id =
  if Hashtbl.mem t.pages page_id then begin
    Hashtbl.remove t.pages page_id;
    Ok ()
  end
  else Error ("Page not found: " ^ page_id)

let list_pages t = Hashtbl.fold (fun id _page acc -> id :: acc) t.pages []
