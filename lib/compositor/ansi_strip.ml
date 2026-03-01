(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: MIT                                               *)
(* Copyright (c) 2026 Nomadic Labs <contact@nomadic-labs.com>                 *)
(*                                                                            *)
(******************************************************************************)

(** Remove ANSI/VT escape sequences from a string, returning plain text. *)
let strip s =
  let buf = Buffer.create (String.length s) in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '\x1b' then (
      incr i;
      if !i < n && s.[!i] = '[' then (
        (* CSI sequence: ESC [ ... <final byte 0x40-0x7e> *)
        incr i;
        while !i < n && (s.[!i] < '@' || s.[!i] > '~') do
          incr i
        done;
        if !i < n then incr i (* consume final byte *))
      else if !i < n then incr i (* skip single char after ESC (Fe sequence) *))
    else (
      Buffer.add_char buf s.[!i];
      incr i)
  done;
  Buffer.contents buf
