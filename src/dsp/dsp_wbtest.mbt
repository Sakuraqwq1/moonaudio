// moonaudio - pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// `true` when two doubles agree within `tolerance`.
fn near(actual : Double, expected : Double, tolerance : Double) -> Bool {
  (actual - expected).abs() <= tolerance
}

///|
/// Deterministic pseudo random doubles in `[-1, 1)`, from a 31 bit linear
/// congruential generator so every run sees exactly the same signal.
fn pseudo_random(count : Int32) -> Array[Double] {
  let out : Array[Double] = Array::make(count, 0.0)
  let mut state = 12345L
  for index = 0; index < count; index = index + 1 {
    state = (state * 1103515245L + 12345L) & 0x7FFFFFFFL
    out[index] = state.to_double() / 1073741823.5 - 1.0
  }
  out
}

///|
/// Straightforward `O(N^2)` discrete Fourier transform, the reference the fast
/// transform is checked against.
fn naive_dft(input : Array[Complex]) -> Array[Complex] {
  let size = input.length()
  let out : Array[Complex] = Array::make(size, Complex::zero())
  for bin = 0; bin < size; bin = bin + 1 {
    let mut sum = Complex::zero()
    for index = 0; index < size; index = index + 1 {
      let angle = -2.0 *
        @math.PI *
        bin.to_double() *
        index.to_double() /
        size.to_double()
      let weight = Complex::{ re: @math.cos(angle), im: @math.sin(angle), }
      sum = sum.add(input[index].mul(weight))
    }
    out[bin] = sum
  }
  out
}

///|
/// Real samples of a unit amplitude mono sine, the fixture most spectral tests
/// start from.
fn sine_samples(
  frequency : Double,
  sample_rate : Int32,
  count : Int32,
) -> Array[Double] {
  let samples : Array[Double] = Array::make(count, 0.0)
  let step = 2.0 * @math.PI * frequency / sample_rate.to_double()
  for index = 0; index < count; index = index + 1 {
    samples[index] = @math.sin(step * index.to_double())
  }
  samples
}

///|
/// Mono sine as an audio buffer.
fn sine_buffer(
  frequency : Double,
  sample_rate : Int32,
  frames : Int32,
  amplitude~ : Double = 0.5,
) -> @audio.AudioBuffer {
  tone(frequency, sample_rate, frames, amplitude~) catch {
    (_ : @audio.AudioError) => panic()
  }
}

///|
/// Root mean square of a plain sample array.
fn rms_of(samples : Array[Double]) -> Double {
  if samples.length() == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for value in samples {
    sum = sum + value * value
  }
  (sum / samples.length().to_double()).sqrt()
}

///|
/// Index of the largest entry of an array of magnitudes, searching from `from`.
fn peak_bin(values : Array[Double], from : Int32) -> Int32 {
  let mut best = from
  for bin = from; bin < values.length(); bin = bin + 1 {
    if values[bin] > values[best] {
      best = bin
    }
  }
  best
}

///|
/// Kind of the error raised by a transform of `size` zero bins, or `"ok"`.
fn fft_error_kind(size : Int32) -> String {
  let mut result = "ok"
  let input : Array[Complex] = Array::make(size, Complex::zero())
  let _ = fft(input) catch {
    (error : @audio.AudioError) => {
      result = error.kind()
      []
    }
  }
  result
}

///|
/// Kind of the error raised by an inverse transform of `size` zero bins.
fn ifft_error_kind(size : Int32) -> String {
  let mut result = "ok"
  let input : Array[Complex] = Array::make(size, Complex::zero())
  let _ = ifft(input) catch {
    (error : @audio.AudioError) => {
      result = error.kind()
      []
    }
  }
  result
}

///|
/// Kind of the error raised by a biquad design, or `"ok"`.
fn biquad_error_kind(
  kind : FilterKind,
  sample_rate : Int32,
  frequency : Double,
  q : Double,
) -> String {
  let mut result = "ok"
  let _ = Biquad::new(kind, sample_rate, frequency, q~) catch {
    (error : @audio.AudioError) => {
      result = error.kind()
      Biquad::{ b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0, }
    }
  }
  result
}

///|
/// Kind of the error raised by mixing two buffers, or `"ok"`.
fn mix_error_kind(a : @audio.AudioBuffer, b : @audio.AudioBuffer) -> String {
  let mut result = "ok"
  let _ = mix(a, b) catch {
    (error : @audio.AudioError) => {
      result = error.kind()
      a
    }
  }
  result
}

///|
/// Kind of the error raised by a tone request, or `"ok"`.
fn tone_error_kind(frequency : Double, sample_rate : Int32) -> String {
  let mut result = "ok"
  let fallback = white_noise(1, 8000, 1L)
  let _ = tone(frequency, sample_rate, 8) catch {
    (error : @audio.AudioError) => {
      result = error.kind()
      fallback
    }
  }
  result
}

///|
/// Kind of the error raised by a spectrogram request, or `"ok"`.
fn spectrogram_error_kind(
  audio : @audio.AudioBuffer,
  fft_size : Int32,
  hop : Int32,
) -> String {
  let mut result = "ok"
  let _ = spectrogram(audio, fft_size~, hop~) catch {
    (error : @audio.AudioError) => {
      result = error.kind()
      Spectrogram::{
        sample_rate: 8000,
        fft_size: 2,
        hop: 1,
        frames: [],
        max_db: 0.0,
        min_db: -100.0,
      }
    }
  }
  result
}

///|
/// A silent mono buffer of `frames` frames, used as a canvas by the editing
/// tests.
fn silent_buffer(frames : Int32) -> @audio.AudioBuffer {
  @audio.AudioBuffer::silence(8000, 1, frames) catch {
    (_ : @audio.AudioError) => panic()
  }
}

///|
test "complex arithmetic" {
  let a = Complex::new(3.0, 4.0)
  let b = Complex::new(-1.0, 2.0)
  let sum = a.add(b)
  assert_true(near(sum.re, 2.0, 1.0e-12) && near(sum.im, 6.0, 1.0e-12))
  let difference = a.sub(b)
  assert_true(near(difference.re, 4.0, 1.0e-12))
  assert_true(near(difference.im, 2.0, 1.0e-12))
  let product = a.mul(b)
  assert_true(near(product.re, -11.0, 1.0e-12))
  assert_true(near(product.im, 2.0, 1.0e-12))
  let scaled = a.scale(2.0)
  assert_true(near(scaled.re, 6.0, 1.0e-12) && near(scaled.im, 8.0, 1.0e-12))
  assert_true(near(a.magnitude(), 5.0, 1.0e-12))
  assert_true(near(a.phase(), @math.atan2(4.0, 3.0), 1.0e-12))
  assert_true(near(a.conjugate().im, -4.0, 1.0e-12))
  let negated = a.neg()
  assert_true(near(negated.re, -3.0, 1.0e-12))
  // The same operations again through the operator overloads.
  let operated = (a + b) * b - b
  let expected = sum.mul(b).sub(b)
  assert_true(near(operated.re, expected.re, 1.0e-12))
  assert_true(near(operated.im, expected.im, 1.0e-12))
  assert_eq(Complex::zero().re, 0.0)
  assert_true(Complex::new(-0.0, 0.0).same(Complex::zero()))
}

///|
test "fft matches a naive dft" {
  let values = pseudo_random(64)
  let input : Array[Complex] = []
  for index = 0; index < values.length(); index = index + 1 {
    input.push(Complex::{
      re: values[index],
      im: values[index * 7 % values.length()],
    })
  }
  let fast = fft(input) catch { (_ : @audio.AudioError) => panic() }
  let slow = naive_dft(input)
  assert_eq(fast.length(), 64)
  for bin = 0; bin < 64; bin = bin + 1 {
    assert_true(near(fast[bin].re, slow[bin].re, 1.0e-9))
    assert_true(near(fast[bin].im, slow[bin].im, 1.0e-9))
  }
}

///|
test "fft rejects lengths that are not powers of two" {
  assert_eq(fft_error_kind(0), "invalid")
  assert_eq(fft_error_kind(3), "invalid")
  assert_eq(fft_error_kind(12), "invalid")
  assert_eq(fft_error_kind(1), "ok")
  assert_eq(fft_error_kind(32), "ok")
  assert_eq(ifft_error_kind(0), "invalid")
  assert_eq(ifft_error_kind(6), "invalid")
  assert_eq(ifft_error_kind(8), "ok")
}

///|
test "ifft inverts fft" {
  let values = pseudo_random(32)
  let input : Array[Complex] = []
  for index = 0; index < values.length(); index = index + 1 {
    input.push(Complex::{ re: values[index], im: 0.0, })
  }
  let spectrum = fft(input) catch { (_ : @audio.AudioError) => panic() }
  let restored = ifft(spectrum) catch { (_ : @audio.AudioError) => panic() }
  for index = 0; index < 32; index = index + 1 {
    assert_true(near(restored[index].re, values[index], 1.0e-12))
    assert_true(near(restored[index].im, 0.0, 1.0e-12))
  }
}

///|
test "fft preserves energy" {
  let values = pseudo_random(64)
  let input : Array[Complex] = []
  for index = 0; index < values.length(); index = index + 1 {
    input.push(Complex::{
      re: values[index],
      im: values[index * 5 % values.length()],
    })
  }
  let spectrum = fft(input) catch { (_ : @audio.AudioError) => panic() }
  let mut time_energy = 0.0
  for value in input {
    time_energy = time_energy + value.re * value.re + value.im * value.im
  }
  let mut bin_energy = 0.0
  for value in spectrum {
    bin_energy = bin_energy + value.re * value.re + value.im * value.im
  }
  assert_true(near(bin_energy / 64.0, time_energy, 1.0e-9))
}

///|
test "real fft of a sine peaks at the expected bin" {
  let samples = sine_samples(1000.0, 8000, 1024)
  let spectrum = real_fft(samples)
  assert_eq(spectrum.length(), 513)
  let magnitudes = magnitude(spectrum, n=1024)
  assert_eq(magnitudes.length(), 513)
  assert_eq(peak_bin(magnitudes, 1), 128)
  // The source sine has unit amplitude, so its peak bin reads 1.0.
  assert_true(near(magnitudes[128], 1.0, 1.0e-9))
  // Halving the signal halves the magnitude.
  let quiet : Array[Double] = Array::make(1024, 0.0)
  for index = 0; index < 1024; index = index + 1 {
    quiet[index] = samples[index] * 0.5
  }
  let half = magnitude(real_fft(quiet), n=1024)
  assert_true(near(half[128], 0.5, 1.0e-9))
}

///|
test "real fft pads odd and non power of two lengths" {
  let odd : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0]
  let spectrum = real_fft(odd)
  // 5 samples pad to 6, then up to the next power of two (8): 8 / 2 + 1 bins.
  assert_eq(spectrum.length(), 5)
  assert_true(near(spectrum[0].re, 15.0, 1.0e-12))
  assert_true(near(spectrum[0].im, 0.0, 1.0e-12))
  let empty : Array[Double] = []
  assert_eq(real_fft(empty).length(), 0)
  let six : Array[Double] = Array::make(6, 1.0)
  let padded = real_fft(six)
  assert_eq(padded.length(), 5)
  assert_true(near(padded[0].re, 6.0, 1.0e-12))
}

///|
test "magnitude is one sided and normalised" {
  let ones : Array[Double] = Array::make(8, 1.0)
  let flat = magnitude(real_fft(ones))
  assert_eq(flat.length(), 5)
  // A constant signal is all DC, so the Nyquist bin is empty.
  assert_true(near(flat[0], 1.0, 1.0e-12))
  assert_true(flat[4] < 1.0e-12)
  assert_true(flat[1] < 1.0e-12)
  // A packed real spectrum and the full complex one agree bin for bin.
  let samples = sine_samples(500.0, 8000, 64)
  let packed = magnitude(real_fft(samples))
  let complex_input : Array[Complex] = []
  for value in samples {
    complex_input.push(Complex::{ re: value, im: 0.0, })
  }
  let full = magnitude(
    fft(complex_input) catch {
      (_ : @audio.AudioError) => panic()
    },
  )
  assert_eq(packed.length(), full.length())
  for bin = 0; bin < packed.length(); bin = bin + 1 {
    assert_true(near(packed[bin], full[bin], 1.0e-12))
  }
  assert_eq(packed.length(), 33)
  assert_eq(magnitude([]).length(), 0)
}

///|
test "power spectrum integrates to the mean square" {
  let samples = sine_samples(1000.0, 8000, 512)
  let power = power_spectrum(samples)
  assert_eq(power.length(), 257)
  let mut total = 0.0
  for value in power {
    total = total + value
  }
  // A unit amplitude sine has a mean square of 0.5.
  assert_true(near(total, 0.5, 1.0e-6))
  assert_eq(peak_bin(power, 1), 64)
  assert_true(near(power[64], 0.5, 1.0e-6))
  // Windowing keeps the tone in the same bin.
  let windowed = power_spectrum(samples, window=Hann.coefficients(512))
  assert_eq(windowed.length(), 257)
  assert_eq(peak_bin(windowed, 1), 64)
  assert_eq(power_spectrum([]).length(), 0)
}

///|
test "window taps are symmetric and sum to one" {
  let kinds : Array[WindowKind] = [
    Rectangular,
    Hann,
    Hamming,
    Blackman,
    BlackmanHarris,
    Kaiser,
  ]
  for kind in kinds {
    let taps = kind.coefficients(33)
    assert_eq(taps.length(), 33)
    let mut total = 0.0
    for tap in taps {
      total = total + tap
      // Taps stay non negative up to rounding: Blackman's end tap lands on
      // about -1e-18 rather than exactly zero.
      assert_true(tap >= -1.0e-15 && tap <= 1.0)
    }
    assert_true(near(total, 1.0, 1.0e-12))
    for index = 0; index < 33; index = index + 1 {
      assert_true(near(taps[index], taps[32 - index], 1.0e-15))
    }
  }
  // Degenerate sizes stay usable.
  assert_eq(Hann.coefficients(0).length(), 0)
  assert_eq(Hann.coefficients(-4).length(), 0)
  let single = Hann.coefficients(1)
  assert_eq(single.length(), 1)
  assert_eq(single[0], 1.0)
}

///|
test "hann vanishes at both ends and kaiser beta shapes the taper" {
  let hann = Hann.coefficients(64)
  assert_true(hann[0].abs() < 1.0e-15)
  assert_true(hann[63].abs() < 1.0e-15)
  assert_true(near(hann[31], hann[32], 1.0e-12))
  let hamming = Hamming.coefficients(64)
  assert_true(hamming[0] > 0.0)
  assert_true(near(hamming[0], hamming[63], 1.0e-15))
  let blackman = Blackman.coefficients(64)
  assert_true(blackman[0].abs() < 1.0e-15)
  // beta = 0 makes Kaiser a rectangular window.
  let flat = Kaiser.coefficients(16, beta=0.0)
  let rectangular = Rectangular.coefficients(16)
  for index = 0; index < 16; index = index + 1 {
    assert_true(near(flat[index], rectangular[index], 1.0e-15))
  }
  // A large beta concentrates the taper around the centre tap.
  let narrow = Kaiser.coefficients(65, beta=12.0)
  let wide = Kaiser.coefficients(65, beta=2.0)
  assert_true(narrow[0] < wide[0])
  assert_true(narrow[32] > wide[32])
}

///|
test "window names are stable" {
  assert_eq(Rectangular.to_name(), "rectangular")
  assert_eq(Hann.to_name(), "hann")
  assert_eq(Hamming.to_name(), "hamming")
  assert_eq(Blackman.to_name(), "blackman")
  assert_eq(BlackmanHarris.to_name(), "blackman-harris")
  assert_eq(Kaiser.to_name(), "kaiser")
}

///|
test "spectrogram dimensions and peak frequency" {
  let audio = sine_buffer(1000.0, 8000, 8000)
  let spec = spectrogram(audio, fft_size=256, hop=128) catch {
    (_ : @audio.AudioError) => panic()
  }
  let (frames, bins) = spec.size()
  assert_eq(bins, 129)
  assert_eq(frames, 62)
  assert_eq(spec.frames.length(), 62)
  assert_eq(spec.frames[0].length(), 129)
  assert_eq(spec.fft_size, 256)
  assert_eq(spec.hop, 128)
  assert_eq(spec.sample_rate, 8000)
  assert_true(near(spec.bin_hz(), 31.25, 1.0e-12))
  assert_eq(spec.max_db, 0.0)
  assert_eq(spec.min_db, -100.0)
  let frequency = spec.peak_frequency(5)
  assert_true((frequency - 1000.0).abs() <= spec.bin_hz())
  // Every cell sits inside the advertised dB window.
  for row in spec.frames {
    for value in row {
      assert_true(value >= spec.min_db && value <= spec.max_db)
    }
  }
  // An out of range frame reports zero rather than panicking.
  assert_eq(spec.peak_frequency(-1), 0.0)
  assert_eq(spec.peak_frequency(999), 0.0)
}

///|
test "spectrogram mono mixes multichannel audio" {
  let samples = sine_samples(1000.0, 8000, 256)
  let mono = @audio.AudioBuffer::{
    sample_rate: 8000,
    channels: 1,
    data: samples,
  }
  let stereo = @audio.AudioBuffer::from_channels(8000, [samples, samples]) catch {
    (_ : @audio.AudioError) => panic()
  }
  let mono_spec = spectrogram(mono, fft_size=256, hop=128) catch {
    (_ : @audio.AudioError) => panic()
  }
  let stereo_spec = spectrogram(stereo, fft_size=256, hop=128) catch {
    (_ : @audio.AudioError) => panic()
  }
  // One frame covers the whole signal, and averaging two identical channels
  // reproduces the mono analysis exactly (summing would add 6 dB).
  assert_eq(mono_spec.frames.length(), 1)
  assert_eq(stereo_spec.frames.length(), 1)
  for bin = 0; bin < 129; bin = bin + 1 {
    assert_true(
      near(stereo_spec.frames[0][bin], mono_spec.frames[0][bin], 1.0e-12),
    )
  }
  assert_true(mono_spec.frames[0][32] > -1.0)
}

///|
test "spectrogram rejects impossible parameters" {
  let audio = sine_buffer(1000.0, 8000, 256)
  assert_eq(spectrogram_error_kind(audio, 100, 64), "invalid")
  assert_eq(spectrogram_error_kind(audio, 1, 64), "invalid")
  assert_eq(spectrogram_error_kind(audio, 64, 0), "out_of_range")
  assert_eq(spectrogram_error_kind(audio, 64, -8), "out_of_range")
  assert_eq(spectrogram_error_kind(audio, 64, 32), "ok")
  // An empty buffer produces an empty matrix but keeps its geometry.
  let empty = @audio.AudioBuffer::silence(8000, 1, 0) catch {
    (_ : @audio.AudioError) => panic()
  }
  let spec = spectrogram(empty) catch { (_ : @audio.AudioError) => panic() }
  let (frames, bins) = spec.size()
  assert_eq(frames, 0)
  assert_eq(bins, 513)
}

///|
test "spectrogram csv has a header and a cell per frame and bin" {
  let audio = sine_buffer(1000.0, 8000, 1024)
  let spec = spectrogram(audio, fft_size=128, hop=64) catch {
    (_ : @audio.AudioError) => panic()
  }
  let (frames, bins) = spec.size()
  assert_eq(frames, 15)
  assert_eq(bins, 65)
  let csv = spec.to_csv()
  assert_true(csv.has_prefix("frequency_hz,frame_0,frame_1"))
  // One header row plus one row per bin, each with `frames` commas.
  assert_eq(csv.split(",").count(), (bins + 1) * frames + 1)
  assert_eq(csv.split("\n").count(), bins + 2)
}

///|
test "spectrogram svg is well formed" {
  let audio = sine_buffer(1000.0, 8000, 1024)
  let spec = spectrogram(audio, fft_size=128, hop=64) catch {
    (_ : @audio.AudioError) => panic()
  }
  let svg = spec.to_svg(width=120, height=60)
  assert_true(svg.has_prefix("<svg"))
  assert_true(svg.has_suffix("</svg>\n"))
  assert_true(svg.contains("<rect"))
  assert_true(svg.contains("rgb("))
  assert_true(!svg.contains("nan"))
  assert_true(!svg.contains("inf"))
  assert_true(svg.length() > 200)
  // The default geometry still fits the canvas.
  let large = spec.to_svg()
  assert_true(large.has_prefix("<svg"))
  assert_true(large.contains("width=\"640\""))
  assert_true(large.contains("height=\"240\""))
}

///|
test "low pass keeps low tones and drops high ones" {
  let filter = Biquad::new(LowPass, 8000, 1000.0) catch {
    (_ : @audio.AudioError) => panic()
  }
  let low = rms_of(filter.apply(sine_samples(200.0, 8000, 4000)))
  let high = rms_of(filter.apply(sine_samples(3000.0, 8000, 4000)))
  assert_true(low > 0.3)
  assert_true(high < 0.05)
  assert_true(low > high * 10.0)
}

///|
test "high pass keeps high tones and drops low ones" {
  let filter = Biquad::new(HighPass, 8000, 1000.0) catch {
    (_ : @audio.AudioError) => panic()
  }
  let low = rms_of(filter.apply(sine_samples(200.0, 8000, 4000)))
  let high = rms_of(filter.apply(sine_samples(3000.0, 8000, 4000)))
  assert_true(high > 0.3)
  assert_true(low < 0.05)
  assert_true(high > low * 10.0)
}

///|
test "biquad stays stable on a step" {
  let filter = Biquad::new(LowPass, 8000, 500.0) catch {
    (_ : @audio.AudioError) => panic()
  }
  let step : Array[Double] = Array::make(2000, 1.0)
  let out = filter.apply(step)
  for value in out {
    assert_true(!value.is_nan())
    assert_true(value.abs() <= 1.5)
  }
  assert_true(near(out[0], filter.b0, 1.0e-12))
  assert_true(near(out[1999], 1.0, 1.0e-6))
  // Streaming one sample at a time matches the block helper.
  let state = BiquadState::new()
  let streamed : Array[Double] = []
  for value in step {
    streamed.push(filter.process_sample(value, state))
  }
  for index = 0; index < 2000; index = index + 1 {
    assert_true(near(streamed[index], out[index], 1.0e-12))
  }
  assert_eq(BiquadState::new().x1, 0.0)
}

///|
test "biquad rejects designs outside the valid range" {
  assert_eq(biquad_error_kind(LowPass, 8000, 4000.0, 0.707), "out_of_range")
  assert_eq(biquad_error_kind(LowPass, 8000, 5000.0, 0.707), "out_of_range")
  assert_eq(biquad_error_kind(LowPass, 8000, 0.0, 0.707), "out_of_range")
  assert_eq(biquad_error_kind(LowPass, 8000, -100.0, 0.707), "out_of_range")
  assert_eq(biquad_error_kind(LowPass, 8000, 1000.0, 0.0), "out_of_range")
  assert_eq(biquad_error_kind(LowPass, 8000, 1000.0, -1.0), "out_of_range")
  assert_eq(biquad_error_kind(LowPass, 0, 1000.0, 0.707), "out_of_range")
  assert_eq(biquad_error_kind(LowPass, 8000, 1000.0, 0.707), "ok")
  assert_eq(biquad_error_kind(HighShelf, 8000, 1000.0, 0.707), "ok")
}

///|
test "every filter kind stays finite and bounded" {
  let kinds : Array[FilterKind] = [
    LowPass,
    HighPass,
    BandPass,
    Notch,
    Peaking,
    LowShelf,
    HighShelf,
  ]
  for kind in kinds {
    let filter = Biquad::new(kind, 8000, 1000.0, gain_db=6.0) catch {
      (_ : @audio.AudioError) => panic()
    }
    assert_true(!filter.b0.is_nan() && !filter.b0.is_inf())
    assert_true(!filter.b1.is_nan() && !filter.b1.is_inf())
    assert_true(!filter.b2.is_nan() && !filter.b2.is_inf())
    assert_true(!filter.a1.is_nan() && !filter.a1.is_inf())
    assert_true(!filter.a2.is_nan() && !filter.a2.is_inf())
    let out = filter.apply(sine_samples(1000.0, 8000, 512))
    for value in out {
      assert_true(!value.is_nan())
      assert_true(value.abs() < 8.0)
    }
  }
}

///|
test "biquad filters every channel of a buffer" {
  let audio = @audio.AudioBuffer::{
    sample_rate: 8000,
    channels: 2,
    data: [0.0, 0.0, 0.5, 0.25, 1.0, 0.5, 0.5, 0.25],
  }
  let filter = Biquad::new(LowPass, 8000, 2000.0) catch {
    (_ : @audio.AudioError) => panic()
  }
  let filtered = filter.apply_buffer(audio)
  assert_eq(filtered.frames(), 4)
  assert_eq(filtered.channels, 2)
  assert_eq(filtered.sample_rate, 8000)
  assert_eq(filtered.sample(0, 0), 0.0)
  assert_true(filtered.sample(3, 0) > filtered.sample(3, 1))
  assert_true(filtered.peak() <= 1.2)
}

///|
test "stats report peak rms and crest factor of a sine" {
  let stats = analyse(sine_buffer(1000.0, 8000, 8000))
  assert_eq(stats.frames, 8000)
  assert_eq(stats.channels, 1)
  assert_eq(stats.sample_rate, 8000)
  assert_true(near(stats.peak, 0.5, 1.0e-12))
  assert_true(near(stats.rms, 0.35355339059327373, 1.0e-6))
  assert_true(near(stats.crest_factor, 1.4142135623730951, 1.0e-4))
  assert_true(near(stats.peak_dbfs, -6.020599913279624, 1.0e-6))
  assert_true(near(stats.rms_dbfs, -9.030899869919436, 1.0e-6))
  assert_true(near(stats.zero_crossing_rate, 0.25, 1.0e-3))
  assert_true(near(stats.dc_offset, 0.0, 1.0e-9))
  assert_true(near(stats.duration_seconds, 1.0, 1.0e-12))
  // A 1 kHz sine on an 8 kHz stream hits zero exactly every fourth sample.
  assert_eq(stats.silent_frames, 2000)
}

///|
test "stats detect a dc offset and removal flattens it" {
  let biased = silent_buffer(100)
  for frame = 0; frame < 100; frame = frame + 1 {
    biased.set_sample(frame, 0, 0.25)
  }
  let stats = analyse(biased)
  assert_true(near(stats.dc_offset, 0.25, 1.0e-12))
  assert_true(near(stats.peak, 0.25, 1.0e-12))
  assert_true(near(stats.crest_factor, 1.0, 1.0e-12))
  assert_eq(stats.zero_crossing_rate, 0.0)
  assert_eq(stats.silent_frames, 0)
  let flat = remove_dc_offset(biased)
  assert_true(flat.peak() < 1.0e-12)
  assert_true(near(analyse(flat).dc_offset, 0.0, 1.0e-12))
  // The source buffer is left alone.
  assert_true(near(analyse(biased).dc_offset, 0.25, 1.0e-12))
}

///|
test "stats lines are stable and ordered" {
  let text = analyse(sine_buffer(1000.0, 8000, 800)).to_lines()
  let lines = text.split("\n").to_array()
  assert_eq(lines.length(), 13)
  assert_eq(lines[0].to_owned(), "frames=800")
  assert_eq(lines[1].to_owned(), "channels=1")
  assert_eq(lines[2].to_owned(), "sample_rate=8000")
  assert_eq(lines[3].to_owned(), "peak=0.500000")
  assert_eq(lines[4].to_owned(), "peak_dbfs=-6.020600")
  assert_eq(lines[5].to_owned(), "rms=0.353553")
  assert_eq(lines[7].to_owned(), "crest_factor=1.414214")
  // The crossing count depends on the sign of samples that land on ~1e-16
  // instead of exactly zero, so only its neighbourhood is asserted here; the
  // stats test pins the value to within 1e-3 of 0.25.
  assert_true(lines[8].has_prefix("zero_crossing_rate=0.24"))
  assert_eq(lines[9].to_owned(), "dc_offset=0.000000")
  assert_eq(lines[10].to_owned(), "silent_frames=200")
  assert_eq(lines[11].to_owned(), "duration_seconds=0.100000")
}

///|
test "trim silence drops leading and trailing silence" {
  let source = silent_buffer(800)
  for frame = 100; frame < 600; frame = frame + 1 {
    source.set_sample(frame, 0, 0.5)
  }
  assert_eq(analyse(source).silent_frames, 300)
  let trimmed = trim_silence(source)
  assert_eq(trimmed.frames(), 500)
  assert_eq(trimmed.sample(0, 0), 0.5)
  assert_eq(trimmed.sample(499, 0), 0.5)
  let silent = silent_buffer(16)
  assert_eq(trim_silence(silent).frames(), 0)
  // A louder threshold trims more aggressively.
  let quiet = silent_buffer(10)
  for frame = 3; frame < 8; frame = frame + 1 {
    quiet.set_sample(frame, 0, 0.01)
  }
  assert_eq(trim_silence(quiet).frames(), 5)
  assert_eq(trim_silence(quiet, threshold=0.1).frames(), 0)
}

///|
test "fades ramp from and to zero" {
  let source = silent_buffer(8)
  for frame = 0; frame < 8; frame = frame + 1 {
    source.set_sample(frame, 0, 1.0)
  }
  let faded_in = fade_in(source, 4)
  assert_eq(faded_in.sample(0, 0), 0.0)
  assert_true(near(faded_in.sample(1, 0), 0.25, 1.0e-12))
  assert_true(near(faded_in.sample(2, 0), 0.5, 1.0e-12))
  assert_eq(faded_in.sample(4, 0), 1.0)
  assert_eq(faded_in.sample(7, 0), 1.0)
  let faded_out = fade_out(source, 4)
  assert_eq(faded_out.sample(7, 0), 0.0)
  assert_true(near(faded_out.sample(6, 0), 0.25, 1.0e-12))
  assert_eq(faded_out.sample(3, 0), 1.0)
  assert_eq(faded_out.sample(0, 0), 1.0)
  // The input buffer is untouched and non positive spans are a no-op.
  assert_eq(source.sample(0, 0), 1.0)
  assert_eq(fade_in(source, 0).sample(0, 0), 1.0)
  assert_eq(fade_out(source, -2).sample(7, 0), 1.0)
}

///|
test "mix sums with gains and rejects layout mismatches" {
  let a = @audio.AudioBuffer::{
    sample_rate: 8000,
    channels: 1,
    data: [0.25, 0.5, -0.25, -0.5],
  }
  let b = @audio.AudioBuffer::{
    sample_rate: 8000,
    channels: 1,
    data: [0.5, -0.5, 0.5, -0.5],
  }
  let summed = mix(a, b) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(summed.frames(), 4)
  assert_true(near(summed.sample(0, 0), 0.75, 1.0e-12))
  assert_true(near(summed.sample(1, 0), 0.0, 1.0e-12))
  let scaled = mix(a, b, gain_a=0.5, gain_b=0.0) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true(near(scaled.sample(0, 0), 0.125, 1.0e-12))
  // The longer buffer decides the length.
  let short = @audio.AudioBuffer::{
    sample_rate: 8000,
    channels: 1,
    data: [0.5],
  }
  let joined = mix(a, short) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(joined.frames(), 4)
  // A channel or sample rate mismatch is rejected.
  let stereo = @audio.AudioBuffer::{
    sample_rate: 8000,
    channels: 2,
    data: [0.0, 0.0],
  }
  assert_eq(mix_error_kind(a, stereo), "invalid")
  let other_rate = @audio.AudioBuffer::{
    sample_rate: 44100,
    channels: 1,
    data: [0.0],
  }
  assert_eq(mix_error_kind(a, other_rate), "invalid")
  assert_eq(mix_error_kind(a, b), "ok")
}

///|
test "tone produces the requested length and peak" {
  let audio = sine_buffer(1000.0, 8000, 100, amplitude=0.5)
  assert_eq(audio.frames(), 100)
  assert_eq(audio.channels, 1)
  assert_eq(audio.sample_rate, 8000)
  assert_true(near(audio.peak(), 0.5, 1.0e-12))
  assert_true(audio.sample(2, 0) > 0.4999)
  assert_eq(audio.sample(0, 0), 0.0)
  // Phase shifts the waveform without changing its level.
  let shifted = tone(1000.0, 8000, 100, phase=@math.PI / 2.0) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_true(near(shifted.sample(0, 0), 0.5, 1.0e-12))
  assert_eq(tone_error_kind(4000.0, 8000), "out_of_range")
  assert_eq(tone_error_kind(9000.0, 8000), "out_of_range")
  assert_eq(tone_error_kind(1000.0, 0), "out_of_range")
  assert_eq(tone_error_kind(1000.0, 8000), "ok")
}

///|
test "white noise is deterministic and bounded" {
  let first = white_noise(64, 8000, 42L)
  let second = white_noise(64, 8000, 42L)
  let third = white_noise(64, 8000, 43L)
  assert_eq(first.frames(), 64)
  assert_eq(first.channels, 1)
  assert_eq(first.sample_rate, 8000)
  for index = 0; index < 64; index = index + 1 {
    assert_eq(first.sample(index, 0), second.sample(index, 0))
  }
  let mut differences = 0
  for index = 0; index < 64; index = index + 1 {
    if first.sample(index, 0) != third.sample(index, 0) {
      differences = differences + 1
    }
  }
  assert_true(differences > 32)
  for value in first.data {
    assert_true(value.abs() <= 0.5)
  }
  assert_true(first.peak() > 0.1)
  // A zero seed is replaced rather than sticking at zero.
  assert_true(white_noise(16, 8000, 0L).peak() > 0.0)
  assert_eq(white_noise(0, 8000, 7L).frames(), 0)
  // The generator is roughly centred.
  assert_true(near(analyse(first).dc_offset, 0.0, 0.15))
}
