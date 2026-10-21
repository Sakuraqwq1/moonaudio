// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Bounds check used by every byte level reader.
///
/// Audio containers are read from untrusted files, so every multi-byte read is
/// guarded: a malformed length must surface as a `Truncated` error instead of a
/// trap.
pub fn require_bytes(
  data : Bytes,
  offset : Int32,
  length : Int32,
  what : String,
) -> Unit raise AudioError {
  if offset < 0 || length < 0 || offset + length > data.length() {
    raise Truncated(
      "\{what}: need \{length} byte(s) at offset \{offset}, file has \{data.length()}",
    )
  }
}

///|
/// Read one unsigned byte.
pub fn read_u8(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  require_bytes(data, offset, 1, "u8")
  data.at(offset).to_int()
}

///|
/// Read a little endian unsigned 16 bit integer.
pub fn read_u16le(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  require_bytes(data, offset, 2, "u16le")
  data.at(offset).to_int() | (data.at(offset + 1).to_int() << 8)
}

///|
/// Read a big endian unsigned 16 bit integer.
pub fn read_u16be(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  require_bytes(data, offset, 2, "u16be")
  (data.at(offset).to_int() << 8) | data.at(offset + 1).to_int()
}

///|
/// Read a little endian unsigned 24 bit integer.
pub fn read_u24le(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  require_bytes(data, offset, 3, "u24le")
  data.at(offset).to_int() |
  (data.at(offset + 1).to_int() << 8) |
  (data.at(offset + 2).to_int() << 16)
}

///|
/// Read a big endian unsigned 24 bit integer.
pub fn read_u24be(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  require_bytes(data, offset, 3, "u24be")
  (data.at(offset).to_int() << 16) |
  (data.at(offset + 1).to_int() << 8) |
  data.at(offset + 2).to_int()
}

///|
/// Read a little endian unsigned 32 bit integer, widened to `Int64` so the
/// value stays positive.
pub fn read_u32le(data : Bytes, offset : Int32) -> Int64 raise AudioError {
  require_bytes(data, offset, 4, "u32le")
  data.at(offset).to_int64() |
  (data.at(offset + 1).to_int64() << 8) |
  (data.at(offset + 2).to_int64() << 16) |
  (data.at(offset + 3).to_int64() << 24)
}

///|
/// Read a big endian unsigned 32 bit integer, widened to `Int64`.
pub fn read_u32be(data : Bytes, offset : Int32) -> Int64 raise AudioError {
  require_bytes(data, offset, 4, "u32be")
  (data.at(offset).to_int64() << 24) |
  (data.at(offset + 1).to_int64() << 16) |
  (data.at(offset + 2).to_int64() << 8) |
  data.at(offset + 3).to_int64()
}

///|
/// Read a little endian signed 16 bit integer, sign extended to `Int32`.
pub fn read_i16le(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  sign_extend(read_u16le(data, offset), 16)
}

///|
/// Read a big endian signed 16 bit integer, sign extended to `Int32`.
pub fn read_i16be(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  sign_extend(read_u16be(data, offset), 16)
}

///|
/// Read a little endian signed 24 bit integer, sign extended to `Int32`.
pub fn read_i24le(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  sign_extend(read_u24le(data, offset), 24)
}

///|
/// Read a big endian signed 24 bit integer, sign extended to `Int32`.
pub fn read_i24be(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  sign_extend(read_u24be(data, offset), 24)
}

///|
/// Read a little endian signed 32 bit integer.
pub fn read_i32le(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  require_bytes(data, offset, 4, "i32le")
  data.at(offset).to_int() |
  (data.at(offset + 1).to_int() << 8) |
  (data.at(offset + 2).to_int() << 16) |
  (data.at(offset + 3).to_int() << 24)
}

///|
/// Read a big endian signed 32 bit integer.
pub fn read_i32be(data : Bytes, offset : Int32) -> Int32 raise AudioError {
  require_bytes(data, offset, 4, "i32be")
  (data.at(offset).to_int() << 24) |
  (data.at(offset + 1).to_int() << 16) |
  (data.at(offset + 2).to_int() << 8) |
  data.at(offset + 3).to_int()
}

///|
/// Read a little endian IEEE 754 single precision sample.
pub fn read_f32le(data : Bytes, offset : Int32) -> Double raise AudioError {
  f32_bits_to_double(read_u32le(data, offset))
}

///|
/// Read a big endian IEEE 754 single precision sample.
pub fn read_f32be(data : Bytes, offset : Int32) -> Double raise AudioError {
  f32_bits_to_double(read_u32be(data, offset))
}

///|
/// Read a little endian IEEE 754 double precision sample.
pub fn read_f64le(data : Bytes, offset : Int32) -> Double raise AudioError {
  require_bytes(data, offset, 8, "f64le")
  let mut bits = 0L
  for index = 7; index >= 0; index = index - 1 {
    bits = (bits << 8) | data.at(offset + index).to_int64()
  }
  bits.reinterpret_as_double()
}

///|
/// Read a big endian IEEE 754 double precision sample.
pub fn read_f64be(data : Bytes, offset : Int32) -> Double raise AudioError {
  require_bytes(data, offset, 8, "f64be")
  let mut bits = 0L
  for index = 0; index < 8; index = index + 1 {
    bits = (bits << 8) | data.at(offset + index).to_int64()
  }
  bits.reinterpret_as_double()
}

///|
/// Read `length` bytes as an ASCII string.
pub fn read_ascii(
  data : Bytes,
  offset : Int32,
  length : Int32,
) -> String raise AudioError {
  require_bytes(data, offset, length, "ascii")
  @utf8.decode_lossy(data.exact_view(start=offset, end=offset + length))
}

///|
/// `true` when `data[offset .. offset + length]` equals `expected`.
pub fn ascii_is(
  data : Bytes,
  offset : Int32,
  length : Int32,
  expected : String,
) -> Bool {
  if offset < 0 || length < 0 || offset + length > data.length() {
    return false
  }
  if length != expected.length() {
    return false
  }
  for index = 0; index < length; index = index + 1 {
    if data.at(offset + index).to_int() != expected.at(index).to_int() {
      return false
    }
  }
  true
}

///|
/// Interpret `length` bytes starting at `offset` as ASCII, or `None` when the
/// range leaves the buffer.
pub fn ascii_at(data : Bytes, offset : Int32, length : Int32) -> String? {
  if offset < 0 || length < 0 || offset + length > data.length() {
    return None
  }
  Some(@utf8.decode_lossy(data.exact_view(start=offset, end=offset + length)))
}

///|
/// Little endian 16 bit pair of bytes, handy for chunk headers.
pub fn u16le_bytes(value : Int32) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=2)
  buffer.write_byte((value & 0xFF).to_byte())
  buffer.write_byte(((value >> 8) & 0xFF).to_byte())
  buffer.to_bytes()
}
