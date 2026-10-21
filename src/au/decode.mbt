// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Size of the fixed Sun/NeXT `.au` header, in bytes.
///
/// A conforming file may put its data further out to make room for an
/// annotation; the fixed part is always these 24 bytes.
let au_header_size : Int32 = 24

///|
/// Everything the decoder needs beyond [`AuInfo`]: the resolved codec and the
/// offset of the sample data.
priv struct AuHeader {
  info : AuInfo
  codec : AuCodec
  data_offset : Int32
}

///|
/// Parse a Sun/NeXT `.au` header, including the optional annotation.
///
/// All six header words are big endian 32 bit unsigned values. A data size of
/// `0xFFFFFFFF` means "until end of file". Every bound is checked here so the
/// per-sample loop cannot read outside the buffer.
fn parse_header(bytes : Bytes) -> AuHeader raise @audio.AudioError {
  @audio.require_bytes(bytes, 0, au_header_size, "Sun/NeXT .au header")
  if !@audio.ascii_is(bytes, 0, 4, ".snd") {
    raise @audio.Unsupported("not a Sun/NeXT .au file: magic is not \".snd\"")
  }
  let offset_field = @audio.read_u32be(bytes, 4)
  let size_field = @audio.read_u32be(bytes, 8)
  let encoding_field = @audio.read_u32be(bytes, 12)
  let rate_field = @audio.read_u32be(bytes, 16)
  let channels_field = @audio.read_u32be(bytes, 20)
  if offset_field < au_header_size.to_int64() {
    raise @audio.Invalid(
      "data offset \{offset_field} is smaller than the \{au_header_size} byte header",
    )
  }
  if offset_field > bytes.length().to_int64() {
    raise @audio.Truncated(
      "data offset \{offset_field} lies past the end of the \{bytes.length()} byte file",
    )
  }
  if rate_field <= 0L || rate_field > 0x7FFFFFFFL {
    raise @audio.Invalid(
      "header declares an invalid sample rate of \{rate_field} Hz",
    )
  }
  if channels_field <= 0L || channels_field > 0x7FFFFFFFL {
    raise @audio.Invalid(
      "header declares an invalid channel count of \{channels_field}",
    )
  }
  let encoding = encoding_field.to_int()
  let codec = AuCodec::resolve(encoding)
  let data_offset = offset_field.to_int()
  let available = bytes.length() - data_offset
  let declared = if size_field == 0xFFFFFFFFL {
    available.to_int64()
  } else {
    size_field
  }
  if declared > available.to_int64() {
    raise @audio.Truncated(
      "data region declares \{declared} byte(s) but only \{available} are present",
    )
  }
  let frame_bytes = channels_field * codec.width().to_int64()
  let frames = (declared / frame_bytes).to_int()
  let annotation = if data_offset > au_header_size {
    trim_annotation(
      @audio.read_ascii(bytes, au_header_size, data_offset - au_header_size),
    )
  } else {
    ""
  }
  let info = AuInfo::{
    sample_rate: rate_field.to_int(),
    channels: channels_field.to_int(),
    frames,
    format: codec.sample_format(),
    encoding,
    encoding_name: codec.name(),
    annotation,
    header_size: data_offset,
  }
  AuHeader::{ info, codec, data_offset, }
}

///|
/// Drop trailing NUL padding from an annotation.
///
/// Annotations are free-form bytes, so they are decoded lossily; trailing NULs
/// are padding written by tools that like NUL terminated strings, and removing
/// them keeps a decode/encode roundtrip byte-for-byte stable.
fn trim_annotation(text : String) -> String {
  let mut end = text.length()
  while end > 0 && text.at(end - 1) == 0 {
    end = end - 1
  }
  if end == text.length() {
    text
  } else {
    text[0:end].to_owned()
  }
}

///|
/// Parse only the metadata of a `.au` file, without decoding samples.
pub fn parse_info(bytes : Bytes) -> AuInfo raise @audio.AudioError {
  parse_header(bytes).info
}

///|
/// Parse a `.au` file: metadata plus decoded samples.
pub fn parse(bytes : Bytes) -> AuFile raise @audio.AudioError {
  let header = parse_header(bytes)
  let audio = decode_samples(bytes, header)
  AuFile::{ info: header.info, audio, }
}

///|
/// Decode a `.au` file into an [`@audio.AudioBuffer`].
pub fn decode(bytes : Bytes) -> @audio.AudioBuffer raise @audio.AudioError {
  parse(bytes).audio
}

///|
/// Decode the data region described by `header` into an interleaved buffer.
fn decode_samples(
  bytes : Bytes,
  header : AuHeader,
) -> @audio.AudioBuffer raise @audio.AudioError {
  let info = header.info
  let channels = info.channels
  let frames = info.frames
  let width = header.codec.width()
  let data : Array[Double] = Array::make(frames * channels, 0.0)
  for frame = 0; frame < frames; frame = frame + 1 {
    let base = header.data_offset + frame * channels * width
    for channel = 0; channel < channels; channel = channel + 1 {
      let at = base + channel * width
      data[frame * channels + channel] = read_sample(bytes, at, header.codec)
    }
  }
  @audio.AudioBuffer::{ sample_rate: info.sample_rate, channels, data, }
}

///|
/// Decode one big endian sample at `offset`.
///
/// Integer widths are scaled by the largest magnitude code that fits the width
/// (`2^(bits-1)`), which is the same convention the WAV decoder uses, so a
/// sample survives a `.au` -> buffer -> `.au` trip within one LSB.
fn read_sample(
  bytes : Bytes,
  offset : Int32,
  codec : AuCodec,
) -> Double raise @audio.AudioError {
  match codec {
    MuLaw => @audio.mulaw_decode(@audio.read_u8(bytes, offset))
    Linear8 =>
      @audio.sign_extend(@audio.read_u8(bytes, offset), 8).to_double() / 128.0
    Linear16 => @audio.dequantize(@audio.read_i16be(bytes, offset), @audio.I16)
    Linear24 => @audio.dequantize(@audio.read_i24be(bytes, offset), @audio.I24)
    Linear32 => @audio.dequantize(@audio.read_i32be(bytes, offset), @audio.I32)
    Float32 => @audio.read_f32be(bytes, offset)
    Float64 => @audio.read_f64be(bytes, offset)
    ALaw => @audio.alaw_decode(@audio.read_u8(bytes, offset))
  }
}
