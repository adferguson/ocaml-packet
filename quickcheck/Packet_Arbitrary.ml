open Packet
open QuickCheck
module Gen = QuickCheck_gen

(* arbitrary first `b` bits set in an Int32 *)
let arbitrary_uint32_bits b =
  Gen.choose_int32 (Int32.zero, Int32.of_int ((0x1 lsl b) - 1) )

(* arbitrary instance for uint3, using the `int32` type. *)
let arbitrary_uint4 = arbitrary_uint32_bits 4

(* arbitrary instance for uint8, using the `int32` type. *)
let arbitrary_uint8 = arbitrary_uint32_bits 8

(* arbitrary instance for uint12, using the `int32` type. *)
let arbitrary_uint12 = arbitrary_uint32_bits 12

(* arbitrary instance for uint16, using the `int32` type. *)
let arbitrary_uint16 = arbitrary_uint32_bits 16

(* arbitrary instance for uint32, using the `int32` type. *)
let arbitrary_uint32 =
  let open Gen in
  arbitrary_uint16 >>= fun w16_1 ->
  arbitrary_uint16 >>= fun w16_2 ->
    ret_gen Int32.(logor (shift_left w16_1 16) w16_2)

let choose_int64 = Gen.lift_gen QuickCheck_util.Random.int64_range

(* arbitrary instance for uint48, using the `int64` type. *)
let arbitrary_int48 =
  choose_int64 (Int64.zero, 0xffffffffffL)

(* arbitrary instance for option type, favoring `Some` rather than `None` *)
let arbitrary_option arb =
  let open Gen in
  frequency [
      (1, ret_gen None);
      (3, arb >>= fun e -> ret_gen (Some e)) ]

let arbitrary_dlAddr = arbitrary_int48
let arbitrary_nwAddr = arbitrary_int32

let arbitrary_dlVlan =
  let open Gen in
  arbitrary_option arbitrary_uint12 >>= fun m_w16 ->
  begin match m_w16 with
    | None     -> ret_gen (None, false, 0x0)
    | Some w16 ->
      arbitrary_uint32_bits 3 >>= fun w4 ->
      arbitrary_bool >>=  fun b ->
          ret_gen (Some (Int32.to_int w16), b, Int32.to_int w4)
  end

let arbitrary_dl_unparsable_len l =
  let li = Int32.to_int l in
  Gen.ret_gen (Unparsable(li, Cstruct.create li))

let arbitrary_dl_unparsable =
  let open Gen in
  Gen.choose_int32 (Int32.zero, Int32.of_int 0x05DC)
    >>= arbitrary_dl_unparsable_len

let arbitrary_packet arbitrary_nw =
  let open Gen in
  arbitrary_dlAddr >>= fun dlSrc ->
  arbitrary_dlAddr >>= fun dlDst ->
  arbitrary_dlVlan >>= fun (dlVlan, dlVlanDei, dlVlanPcp) ->
  arbitrary_nw >>= fun nw ->
    ret_gen {
         dlSrc = dlSrc
       ; dlDst = dlDst
       ; dlVlan = dlVlan
       ; dlVlanDei = dlVlanDei
       ; dlVlanPcp = dlVlanPcp
       ; nw = nw
    }

let arbitrary_arp =
  let open Gen in
  arbitrary_dlAddr >>= fun dlSrc ->
  arbitrary_nwAddr >>= fun nwSrc ->
  arbitrary_nwAddr >>= fun nwDst ->
    oneof [ (ret_gen (Arp.Query(dlSrc, nwSrc, nwDst)))
          ; (arbitrary_dlAddr >>= fun dlDst ->
              ret_gen (Arp.Reply(dlSrc, nwSrc, dlDst, nwDst)))
          ]

let arbitrary_payload max_len =
  let open Gen in
  choose_int32 (Int32.zero, Int32.of_int max_len) >>= fun l ->
    ret_gen (Cstruct.create (Int32.to_int l))

let arbitrary_ip_unparsable =
  let open Gen in
  arbitrary_payload (65535 - 20) >>= fun payload ->
    ret_gen (Ip.Unparsable(12, payload))

let arbitrary_ip_frag =
  Gen.choose_int32 (Int32.zero, Int32.of_int 0b111111111111)

let arbitrary_ip_flags =
  let open Gen in
  arbitrary_bool >>= fun df ->
  arbitrary_bool >>= fun mf ->
    ret_gen { Ip.Flags.df = df; Ip.Flags.mf = mf }


let empty_bytes = Cstruct.create 0

(* Arbitrary IPv4 packet without options. *)
let arbitrary_ip arbitrary_tp =
  let open Gen in
  let open Ip in
  arbitrary_uint8 >>= fun tos ->
  arbitrary_uint16 >>= fun ident ->
  arbitrary_ip_flags >>= fun flags ->
  arbitrary_ip_frag >>= fun frag ->
  arbitrary_uint8 >>= fun ttl ->
  arbitrary_uint16 >>= fun chksum ->
  arbitrary_nwAddr >>= fun nwSrc ->
  arbitrary_nwAddr >>= fun nwDst ->
  arbitrary_tp >>= fun tp ->
    ret_gen {
        tos = Int32.to_int tos
      ; ident = Int32.to_int ident
      ; flags = flags
      ; frag = Int32.to_int frag
      ; ttl = Int32.to_int ttl
      (* Dummy checksum, as the library currently does not verify it *)
      ; chksum = Int32.to_int chksum
      ; src = nwSrc
      ; dst = nwDst
      ; tp = tp
      ; options = empty_bytes
    }

let arbitrary_tpPort = Gen.map_gen Int32.to_int arbitrary_uint16

let arbitrary_tcp_flags =
  let open Gen in
  let open Tcp.Flags in
  arbitrary_bool >>= fun ns ->
  arbitrary_bool >>= fun cwr ->
  arbitrary_bool >>= fun ece ->
  arbitrary_bool >>= fun urg ->
  arbitrary_bool >>= fun ack ->
  arbitrary_bool >>= fun psh ->
  arbitrary_bool >>= fun rst ->
  arbitrary_bool >>= fun syn ->
  arbitrary_bool >>= fun fin ->
    ret_gen {
        ns = ns
      ; cwr = cwr
      ; ece = ece
      ; urg = urg
      ; ack = ack
      ; psh = psh
      ; rst = rst
      ; syn = syn
      ; fin = fin
    }

(* Arbitrary UDP packet *)
let arbitrary_udp arbitrary_payload =
  let open Gen in
  let open Udp in
  arbitrary_tpPort >>= fun src ->
  arbitrary_tpPort >>= fun dst ->
  arbitrary_payload >>= fun payload ->
    ret_gen {
        src = src
      ; dst = dst
      (* Dummy checksum, as the library currently does not verify it *)
      ; chksum = 0
      ; payload = payload
    }

(* Arbitrary TCP packet *)
let arbitrary_tcp arbitrary_payload =
  let open Gen in
  let open Tcp in
  arbitrary_tpPort >>= fun src ->
  arbitrary_tpPort >>= fun dst ->
  arbitrary_uint32 >>= fun seq ->
  arbitrary_uint32 >>= fun ack ->
  arbitrary_uint4 >>= fun offset ->
  arbitrary_tcp_flags >>= fun flags ->
  arbitrary_uint16 >>= fun window ->
  arbitrary_uint8 >>= fun urgent ->
  arbitrary_payload >>= fun payload ->
    ret_gen {
        src = src
      ; dst = dst
      ; seq = seq
      ; ack = ack
      ; offset = Int32.to_int offset
      ; flags = flags
      ; window = Int32.to_int window
      ; chksum = 0
      ; urgent = Int32.to_int urgent
      ; payload = payload
    }
