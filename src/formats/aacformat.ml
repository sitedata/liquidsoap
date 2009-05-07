(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2009 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 *****************************************************************************)

(** Decode and read metadatas of AAC files. *)

module Generator = Float_pcm.Generator

let buflen = 1024

let decoder file =
  let dec = Faad.create () in
  let fd = Unix.openfile file [Unix.O_RDONLY] 0o644 in
  let abg = Generator.create () in
  let buffer_length = Decoder.buffer_length () in
  let aacbuflen = 1024 in
  let aacbuf = String.create aacbuflen in
  let aacbufpos = ref aacbuflen in
  let fill_aacbuf () =
    String.blit aacbuf !aacbufpos aacbuf 0 (aacbuflen - !aacbufpos);
    let n = Unix.read fd aacbuf (aacbuflen - !aacbufpos) !aacbufpos in
    let n = !aacbufpos + n in
      aacbufpos := 0;
      n
  in

  (* Dummy decoding in order to test format. *)
  let () =
    let offset, _, _ = Faad.init dec aacbuf 0 (Unix.read fd aacbuf 0 aacbuflen) in
    ignore (Unix.lseek fd offset Unix.SEEK_SET);
    let aacbuflen = fill_aacbuf () in
      if aacbuflen = 0 then raise End_of_file;
      if aacbuf.[0] <> '\255' then raise End_of_file;
      ignore (Faad.decode dec aacbuf 0 aacbuflen);
      ignore (Unix.lseek fd 0 Unix.SEEK_SET)
  in

  let offset, sample_freq, chans =
    Faad.init dec aacbuf 0 (Unix.read fd aacbuf 0 aacbuflen)
  in
  aacbufpos := aacbuflen;
  ignore (Unix.lseek fd offset Unix.SEEK_SET);

  let closed = ref false in
  let close () =
    assert (not !closed) ;
    closed := true ;
    Faad.close dec;
    Unix.close fd
  in

  let fill buf =
    assert (not !closed) ;

    begin
      try
        while Generator.length abg < buffer_length do
          try
            let aacbuflen = fill_aacbuf () in
              if aacbuflen = 0 then raise End_of_file;
              if aacbuf.[0] <> '\255' then raise End_of_file;
              let pos, buf = Faad.decode dec aacbuf 0 aacbuflen in
                aacbufpos := pos;
                Generator.feed abg ~sample_freq buf
          with
            | Faad.Error n ->
                Printf.printf "Faad error: %s\n%!" (Faad.error_message n)
        done
      with _ -> () (* TODO: log the error *)
    end ;

    (*
    let offset = AFrame.position buf in
    *)
      Float_pcm.Generator.fill abg buf ;
    (*
      in_bytes := Unix.lseek fd 0 Unix.SEEK_CUR ;
      out_samples := !out_samples + AFrame.position buf - offset ;
      (* Compute an estimated number of remaining ticks. *)
      let abglen = Generator.length abg in
        assert (!in_bytes!=0) ;
        let compression =
          (float (!out_samples+abglen)) /. (float !in_bytes)
        in
        let remaining_samples =
          (float (file_size - !in_bytes)) *. compression
          +. (float abglen)
        in
          (* I suspect that in_bytes in not accurate, since I don't
           * get an exact countdown after than in_size=in_bytes, but there
           * is a stall at the beginning after which the countdown starts. *)
          Fmt.ticks_of_samples (int_of_float remaining_samples)
     *)
    0
  in
    { Decoder.fill = fill ; Decoder.close = close }

let decoder_mp4 file =
  let dec = Faad.create () in
  let fd = Unix.openfile file [Unix.O_RDONLY] 0o644 in
  let mp4 = Faad.Mp4.openfile_fd fd in

  let abg = Generator.create () in
  let buffer_length = Decoder.buffer_length () in

  let track = Faad.Mp4.find_aac_track mp4 in
  let sample_freq, chans = Faad.Mp4.init mp4 dec track in
  let samples = Faad.Mp4.samples mp4 track in
  let sample = ref 0 in

  let closed = ref false in
  let close () =
    assert (not !closed) ;
    closed := true ;
    Faad.close dec;
    Unix.close fd
  in

  let fill buf =
    assert (not !closed) ;

    begin
      try
        while Generator.length abg < buffer_length do
          try
            if !sample >= samples then raise End_of_file;
            Generator.feed abg ~sample_freq (Faad.Mp4.decode mp4 track !sample dec);
            incr sample
          with
            | Faad.Error n ->
                Printf.printf "Faad error: %s\n%!" (Faad.error_message n)
        done
      with _ -> () (* TODO: log the error *)
    end ;

    (* TODO: duration *)
    (*
    let offset = AFrame.position buf in
    *)
      Float_pcm.Generator.fill abg buf ;
    (*
      in_bytes := Unix.lseek fd 0 Unix.SEEK_CUR ;
      out_samples := !out_samples + AFrame.position buf - offset ;
      (* Compute an estimated number of remaining ticks. *)
      let abglen = Generator.length abg in
        assert (!in_bytes!=0) ;
        let compression =
          (float (!out_samples+abglen)) /. (float !in_bytes)
        in
        let remaining_samples =
          (float (file_size - !in_bytes)) *. compression
          +. (float abglen)
        in
          (* I suspect that in_bytes in not accurate, since I don't
           * get an exact countdown after than in_size=in_bytes, but there
           * is a stall at the beginning after which the countdown starts. *)
          Fmt.ticks_of_samples (int_of_float remaining_samples)
     *)
    0
  in
    { Decoder.fill = fill ; Decoder.close = close }

let () =
  Decoder.formats#register "AAC"
    (fun name -> try Some (decoder name) with _ -> None);
  Decoder.formats#register "AACMP4"
    (fun name -> try Some (decoder_mp4 name) with _ -> None)
