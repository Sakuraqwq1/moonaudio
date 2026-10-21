// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// A guided tour of the library: synthesis, analysis, filtering, resampling and
/// container roundtrips, each printed as one section.
///
/// Run with `moon run examples/tour`.
fn main {
  synthesis()
  analysis()
  filtering()
  resampling()
  containers()
}

///|
/// Build a chord (440 Hz + 660 Hz) and report its levels.
fn synthesis() -> Unit {
  section("synthesis")
  let a = @dsp.tone(440.0, 44100, 22050, amplitude=0.4) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  let b = @dsp.tone(660.0, 44100, 22050, amplitude=0.3) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  let chord = @dsp.mix(a, b) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  println("  tone 440 Hz : \{a.frames()} frames, peak \{round3(a.peak())}")
  println("  tone 660 Hz : \{b.frames()} frames, peak \{round3(b.peak())}")
  println(
    "  mixed       : peak \{round3(chord.peak())}, rms \{round3(chord.rms())}",
  )
  let noise = @dsp.white_noise(22050, 44100, 42L, amplitude=0.2)
  println("  noise seed 42: peak \{round3(noise.peak())}")
  let repeat = @dsp.white_noise(22050, 44100, 42L, amplitude=0.2)
  println("  deterministic: \{noise.data[0] == repeat.data[0]}")
}

///|
/// FFT peak detection, spectrogram and statistics on the same tone.
fn analysis() -> Unit {
  section("analysis")
  let tone = @dsp.tone(1000.0, 8000, 8000, amplitude=0.8) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  let spectrum = @dsp.real_fft(pad_to(tone.data, 1024))
  let magnitudes = @dsp.magnitude(spectrum, n=1024)
  let mut best = 0.0
  let mut best_index = 0
  for index = 0; index < magnitudes.length(); index = index + 1 {
    if magnitudes[index] > best {
      best = magnitudes[index]
      best_index = index
    }
  }
  let peak_hz = best_index.to_double() * 8000.0 / 1024.0
  println(
    "  fft peak at bin \{best_index}: \{round3(peak_hz)} Hz (input 1000 Hz)",
  )
  let spectrogram = @dsp.spectrogram(
    tone,
    fft_size=512,
    hop=256,
    window=@dsp.WindowKind::BlackmanHarris,
  ) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  let (frames, bins) = spectrogram.size()
  println(
    "  spectrogram: \{frames} frames x \{bins} bins, \{round3(spectrogram.bin_hz())} Hz per bin",
  )
  println("  frame 0 peak: \{round3(spectrogram.peak_frequency(0))} Hz")
  let stats = @dsp.analyse(tone)
  println(
    "  stats lines: \{stats.to_lines().split("\n").count()} key=value entries",
  )
  println("  zero crossing rate: \{round3(stats.zero_crossing_rate)}")
}

///|
/// Low-pass a square-ish signal and show the level drop.
fn filtering() -> Unit {
  section("filtering")
  let noisy = @dsp.white_noise(2000, 8000, 7L, amplitude=0.5)
  let low_pass = @dsp.Biquad::new(@dsp.LowPass, 8000, 500.0) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  let filtered = low_pass.apply_buffer(noisy)
  println("  white noise peak : \{round3(noisy.peak())}")
  println("  low passed peak  : \{round3(filtered.peak())}")
  let trimmed = @dsp.trim_silence(filtered, threshold=0.01)
  println("  after trim       : \{trimmed.frames()} frames")
  let faded = @dsp.fade_out(trimmed, trimmed.frames() / 2)
  println("  fade out tail    : \{round3(faded.data[faded.data.length() - 1])}")
}

///|
/// Resample a tone and confirm the frequency survives.
fn resampling() -> Unit {
  section("resampling")
  let tone = @dsp.tone(440.0, 44100, 4410, amplitude=0.5) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  let up = @resample.resample(tone, 48000) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  let (num, den) = @resample.reduce_ratio(44100, 48000)
  println("  ratio 44100:48000 reduces to \{num}:\{den}")
  println(
    "  expected frames: \{@resample.sample_count(tone.frames(), 44100, 48000)}",
  )
  println("  actual frames  : \{up.frames()}")
  println("  peak preserved : \{round3(up.peak())}")
  let back = @resample.resample(up, 44100) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  println("  roundtrip frames: \{back.frames()}")
}

///|
/// Encode the same signal as WAV, AIFF and back through the facade.
fn containers() -> Unit {
  section("containers")
  let tone = @dsp.tone(440.0, 22050, 2205, amplitude=0.6) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  let wav_bytes = @wav.encode(tone) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  let aiff_bytes = @aiff.encode(tone, format=@audio.I24) catch {
    (error : @audio.AudioError) => {
      fail(error)
      return
    }
  }
  for bytes in [wav_bytes, aiff_bytes] {
    let container = match @moonaudio.sniff(bytes) {
      Some(container) => container.to_name()
      None => "unknown"
    }
    let summary = @moonaudio.describe(bytes) catch {
      (error : @audio.AudioError) => {
        fail(error)
        return
      }
    }
    println("  \{container}: \{bytes.length()} bytes — \{summary}")
  }
}

///|
/// Print a section header.
fn section(title : String) -> Unit {
  println("")
  println("== \{title} ==")
}

///|
/// Print an error in the tour format.
fn fail(error : @audio.AudioError) -> Unit {
  println("  error: \{error.message()}")
}

///|
/// Round to three decimals for readable output.
fn round3(value : Double) -> String {
  let scaled = (value * 1000.0).round().to_int()
  (scaled.to_double() / 1000.0).to_string()
}

///|
/// Copy `data` into a fixed size array, zero padding the tail.
fn pad_to(data : Array[Double], size : Int32) -> Array[Double] {
  let out : Array[Double] = Array::make(size, 0.0)
  let count = if data.length() < size { data.length() } else { size }
  for index = 0; index < count; index = index + 1 {
    out[index] = data[index]
  }
  out
}
