// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Metadata parsed from a Sun/NeXT `.au` (`.snd`) header.
///
/// The container is minimal: six big endian 32 bit words followed by an
/// optional annotation and then the sample data. Everything a caller needs to
/// interpret that data lives here.
pub(all) struct AuInfo {
  /// Sample rate in Hz, as declared by the fifth header word.
  sample_rate : Int32
  /// Number of interleaved channels, as declared by the sixth header word.
  channels : Int32
  /// Number of complete frames in the data region.
  frames : Int32
  /// Sample encoding mapped onto the shared [`@audio.SampleFormat`] type.
  ///
  /// Sun encoding 2 is *signed* 8 bit linear while [`@audio.U8`] describes
  /// unsigned offset binary, so a `.au` file reporting `U8` here still stores
  /// two's complement samples; the decoder takes care of the difference.
  format : @audio.SampleFormat
  /// Raw Sun encoding code (1 mu-law, 2 linear 8 bit, 3 linear 16 bit,
  /// 4 linear 24 bit, 5 linear 32 bit, 6 IEEE float32, 7 IEEE float64,
  /// 27 A-law).
  encoding : Int32
  /// Human readable name of [`AuInfo::encoding`], for logs and tests.
  encoding_name : String
  /// Text found between the 24 byte header and the sample data, decoded
  /// lossily and with trailing NUL padding removed.
  annotation : String
  /// Offset of the first sample byte, i.e. `24 + annotation bytes`.
  header_size : Int32
}

///|
/// One line summary of a `.au` header, used by the CLI, logs and tests.
pub fn AuInfo::describe(self : AuInfo) -> String {
  let note = if self.annotation.is_empty() {
    ""
  } else {
    ", note \"" + self.annotation + "\""
  }
  "\{self.sample_rate} Hz, \{self.channels} ch, \{self.format.bits()} bit (\{self.format.to_name()}), \{self.encoding_name}, \{self.frames} frames\{note}"
}

///|
/// A fully parsed `.au` file: header metadata plus the decoded samples.
pub(all) struct AuFile {
  /// Header metadata, including the annotation and the data offset.
  info : AuInfo
  /// Decoded samples normalised to `[-1.0, 1.0]`, interleaved by frame.
  audio : @audio.AudioBuffer
}
