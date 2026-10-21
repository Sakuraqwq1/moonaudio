// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// A short two channel test signal at 44.1 kHz.
fn stereo_buffer() -> @audio.AudioBuffer {
  @audio.AudioBuffer::{
    sample_rate: 44100,
    channels: 2,
    data: [0.0, 0.0, 0.5, -0.5, -1.0, 1.0, 0.25, -0.25],
  }
}

///|
/// A short mono signal at `rate`.
fn mono_buffer(rate : Int32, values : Array[Double]) -> @audio.AudioBuffer {
  @audio.AudioBuffer::{ sample_rate: rate, channels: 1, data: values, }
}

///|
/// Build a `Bytes` value from ASCII text without escape syntax.
fn ascii(text : String) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=text.length())
  buffer.write_string_utf8(text)
  buffer.to_bytes()
}

///|
/// Write a big endian 32 bit value.
fn put_be32(out : @buffer.Buffer, value : Int64) -> Unit {
  for shift = 24; shift >= 0; shift = shift - 8 {
    out.write_byte(((value >> shift) & 0xFFL).to_byte())
  }
}

///|
/// Write a big endian 16 bit value.
fn put_i16be(out : @buffer.Buffer, value : Int32) -> Unit {
  out.write_byte(((value >> 8) & 0xFF).to_byte())
  out.write_byte((value & 0xFF).to_byte())
}

///|
/// Assemble a `.au` file from raw header fields and a sample payload.
///
/// `override_size` lets a fixture lie about the data length, which is how the
/// "until end of file" and truncation paths are exercised.
fn craft_au(
  encoding : Int32,
  sample_rate : Int32,
  channels : Int32,
  data : Bytes,
  annotation~ : String = "",
  override_size~ : Int64 = -1L,
) -> Bytes {
  let note = @buffer.Buffer::Buffer(size_hint=annotation.length() + 1)
  note.write_string_utf8(annotation)
  let note_bytes = note.to_bytes()
  let out = @buffer.Buffer::Buffer(size_hint=32 + data.length())
  out.write_string_utf8(".snd")
  put_be32(out, (24 + note_bytes.length()).to_int64())
  put_be32(
    out,
    if override_size >= 0L {
      override_size
    } else {
      data.length().to_int64()
    },
  )
  put_be32(out, encoding.to_int64())
  put_be32(out, sample_rate.to_int64())
  put_be32(out, channels.to_int64())
  out.write_bytes(note_bytes)
  out.write_bytes(data)
  out.to_bytes()
}

///|
/// Decode `bytes` and report the error kind, or `"ok"`.
fn decode_error_kind(bytes : Bytes) -> String {
  let mut kind = "ok"
  let _ = decode(bytes) catch {
    (error : @audio.AudioError) => {
      kind = error.kind()
      @audio.AudioBuffer::new(0, 1)
    }
  }
  kind
}

///|
/// Parse `bytes` and report the error kind, or `"ok"`.
fn info_error_kind(bytes : Bytes) -> String {
  let mut kind = "ok"
  let _ = parse_info(bytes) catch {
    (error : @audio.AudioError) => {
      kind = error.kind()
      AuInfo::{
        sample_rate: 0,
        channels: 0,
        frames: 0,
        format: @audio.I16,
        encoding: 0,
        encoding_name: "",
        annotation: "",
        header_size: 0,
      }
    }
  }
  kind
}

///|
/// Read a big endian 32 bit header word, panicking on a short buffer.
fn header_word(bytes : Bytes, offset : Int32) -> Int64 {
  let value = @audio.read_u32be(bytes, offset) catch {
    (_ : @audio.AudioError) => panic()
  }
  value
}

///|
test "16 bit stereo roundtrip" {
  let source = stereo_buffer()
  let encoded = encode(source) catch { (_ : @audio.AudioError) => panic() }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.sample_rate, 44100)
  assert_eq(info.channels, 2)
  assert_eq(info.frames, 4)
  assert_eq(info.header_size, 24)
  assert_eq(info.encoding, 3)
  assert_eq(info.encoding_name, "linear-16")
  assert_eq(info.format.to_name(), "s16")
  assert_eq(info.annotation, "")
  let file = parse(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(file.info.encoding, 3)
  assert_eq(file.audio.frames(), 4)
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
test "24 bit roundtrip" {
  let source = stereo_buffer()
  let encoded = encode(source, format=@audio.I24) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.encoding, 4)
  assert_eq(info.encoding_name, "linear-24")
  assert_eq(info.format.to_name(), "s24")
  assert_eq(info.format.bits(), 24)
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  for index = 0; index < source.data.length(); index = index + 1 {
    assert_true(
      (decoded.data[index] - source.data[index]).abs() <= 1.0 / 8388608.0,
    )
  }
}

///|
test "32 bit roundtrip" {
  let source = stereo_buffer()
  let encoded = encode(source, format=@audio.I32) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.encoding, 5)
  assert_eq(info.encoding_name, "linear-32")
  assert_eq(info.format.to_name(), "s32")
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  for index = 0; index < source.data.length(); index = index + 1 {
    assert_true(
      (decoded.data[index] - source.data[index]).abs() <= 1.0 / 2147483648.0,
    )
  }
}

///|
test "8 bit signed roundtrip" {
  let source = mono_buffer(8000, [-1.0, -0.5, 0.0, 0.5, 0.75])
  let encoded = encode(source, format=@audio.U8) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.encoding, 2)
  assert_eq(info.encoding_name, "linear-8")
  assert_eq(info.format.to_name(), "u8")
  assert_eq(encoded.length(), 24 + 5)
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.frames(), 5)
  for index = 0; index < 5; index = index + 1 {
    assert_true((decoded.data[index] - source.data[index]).abs() <= 1.0 / 128.0)
  }
}

///|
test "float roundtrip" {
  let source = stereo_buffer()
  let f32 = encode(source, format=@audio.F32) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info32 = parse_info(f32) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info32.encoding, 6)
  assert_eq(info32.encoding_name, "float-32")
  assert_eq(info32.format.to_name(), "f32")
  let decoded32 = decode(f32) catch { (_ : @audio.AudioError) => panic() }
  for index = 0; index < source.data.length(); index = index + 1 {
    assert_true((decoded32.data[index] - source.data[index]).abs() <= 1.0e-6)
  }
  let f64 = encode(source, format=@audio.F64) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info64 = parse_info(f64) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info64.encoding, 7)
  assert_eq(info64.encoding_name, "float-64")
  assert_eq(info64.format.to_name(), "f64")
  let decoded64 = decode(f64) catch { (_ : @audio.AudioError) => panic() }
  for index = 0; index < source.data.length(); index = index + 1 {
    assert_true((decoded64.data[index] - source.data[index]).abs() <= 1.0e-12)
  }
}

///|
test "mu-law and a-law fixtures decode" {
  let mulaw = @buffer.Buffer::Buffer(size_hint=4)
  mulaw.write_byte(@audio.mulaw_encode(0.5).to_byte())
  mulaw.write_byte(@audio.mulaw_encode(-0.5).to_byte())
  mulaw.write_byte(@audio.mulaw_encode(1.0).to_byte())
  mulaw.write_byte(@audio.mulaw_encode(0.0).to_byte())
  let file = craft_au(1, 8000, 1, mulaw.to_bytes())
  let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.encoding, 1)
  assert_eq(info.encoding_name, "mu-law")
  assert_eq(info.format.to_name(), "s16")
  assert_eq(info.frames, 4)
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_true((decoded.data[0] - 0.5).abs() < 0.1)
  assert_true((decoded.data[1] + 0.5).abs() < 0.1)
  assert_true((decoded.data[2] - 1.0).abs() < 0.1)
  assert_true(decoded.data[3].abs() < 0.1)
  let alaw = @buffer.Buffer::Buffer(size_hint=2)
  alaw.write_byte(@audio.alaw_encode(0.5).to_byte())
  alaw.write_byte(@audio.alaw_encode(-0.5).to_byte())
  let alaw_file = craft_au(27, 8000, 1, alaw.to_bytes())
  let alaw_info = parse_info(alaw_file) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(alaw_info.encoding, 27)
  assert_eq(alaw_info.encoding_name, "a-law")
  assert_eq(alaw_info.frames, 2)
  let alaw_decoded = decode(alaw_file) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true((alaw_decoded.data[0] - 0.5).abs() < 0.1)
  assert_true((alaw_decoded.data[1] + 0.5).abs() < 0.1)
}

///|
test "annotation roundtrip" {
  let source = stereo_buffer()
  let encoded = encode_with_annotation(source, @audio.I16, "moonaudio test") catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.annotation, "moonaudio test")
  assert_eq(info.header_size, 24 + 14)
  assert_eq(info.frames, 4)
  assert_true(info.describe().contains("note \"moonaudio test\""))
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.frames(), 4)
  assert_true((decoded.data[2] - 0.5).abs() <= 1.0 / 32768.0)
  assert_true((decoded.data[5] - 1.0).abs() <= 1.0 / 32768.0)
}

///|
test "non 24 byte data offset is honoured" {
  let data = @buffer.Buffer::Buffer(size_hint=8)
  put_i16be(data, 16384)
  put_i16be(data, -16384)
  put_i16be(data, 8192)
  put_i16be(data, -32768)
  let file = craft_au(
    3,
    22050,
    1,
    data.to_bytes(),
    annotation="crafted-by-hand\u{0}\u{0}",
  )
  let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.header_size, 24 + 15 + 2)
  assert_eq(info.annotation, "crafted-by-hand")
  assert_eq(info.sample_rate, 22050)
  assert_eq(info.frames, 4)
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_true((decoded.data[0] - 0.5).abs() < 1.0e-4)
  assert_true((decoded.data[1] + 0.5).abs() < 1.0e-4)
  assert_true((decoded.data[2] - 0.25).abs() < 1.0e-4)
  assert_true((decoded.data[3] + 1.0).abs() < 1.0e-4)
}

///|
test "truncated data is reported" {
  let data = @buffer.Buffer::Buffer(size_hint=4)
  put_i16be(data, 0)
  put_i16be(data, 0)
  let lying = craft_au(3, 8000, 1, data.to_bytes(), override_size=64L)
  assert_eq(decode_error_kind(lying), "truncated")
  assert_eq(info_error_kind(lying), "truncated")
  assert_eq(decode_error_kind(ascii(".snd")), "truncated")
  let past = @buffer.Buffer::Buffer(size_hint=24)
  past.write_string_utf8(".snd")
  put_be32(past, 4096L)
  put_be32(past, 4L)
  put_be32(past, 3L)
  put_be32(past, 8000L)
  put_be32(past, 1L)
  assert_eq(decode_error_kind(past.to_bytes()), "truncated")
}

///|
test "unsupported encodings are rejected" {
  let payload = Bytes::make(4, 0)
  for encoding in [23, 24, 25, 99] {
    let file = craft_au(encoding, 8000, 1, payload)
    assert_eq(decode_error_kind(file), "unsupported")
    assert_eq(info_error_kind(file), "unsupported")
  }
  assert_eq(decode_error_kind(ascii("MThdMThdMThdMThdMThdMThd")), "unsupported")
}

///|
test "encode writes correct header fields" {
  let source = mono_buffer(8000, [0.0, 0.5, -0.5])
  let encoded = encode(source, format=@audio.I24) catch {
    (_ : @audio.AudioError) => panic()
  }
  let magic = @audio.read_ascii(encoded, 0, 4) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(magic, ".snd")
  assert_eq(header_word(encoded, 4), 24L)
  assert_eq(header_word(encoded, 8), 9L)
  assert_eq(header_word(encoded, 12), 4L)
  assert_eq(header_word(encoded, 16), 8000L)
  assert_eq(header_word(encoded, 20), 1L)
  assert_eq(encoded.length(), 24 + 9)
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.frames, 3)
  assert_eq(info.header_size, 24)
  assert_true(info.describe().contains("8000 Hz"))
  assert_true(info.describe().contains("(s24)"))
  assert_true(info.describe().contains("3 frames"))
}

///|
test "unknown data size reads until end of file" {
  let data = @buffer.Buffer::Buffer(size_hint=4)
  put_i16be(data, 16384)
  put_i16be(data, -16384)
  let file = craft_au(3, 8000, 1, data.to_bytes(), override_size=0xFFFFFFFFL)
  let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.frames, 2)
  assert_eq(info.header_size, 24)
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_true((decoded.data[0] - 0.5).abs() < 1.0e-4)
  assert_true((decoded.data[1] + 0.5).abs() < 1.0e-4)
}
