// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// One chunk discovered while walking a RIFF container.
pub(all) struct ChunkRef {
  /// Four character chunk identifier, for example `"fmt "` or `"data"`.
  id : String
  /// Offset of the chunk *payload* inside the file.
  offset : Int32
  /// Payload length in bytes, as declared by the chunk header.
  size : Int32
}

///|
/// Metadata extracted from an `LIST`/`INFO` chunk.
///
/// Keys are the four character INFO identifiers (`INAM`, `IART`, `ICRD`, ...)
/// with surrounding NUL bytes trimmed.
pub(all) struct WavInfo {
  /// Sample rate in Hz.
  sample_rate : Int32
  /// Number of interleaved channels.
  channels : Int32
  /// Number of frames in the `data` chunk(s).
  frames : Int32
  /// Sample encoding as exposed to callers.
  format : @audio.SampleFormat
  /// Raw `wFormatTag` from the `fmt ` chunk (1 PCM, 3 IEEE float, 0xFFFE
  /// extensible, ...).
  format_tag : Int32
  /// Declared bit width of one sample slot.
  bits_per_sample : Int32
  /// Number of meaningful bits per sample; equals `bits_per_sample` unless a
  /// `WAVE_FORMAT_EXTENSIBLE` header narrows it.
  valid_bits : Int32
  /// `dwChannelMask` from the extensible header (0 when absent).
  channel_mask : Int64
  /// `nAvgBytesPerSec` from the `fmt ` chunk.
  byte_rate : Int64
  /// `true` when the file uses `WAVE_FORMAT_EXTENSIBLE`.
  extensible : Bool
  /// Every chunk found in the file, in file order.
  chunks : Array[ChunkRef]
  /// `LIST/INFO` entries, in file order.
  metadata : Array[(String, String)]
}

///|
/// A fully decoded WAV file.
pub(all) struct WavFile {
  info : WavInfo
  audio : @audio.AudioBuffer
}

///|
/// Look up an INFO metadata value by key.
pub fn WavInfo::meta(self : WavInfo, key : String) -> String? {
  for entry in self.metadata {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Number of bytes one frame occupies on disk.
pub fn WavInfo::block_align(self : WavInfo) -> Int32 {
  self.channels * (self.bits_per_sample / 8)
}

///|
/// Human readable container description used by the CLI and by tests.
pub fn WavInfo::describe(self : WavInfo) -> String {
  let layout = if self.extensible {
    "extensible"
  } else {
    match self.format_tag {
      1 => "pcm"
      3 => "ieee_float"
      6 => "alaw"
      7 => "mulaw"
      _ => "tag_" + self.format_tag.to_string()
    }
  }
  "\{self.sample_rate} Hz, \{self.channels} ch, \{self.bits_per_sample} bit (\{self.format.to_name()}), \{layout}, \{self.frames} frames"
}
