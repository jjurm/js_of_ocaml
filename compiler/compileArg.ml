(* Js_of_ocaml compiler
 * http://www.ocsigen.org/js_of_ocaml/
 * Copyright (C) 2014 Hugo Heuzard
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

open Cmdliner

type t = {
  common : CommonArg.t;
  (* compile option *)
  profile : Driver.profile option;
  source_map : (string option * Source_map.t) option;
  runtime_files : string list;
  output_file : string option;
  input_file : string option;
  params : (string * string) list;
  (* toplevel *)
  linkall : bool;
  toplevel : bool;
  nocmis : bool;
  (* filesystem *)
  include_dir : string list;
  fs_files : string list;
  fs_output : string option;
  fs_external : bool;
}

exception Error of (bool * string)


let options =
  let toplevel_section = "OPTIONS (TOPLEVEL)" in
  let filesystem_section = "OPTIONS (FILESYSTEM)" in
  let js_files =
    let doc = "Link JavaScript files [$(docv)]. " ^
              "One can refer to path relative to Findlib packages with " ^
              "the syntax '+pkg_name/file.js'"
    in
    Arg.(value & pos_left ~rev:true 0 string [] & info [] ~docv:"JS_FILES" ~doc)
  in
  let output_file =
    let doc = "Set output file name to [$(docv)]." in
    Arg.(value & opt (some string) None & info ["o"] ~docv:"FILE" ~doc)
  in
  let input_file =
    let doc = "Compile the bytecode program [$(docv)]. " ^
              "Use '-' to read from the standard input instead." in
    Arg.(required & pos ~rev:true 0 (some string) None & info [] ~docv:"PROGRAM" ~doc)
  in
  let profile =
    let doc = "Set optimization profile : [$(docv)]." in
    let profile = List.map (fun (i,p) -> string_of_int i, p) Driver.profiles in
    Arg.(value & opt (some (enum profile)) None & info ["opt"] ~docv:"NUM" ~doc)
  in
  let noruntime =
    let doc = "Do not include the standard runtime." in
    Arg.(value & flag & info ["noruntime";"no-runtime"] ~doc)
  in
  let sourcemap =
    let doc = "Generate source map." in
    Arg.(value & flag & info ["sourcemap";"source-map"] ~doc)
  in
  let inlined_sourcemap =
    let doc = "Generate inlined source map." in
    Arg.(value & flag & info ["inlined-source-map"] ~doc)
  in
  let set_param =
    let doc = "Set compiler options." in
    let all = List.map (fun (x,_) ->
      x, x) (Option.Param.all ()) in
    Arg.(value & opt_all (list (pair ~sep:'=' (enum all) string)) [] & info ["set"] ~docv:"PARAM=VALUE"~doc)
  in
  let toplevel =
    let doc = "Compile a toplevel." in
    Arg.(value & flag & info ["toplevel"] ~docs:toplevel_section ~doc)
  in
  let linkall =
    let doc = "Link all primitives." in
    Arg.(value & flag & info ["linkall"] ~docs:toplevel_section ~doc)
  in
  let nocmis =
    let doc = "Do not include cmis when compiling toplevel." in
    Arg.(value & flag & info ["nocmis";"no-cmis"] ~docs:toplevel_section ~doc)
  in
  let include_dir =
    let doc = "Add [$(docv)] to the list of include directories." in
    Arg.(value & opt_all string [] & info ["I"] ~docs:filesystem_section ~docv:"DIR" ~doc)
  in
  let fs_files =
    let doc = "Register [$(docv)] to the pseudo filesystem." in
    Arg.(value & opt_all string [] & info ["file"] ~docs:filesystem_section ~docv:"FILE" ~doc)
  in
  let fs_external =
    let doc = "Configure pseudo-filesystem to allow registering files from outside." in
    Arg.(value & flag & info ["extern-fs"] ~docs:filesystem_section ~doc)
  in
  let fs_output =
    let doc = "Output the filesystem to [$(docv)]." in
    Arg.(value & opt (some string) None & info ["ofs"] ~docs:filesystem_section ~docv:"FILE" ~doc)
  in
  let build_t
      common
      set_param
      linkall
      toplevel
      include_dir
      fs_files
      fs_output
      fs_external
      nocmis
      profile
      noruntime
      sourcemap
      inlined_sourcemap
      output_file
      input_file
      js_files

    =
    let chop_extension s =
      try Filename.chop_extension s with Invalid_argument _ -> s in
    try
      let runtime_files = js_files in
      let runtime_files =
        if noruntime
        then runtime_files
        else "+runtime.js"::runtime_files in
      let linkall = linkall || toplevel in
      let fs_external = fs_external || (toplevel && nocmis) in
      let input_file = match input_file with
        | "-" -> None
        | x -> Some x in
      let output_file = match output_file with
        | Some _ -> output_file
        | None   -> Util.opt_map (fun s -> chop_extension s ^ ".js") input_file in
      let source_map =
        if sourcemap || inlined_sourcemap
        then
	  let file, output_file =
	    match output_file with
            | Some file when inlined_sourcemap -> file, None
	    | Some file -> file, Some (chop_extension file ^ ".map")
	    | None -> "STDIN", None in
          Some (
              output_file,
              {
                Source_map.version = 3;
                file;
                sourceroot = None;
                sources = [];
                sources_content = [];
                names = [];
                mappings = []
            })
        else None in
      let params : (string * string) list = List.flatten set_param in
      `Ok {
        common;
        params;
        profile;

        linkall;
        toplevel;

        include_dir;
        runtime_files;

        fs_files;
        fs_output;
        fs_external;
        nocmis;

        output_file;
        input_file;
        source_map
      }
    with Error (b,str) -> `Error (b,str)
  in
  let t =
    Term.(pure build_t
          $ CommonArg.t
          $ set_param
          $ linkall
          $ toplevel

          $ include_dir
          $ fs_files
          $ fs_output
          $ fs_external
          $ nocmis

          $ profile

          $ noruntime
          $ sourcemap
          $ inlined_sourcemap

          $ output_file

          $ input_file
          $ js_files)
  in
  Term.ret t

let info =
  let doc =
    "Js_of_ocaml compiler"
  in
  let man = [
    `S "DESCRIPTION";
    `P "Js_of_ocaml is a compiler from OCaml bytecode to Javascript. \
        It makes OCaml programs run on Web browsers.";
    `S "BUGS";
    `P "Bugs are tracked on github at \
        $(i,https://github.com/ocsigen/js_of_ocaml/issues).";
    `S "SEE ALSO";
    `P "ocaml(1)";
    `S "AUTHORS";
    `P "Jerome Vouillon, Hugo Heuzard.";
    `S "LICENSE";
    `P "Copyright (C) 2010-2014.";
    `P "js_of_ocaml is free software, you can redistribute it and/or modify \
        it under the terms of the GNU Lesser General Public License as published \
        by the Free Software Foundation, with linking exception; \
        either version 2.1 of the License, or (at your option) any later version."
  ]
  in
  let version = match Compiler_version.git_version with
    | "" -> Compiler_version.s
    | v  -> Printf.sprintf "%s+git-%s"Compiler_version.s v in
  Term.info "js_of_ocaml" ~version ~doc ~man
