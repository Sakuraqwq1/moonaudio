// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Encode an [`@audio.AudioBuffer`] as a RIFF/WAVE file.
///
/// `format` selects the target sample encoding; the default is signed 16 bit
/// PCM, the format every player understands.
pub fn encode(
  audio : @audio.AudioBuffer,
  format~ : @audio.SampleFormat = @audio.I16,
) -> Bytes raise @audio.AudioError {
  encode_with_metadata(audio, format, [])
}

///|
/// Encode a buffer and attach `LIST/INFO` metadata.
///
/// Keys must be four ASCII characters when non-empty; longer keys are truncated
/// and short keys are padded with spaces so the result stays a valid INFO
/// chunk.
pub fn encode_with_metadata(
  audio : @audio.AudioBuffer,
  format : @audio.SampleFormat,
  metadata : Array[(String, String)],
) -> Bytes raise @audio.AudioError {
  if audio.channels <= 0 {
    raise @audio.OutOfRange("cannot encode a buffer with no channels")
  }
  if audio.sample_rate <= 0 {
    raise @audio.OutOfRange("cannot encode a buffer with no sample rate")
  }
  let bits = format.bits()
  let width = bits / 8
  let block_align = audio.channels * width
  let byte_rate = audio.sample_rate.to_int64() * block_align.to_int64()
  let samples = audio.data.length()
  let data_len = samples * width
  let info = build_info_chunk(metadata)
  let info_len = info.length()
  let riff_size = 4L +
    8L +
    16L +
    8L +
    data_len.to_int64() +
    (if info_len > 0 { 8L + info_len.to_int64() } else { 0L })
  let buffer = @buffer.Buffer::Buffer(size_hint=(riff_size + 8L).to_int() + 8)
  write_ascii(buffer, "RIFF")
  write_u32le(buffer, riff_size)
  write_ascii(buffer, "WAVE")
  write_ascii(buffer, "fmt ")
  write_u32le(buffer, 16L)
  let tag = if format.is_float() { 3 } else { 1 }
  write_u16le(buffer, tag)
  write_u16le(buffer, audio.channels)
  write_u32le(buffer, audio.sample_rate.to_int64())
  write_u32le(buffer, byte_rate)
  write_u16le(buffer, block_align)
  write_u16le(buffer, bits)
  write_ascii(buffer, "data")
  write_u32le(buffer, data_len.to_int64())
  for sample in audio.data {
    write_sample(buffer, sample, format)
  }
  if data_len % 2 == 1 {
    buffer.write_byte(0x00)
  }
  if info_len > 0 {
    write_ascii(buffer, "LIST")
    write_u32le(buffer, info_len.to_int64())
    buffer.write_bytes(info)
  }
  buffer.to_bytes()
}

///|
/// Write one sample in the requested encoding.
fn write_sample(
  buffer : @buffer.Buffer,
  sample : Double,
  format : @audio.SampleFormat,
) -> Unit {
  match format {
    @audio.U8 => buffer.write_byte(@audio.quantize(sample, @audio.U8).to_byte())
    @audio.I16 => {
      let code = @audio.quantize(sample, @audio.I16)
      buffer.write_byte((code & 0xFF).to_byte())
      buffer.write_byte(((code >> 8) & 0xFF).to_byte())
    }
    @audio.I24 => {
      let code = @audio.quantize(sample, @audio.I24)
      buffer.write_byte((code & 0xFF).to_byte())
      buffer.write_byte(((code >> 8) & 0xFF).to_byte())
      buffer.write_byte(((code >> 16) & 0xFF).to_byte())
    }
    @audio.I32 => {
      let code = @audio.quantize(sample, @audio.I32)
      buffer.write_byte((code & 0xFF).to_byte())
      buffer.write_byte(((code >> 8) & 0xFF).to_byte())
      buffer.write_byte(((code >> 16) & 0xFF).to_byte())
      buffer.write_byte(((code >> 24) & 0xFF).to_byte())
    }
    @audio.F32 => write_u32le(buffer, @audio.double_to_f32_bits(sample))
    @audio.F64 => write_u64le(buffer, sample.reinterpret_as_int64())
  }
}

///|
/// Build a `LIST/INFO` payload, or an empty byte string when `metadata` is
/// empty.
fn build_info_chunk(metadata : Array[(String, String)]) -> Bytes {
  if metadata.length() == 0 {
    return Bytes::make(0, 0)
  }
  let buffer = @buffer.Buffer::Buffer(size_hint=64)
  write_ascii(buffer, "INFO")
  for entry in metadata {
    let key = fit_four(entry.0)
    let value = entry.1
    write_ascii(buffer, key)
    write_u32le(buffer, value.length().to_int64())
    buffer.write_string_utf8(value)
    if value.length() % 2 == 1 {
      buffer.write_byte(0x00)
    }
  }
  buffer.to_bytes()
}

///|
/// Pad or truncate `key` to exactly four ASCII characters.
fn fit_four(key : String) -> String {
  if key.length() == 4 {
    key
  } else if key.length() > 4 {
    key[0:4].to_owned()
  } else {
    key + " ".repeat(4 - key.length())
  }
}

///|
/// Write an ASCII string into a buffer.
fn write_ascii(buffer : @buffer.Buffer, text : String) -> Unit {
  buffer.write_string_utf8(text)
}

///|
/// Write a little endian 16 bit value.
fn write_u16le(buffer : @buffer.Buffer, value : Int32) -> Unit {
  buffer.write_byte((value & 0xFF).to_byte())
  buffer.write_byte(((value >> 8) & 0xFF).to_byte())
}

///|
/// Write a little endian 32 bit value.
fn write_u32le(buffer : @buffer.Buffer, value : Int64) -> Unit {
  buffer.write_byte((value & 0xFFL).to_byte())
  buffer.write_byte(((value >> 8) & 0xFFL).to_byte())
  buffer.write_byte(((value >> 16) & 0xFFL).to_byte())
  buffer.write_byte(((value >> 24) & 0xFFL).to_byte())
}

///|
/// Write a little endian 64 bit value.
fn write_u64le(buffer : @buffer.Buffer, value : Int64) -> Unit {
  for index = 0; index < 8; index = index + 1 {
    buffer.write_byte(((value >> (index * 8)) & 0xFFL).to_byte())
  }
}
