// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// `2.0 ^ exponent` built by repeated scaling.
///
/// Scaling by two is exact until the value leaves the `Double` range, so this
/// helper keeps the 80 bit extended float conversion bit exact without pulling
/// in a floating point transcendental.
fn pow2(exponent : Int32) -> Double {
  let mut result = 1.0
  let mut remaining = exponent
  while remaining > 0 {
    result = result * 2.0
    remaining = remaining - 1
  }
  while remaining < 0 {
    result = result / 2.0
    remaining = remaining + 1
  }
  result
}

///|
/// Decode the 80 bit IEEE 754 extended float stored at `offset`.
///
/// AIFF keeps `sampleRate` as an extended precision value: one sign bit, a 15
/// bit biased exponent (bias 16383) and a 64 bit mantissa whose explicit
/// integer bit is the most significant bit. The layout is big-endian.
///
/// The reserved exponent `0x7FFF` (NaN and the infinities) is rejected, as is
/// any value whose magnitude cannot be represented by a `Double`; the sample
/// rates audio files actually use are converted exactly.
pub fn ext_float_to_double(
  bytes : Bytes,
  offset : Int32,
) -> Double raise @audio.AudioError {
  @audio.require_bytes(bytes, offset, 10, "80-bit extended float")
  let first = bytes.at(offset).to_int()
  let second = bytes.at(offset + 1).to_int()
  let negative = (first & 0x80) != 0
  let exponent = ((first & 0x7F) << 8) | second
  if exponent == 0x7FFF {
    raise @audio.Invalid("80-bit extended float is NaN or Infinity")
  }
  let high = @audio.read_u32be(bytes, offset + 2)
  let low = @audio.read_u32be(bytes, offset + 6)
  let mantissa = high.to_double() * 4294967296.0 + low.to_double()
  if exponent == 0 {
    if mantissa == 0.0 {
      return 0.0
    }
    raise @audio.OutOfRange(
      "80-bit extended float is denormal, below the Double range",
    )
  }
  let unbiased = exponent - 16383
  if unbiased > 1023 || unbiased < -1074 {
    raise @audio.OutOfRange(
      "80-bit extended float exponent \{unbiased} is outside the Double range",
    )
  }
  let magnitude = mantissa / 9223372036854775808.0 * pow2(unbiased)
  if negative {
    -magnitude
  } else {
    magnitude
  }
}

///|
/// Encode `value` as a 10 byte big-endian 80 bit IEEE 754 extended float.
///
/// NaN and the infinities have no defined representation in the AIFF
/// `sampleRate` field and are rejected with [`@audio.OutOfRange`]. Every finite
/// `Double` round trips through [`ext_float_to_double`] bit for bit; integer
/// sample rates such as 8000, 44100 or 96000 produce the canonical byte
/// pattern every other AIFF writer produces.
pub fn double_to_ext_float(value : Double) -> Bytes raise @audio.AudioError {
  if value.is_nan() {
    raise @audio.OutOfRange("cannot store NaN in an 80-bit extended float")
  }
  if value.abs() > 1.7976931348623157e308 {
    // Only an infinity is larger than the largest finite Double.
    raise @audio.OutOfRange("cannot store Infinity in an 80-bit extended float")
  }
  let negative = value < 0.0
  let magnitude = value.abs()
  let buffer = @buffer.Buffer::Buffer(size_hint=10)
  if magnitude == 0.0 {
    buffer.write_bytes(Bytes::make(10, 0))
    return buffer.to_bytes()
  }
  // Normalise to `magnitude = m * 2^exponent` with `m` in `[1.0, 2.0)`.
  let mut exponent = 0
  let mut m = magnitude
  while m >= 2.0 {
    m = m / 2.0
    exponent = exponent + 1
  }
  while m < 1.0 {
    m = m * 2.0
    exponent = exponent - 1
  }
  // `scaled = magnitude * 2^(63 - exponent)` lies in `[2^63, 2^64)`.
  let shift = 63 - exponent
  let scaled = if shift >= 0 {
    let first = if shift > 1000 { 1000 } else { shift }
    magnitude * pow2(first) * pow2(shift - first)
  } else {
    magnitude / pow2(-shift)
  }
  let high_d = (scaled / 4294967296.0).floor()
  let high = high_d.to_int64()
  let low = (scaled - high_d * 4294967296.0).to_int64()
  let biased = exponent + 16383
  let sign = if negative { 0x80 } else { 0 }
  buffer.write_byte((sign | ((biased >> 8) & 0x7F)).to_byte())
  buffer.write_byte((biased & 0xFF).to_byte())
  write_u32be_raw(buffer, high)
  write_u32be_raw(buffer, low)
  buffer.to_bytes()
}

///|
/// Write the low 32 bits of `value` big-endian into `buffer`.
fn write_u32be_raw(buffer : @buffer.Buffer, value : Int64) -> Unit {
  buffer.write_byte(((value >> 24) & 0xFFL).to_byte())
  buffer.write_byte(((value >> 16) & 0xFFL).to_byte())
  buffer.write_byte(((value >> 8) & 0xFFL).to_byte())
  buffer.write_byte((value & 0xFFL).to_byte())
}
