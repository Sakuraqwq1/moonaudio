// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Errors raised by every `moonaudio` decoder, encoder and DSP helper.
///
/// The four variants deliberately separate the *reason* a byte stream was
/// rejected so callers can decide whether to skip a file, fall back to another
/// decoder, or report the problem to the user.
pub(all) suberror AudioError {
  /// The input ended before a complete structure could be read.
  Truncated(String)
  /// The container or sample encoding is recognised but not supported.
  Unsupported(String)
  /// The bytes are malformed according to the container specification.
  Invalid(String)
  /// A caller supplied a value outside the range the operation accepts.
  OutOfRange(String)
}

///|
/// Human readable explanation of an [`AudioError`].
pub fn AudioError::message(self : AudioError) -> String {
  match self {
    Truncated(message) => "truncated audio data: " + message
    Unsupported(message) => "unsupported audio feature: " + message
    Invalid(message) => "invalid audio data: " + message
    OutOfRange(message) => "value out of range: " + message
  }
}

///|
/// Short machine friendly tag of an [`AudioError`], suitable for logs.
pub fn AudioError::kind(self : AudioError) -> String {
  match self {
    Truncated(_) => "truncated"
    Unsupported(_) => "unsupported"
    Invalid(_) => "invalid"
    OutOfRange(_) => "out_of_range"
  }
}

///|
/// Construct a `Truncated` error with a message.
pub fn truncated(message : String) -> AudioError {
  Truncated(message)
}

///|
/// Construct an `Unsupported` error with a message.
pub fn unsupported(message : String) -> AudioError {
  Unsupported(message)
}

///|
/// Construct an `Invalid` error with a message.
pub fn invalid(message : String) -> AudioError {
  Invalid(message)
}

///|
/// Construct an `OutOfRange` error with a message.
pub fn out_of_range(message : String) -> AudioError {
  OutOfRange(message)
}
