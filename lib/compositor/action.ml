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
