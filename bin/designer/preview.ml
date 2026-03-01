(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

[@@@warning "-32-34-37-69"]

module Csession = Miaou_composer_lib.Session
module Cpage = Miaou_composer_lib.Page
module Clayout = Miaou_composer_lib.Layout_tree

let render_preview (t : Designer_state.t) ~cols ~rows =
  match Csession.get_page t.session ~page_id:t.page_id with
  | None -> "(no page)"
  | Some cpage ->
      let widget_ids = Clayout.collect_ids cpage.Cpage.layout in
      if widget_ids = [] then
        let hint = "No widgets yet -- press 'a' to add one" in
        let pad = max 0 ((cols - String.length hint) / 2) in
        String.make pad ' ' ^ hint
      else begin
        cpage.Cpage.size <- { LTerm_geom.rows; cols };
        Cpage.render cpage
      end

let send_key (t : Designer_state.t) ~key =
  match Csession.get_page t.session ~page_id:t.page_id with
  | None -> ()
  | Some cpage -> ignore (Cpage.send_key cpage ~key)

let get_focused_widget (t : Designer_state.t) =
  match Csession.get_page t.session ~page_id:t.page_id with
  | None -> None
  | Some cpage ->
      let focused, _, _ = Cpage.query_focus cpage in
      focused
