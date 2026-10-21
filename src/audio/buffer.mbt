// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// A decoded audio signal: interleaved `Double` samples normalised to
/// `[-1.0, 1.0]`, plus the sample rate and channel count needed to interpret
/// them.
///
/// Interleaved layout keeps decoding, resampling and re-encoding simple: frame
/// `f` channel `c` lives at `data[f * channels + c]`. Samples are stored as
/// `Double` because every integer PCM width up to 32 bit converts losslessly
/// into it, and DSP stages work in floating point anyway.
pub(all) struct AudioBuffer {
  sample_rate : Int32
  channels : Int32
  data : Array[Double]
}

///|
/// Create an empty buffer with `sample_rate` and `channels`.
pub fn AudioBuffer::new(sample_rate : Int32, channels : Int32) -> AudioBuffer {
  AudioBuffer::{ sample_rate, channels, data: [], }
}

///|
/// Create a silent buffer that already contains `frames` frames.
pub fn AudioBuffer::silence(
  sample_rate : Int32,
  channels : Int32,
  frames : Int32,
) -> AudioBuffer raise AudioError {
  if sample_rate <= 0 {
    raise OutOfRange("sample rate must be positive, got \{sample_rate}")
  }
  if channels <= 0 {
    raise OutOfRange("channel count must be positive, got \{channels}")
  }
  if frames < 0 {
    raise OutOfRange("frame count must not be negative, got \{frames}")
  }
  AudioBuffer::{
    sample_rate,
    channels,
    data: Array::make(frames * channels, 0.0),
  }
}

///|
/// Number of frames (one sample per channel) in the buffer.
pub fn AudioBuffer::frames(self : AudioBuffer) -> Int32 {
  if self.channels <= 0 {
    0
  } else {
    self.data.length() / self.channels
  }
}

///|
/// `true` when the buffer carries no frames.
pub fn AudioBuffer::is_empty(self : AudioBuffer) -> Bool {
  self.frames() == 0
}

///|
/// Playback duration in seconds.
pub fn AudioBuffer::duration_seconds(self : AudioBuffer) -> Double {
  if self.sample_rate <= 0 {
    0.0
  } else {
    self.frames().to_double() / self.sample_rate.to_double()
  }
}

///|
/// Read one sample; out of range reads yield `0.0` so DSP stages stay total.
pub fn AudioBuffer::sample(
  self : AudioBuffer,
  frame : Int32,
  channel : Int32,
) -> Double {
  if channel < 0 || channel >= self.channels {
    return 0.0
  }
  let index = frame * self.channels + channel
  if index < 0 || index >= self.data.length() {
    0.0
  } else {
    self.data[index]
  }
}

///|
/// Overwrite one sample, ignoring writes outside the buffer.
pub fn AudioBuffer::set_sample(
  self : AudioBuffer,
  frame : Int32,
  channel : Int32,
  value : Double,
) -> Unit {
  if channel < 0 || channel >= self.channels {
    return
  }
  let index = frame * self.channels + channel
  if index >= 0 && index < self.data.length() {
    self.data[index] = value
  }
}

///|
/// Append one frame given as a slice of per-channel samples.
///
/// The slice is padded with silence or truncated when its length differs from
/// the channel count.
pub fn AudioBuffer::push_frame(
  self : AudioBuffer,
  samples : ArrayView[Double],
) -> Unit {
  for channel = 0; channel < self.channels; channel = channel + 1 {
    self.data.push(
      if channel < samples.length() {
        samples[channel]
      } else {
        0.0
      },
    )
  }
}

///|
/// Append every frame of another buffer that shares the same layout.
pub fn AudioBuffer::append(
  self : AudioBuffer,
  other : AudioBuffer,
) -> Unit raise AudioError {
  if other.channels != self.channels {
    raise Invalid("channel mismatch: \{self.channels} vs \{other.channels}")
  }
  if other.sample_rate != self.sample_rate {
    raise Invalid(
      "sample rate mismatch: \{self.sample_rate} vs \{other.sample_rate}",
    )
  }
  for sample in other.data {
    self.data.push(sample)
  }
}

///|
/// Build a buffer from per-channel arrays, converting to interleaved layout.
pub fn AudioBuffer::from_channels(
  sample_rate : Int32,
  channels : Array[Array[Double]],
) -> AudioBuffer raise AudioError {
  let count = channels.length()
  if count == 0 {
    raise OutOfRange("at least one channel is required")
  }
  let mut frames = channels[0].length()
  for channel in channels {
    if channel.length() < frames {
      frames = channel.length()
    }
  }
  let data : Array[Double] = Array::make(frames * count, 0.0)
  for channel = 0; channel < count; channel = channel + 1 {
    let source = channels[channel]
    for frame = 0; frame < frames; frame = frame + 1 {
      data[frame * count + channel] = source[frame]
    }
  }
  AudioBuffer::{ sample_rate, channels: count, data, }
}

///|
/// Split the buffer into per-channel arrays.
pub fn AudioBuffer::to_channels(self : AudioBuffer) -> Array[Array[Double]] {
  let frames = self.frames()
  let result : Array[Array[Double]] = []
  for channel = 0; channel < self.channels; channel = channel + 1 {
    let samples : Array[Double] = Array::make(frames, 0.0)
    for frame = 0; frame < frames; frame = frame + 1 {
      samples[frame] = self.data[frame * self.channels + channel]
    }
    result.push(samples)
  }
  result
}

///|
/// Largest absolute sample value in the buffer.
pub fn AudioBuffer::peak(self : AudioBuffer) -> Double {
  let mut peak = 0.0
  for sample in self.data {
    let magnitude = sample.abs()
    if magnitude > peak {
      peak = magnitude
    }
  }
  peak
}

///|
/// Root mean square level of all samples.
pub fn AudioBuffer::rms(self : AudioBuffer) -> Double {
  if self.data.length() == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for sample in self.data {
    sum += sample * sample
  }
  (sum / self.data.length().to_double()).sqrt()
}

///|
/// Peak level in dBFS (`-inf` for silence).
pub fn AudioBuffer::peak_dbfs(self : AudioBuffer) -> Double {
  dbfs(self.peak())
}

///|
/// RMS level in dBFS (`-inf` for silence).
pub fn AudioBuffer::rms_dbfs(self : AudioBuffer) -> Double {
  dbfs(self.rms())
}

///|
/// Linear amplitude to dBFS, with 0.0 mapped to negative infinity.
pub fn dbfs(amplitude : Double) -> Double {
  let magnitude = amplitude.abs()
  if magnitude <= 0.0 {
    -@double.infinity
  } else {
    20.0 * @math.log10(magnitude)
  }
}

///|
/// dBFS back to linear amplitude.
pub fn from_dbfs(decibels : Double) -> Double {
  @math.pow(10.0, decibels / 20.0)
}

///|
/// Scale every sample so the peak equals `target` (in `[0, 1]`).
///
/// Returns the applied linear gain; a silent buffer is left untouched.
pub fn AudioBuffer::normalize(
  self : AudioBuffer,
  target~ : Double = 0.9,
) -> Double {
  let goal = if target < 0.0 {
    0.0
  } else if target > 1.0 {
    1.0
  } else {
    target
  }
  let peak = self.peak()
  if peak <= 0.0 {
    return 1.0
  }
  let gain = goal / peak
  for index = 0; index < self.data.length(); index = index + 1 {
    self.data[index] = self.data[index] * gain
  }
  gain
}

///|
/// Multiply every sample by `gain`.
pub fn AudioBuffer::apply_gain(self : AudioBuffer, gain : Double) -> Unit {
  for index = 0; index < self.data.length(); index = index + 1 {
    self.data[index] = self.data[index] * gain
  }
}

///|
/// Multiply every sample by `gain` while keeping `|sample| <= 1.0`.
pub fn AudioBuffer::apply_gain_clamped(
  self : AudioBuffer,
  gain : Double,
) -> Unit {
  for index = 0; index < self.data.length(); index = index + 1 {
    self.data[index] = clamp_sample(self.data[index] * gain)
  }
}

///|
/// Return a copy of the buffer.
pub fn AudioBuffer::copy(self : AudioBuffer) -> AudioBuffer {
  AudioBuffer::{
    sample_rate: self.sample_rate,
    channels: self.channels,
    data: self.data.copy(),
  }
}

///|
/// Return the frame range `[start, end)` as a new buffer.
pub fn AudioBuffer::slice(
  self : AudioBuffer,
  start : Int32,
  end : Int32,
) -> AudioBuffer {
  let frames = self.frames()
  let from = start.max(0).min(frames)
  let to = end.max(from).min(frames)
  let data : Array[Double] = Array::make((to - from) * self.channels, 0.0)
  let offset = from * self.channels
  for index = 0; index < data.length(); index = index + 1 {
    data[index] = self.data[offset + index]
  }
  AudioBuffer::{ sample_rate: self.sample_rate, channels: self.channels, data, }
}

///|
/// Downmix or upmix to `channels` channels.
///
/// Mono to stereo duplicates the channel, stereo to mono averages both
/// channels, and other conversions average all source channels then replicate
/// the result, which keeps analysis pipelines predictable.
pub fn AudioBuffer::remix(
  self : AudioBuffer,
  channels : Int32,
) -> AudioBuffer raise AudioError {
  if channels <= 0 {
    raise OutOfRange("channel count must be positive, got \{channels}")
  }
  if channels == self.channels {
    return self.copy()
  }
  let frames = self.frames()
  let data : Array[Double] = Array::make(frames * channels, 0.0)
  if self.channels == 1 && channels == 2 {
    for frame = 0; frame < frames; frame = frame + 1 {
      let value = self.data[frame]
      data[frame * 2] = value
      data[frame * 2 + 1] = value
    }
  } else if self.channels == 2 && channels == 1 {
    for frame = 0; frame < frames; frame = frame + 1 {
      data[frame] = (self.data[frame * 2] + self.data[frame * 2 + 1]) * 0.5
    }
  } else {
    for frame = 0; frame < frames; frame = frame + 1 {
      let mut sum = 0.0
      for channel = 0; channel < self.channels; channel = channel + 1 {
        sum += self.data[frame * self.channels + channel]
      }
      let value = sum / self.channels.to_double()
      for channel = 0; channel < channels; channel = channel + 1 {
        data[frame * channels + channel] = value
      }
    }
  }
  AudioBuffer::{ sample_rate: self.sample_rate, channels, data, }
}

///|
/// Linear interpolation between `a` and `b`.
pub fn lerp(a : Double, b : Double, t : Double) -> Double {
  a + (b - a) * t
}
