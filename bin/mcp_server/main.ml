(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

(** MCP server entry point. Reads JSON-RPC messages from stdin, dispatches to
    handlers, writes responses to stdout. *)

let () =
  let session = Miaou_composer_lib.Session.create () in
  (* Read lines from stdin, parse as JSON-RPC, dispatch *)
  try
    while true do
      let line = input_line stdin in
      if String.length line > 0 then begin
        match Yojson.Safe.from_string line with
        | json -> (
            match
              (try Ok (Mcp_protocol.dispatch session json)
               with exn -> Error (Printexc.to_string exn))
            with
            | Error msg ->
                let err =
                  Mcp_protocol.make_error_response ~id:`Null ~code:(-32603)
                    ~message:("Internal error: " ^ msg)
                in
                print_string (Yojson.Safe.to_string err);
                print_char '\n';
                flush stdout
            | Ok (Some response) ->
                let out = Yojson.Safe.to_string response in
                print_string out;
                print_char '\n';
                flush stdout
            | Ok None -> ())
        | exception Yojson.Json_error msg ->
            let err =
              Mcp_protocol.make_error_response ~id:`Null ~code:(-32700)
                ~message:("Parse error: " ^ msg)
            in
            print_string (Yojson.Safe.to_string err);
            print_char '\n';
            flush stdout
      end
    done
  with End_of_file -> ()
