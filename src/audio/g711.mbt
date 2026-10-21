// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// G.711 mu-law expansion, as used by `WAVE_FORMAT_MULAW` and Sun `.au`
/// encoding 1.
///
/// The table is generated arithmetically instead of stored, which keeps the
/// decoder allocation free and exact.
pub fn mulaw_decode(byte : Int32) -> Double {
  let inverted = byte.lnot() & 0xFF
  let sign = if (inverted & 0x80) != 0 { -1.0 } else { 1.0 }
  let exponent = (inverted >> 4) & 0x07
  let mantissa = inverted & 0x0F
  let magnitude = (((mantissa << 3) + 0x84) << exponent) - 0x84
  sign * magnitude.to_double() / 32768.0
}

///|
/// G.711 A-law expansion, as used by `WAVE_FORMAT_ALAW` and Sun `.au`
/// encoding 27.
pub fn alaw_decode(byte : Int32) -> Double {
  let value = byte ^ 0x55
  let sign = if (value & 0x80) != 0 { 1.0 } else { -1.0 }
  let exponent = (value >> 4) & 0x07
  let mantissa = value & 0x0F
  let magnitude = if exponent == 0 {
    (mantissa << 4) + 8
  } else {
    ((mantissa << 4) + 0x108) << (exponent - 1)
  }
  sign * magnitude.to_double() / 32768.0
}

///|
/// G.711 mu-law compression, the inverse of [`mulaw_decode`].
pub fn mulaw_encode(sample : Double) -> Int32 {
  let value = clamp_sample(sample) * 32768.0
  let sign : Int32 = if value < 0.0 { 0x80 } else { 0x00 }
  let magnitude = if value < 0.0 { -value } else { value }
  let clipped = magnitude.to_int().min(32635)
  let biased = clipped + 0x84
  let exponent = highest_set_bit(biased >> 7)
  let mantissa = (biased >> (exponent + 3)) & 0x0F
  (sign | (exponent << 4) | mantissa).lnot() & 0xFF
}

///|
/// G.711 A-law compression, the inverse of [`alaw_decode`].
pub fn alaw_encode(sample : Double) -> Int32 {
  let value = clamp_sample(sample) * 32768.0
  let sign : Int32 = if value >= 0.0 { 0x80 } else { 0x00 }
  let magnitude = if value < 0.0 { -value } else { value }
  let mut biased = magnitude.to_int()
  if biased > 32767 {
    biased = 32767
  }
  let mut encoded = if biased < 256 {
    biased >> 4
  } else {
    let exponent = highest_set_bit(biased >> 8)
    ((exponent + 1) << 4) | ((biased >> (exponent + 3)) & 0x0F)
  }
  encoded = (encoded | sign) ^ 0x55
  encoded & 0xFF
}

///|
/// Index of the highest set bit of a non-negative `Int32`.
fn highest_set_bit(value : Int32) -> Int32 {
  let mut index = 0
  let mut remaining = value
  while remaining > 1 {
    remaining = remaining >> 1
    index = index + 1
  }
  index
}
