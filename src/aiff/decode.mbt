// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Sample encoding resolved from the `COMM` chunk and the AIFC compression
/// type.
priv enum SampleCodec {
  Pcm8
  Pcm16
  Pcm24
  Pcm32
  Float32
  Float64
}

///|
/// Number of bytes one sample occupies on disk.
fn SampleCodec::width(self : SampleCodec) -> Int32 {
  match self {
    Pcm8 => 1
    Pcm16 => 2
    Pcm24 => 3
    Pcm32 => 4
    Float32 => 4
    Float64 => 8
  }
}

///|
/// Sample format exposed to callers for a codec.
fn SampleCodec::to_sample_format(self : SampleCodec) -> @audio.SampleFormat {
  match self {
    Pcm8 => @audio.U8
    Pcm16 => @audio.I16
    Pcm24 => @audio.I24
    Pcm32 => @audio.I32
    Float32 => @audio.F32
    Float64 => @audio.F64
  }
}

///|
/// Parsed `COMM` chunk.
priv struct CommChunk {
  channels : Int32
  frames : Int32
  bits : Int32
  sample_rate : Int32
  compression : String
  codec : SampleCodec
  little_endian : Bool
}

///|
/// One pass over the container: the public metadata plus the location of the
/// sample bytes inside `SSND`.
priv struct AiffScan {
  info : AiffInfo
  data_offset : Int32
  codec : SampleCodec
  little_endian : Bool
}

///|
/// Decode an AIFF/AIFC file into an [`@audio.AudioBuffer`].
pub fn decode(bytes : Bytes) -> @audio.AudioBuffer raise @audio.AudioError {
  let parsed = parse(bytes)
  parsed.audio
}

///|
/// Parse an AIFF/AIFC file: metadata plus decoded audio.
pub fn parse(bytes : Bytes) -> AiffFile raise @audio.AudioError {
  let scan = scan_file(bytes)
  let audio = decode_samples(bytes, scan)
  AiffFile::{ info: scan.info, audio, }
}

///|
/// Parse only the metadata of an AIFF/AIFC file, without decoding samples.
pub fn parse_info(bytes : Bytes) -> AiffInfo raise @audio.AudioError {
  scan_file(bytes).info
}

///|
/// Walk the container once and resolve `COMM`, the text chunks and the `SSND`
/// payload.
fn scan_file(bytes : Bytes) -> AiffScan raise @audio.AudioError {
  @audio.require_bytes(bytes, 0, 12, "FORM header")
  if !@audio.ascii_is(bytes, 0, 4, "FORM") {
    raise @audio.Unsupported("not an AIFF/AIFC file")
  }
  let is_aifc = @audio.ascii_is(bytes, 8, 4, "AIFC")
  if !is_aifc && !@audio.ascii_is(bytes, 8, 4, "AIFF") {
    raise @audio.Unsupported("FORM type is neither AIFF nor AIFC")
  }
  let chunks = walk_chunks(bytes)
  let mut comm : CommChunk? = None
  let mut sound_payload = -1
  let mut sound_size = 0
  let metadata : Array[(String, String)] = []
  for chunk in chunks {
    let id = chunk.0
    let payload = chunk.1
    let size = chunk.2
    if id == "COMM" && comm is None {
      comm = Some(parse_comm(bytes, payload, size, is_aifc))
    } else if id == "SSND" && sound_payload < 0 {
      sound_payload = payload
      sound_size = size
    } else if is_text_chunk(id) {
      let value = match @audio.ascii_at(bytes, payload, size) {
        Some(text) => trim_padding(text)
        None => ""
      }
      metadata.push((id, value))
    }
  }
  let comm = match comm {
    Some(comm) => comm
    None => raise @audio.Invalid("missing COMM chunk")
  }
  if sound_payload < 0 {
    raise @audio.Invalid("missing SSND chunk")
  }
  if sound_size < 8 {
    raise @audio.Invalid("SSND chunk is \{sound_size} bytes, need at least 8")
  }
  let declared_offset = @audio.read_u32be(bytes, sound_payload)
  let available = sound_size - 8
  if declared_offset > available.to_int64() {
    raise @audio.Invalid(
      "SSND offset \{declared_offset} leaves the \{available} byte payload",
    )
  }
  let offset = declared_offset.to_int()
  let data_offset = sound_payload + 8 + offset
  let data_size = available - offset
  let width = comm.codec.width()
  let frame_bytes = width * comm.channels
  let frames_available = data_size / frame_bytes
  let frames = if comm.frames < frames_available {
    comm.frames
  } else {
    frames_available
  }
  AiffScan::{
    info: AiffInfo::{
      sample_rate: comm.sample_rate,
      channels: comm.channels,
      frames,
      format: comm.codec.to_sample_format(),
      bits_per_sample: comm.bits,
      compression: comm.compression,
      is_aifc,
      chunks,
      metadata,
    },
    data_offset,
    codec: comm.codec,
    little_endian: comm.little_endian,
  }
}

///|
/// Enumerate the chunks of a `FORM` container.
///
/// The walker is padding safe: a chunk with an odd payload length is followed
/// by one pad byte, so the next header starts at the next even offset. A
/// truncated final chunk keeps its usable length and ends the walk.
fn walk_chunks(
  bytes : Bytes,
) -> Array[(String, Int32, Int32)] raise @audio.AudioError {
  let chunks : Array[(String, Int32, Int32)] = []
  let limit = bytes.length()
  let mut offset = 12
  while offset + 8 <= limit {
    let id = @audio.read_ascii(bytes, offset, 4)
    let declared = @audio.read_u32be(bytes, offset + 4)
    let payload = offset + 8
    let available = limit - payload
    if available < 0 {
      break
    }
    let mut size = if declared > 0x7FFFFFFFL {
      available
    } else {
      declared.to_int()
    }
    if size > available {
      size = available
    }
    chunks.push((id, payload, size))
    offset = payload + size + (size & 1)
  }
  chunks
}

///|
/// `true` when `id` names a chunk that carries a text value.
fn is_text_chunk(id : String) -> Bool {
  id == "NAME" || id == "AUTH" || id == "(c) " || id == "(C) " || id == "ANNO"
}

///|
/// Parse a `COMM` chunk payload.
fn parse_comm(
  bytes : Bytes,
  offset : Int32,
  size : Int32,
  is_aifc : Bool,
) -> CommChunk raise @audio.AudioError {
  let minimum = if is_aifc { 22 } else { 18 }
  if size < minimum {
    raise @audio.Invalid(
      "COMM chunk is \{size} bytes, need at least \{minimum}",
    )
  }
  let channels = @audio.read_u16be(bytes, offset)
  let frame_count = @audio.read_u32be(bytes, offset + 2)
  let bits = @audio.read_u16be(bytes, offset + 6)
  let rate = ext_float_to_double(bytes, offset + 8)
  if channels <= 0 {
    raise @audio.Invalid("COMM declares \{channels} channels")
  }
  if frame_count > 0x7FFFFFFFL {
    raise @audio.Invalid(
      "COMM declares \{frame_count} frames, beyond a 32 bit frame count",
    )
  }
  if rate <= 0.0 || rate > 2147483647.0 {
    raise @audio.Invalid("COMM declares an unusable sample rate of \{rate}")
  }
  let sample_rate = rate.round().to_int()
  if sample_rate <= 0 {
    raise @audio.Invalid("COMM sample rate rounds down to 0 Hz")
  }
  let compression = if is_aifc {
    @audio.read_ascii(bytes, offset + 18, 4)
  } else {
    "NONE"
  }
  let (codec, little_endian) = resolve_codec(compression, bits)
  CommChunk::{
    channels,
    frames: frame_count.to_int(),
    bits,
    sample_rate,
    compression,
    codec,
    little_endian,
  }
}

///|
/// Map an AIFC compression type and `sampleSize` onto a codec.
fn resolve_codec(
  compression : String,
  bits : Int32,
) -> (SampleCodec, Bool) raise @audio.AudioError {
  if compression == "NONE" || compression == "twos" {
    (pcm_codec(bits), false)
  } else if compression == "sowt" {
    (pcm_codec(bits), true)
  } else if compression == "raw " {
    if bits != 8 {
      raise @audio.Unsupported(
        "AIFC compression \"raw \" with \{bits} bits per sample",
      )
    }
    (Pcm8, false)
  } else if compression == "fl32" || compression == "FL32" {
    if bits != 32 {
      raise @audio.Unsupported(
        "AIFC compression \"\{compression}\" with \{bits} bits per sample",
      )
    }
    (Float32, false)
  } else if compression == "fl64" || compression == "FL64" {
    if bits != 64 {
      raise @audio.Unsupported(
        "AIFC compression \"\{compression}\" with \{bits} bits per sample",
      )
    }
    (Float64, false)
  } else {
    raise @audio.Unsupported("AIFC compression type \"\{compression}\"")
  }
}

///|
/// Resolve a plain PCM `sampleSize` to a codec.
fn pcm_codec(bits : Int32) -> SampleCodec raise @audio.AudioError {
  match bits {
    8 => Pcm8
    16 => Pcm16
    24 => Pcm24
    32 => Pcm32
    _ => raise @audio.Unsupported("PCM with \{bits} bits per sample")
  }
}

///|
/// Decode the samples described by `scan` into an interleaved buffer.
fn decode_samples(
  bytes : Bytes,
  scan : AiffScan,
) -> @audio.AudioBuffer raise @audio.AudioError {
  let info = scan.info
  let width = scan.codec.width()
  let frame_bytes = width * info.channels
  let data : Array[Double] = Array::make(info.frames * info.channels, 0.0)
  for frame = 0; frame < info.frames; frame = frame + 1 {
    let base = scan.data_offset + frame * frame_bytes
    for channel = 0; channel < info.channels; channel = channel + 1 {
      let at = base + channel * width
      data[frame * info.channels + channel] = read_sample(
        bytes,
        at,
        scan.codec,
        scan.little_endian,
      )
    }
  }
  @audio.AudioBuffer::{
    sample_rate: info.sample_rate,
    channels: info.channels,
    data,
  }
}

///|
/// Decode one sample at `offset`.
fn read_sample(
  bytes : Bytes,
  offset : Int32,
  codec : SampleCodec,
  little_endian : Bool,
) -> Double raise @audio.AudioError {
  match codec {
    Pcm8 => @audio.sign_extend(bytes.at(offset).to_int(), 8).to_double() / 128.0
    Pcm16 => {
      let raw = if little_endian {
        @audio.read_i16le(bytes, offset)
      } else {
        @audio.read_i16be(bytes, offset)
      }
      raw.to_double() / 32768.0
    }
    Pcm24 => {
      let raw = if little_endian {
        @audio.read_i24le(bytes, offset)
      } else {
        @audio.read_i24be(bytes, offset)
      }
      raw.to_double() / 8388608.0
    }
    Pcm32 => {
      let raw = if little_endian {
        @audio.read_i32le(bytes, offset)
      } else {
        @audio.read_i32be(bytes, offset)
      }
      raw.to_double() / 2147483648.0
    }
    Float32 => @audio.read_f32be(bytes, offset)
    Float64 => @audio.read_f64be(bytes, offset)
  }
}

///|
/// Trim trailing NUL and space padding from a text chunk value.
fn trim_padding(text : String) -> String {
  let mut end = text.length()
  while end > 0 {
    let last = text.at(end - 1)
    if last == 0 || last == 32 {
      end = end - 1
    } else {
      break
    }
  }
  if end == text.length() {
    text
  } else {
    text[0:end].to_owned()
  }
}
