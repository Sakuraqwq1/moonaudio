// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Version of the `moonaudio` module.
/// Keep in sync with the `version` field in `moon.mod`.
pub fn version() -> String {
  "0.3.1"
}

///|
/// Audio container recognised by [`sniff`].
pub(all) enum Container {
  /// RIFF/WAVE (little endian), RIFX (big endian) or RF64.
  Wav
  /// AIFF or AIFC (big endian form container).
  Aiff
  /// Sun/NeXT `.au` (`.snd`).
  Au
  /// Native FLAC stream.
  Flac
}

///|
/// Canonical lower case container name.
pub fn Container::to_name(self : Container) -> String {
  match self {
    Wav => "wav"
    Aiff => "aiff"
    Au => "au"
    Flac => "flac"
  }
}

///|
/// Default file extension for a container, including the dot.
pub fn Container::extension(self : Container) -> String {
  match self {
    Wav => ".wav"
    Aiff => ".aiff"
    Au => ".au"
    Flac => ".flac"
  }
}

///|
/// Guess the container of `bytes` from its magic number.
///
/// Returns `None` for input that carries no recognised audio header, which lets
/// callers fall back to a user supplied format instead of guessing wrong.
pub fn sniff(bytes : Bytes) -> Container? {
  if @audio.ascii_is(bytes, 0, 4, "RIFF") ||
    @audio.ascii_is(bytes, 0, 4, "RIFX") ||
    @audio.ascii_is(bytes, 0, 4, "RF64") {
    if @audio.ascii_is(bytes, 8, 4, "WAVE") {
      return Some(Wav)
    }
  }
  if @audio.ascii_is(bytes, 0, 4, "FORM") {
    if @audio.ascii_is(bytes, 8, 4, "AIFF") ||
      @audio.ascii_is(bytes, 8, 4, "AIFC") {
      return Some(Aiff)
    }
  }
  if @audio.ascii_is(bytes, 0, 4, ".snd") {
    return Some(Au)
  }
  if @audio.ascii_is(bytes, 0, 4, "fLaC") {
    return Some(Flac)
  }
  None
}

///|
/// Decode any supported container, dispatching on the magic number.
pub fn decode(bytes : Bytes) -> @audio.AudioBuffer raise @audio.AudioError {
  match sniff(bytes) {
    Some(Wav) => @wav.decode(bytes)
    Some(Aiff) => @aiff.decode(bytes)
    Some(Au) => @au.decode(bytes)
    Some(Flac) => @flac.decode(bytes)
    None => raise @audio.Unsupported("unrecognised audio container")
  }
}

///|
/// Decode any supported container and also report which one it was.
pub fn decode_detected(
  bytes : Bytes,
) -> (Container, @audio.AudioBuffer) raise @audio.AudioError {
  let container = match sniff(bytes) {
    Some(container) => container
    None => raise @audio.Unsupported("unrecognised audio container")
  }
  let audio = match container {
    Wav => @wav.decode(bytes)
    Aiff => @aiff.decode(bytes)
    Au => @au.decode(bytes)
    Flac => @flac.decode(bytes)
  }
  (container, audio)
}

///|
/// Human readable summary of a supported file, without decoding the samples.
pub fn describe(bytes : Bytes) -> String raise @audio.AudioError {
  match sniff(bytes) {
    Some(Wav) => @wav.parse_info(bytes).describe()
    Some(Aiff) => @aiff.parse_info(bytes).describe()
    Some(Au) => @au.parse_info(bytes).describe()
    Some(Flac) => @flac.parse_info(bytes).describe()
    None => raise @audio.Unsupported("unrecognised audio container")
  }
}
