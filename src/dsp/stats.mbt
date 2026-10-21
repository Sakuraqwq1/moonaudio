// moonaudio - pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Summary measurements of an audio buffer, the numbers a level meter, a
/// silence detector or a test assertion needs.
///
/// All amplitudes are linear except the `*_dbfs` fields, which use the usual
/// `20 log10` scale with full scale at `0.0`; silence reports `-inf`.
pub(all) struct AudioStats {
  /// Number of frames (one sample per channel) in the buffer.
  frames : Int32
  /// Channel count of the buffer.
  channels : Int32
  /// Sample rate in hertz.
  sample_rate : Int32
  /// Largest absolute sample value.
  peak : Double
  /// [`peak`](AudioStats::peak) in dBFS.
  peak_dbfs : Double
  /// Root mean square of every sample.
  rms : Double
  /// [`rms`](AudioStats::rms) in dBFS.
  rms_dbfs : Double
  /// `peak / rms`, the headroom of the signal over its average level.
  crest_factor : Double
  /// Fraction of adjacent sample pairs that change sign, averaged over the
  /// channels; a sine at `f` hertz on a `fs` hertz stream reads about `2f / fs`.
  zero_crossing_rate : Double
  /// Mean sample value, i.e. how far the waveform sits off zero.
  dc_offset : Double
  /// Frames whose samples all stay within the silence threshold.
  silent_frames : Int32
  /// Playback duration in seconds.
  duration_seconds : Double
}

///|
/// Mean of an array, `0.0` when it is empty.
fn mean_of(data : Array[Double]) -> Double {
  if data.length() == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for value in data {
    sum = sum + value
  }
  sum / data.length().to_double()
}

///|
/// `true` when every channel of `frame` stays within `threshold` of zero.
fn frame_is_silent(
  audio : @audio.AudioBuffer,
  frame : Int32,
  threshold : Double,
) -> Bool {
  for channel = 0; channel < audio.channels; channel = channel + 1 {
    if audio.sample(frame, channel).abs() > threshold {
      return false
    }
  }
  true
}

///|
/// Zero crossing rate of a buffer: sign changes between neighbouring frames,
/// divided by the number of frame gaps and averaged over the channels.
fn zero_crossings(audio : @audio.AudioBuffer) -> Double {
  let frames = audio.frames()
  if frames < 2 || audio.channels <= 0 {
    return 0.0
  }
  let gaps = (frames - 1).to_double()
  let mut total = 0.0
  for channel = 0; channel < audio.channels; channel = channel + 1 {
    let mut crossings = 0
    let mut previous = audio.sample(0, channel)
    for frame = 1; frame < frames; frame = frame + 1 {
      let value = audio.sample(frame, channel)
      if (previous < 0.0) != (value < 0.0) {
        crossings = crossings + 1
      }
      previous = value
    }
    total = total + crossings.to_double() / gaps
  }
  total / audio.channels.to_double()
}

///|
/// Measure a buffer.
///
/// `silence_threshold` is the largest absolute sample value still counted as
/// silence; a frame is silent when every channel stays within it. The default
/// `0.001` is about -60 dBFS, which ignores dither and hum while still catching
/// real pauses.
pub fn analyse(
  audio : @audio.AudioBuffer,
  silence_threshold~ : Double = 0.001,
) -> AudioStats {
  let frames = audio.frames()
  let channels = audio.channels
  let peak = audio.peak()
  let rms = audio.rms()
  let offset = mean_of(audio.data)
  let mut silent = 0
  for frame = 0; frame < frames; frame = frame + 1 {
    if frame_is_silent(audio, frame, silence_threshold) {
      silent = silent + 1
    }
  }
  AudioStats::{
    frames,
    channels,
    sample_rate: audio.sample_rate,
    peak,
    peak_dbfs: @audio.dbfs(peak),
    rms,
    rms_dbfs: @audio.dbfs(rms),
    crest_factor: if rms > 0.0 {
      peak / rms
    } else {
      0.0
    },
    zero_crossing_rate: zero_crossings(audio),
    dc_offset: offset,
    silent_frames: silent,
    duration_seconds: if audio.sample_rate > 0 {
      frames.to_double() / audio.sample_rate.to_double()
    } else {
      0.0
    },
  }
}

///|
/// Render a summary as one `key=value` per line, in a stable order:
/// `frames`, `channels`, `sample_rate`, `peak`, `peak_dbfs`, `rms`, `rms_dbfs`,
/// `crest_factor`, `zero_crossing_rate`, `dc_offset`, `silent_frames`,
/// `duration_seconds`.
///
/// Counts print as integers and measurements with six decimals, so the output
/// is stable enough to diff or snapshot.
pub fn AudioStats::to_lines(self : AudioStats) -> String {
  let buffer = @buffer.Buffer::Buffer(size_hint=256)
  buffer.write_string_utf8("frames=\{self.frames}\n")
  buffer.write_string_utf8("channels=\{self.channels}\n")
  buffer.write_string_utf8("sample_rate=\{self.sample_rate}\n")
  buffer.write_string_utf8("peak=\{format_fixed(self.peak, 6)}\n")
  buffer.write_string_utf8("peak_dbfs=\{format_fixed(self.peak_dbfs, 6)}\n")
  buffer.write_string_utf8("rms=\{format_fixed(self.rms, 6)}\n")
  buffer.write_string_utf8("rms_dbfs=\{format_fixed(self.rms_dbfs, 6)}\n")
  buffer.write_string_utf8(
    "crest_factor=\{format_fixed(self.crest_factor, 6)}\n",
  )
  buffer.write_string_utf8(
    "zero_crossing_rate=\{format_fixed(self.zero_crossing_rate, 6)}\n",
  )
  buffer.write_string_utf8("dc_offset=\{format_fixed(self.dc_offset, 6)}\n")
  buffer.write_string_utf8("silent_frames=\{self.silent_frames}\n")
  buffer.write_string_utf8(
    "duration_seconds=\{format_fixed(self.duration_seconds, 6)}\n",
  )
  buffer_text(buffer)
}

///|
/// Drop silent frames from the start and the end of a buffer.
///
/// A frame counts as silent when every channel stays within `threshold` of
/// zero. Audio in the middle is never touched, and a fully silent buffer
/// becomes empty. The result keeps the sample rate and channel count.
pub fn trim_silence(
  audio : @audio.AudioBuffer,
  threshold~ : Double = 0.001,
) -> @audio.AudioBuffer {
  let frames = audio.frames()
  let mut first = frames
  let mut last = -1
  for frame = 0; frame < frames; frame = frame + 1 {
    if !frame_is_silent(audio, frame, threshold) {
      if first == frames {
        first = frame
      }
      last = frame
    }
  }
  if last < 0 {
    audio.slice(0, 0)
  } else {
    audio.slice(first, last + 1)
  }
}

///|
/// Subtract the mean sample value from every channel, removing a constant DC
/// bias while leaving the waveform shape intact.
pub fn remove_dc_offset(audio : @audio.AudioBuffer) -> @audio.AudioBuffer {
  let copy = audio.copy()
  let offset = mean_of(audio.data)
  for index = 0; index < copy.data.length(); index = index + 1 {
    copy.data[index] = copy.data[index] - offset
  }
  copy
}

///|
/// Apply a linear fade in over the first `frames` frames.
///
/// The first frame becomes exactly zero and frame `frames` is the first one at
/// full level, so the ramp is `i / frames`. A `frames` larger than the buffer,
/// or a non positive one, fades the whole buffer or does nothing respectively.
pub fn fade_in(
  audio : @audio.AudioBuffer,
  frames : Int32,
) -> @audio.AudioBuffer {
  let copy = audio.copy()
  let total = copy.frames()
  let span = frames.min(total)
  if span <= 0 {
    return copy
  }
  let channels = copy.channels
  let scale = span.to_double()
  for frame = 0; frame < span; frame = frame + 1 {
    let gain = frame.to_double() / scale
    for channel = 0; channel < channels; channel = channel + 1 {
      let index = frame * channels + channel
      copy.data[index] = copy.data[index] * gain
    }
  }
  copy
}

///|
/// Apply a linear fade out over the last `frames` frames.
///
/// The mirror image of [`fade_in`]: the final frame becomes exactly zero and the
/// ramp is `(total - 1 - frame) / frames` over the final `frames` frames.
pub fn fade_out(
  audio : @audio.AudioBuffer,
  frames : Int32,
) -> @audio.AudioBuffer {
  let copy = audio.copy()
  let total = copy.frames()
  let span = frames.min(total)
  if span <= 0 {
    return copy
  }
  let channels = copy.channels
  let scale = span.to_double()
  for frame = total - span; frame < total; frame = frame + 1 {
    let gain = (total - 1 - frame).to_double() / scale
    for channel = 0; channel < channels; channel = channel + 1 {
      let index = frame * channels + channel
      copy.data[index] = copy.data[index] * gain
    }
  }
  copy
}

///|
/// Sum two buffers sample by sample, scaling each by its own gain.
///
/// The result is as long as the longer input and the shorter one is treated as
/// silence past its end. Channel count and sample rate must match, otherwise
/// [`@audio.Invalid`] is raised.
pub fn mix(
  a : @audio.AudioBuffer,
  b : @audio.AudioBuffer,
  gain_a~ : Double = 1.0,
  gain_b~ : Double = 1.0,
) -> @audio.AudioBuffer raise @audio.AudioError {
  if a.channels != b.channels {
    raise @audio.Invalid("channel mismatch: \{a.channels} vs \{b.channels}")
  }
  if a.sample_rate != b.sample_rate {
    raise @audio.Invalid(
      "sample rate mismatch: \{a.sample_rate} vs \{b.sample_rate}",
    )
  }
  let channels = a.channels
  let frames = a.frames().max(b.frames())
  let data : Array[Double] = Array::make(frames * channels, 0.0)
  for frame = 0; frame < frames; frame = frame + 1 {
    for channel = 0; channel < channels; channel = channel + 1 {
      data[frame * channels + channel] = a.sample(frame, channel) * gain_a +
        b.sample(frame, channel) * gain_b
    }
  }
  @audio.AudioBuffer::{ sample_rate: a.sample_rate, channels, data, }
}

///|
/// Generate a mono sinusoid.
///
/// `frequency` is in hertz and must lie in `[0, sample_rate / 2)`, `frames` is
/// the number of samples and `phase` is an offset in radians applied to the
/// whole waveform. Samples are clamped to `[-1, 1]` so the result honours the
/// buffer invariant even for an `amplitude` above one.
///
/// Raises [`@audio.OutOfRange`] for a non positive sample rate, a frequency
/// outside `[0, Nyquist)` or a negative frame count.
pub fn tone(
  frequency : Double,
  sample_rate : Int32,
  frames : Int32,
  amplitude~ : Double = 0.5,
  phase~ : Double = 0.0,
) -> @audio.AudioBuffer raise @audio.AudioError {
  if sample_rate <= 0 {
    raise @audio.OutOfRange("sample rate must be positive, got \{sample_rate}")
  }
  let nyquist = sample_rate.to_double() * 0.5
  if !(frequency >= 0.0) || frequency >= nyquist {
    raise @audio.OutOfRange(
      "frequency must be between 0 and the Nyquist limit \{nyquist}, got \{frequency}",
    )
  }
  if frames < 0 {
    raise @audio.OutOfRange("frame count must not be negative, got \{frames}")
  }
  let step = 2.0 * @math.PI * frequency / sample_rate.to_double()
  let data : Array[Double] = Array::make(frames, 0.0)
  for frame = 0; frame < frames; frame = frame + 1 {
    let value = amplitude * @math.sin(step * frame.to_double() + phase)
    data[frame] = @audio.clamp_sample(value)
  }
  @audio.AudioBuffer::{ sample_rate, channels: 1, data, }
}

///|
/// Generate deterministic white noise with a `xorshift64` generator.
///
/// The state starts at `seed` (a zero seed is replaced by `88172645463325252`
/// so the generator never sticks at zero) and each sample advances it with
/// Marsaglia's `x ^= x << 13; x ^= x >> 7; x ^= x << 17`, takes bits 11 to 63 as
/// a 53 bit integer, maps it to `[0, 1)` and then to `[-amplitude, amplitude]`.
/// The same seed therefore always produces the same buffer, which makes noise
/// based tests and fixtures reproducible.
///
/// Invalid sizes degrade gracefully: a non positive frame count yields an empty
/// buffer and a non positive sample rate is stored as `1`.
pub fn white_noise(
  frames : Int32,
  sample_rate : Int32,
  seed : Int64,
  amplitude~ : Double = 0.5,
) -> @audio.AudioBuffer {
  let count = if frames > 0 { frames } else { 0 }
  let rate = if sample_rate > 0 { sample_rate } else { 1 }
  let data : Array[Double] = Array::make(count, 0.0)
  let mut state = if seed == 0L { 88172645463325252L } else { seed }
  let inverse = 1.0 / 9007199254740992.0
  for index = 0; index < count; index = index + 1 {
    state = state ^ (state << 13)
    state = state ^ (state >> 7)
    state = state ^ (state << 17)
    let bits = (state >> 11) & 9007199254740991L
    let uniform = bits.to_double() * inverse
    data[index] = @audio.clamp_sample((uniform * 2.0 - 1.0) * amplitude)
  }
  @audio.AudioBuffer::{ sample_rate: rate, channels: 1, data, }
}
