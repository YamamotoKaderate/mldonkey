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

open AnyEndian
open LittleEndian
open Printf2
open CommonOptions
open BasicSocket  
open TcpBufferedSocket
open Options
  
open CommonClient
open CommonServer
open CommonNetwork
open CommonOptions
open CommonTypes
open CommonFile
open CommonGlobals
open CommonSearch
open CommonResult
open CommonServer
open CommonTypes
open CommonComplexOptions
  
  
  
(*************  ADD/REMOVE FUNCTIONS ************)

let canonize_basename name =
  let name = String.copy name in
  for i = 0 to String.length name - 1 do
    match name.[i] with
    | '/' | '\\' -> name.[i] <- '_'
    | _ -> ()
  done;
  name
  
let file_commited_name file =   
  let network = file_network file in
  let best_name = file_best_name file in
  let file_name = file_disk_name file in
  let incoming_dir =
    if network.network_incoming_subdir () <> "" then
      Filename.concat !!incoming_directory
        (network.network_incoming_subdir ())
    else !!incoming_directory
  in
  (try Unix2.safe_mkdir incoming_dir with _ -> ());
  let new_name = 
    Filename.concat incoming_dir (canonize_basename 
        (file_best_name file))
  in
  let new_name = 
    if Sys.file_exists new_name then
      let rec iter num =
        let new_name = Printf.sprintf "%s.%d" new_name num in
        if Sys.file_exists new_name then
          iter (num+1)
        else new_name
      in
      iter 1
    else new_name in
  new_name  
  
(********
These two functions 'file_commit' and 'file_cancel' should be the two only
functions in mldonkey able to destroy a file, the first one by moving it, 
the second one by deleting it. 

Note that when the network specific file_commit function is called, the
file has already been moved to the incoming/ directory under its new
name.
*)
  
let file_commit file =
  let impl = as_file_impl file in
  if impl.impl_file_state = FileDownloaded then
    let new_name = file_commited_name file in
    try
      set_file_disk_name file new_name;
      let best_name = file_best_name file in  
      Unix32.destroy (file_fd file);
      (* Commit the file first, and share it after... *)
      impl.impl_file_ops.op_file_commit impl.impl_file_val new_name;
      if not (Unix2.is_directory new_name) then 
        ignore (CommonShared.new_shared 
            !!incoming_directory !!incoming_directory_prio best_name new_name);
      done_files =:= List2.removeq file !!done_files;
      update_file_state impl FileShared;
    with e ->
      lprintf "Exception in file_commit: %s\n" (Printexc2.to_string e)
      
let file_cancel file =
  try
    let impl = as_file_impl file in    
    if impl.impl_file_state <> FileCancelled then begin
        update_file_state impl FileCancelled;
        impl.impl_file_ops.op_file_cancel impl.impl_file_val;
        (try  Unix32.remove (file_fd file)  with e -> 
              lprintf "Sys.remove %s exception %s\n" 
                (file_disk_name file)
              (Printexc2.to_string e); );
        Unix32.destroy (file_fd file);
        files =:= List2.removeq file !!files;
    end
  with e ->
      lprintf "Exception in file_cancel: %s\n" (Printexc2.to_string e)

        
let mail_for_completed_file file =
  if !!mail <> "" then
    let module M = Mailer in
    let line1 = "mldonkey has completed the download of:\r\n\r\n" in

    let line2 = Printf.sprintf "\r\nFile: %s\r\nSize: %Ld bytes\r\nComment: %s\r\n" 
      (file_best_name file)
      (file_size file)
      (file_comment file)
    in
    
    let subject = if !!filename_in_subject then
        Printf.sprintf "[mldonkey] file received - %s"
        (file_best_name file)
      else
        Printf.sprintf "mldonkey, file received";        
    in

    let line3 = if !!url_in_mail <> "" then
	Printf.sprintf "\r\n%s/%s\r\n" !!url_in_mail (file_best_name file)
      else
        Printf.sprintf "";
    in
    
    let mail = {
        M.mail_to = !!mail;
        M.mail_from = !!mail;
        M.mail_subject = subject;
        M.mail_body = line1 ^ line2 ^ line3;
      } in
    M.sendmail !!smtp_server !!smtp_port !!add_mail_brackets mail

let chat_for_completed_file file =
  CommonChat.send_warning_for_downloaded_file (file_best_name file)

      
let file_completed (file : file) =
  try
    let impl = as_file_impl file in
    if impl.impl_file_state = FileDownloading then begin
        files =:= List2.removeq file !!files;
        done_files =:= file :: !!done_files;
        update_file_state impl FileDownloaded;  
        let file_name = file_disk_name file in
        let file_id = Filename.basename file_name in
        ignore (CommonShared.new_shared "completed" 0 (
            file_best_name file )
          file_name);
        (try mail_for_completed_file file with e ->
              lprintf "Exception %s in sendmail\n" (Printexc2.to_string e);
              );
        if !!CommonOptions.chat_warning_for_downloaded then
          chat_for_completed_file file;
        
        if !!file_completed_cmd <> "" then begin
            MlUnix.fork_and_exec  !!file_completed_cmd 
              [|
              file_name;
              file_id;
              Int64.to_string (file_size file);
              file_best_name file
            |]
          
          end
      
      
      end
  with e ->
      lprintf "Exception in file_completed: %s\n" (Printexc2.to_string e)
      
let file_add impl state = 
  try
    let file = as_file impl in
    if impl.impl_file_state = FileNew then begin
        update_file_num impl;
        (match state with
            FileDownloaded -> 
              done_files =:= file :: !!done_files;
          | FileShared
          | FileNew
          | FileCancelled -> ()
              
          | FileAborted _
          | FileDownloading
          | FileQueued
          | FilePaused -> 
              files =:= file :: !!files);
        update_file_state impl state
      end
  with e ->
      lprintf "Exception in file_add: %s\n" (Printexc2.to_string e)
      
let server_remove server =
  try
    let impl = as_server_impl server in
    if impl.impl_server_state <> RemovedHost then begin
        set_server_state server RemovedHost;
        (try impl.impl_server_ops.op_server_remove impl.impl_server_val
          with _ -> ());
        servers =:= Intmap.remove (server_num server) !!servers;
      end
  with e ->
      lprintf "Exception in server_remove: %s\n" (Printexc2.to_string e)
  
let server_add impl =
  let server = as_server impl in
  if impl.impl_server_state = NewHost then begin
      server_update_num impl;
      servers =:= Intmap.add (server_num server) server !!servers;
      impl.impl_server_state <- NotConnected (BasicSocket.Closed_by_user, -1);
    end

let friend_add c =
  let impl = as_client_impl c in
  if not (is_friend c) then begin
      set_friend c;
      client_must_update c;
      friends =:= c :: !!friends;
      contacts := List2.removeq c !contacts;
      impl.impl_client_ops.op_client_browse impl.impl_client_val true
    end
    
(* Maybe we should not add the client to the contact list and completely remove
it ? *)
let friend_remove c =
  try
    let impl = as_client_impl c in
    if is_friend c then begin
        set_not_friend c;
        client_must_update c;
        friends =:= List2.removeq c !!friends;
        impl.impl_client_ops.op_client_clear_files impl.impl_client_val
      end else
    if is_contact c then begin
        set_not_contact c;
        client_must_update c;
        contacts := List2.removeq c !contacts;
        impl.impl_client_ops.op_client_clear_files impl.impl_client_val
      end        
      
  with e ->
      lprintf "Exception in friend_remove: %s\n" (Printexc2.to_string e)
  
let contact_add c =
  let impl = as_client_impl c in
  if not (is_friend c || is_contact c) then begin
      set_contact c;
      client_must_update c;
      contacts := c :: !contacts;
      impl.impl_client_ops.op_client_browse impl.impl_client_val true
    end
    
let contact_remove c =
  try
    let impl = as_client_impl c in
    if is_contact c then begin
        set_not_contact c;
        client_must_update c;
        contacts := List2.removeq c !contacts;
        impl.impl_client_ops.op_client_clear_files impl.impl_client_val
      end
  with e ->
      lprintf "Exception in contact_remove: %s\n" (Printexc2.to_string e)

  
  
  
let time_of_sec sec = 
  let hours = sec / 60 / 60 in
  let rest = sec - hours * 60 * 60 in
  let minutes = rest / 60 in
  let seconds = rest - minutes * 60 in
    if hours > 0 then Printf.sprintf "%d:%02d:%02d" hours minutes seconds
	else if minutes > 0 then Printf.sprintf "%d:%02d" minutes seconds
    	else Printf.sprintf "00:%02d" seconds
  
(* ripped from gui_misc *)

let ko = 1024.0 
let mo = ko *. ko 
let go = mo *. ko 
let tob = go *. ko 

let size_of_int64 size =
  if !!html_mods_human_readable then
    let f = Int64.to_float size in
	if f > tob then
      Printf.sprintf "%.2fT" (f /. tob)
	else
     if f > go then
      Printf.sprintf "%.2fG" (f /. go)
     else
      if f > mo then
      Printf.sprintf "%.1fM" (f /. mo)
      else
     if f > ko then
       Printf.sprintf "%.1fk" (f /. ko)
     else
       Int64.to_string size
  else
    Int64.to_string size

  
let display_vd = ref false

let start_download file =
  
  if !!file_started_cmd <> "" then 
      MlUnix.fork_and_exec  !!file_started_cmd 
      [|
      !!file_started_cmd;
        "-file";
        string_of_int (CommonFile.file_num file);
      |]
      
let download_file o arg =
  let user = o.conn_user in
  let buf = o.conn_buf in
  Printf.bprintf buf "%s\n" (
    try
      match user.ui_last_search with
        None -> "no last search"
      | Some s ->
          let result = List.assoc (int_of_string arg) user.ui_last_results  in
          let files = CommonResult.result_download 
            result [] false in
          List.iter start_download files;
          "download started"
    with
    | Failure s -> s
    | _ -> "could not start download"
  )
  
let start_search user query buf =
  let s = CommonSearch.new_search user query in
  begin
    match s.search_type with
    LocalSearch ->
        CommonSearch.local_search s
    | _ ->
        networks_iter (fun r -> 
            if query.GuiTypes.search_network = 0 ||
              r.network_num = query.GuiTypes.search_network
            then
              r.op_network_search s buf);
  end;
  s
  
let print_connected_servers o =
  let buf = o.conn_buf in
  networks_iter (fun r ->
      try
       let list = network_connected_servers r in
		if r.network_name <> "BitTorrent" then begin	
       if use_html_mods o then Printf.bprintf buf "\\<div class=servers\\>";
       Printf.bprintf buf "--- Connected to %d servers on the %s network ---\n"
         (List.length list) r.network_name;
       if use_html_mods o then Printf.bprintf buf "\\</div\\>";
		end;
       if use_html_mods o && List.length list > 0 then server_print_html_header buf "C";

      let counter = ref 0 in  
       List.iter (fun s ->
        incr counter;
		if use_html_mods o then 
         Printf.bprintf buf "\\<tr class=\\\"%s\\\"\\>"     
          (if (!counter mod 2 == 0) then "dl-1" else "dl-2");
        server_print s o;
       ) (List.sort (fun s1 s2 -> compare (server_num s1) (server_num s2)) list);

        if use_html_mods o && List.length list > 0 then 
           Printf.bprintf buf "\\</table\\>\\</div\\>";
       with e ->
           Printf.bprintf  buf "Exception %s in print_connected_servers"
             (Printexc2.to_string e);

  )
  
let send_custom_query user buf query args = 
  try
    let q = List.assoc query (CommonComplexOptions.customized_queries()) in
    let args = ref args in
    let get_arg arg_name = 
(*      lprintf "Getting %s\n" arg_name; *)
      match !args with
        (label, value) :: tail ->
          args := tail;
          if label = arg_name then value else begin
              Printf.bprintf buf "Error expecting argument %s instead of %s" arg_name label;  
              raise Exit
            end
      | _ ->
          Printf.bprintf buf "Error while expecting argument %s" arg_name;
          raise Exit
    in
    let rec iter q =
      match q with
      | Q_COMBO _ -> assert false
      | Q_KEYWORDS _ -> 
          let value = get_arg "keywords" in
          want_and_not andnot (fun w -> QHasWord w) QNone value
      
      | Q_AND list ->
          begin
            let ands = ref [] in
            List.iter (fun q ->
                try ands := (iter q) :: !ands with _ -> ()) list;
            match !ands with
              [] -> raise Not_found
            | [q] -> q
            | q1 :: tail ->
                List.fold_left (fun q1 q2 -> QAnd (q1,q2)) q1 tail
          end
      
      | Q_HIDDEN list ->
          begin
            let ands = ref [] in
            List.iter (fun q ->
                try ands := (iter q) :: !ands with _ -> ()) list;
            match !ands with
              [] -> raise Not_found
            | [q] -> q
            | q1 :: tail ->
                List.fold_left (fun q1 q2 -> QAnd (q1,q2)) q1 tail
          end
      
      | Q_OR list ->
          begin
            let ands = ref [] in
            List.iter (fun q ->
                try ands := (iter q) :: !ands with _ -> ()) list;
            match !ands with
              [] -> raise Not_found
            | [q] -> q
            | q1 :: tail ->
                List.fold_left (fun q1 q2 -> QOr (q1,q2)) q1 tail
          end
      
      | Q_ANDNOT (q1, q2) ->
          begin
            let r1 = iter q1 in
            try
              QAndNot(r1, iter q2)
            with Not_found -> r1
          end
      
      | Q_MODULE (s, q) -> iter q
      
      | Q_MINSIZE _ ->
          let minsize = get_arg "minsize" in
          let unit = get_arg "minsize_unit" in
          if minsize = "" then raise Not_found;
          let minsize = Int64.of_string minsize in
          let unit = Int64.of_string unit in
          QHasMinVal (Field_Size, Int64.mul minsize unit)
      
      | Q_MAXSIZE _ ->
          let maxsize = get_arg "maxsize" in
          let unit = get_arg "maxsize_unit" in
          if maxsize = "" then raise Not_found;
          let maxsize = Int64.of_string maxsize in
          let unit = Int64.of_string unit in
          QHasMaxVal (Field_Size, Int64.mul maxsize unit)
      
      | Q_FORMAT _ ->
          let format = get_arg "format" in
          let format_propose = get_arg "format_propose" in
          let format = if format = "" then 
              if format_propose = "" then raise Not_found
              else format_propose
            else format in
          want_comb_not andnot
            or_comb
            (fun w -> QHasField(Field_Format, w)) QNone format
      
      | Q_MEDIA _ ->
          let media = get_arg "media" in
          let media_propose = get_arg "media_propose" in
          let media = if media = "" then 
              if media_propose = "" then raise Not_found
              else media_propose
            else media in
          QHasField(Field_Type, media)
      
      | Q_MP3_ARTIST _ ->
          let artist = get_arg "artist" in
          if artist = "" then raise Not_found;
          want_comb_not andnot and_comb 
            (fun w -> QHasField(Field_Artist, w)) QNone artist
      
      | Q_MP3_TITLE _ ->
          let title = get_arg "title" in
          if title = "" then raise Not_found;
          want_comb_not andnot and_comb 
            (fun w -> QHasField(Field_Title, w)) QNone title
      
      | Q_MP3_ALBUM _ ->
          let album = get_arg "album" in
          if album = "" then raise Not_found;
          want_comb_not andnot and_comb 
            (fun w -> QHasField(Field_Album, w)) QNone album
      
      | Q_MP3_BITRATE _ ->
          let bitrate = get_arg "bitrate" in
          if bitrate = "" then raise Not_found;
          QHasMinVal(Field_unknown "bitrate", Int64.of_string bitrate)
    
    in
    try
      let request = CommonGlobals.simplify_query (iter q) in
      Printf.bprintf buf "Sending query !!!";
      
      let s = 
        let module G = GuiTypes in
        { G.search_num = 0;
          G.search_query = request;
          G.search_type = RemoteSearch;
          G.search_max_hits = 10000;
          G.search_network = (
            try
              let net = get_arg "network" in
              (network_find_by_name net).network_num
            with _ -> 0);
        }
      in
      ignore (start_search user s buf)
    with
      Not_found ->
        Printf.bprintf buf "Void query %s" query        
  with 
    Not_found ->
      Printf.bprintf buf "No such custom search %s" query
  | Exit -> ()
  | e -> 
      Printf.bprintf buf "Error %s while parsing request"
        (Printexc2.to_string e)

let sort_options l =
  List.sort (fun o1 o2 ->
      String.compare o1.option_name o2.option_name) l
    
let opfile_args r opfile =
  let prefix = r.network_prefix () in
  let args = simple_options prefix opfile in
  args
  
let all_simple_options () =
  let options = ref (sort_options
      (simple_options "" downloads_ini) 
    )
  in
  networks_iter_all (fun r ->
      List.iter (fun opfile ->
          options := !options @ (opfile_args r opfile)
      )
      r.network_config_file 
  );
  !options

let parse_simple_options args = 
  let v = all_simple_options () in
  match args with
    [] -> v 
    | args ->
      let match_star = Str.regexp "\\*" in
      let options_filter = Str.regexp ("^\\(" 
        ^ (List.fold_left (fun acc a -> acc 
        ^ (if acc <> "" then "\\|" else "") 
        ^ (Str.global_replace match_star ".*" a)) "" args) 
        ^ "\\)$") in
      List.filter (fun o -> Str.string_match options_filter o.option_name 0) v

let some_simple_options num =
               let cnt = ref 0 in
               let options = ref [] in
               networks_iter_all (fun r ->
                       List.iter (fun opfile ->
                               if !cnt = num then begin
          options := !options @ (opfile_args r opfile)

                       end;
                       incr cnt
                       ) r.network_config_file
               );
               !options

let all_active_network_opfile_network_names () =
       let names = ref [] in
       networks_iter_all (fun r ->
               List.iter (fun opfile ->
                       names := !names @ [r.network_name]
               ) r.network_config_file
       );
       !names

let apply_on_fully_qualified_options name f =
  if !verbose then lprintf "For option %s\n" name; 
  let rec iter prefix opfile =
    let args = simple_options prefix opfile in
    List.iter (fun o ->
(*        lprintf "Compare [%s] [%s]\n" o.option_name name; *)
        if o.option_name = name then
          (f opfile o.option_shortname o.option_value; raise Exit))
    args
  in
  try
    iter "" downloads_ini;
    if not (networks_iter_all_until_true (fun r ->
            try
              List.iter (fun opfile ->
                  let prefix = r.network_prefix () in
(*                  lprintf "Prefix [%s]\n" prefix; *)
                  iter prefix opfile;
              )
              r.network_config_file ;
              false
            with Exit -> true
        )) then begin
        lprintf "Could not set option %s\n" name; 
        raise Not_found
      end
  with Exit -> ()
      

let set_fully_qualified_options name value =
  apply_on_fully_qualified_options name (fun opfile old_name old_value ->
      set_simple_option opfile old_name value)

let get_fully_qualified_options name =
  let value = ref None in
  (try
      apply_on_fully_qualified_options name (fun opfile old_name old_value ->
      value := Some (get_simple_option opfile old_name)
      );
    with _ -> ());
  match !value with
    None -> "????"
  | Some s -> s

let add_item_to_fully_qualified_options name value =
  ()

let del_item_from_fully_qualified_options name value = 
  ()

let keywords_of_query query =
  let keywords = ref [] in
  
  let rec iter q = 
    match q with
    | QOr (q1,q2) 
    | QAnd (q1, q2) -> iter q1; iter q2
    | QAndNot (q1,q2) -> iter q1 
    | QHasWord w -> keywords := (String2.split_simplify w ' ') @ !keywords
    | QHasField(field, w) ->
        begin
          match field with
            Field_Album
          | Field_Title
          | Field_Artist
          | _ -> keywords := (String2.split_simplify w ' ') @ !keywords
        end
    | QHasMinVal (field, value) ->
        begin
          match field with
            Field_unknown "bitrate"
          | Field_Size
          | _ -> ()
        end
    | QHasMaxVal (field, value) ->
        begin
          match field with
            Field_unknown "bitrate"
          | Field_Size
          | _ -> ()
        end
    | QNone ->
        lprintf "LimewireInteractive.start_search: QNone in query\n";
        ()
  in
  iter query;
  !keywords

let gui_options_panels = ref ([] : (string * (string * string * string) list) list)
  
let register_gui_options_panel name panel =
  if not (List.mem_assoc name !gui_options_panels) then
    gui_options_panels := (name, panel) :: !gui_options_panels
    
    
let _ =
  add_infinite_timer filter_search_delay (fun _ ->
(*      if !!filter_search then *) begin
(*          lprintf "Filter search results\n"; *)
          List.iter (fun user ->
              List.iter  (fun s -> CommonSearch.Filter.find s) 
              user.ui_user_searches;
          ) !ui_users
        end;
      CommonSearch.Filter.clear ();
  )
  
let search_add_result filter s r =
  if !CommonSearch.clean_local_search <> 0 then
    CommonSearch.Local.add r;
  if not filter (*!!filter_search*) then begin
(*      lprintf "Adding result to filter\n"; *)
      CommonSearch.search_add_result_in s r
    end
  else
    CommonSearch.Filter.add r

let main_options = ref ([] : (string * Arg.spec * string) list)
  
let add_main_options list =
  main_options := !main_options @ list

  
(*************************************************************

Every minute, sort the files by priority, and test if the
files with the highest priority are in FileDownloading state,
and the ones with lowest priority in FileQueued state, if there
is a max_concurrent_downloads constraint.

In the future, we could try to mix this with the multi-users
system to give some fairness between downloads of different 
users.
  
**************************************************************)  

open CommonFile
  
let force_download_quotas () = 
  let files = List.sort (fun f1 f2 -> 
        let v = file_priority f2 - file_priority f1 in
        if v <> 0 then v else
        let s1 = file_downloaded f1 in
        let s2 = file_downloaded f2 in
        if s1 = s2 then 0 else
        if s2 > s1 then 1 else -1
        )
    !!CommonComplexOptions.files in
  
  let rec iter list priority files ndownloads nqueued =
    match list, files with
      [], [] -> ()
    | [], _ -> 
        iter_line list priority files ndownloads nqueued
    | f :: tail , _ :: _ when file_priority f < priority ->
        iter_line list priority files ndownloads nqueued
    | f :: tail, files ->
        match file_state f with
          FileDownloading ->
            iter tail (file_priority f) (f :: files) (ndownloads+1) nqueued
        | FileQueued ->
            iter tail (file_priority f) (f :: files) ndownloads (nqueued+1)
        | _ ->
            iter tail (file_priority f) files ndownloads nqueued
        
  and iter_line list priority files ndownloads nqueued = 
    if ndownloads > !!max_concurrent_downloads then
      match files with
        [] -> assert false
      | f :: tail ->
          match file_state f with
            FileDownloading ->
              set_file_state f FileQueued;
              iter_line list priority tail (ndownloads-1) nqueued
          | _ -> iter_line list priority tail ndownloads (nqueued-1)
    else
    if ndownloads < !!max_concurrent_downloads && nqueued > 0 then
      match files with
        [] -> assert false
      | f :: tail ->
          match file_state f with
            FileQueued ->
              set_file_state f FileDownloading;
              iter_line list priority tail (ndownloads+1) (nqueued-1)
          | _ -> iter_line list priority tail ndownloads nqueued      
    else
      iter list priority [] ndownloads nqueued
    
  in
  iter files max_int [] 0 0
  
let _ =
  option_hook max_concurrent_downloads (fun _ ->
      force_download_quotas ()   
  )
