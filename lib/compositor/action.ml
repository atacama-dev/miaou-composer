(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Closed variant of compositor actions that can be triggered by wirings. *)

type outcome = Commit | Cancel

type t =
  | Set_text of { target : string; value : string }
  | Set_checked of { target : string; value : bool }
  | Toggle of { target : string }
  | Append_text of { target : string; value : string }
  | Push_modal of { modal_def : Yojson.Safe.t }
  | Close_modal of { outcome : outcome }
  | Navigate of { target : string }
  | Back
  | Quit
  | Focus of { target : string }
  | Emit of { event : string }
  | Set_disabled of { target : string; value : bool }
  | Set_visible of { target : string; value : bool }
  | Set_items of { target : string; items : string list }
  | Set_state of { key : string; value : Yojson.Safe.t }
  | Copy_widget_to_state of { key : string; source : string }
  | Inc_state of { key : string; by : float }
  | Reset_state of { key : string }
  | Sequence of t list
  | Call_tool of { name : string; args : (string * string) list }
