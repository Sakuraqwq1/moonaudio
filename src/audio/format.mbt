// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Encoding of a single sample as stored in a container.
///
/// `moonaudio` always decodes samples to `Double` in the closed interval
/// `[-1.0, 1.0]`, so this type only describes the *source* (or requested
/// target) representation.
pub(all) enum SampleFormat {
  /// Unsigned 8 bit, offset binary (0..255 maps to -1.0..1.0).
  U8
  /// Signed 16 bit, endianness depends on the container.
  I16
  /// Signed 24 bit, stored as three bytes.
  I24
  /// Signed 32 bit.
  I32
  /// IEEE 754 single precision.
  F32
  /// IEEE 754 double precision.
  F64
}

///|
/// Number of bits occupied by one sample of this format.
pub fn SampleFormat::bits(self : SampleFormat) -> Int32 {
  match self {
    U8 => 8
    I16 => 16
    I24 => 24
    I32 => 32
    F32 => 32
    F64 => 64
  }
}

///|
/// Number of bytes occupied by one sample of this format.
pub fn SampleFormat::bytes(self : SampleFormat) -> Int32 {
  self.bits() / 8
}

///|
/// `true` when the format stores IEEE floating point samples.
pub fn SampleFormat::is_float(self : SampleFormat) -> Bool {
  match self {
    F32 | F64 => true
    _ => false
  }
}

///|
/// `true` when the format stores signed integers.
pub fn SampleFormat::is_signed(self : SampleFormat) -> Bool {
  match self {
    I16 | I24 | I32 => true
    _ => false
  }
}

///|
/// Largest integer code of the format (1.0 for float formats).
pub fn SampleFormat::max_code(self : SampleFormat) -> Double {
  match self {
    U8 => 127.0
    I16 => 32767.0
    I24 => 8388607.0
    I32 => 2147483647.0
    F32 | F64 => 1.0
  }
}

///|
/// Parse a format name such as `"s16"`, `"s24"`, `"f32"` or `"u8"`.
///
/// The accepted spellings follow `ffmpeg` style tooling, with a few aliases
/// (`pcm16`, `float32`, `int24`, ...) so the CLI is forgiving.
pub fn SampleFormat::parse(name : String) -> SampleFormat raise AudioError {
  let lowered = name.to_lower()
  match lowered {
    "u8" | "u8le" | "uint8" | "pcm_u8" => U8
    "s16" | "i16" | "s16le" | "i16le" | "int16" | "pcm16" | "pcm_s16le" => I16
    "s24" | "i24" | "s24le" | "int24" | "pcm24" => I24
    "s32" | "i32" | "s32le" | "int32" | "pcm32" => I32
    "f32" | "float" | "float32" | "f32le" => F32
    "f64" | "double" | "float64" | "f64le" => F64
    _ => raise Invalid("unknown sample format \"" + name + "\"")
  }
}

///|
/// Canonical short name of a sample format, the inverse of
/// [`SampleFormat::parse`].
pub fn SampleFormat::to_name(self : SampleFormat) -> String {
  match self {
    U8 => "u8"
    I16 => "s16"
    I24 => "s24"
    I32 => "s32"
    F32 => "f32"
    F64 => "f64"
  }
}

///|
/// `true` when two sample formats are the same variant.
pub fn SampleFormat::same(self : SampleFormat, other : SampleFormat) -> Bool {
  self.to_name() == other.to_name()
}
