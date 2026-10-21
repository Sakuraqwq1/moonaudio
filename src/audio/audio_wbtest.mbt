// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Build a `Bytes` value from a list of byte values; keeps test fixtures
/// readable without depending on escape syntax.
fn bytes_from(values : Array[Int32]) -> Bytes {
  let out : Array[Byte] = []
  for value in values {
    out.push(value.to_byte())
  }
  Bytes::from_array(out[:])
}

///|
/// Build a `Bytes` value from ASCII text.
fn ascii_bytes(text : String) -> Bytes {
  let out : Array[Byte] = []
  for c in text {
    out.push(c.to_int().to_byte())
  }
  Bytes::from_array(out[:])
}

///|
/// A two channel ramp buffer at 8 kHz, built directly to keep the helper
/// non-raising.
fn ramp_buffer() -> AudioBuffer {
  AudioBuffer::{
    sample_rate: 8000,
    channels: 2,
    data: [-0.5, 0.5, -0.25, 0.25, 0.0, 1.0, 0.75, -1.0],
  }
}

///|
/// Return the kind of the error raised by parsing `name`, or `"ok"`.
fn parse_error_kind(name : String) -> String {
  let mut result = "ok"
  let _ = SampleFormat::parse(name) catch {
    (error : AudioError) => {
      result = error.kind()
      U8
    }
  }
  result
}

///|
/// Return the kind of the error raised by a short read, or `"ok"`.
fn short_read_kind() -> String {
  let mut result = "ok"
  let _ = read_u16le(Bytes::make(0, 0), 0) catch {
    (error : AudioError) => {
      result = error.kind()
      0
    }
  }
  result
}

///|
/// Return the kind of the error raised by an out of range ASCII read.
fn ascii_read_kind() -> String {
  let mut result = "ok"
  let _ = read_ascii(ascii_bytes("RIFF"), 0, 9) catch {
    (error : AudioError) => {
      result = error.kind()
      ""
    }
  }
  result
}

///|
test "buffer geometry and sampling" {
  let buffer = ramp_buffer()
  assert_eq(buffer.frames(), 4)
  assert_eq(buffer.channels, 2)
  assert_eq(buffer.sample_rate, 8000)
  assert_true((buffer.duration_seconds() - 0.0005).abs() < 1.0e-9)
  assert_eq(buffer.sample(0, 0), -0.5)
  assert_eq(buffer.sample(3, 1), -1.0)
  assert_eq(buffer.sample(99, 0), 0.0)
  assert_eq(buffer.sample(0, 9), 0.0)
  assert_eq(buffer.is_empty(), false)
}

///|
test "peak, rms and normalisation" {
  let buffer = ramp_buffer()
  assert_eq(buffer.peak(), 1.0)
  assert_true(buffer.rms() > 0.5 && buffer.rms() < 0.7)
  let quiet = AudioBuffer::silence(8000, 1, 2) catch {
    (_ : AudioError) => panic()
  }
  quiet.set_sample(0, 0, 0.25)
  quiet.set_sample(1, 0, -0.5)
  assert_eq(quiet.normalize(target=1.0), 2.0)
  assert_eq(quiet.peak(), 1.0)
  let silent = AudioBuffer::silence(8000, 1, 2) catch {
    (_ : AudioError) => panic()
  }
  assert_eq(silent.normalize(), 1.0)
}

///|
test "channel conversion" {
  let buffer = ramp_buffer()
  let mono = buffer.remix(1) catch { (_ : AudioError) => panic() }
  assert_eq(mono.channels, 1)
  assert_eq(mono.frames(), 4)
  assert_eq(mono.sample(0, 0), 0.0)
  assert_eq(mono.sample(2, 0), 0.5)
  let copied = mono.remix(2) catch { (_ : AudioError) => panic() }
  assert_eq(copied.sample(2, 0), 0.5)
  assert_eq(copied.sample(2, 1), 0.5)
  let six = buffer.remix(6) catch { (_ : AudioError) => panic() }
  assert_eq(six.channels, 6)
  assert_eq(six.sample(3, 5), -0.125)
}

///|
test "slice and append" {
  let buffer = ramp_buffer()
  let head = buffer.slice(0, 2)
  assert_eq(head.frames(), 2)
  let tail = buffer.slice(2, 4)
  head.append(tail) catch {
    (_ : AudioError) => panic()
  }
  assert_eq(head.frames(), 4)
  assert_eq(head.sample(3, 1), -1.0)
  assert_eq(buffer.slice(3, 99).frames(), 1)
  assert_eq(buffer.slice(9, 99).frames(), 0)
}

///|
test "from_channels interleaves" {
  let left : Array[Double] = [0.0, 0.5]
  let right : Array[Double] = [0.25, -0.25]
  let buffer = AudioBuffer::from_channels(44100, [left, right]) catch {
    (_ : AudioError) => panic()
  }
  assert_eq(buffer.frames(), 2)
  assert_eq(buffer.sample(1, 0), 0.5)
  assert_eq(buffer.sample(1, 1), -0.25)
  let split = buffer.to_channels()
  assert_eq(split.length(), 2)
  assert_eq(split[0][0], 0.0)
  assert_eq(split[1][1], -0.25)
}

///|
test "sample format metadata" {
  assert_eq(U8.bits(), 8)
  assert_eq(I24.bytes(), 3)
  assert_true(F32.is_float())
  assert_true(!I16.is_float())
  assert_eq(I16.max_code(), 32767.0)
  assert_eq(I16.to_name(), "s16")
  let parsed = SampleFormat::parse("s24") catch { (_ : AudioError) => panic() }
  assert_eq(parsed.to_name(), "s24")
  assert_eq(parse_error_kind("nope"), "invalid")
  assert_eq(parse_error_kind("s16"), "ok")
}

///|
test "quantise and dequantise" {
  assert_eq(quantize(0.0, I16), 0)
  assert_eq(quantize(1.0, I16), 32767)
  assert_eq(quantize(-1.0, I16), -32768)
  assert_eq(quantize(3.0, I16), 32767)
  assert_eq(quantize(-3.0, U8), 0)
  assert_eq(quantize(0.0, U8), 128)
  assert_true((dequantize(16384, I16) - 0.5).abs() < 1.0e-9)
  assert_true((dequantize(128, U8) - 0.00392156862745098).abs() < 1.0e-9)
  assert_eq(clamp_sample(@double.not_a_number), 0.0)
}

///|
test "float32 bit patterns" {
  assert_eq(f32_bits_to_double(0L), 0.0)
  assert_eq(f32_bits_to_double(0x3F800000L), 1.0)
  assert_eq(f32_bits_to_double(0xBF800000L), -1.0)
  assert_eq(f32_bits_to_double(0x40490FDBL), 3.1415927410125732)
  assert_eq(double_to_f32_bits(1.0), 0x3F800000L)
  assert_eq(double_to_f32_bits(-1.0), 0xBF800000L)
  assert_eq(f32_bits_to_double(double_to_f32_bits(0.75)), 0.75)
  assert_eq(f32_bits_to_double(double_to_f32_bits(1.0e40)), @double.infinity)
}

///|
test "g711 roundtrip stays close" {
  let samples : Array[Double] = [0.0, 0.1, -0.1, 0.5, -0.5, 0.9, -0.9]
  for sample in samples {
    let decoded = mulaw_decode(mulaw_encode(sample))
    assert_true((decoded - sample).abs() < 0.1 * sample.abs() + 0.05)
    let alaw = alaw_decode(alaw_encode(sample))
    assert_true((alaw - sample).abs() < 0.15 * sample.abs() + 0.05)
  }
}

///|
test "decibel helpers" {
  assert_eq(dbfs(1.0), 0.0)
  assert_true((dbfs(0.5) + 6.020599913279624).abs() < 1.0e-9)
  assert_true(dbfs(0.0) == @double.neg_infinity)
  assert_true((from_dbfs(0.0) - 1.0).abs() < 1.0e-12)
}

///|
test "byte readers and bounds" {
  let bytes = bytes_from([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
  let low16 = read_u16le(bytes, 0) catch { (_ : AudioError) => panic() }
  assert_eq(low16, 0x0201)
  let high16 = read_u16be(bytes, 0) catch { (_ : AudioError) => panic() }
  assert_eq(high16, 0x0102)
  let low24 = read_u24le(bytes, 0) catch { (_ : AudioError) => panic() }
  assert_eq(low24, 0x030201)
  let high24 = read_u24be(bytes, 0) catch { (_ : AudioError) => panic() }
  assert_eq(high24, 0x010203)
  let neg24 = read_i24le(bytes_from([0xFF, 0xFF, 0xFF]), 0) catch {
    (_ : AudioError) => panic()
  }
  assert_eq(neg24, -1)
  let neg16 = read_i16le(bytes_from([0xFE, 0xFF]), 0) catch {
    (_ : AudioError) => panic()
  }
  assert_eq(neg16, -2)
  let low = read_u32le(bytes, 0) catch { (_ : AudioError) => panic() }
  assert_eq(low, 0x04030201L)
  let high = read_u32be(bytes, 4) catch { (_ : AudioError) => panic() }
  assert_eq(high, 0x05060708L)
  let tag = read_ascii(ascii_bytes("RIFFxxxx"), 0, 4) catch {
    (_ : AudioError) => panic()
  }
  assert_eq(tag, "RIFF")
  assert_true(ascii_at(ascii_bytes("RIFF"), 0, 9) == None)
  assert_eq(short_read_kind(), "truncated")
  assert_eq(ascii_read_kind(), "truncated")
}
