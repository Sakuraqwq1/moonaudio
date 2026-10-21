// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// π, kept local so the interpolation kernels do not depend on how
/// `moonbitlang/core/math` spells its constant.
let pi : Double = 3.141592653589793

///|
/// Resample `audio` to `target_rate` hertz.
///
/// Every channel is converted independently and the result keeps the channel
/// layout of the input, only the rate changes. A target rate equal to the
/// source rate returns a copy, which makes the function safe to call
/// unconditionally. `quality` picks the interpolation kernel and `taps` is the
/// half-width of the sinc kernel in source frames (ignored by `Linear` and
/// `Cubic`).
///
/// Edges are handled by zero padding: samples outside the input read as `0.0`,
/// so the sinc reconstruction fades in and out over a few taps instead of
/// wrapping around.
pub fn resample(
  audio : @audio.AudioBuffer,
  target_rate : Int32,
  quality~ : ResampleQuality = Sinc,
  taps~ : Int32 = 16,
) -> @audio.AudioBuffer raise @audio.AudioError {
  if target_rate <= 0 {
    raise @audio.OutOfRange(
      "target sample rate must be positive, got \{target_rate}",
    )
  }
  if audio.channels <= 0 {
    raise @audio.OutOfRange("cannot resample a buffer with no channels")
  }
  if audio.sample_rate <= 0 {
    raise @audio.OutOfRange("cannot resample a buffer with no sample rate")
  }
  match quality {
    Sinc =>
      if taps < 1 {
        raise @audio.OutOfRange("sinc taps must be at least 1, got \{taps}")
      }
    _ => ()
  }
  let frames = audio.frames()
  if target_rate == audio.sample_rate || frames == 0 {
    return @audio.AudioBuffer::{
      sample_rate: target_rate,
      channels: audio.channels,
      data: audio.data.copy(),
    }
  }
  let out_frames = sample_count(frames, audio.sample_rate, target_rate)
  let step = audio.sample_rate.to_double() / target_rate.to_double()
  // Cutoff normalised to the *source* Nyquist. Downsampling must lower it so
  // the kernel rejects the content that would alias; the 0.95 guard band keeps
  // the transition region clear of the new Nyquist frequency.
  let cutoff = (1.0 / step).min(1.0) * 0.95
  // The kernel keeps `taps` lobes of the sinc inside its window. When the
  // cutoff drops, the sinc stretches by `1 / cutoff`, so the window has to
  // reach proportionally further into the source to stay as selective.
  let window_half = taps.to_double() / cutoff
  let radius = window_half.ceil().to_int()
  let source = audio.to_channels()
  let converted : Array[Array[Double]] = []
  for channel = 0; channel < audio.channels; channel = channel + 1 {
    let input = source[channel]
    let output : Array[Double] = Array::make(out_frames, 0.0)
    match quality {
      Linear =>
        for index = 0; index < out_frames; index = index + 1 {
          output[index] = linear_at(input, index.to_double() * step)
        }
      Cubic =>
        for index = 0; index < out_frames; index = index + 1 {
          output[index] = cubic_at(input, index.to_double() * step)
        }
      Sinc =>
        for index = 0; index < out_frames; index = index + 1 {
          output[index] = sinc_at(
            input,
            index.to_double() * step,
            cutoff,
            window_half,
            radius,
          )
        }
    }
    converted.push(output)
  }
  @audio.AudioBuffer::from_channels(target_rate, converted)
}

///|
/// Resample by a free-form `ratio` (`2.0` doubles the rate, `0.5` halves it).
///
/// The rate is rounded to the nearest integer hertz and the work is delegated
/// to [`resample`], so a ratio of `2.0` and an explicit doubled target rate
/// produce byte identical results.
pub fn resample_by_ratio(
  audio : @audio.AudioBuffer,
  ratio : Double,
  quality~ : ResampleQuality = Sinc,
) -> @audio.AudioBuffer raise @audio.AudioError {
  let scaled = audio.sample_rate.to_double() * ratio
  if scaled.is_nan() || scaled <= 0.0 || scaled > 2147483647.0 {
    raise @audio.OutOfRange(
      "resample ratio must be positive and finite, got \{ratio}",
    )
  }
  resample(audio, scaled.round().to_int(), quality~)
}

///|
/// Read one sample, treating everything outside the input as silence.
fn sample_at(input : Array[Double], index : Int32) -> Double {
  if index < 0 || index >= input.length() {
    0.0
  } else {
    input[index]
  }
}

///|
/// Two point linear interpolation at a fractional frame position.
fn linear_at(input : Array[Double], position : Double) -> Double {
  let base = position.floor().to_int()
  let fraction = position - base.to_double()
  @audio.lerp(sample_at(input, base), sample_at(input, base + 1), fraction)
}

///|
/// Four point Catmull-Rom cubic interpolation at a fractional frame position.
///
/// The spline uses the two samples on each side of `position`, which keeps the
/// kernel compact while staying third-order accurate; the weights sum to one
/// for every fractional offset, so gain is unity at DC.
fn cubic_at(input : Array[Double], position : Double) -> Double {
  let base = position.floor().to_int()
  let t = position - base.to_double()
  let y0 = sample_at(input, base - 1)
  let y1 = sample_at(input, base)
  let y2 = sample_at(input, base + 1)
  let y3 = sample_at(input, base + 2)
  let a = -0.5 * y0 + 1.5 * y1 - 1.5 * y2 + 0.5 * y3
  let b = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3
  let c = -0.5 * y0 + 0.5 * y2
  ((a * t + b) * t + c) * t + y1
}

///|
/// Windowed-sinc interpolation at a fractional frame position.
///
/// Every source sample within `radius` frames of `position` contributes one
/// tap, and the result is divided by the sum of the weights, which makes the
/// reconstruction gain exactly one even though the truncated Blackman-Harris
/// kernel does not sum to one on its own.
fn sinc_at(
  input : Array[Double],
  position : Double,
  cutoff : Double,
  window_half : Double,
  radius : Int32,
) -> Double {
  let base = position.floor().to_int()
  let fraction = position - base.to_double()
  let mut sum = 0.0
  let mut weight_sum = 0.0
  for offset = -radius + 1; offset <= radius; offset = offset + 1 {
    let distance = offset.to_double() - fraction
    let weight = sinc_weight(distance, cutoff, window_half)
    sum += sample_at(input, base + offset) * weight
    weight_sum += weight
  }
  if weight_sum.abs() < 1.0e-12 {
    0.0
  } else {
    sum / weight_sum
  }
}

///|
/// One tap of the lowpass interpolation kernel.
///
/// `distance` is measured in source frames from the reconstruction point,
/// `cutoff` is the normalised cutoff frequency (`1.0` = source Nyquist) and
/// `window_half` is the half-width of the Blackman-Harris window, also in
/// source frames.
fn sinc_weight(
  distance : Double,
  cutoff : Double,
  window_half : Double,
) -> Double {
  let position = (distance + window_half) / (2.0 * window_half)
  if position < 0.0 || position > 1.0 {
    return 0.0
  }
  let scaled = cutoff * distance
  let sinc = if scaled.abs() < 1.0e-9 {
    1.0
  } else {
    let angle = pi * scaled
    @math.sin(angle) / angle
  }
  cutoff * sinc * blackman_harris(position)
}

///|
/// Four term Blackman-Harris window over `[0, 1]`, normalised to peak `1.0` at
/// the centre.
///
/// The sidelobes are about `-92 dB`, which is why the sinc kernel can be
/// truncated at a few taps without audible ringing. The second and third
/// harmonics of the window are evaluated from `cos` with the standard multiple
/// angle identities, so one tap costs a single sine and a single cosine.
fn blackman_harris(position : Double) -> Double {
  let c1 = @math.cos(2.0 * pi * position)
  let c2 = 2.0 * c1 * c1 - 1.0
  let c3 = 4.0 * c1 * c1 * c1 - 3.0 * c1
  0.35875 - 0.48829 * c1 + 0.14128 * c2 - 0.01168 * c3
}
