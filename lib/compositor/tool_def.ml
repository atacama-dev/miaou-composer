(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** Tool definitions: builtins, process tools, and shell tools. *)

type t =
  | Builtin of { name : string }
  | Process of {
      name : string;
      bin : string;
      argv : string list;
      stdin : string option;
      cwd : string option;
      capture_stdout : string option;
      capture_stdout_lines : string option;
      capture_json_fields : bool;
      on_exit : Action.t option;
    }
  | Shell of {
      name : string;
      cmd : string;
      cwd : string option;
      capture_stdout : string option;
      capture_stdout_lines : string option;
      capture_json_fields : bool;
      on_exit : Action.t option;
    }

let name = function
  | Builtin { name } -> name
  | Process { name; _ } -> name
  | Shell { name; _ } -> name
