// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// A metadata block header plus its payload range inside the file.
pub(all) struct MetaBlock {
  /// Block type, 0 STREAMINFO, 4 VORBIS_COMMENT, 6 PICTURE, ...
  kind : Int32
  /// Offset of the block payload in the file.
  offset : Int32
  /// Payload length in bytes.
  length : Int32
  /// `true` for the last block before the first frame.
  last : Bool
}

///|
/// Stream level information taken from the `STREAMINFO` block and any comment
/// blocks.
pub(all) struct FlacInfo {
  sample_rate : Int32
  channels : Int32
  bits_per_sample : Int32
  total_samples : Int64
  min_block_size : Int32
  max_block_size : Int32
  min_frame_size : Int32
  max_frame_size : Int32
  /// MD5 of the unencoded audio, lower case hex (empty when not present).
  md5 : String
  /// `VORBIS_COMMENT` entries, keys as stored by the encoder.
  metadata : Array[(String, String)]
  /// Every metadata block in file order.
  blocks : Array[MetaBlock]
  /// Byte offset of the first audio frame.
  stream_offset : Int32
}

///|
/// A decoded FLAC stream.
pub(all) struct FlacFile {
  info : FlacInfo
  audio : @audio.AudioBuffer
}

///|
/// Look up a Vorbis comment value by key (case sensitive, as stored).
pub fn FlacInfo::meta(self : FlacInfo, key : String) -> String? {
  for entry in self.metadata {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Duration in seconds, or 0 when the stream does not declare a length.
pub fn FlacInfo::duration_seconds(self : FlacInfo) -> Double {
  if self.sample_rate <= 0 || self.total_samples <= 0L {
    0.0
  } else {
    self.total_samples.to_double() / self.sample_rate.to_double()
  }
}

///|
/// Human readable summary used by the CLI and tests.
pub fn FlacInfo::describe(self : FlacInfo) -> String {
  let blocks = self.blocks.length()
  "\{self.sample_rate} Hz, \{self.channels} ch, \{self.bits_per_sample} bit, \{self.total_samples} samples, \{blocks} metadata block(s), md5=\{self.md5}"
}

///|
/// Step one: check the `fLaC` marker and walk the metadata blocks.
pub fn parse_info(bytes : Bytes) -> FlacInfo raise @audio.AudioError {
  if !@audio.ascii_is(bytes, 0, 4, "fLaC") {
    raise @audio.Unsupported("missing fLaC stream marker")
  }
  let blocks : Array[MetaBlock] = []
  let metadata : Array[(String, String)] = []
  let mut offset = 4
  let mut last = false
  let mut stream_info : StreamInfo? = None
  while !last {
    if offset + 4 > bytes.length() {
      raise @audio.Truncated("metadata block header at \{offset}")
    }
    let header = bytes.at(offset).to_int()
    last = (header & 0x80) != 0
    let kind = header & 0x7F
    let length = @audio.read_u24be(bytes, offset + 1)
    let payload = offset + 4
    if length < 0 || payload + length > bytes.length() {
      raise @audio.Truncated("metadata block payload of \{length} bytes")
    }
    blocks.push(MetaBlock::{ kind, offset: payload, length, last, })
    if kind == 0 {
      if length < 34 {
        raise @audio.Invalid("STREAMINFO block is \{length} bytes, need 34")
      }
      stream_info = Some(parse_stream_info(bytes, payload))
    } else if kind == 4 {
      parse_vorbis_comment(bytes, payload, length, metadata)
    }
    offset = payload + length
  }
  let stream = match stream_info {
    Some(info) => info
    None => raise @audio.Invalid("missing STREAMINFO block")
  }
  FlacInfo::{
    sample_rate: stream.sample_rate,
    channels: stream.channels,
    bits_per_sample: stream.bits_per_sample,
    total_samples: stream.total_samples,
    min_block_size: stream.min_block_size,
    max_block_size: stream.max_block_size,
    min_frame_size: stream.min_frame_size,
    max_frame_size: stream.max_frame_size,
    md5: stream.md5,
    metadata,
    blocks,
    stream_offset: offset,
  }
}

///|
/// Parsed `STREAMINFO` payload.
priv struct StreamInfo {
  sample_rate : Int32
  channels : Int32
  bits_per_sample : Int32
  total_samples : Int64
  min_block_size : Int32
  max_block_size : Int32
  min_frame_size : Int32
  max_frame_size : Int32
  md5 : String
}

///|
/// Decode the 34 byte `STREAMINFO` payload.
fn parse_stream_info(
  bytes : Bytes,
  offset : Int32,
) -> StreamInfo raise @audio.AudioError {
  let min_block = @audio.read_u16be(bytes, offset)
  let max_block = @audio.read_u16be(bytes, offset + 2)
  let min_frame = @audio.read_u24be(bytes, offset + 4)
  let max_frame = @audio.read_u24be(bytes, offset + 7)
  // 20 bits sample rate, 3 bits channels-1, 5 bits bps-1, 36 bits samples.
  let reader = BitReader::new(bytes, bit=(offset + 10) * 8)
  let sample_rate = reader.read_bits(20)
  let channels = reader.read_bits(3) + 1
  let bits = reader.read_bits(5) + 1
  let total = reader.read_bits64(36)
  let md5_start = offset + 18
  let md5 = hex_lower(bytes, md5_start, md5_start + 16)
  StreamInfo::{
    sample_rate,
    channels,
    bits_per_sample: bits,
    total_samples: total,
    min_block_size: min_block,
    max_block_size: max_block,
    min_frame_size: min_frame,
    max_frame_size: max_frame,
    md5,
  }
}

///|
/// Lower case hexadecimal rendering of a byte range.
fn hex_lower(bytes : Bytes, start : Int32, end : Int32) -> String {
  let buffer = @buffer.Buffer::Buffer(size_hint=(end - start) * 2)
  for index = start; index < end; index = index + 1 {
    let value = bytes.at(index).to_int() & 0xFF
    let high = value >> 4
    let low = value & 0x0F
    buffer.write_byte(hex_digit(high))
    buffer.write_byte(hex_digit(low))
  }
  buffer.to_string()
}

///|
/// ASCII code of a hexadecimal digit.
fn hex_digit(value : Int32) -> Byte {
  if value < 10 {
    (0x30 + value).to_byte()
  } else {
    (0x61 + value - 10).to_byte()
  }
}

///|
/// Parse a Vorbis comment block into `target`.
fn parse_vorbis_comment(
  bytes : Bytes,
  offset : Int32,
  length : Int32,
  target : Array[(String, String)],
) -> Unit raise @audio.AudioError {
  let end = offset + length
  let mut cursor = offset
  if cursor + 4 > end {
    return
  }
  let vendor_len = @audio.read_u32le(bytes, cursor).to_int()
  cursor = cursor + 4
  if vendor_len < 0 || cursor + vendor_len > end {
    return
  }
  cursor = cursor + vendor_len
  if cursor + 4 > end {
    return
  }
  let count = @audio.read_u32le(bytes, cursor).to_int()
  cursor = cursor + 4
  for _index = 0; _index < count; _index = _index + 1 {
    if cursor + 4 > end {
      return
    }
    let size = @audio.read_u32le(bytes, cursor).to_int()
    cursor = cursor + 4
    if size < 0 || cursor + size > end {
      return
    }
    let text = @utf8.decode_lossy(
      bytes.exact_view(start=cursor, end=cursor + size),
    )
    cursor = cursor + size
    match text.find("=") {
      Some(position) => {
        let key = text[0:position].to_owned()
        let value = text[position + 1:text.length()].to_owned()
        target.push((key, value))
      }
      None => ()
    }
  }
}
