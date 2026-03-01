(** MCP JSON-RPC 2.0 protocol implementation over stdio. *)

let server_info =
  `Assoc [ ("name", `String "miaou-composer"); ("version", `String "0.1.0") ]

let server_capabilities = `Assoc [ ("tools", `Assoc []) ]

(** Build a JSON-RPC 2.0 response. *)
let make_response ~id result =
  `Assoc [ ("jsonrpc", `String "2.0"); ("id", id); ("result", result) ]

(** Build a JSON-RPC 2.0 error response. *)
let make_error_response ~id ~code ~message =
  `Assoc
    [
      ("jsonrpc", `String "2.0");
      ("id", id);
      ("error", `Assoc [ ("code", `Int code); ("message", `String message) ]);
    ]

(** Handle the initialize request. *)
let handle_initialize _params =
  `Assoc
    [
      ("protocolVersion", `String "2024-11-05");
      ("capabilities", server_capabilities);
      ("serverInfo", server_info);
    ]

(** Handle tools/list request. *)
let handle_tools_list () =
  `Assoc [ ("tools", `List (List.map Tools.tool_to_json (Tools.all_tools ()))) ]

(** Handle tools/call request. *)
let handle_tools_call session params =
  match params with
  | `Assoc fields -> (
      let tool_name =
        match List.assoc_opt "name" fields with
        | Some (`String s) -> s
        | _ -> ""
      in
      let args =
        match List.assoc_opt "arguments" fields with
        | Some (`Assoc a) -> a
        | _ -> []
      in
      match Tool_handlers.handle_tool session ~tool_name ~args with
      | Ok result ->
          `Assoc
            [
              ( "content",
                `List
                  [
                    `Assoc
                      [
                        ("type", `String "text");
                        ("text", `String (Yojson.Safe.to_string result));
                      ];
                  ] );
            ]
      | Error msg ->
          `Assoc
            [
              ( "content",
                `List
                  [ `Assoc [ ("type", `String "text"); ("text", `String msg) ] ]
              );
              ("isError", `Bool true);
            ])
  | _ ->
      `Assoc
        [
          ( "content",
            `List
              [
                `Assoc
                  [
                    ("type", `String "text"); ("text", `String "Invalid params");
                  ];
              ] );
          ("isError", `Bool true);
        ]

(** Dispatch a JSON-RPC request. *)
let dispatch session (request : Yojson.Safe.t) : Yojson.Safe.t option =
  match request with
  | `Assoc fields -> (
      let id =
        match List.assoc_opt "id" fields with Some id -> id | None -> `Null
      in
      let method_ =
        match List.assoc_opt "method" fields with
        | Some (`String s) -> s
        | _ -> ""
      in
      let params =
        match List.assoc_opt "params" fields with
        | Some p -> p
        | None -> `Assoc []
      in
      match method_ with
      | "initialize" -> Some (make_response ~id (handle_initialize params))
      | "initialized" ->
          (* Notification, no response needed *)
          None
      | "tools/list" -> Some (make_response ~id (handle_tools_list ()))
      | "tools/call" ->
          Some (make_response ~id (handle_tools_call session params))
      | "notifications/cancelled" -> None
      | m ->
          Some
            (make_error_response ~id ~code:(-32601)
               ~message:("Method not found: " ^ m)))
  | _ ->
      Some
        (make_error_response ~id:`Null ~code:(-32600)
           ~message:"Invalid JSON-RPC request")
