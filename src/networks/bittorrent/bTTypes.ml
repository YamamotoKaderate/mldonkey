(* Copyright 2001, 2002 b52_simon :), b8_bavard, b8_fee_carabine, INRIA *)
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


open Md4
open CommonTypes
open CommonDownloads
open CommonStats
open BTRate


type torrent = {
    mutable torrent_name : string;
    mutable torrent_name_utf8 : string;
    mutable torrent_filename : string;
    mutable torrent_length : int64;
    mutable torrent_announce : string;
    mutable torrent_announce_list : string list;
    mutable torrent_piece_size : int64;
    mutable torrent_files :  (string * int64) list;
    mutable torrent_pieces : Sha1.t array;
    mutable torrent_comment : string;
    mutable torrent_created_by : string;
    mutable torrent_creation_date : int64;
    mutable torrent_modified_by : string;
    mutable torrent_encoding : string;
    mutable torrent_private : int64;
(*
    mutable torrent_nodes : string;
*)
  }

type brand =
  Brand_unknown
| Brand_abc
| Brand_arctic
| Brand_azureus
| Brand_bitbuddy
| Brand_bitcomet
| Brand_bitkitten
| Brand_bitlord
| Brand_bitsonwheels
| Brand_bitspirit
| Brand_bittornado
| Brand_bittorrentx
| Brand_btplus
| Brand_btslave
| Brand_btugaxp
| Brand_burst
| Brand_ctorrent
| Brand_deadmanwalking
| Brand_exeem
| Brand_experimental
| Brand_g3torrent
| Brand_libtorrent
| Brand_mainline
| Brand_martiniman
| Brand_mldonkey
| Brand_moonlighttorrent
| Brand_plus
| Brand_shadow
| Brand_sharenet
| Brand_shareaza
| Brand_simplebt
| Brand_snark
| Brand_swarmscope
| Brand_swarmy
| Brand_swiftbit
| Brand_teeweety
| Brand_torrentdotnet
| Brand_torrentstorm
| Brand_turbobt
| Brand_upnp
| Brand_xantorrent
| Brand_xbt
| Brand_ziptorrent
| Brand_moopolice
| Brand_utorrent
| Brand_opera
| Brand_torrenttopia
| Brand_greedbt
| Brand_btgetit
| Brand_ktorrent
| Brand_lphant
| Brand_transmission
| Brand_hydranode
| Brand_jvtorrent
| Brand_retriever
| Brand_osprey

let brand_list = [ 
   ( Brand_unknown          , "unknown"                , "unk" ) ;
   ( Brand_abc              , "ABC"                    , "abc" ) ;
   ( Brand_arctic           , "Arctic"                 , "arc" ) ;
   ( Brand_azureus          , "Azureus"                , "azu" ) ;
   ( Brand_bitbuddy         , "Bitbuddy"               , "bud" ) ;
   ( Brand_bitcomet         , "BitComet"               , "com" ) ;
   ( Brand_bitkitten        , "BitKitten (libTorrent)" , "kit" ) ;
   ( Brand_bitlord          , "BitLord"                , "lor" ) ;
   ( Brand_bitsonwheels     , "BitsOnWheels"           , "bow" ) ;
   ( Brand_bitspirit        , "BitSpirit"              , "spi" ) ;
   ( Brand_bittornado       , "BitTornado"             , "trn" ) ;
   ( Brand_bittorrentx      , "BitTorrent X"           , "btx" ) ;
   ( Brand_btplus           , "BitTorrent Plus!"       , "plu" ) ;
   ( Brand_btslave          , "BTSlave"                , "sla" ) ;
   ( Brand_btugaxp          , "BTugaXP"                , "uga" ) ;
   ( Brand_burst            , "Burst !"                , "brs" ) ;
   ( Brand_ctorrent         , "CTorrent"               , "cto" ) ;
   ( Brand_deadmanwalking   , "Deadman Walking"        , "dmw" ) ;
   ( Brand_exeem            , "eXeem"                  , "exm" ) ;
   ( Brand_experimental     , "Experimental"           , "exp" ) ;
   ( Brand_g3torrent        , "G3 Torrent"             , "g3t" ) ;
   ( Brand_libtorrent       , "libTorrent"             , "lib" ) ;
   ( Brand_mainline         , "Mainline"               , "mai" ) ;
   ( Brand_martiniman       , "Martini Man"            , "mar" ) ;
   ( Brand_mldonkey         , "MLdonkey"               , "mld" ) ;
   ( Brand_moonlighttorrent , "MoonlightTorrent"       , "mlt" ) ;
   ( Brand_plus             , "Plus"                   , "plu" ) ;
   ( Brand_shadow           , "Shad0w"                 , "sdo" ) ;
   ( Brand_sharenet         , "Sharenet"               , "shn" ) ;
   ( Brand_shareaza         , "Shareaza"               , "shz" ) ;
   ( Brand_simplebt         , "SimpleBT"               , "sbt" ) ;
   ( Brand_snark            , "Snark"                  , "snk" ) ;
   ( Brand_swarmscope       , "SwarmScope"             , "sws" ) ;
   ( Brand_swarmy           , "Swarmy"                 , "swy" ) ;
   ( Brand_swiftbit         , "SwiftBit"               , "swb" ) ;
   ( Brand_teeweety         , "Teeweety"               , "twt" ) ;
   ( Brand_torrentdotnet    , "Torrent.NET"            , "t.n" ) ;
   ( Brand_torrentstorm     , "TorrentStorm"           , "sto" ) ;
   ( Brand_turbobt          , "TurboBT"                , "tbt" ) ;
   ( Brand_upnp             , "UPNP"                   , "upn" ) ;
   ( Brand_xantorrent       , "XanTorrent"             , "xat" ) ;
   ( Brand_xbt              , "XBT"                    , "xbt" ) ;
   ( Brand_ziptorrent       , "ZipTorrent"             , "zit" ) ;
   ( Brand_moopolice        , "MooPolice"              , "moo" ) ;
   ( Brand_utorrent         , "uTorrent"               , "uTo" ) ;
   ( Brand_opera            , "Opera"                  , "opr" ) ;
   ( Brand_torrenttopia     , "TorrentTopia"           , "tt" ) ;
   ( Brand_greedbt          , "GreedBT"                , "gbt" ) ;
   ( Brand_btgetit          , "BTGetit"                , "btg" ) ;
   ( Brand_ktorrent         , "KTorrent"               , "kto" ) ;
   ( Brand_lphant           , "Lphant"                 , "lph" ) ;
   ( Brand_transmission     , "Transmission"           , "tra" ) ;
   ( Brand_hydranode        , "Hydranode"              , "hyd" ) ;
   ( Brand_jvtorrent        , "JVtorrent"              , "jvt" ) ;
   ( Brand_retriever        , "Retriever"              , "ret" ) ;
   ( Brand_osprey           , "Osprey permaseed"       , "osp" ) ;
  ] 

let brand_count = List.length brand_list

let brand_to_string brand =
  find_brand_to_string brand brand_list false

let brand_to_string_short brand =
  find_brand_to_string brand brand_list true

let brand_to_int brand = 
  find_int_of_brand brand brand_list

type client = {
    client_client : client CommonClient.client_impl;
    mutable client_file : file;
    mutable client_connection_control : connection_control;
    mutable client_sock : tcp_connection;
    mutable client_host : Ip.t * int;
    mutable client_chunks : (int64 * int64) list;
    mutable client_uploader : Int64Swarmer.uploader option;
    mutable client_ranges_sent : (int64 * int64 * Int64Swarmer.range) list;
    mutable client_range_waiting :
    (int64 * int64 * Int64Swarmer.range) option;
    mutable client_block : Int64Swarmer.block option;

    mutable client_received_peer_id : bool;
    mutable client_sent_choke : bool; (* we sent a Choke to the client *)
    mutable client_choked : bool;      (* we received a Choke from the client *)
    mutable client_interested : bool;
    mutable client_uid : Sha1.t;

    mutable client_brand : brand;
    mutable client_release : string;

    mutable client_bitmap : Bitv.t option;
    mutable client_new_chunks : int list;

    mutable client_upload_requests : (int * int64 * int64) list;
    mutable client_allowed_to_write : int64;
    mutable client_upload_rate : Rate.t;
    mutable client_downloaded_rate :  Rate.t;
    mutable client_downloaded : int64;
    mutable client_uploaded : int64;
    mutable client_optimist_time : int;

    mutable client_blocks_sent : int list;
    mutable client_good : bool;
    mutable client_num_try : int;
    mutable client_alrd_sent_interested : bool;
    mutable client_alrd_sent_notinterested : bool;
    mutable client_interesting : bool;
    mutable client_incoming : bool;
    mutable client_registered_bitfield : bool;
    mutable client_last_optimist : int;
  }

and tracker_info = {
    tracker_url : string;
    mutable tracker_interval : int;
    mutable tracker_min_interval : int;
    mutable tracker_last_conn : int;
    mutable tracker_last_clients_num : int;
    mutable tracker_torrent_downloaded : int;
    mutable tracker_torrent_complete : int;
    mutable tracker_torrent_incomplete : int;
    mutable tracker_torrent_total_clients_count : int;
    mutable tracker_torrent_last_dl_req : int;
    mutable tracker_id : string;
    mutable tracker_key : string;
    mutable tracker_enabled : bool;
  }

and file = {
    file_file : file CommonFile.file_impl;
    file_piece_size : int64;
    file_id : Sha1.t;
    file_name : string;
    file_comment : string;
    file_created_by : string;
    file_creation_date : int64;
    file_modified_by : string;
    file_encoding : string;
    mutable file_swarmer : Int64Swarmer.t option;
    mutable file_clients : ((Ip.t*int), client) Hashtbl.t ;
    mutable file_clients_num : int ;
    mutable file_chunks : Sha1.t array;
    mutable file_files : (string * int64) list;
    mutable file_blocks_downloaded : int list;
    (* vvv probably a network specific value vvv ?what about file_downloaded?*)
    mutable file_uploaded : int64;
    mutable file_torrent_diskname : string;
    mutable file_trackers : tracker_info list;
    mutable file_tracker_connected : bool;
    mutable file_completed_hook : (file -> unit);
    mutable file_shared : file CommonShared.shared_impl option;
  }

and ft = {
    ft_file : ft CommonFile.file_impl;
    ft_id : int;
    ft_filename : string;
    mutable ft_retry : (ft -> unit);
  }
