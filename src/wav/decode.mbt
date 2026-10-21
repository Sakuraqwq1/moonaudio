// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Parsed `fmt ` chunk.
priv struct FmtChunk {
  format_tag : Int32
  channels : Int32
  sample_rate : Int32
  byte_rate : Int64
  block_align : Int32
  bits_per_sample : Int32
  valid_bits : Int32
  channel_mask : Int64
  extensible : Bool
  codec : Codec
}

///|
/// Sample codec behind a `fmt ` tag, after resolution of the extensible
/// sub-format.
priv enum Codec {
  PcmU8
  PcmI16
  PcmI24
  PcmI32
  Float32
  Float64
  MuLaw
  ALaw
}

///|
/// `true` when the first four bytes spell `RIFF`, `RIFX` or `RF64`.
fn riff_kind(bytes : Bytes) -> String? {
  if @audio.ascii_is(bytes, 0, 4, "RIFF") {
    Some("riff")
  } else if @audio.ascii_is(bytes, 0, 4, "RIFX") {
    Some("rifx")
  } else if @audio.ascii_is(bytes, 0, 4, "RF64") {
    Some("rf64")
  } else {
    None
  }
}

///|
/// Decode a WAV file into an [`@audio.AudioBuffer`].
pub fn decode(bytes : Bytes) -> @audio.AudioBuffer raise @audio.AudioError {
  let parsed = parse(bytes)
  parsed.audio
}

///|
/// Parse a WAV file: metadata plus decoded audio.
pub fn parse(bytes : Bytes) -> WavFile raise @audio.AudioError {
  let info = parse_info(bytes)
  @audio.require_bytes(bytes, 0, 12, "RIFF header")
  let big_endian = match riff_kind(bytes) {
    Some("rifx") => true
    Some(_) => false
    None => raise @audio.Unsupported("not a RIFF/WAVE file")
  }
  if !@audio.ascii_is(bytes, 8, 4, "WAVE") {
    raise @audio.Invalid("RIFF form is not WAVE")
  }
  let mut fmt : FmtChunk? = None
  let mut data_offset = 0
  let mut data_size = 0
  let mut offset = 12
  let limit = bytes.length()
  while offset + 8 <= limit {
    let id = @audio.read_ascii(bytes, offset, 4)
    let declared = if big_endian {
      @audio.read_u32be(bytes, offset + 4)
    } else {
      @audio.read_u32le(bytes, offset + 4)
    }
    let mut size = declared.to_int()
    if size < 0 || declared > 0x7FFFFFFFL {
      size = limit - offset - 8
    }
    let payload = offset + 8
    let available = limit - payload
    if available < 0 {
      break
    }
    let usable = if size > available { available } else { size }
    if id == "fmt " {
      fmt = Some(parse_fmt(bytes, payload, usable, big_endian))
    } else if id == "data" {
      if data_size == 0 {
        data_offset = payload
        data_size = usable
      }
    }
    let advance = usable + (usable & 1)
    if advance <= 0 {
      break
    }
    offset = payload + advance
  }
  let fmt = match fmt {
    Some(fmt) => fmt
    None => raise @audio.Invalid("missing fmt chunk")
  }
  if fmt.channels <= 0 {
    raise @audio.Invalid("fmt declares \{fmt.channels} channels")
  }
  if fmt.sample_rate <= 0 {
    raise @audio.Invalid("fmt declares \{fmt.sample_rate} Hz")
  }
  if data_size == 0 {
    raise @audio.Invalid("missing data chunk")
  }
  let audio = decode_samples(
    bytes,
    data_offset,
    data_size,
    fmt,
    big_endian,
    info.frames,
  )
  WavFile::{ info, audio, }
}

///|
/// Parse only the metadata of a WAV file, without decoding samples.
pub fn parse_info(bytes : Bytes) -> WavInfo raise @audio.AudioError {
  @audio.require_bytes(bytes, 0, 12, "RIFF header")
  let big_endian = match riff_kind(bytes) {
    Some("rifx") => true
    Some(_) => false
    None => raise @audio.Unsupported("not a RIFF/WAVE file")
  }
  if !@audio.ascii_is(bytes, 8, 4, "WAVE") {
    raise @audio.Invalid("RIFF form is not WAVE")
  }
  let chunks : Array[ChunkRef] = []
  let metadata : Array[(String, String)] = []
  let mut fmt : FmtChunk? = None
  let mut frames = 0
  let mut offset = 12
  let limit = bytes.length()
  while offset + 8 <= limit {
    let id = @audio.read_ascii(bytes, offset, 4)
    let declared = if big_endian {
      @audio.read_u32be(bytes, offset + 4)
    } else {
      @audio.read_u32le(bytes, offset + 4)
    }
    let mut size = declared.to_int()
    if size < 0 || declared > 0x7FFFFFFFL {
      size = limit - offset - 8
    }
    let payload = offset + 8
    let available = limit - payload
    if available < 0 {
      break
    }
    let usable = if size > available { available } else { size }
    chunks.push(ChunkRef::{ id, offset: payload, size: usable, })
    if id == "fmt " {
      fmt = Some(parse_fmt(bytes, payload, usable, big_endian))
    } else if id == "data" {
      if usable > 0 {
        let block_align = match fmt {
          Some(parsed) => parsed.block_align
          None => 0
        }
        if block_align > 0 {
          frames = frames + usable / block_align
        }
      }
    } else if id == "LIST" {
      collect_info(bytes, payload, usable, big_endian, metadata)
    }
    let advance = usable + (usable & 1)
    if advance <= 0 {
      break
    }
    offset = payload + advance
  }
  let fmt = match fmt {
    Some(fmt) => fmt
    None => raise @audio.Invalid("missing fmt chunk")
  }
  if fmt.channels <= 0 {
    raise @audio.Invalid("fmt declares \{fmt.channels} channels")
  }
  if fmt.sample_rate <= 0 {
    raise @audio.Invalid("fmt declares \{fmt.sample_rate} Hz")
  }
  WavInfo::{
    sample_rate: fmt.sample_rate,
    channels: fmt.channels,
    frames,
    format: fmt.codec.to_sample_format(),
    format_tag: fmt.format_tag,
    bits_per_sample: fmt.bits_per_sample,
    valid_bits: fmt.valid_bits,
    channel_mask: fmt.channel_mask,
    byte_rate: fmt.byte_rate,
    extensible: fmt.extensible,
    chunks,
    metadata,
  }
}

///|
/// Parse a `fmt ` chunk payload.
fn parse_fmt(
  bytes : Bytes,
  offset : Int32,
  size : Int32,
  big_endian : Bool,
) -> FmtChunk raise @audio.AudioError {
  if size < 16 {
    raise @audio.Invalid("fmt chunk is \{size} bytes, need at least 16")
  }
  let tag = if big_endian {
    @audio.read_u16be(bytes, offset)
  } else {
    @audio.read_u16le(bytes, offset)
  }
  let channels = if big_endian {
    @audio.read_u16be(bytes, offset + 2)
  } else {
    @audio.read_u16le(bytes, offset + 2)
  }
  let sample_rate_u = if big_endian {
    @audio.read_u32be(bytes, offset + 4)
  } else {
    @audio.read_u32le(bytes, offset + 4)
  }
  let byte_rate = if big_endian {
    @audio.read_u32be(bytes, offset + 8)
  } else {
    @audio.read_u32le(bytes, offset + 8)
  }
  let bits = if big_endian {
    @audio.read_u16be(bytes, offset + 14)
  } else {
    @audio.read_u16le(bytes, offset + 14)
  }
  let mut effective_tag = tag
  let mut extensible = false
  let mut valid_bits = bits
  let mut channel_mask = 0L
  if tag == 0xFFFE && size >= 40 {
    extensible = true
    valid_bits = if big_endian {
      @audio.read_u16be(bytes, offset + 18)
    } else {
      @audio.read_u16le(bytes, offset + 18)
    }
    channel_mask = if big_endian {
      @audio.read_u32be(bytes, offset + 20)
    } else {
      @audio.read_u32le(bytes, offset + 20)
    }
    effective_tag = if big_endian {
      @audio.read_u16be(bytes, offset + 24)
    } else {
      @audio.read_u16le(bytes, offset + 24)
    }
  }
  if bits <= 0 || bits % 8 != 0 {
    raise @audio.Unsupported("sample width of \{bits} bits is not byte aligned")
  }
  if valid_bits <= 0 || valid_bits > bits {
    valid_bits = bits
  }
  let codec = resolve_codec(effective_tag, bits)
  let block_align = channels * (bits / 8)
  FmtChunk::{
    format_tag: tag,
    channels,
    sample_rate: sample_rate_u.to_int(),
    byte_rate,
    block_align,
    bits_per_sample: bits,
    valid_bits,
    channel_mask,
    extensible,
    codec,
  }
}

///|
/// Map a resolved `wFormatTag` and width onto a [`Codec`].
fn resolve_codec(tag : Int32, bits : Int32) -> Codec raise @audio.AudioError {
  if tag == 1 {
    if bits == 8 {
      Codec::PcmU8
    } else if bits == 16 {
      Codec::PcmI16
    } else if bits == 24 {
      Codec::PcmI24
    } else if bits == 32 {
      Codec::PcmI32
    } else {
      raise @audio.Unsupported("PCM with \{bits} bits per sample")
    }
  } else if tag == 3 {
    if bits == 32 {
      Codec::Float32
    } else if bits == 64 {
      Codec::Float64
    } else {
      raise @audio.Unsupported("IEEE float with \{bits} bits per sample")
    }
  } else if tag == 6 {
    Codec::ALaw
  } else if tag == 7 {
    Codec::MuLaw
  } else {
    raise @audio.Unsupported("WAV format tag \{tag}")
  }
}

///|
/// Sample format exposed to callers for a codec.
fn Codec::to_sample_format(self : Codec) -> @audio.SampleFormat {
  match self {
    PcmU8 => @audio.U8
    PcmI16 => @audio.I16
    PcmI24 => @audio.I24
    PcmI32 => @audio.I32
    Float32 => @audio.F32
    Float64 => @audio.F64
    MuLaw => @audio.I16
    ALaw => @audio.I16
  }
}

///|
/// Decode `size` bytes of sample data into an interleaved buffer.
fn decode_samples(
  bytes : Bytes,
  offset : Int32,
  size : Int32,
  fmt : FmtChunk,
  big_endian : Bool,
  _frames_hint : Int32,
) -> @audio.AudioBuffer raise @audio.AudioError {
  let width = fmt.bits_per_sample / 8
  let frame_bytes = width * fmt.channels
  if frame_bytes <= 0 {
    raise @audio.Invalid("invalid frame layout")
  }
  let frames = size / frame_bytes
  let data : Array[Double] = Array::make(frames * fmt.channels, 0.0)
  let shift = fmt.bits_per_sample - fmt.valid_bits
  for frame = 0; frame < frames; frame = frame + 1 {
    let base = offset + frame * frame_bytes
    for channel = 0; channel < fmt.channels; channel = channel + 1 {
      let at = base + channel * width
      let value = read_sample(bytes, at, fmt.codec, big_endian, shift)
      data[frame * fmt.channels + channel] = value
    }
  }
  @audio.AudioBuffer::{
    sample_rate: fmt.sample_rate,
    channels: fmt.channels,
    data,
  }
}

///|
/// Decode one sample at `offset`.
fn read_sample(
  bytes : Bytes,
  offset : Int32,
  codec : Codec,
  big_endian : Bool,
  shift : Int32,
) -> Double raise @audio.AudioError {
  match codec {
    PcmU8 => (bytes.at(offset).to_int().to_double() - 128.0) / 128.0
    PcmI16 => {
      let raw = if big_endian {
        @audio.read_i16be(bytes, offset)
      } else {
        @audio.read_i16le(bytes, offset)
      }
      raw.to_double() / 32768.0
    }
    PcmI24 => {
      let raw = if big_endian {
        @audio.read_i24be(bytes, offset)
      } else {
        @audio.read_i24le(bytes, offset)
      }
      (raw >> shift).to_double() / 8388608.0
    }
    PcmI32 => {
      let raw = if big_endian {
        @audio.read_i32be(bytes, offset)
      } else {
        @audio.read_i32le(bytes, offset)
      }
      (raw >> shift).to_double() / 2147483648.0
    }
    Float32 =>
      if big_endian {
        @audio.read_f32be(bytes, offset)
      } else {
        @audio.read_f32le(bytes, offset)
      }
    Float64 =>
      if big_endian {
        @audio.read_f64be(bytes, offset)
      } else {
        @audio.read_f64le(bytes, offset)
      }
    MuLaw => @audio.mulaw_decode(bytes.at(offset).to_int())
    ALaw => @audio.alaw_decode(bytes.at(offset).to_int())
  }
}

///|
/// Collect `LIST/INFO` sub-chunks into `target`.
fn collect_info(
  bytes : Bytes,
  offset : Int32,
  size : Int32,
  big_endian : Bool,
  target : Array[(String, String)],
) -> Unit raise @audio.AudioError {
  if size < 4 || !@audio.ascii_is(bytes, offset, 4, "INFO") {
    return
  }
  let mut cursor = offset + 4
  let end = offset + size
  while cursor + 8 <= end {
    let key = match @audio.ascii_at(bytes, cursor, 4) {
      Some(key) => key
      None => break
    }
    let declared = if big_endian {
      @audio.read_u32be(bytes, cursor + 4)
    } else {
      @audio.read_u32le(bytes, cursor + 4)
    }
    let mut length = declared.to_int()
    let payload = cursor + 8
    let available = end - payload
    if length < 0 || length > available {
      length = available
    }
    let value = match @audio.ascii_at(bytes, payload, length) {
      Some(text) => trim_nul(text)
      None => ""
    }
    target.push((key, value))
    let advance = length + (length & 1)
    if advance <= 0 {
      break
    }
    cursor = payload + advance
  }
}

///|
/// Trim trailing NUL and space padding from an INFO value.
fn trim_nul(text : String) -> String {
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
