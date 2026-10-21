// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Render `value` with exactly `digits` fractional digits.
///
/// MoonBit has no `printf`, so the fixed width numbers used by the CSV export,
/// the SVG heat map and the statistics report are assembled by hand: scale by
/// `10^digits`, round to an integer, then split the integer into whole and
/// fractional parts and pad the fraction with leading zeros.
///
/// Non finite values render as `nan`, `inf` and `-inf` (all SVG and CSV safe),
/// magnitudes beyond `1e9` fall back to the shortest round trip form so the
/// integer conversion can never overflow, and `digits` is clamped to
/// `[0, 9]`.
fn format_fixed(value : Double, digits : Int32) -> String {
  if value.is_nan() {
    return "nan"
  }
  if value.is_pos_inf() {
    return "inf"
  }
  if value.is_neg_inf() {
    return "-inf"
  }
  let places = if digits < 0 { 0 } else if digits > 9 { 9 } else { digits }
  let scale = @math.pow(10.0, places.to_double())
  let scaled = (value * scale).round()
  if scaled.abs() >= 1000000000.0 {
    return "\{value}"
  }
  let total = scaled.to_int()
  let magnitude = if total < 0 { -total } else { total }
  let divisor = scale.to_int()
  let whole = magnitude / divisor
  let fraction = magnitude % divisor
  let sign = if total < 0 { "-" } else { "" }
  if places == 0 {
    return sign + "\{whole}"
  }
  let text = "\{fraction}"
  let padding = places - text.length()
  let padded = if padding > 0 { "0".repeat(padding) + text } else { text }
  sign + "\{whole}" + "." + padded
}

///|
/// Render a `[0, 1]` position with three decimals, the precision the SVG
/// geometry uses.
fn format_position(value : Double) -> String {
  format_fixed(value, 3)
}

///|
/// Turn the UTF-8 bytes accumulated in a buffer into a `String`.
///
/// `Buffer::to_string` is not used here: on this toolchain it reinterprets the
/// stored bytes instead of decoding them, which turns text into mojibake. Going
/// through `to_bytes` and an explicit lossy UTF-8 decode keeps the CSV, SVG and
/// report text intact.
fn buffer_text(buffer : @buffer.Buffer) -> String {
  @utf8.decode_lossy(buffer.to_bytes()[:])
}
