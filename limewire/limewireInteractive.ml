(* Copyright 2001, 2002 b8_bavard, b8_fee_carabine, INRIA *)
(*
    This file is part of mldonkey.

    mldonkey is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    mldonkey is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mldonkey; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

open CommonOptions
open CommonServer
open CommonResult
open CommonTypes
open CommonComplexOptions
open CommonFile
open Options
open LimewireTypes
open LimewireOptions
open LimewireGlobals
open LimewireComplexOptions

open LimewireProtocol

let _ =
  server_ops.op_server_print <- (fun s o ->
      let buf = o.conn_buf in
      Printf.bprintf buf "%s:%d  %30s %d files(%d) %d kb\n"
        (Ip.to_string s.server_ip) s.server_port
        s.server_agent s.server_nfiles s.server_nfiles_last s.server_nkb      
  )

let _ =
  network.op_network_search <- (fun search buf ->
      let query = search.search_query in
  let keywords = ref [] in

  let rec iter q = 
    match q with
    | QOr (q1,q2) 
    | QAnd (q1, q2) -> iter q1; iter q2
    | QAndNot (q1,q2) -> iter q1 
    | QHasWord w -> keywords := String2.split_simplify w ' '
    | QHasField(field, w) ->
         begin
          match field with
            "Album"
          | "Title"
          | "Artist"
          | _ -> keywords := String2.split_simplify w ' '
        end
    | QHasMinVal (field, value) ->
        begin
          match field with
            "bitrate"
          | "size"
          | _ -> ()
        end
    | QHasMaxVal (field, value) ->
        begin
          match field with
            "bitrate"
          | "size"
          | _ -> ()
        end
    | QNone ->
	prerr_endline "LimewireInteractive.start_search: QNone in query";
	()
  in
  iter query;

  let p = LimewireServers.send_query 0 !keywords "" in
    
  let s = {
      search_search = search;
      search_uid = p.pkt_uid;
    } in
  Hashtbl.add searches_by_uid p.pkt_uid s;
  ())

let _ =
  result_ops.op_result_print <- (fun r counter o ->
      let buf = o.conn_buf in
      let file = r.result_file in
      Printf.bprintf buf "[Limewire %5d] %-70s %10s "
        counter
        (String.escaped file.file_name) (Int32.to_string file.file_size);
      List.iter (fun s ->
          Printf.bprintf buf "(%s:%d on %d kb/s%s)"
            (Ip.to_string s.source_ip) s.source_port s.source_speed
            (if s.source_push then "(PUSH)" else "")
      ) r.result_sources;
      Printf.bprintf buf "\n";
  );
  result_ops.op_result_download <- (fun result _ ->
      LimewireServers.download_file result)

let file_num file =
  file.file_file.impl_file_num

let _ =
  file_ops.op_file_print <- (fun file o ->
      let buf = o.conn_buf in
      let f = file.file_result.result_file in
      Printf.bprintf buf "[LimeWire %5d] %-50s %10s %10s\n" 
        (file_num file) f.file_name 
        (Int32.to_string f.file_size)
      (Int32.to_string file.file_downloaded)      
  );
  file_ops.op_file_cancel <- (fun file ->
      current_files := List2.remove file !current_files;
      file_cancel (as_file file.file_file);
  );
  file_ops.op_file_disk_name <- (fun file ->
      file.file_temp;
  )
  
module P = Gui_proto
  
let _ =
  file_ops.op_file_cancel <- (fun file ->
      let r = file.file_result in
      let f = r.result_file in
      Hashtbl.remove OpennapGlobals.files_by_key (f.file_name, f.file_size);
      current_files := List2.removeq file !current_files      
  );
  file_ops.op_file_print <- (fun file o ->
      let buf = o.conn_buf in
      let f = file.file_result.result_file in
      Printf.bprintf buf "[Opennap %5d] %-50s %10s %10s\n" 
      (file_num file) f.file_name 
      (Int32.to_string f.file_size)
      (Int32.to_string file.file_downloaded)      
  );
  file_ops.op_file_info <- (fun file ->
      let r = file.file_result in
      let f = r.result_file in
       {
        P.file_num = (file_num file);
        P.file_network = network.network_num;
        P.file_names = [f.file_name];
        P.file_md4 = Md4.null;
        P.file_size = f.file_size;
        P.file_downloaded = file.file_downloaded;
        P.file_nlocations = 0;
        P.file_nclients = 0;
        P.file_state = file_state file;
        P.file_sources = None;
        P.file_download_rate = 0.0;
        P.file_chunks = "0";
        P.file_availability = "0";
        P.file_format = Unknown_format;
        P.file_chunks_age = [|0.0|];
        P.file_age = 0.0;
      }    
  )
  
let _ =
  server_ops.op_server_info <- (fun s ->
      if !!enable_limewire then
        {
          P.server_num = (server_num s);
          P.server_network = network.network_num;
          P.server_ip = s.server_ip;
          P.server_port = s.server_port;
          P.server_score = 0;
          P.server_tags = [];
          P.server_nusers = 0;
          P.server_nfiles = s.server_nfiles;
          P.server_state = server_state s;
          P.server_name = s.server_agent;
          P.server_description = "";
          P.server_users = None;
        } else
        raise Not_found
  )

module C = CommonTypes
  
let _ =
  result_ops.op_result_info <- (fun r ->
       {
        C.result_num = r.result_result.impl_result_num;    
        C.result_network = network.network_num;
        
        C.result_names = [r.result_file.file_name];
        C.result_md4 = Md4.null;
        C.result_size = r.result_file.file_size;
        C.result_format = "";
        C.result_type = "";
        C.result_tags = [];
        C.result_comment = None;
        C.result_done = false;
      }   
  )
  