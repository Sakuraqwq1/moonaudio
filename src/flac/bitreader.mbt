// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Most significant bit first bit reader over a byte buffer.
///
/// FLAC stores everything (frame headers, subframe headers, Rice codes) in a
/// single MSB-first bit stream, so every reader in this package goes through
/// this type. Reads are bounds checked: running past the end raises
/// `Truncated` instead of returning zero, because a truncated frame is a
/// corrupt file rather than silence.
pub(all) struct BitReader {
  data : Bytes
  mut bit : Int32
}

///|
/// Create a reader positioned at `bit` (0 means the most significant bit of
/// `data[0]`).
pub fn BitReader::new(data : Bytes, bit? : Int32 = 0) -> BitReader {
  BitReader::{ data, bit }
}

///|
/// Current bit position from the start of the buffer.
pub fn BitReader::position(self : BitReader) -> Int32 {
  self.bit
}

///|
/// Total number of bits still available.
pub fn BitReader::remaining(self : BitReader) -> Int32 {
  self.data.length() * 8 - self.bit
}

///|
/// `true` when at least `count` bits remain.
pub fn BitReader::has(self : BitReader, count : Int32) -> Bool {
  self.remaining() >= count
}

///|
/// Read a single bit as 0 or 1.
pub fn BitReader::read_bit(self : BitReader) -> Int32 raise @audio.AudioError {
  if self.bit >= self.data.length() * 8 {
    raise @audio.Truncated("bit stream ended while reading a bit")
  }
  let byte = self.data.at(self.bit / 8).to_int()
  let shift = 7 - self.bit % 8
  self.bit = self.bit + 1
  (byte >> shift) & 1
}

///|
/// Read `count` bits (0..=31) as an unsigned integer.
pub fn BitReader::read_bits(
  self : BitReader,
  count : Int32,
) -> Int32 raise @audio.AudioError {
  if count < 0 || count > 31 {
    raise @audio.Invalid("read_bits supports 0..=31 bits, got \{count}")
  }
  let mut value = 0
  let mut left = count
  while left > 0 {
    let byte_remaining = 8 - self.bit % 8
    let take = if left < byte_remaining { left } else { byte_remaining }
    let byte = self.data.at(self.bit / 8).to_int()
    let shift = byte_remaining - take
    let chunk = (byte >> shift) & ((1 << take) - 1)
    value = (value << take) | chunk
    self.bit = self.bit + take
    left = left - take
  }
  if self.bit > self.data.length() * 8 {
    raise @audio.Truncated("bit stream ended inside read_bits")
  }
  value
}

///|
/// Read `count` bits (0..=63) as an unsigned integer widened to `Int64`.
pub fn BitReader::read_bits64(
  self : BitReader,
  count : Int32,
) -> Int64 raise @audio.AudioError {
  if count < 0 || count > 63 {
    raise @audio.Invalid("read_bits64 supports 0..=63 bits, got \{count}")
  }
  if count <= 31 {
    return self.read_bits(count).to_int64()
  }
  let mut value = 0L
  let mut left = count
  while left > 0 {
    let take = if left > 24 { 24 } else { left }
    value = (value << take) | self.read_bits(take).to_int64()
    left = left - take
  }
  value
}

///|
/// Read `count` bits as a two's complement signed integer.
pub fn BitReader::read_signed(
  self : BitReader,
  count : Int32,
) -> Int32 raise @audio.AudioError {
  let raw = self.read_bits(count)
  @audio.sign_extend(raw, count)
}

///|
/// Read `count` bits as a two's complement signed 64 bit integer.
pub fn BitReader::read_signed64(
  self : BitReader,
  count : Int32,
) -> Int64 raise @audio.AudioError {
  let raw = self.read_bits64(count)
  if count <= 0 || count >= 64 {
    return raw
  }
  let shift = 64 - count
  (raw << shift) >> shift
}

///|
/// Count zero bits until the next one bit (the one bit is consumed).
///
/// A run longer than `limit` is rejected: the guard keeps a corrupt stream from
/// spinning for megabytes.
pub fn BitReader::read_unary(
  self : BitReader,
  limit? : Int32 = 1 << 20,
) -> Int32 raise @audio.AudioError {
  let mut count = 0
  while self.read_bit() == 0 {
    count = count + 1
    if count > limit {
      raise @audio.Invalid("unary code exceeded \{limit} zero bits")
    }
  }
  count
}

///|
/// Skip to the next byte boundary.
pub fn BitReader::align(self : BitReader) -> Unit {
  let remainder = self.bit % 8
  if remainder != 0 {
    self.bit = self.bit + (8 - remainder)
  }
}

///|
/// Read one whole byte, aligning first when needed.
pub fn BitReader::read_byte(self : BitReader) -> Int32 raise @audio.AudioError {
  if self.bit % 8 != 0 {
    raise @audio.Invalid("read_byte requires a byte aligned stream")
  }
  if self.bit + 8 > self.data.length() * 8 {
    raise @audio.Truncated("bit stream ended while reading a byte")
  }
  let value = self.data.at(self.bit / 8).to_int()
  self.bit = self.bit + 8
  value
}

///|
/// Read `count` whole bytes as a `Bytes` slice.
pub fn BitReader::read_bytes(
  self : BitReader,
  count : Int32,
) -> Bytes raise @audio.AudioError {
  if self.bit % 8 != 0 {
    raise @audio.Invalid("read_bytes requires a byte aligned stream")
  }
  if count < 0 || self.bit + count * 8 > self.data.length() * 8 {
    raise @audio.Truncated("bit stream ended while reading \{count} bytes")
  }
  let start = self.bit / 8
  self.bit = self.bit + count * 8
  self.data.exact_view(start=start, end=start + count).to_owned()
}

///|
/// Read FLAC's UTF-8-style coded frame/sample number.
///
/// The encoding is UTF-8 with the 16 bit surrogate range allowed, so the value
/// can exceed the Unicode limit; it is returned as `Int64`.
pub fn BitReader::read_utf8_uint(self : BitReader) -> Int64 raise @audio.AudioError {
  let first = self.read_byte()
  if first < 0x80 {
    return first.to_int64()
  }
  let mut extra = 0
  let mut value = 0L
  if (first & 0xE0) == 0xC0 {
    extra = 1
    value = (first & 0x1F).to_int64()
  } else if (first & 0xF0) == 0xE0 {
    extra = 2
    value = (first & 0x0F).to_int64()
  } else if (first & 0xF8) == 0xF0 {
    extra = 3
    value = (first & 0x07).to_int64()
  } else if (first & 0xFC) == 0xF8 {
    extra = 4
    value = (first & 0x03).to_int64()
  } else if (first & 0xFE) == 0xFC {
    extra = 5
    value = (first & 0x01).to_int64()
  } else if first == 0xFE {
    extra = 6
    value = 0L
  } else {
    raise @audio.Invalid("invalid UTF-8 leading byte 0x\{first}")
  }
  for _index = 0; _index < extra; _index = _index + 1 {
    let next = self.read_byte()
    if (next & 0xC0) != 0x80 {
      raise @audio.Invalid("invalid UTF-8 continuation byte")
    }
    value = (value << 6) | (next & 0x3F).to_int64()
  }
  value
}
