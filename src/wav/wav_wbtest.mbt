// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// A short two channel test signal.
fn stereo_buffer() -> @audio.AudioBuffer {
  @audio.AudioBuffer::{
    sample_rate: 44100,
    channels: 2,
    data: [0.0, 0.0, 0.5, -0.5, -1.0, 1.0, 0.25, -0.25],
  }
}

///|
/// ASCII helper: build bytes from a text literal without escape syntax.
fn ascii(text : String) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=text.length())
  buffer.write_string_utf8(text)
  buffer.to_bytes()
}
///|
/// Build a RIFF/WAVE file from raw `fmt ` and `data` payloads.
fn craft(
  fmt : Bytes,
  data : Bytes,
  big_endian? : Bool = false,
) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=64)
  buffer.write_string_utf8("RIFF")
  put_u32(buffer, (4 + 8 + fmt.length() + 8 + data.length()).to_int64(), big_endian)
  buffer.write_string_utf8("WAVE")
  buffer.write_string_utf8("fmt ")
  put_u32(buffer, fmt.length().to_int64(), big_endian)
  buffer.write_bytes(fmt)
  buffer.write_string_utf8("data")
  put_u32(buffer, data.length().to_int64(), big_endian)
  buffer.write_bytes(data)
  if data.length() % 2 == 1 {
    buffer.write_byte(0)
  }
  buffer.to_bytes()
}

///|
/// Write a 32 bit value in the requested byte order.
fn put_u32(buffer : @buffer.Buffer, value : Int64, big_endian : Bool) -> Unit {
  if big_endian {
    for shift = 24; shift >= 0; shift = shift - 8 {
      buffer.write_byte(((value >> shift) & 0xFFL).to_byte())
    }
  } else {
    for shift = 0; shift <= 24; shift = shift + 8 {
      buffer.write_byte(((value >> shift) & 0xFFL).to_byte())
    }
  }
}

///|
/// Little endian 16 bit writer used by the fixtures.
fn put_u16(buffer : @buffer.Buffer, value : Int32) -> Unit {
  buffer.write_byte((value & 0xFF).to_byte())
  buffer.write_byte(((value >> 8) & 0xFF).to_byte())
}
///|
/// Big endian 16 bit writer used by the RIFX fixture.
fn put_u16_be(buffer : @buffer.Buffer, value : Int32) -> Unit {
  buffer.write_byte(((value >> 8) & 0xFF).to_byte())
  buffer.write_byte((value & 0xFF).to_byte())
}

///|
test "16 bit stereo roundtrip" {
  let source = stereo_buffer()
  let encoded = encode(source) catch { (_ : @audio.AudioError) => panic() }
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.sample_rate, 44100)
  assert_eq(decoded.channels, 2)
  assert_eq(decoded.frames(), 4)
  for frame = 0; frame < 4; frame = frame + 1 {
    for channel = 0; channel < 2; channel = channel + 1 {
      let expected = source.sample(frame, channel)
      let actual = decoded.sample(frame, channel)
      assert_true((expected - actual).abs() <= 1.0 / 32768.0)
    }
  }
}

///|
test "8 bit mono roundtrip and padding" {
  let source : @audio.AudioBuffer = {
    sample_rate: 8000,
    channels: 1,
    data: [-1.0, 0.0, 1.0],
  }
  let encoded = encode(source, format=@audio.U8) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(encoded.length() % 2, 0)
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.frames(), 3)
  assert_true((decoded.data[0] + 1.0).abs() < 0.01)
  assert_true(decoded.data[1].abs() < 0.01)
  assert_true((decoded.data[2] - 1.0).abs() < 0.01)
}

///|
test "24 bit roundtrip" {
  let source = stereo_buffer()
  let encoded = encode(source, format=@audio.I24) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.bits_per_sample, 24)
  assert_eq(info.format.to_name(), "s24")
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_true((decoded.data[2] - 0.5).abs() < 1.0e-5)
  assert_true((decoded.data[4] + 1.0).abs() < 1.0e-5)
}

///|
test "float32 roundtrip and info" {
  let source = stereo_buffer()
  let encoded = encode(source, format=@audio.F32) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.format_tag, 3)
  assert_eq(info.format.to_name(), "f32")
  assert_eq(info.channels, 2)
  assert_eq(info.frames, 4)
  assert_eq(info.sample_rate, 44100)
  assert_eq(info.block_align(), 8)
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_true((decoded.data[2] - 0.5).abs() < 1.0e-6)
  assert_true((decoded.data[4] + 1.0).abs() < 1.0e-6)
}

///|
test "metadata roundtrip" {
  let source = stereo_buffer()
  let metadata : Array[(String, String)] = [
    ("INAM", "Test Tone"),
    ("IART", "moonaudio"),
  ]
  let encoded = encode_with_metadata(source, @audio.I16, metadata) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.meta("INAM"), Some("Test Tone"))
  assert_eq(info.meta("IART"), Some("moonaudio"))
  assert_eq(info.meta("ICMT"), None)
  let mut has_list = false
  for chunk in info.chunks {
    if chunk.id == "LIST" {
      has_list = true
    }
  }
  assert_true(has_list)
}

///|
test "chunk inventory" {
  let encoded = encode(stereo_buffer()) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.chunks.length(), 2)
  assert_eq(info.chunks[0].id, "fmt ")
  assert_eq(info.chunks[1].id, "data")
  assert_true(info.describe().contains("44100 Hz"))
  assert_true(!info.extensible)
}

///|
test "extensible header is understood" {
  let fmt = @buffer.Buffer::Buffer(size_hint=40)
  put_u16(fmt, 0xFFFE)
  put_u16(fmt, 1)
  put_u32(fmt, 8000L, false)
  put_u32(fmt, 16000L, false)
  put_u16(fmt, 2)
  put_u16(fmt, 16)
  put_u16(fmt, 22)
  put_u16(fmt, 16)
  put_u32(fmt, 0x4L, false)
  put_u16(fmt, 1)
  for index = 0; index < 14; index = index + 1 {
    fmt.write_byte(0)
  }
  let data = @buffer.Buffer::Buffer(size_hint=4)
  put_u16(data, 0x4000)
  put_u16(data, 0xC000)
  let file = craft(fmt.to_bytes(), data.to_bytes())
  let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
  assert_true(info.extensible)
  assert_eq(info.format_tag, 0xFFFE)
  assert_eq(info.valid_bits, 16)
  assert_eq(info.channel_mask, 0x4L)
  assert_eq(info.format.to_name(), "s16")
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_true((decoded.data[0] - 0.5).abs() < 1.0e-4)
  assert_true((decoded.data[1] + 0.5).abs() < 1.0e-4)
}

///|
test "big endian RIFX is decoded" {
  let fmt = @buffer.Buffer::Buffer(size_hint=16)
  put_u16_be(fmt, 1)
  put_u16_be(fmt, 1)
  put_u32(fmt, 8000L, true)
  put_u32(fmt, 16000L, true)
  put_u16_be(fmt, 2)
  put_u16_be(fmt, 16)
  let data = @buffer.Buffer::Buffer(size_hint=4)
  data.write_byte(0x40)
  data.write_byte(0x00)
  data.write_byte(0xC0)
  data.write_byte(0x00)
  let file = craft(fmt.to_bytes(), data.to_bytes(), big_endian=true)
  // Patch the form type so the file claims RIFX.
  let patched = @buffer.Buffer::Buffer(size_hint=file.length())
  patched.write_string_utf8("RIFX")
  patched.write_bytes(file.exact_view(start=4, end=file.length()))
  assert_eq(decode_error_kind(patched.to_bytes()), "ok")
  let decoded = decode(patched.to_bytes()) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(decoded.channels, 1)
  assert_true((decoded.data[0] - 0.5).abs() < 1.0e-4)
  assert_true((decoded.data[1] + 0.5).abs() < 1.0e-4)
}

///|
test "mu-law wave is expanded" {
  let fmt = @buffer.Buffer::Buffer(size_hint=18)
  put_u16(fmt, 7)
  put_u16(fmt, 1)
  put_u32(fmt, 8000L, false)
  put_u32(fmt, 8000L, false)
  put_u16(fmt, 1)
  put_u16(fmt, 8)
  put_u16(fmt, 0)
  let data = @buffer.Buffer::Buffer(size_hint=2)
  data.write_byte(@audio.mulaw_encode(0.5).to_byte())
  data.write_byte(@audio.mulaw_encode(-0.5).to_byte())
  let file = craft(fmt.to_bytes(), data.to_bytes())
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_true((decoded.data[0] - 0.5).abs() < 0.1)
  assert_true((decoded.data[1] + 0.5).abs() < 0.1)
}

///|
/// Decode `bytes` and report the error kind, or `"ok"`.
fn decode_error_kind(bytes : Bytes) -> String {
  let mut kind = "ok"
  let _ = decode(bytes) catch { (error : @audio.AudioError) => {
    kind = error.kind()
    @audio.AudioBuffer::new(0, 1)
  } }
  kind
}

///|
/// Parse `bytes` and report the error kind, or `"ok"`.
fn info_error_kind(bytes : Bytes) -> String {
  let mut kind = "ok"
  let _ = parse_info(bytes) catch { (error : @audio.AudioError) => {
    kind = error.kind()
    WavInfo::{
      sample_rate: 0,
      channels: 0,
      frames: 0,
      format: @audio.I16,
      format_tag: 0,
      bits_per_sample: 0,
      valid_bits: 0,
      channel_mask: 0L,
      byte_rate: 0L,
      extensible: false,
      chunks: [],
      metadata: [],
    }
  } }
  kind
}

///|
test "rejects files that are not RIFF" {
  assert_eq(decode_error_kind(ascii("MThdMThdMThd")), "unsupported")
}

///|
test "truncated header is reported" {
  assert_eq(decode_error_kind(ascii("RIFF")), "truncated")
}

///|
test "missing fmt chunk raises invalid" {
  let buffer = @buffer.Buffer::Buffer(size_hint=16)
  buffer.write_string_utf8("RIFF")
  put_u32(buffer, 4L, false)
  buffer.write_string_utf8("WAVE")
  assert_eq(decode_error_kind(buffer.to_bytes()), "invalid")
  assert_eq(info_error_kind(buffer.to_bytes()), "invalid")
}
