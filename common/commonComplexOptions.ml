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

open CommonClient
open CommonServer
open CommonNetwork
open Options
open CommonOptions
open CommonTypes
open CommonFile
  
module FileOption = struct
    
    let value_to_file is_done v =
      match v with
        Options.Module assocs ->
          let get_value name conv = conv (List.assoc name assocs) in
          let network = try
              get_value "file_network" value_to_string
            with _ -> "Donkey"
          in
          let network = network_find_by_name network in
          let file = network_add_file network is_done assocs in
          file
      | _ -> assert false
          
    let file_to_value file =
      Options.Module (
        ("file_network", string_to_value (file_network file).network_name)
        ::
        (file_to_option file)
      )
      
    let t is_done =
      define_option_class "File" (value_to_file is_done) file_to_value
    ;;
  end

    
let done_files = 
  define_option files_ini ["done_files"] 
    "The files whose download is finished" (list_option (FileOption.t true)) []
  
let files = 
  define_option files_ini ["files"] 
    "The files currently being downloaded" (list_option (FileOption.t false)) []
    
module ServerOption = struct
    
    let value_to_server v =
      match v with
        Options.Module assocs ->
          let get_value name conv = conv (List.assoc name assocs) in
          let network = try
              get_value "server_network" value_to_string
            with _ -> "Donkey"
          in
          let network = network_find_by_name network in
          let server = network_add_server network assocs in
          server
      | _ -> assert false
          
    let server_to_value server =
      Options.Module (
        ("server_network", string_to_value (server_network server).network_name)
        ::
        (server_to_option server)
      )
      
    let t =
      define_option_class "Server" value_to_server server_to_value
    ;;
  end


let servers = define_option servers_ini
    ["known_servers"] "List of known servers"
    (list_option ServerOption.t) []


let rec string_of_option v =
  match v with
    Module m -> "{ MODULE }"
  | StringValue s -> Printf.sprintf "STRING [%s]" s
  | IntValue i -> Printf.sprintf "INT [%ld]" i
  | FloatValue f -> Printf.sprintf "FLOAT [%f]" f
  | List l | SmallList l ->
      (List.fold_left (fun s v ->
            s ^ (string_of_option v) ^ ";" 
        ) "LIST [" l) ^ "]"

module QueryOption = struct
    let rec query_to_value q =
      match q with
      | Q_AND list ->
          List ((StringValue "AND") :: (List.map query_to_value list))
      | Q_OR list ->
          List ((StringValue "OR"):: (List.map query_to_value list))
      | Q_HIDDEN list ->
          List ((StringValue "HIDDEN"):: (List.map query_to_value list))
      | Q_ANDNOT (q1, q2) ->
          SmallList [StringValue "ANDNOT"; query_to_value q1; query_to_value q2 ]
      | Q_MODULE (s, q) ->
          SmallList [StringValue "MODULE"; StringValue s;  query_to_value q]
          
        
        | Q_KEYWORDS (label, s) ->
            SmallList [StringValue "KEYWORDS"; StringValue label; StringValue s]
        | Q_MINSIZE (label, s) ->
            SmallList [StringValue "MINSIZE"; StringValue label; StringValue s]
        | Q_MAXSIZE (label, s) ->
            SmallList [StringValue "MAXSIZE"; StringValue label; StringValue s]
        | Q_FORMAT (label, s) ->
            SmallList [StringValue "FORMAT"; StringValue label; StringValue s]
        | Q_MEDIA (label, s) ->
            SmallList [StringValue "MEDIA"; StringValue label; StringValue s]
        
        | Q_MP3_ARTIST (label, s) ->
            SmallList [StringValue "MP3_ARTIST"; StringValue label; StringValue s]
        | Q_MP3_TITLE (label, s) ->
            SmallList [StringValue "MP3_TITLE"; StringValue label; StringValue s]
        | Q_MP3_ALBUM (label, s) ->
            SmallList [StringValue "MP3_ALBUM"; StringValue label; StringValue s]
        | Q_MP3_BITRATE (label, s) ->
            SmallList [StringValue "MP3_BITRATE"; StringValue label; StringValue s]
          
    let rec value_to_query v =
      match v with
      | SmallList ((StringValue "AND") :: list)
      | List ((StringValue "AND") :: list) -> 
          Q_AND (List.map value_to_query list)

      | SmallList ((StringValue "OR") :: list)
      | List ((StringValue "OR") :: list) -> 
          Q_OR (List.map value_to_query list)

      | SmallList ((StringValue "HIDDEN") :: list)
      | List ((StringValue "HIDDEN") :: list) -> 
          Q_HIDDEN (List.map value_to_query list)

      | SmallList [StringValue "ANDNOT"; v1; v2 ]
      | List [StringValue "ANDNOT"; v1; v2 ] -> 
          Q_ANDNOT (value_to_query v1, value_to_query v2)

      | SmallList [StringValue "MODULE"; StringValue label; v2 ]
      | List [StringValue "MODULE"; StringValue label; v2 ] -> 
          Q_MODULE (label, value_to_query v2)


          
      | SmallList [StringValue "KEYWORDS"; StringValue label; StringValue s]
      | List [StringValue "KEYWORDS"; StringValue label; StringValue s] ->
          Q_KEYWORDS (label, s)

      | SmallList [StringValue "MINSIZE"; StringValue label; StringValue s]
      | List [StringValue "MINSIZE"; StringValue label; StringValue s] ->
          Q_MINSIZE (label, s)

      | SmallList [StringValue "MAXSIZE"; StringValue label; StringValue s]
      | List [StringValue "MAXSIZE"; StringValue label; StringValue s] ->
          Q_MAXSIZE (label, s)

      | SmallList [StringValue "MINSIZE"; StringValue label; IntValue s]
      | List [StringValue "MINSIZE"; StringValue label; IntValue s] ->
          Q_MINSIZE (label, Int32.to_string s)

      | SmallList [StringValue "MAXSIZE"; StringValue label; IntValue s]
      | List [StringValue "MAXSIZE"; StringValue label; IntValue s] ->
          Q_MAXSIZE (label, Int32.to_string s)

      | SmallList [StringValue "FORMAT"; StringValue label; StringValue s]
      | List [StringValue "FORMAT"; StringValue label; StringValue s] ->
          Q_FORMAT (label, s)

      | SmallList [StringValue "MEDIA"; StringValue label; StringValue s]
      | List [StringValue "MEDIA"; StringValue label; StringValue s] ->
          Q_MEDIA (label, s)
          
      | SmallList [StringValue "MP3_ARTIST"; StringValue label; StringValue s]
      | List [StringValue "MP3_ARTIST"; StringValue label; StringValue s] ->
          Q_MP3_ARTIST (label, s)

      | SmallList [StringValue "MP3_TITLE"; StringValue label; StringValue s]
      | List [StringValue "MP3_TITLE"; StringValue label; StringValue s] ->
          Q_MP3_TITLE (label, s)

      | SmallList [StringValue "MP3_ALBUM"; StringValue label; StringValue s]
      | List [StringValue "MP3_ALBUM"; StringValue label; StringValue s] ->
          Q_MP3_ALBUM (label, s)

      | SmallList [StringValue "MP3_BITRATE"; StringValue label; StringValue s]
      | List [StringValue "MP3_BITRATE"; StringValue label; StringValue s] ->
          Q_MP3_BITRATE (label, s)

      | SmallList [StringValue "MP3_BITRATE"; StringValue label; IntValue s]
      | List [StringValue "MP3_BITRATE"; StringValue label; IntValue s] ->
          Q_MP3_BITRATE (label, Int32.to_string s)
          
      | _ -> failwith (Printf.sprintf "Query option: error while parsing %s"
              (string_of_option  v)
          )
      
    let t = define_option_class "Query" value_to_query query_to_value    
  end
      
let customized_queries = define_option searches_ini ["customized_queries"] ""
    (list_option (tuple2_option (string_option, QueryOption.t)))
  [ 
    "Complex Search", 
    Q_AND [
      Q_KEYWORDS ("keywords", "");
      Q_MODULE ("Simple Options",
        Q_AND [
          Q_MINSIZE ("Min Size", "");
          Q_MAXSIZE ("Max Size", "");
          Q_MEDIA ("Media", "");
          Q_FORMAT ("Format", "");
        ];
      );
      Q_MODULE ("Mp3 Options",
        Q_AND [
          Q_MP3_ARTIST ("Artist", ""); 
          Q_MP3_ALBUM ("Album", ""); 
          Q_MP3_TITLE ("Title", ""); 
          Q_MP3_BITRATE ("Min Bitrate", ""); 
        ]
      );
    ];
    "Search for mp3s", 
    Q_AND [
      Q_KEYWORDS ("keywords", "");
      Q_MP3_ARTIST ("Artist", ""); 
      Q_MP3_ALBUM ("Album", ""); 
      Q_MP3_TITLE ("Title", ""); 
      Q_MP3_BITRATE ("Min Bitrate", ""); 
      Q_HIDDEN [
        Q_MEDIA ("Media", "Audio");
        Q_FORMAT ("Format", "mp3");
      ]
    ];
    "Search for movies", 
    Q_AND [
      Q_KEYWORDS ("keywords", "");
      Q_HIDDEN [
        Q_MINSIZE ("Min Size", "500000000");
        Q_MEDIA ("Media", "Video");
        Q_FORMAT ("Format", "avi");
      ]
    ];
    "Search for albums",
    Q_AND [
      Q_KEYWORDS ("Keywords", "album");
      Q_HIDDEN [
        Q_ANDNOT (
          Q_MINSIZE ("Min Size", "30000000"),
          Q_FORMAT ("Format", "mp3")
        );
      ]
    ];
  ]
  
module ClientOption = struct
    
    let value_to_client is_friend v =
      match v with
        Options.Module assocs ->
          let get_value name conv = conv (List.assoc name assocs) in
          let network = try
              get_value "client_network" value_to_string
            with _ -> "Donkey"
          in
          let network = network_find_by_name network in
          let c = network_add_client network is_friend assocs in
          c
      | _ -> assert false
          
    let client_to_value client =
      Options.Module (
        ("client_network", string_to_value (client_network client).network_name)
        ::
        (client_to_option client)
      )
      
    let t is_friend =
      define_option_class "Client" (value_to_client is_friend) 
      client_to_value
    ;;
  end
  
let friends = 
  define_option friends_ini ["friends"] 
    "The list of known friends" (list_option (ClientOption.t true)) []
  
let load () = 
  Options.load files_ini;
  Options.load servers_ini;
  Options.load searches_ini;
  Options.load friends_ini
  
let save () = 
  servers =:= server_sort ();
  
  Options.save_with_help files_ini;
  Options.save_with_help searches_ini;
  Options.save_with_help friends_ini;
  Options.save_with_help servers_ini

(*************  ADD/REMOVE FUNCTIONS ************)
  
let file_commit file =
  let impl = as_file_impl file in
  if impl.impl_file_state = FileDownloaded then begin
      update_file_state impl FileShared;
      done_files =:= List2.removeq file !!done_files;
      impl.impl_file_ops.op_file_commit impl.impl_file_val;
    end
  
let file_cancel file =
  let impl = as_file_impl file in

  if impl.impl_file_state <> FileCancelled then begin
      update_file_state impl FileCancelled;
      impl.impl_file_ops.op_file_cancel impl.impl_file_val;
      files =:= List2.removeq file !!files;
      Hashtbl.remove com_files_by_num impl.impl_file_num
    end
  
let file_completed (file : file) =
  let impl = as_file_impl file in
  if impl.impl_file_state = FileDownloading then begin
      files =:= List2.removeq file !!files;
      done_files =:= file :: !!done_files;
      let sh = CommonShared.new_shared (file_disk_name file) in
      update_file_state impl FileDownloaded;  
    end
    
let file_add impl state = 
  let file = as_file impl in
  if impl.impl_file_state = FileNew then begin
      Printf.printf "update file num"; print_newline ();
      update_file_num impl;
      (match state with
          FileDownloaded -> 
            done_files =:= file :: !!done_files;
        | FileShared
        | FileNew
        | FileCancelled -> ()
        | FileDownloading
        | FilePaused -> 
            files =:= file :: !!files);
      update_file_state impl state
    end
  
let server_remove server =
  let impl = as_server_impl server in
  if impl.impl_server_state <> RemovedHost then begin
      set_server_state server RemovedHost;
      (try impl.impl_server_ops.op_server_remove impl.impl_server_val
          with _ -> ());
      servers =:= List2.removeq server !!servers;
      Hashtbl.remove com_servers_by_num impl.impl_server_num;
    end
  
let server_add impl =
  let server = as_server impl in
  if impl.impl_server_state = NewHost then begin
      server_update_num impl;
      servers =:= server :: !!servers;
      impl.impl_server_state <- NotConnected;
    end

let friend_add c =
  Printf.printf "friend add"; print_newline ();
  let impl = as_client_impl c in
  match impl.impl_client_type with
    FriendClient -> 
      Printf.printf "Already a friend"; print_newline ();
  | _ ->
      impl.impl_client_type <- FriendClient;
      client_must_update c;
      friends =:= c :: !!friends;
      impl.impl_client_ops.op_client_set_friend impl.impl_client_val

let friend_remove c =
  let impl = as_client_impl c in
  match  impl.impl_client_type with 
    FriendClient ->
      impl.impl_client_type <- ContactClient;
      client_must_update c;
      friends =:= List2.removeq c !!friends;
      impl.impl_client_ops.op_client_remove_friend impl.impl_client_val
  | _ -> ()
  