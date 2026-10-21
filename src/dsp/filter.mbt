// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Second order filter shapes from the RBJ audio EQ cookbook.
///
/// The five "boost/cut" variants [`Peaking`](FilterKind::Peaking),
/// [`LowShelf`](FilterKind::LowShelf) and [`HighShelf`](FilterKind::HighShelf)
/// use `gain_db`; the others ignore it.
pub(all) enum FilterKind {
  /// Pass frequencies below the cutoff, roll off above it.
  LowPass
  /// Pass frequencies above the cutoff, roll off below it.
  HighPass
  /// Pass a band around the centre frequency with 0 dB peak gain.
  BandPass
  /// Reject a band around the centre frequency.
  Notch
  /// Boost or cut a band around the centre frequency by `gain_db`.
  Peaking
  /// Boost or cut everything below the corner by `gain_db`.
  LowShelf
  /// Boost or cut everything above the corner by `gain_db`.
  HighShelf
}

///|
/// Normalised coefficients of a biquad section:
///
/// `y[n] = b0 x[n] + b1 x[n-1] + b2 x[n-2] - a1 y[n-1] - a2 y[n-2]`
///
/// `a0` is divided out at construction, so the recursion above is exactly the
/// transfer function that was designed.
pub(all) struct Biquad {
  /// Feed forward coefficient of the current sample.
  b0 : Double
  /// Feed forward coefficient of the previous sample.
  b1 : Double
  /// Feed forward coefficient of the sample before that.
  b2 : Double
  /// Feedback coefficient of the previous output.
  a1 : Double
  /// Feedback coefficient of the output before that.
  a2 : Double
}

///|
/// Direct form I filter memory: the last two inputs and outputs.
///
/// The fields are mutable so [`Biquad::process_sample`] can advance the
/// history in place while returning the filtered sample; pass one state per
/// channel and keep reusing it for the whole stream.
pub(all) struct BiquadState {
  /// `x[n-1]`.
  mut x1 : Double
  /// `x[n-2]`.
  mut x2 : Double
  /// `y[n-1]`.
  mut y1 : Double
  /// `y[n-2]`.
  mut y2 : Double
}

///|
/// A zeroed filter memory, i.e. a silent history.
pub fn BiquadState::new() -> BiquadState {
  BiquadState::{ x1: 0.0, x2: 0.0, y1: 0.0, y2: 0.0, }
}

///|
/// Design a biquad from the RBJ audio EQ cookbook.
///
/// `frequency` is the cutoff, centre or corner frequency in hertz and must lie
/// strictly between 0 and `sample_rate / 2`; `q` is the quality factor (the
/// resonance) and must be positive, with `1 / sqrt(2)` giving a maximally flat
/// Butterworth response. `gain_db` is only read by the shelving and peaking
/// shapes, where `A = 10^(gain_db / 40)`; shelving filters fix the shelf slope
/// at `S = 1` and ignore `q`.
///
/// Raises [`@audio.OutOfRange`] for a non positive sample rate, a frequency
/// outside `(0, Nyquist)` or a non positive `q`.
pub fn Biquad::new(
  kind : FilterKind,
  sample_rate : Int32,
  frequency : Double,
  q~ : Double = 0.7071067811865476,
  gain_db~ : Double = 0.0,
) -> Biquad raise @audio.AudioError {
  if sample_rate <= 0 {
    raise @audio.OutOfRange("sample rate must be positive, got \{sample_rate}")
  }
  let nyquist = sample_rate.to_double() * 0.5
  if !(frequency > 0.0) || frequency >= nyquist {
    raise @audio.OutOfRange(
      "frequency must be between 0 and the Nyquist limit \{nyquist}, got \{frequency}",
    )
  }
  if !(q > 0.0) {
    raise @audio.OutOfRange("Q must be positive, got \{q}")
  }
  let omega = 2.0 * @math.PI * frequency / sample_rate.to_double()
  let cosine = @math.cos(omega)
  let sine = @math.sin(omega)
  let alpha = sine / (2.0 * q)
  let gain = @math.pow(10.0, gain_db / 40.0)
  let shelf_alpha = sine * 0.5 * 2.0.sqrt()
  let shelf_beta = 2.0 * gain.sqrt() * shelf_alpha
  let (b0, b1, b2, a0, a1, a2) = match kind {
    LowPass =>
      (
        (1.0 - cosine) * 0.5,
        1.0 - cosine,
        (1.0 - cosine) * 0.5,
        1.0 + alpha,
        -2.0 * cosine,
        1.0 - alpha,
      )
    HighPass =>
      (
        (1.0 + cosine) * 0.5,
        -(1.0 + cosine),
        (1.0 + cosine) * 0.5,
        1.0 + alpha,
        -2.0 * cosine,
        1.0 - alpha,
      )
    BandPass => (alpha, 0.0, -alpha, 1.0 + alpha, -2.0 * cosine, 1.0 - alpha)
    Notch => (1.0, -2.0 * cosine, 1.0, 1.0 + alpha, -2.0 * cosine, 1.0 - alpha)
    Peaking =>
      (
        1.0 + alpha * gain,
        -2.0 * cosine,
        1.0 - alpha * gain,
        1.0 + alpha / gain,
        -2.0 * cosine,
        1.0 - alpha / gain,
      )
    LowShelf =>
      (
        gain * (gain + 1.0 - (gain - 1.0) * cosine + shelf_beta),
        2.0 * gain * (gain - 1.0 - (gain + 1.0) * cosine),
        gain * (gain + 1.0 - (gain - 1.0) * cosine - shelf_beta),
        gain + 1.0 + (gain - 1.0) * cosine + shelf_beta,
        -2.0 * (gain - 1.0 + (gain + 1.0) * cosine),
        gain + 1.0 + (gain - 1.0) * cosine - shelf_beta,
      )
    HighShelf =>
      (
        gain * (gain + 1.0 + (gain - 1.0) * cosine + shelf_beta),
        -2.0 * gain * (gain - 1.0 + (gain + 1.0) * cosine),
        gain * (gain + 1.0 + (gain - 1.0) * cosine - shelf_beta),
        gain + 1.0 - (gain - 1.0) * cosine + shelf_beta,
        2.0 * (gain - 1.0 - (gain + 1.0) * cosine),
        gain + 1.0 - (gain - 1.0) * cosine - shelf_beta,
      )
  }
  if a0 == 0.0 || a0.is_nan() {
    raise @audio.OutOfRange("filter design produced an invalid a0")
  }
  Biquad::{ b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0, }
}

///|
/// Filter one sample, advancing `state` by one step.
///
/// The recursion is the direct form I difference equation of [`Biquad`], so
/// feeding a stream through the same `state` yields the whole filtered signal:
///
/// ```text
/// let state = BiquadState::new()
/// let y = filter.process_sample(x, state)
/// ```
pub fn Biquad::process_sample(
  self : Biquad,
  x : Double,
  state : BiquadState,
) -> Double {
  let y = self.b0 * x +
    self.b1 * state.x1 +
    self.b2 * state.x2 -
    self.a1 * state.y1 -
    self.a2 * state.y2
  state.x2 = state.x1
  state.x1 = x
  state.y2 = state.y1
  state.y1 = y
  y
}

///|
/// Filter a block of samples from a silent history, returning a new array.
pub fn Biquad::apply(self : Biquad, samples : Array[Double]) -> Array[Double] {
  let state = BiquadState::new()
  let out : Array[Double] = Array::make(samples.length(), 0.0)
  for index = 0; index < samples.length(); index = index + 1 {
    out[index] = self.process_sample(samples[index], state)
  }
  out
}

///|
/// Filter every channel of a buffer independently, keeping its layout.
///
/// Each channel gets its own [`BiquadState`], so a stereo buffer is filtered as
/// two independent streams and the channels never bleed into each other.
pub fn Biquad::apply_buffer(
  self : Biquad,
  audio : @audio.AudioBuffer,
) -> @audio.AudioBuffer {
  let frames = audio.frames()
  let channels = audio.channels
  let data : Array[Double] = Array::make(frames * channels, 0.0)
  for channel = 0; channel < channels; channel = channel + 1 {
    let state = BiquadState::new()
    for frame = 0; frame < frames; frame = frame + 1 {
      let index = frame * channels + channel
      data[index] = self.process_sample(audio.data[index], state)
    }
  }
  @audio.AudioBuffer::{ sample_rate: audio.sample_rate, channels, data, }
}
