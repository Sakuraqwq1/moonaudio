// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Clamp a normalised sample into `[-1.0, 1.0]`, mapping NaN to `0.0`.
///
/// Every encoder in `moonaudio` funnels integer conversion through this
/// function, so a DSP stage that overshoots can never wrap around to the
/// opposite polarity.
pub fn clamp_sample(value : Double) -> Double {
  if value.is_nan() {
    0.0
  } else if value < -1.0 {
    -1.0
  } else if value > 1.0 {
    1.0
  } else {
    value
  }
}

///|
/// Convert a normalised sample to an integer code in `[min, max]`.
fn quantize_scaled(scaled : Double, min : Double, max : Double) -> Int32 {
  let value = if scaled.is_nan() {
    0.0
  } else if scaled <= min {
    min
  } else if scaled >= max {
    max
  } else {
    scaled
  }
  value.round().to_int()
}

///|
/// Convert a normalised sample to the integer code used by `format`.
///
/// Unsigned 8 bit uses offset binary (`0` is `-1.0`, `255` is `+1.0`); signed
/// formats use two's complement. Float formats return `0` and exist here only
/// so callers can treat every format uniformly.
pub fn quantize(value : Double, format : SampleFormat) -> Int32 {
  let sample = clamp_sample(value)
  match format {
    U8 => quantize_scaled(sample * 127.5 + 127.5, 0.0, 255.0)
    I16 => quantize_scaled(sample * 32768.0, -32768.0, 32767.0)
    I24 => quantize_scaled(sample * 8388608.0, -8388608.0, 8388607.0)
    I32 =>
      quantize_scaled(
        sample * 2147483648.0,
        -2147483648.0,
        2147483647.0,
      )
    F32 | F64 => 0
  }
}

///|
/// Convert an integer code of `format` back to a normalised sample.
pub fn dequantize(code : Int32, format : SampleFormat) -> Double {
  match format {
    U8 => (code.to_double() - 127.5) / 127.5
    I16 => code.to_double() / 32768.0
    I24 => code.to_double() / 8388608.0
    I32 => code.to_double() / 2147483648.0
    F32 | F64 => 0.0
  }
}

///|
/// Sign extend `raw` from `bits` bits to 32 bits.
///
/// Used by containers that keep samples at their native width but report a
/// different *valid* bit count (WAVE_FORMAT_EXTENSIBLE, 20 bit in 24 bit slots).
pub fn sign_extend(raw : Int32, bits : Int32) -> Int32 {
  if bits <= 0 || bits >= 32 {
    return raw
  }
  let shift = 32 - bits
  (raw << shift) >> shift
}

///|
/// Decode an IEEE 754 single precision pattern into a `Double`.
///
/// Implemented by hand so the library does not depend on a host float
/// reinterpretation intrinsic; the operation is exact for every finite value.
pub fn f32_bits_to_double(bits : Int64) -> Double {
  let sign = if ((bits >> 31) & 1L) == 1L { -1.0 } else { 1.0 }
  let exponent = ((bits >> 23) & 0xFF).to_int()
  let mantissa = (bits & 0x7FFFFF).to_double()
  if exponent == 0 {
    if mantissa == 0.0 {
      0.0 * sign
    } else {
      sign * (mantissa / 8388608.0) * @math.pow(2.0, -126.0)
    }
  } else if exponent == 255 {
    if mantissa == 0.0 {
      sign * @double.infinity
    } else {
      @double.not_a_number
    }
  } else {
    sign *
    (1.0 + mantissa / 8388608.0) *
    @math.pow(2.0, (exponent - 127).to_double())
  }
}

///|
/// Round to the nearest integer with ties to even, clamped to the `Int32`
/// range.
fn round_half_even(value : Double) -> Int32 {
  let floor = value.floor()
  let fraction = value - floor
  let rounded = if fraction > 0.5 {
    floor + 1.0
  } else if fraction < 0.5 {
    floor
  } else if (floor / 2.0).floor() * 2.0 == floor {
    floor
  } else {
    floor + 1.0
  }
  if rounded > 2147483647.0 {
    2147483647
  } else if rounded < -2147483648.0 {
    -2147483648
  } else {
    rounded.to_int()
  }
}

///|
/// Encode a `Double` as an IEEE 754 single precision bit pattern.
///
/// Values outside the single precision range saturate to infinity and NaN is
/// canonicalised, which keeps encoder output deterministic.
pub fn double_to_f32_bits(value : Double) -> Int64 {
  if value.is_nan() {
    return 0x7FC00000L
  }
  let mut sign = 0L
  let mut magnitude = value
  if magnitude < 0.0 {
    sign = 1L
    magnitude = -magnitude
  }
  if magnitude == 0.0 {
    return sign << 31
  }
  let exponent = @math.log2(magnitude).floor().to_int()
  if exponent > 127 {
    return (sign << 31) | 0x7F800000L
  }
  if exponent < -126 {
    let scaled = magnitude / @math.pow(2.0, -149.0)
    let mantissa = round_half_even(scaled).to_int64()
    if mantissa <= 0L {
      return sign << 31
    }
    return (sign << 31) | mantissa
  }
  let biased = (exponent + 127).to_int64()
  let fraction = (magnitude / @math.pow(2.0, exponent.to_double()) - 1.0) *
    8388608.0
  let mantissa = round_half_even(fraction)
  if mantissa >= 8388608 {
    return (sign << 31) | ((biased + 1) << 23)
  }
  (sign << 31) | (biased << 23) | mantissa.to_int64()
}
