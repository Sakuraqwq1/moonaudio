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
/// Build bytes from a list of byte values.
fn bytes_of(values : Array[Int32]) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=values.length())
  for value in values {
    buffer.write_byte(value.to_byte())
  }
  buffer.to_bytes()
}

///|
/// ASCII helper: build bytes from a text literal without escape syntax.
fn ascii(text : String) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=text.length())
  buffer.write_string_utf8(text)
  buffer.to_bytes()
}

///|
/// Big endian 32 bit writer used by the fixtures.
fn put_u32be(buffer : @buffer.Buffer, value : Int64) -> Unit {
  for shift = 24; shift >= 0; shift = shift - 8 {
    buffer.write_byte(((value >> shift) & 0xFFL).to_byte())
  }
}

///|
/// Big endian 16 bit writer used by the fixtures.
fn put_u16be(buffer : @buffer.Buffer, value : Int32) -> Unit {
  buffer.write_byte(((value >> 8) & 0xFF).to_byte())
  buffer.write_byte((value & 0xFF).to_byte())
}

///|
/// Build a `FORM` container from prepared chunks, padding odd payloads.
fn craft_aiff(form : String, chunks : Array[(String, Bytes)]) -> Bytes {
  let mut body = 4
  for chunk in chunks {
    let size = chunk.1.length()
    body = body + 8 + size + (size & 1)
  }
  let buffer = @buffer.Buffer::Buffer(size_hint=body + 8)
  buffer.write_string_utf8("FORM")
  put_u32be(buffer, body.to_int64())
  buffer.write_string_utf8(form)
  for chunk in chunks {
    buffer.write_string_utf8(chunk.0)
    put_u32be(buffer, chunk.1.length().to_int64())
    buffer.write_bytes(chunk.1)
    if chunk.1.length() % 2 == 1 {
      buffer.write_byte(0)
    }
  }
  buffer.to_bytes()
}

///|
/// Build a `COMM` payload; `compression` adds the AIFC fields when present.
fn comm_payload(
  channels : Int32,
  frames : Int32,
  bits : Int32,
  rate_bytes : Bytes,
  compression : String?,
) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=40)
  put_u16be(buffer, channels)
  put_u32be(buffer, frames.to_int64())
  put_u16be(buffer, bits)
  buffer.write_bytes(rate_bytes)
  match compression {
    Some(compression) => {
      buffer.write_string_utf8(compression)
      buffer.write_byte(0)
    }
    None => ()
  }
  buffer.to_bytes()
}

///|
/// Build a `COMM` payload from a sample rate in Hz.
fn comm_at_rate(
  channels : Int32,
  frames : Int32,
  bits : Int32,
  rate : Double,
  compression : String?,
) -> Bytes {
  let rate_bytes = double_to_ext_float(rate) catch {
    (_ : @audio.AudioError) => panic()
  }
  comm_payload(channels, frames, bits, rate_bytes, compression)
}

///|
/// Build an `SSND` payload with the given leading offset bytes.
fn ssnd_payload(
  samples : Bytes,
  offset_bytes : Bytes,
  block_size : Int32,
) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=8 + samples.length())
  put_u32be(buffer, offset_bytes.length().to_int64())
  put_u32be(buffer, block_size.to_int64())
  buffer.write_bytes(offset_bytes)
  buffer.write_bytes(samples)
  buffer.to_bytes()
}

///|
/// Payload offset of the first chunk with `id`, or `-1` when absent.
fn chunk_payload_offset(info : AiffInfo, id : String) -> Int32 {
  for chunk in info.chunks {
    if chunk.0 == id {
      return chunk.1
    }
  }
  -1
}

///|
/// A placeholder used to absorb an error into a diagnostic string.
fn dummy_info() -> AiffInfo {
  AiffInfo::{
    sample_rate: 0,
    channels: 0,
    frames: 0,
    format: @audio.I16,
    bits_per_sample: 0,
    compression: "",
    is_aifc: false,
    chunks: [],
    metadata: [],
  }
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
      dummy_info()
    }
  }
  kind
}

///|
test "16 bit stereo roundtrip" {
  let source = stereo_buffer()
  let encoded = encode(source) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(encoded.length() % 2, 0)
  assert_true(@audio.ascii_is(encoded, 0, 4, "FORM"))
  assert_true(@audio.ascii_is(encoded, 8, 4, "AIFF"))
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.sample_rate, 44100)
  assert_eq(info.channels, 2)
  assert_eq(info.frames, 4)
  assert_eq(info.bits_per_sample, 16)
  assert_eq(info.format.to_name(), "s16")
  assert_eq(info.compression, "NONE")
  assert_true(!info.is_aifc)
  // The FORM size counts every chunk but not the FORM header itself.
  let form_size = @audio.read_u32be(encoded, 4) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(form_size, (encoded.length() - 8).to_int64())
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
test "8 bit mono roundtrip stores signed samples" {
  let source : @audio.AudioBuffer = {
    sample_rate: 8000,
    channels: 1,
    data: [-1.0, 0.0, 1.0],
  }
  let encoded = encode(source, format=@audio.U8) catch {
    (_ : @audio.AudioError) => panic()
  }
  // Three samples occupy an odd number of bytes, so the chunk needs padding.
  assert_eq(encoded.length() % 2, 0)
  let form_size = @audio.read_u32be(encoded, 4) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(form_size, (encoded.length() - 8).to_int64())
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.bits_per_sample, 8)
  assert_eq(info.format.to_name(), "u8")
  assert_eq(info.frames, 3)
  let data = chunk_payload_offset(info, "SSND") + 8
  // -1.0, 0.0 and +1.0 are stored as 0x80, 0x00 and 0x7F, not offset binary.
  assert_eq(encoded.at(data).to_int(), 128)
  assert_eq(encoded.at(data + 1).to_int(), 0)
  assert_eq(encoded.at(data + 2).to_int(), 127)
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.frames(), 3)
  assert_true((decoded.data[0] + 1.0).abs() <= 1.0 / 128.0)
  assert_true(decoded.data[1].abs() <= 1.0 / 128.0)
  assert_true((decoded.data[2] - 1.0).abs() <= 1.0 / 128.0)
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
  assert_eq(decoded.frames(), 4)
  for frame = 0; frame < 4; frame = frame + 1 {
    for channel = 0; channel < 2; channel = channel + 1 {
      let expected = source.sample(frame, channel)
      let actual = decoded.sample(frame, channel)
      assert_true((expected - actual).abs() <= 1.0 / 8388608.0)
    }
  }
}

///|
test "32 bit roundtrip" {
  let source = stereo_buffer()
  let encoded = encode(source, format=@audio.I32) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.bits_per_sample, 32)
  assert_eq(info.format.to_name(), "s32")
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  for frame = 0; frame < 4; frame = frame + 1 {
    for channel = 0; channel < 2; channel = channel + 1 {
      let expected = source.sample(frame, channel)
      let actual = decoded.sample(frame, channel)
      assert_true((expected - actual).abs() <= 1.0 / 2147483648.0)
    }
  }
}

///|
test "aifc sowt decodes little endian pcm" {
  let comm = comm_at_rate(1, 2, 16, 44100.0, Some("sowt"))
  let ssnd = ssnd_payload(bytes_of([0x00, 0x40, 0x00, 0xC0]), bytes_of([]), 0)
  let file = craft_aiff("AIFC", [("COMM", comm), ("SSND", ssnd)])
  let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
  assert_true(info.is_aifc)
  assert_eq(info.compression, "sowt")
  assert_eq(info.format.to_name(), "s16")
  assert_eq(info.frames, 2)
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.channels, 1)
  assert_true((decoded.data[0] - 0.5).abs() < 1.0e-4)
  assert_true((decoded.data[1] + 0.5).abs() < 1.0e-4)
}

///|
test "aifc twos decodes big endian pcm" {
  let comm = comm_at_rate(1, 2, 16, 48000.0, Some("twos"))
  let ssnd = ssnd_payload(bytes_of([0x40, 0x00, 0xC0, 0x00]), bytes_of([]), 0)
  let file = craft_aiff("AIFC", [("COMM", comm), ("SSND", ssnd)])
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.sample_rate, 48000)
  assert_true((decoded.data[0] - 0.5).abs() < 1.0e-4)
  assert_true((decoded.data[1] + 0.5).abs() < 1.0e-4)
}

///|
test "float32 roundtrip writes aifc with fver" {
  let source = stereo_buffer()
  let encoded = encode(source, format=@audio.F32) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_true(info.is_aifc)
  assert_eq(info.compression, "fl32")
  assert_eq(info.format.to_name(), "f32")
  assert_eq(info.bits_per_sample, 32)
  assert_eq(info.chunks.length(), 3)
  let fver = info.chunks[0]
  let comm = info.chunks[1]
  assert_eq(fver.0, "FVER")
  assert_eq(fver.2, 4)
  assert_eq(
    @audio.read_u32be(encoded, fver.1) catch {
      (_ : @audio.AudioError) => panic()
    },
    0xA2805140L,
  )
  assert_eq(comm.0, "COMM")
  assert_eq(comm.2, 44)
  assert_true(info.describe().contains("AIFC"))
  assert_true(info.describe().contains("fl32"))
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  for frame = 0; frame < 4; frame = frame + 1 {
    for channel = 0; channel < 2; channel = channel + 1 {
      let expected = source.sample(frame, channel)
      let actual = decoded.sample(frame, channel)
      assert_true((expected - actual).abs() <= 1.0e-6)
    }
  }
}

///|
test "float64 roundtrip" {
  let source = stereo_buffer()
  let encoded = encode(source, format=@audio.F64) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.compression, "fl64")
  assert_eq(info.format.to_name(), "f64")
  assert_eq(info.bits_per_sample, 64)
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.sample_rate, 44100)
  assert_true((decoded.data[2] - 0.5).abs() < 1.0e-12)
  assert_true((decoded.data[4] + 1.0).abs() < 1.0e-12)
}

///|
test "extended float sample rates are exact" {
  let rates : Array[Double] = [
    8000.0, 11025.0, 22050.0, 44100.0, 48000.0, 96000.0,
  ]
  for rate in rates {
    let encoded_rate = double_to_ext_float(rate) catch {
      (_ : @audio.AudioError) => panic()
    }
    assert_eq(encoded_rate.length(), 10)
    let back = ext_float_to_double(encoded_rate, 0) catch {
      (_ : @audio.AudioError) => panic()
    }
    assert_eq(back, rate)
    let comm = comm_payload(1, 1, 16, encoded_rate, None)
    let ssnd = ssnd_payload(bytes_of([0x40, 0x00]), bytes_of([]), 0)
    let file = craft_aiff("AIFF", [("COMM", comm), ("SSND", ssnd)])
    let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
    assert_eq(info.sample_rate, rate.to_int())
  }
}

///|
test "extended float canonical layout" {
  let bytes = double_to_ext_float(44100.0) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(bytes.length(), 10)
  assert_eq(bytes.at(0).to_int(), 0x40)
  assert_eq(bytes.at(1).to_int(), 0x0E)
  assert_eq(bytes.at(2).to_int(), 0xAC)
  assert_eq(bytes.at(3).to_int(), 0x44)
  for index = 4; index < 10; index = index + 1 {
    assert_eq(bytes.at(index).to_int(), 0)
  }
  // 8000 Hz: exponent 12 (0x400B) with mantissa 0xFA00000000000000.
  let eight_k = bytes_of([
    0x40, 0x0B, 0xFA, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ])
  assert_eq(
    ext_float_to_double(eight_k, 0) catch {
      (_ : @audio.AudioError) => panic()
    },
    8000.0,
  )
}

///|
test "extended float rejects nan and infinities" {
  let nan_rate = bytes_of([
    0x7F, 0xFF, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ])
  let comm = comm_payload(1, 1, 16, nan_rate, None)
  let ssnd = ssnd_payload(bytes_of([0x40, 0x00]), bytes_of([]), 0)
  let file = craft_aiff("AIFF", [("COMM", comm), ("SSND", ssnd)])
  assert_eq(info_error_kind(file), "invalid")
  assert_eq(decode_error_kind(file), "invalid")
  // The writer refuses values the field cannot represent.
  let infinity = @audio.read_f64be(bytes_of([0x7F, 0xF0, 0, 0, 0, 0, 0, 0]), 0) catch {
    (_ : @audio.AudioError) => panic()
  }
  let mut writer_kind = "ok"
  let _ = double_to_ext_float(infinity) catch {
    (error : @audio.AudioError) => {
      writer_kind = error.kind()
      bytes_of([])
    }
  }
  assert_eq(writer_kind, "out_of_range")
}

///|
test "text metadata roundtrip" {
  let source = stereo_buffer()
  let metadata : Array[(String, String)] = [
    ("NAME", "Test Tone"),
    ("AUTH", "moonaudio"),
    ("ANNO", "hello"),
  ]
  let encoded = encode_with_metadata(source, @audio.I16, metadata) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(encoded.length() % 2, 0)
  let form_size = @audio.read_u32be(encoded, 4) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(form_size, (encoded.length() - 8).to_int64())
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.meta("NAME"), Some("Test Tone"))
  assert_eq(info.meta("AUTH"), Some("moonaudio"))
  assert_eq(info.meta("ANNO"), Some("hello"))
  assert_eq(info.meta("(c) "), None)
  assert_eq(info.chunks.length(), 5)
  assert_eq(info.frames, 4)
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_true((decoded.data[2] - 0.5).abs() <= 1.0 / 32768.0)
}

///|
test "foreign metadata key becomes an anno annotation" {
  let metadata : Array[(String, String)] = [("title", "Song")]
  let encoded = encode_with_metadata(stereo_buffer(), @audio.I16, metadata) catch {
    (_ : @audio.AudioError) => panic()
  }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.meta("ANNO"), Some("title: Song"))
  assert_eq(info.meta("title"), None)
}

///|
test "chunk inventory and offsets" {
  let info = parse_info(
    encode(stereo_buffer()) catch {
      (_ : @audio.AudioError) => panic()
    },
  ) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(info.chunks.length(), 2)
  let comm = info.chunks[0]
  let ssnd = info.chunks[1]
  assert_eq(comm.0, "COMM")
  assert_eq(comm.1, 20)
  assert_eq(comm.2, 18)
  assert_eq(ssnd.0, "SSND")
  assert_eq(ssnd.1, 46)
  assert_eq(ssnd.2, 8 + 16)
  assert_eq(chunk_payload_offset(info, "SSND") + 8, 54)
  assert_eq(chunk_payload_offset(info, "MARK"), -1)
  assert_true(info.describe().contains("44100 Hz"))
  assert_true(info.describe().contains("16 bit"))
}

///|
test "odd length chunks are padded" {
  let comm = comm_at_rate(1, 2, 16, 44100.0, None)
  let name = ascii("abcde")
  let ssnd = ssnd_payload(bytes_of([0x40, 0x00, 0xC0, 0x00]), bytes_of([]), 0)
  let file = craft_aiff("AIFF", [("COMM", comm), ("NAME", name), ("SSND", ssnd)])
  let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.chunks.length(), 3)
  assert_eq(info.chunks[1].0, "NAME")
  assert_eq(info.chunks[1].2, 5)
  assert_eq(info.chunks[2].0, "SSND")
  assert_eq(info.meta("NAME"), Some("abcde"))
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.frames(), 2)
  assert_true((decoded.data[0] - 0.5).abs() < 1.0e-4)
}

///|
test "ssnd offset is honoured" {
  let comm = comm_at_rate(1, 2, 16, 22050.0, None)
  let ssnd = ssnd_payload(
    bytes_of([0x40, 0x00, 0xC0, 0x00]),
    bytes_of([0xAA, 0xBB, 0xCC, 0xDD]),
    0,
  )
  let file = craft_aiff("AIFF", [("COMM", comm), ("SSND", ssnd)])
  let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.frames, 2)
  assert_eq(info.chunks[1].2, 8 + 4 + 4)
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.frames(), 2)
  assert_true((decoded.data[0] - 0.5).abs() < 1.0e-4)
  assert_true((decoded.data[1] + 0.5).abs() < 1.0e-4)
}

///|
test "comm frame count is clamped to the ssnd bytes" {
  let comm = comm_at_rate(1, 8, 16, 44100.0, None)
  let ssnd = ssnd_payload(bytes_of([0x40, 0x00, 0xC0, 0x00]), bytes_of([]), 0)
  let file = craft_aiff("AIFF", [("COMM", comm), ("SSND", ssnd)])
  let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.frames, 2)
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.frames(), 2)
}

///|
test "mark inst and comt chunks are skipped safely" {
  let comm = comm_at_rate(1, 2, 16, 44100.0, None)
  let mark = bytes_of([0x00, 0x01, 0x00])
  let inst = bytes_of([
    0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ])
  let comt = bytes_of([
    0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x68, 0x69, 0x21,
  ])
  let ssnd = ssnd_payload(bytes_of([0x40, 0x00, 0xC0, 0x00]), bytes_of([]), 0)
  let file = craft_aiff("AIFF", [
    ("COMM", comm),
    ("MARK", mark),
    ("INST", inst),
    ("COMT", comt),
    ("SSND", ssnd),
  ])
  let info = parse_info(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.chunks.length(), 5)
  assert_eq(info.chunks[1].0, "MARK")
  assert_eq(info.chunks[2].0, "INST")
  assert_eq(info.chunks[3].0, "COMT")
  assert_eq(info.chunks[4].0, "SSND")
  let decoded = decode(file) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.frames(), 2)
  assert_true((decoded.data[0] - 0.5).abs() < 1.0e-4)
}

///|
test "empty buffer roundtrip" {
  let source = @audio.AudioBuffer::new(8000, 1)
  let encoded = encode(source) catch { (_ : @audio.AudioError) => panic() }
  let info = parse_info(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.frames, 0)
  assert_eq(info.chunks[1].2, 8)
  let decoded = decode(encoded) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(decoded.frames(), 0)
  assert_eq(decoded.channels, 1)
}

///|
test "truncated header is reported" {
  assert_eq(decode_error_kind(ascii("FORM")), "truncated")
  assert_eq(info_error_kind(ascii("FOR")), "truncated")
  assert_eq(decode_error_kind(ascii("")), "truncated")
}

///|
test "missing comm chunk raises invalid" {
  let ssnd = ssnd_payload(bytes_of([0x40, 0x00]), bytes_of([]), 0)
  let file = craft_aiff("AIFF", [("SSND", ssnd)])
  assert_eq(info_error_kind(file), "invalid")
  assert_eq(decode_error_kind(file), "invalid")
}

///|
test "missing ssnd chunk raises invalid" {
  let comm = comm_at_rate(1, 2, 16, 44100.0, None)
  let file = craft_aiff("AIFF", [("COMM", comm)])
  assert_eq(info_error_kind(file), "invalid")
  assert_eq(decode_error_kind(file), "invalid")
}

///|
test "unsupported compression is rejected" {
  let comm = comm_at_rate(1, 2, 16, 44100.0, Some("ima4"))
  let ssnd = ssnd_payload(bytes_of([0x40, 0x00, 0xC0, 0x00]), bytes_of([]), 0)
  let file = craft_aiff("AIFC", [("COMM", comm), ("SSND", ssnd)])
  assert_eq(info_error_kind(file), "unsupported")
  assert_eq(decode_error_kind(file), "unsupported")
  // A known compression type with the wrong sample width is rejected too.
  let mismatch = comm_at_rate(1, 2, 16, 44100.0, Some("fl32"))
  let file32 = craft_aiff("AIFC", [("COMM", mismatch), ("SSND", ssnd)])
  assert_eq(info_error_kind(file32), "unsupported")
}

///|
test "form type must be aiff or aifc" {
  assert_eq(decode_error_kind(ascii("MThdMThdMThd")), "unsupported")
  let comm = comm_at_rate(1, 2, 16, 44100.0, None)
  let ssnd = ssnd_payload(bytes_of([0x40, 0x00, 0xC0, 0x00]), bytes_of([]), 0)
  let file = craft_aiff("AIFX", [("COMM", comm), ("SSND", ssnd)])
  assert_eq(decode_error_kind(file), "unsupported")
}

///|
test "too short comm chunk raises invalid" {
  let comm = bytes_of([0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x10])
  let ssnd = ssnd_payload(bytes_of([0x40, 0x00]), bytes_of([]), 0)
  let file = craft_aiff("AIFF", [("COMM", comm), ("SSND", ssnd)])
  assert_eq(info_error_kind(file), "invalid")
}

///|
test "ssnd offset past the payload raises invalid" {
  let comm = comm_at_rate(1, 2, 16, 44100.0, None)
  let ssnd = @buffer.Buffer::Buffer(size_hint=12)
  put_u32be(ssnd, 100L)
  put_u32be(ssnd, 0L)
  ssnd.write_bytes(bytes_of([0x40, 0x00]))
  let file = craft_aiff("AIFF", [("COMM", comm), ("SSND", ssnd.to_bytes())])
  assert_eq(info_error_kind(file), "invalid")
  assert_eq(decode_error_kind(file), "invalid")
}
