// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Greatest common divisor of two integers, always non-negative.
///
/// `gcd(0, 0)` is `0` and `gcd(0, n)` is `|n|`, so the helper is total and can
/// be used to reduce a sample-rate pair without special cases.
pub fn gcd(a : Int32, b : Int32) -> Int32 {
  let mut x = a.abs()
  let mut y = b.abs()
  while y != 0 {
    let remainder = x % y
    x = y
    y = remainder
  }
  x
}

///|
/// Reduce the rate pair `from_rate : to_rate` by their greatest common divisor.
///
/// This is the integer form of the conversion ratio: an `44100 -> 48000`
/// conversion becomes `147 : 160`, i.e. 160 output frames for every 147 input
/// frames. Reducing the ratio is what makes the output length deterministic —
/// [`sample_count`] is a pure integer computation, so the same input always
/// produces the same number of frames, independent of floating point rounding.
/// Non-positive rates are returned unchanged so callers can validate them.
pub fn reduce_ratio(from_rate : Int32, to_rate : Int32) -> (Int32, Int32) {
  if from_rate <= 0 || to_rate <= 0 {
    return (from_rate, to_rate)
  }
  let divisor = gcd(from_rate, to_rate)
  if divisor <= 1 {
    (from_rate, to_rate)
  } else {
    (from_rate / divisor, to_rate / divisor)
  }
}

///|
/// Number of output frames produced when `frames` frames at `from_rate` are
/// resampled to `to_rate`.
///
/// The result is the ceiling of `frames * to_rate / from_rate`: rounding up
/// keeps the last partial period of the input inside the output, and an
/// identical rate pair is the identity (`sample_count(n, r, r) == n`). The
/// product is computed in `Int64` so realistic rates cannot overflow.
pub fn sample_count(
  frames : Int32,
  from_rate : Int32,
  to_rate : Int32,
) -> Int32 {
  if frames <= 0 || from_rate <= 0 || to_rate <= 0 {
    return 0
  }
  let numerator = frames.to_int64() * to_rate.to_int64()
  let denominator = from_rate.to_int64()
  ((numerator + denominator - 1L) / denominator).to_int()
}
