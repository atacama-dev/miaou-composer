(******************************************************************************)
(*                                                                            *)
(* SPDX-License-Identifier: GPL-3.0-or-later                                  *)
(* Copyright (c) 2026 Mathias Bourgoin <mathias.bourgoin@atacama.tech>        *)
(*                                                                            *)
(******************************************************************************)

let register_system () =
  let module Sys_cap = Miaou_interfaces.System in
  Sys_cap.set
    {
      Sys_cap.file_exists = Sys.file_exists;
      is_directory = (fun p -> try Sys.is_directory p with _ -> false);
      read_file =
        (fun path ->
          try
            let ic = open_in_bin path in
            let len = in_channel_length ic in
            let buf = really_input_string ic len in
            close_in ic;
            Ok buf
          with e -> Error (Printexc.to_string e));
      write_file =
        (fun path contents ->
          try
            let oc = open_out_bin path in
            output_string oc contents;
            close_out oc;
            Ok ()
          with e -> Error (Printexc.to_string e));
      mkdir =
        (fun path ->
          try
            Unix.mkdir path 0o755;
            Ok ()
          with e -> Error (Printexc.to_string e));
      run_command =
        (fun ~argv ~cwd ->
          match argv with
          | [] -> Error "empty argv"
          | _ -> (
              try
                let orig = Sys.getcwd () in
                (match cwd with Some d -> Unix.chdir d | None -> ());
                let cmd = String.concat " " (List.map Filename.quote argv) in
                let ic, oc, ec =
                  Unix.open_process_full cmd (Unix.environment ())
                in
                close_out oc;
                let read_all ch =
                  let buf = Buffer.create 256 in
                  (try
                     while true do
                       Buffer.add_channel buf ch 1
                     done
                   with End_of_file -> ());
                  Buffer.contents buf
                in
                let stdout = read_all ic in
                let stderr = read_all ec in
                let st = Unix.close_process_full (ic, oc, ec) in
                (match cwd with Some _ -> Unix.chdir orig | None -> ());
                let exit_code = match st with Unix.WEXITED n -> n | _ -> 1 in
                Ok { Sys_cap.exit_code; stdout; stderr }
              with e -> Error (Printexc.to_string e)));
      get_current_user_info =
        (fun () ->
          try
            let pw = Unix.getpwuid (Unix.getuid ()) in
            Ok (pw.Unix.pw_name, pw.Unix.pw_dir)
          with e -> Error (Printexc.to_string e));
      get_disk_usage =
        (fun ~path ->
          try
            let st = Unix.stat path in
            Ok (Int64.of_int st.Unix.st_size)
          with _ -> Ok 0L);
      list_dir =
        (fun path ->
          try
            let arr = Sys.readdir path in
            Ok (Array.to_list arr)
          with e -> Error (Printexc.to_string e));
      probe_writable =
        (fun ~path ->
          try
            let tmp =
              Filename.concat path
                (Printf.sprintf ".miaou_probe_%d" (Unix.getpid ()))
            in
            let oc = open_out tmp in
            output_string oc "";
            close_out oc;
            Sys.remove tmp;
            Ok true
          with _ -> Ok false);
      get_env_var = Sys.getenv_opt;
    }

let () =
  register_system ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  Miaou_helpers.Fiber_runtime.init ~env ~sw;
  let module Page_impl =
    Miaou_core.Direct_page.With_defaults (Miaou_composer_json_runner.Runner_page) in
  let module Full_page = Miaou_core.Direct_page.Make (Page_impl) in
  let page : Miaou_core.Registry.page =
    (module Full_page : Miaou_core.Tui_page.PAGE_SIG)
  in
  let on_frame =
    match Sys.getenv_opt "MIAOU_WEB_VIEWER_PORT" with
    | Some port_str ->
        let port = int_of_string port_str in
        let viewer =
          Miaou_driver_web.Web_viewer.start ~sw ~net:(Eio.Stdenv.net env) ~port
            ()
        in
        Printf.eprintf "Web viewer: %s\n%!"
          (Miaou_driver_web.Web_viewer.url viewer);
        Some
          (fun ~rows ~cols data ->
            Miaou_driver_web.Web_viewer.broadcast viewer ~rows ~cols data)
    | None -> None
  in
  ignore (Miaou_runner_tui.Runner_tui.run ?on_frame page)
