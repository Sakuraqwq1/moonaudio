// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// A pure sine tone with every channel carrying the same signal.
fn tone(
  rate : Int32,
  channels : Int32,
  frames : Int32,
  hz : Double,
  amplitude : Double,
) -> @audio.AudioBuffer {
  let data : Array[Double] = Array::make(frames * channels, 0.0)
  for frame = 0; frame < frames; frame = frame + 1 {
    let seconds = frame.to_double() / rate.to_double()
    let value = @math.sin(2.0 * pi * hz * seconds) * amplitude
    for channel = 0; channel < channels; channel = channel + 1 {
      data[frame * channels + channel] = value
    }
  }
  @audio.AudioBuffer::{ sample_rate: rate, channels, data, }
}

///|
/// Two independent tones, one per channel; used to show that channels are
/// resampled in isolation rather than mixed together.
fn two_tone(
  rate : Int32,
  frames : Int32,
  left_hz : Double,
  right_hz : Double,
  amplitude : Double,
) -> @audio.AudioBuffer {
  let data : Array[Double] = Array::make(frames * 2, 0.0)
  for frame = 0; frame < frames; frame = frame + 1 {
    let seconds = frame.to_double() / rate.to_double()
    data[frame * 2] = @math.sin(2.0 * pi * left_hz * seconds) * amplitude
    data[frame * 2 + 1] = @math.sin(2.0 * pi * right_hz * seconds) * amplitude
  }
  @audio.AudioBuffer::{ sample_rate: rate, channels: 2, data, }
}

///|
/// Number of sign changes in one channel, ignoring exact zeros.
///
/// A steady tone crosses zero twice per period, so this is a cheap,
/// FFT-free way to check that resampling did not shift the pitch.
fn zero_crossings(buffer : @audio.AudioBuffer, channel : Int32) -> Int32 {
  let mut crossings = 0
  let mut last = 0
  for frame = 0; frame < buffer.frames(); frame = frame + 1 {
    let value = buffer.sample(frame, channel)
    let sign = if value > 0.0 { 1 } else if value < 0.0 { -1 } else { 0 }
    if sign != 0 {
      if last != 0 && sign != last {
        crossings = crossings + 1
      }
      last = sign
    }
  }
  crossings
}

///|
/// `true` when the sign changes of `channel` match a `hz` tone within
/// `tolerance` crossings.
fn crossings_match(
  buffer : @audio.AudioBuffer,
  channel : Int32,
  hz : Double,
  tolerance : Double,
) -> Bool {
  let duration = buffer.frames().to_double() / buffer.sample_rate.to_double()
  let expected = 2.0 * hz * duration
  (zero_crossings(buffer, channel).to_double() - expected).abs() <= tolerance
}

///|
/// Amplitude of a sine estimated from its RMS level.
///
/// RMS times `sqrt(2)` is insensitive to where the resampled grid happens to
/// land relative to the crests, which makes it a fairer amplitude probe than
/// the peak value for short buffers.
fn amplitude_estimate(buffer : @audio.AudioBuffer) -> Double {
  buffer.rms() * 1.4142135623730951
}

///|
/// Largest absolute value in one channel over `[from, to)`.
///
/// The zero padded edges are excluded, so this measures the steady state of a
/// signal rather than the fade in/out transient.
fn peak_between(
  buffer : @audio.AudioBuffer,
  channel : Int32,
  from : Int32,
  to : Int32,
) -> Double {
  let mut peak = 0.0
  for frame = from; frame < to; frame = frame + 1 {
    let value = buffer.sample(frame, channel).abs()
    if value > peak {
      peak = value
    }
  }
  peak
}

///|
/// Resample `audio` to `target` and report the error kind, or `"ok"`.
fn resample_error_kind(audio : @audio.AudioBuffer, target : Int32) -> String {
  let mut kind = "ok"
  let _ = resample(audio, target) catch {
    (error : @audio.AudioError) => {
      kind = error.kind()
      @audio.AudioBuffer::new(0, 1)
    }
  }
  kind
}

///|
/// Resample `audio` by `ratio` and report the error kind, or `"ok"`.
fn ratio_error_kind(audio : @audio.AudioBuffer, ratio : Double) -> String {
  let mut kind = "ok"
  let _ = resample_by_ratio(audio, ratio) catch {
    (error : @audio.AudioError) => {
      kind = error.kind()
      @audio.AudioBuffer::new(0, 1)
    }
  }
  kind
}

///|
test "identity rate returns a copy" {
  let source = tone(44100, 2, 1024, 440.0, 0.5)
  let result = resample(source, 44100) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(result.sample_rate, 44100)
  assert_eq(result.channels, 2)
  assert_eq(result.frames(), 1024)
  for index = 0; index < source.data.length(); index = index + 1 {
    assert_eq(result.data[index], source.data[index])
  }
  // The result must own its samples, so writing to it cannot touch the source.
  result.set_sample(0, 0, 0.25)
  assert_eq(result.sample(0, 0), 0.25)
  assert_eq(source.sample(0, 0), 0.0)
  let empty = @audio.AudioBuffer::new(44100, 2)
  let retuned = resample(empty, 8000) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(retuned.frames(), 0)
  assert_eq(retuned.sample_rate, 8000)
  assert_eq(retuned.channels, 2)
}

///|
test "output length follows sample_count" {
  let source = tone(44100, 1, 1000, 440.0, 0.5)
  let qualities : Array[ResampleQuality] = [Linear, Cubic, Sinc]
  for target in [8000, 22050, 48000, 96000] {
    for quality in qualities {
      let out = resample(source, target, quality~) catch {
        (_ : @audio.AudioError) => panic()
      }
      assert_eq(out.sample_rate, target)
      assert_eq(out.channels, 1)
      assert_eq(out.frames(), sample_count(1000, 44100, target))
    }
  }
  // Ceiling division, so a partial trailing period is kept.
  assert_eq(sample_count(1000, 44100, 48000), 1089)
  assert_eq(sample_count(1000, 44100, 44100), 1000)
  assert_eq(sample_count(0, 44100, 48000), 0)
}

///|
test "linear keeps the tone frequency" {
  let source = tone(44100, 1, 8192, 440.0, 0.8)
  let out = resample(source, 48000, quality=Linear) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(out.frames(), sample_count(8192, 44100, 48000))
  assert_true(crossings_match(out, 0, 440.0, 4.0))
}

///|
test "cubic keeps the tone frequency" {
  let source = tone(44100, 1, 8192, 440.0, 0.8)
  let out = resample(source, 48000, quality=Cubic) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true(crossings_match(out, 0, 440.0, 4.0))
  let down = resample(source, 16000, quality=Cubic) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true(crossings_match(down, 0, 440.0, 4.0))
}

///|
test "sinc keeps the tone frequency" {
  let source = tone(44100, 1, 8192, 440.0, 0.8)
  let up = resample(source, 48000) catch { (_ : @audio.AudioError) => panic() }
  assert_true(crossings_match(up, 0, 440.0, 4.0))
  let down = resample(source, 22050) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true(crossings_match(down, 0, 440.0, 4.0))
  // A 10 kHz tone is far above the 4 kHz Nyquist of a 8 kHz stream: the
  // cutoff must reject it instead of folding it back into the band.
  let high = tone(44100, 1, 8192, 10000.0, 0.8)
  let aliased = resample(high, 8000) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true(peak_between(aliased, 0, 200, aliased.frames() - 200) < 0.01)
}

///|
test "amplitude survives resampling" {
  let source = tone(44100, 1, 8192, 440.0, 0.8)
  let linear = resample(source, 48000, quality=Linear) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true((amplitude_estimate(linear) - 0.8).abs() <= 0.08)
  let cubic = resample(source, 48000, quality=Cubic) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true((amplitude_estimate(cubic) - 0.8).abs() <= 0.08)
  let sinc = resample(source, 48000) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true((amplitude_estimate(sinc) - 0.8).abs() <= 0.024)
}

///|
test "upsample then downsample keeps the length sensible" {
  let source = tone(8000, 1, 800, 440.0, 0.5)
  let up = resample(source, 16000) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(up.sample_rate, 16000)
  assert_eq(up.frames(), 1600)
  let down = resample(up, 8000) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(down.sample_rate, 8000)
  assert_eq(down.frames(), 800)
  assert_true((down.frames() - source.frames()).abs() <= 1)
  assert_true(crossings_match(down, 0, 440.0, 2.0))
  assert_true((amplitude_estimate(down) - 0.5).abs() <= 0.05)
}

///|
test "ratio and explicit rate agree" {
  let source = tone(44100, 2, 2000, 440.0, 0.5)
  let doubled = resample_by_ratio(source, 2.0) catch {
    (_ : @audio.AudioError) => panic()
  }
  let explicit = resample(source, 88200) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(doubled.sample_rate, 88200)
  assert_eq(doubled.frames(), explicit.frames())
  assert_eq(doubled.frames(), 4000)
  for index = 0; index < doubled.data.length(); index = index + 1 {
    assert_eq(doubled.data[index], explicit.data[index])
  }
  let halved = resample_by_ratio(source, 0.5) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(halved.sample_rate, 22050)
  assert_eq(halved.frames(), 1000)
  assert_eq(ratio_error_kind(source, 2.0), "ok")
}

///|
test "integer ratio helpers" {
  assert_eq(gcd(44100, 48000), 300)
  assert_eq(gcd(44100, 44100), 44100)
  assert_eq(gcd(7, 13), 1)
  assert_eq(gcd(0, 5), 5)
  assert_eq(gcd(0, 0), 0)
  assert_eq(reduce_ratio(44100, 48000), (147, 160))
  assert_eq(reduce_ratio(8000, 16000), (1, 2))
  assert_eq(reduce_ratio(44100, 44100), (1, 1))
  assert_eq(reduce_ratio(13, 7), (13, 7))
  assert_eq(reduce_ratio(-44100, 48000), (-44100, 48000))
  assert_eq(sample_count(147, 44100, 48000), 160)
  assert_eq(sample_count(44100, 44100, 48000), 48000)
}

///|
test "invalid target rate is rejected" {
  let source = tone(8000, 1, 64, 440.0, 0.5)
  assert_eq(resample_error_kind(source, 0), "out_of_range")
  assert_eq(resample_error_kind(source, -8000), "out_of_range")
  assert_eq(ratio_error_kind(source, 0.0), "out_of_range")
  assert_eq(ratio_error_kind(source, -2.0), "out_of_range")
  let nan = 0.0 / 0.0
  assert_eq(ratio_error_kind(source, nan), "out_of_range")
}

///|
test "channels are resampled independently" {
  let source = two_tone(44100, 8192, 440.0, 1320.0, 0.5)
  let out = resample(source, 48000) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(out.channels, 2)
  assert_eq(out.frames(), sample_count(8192, 44100, 48000))
  assert_true(crossings_match(out, 0, 440.0, 4.0))
  assert_true(crossings_match(out, 1, 1320.0, 6.0))
  let mut difference = 0.0
  for frame = 0; frame < out.frames(); frame = frame + 1 {
    let delta = (out.sample(frame, 0) - out.sample(frame, 1)).abs()
    if delta > difference {
      difference = delta
    }
  }
  assert_true(difference > 0.5)
}
