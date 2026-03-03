(** JSON serialization for Tool_def.t *)

open Miaou_composer_lib

let get_string fields key =
  match List.assoc_opt key fields with Some (`String s) -> s | _ -> ""

let get_string_opt fields key =
  match List.assoc_opt key fields with
  | Some (`String s) when s <> "" -> Some s
  | _ -> None

let get_bool fields key ~default =
  match List.assoc_opt key fields with Some (`Bool b) -> b | _ -> default

let get_string_list_field fields key =
  match List.assoc_opt key fields with
  | Some (`List items) ->
      List.filter_map (function `String s -> Some s | _ -> None) items
  | _ -> []

let tool_def_to_json (t : Tool_def.t) : Yojson.Safe.t =
  match t with
  | Tool_def.Builtin { name } ->
      `Assoc [ ("name", `String name); ("type", `String "builtin") ]
  | Tool_def.Process
      {
        name;
        bin;
        argv;
        stdin;
        cwd;
        capture_stdout;
        capture_stdout_lines;
        capture_json_fields;
        on_exit;
      } ->
      let fields =
        [
          ("name", `String name);
          ("type", `String "process");
          ("bin", `String bin);
          ("argv", `List (List.map (fun s -> `String s) argv));
        ]
      in
      let opt_fields =
        List.filter_map Fun.id
          [
            Option.map (fun s -> ("stdin", `String s)) stdin;
            Option.map (fun s -> ("cwd", `String s)) cwd;
            Option.map (fun s -> ("capture_stdout", `String s)) capture_stdout;
            Option.map
              (fun s -> ("capture_stdout_lines", `String s))
              capture_stdout_lines;
            (if capture_json_fields then Some ("capture_json_fields", `Bool true)
             else None);
            Option.map
              (fun a -> ("on_exit", Action_codec.action_to_json a))
              on_exit;
          ]
      in
      `Assoc (fields @ opt_fields)
  | Tool_def.Shell
      {
        name;
        cmd;
        cwd;
        capture_stdout;
        capture_stdout_lines;
        capture_json_fields;
        on_exit;
      } ->
      let fields =
        [
          ("name", `String name); ("type", `String "shell"); ("cmd", `String cmd);
        ]
      in
      let opt_fields =
        List.filter_map Fun.id
          [
            Option.map (fun s -> ("cwd", `String s)) cwd;
            Option.map (fun s -> ("capture_stdout", `String s)) capture_stdout;
            Option.map
              (fun s -> ("capture_stdout_lines", `String s))
              capture_stdout_lines;
            (if capture_json_fields then Some ("capture_json_fields", `Bool true)
             else None);
            Option.map
              (fun a -> ("on_exit", Action_codec.action_to_json a))
              on_exit;
          ]
      in
      `Assoc (fields @ opt_fields)

let tool_def_of_json (json : Yojson.Safe.t) : (Tool_def.t, string) result =
  match json with
  | `Assoc fields -> (
      let name = get_string fields "name" in
      if name = "" then Error "Tool definition missing 'name'"
      else
        let on_exit =
          match List.assoc_opt "on_exit" fields with
          | Some j -> (
              match Action_codec.action_of_json j with
              | Ok a -> Some a
              | Error _ -> None)
          | None -> None
        in
        match get_string fields "type" with
        | "builtin" -> Ok (Tool_def.Builtin { name })
        | "process" ->
            let bin = get_string fields "bin" in
            if bin = "" then Error ("Process tool '" ^ name ^ "' missing 'bin'")
            else
              Ok
                (Tool_def.Process
                   {
                     name;
                     bin;
                     argv = get_string_list_field fields "argv";
                     stdin = get_string_opt fields "stdin";
                     cwd = get_string_opt fields "cwd";
                     capture_stdout = get_string_opt fields "capture_stdout";
                     capture_stdout_lines =
                       get_string_opt fields "capture_stdout_lines";
                     capture_json_fields =
                       get_bool fields "capture_json_fields" ~default:false;
                     on_exit;
                   })
        | "shell" ->
            let cmd = get_string fields "cmd" in
            if cmd = "" then Error ("Shell tool '" ^ name ^ "' missing 'cmd'")
            else
              Ok
                (Tool_def.Shell
                   {
                     name;
                     cmd;
                     cwd = get_string_opt fields "cwd";
                     capture_stdout = get_string_opt fields "capture_stdout";
                     capture_stdout_lines =
                       get_string_opt fields "capture_stdout_lines";
                     capture_json_fields =
                       get_bool fields "capture_json_fields" ~default:false;
                     on_exit;
                   })
        | t -> Error ("Unknown tool type: " ^ t))
  | _ -> Error "Tool definition must be a JSON object"
