// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Full scale reference of the dB scale used by [`Spectrogram`]: a sinusoid of
/// peak amplitude `1.0` reads `0.0` dB.
const FULL_SCALE_DB : Double = 0.0

///|
/// Default noise floor of a spectrogram. Bins quieter than this are clamped so
/// silence renders as a uniform background instead of `-inf`.
const FLOOR_DB : Double = -100.0

///|
/// Number of colour steps the SVG heat map quantises to.
const SVG_LEVELS : Int32 = 32

///|
/// A short-time Fourier transform of an audio buffer: one column of dB
/// magnitudes per hop, one row per frequency bin.
///
/// `frames[f][k]` is the magnitude in decibels of bin `k` of frame `f`, where
/// bin `k` sits at `k * sample_rate / fft_size` hertz. Values are floored at
/// `min_db` and capped at `max_db`, so the matrix never contains infinities and
/// can be written straight to CSV or mapped to colours.
pub(all) struct Spectrogram {
  /// Sample rate of the analysed buffer, in hertz.
  sample_rate : Int32
  /// Transform length in samples, always a power of two.
  fft_size : Int32
  /// Advance between successive frames, in samples.
  hop : Int32
  /// `frames * (fft_size / 2 + 1)` matrix of dB magnitudes, oldest first.
  frames : Array[Array[Double]]
  /// Upper end of the dB scale (`0.0`, i.e. full scale).
  max_db : Double
  /// Lower end of the dB scale, the silence floor.
  min_db : Double
}

///|
/// Number of frequency bins in one column: the DC bin, the Nyquist bin and the
/// bins in between.
fn bin_count(spectrum : Spectrogram) -> Int32 {
  if spectrum.fft_size <= 1 {
    0
  } else {
    spectrum.fft_size / 2 + 1
  }
}

///|
/// Hz per bin, `sample_rate / fft_size`.
pub fn Spectrogram::bin_hz(self : Spectrogram) -> Double {
  if self.fft_size <= 0 {
    0.0
  } else {
    self.sample_rate.to_double() / self.fft_size.to_double()
  }
}

///|
/// Mix every channel down to one mono signal, averaging all channels so a
/// correlated stereo pair keeps its level.
fn mono_samples(audio : @audio.AudioBuffer) -> Array[Double] {
  let frames = audio.frames()
  let channels = audio.channels
  let mono : Array[Double] = Array::make(frames, 0.0)
  if channels <= 1 {
    for frame = 0; frame < frames; frame = frame + 1 {
      mono[frame] = audio.sample(frame, 0)
    }
  } else {
    let divisor = channels.to_double()
    for frame = 0; frame < frames; frame = frame + 1 {
      let mut sum = 0.0
      for channel = 0; channel < channels; channel = channel + 1 {
        sum = sum + audio.sample(frame, channel)
      }
      mono[frame] = sum / divisor
    }
  }
  mono
}

///|
/// Number of frames needed to cover `samples` samples.
///
/// A signal shorter than one transform produces a single zero padded frame; a
/// longer one produces frames while the window still overlaps the signal, and
/// the final frame is padded with zeros.
fn frame_count_for(samples : Int32, fft_size : Int32, hop : Int32) -> Int32 {
  if samples <= 0 || fft_size <= 0 || hop <= 0 {
    return 0
  }
  if samples <= fft_size {
    1
  } else {
    1 + (samples - fft_size + hop - 1) / hop
  }
}

///|
/// Clamp a dB value into `[min_db, max_db]`, mapping `-inf` and `nan` to the
/// floor.
fn floor_db(value : Double, min_db : Double, max_db : Double) -> Double {
  if value.is_nan() || value < min_db {
    min_db
  } else if value > max_db {
    max_db
  } else {
    value
  }
}

///|
/// Analyse an audio buffer into a dB magnitude spectrogram.
///
/// The buffer is mono mixed, windowed (`window`, symmetric taps summing to one,
/// so the window's coherent gain is already compensated) and transformed with
/// [`real_fft`]. The frame count is `1 + ceil((frames - fft_size) / hop)` for a
/// signal at least one transform long, and a single frame otherwise; the tail
/// of the last frame is zero padded, so no signal is dropped.
///
/// Amplitudes are one sided and peak normalised: a full scale sinusoid at a bin
/// centre reads `0.0` dB and anything below `-100.0` dB is floored, which keeps
/// the matrix free of `-inf`.
///
/// Raises [`@audio.OutOfRange`] for a non positive sample rate, hop or frame
/// count, and [`@audio.Invalid`] for an `fft_size` that is not a power of two
/// of at least two samples.
pub fn spectrogram(
  audio : @audio.AudioBuffer,
  fft_size~ : Int32 = 1024,
  hop~ : Int32 = 256,
  window~ : WindowKind = Hann,
) -> Spectrogram raise @audio.AudioError {
  if audio.sample_rate <= 0 {
    raise @audio.OutOfRange(
      "sample rate must be positive, got \{audio.sample_rate}",
    )
  }
  if audio.channels <= 0 {
    raise @audio.OutOfRange(
      "channel count must be positive, got \{audio.channels}",
    )
  }
  if fft_size < 2 || (fft_size & (fft_size - 1)) != 0 {
    raise @audio.Invalid(
      "FFT size must be a power of two no smaller than 2, got \{fft_size}",
    )
  }
  if hop <= 0 {
    raise @audio.OutOfRange("hop size must be positive, got \{hop}")
  }
  let mono = mono_samples(audio)
  let taps = window.coefficients(fft_size)
  let mut gain = 0.0
  for tap in taps {
    gain = gain + tap
  }
  if gain <= 0.0 {
    gain = 1.0
  }
  let bins = fft_size / 2 + 1
  let count = mono.length()
  let total = frame_count_for(count, fft_size, hop)
  let frames : Array[Array[Double]] = []
  let segment : Array[Double] = Array::make(fft_size, 0.0)
  for frame = 0; frame < total; frame = frame + 1 {
    let start = frame * hop
    for index = 0; index < fft_size; index = index + 1 {
      let position = start + index
      segment[index] = if position < count {
        mono[position] * taps[index]
      } else {
        0.0
      }
    }
    let spectrum = real_fft(segment)
    let row : Array[Double] = Array::make(bins, FLOOR_DB)
    let reachable = spectrum.length().min(bins)
    for bin = 0; bin < reachable; bin = bin + 1 {
      let amplitude = spectrum[bin].magnitude() / gain
      let peak = if bin == 0 || bin == bins - 1 {
        amplitude
      } else {
        2.0 * amplitude
      }
      row[bin] = floor_db(20.0 * @math.log10(peak), FLOOR_DB, FULL_SCALE_DB)
    }
    frames.push(row)
  }
  Spectrogram::{
    sample_rate: audio.sample_rate,
    fft_size,
    hop,
    frames,
    max_db: FULL_SCALE_DB,
    min_db: FLOOR_DB,
  }
}

///|
/// Shape of the matrix as `(frames, bins)`: one row per hop and one column per
/// frequency bin. An empty analysis reports `(0, fft_size / 2 + 1)`.
pub fn Spectrogram::size(self : Spectrogram) -> (Int32, Int32) {
  (self.frames.length(), bin_count(self))
}

///|
/// Frequency of the loudest bin of `frame`, in hertz.
///
/// `bin_hz` overrides the bin spacing, which is useful when the spectrogram was
/// produced with a different transform length than the one now wanted; passing
/// `0` (the default) uses `sample_rate / fft_size`. An out of range frame or an
/// empty matrix yields `0.0`.
pub fn Spectrogram::peak_frequency(
  self : Spectrogram,
  frame : Int32,
  bin_hz~ : Double = 0.0,
) -> Double {
  if frame < 0 || frame >= self.frames.length() {
    return 0.0
  }
  let row = self.frames[frame]
  if row.length() == 0 {
    return 0.0
  }
  let mut best = 0
  let mut peak = row[0]
  for bin = 1; bin < row.length(); bin = bin + 1 {
    if row[bin] > peak {
      peak = row[bin]
      best = bin
    }
  }
  let spacing = if bin_hz > 0.0 { bin_hz } else { self.bin_hz() }
  best.to_double() * spacing
}

///|
/// Render the matrix as CSV.
///
/// The first row is the header `frequency_hz,frame_0,frame_1,...`; every further
/// row is one frequency bin, starting with its centre frequency in hertz and
/// followed by the dB value of that bin in every frame. Values use three
/// decimals, so a spreadsheet can plot the matrix directly.
pub fn Spectrogram::to_csv(self : Spectrogram) -> String {
  let buffer = @buffer.Buffer::Buffer(size_hint=4096)
  let bins = bin_count(self)
  let total = self.frames.length()
  let spacing = self.bin_hz()
  buffer.write_string_utf8("frequency_hz")
  for frame = 0; frame < total; frame = frame + 1 {
    buffer.write_string_utf8(",frame_\{frame}")
  }
  buffer.write_string_utf8("\n")
  for bin = 0; bin < bins; bin = bin + 1 {
    buffer.write_string_utf8(format_fixed(bin.to_double() * spacing, 3))
    for frame = 0; frame < total; frame = frame + 1 {
      buffer.write_string_utf8(",")
      buffer.write_string_utf8(format_fixed(self.frames[frame][bin], 3))
    }
    buffer.write_string_utf8("\n")
  }
  buffer_text(buffer)
}

///|
/// Map a dB value to a colour step in `[0, SVG_LEVELS)`.
fn level_of(spectrum : Spectrogram, value : Double) -> Int32 {
  let span = spectrum.max_db - spectrum.min_db
  if span <= 0.0 {
    return 0
  }
  let ratio = (value - spectrum.min_db) / span
  let step = (ratio * (SVG_LEVELS - 1).to_double()).round().to_int()
  step.max(0).min(SVG_LEVELS - 1)
}

///|
/// Linear interpolation between two colour stops.
fn channel(stops : Array[Double], index : Int32, fraction : Double) -> Int32 {
  let low = stops[index]
  let high = stops[index + 1]
  (low + (high - low) * fraction).round().to_int().max(0).min(255)
}

///|
/// Magma style colour for one of the `SVG_LEVELS` steps: near black, purple,
/// magenta, orange, and pale yellow at full scale. Returned as an `rgb()`
/// function so the SVG stays free of text nodes.
fn magma_color(level : Int32) -> String {
  let red : Array[Double] = [0.0, 50.0, 120.0, 190.0, 245.0, 252.0]
  let green : Array[Double] = [0.0, 10.0, 28.0, 60.0, 130.0, 253.0]
  let blue : Array[Double] = [4.0, 94.0, 126.0, 110.0, 90.0, 191.0]
  let position = level.to_double() / (SVG_LEVELS - 1).to_double() * 5.0
  let index = position.to_int().min(4).max(0)
  let fraction = position - index.to_double()
  "rgb(\{channel(red, index, fraction)},\{channel(green, index, fraction)},\{channel(blue, index, fraction)})"
}

///|
/// Append one SVG rectangle.
fn write_rect(
  buffer : @buffer.Buffer,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  fill : String,
) -> Unit {
  buffer.write_string_utf8(
    "<rect x=\"\{format_position(x)}\" y=\"\{format_position(y)}\" width=\"\{format_position(width)}\" height=\"\{format_position(height)}\" fill=\"\{fill}\"/>\n",
  )
}

///|
/// Render the spectrogram as a self contained SVG heat map.
///
/// Time runs left to right and frequency bottom to top, and colour follows the
/// magma ramp from near black at `min_db` to pale yellow at `max_db`. The image
/// is drawn on a `width x height` canvas: when the matrix has more frames or
/// bins than pixels, neighbouring cells are pooled by peak level, and runs of
/// equal colour are merged into one rectangle, so the output stays compact.
/// Only numeric attributes are emitted, which makes the result safe to inline
/// without escaping.
pub fn Spectrogram::to_svg(
  self : Spectrogram,
  width~ : Int32 = 640,
  height~ : Int32 = 240,
) -> String {
  let canvas_width = width.max(16)
  let canvas_height = height.max(16)
  let buffer = @buffer.Buffer::Buffer(size_hint=8192)
  buffer.write_string_utf8(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\{canvas_width}\" height=\"\{canvas_height}\" viewBox=\"0 0 \{canvas_width} \{canvas_height}\">\n",
  )
  buffer.write_string_utf8(
    "<rect x=\"0\" y=\"0\" width=\"\{canvas_width}\" height=\"\{canvas_height}\" fill=\"rgb(0,0,4)\"/>\n",
  )
  let bins = bin_count(self)
  let total = self.frames.length()
  if bins > 0 && total > 0 {
    let columns = total.min(canvas_width).max(1)
    let rows = bins.min(canvas_height).max(1)
    let cell_width = canvas_width.to_double() / columns.to_double()
    let cell_height = canvas_height.to_double() / rows.to_double()
    buffer.write_string_utf8("<g shape-rendering=\"crispEdges\">\n")
    for row = 0; row < rows; row = row + 1 {
      let bin_high = bins - 1 - row * bins / rows
      let bin_low = bins - 1 - ((row + 1) * bins / rows - 1)
      let mut run_start = 0
      let mut run_level = -1
      let mut column = 0
      while column <= columns {
        let mut level = -1
        if column < columns {
          let frame_low = column * total / columns
          let frame_high = (column + 1) * total / columns - 1
          let mut peak = self.min_db
          for frame = frame_low; frame <= frame_high; frame = frame + 1 {
            let values = self.frames[frame]
            for bin = bin_low
                bin <= bin_high && bin < values.length()
                bin = bin + 1 {
              if values[bin] > peak {
                peak = values[bin]
              }
            }
          }
          level = level_of(self, peak)
        }
        if column == columns || level != run_level {
          if run_level > 0 {
            let x = run_start.to_double() * cell_width
            let y = row.to_double() * cell_height
            let span = (column - run_start).to_double() * cell_width
            write_rect(buffer, x, y, span, cell_height, magma_color(run_level))
          }
          run_start = column
          run_level = level
        }
        column = column + 1
      }
    }
    buffer.write_string_utf8("</g>\n")
  }
  buffer.write_string_utf8("</svg>\n")
  buffer_text(buffer)
}
