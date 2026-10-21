// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Metadata and stream layout of an `AIFF` or `AIFC` file.
pub(all) struct AiffInfo {
  /// Sample rate in Hz, decoded from the 80 bit extended float in `COMM`.
  sample_rate : Int32
  /// Number of interleaved channels.
  channels : Int32
  /// Number of frames; the `COMM` count clamped to the bytes actually present
  /// in `SSND`.
  frames : Int32
  /// Sample encoding exposed to callers.
  ///
  /// 8 bit `AIFF` stores *signed* samples, a width [`@audio.SampleFormat`] only
  /// models as unsigned. The slot is therefore reported as `U8` while the
  /// decoder keeps the signed interpretation, exactly like the WAV decoder
  /// reports companded formats as `I16`.
  format : @audio.SampleFormat
  /// Declared `sampleSize` of the `COMM` chunk, in bits.
  bits_per_sample : Int32
  /// AIFC compression type as stored in `COMM`, `"NONE"` for plain `AIFF`.
  compression : String
  /// `true` when the form type is `AIFC`.
  is_aifc : Bool
  /// Every chunk in file order as `(id, payload offset, payload size)`.
  ///
  /// Sizes are clamped to the bytes actually present, so a truncated final
  /// chunk is reported with its usable length instead of its declared one.
  chunks : Array[(String, Int32, Int32)]
  /// Text chunk entries (`NAME`, `AUTH`, `(c) `, `ANNO`) in file order.
  metadata : Array[(String, String)]
}

///|
/// A fully decoded AIFF/AIFC file.
pub(all) struct AiffFile {
  info : AiffInfo
  audio : @audio.AudioBuffer
}

///|
/// Look up a text metadata value by its four character chunk id.
///
/// The keys are the chunk identifiers of the file itself (`"NAME"`, `"AUTH"`,
/// `"(c) "`, `"ANNO"`), not free form labels.
pub fn AiffInfo::meta(self : AiffInfo, key : String) -> String? {
  for entry in self.metadata {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Human readable container description used by the CLI and by tests.
pub fn AiffInfo::describe(self : AiffInfo) -> String {
  let container = if self.is_aifc { "AIFC" } else { "AIFF" }
  "\{self.sample_rate} Hz, \{self.channels} ch, \{self.bits_per_sample} bit (\{self.format.to_name()}), \{container} \{self.compression}, \{self.frames} frames"
}
