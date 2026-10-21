// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Smallest useful end-to-end example: build a signal, encode it, decode it
/// back through the generic facade and inspect the result.
///
/// Run with `moon run examples/basic`.
fn main {
  let tone = make_tone() catch {
    (error : @audio.AudioError) => {
      println("error: \{error.message()}")
      return
    }
  }
  println(
    "built  : \{tone.sample_rate} Hz, \{tone.channels} ch, \{tone.frames()} frames",
  )
  let encoded = @wav.encode(tone) catch {
    (error : @audio.AudioError) => {
      println("error: \{error.message()}")
      return
    }
  }
  println("encoded: \{encoded.length()} bytes")
  let container = match @moonaudio.sniff(encoded) {
    Some(container) => container.to_name()
    None => "unknown"
  }
  println("sniffed: \{container}")
  let decoded = @moonaudio.decode(encoded) catch {
    (error : @audio.AudioError) => {
      println("error: \{error.message()}")
      return
    }
  }
  println(
    "decoded: \{decoded.frames()} frames, peak \{decoded.peak()}, rms \{decoded.rms()}",
  )
  println("source : \{@moonaudio.version()}")
}

///|
/// A short 440 Hz sine wave at 44.1 kHz.
fn make_tone() -> @audio.AudioBuffer raise @audio.AudioError {
  let buffer = @audio.AudioBuffer::silence(44100, 1, 4410)
  for frame = 0; frame < 4410; frame = frame + 1 {
    let phase = 2.0 * @math.PI * 440.0 * frame.to_double() / 44100.0
    buffer.data[frame] = 0.5 * @math.sin(phase)
  }
  buffer
}
