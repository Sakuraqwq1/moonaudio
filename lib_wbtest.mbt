// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// ASCII bytes for a text literal, built without extra imports.
fn ascii(text : String) -> Bytes {
  let out : Array[Byte] = []
  for c in text {
    out.push(c.to_int().to_byte())
  }
  Bytes::from_array(out[:])
}

///|
/// A small signal used by every dispatch test.
fn sample_audio() -> @audio.AudioBuffer {
  @audio.AudioBuffer::{
    sample_rate: 32000,
    channels: 2,
    data: [0.0, 0.0, 0.5, -0.5, -0.25, 0.25],
  }
}

///|
/// `true` when `sniff` reported `expected`.
fn is_container(actual : Container?, expected : Container) -> Bool {
  match actual {
    Some(value) => value.to_name() == expected.to_name()
    None => false
  }
}

///|
/// `true` when `sniff` reported nothing.
fn is_unknown(actual : Container?) -> Bool {
  match actual {
    None => true
    Some(_) => false
  }
}

///|
test "version is not empty" {
  assert_true(version().length() > 0)
  assert_true(version().has_prefix("0."))
}

///|
test "sniff recognises every container" {
  let audio = sample_audio()
  let wav_bytes = @wav.encode(audio) catch {
    (_ : @audio.AudioError) => panic()
  }
  let aiff_bytes = @aiff.encode(audio) catch {
    (_ : @audio.AudioError) => panic()
  }
  let au_bytes = @au.encode(audio) catch { (_ : @audio.AudioError) => panic() }
  assert_true(is_container(sniff(wav_bytes), Container::Wav))
  assert_true(is_container(sniff(aiff_bytes), Container::Aiff))
  assert_true(is_container(sniff(au_bytes), Container::Au))
  assert_true(is_container(sniff(ascii("fLaC")), Container::Flac))
}

///|
test "sniff rejects non audio bytes" {
  assert_true(is_unknown(sniff(ascii("hello world"))))
  assert_true(is_unknown(sniff(ascii("RIFF"))))
  assert_true(is_unknown(sniff(ascii("FORM"))))
  // RIFF with a non-WAVE form type is not a WAV file.
  assert_true(is_unknown(sniff(ascii("RIFFxxxxAVI "))))
}

///|
test "decode dispatches on the magic number" {
  let audio = sample_audio()
  let wav_bytes = @wav.encode(audio) catch {
    (_ : @audio.AudioError) => panic()
  }
  let aiff_bytes = @aiff.encode(audio) catch {
    (_ : @audio.AudioError) => panic()
  }
  let au_bytes = @au.encode(audio) catch { (_ : @audio.AudioError) => panic() }
  for bytes in [wav_bytes, aiff_bytes, au_bytes] {
    let decoded = decode(bytes) catch { (_ : @audio.AudioError) => panic() }
    assert_eq(decoded.sample_rate, 32000)
    assert_eq(decoded.channels, 2)
    assert_eq(decoded.frames(), 3)
    assert_true((decoded.data[2] - 0.5).abs() < 1.0e-3)
  }
}

///|
test "decode_detected reports the container" {
  let audio = sample_audio()
  let bytes = @aiff.encode(audio) catch { (_ : @audio.AudioError) => panic() }
  let (container, decoded) = decode_detected(bytes) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(container.to_name(), "aiff")
  assert_eq(decoded.frames(), 3)
}

///|
test "describe summarises every container" {
  let audio = sample_audio()
  let wav_bytes = @wav.encode(audio) catch {
    (_ : @audio.AudioError) => panic()
  }
  let aiff_bytes = @aiff.encode(audio) catch {
    (_ : @audio.AudioError) => panic()
  }
  let au_bytes = @au.encode(audio) catch { (_ : @audio.AudioError) => panic() }
  for bytes in [wav_bytes, aiff_bytes, au_bytes] {
    let summary = describe(bytes) catch { (_ : @audio.AudioError) => panic() }
    assert_true(summary.contains("32000"))
    assert_true(summary.contains("2 ch"))
  }
}

///|
test "unknown containers raise unsupported" {
  let mut kind = "ok"
  let _ = decode(ascii("not audio data")) catch {
    (error : @audio.AudioError) => {
      kind = error.kind()
      @audio.AudioBuffer::new(0, 1)
    }
  }
  assert_eq(kind, "unsupported")
}

///|
test "container names and extensions" {
  assert_eq(Container::Wav.to_name(), "wav")
  assert_eq(Container::Aiff.to_name(), "aiff")
  assert_eq(Container::Au.to_name(), "au")
  assert_eq(Container::Flac.to_name(), "flac")
  assert_eq(Container::Wav.extension(), ".wav")
  assert_eq(Container::Flac.extension(), ".flac")
}
