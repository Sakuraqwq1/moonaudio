// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// A complex number, the element type of every spectrum in `moonaudio`.
///
/// The type is deliberately plain: `re` and `im` are `Double` fields and all
/// arithmetic lives in the functions below, so spectra can be inspected,
/// serialised and compared without hidden state.
pub(all) struct Complex {
  re : Double
  im : Double
}

///|
/// Build a complex number from its real and imaginary parts.
pub fn Complex::new(re : Double, im : Double) -> Complex {
  Complex::{ re, im, }
}

///|
/// The additive identity `0 + 0i`.
pub fn Complex::zero() -> Complex {
  Complex::{ re: 0.0, im: 0.0, }
}

///|
/// Sum of two complex numbers.
pub fn Complex::add(self : Complex, other : Complex) -> Complex {
  Complex::{ re: self.re + other.re, im: self.im + other.im, }
}

///|
/// Difference of two complex numbers.
pub fn Complex::sub(self : Complex, other : Complex) -> Complex {
  Complex::{ re: self.re - other.re, im: self.im - other.im, }
}

///|
/// Product of two complex numbers,
/// `(a + bi)(c + di) = (ac - bd) + (ad + bc)i`.
pub fn Complex::mul(self : Complex, other : Complex) -> Complex {
  Complex::{
    re: self.re * other.re - self.im * other.im,
    im: self.re * other.im + self.im * other.re,
  }
}

///|
/// Multiply by a real factor.
pub fn Complex::scale(self : Complex, factor : Double) -> Complex {
  Complex::{ re: self.re * factor, im: self.im * factor, }
}

///|
/// Euclidean length `sqrt(re^2 + im^2)`, computed with `hypot` so it neither
/// underflows nor overflows for extreme magnitudes.
pub fn Complex::magnitude(self : Complex) -> Double {
  @math.hypot(self.re, self.im)
}

///|
/// Argument in radians, in `(-pi, pi]`, measured from the positive real axis.
pub fn Complex::phase(self : Complex) -> Double {
  @math.atan2(self.im, self.re)
}

///|
/// Complex conjugate `re - im i`, the mirror about the real axis.
pub fn Complex::conjugate(self : Complex) -> Complex {
  Complex::{ re: self.re, im: -self.im, }
}

///|
/// `true` when both parts are exactly equal, handy in tests.
pub fn Complex::same(self : Complex, other : Complex) -> Bool {
  self.re == other.re && self.im == other.im
}

///|
/// Complex addition operator, mirroring [`Complex::add`].
pub impl Add for Complex with fn add(self, other) {
  self.add(other)
}

///|
/// Complex subtraction operator, mirroring [`Complex::sub`].
pub impl Sub for Complex with fn sub(self, other) {
  self.sub(other)
}

///|
/// Complex multiplication operator, mirroring [`Complex::mul`].
pub impl Mul for Complex with fn mul(self, other) {
  self.mul(other)
}

///|
/// Complex negation.
pub fn Complex::neg(self : Complex) -> Complex {
  Complex::{ re: -self.re, im: -self.im, }
}

///|
/// Complex negation operator, mirroring [`Complex::neg`].
pub impl Neg for Complex with fn neg(self) {
  Complex::{ re: -self.re, im: -self.im, }
}

///|
/// `true` when `value` is a positive power of two.
fn is_power_of_two(value : Int32) -> Bool {
  value > 0 && (value & (value - 1)) == 0
}

///|
/// Smallest power of two that is greater than or equal to `value`, or `1` for
/// non positive input.
fn next_power_of_two(value : Int32) -> Int32 {
  if value <= 1 {
    return 1
  }
  let mut result = 1
  while result < value {
    result = result * 2
  }
  result
}

///|
/// Base two logarithm of a power of two, i.e. the number of bits it needs.
fn log2_floor(value : Int32) -> Int32 {
  let mut shifted = value
  let mut bits = 0
  while shifted > 1 {
    shifted = shifted >> 1
    bits = bits + 1
  }
  bits
}

///|
/// Reverse the low `width` bits of `value`, the index permutation of an
/// in-place radix-2 decimation-in-time transform.
fn reverse_bits(value : Int32, width : Int32) -> Int32 {
  let mut source = value
  let mut result = 0
  for _bit = 0; _bit < width; _bit = _bit + 1 {
    result = (result << 1) | (source & 1)
    source = source >> 1
  }
  result
}

///|
/// Table of `exp(-2 pi i k / size)` for `k` in `[0, size / 2)`.
///
/// Precomputing the twiddles once per transform keeps the butterflies free of
/// trigonometric calls and avoids the accumulated drift of a recurrence.
fn twiddle_table(size : Int32) -> Array[Complex] {
  let half = size / 2
  let table : Array[Complex] = Array::make(half, Complex::zero())
  let step = 2.0 * @math.PI / size.to_double()
  for index = 0; index < half; index = index + 1 {
    let angle = step * index.to_double()
    table[index] = Complex::{ re: @math.cos(angle), im: -@math.sin(angle), }
  }
  table
}

///|
/// In-place radix-2 Cooley-Tukey fast Fourier transform, computed out of place
/// on a copy of `input`.
///
/// `input.length()` must be a positive power of two; anything else raises
/// [`@audio.Invalid`] because silently rounding the length would change the
/// bin spacing a caller relies on. The returned array has the same length and
/// holds `X[k] = sum_n x[n] exp(-2 pi i k n / N)` without any normalisation, so
/// `ifft` is the exact inverse.
pub fn fft(input : Array[Complex]) -> Array[Complex] raise @audio.AudioError {
  let size = input.length()
  if size <= 0 {
    raise @audio.Invalid(
      "FFT length must be a positive power of two, got \{size}",
    )
  }
  if !is_power_of_two(size) {
    raise @audio.Invalid("FFT length must be a power of two, got \{size}")
  }
  let data = input.copy()
  let bits = log2_floor(size)
  for index = 0; index < size; index = index + 1 {
    let reversed = reverse_bits(index, bits)
    if reversed > index {
      let saved = data[index]
      data[index] = data[reversed]
      data[reversed] = saved
    }
  }
  let table = twiddle_table(size)
  let mut span = 2
  while span <= size {
    let half = span / 2
    let stride = size / span
    let mut start = 0
    while start < size {
      for offset = 0; offset < half; offset = offset + 1 {
        let weight = table[offset * stride]
        let head = start + offset
        let tail = head + half
        let rotated = weight.mul(data[tail])
        let even = data[head]
        data[head] = even.add(rotated)
        data[tail] = even.sub(rotated)
      }
      start = start + span
    }
    span = span * 2
  }
  data
}

///|
/// Inverse discrete Fourier transform, scaled by `1 / N`.
///
/// Computed with the conjugate trick: `ifft(x) = conj(fft(conj(x))) / N`, so
/// the forward transform is the only butterfly implementation in the package
/// and `ifft(fft(x))` round trips to within rounding error. `input.length()`
/// must be a positive power of two, otherwise [`@audio.Invalid`] is raised.
pub fn ifft(input : Array[Complex]) -> Array[Complex] raise @audio.AudioError {
  let size = input.length()
  if size <= 0 {
    raise @audio.Invalid(
      "FFT length must be a positive power of two, got \{size}",
    )
  }
  let flipped : Array[Complex] = Array::make(size, Complex::zero())
  for index = 0; index < size; index = index + 1 {
    flipped[index] = input[index].conjugate()
  }
  let spectrum = fft(flipped)
  let scale = 1.0 / size.to_double()
  let out : Array[Complex] = Array::make(size, Complex::zero())
  for index = 0; index < size; index = index + 1 {
    out[index] = Complex::{
      re: spectrum[index].re * scale,
      im: -spectrum[index].im * scale,
    }
  }
  out
}

///|
/// Spectrum of a real valued signal, using the standard real-FFT packing.
///
/// Two real samples are packed into one complex sample
/// (`z[m] = x[2m] + i x[2m + 1]`), an `N / 2` point complex transform is
/// computed, and the result is unpacked into the `N / 2 + 1` non redundant
/// bins `X[0 .. N/2]`. That is half the work and half the memory of padding the
/// signal with zeros and calling [`fft`].
///
/// The transform length must be an even power of two. Odd lengths are padded
/// with a single zero, and a length that is even but not a power of two is
/// zero padded up to the next power of two, so the returned array always has
/// `padded_length / 2 + 1` entries. An empty input yields an empty spectrum.
/// The DC bin is real (`sum x`), the Nyquist bin is real as well, and bins
/// `1 .. N/2` are the unique half of the Hermitian symmetric spectrum.
pub fn real_fft(samples : Array[Double]) -> Array[Complex] {
  let count = samples.length()
  if count <= 0 {
    return []
  }
  let even_length = if (count & 1) == 0 { count } else { count + 1 }
  let size = next_power_of_two(even_length)
  let half = size / 2
  let packed : Array[Complex] = Array::make(half, Complex::zero())
  for index = 0; index < half; index = index + 1 {
    let real_index = index * 2
    let imag_index = real_index + 1
    let real = if real_index < count { samples[real_index] } else { 0.0 }
    let imag = if imag_index < count { samples[imag_index] } else { 0.0 }
    packed[index] = Complex::{ re: real, im: imag, }
  }
  let spectrum = fft(packed) catch { (_ : @audio.AudioError) => return [] }
  let bins = half + 1
  let out : Array[Complex] = Array::make(bins, Complex::zero())
  let step = 2.0 * @math.PI / size.to_double()
  for bin = 0; bin < half; bin = bin + 1 {
    let mirror = (half - bin) % half
    let current = spectrum[bin]
    let reflected = spectrum[mirror]
    let even = Complex::{
      re: (current.re + reflected.re) * 0.5,
      im: (current.im - reflected.im) * 0.5,
    }
    let odd = Complex::{
      re: (current.im + reflected.im) * 0.5,
      im: -(current.re - reflected.re) * 0.5,
    }
    let angle = step * bin.to_double()
    let weight = Complex::{ re: @math.cos(angle), im: -@math.sin(angle), }
    out[bin] = even.add(weight.mul(odd))
  }
  let dc = spectrum[0]
  out[half] = Complex::{ re: dc.re - dc.im, im: 0.0, }
  out
}

///|
/// Single sided magnitude spectrum, normalised by the transform length.
///
/// Bin `k` holds the peak amplitude of a sinusoid at that frequency (twice the
/// magnitude for the interior bins, so a full scale sine reads `1.0`), with
/// `|X[k]|` divided by `n`. The bin count follows the input: a full spectrum of
/// `N` complex bins yields `N / 2 + 1` magnitudes, while the `N / 2 + 1` bins
/// produced by [`real_fft`] pass through unchanged.
///
/// `n` overrides the transform length inferred from the input; pass it when
/// the spectrum was zero padded or cropped and the normalisation must stay
/// tied to the original length.
pub fn magnitude(spectrum : Array[Complex], n~ : Int32 = 0) -> Array[Double] {
  let count = spectrum.length()
  if count == 0 {
    return []
  }
  let length = if n > 0 {
    n
  } else if is_power_of_two(count) {
    count
  } else {
    (count - 1) * 2
  }
  if length <= 0 {
    return []
  }
  let limit = length / 2 + 1
  let bins = if count < limit { count } else { limit }
  let scale = 1.0 / length.to_double()
  let out : Array[Double] = Array::make(bins, 0.0)
  for bin = 0; bin < bins; bin = bin + 1 {
    let value = spectrum[bin].magnitude() * scale
    out[bin] = if bin == 0 || bin * 2 == length { value } else { 2.0 * value }
  }
  out
}

///|
/// One sided power spectrum in mean square units.
///
/// Each bin holds the power a sinusoid at that frequency would contribute:
/// `A^2 / 2` for a tone of peak amplitude `A`, and `|X[0]|^2` for the DC term,
/// so summing the bins approximates the mean square (the square of the RMS) of
/// the analysed block. A bin centred tone of amplitude `A` therefore puts
/// `A^2 / 2` into its bin and nothing elsewhere.
///
/// An optional window of any length is applied sample by sample; taps beyond
/// the end of the signal are ignored. Short signals are zero padded up to the
/// next power of two, so the result always has `padded_length / 2 + 1` bins.
pub fn power_spectrum(
  samples : Array[Double],
  window~ : Array[Double] = [],
) -> Array[Double] {
  let count = samples.length()
  if count <= 0 {
    return []
  }
  let taps = window.length()
  let weighted = taps > 0
  let mut gain = 0.0
  if weighted {
    let covered = taps.min(count)
    for index = 0; index < covered; index = index + 1 {
      gain = gain + window[index]
    }
  } else {
    gain = count.to_double()
  }
  if gain <= 0.0 {
    gain = 1.0
  }
  let size = next_power_of_two(count)
  let real : Array[Double] = Array::make(size, 0.0)
  for index = 0; index < count; index = index + 1 {
    real[index] = if weighted && index < taps {
      samples[index] * window[index]
    } else {
      samples[index]
    }
  }
  let spectrum = real_fft(real)
  let bins = spectrum.length()
  let out : Array[Double] = Array::make(bins, 0.0)
  for bin = 0; bin < bins; bin = bin + 1 {
    let amplitude = spectrum[bin].magnitude() / gain
    let edge = bin == 0 || bin == bins - 1
    let peak = if edge { amplitude } else { 2.0 * amplitude }
    out[bin] = if edge { peak * peak } else { peak * peak * 0.5 }
  }
  out
}
