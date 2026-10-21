// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Shape of the taper applied to a block of samples before a Fourier
/// transform.
///
/// Every variant is the *symmetric* ("whole sample") form of its family: tap
/// `k` of an `N` tap window sits at `k / (N - 1)` of the window period, so the
/// first and last taps are equal (`w[0] == w[N - 1]`). The *periodic*
/// ("DFT even") form used by overlap-add resynthesis is obtained by asking for
/// `N + 1` taps and dropping the last one; the two differ by `O(1 / N)`.
///
/// Each window tapers from a broad main lobe with high leakage (rectangular)
/// towards narrow sidelobes at the cost of frequency resolution
/// (Blackman-Harris, Kaiser).
pub(all) enum WindowKind {
  /// Every tap is equal, giving the sharpest main lobe and the worst sidelobe
  /// leakage (about -13 dB).
  Rectangular
  /// Raised cosine `0.5 - 0.5 cos(2 pi k / (N - 1))`; both end taps are zero.
  Hann
  /// Raised cosine on a 0.08 pedestal, `0.54 - 0.46 cos(2 pi k / (N - 1))`;
  /// the end taps are 0.08 of the peak so the seam is continuous.
  Hamming
  /// Three term cosine `0.42 - 0.5 cos(..) + 0.08 cos(2 ..)`; sidelobes about
  /// -58 dB and both end taps are zero.
  Blackman
  /// Four term minimum sidelobe cosine (about -92 dB), the default choice when
  /// a clean spectrum matters more than resolution.
  BlackmanHarris
  /// Kaiser-Bessel window, tunable through `beta`: larger values trade main
  /// lobe width for lower sidelobes (`beta = 8.6` approximates a
  /// Blackman-Harris style taper).
  Kaiser
}

///|
/// Canonical lower case name of a window, suitable for logs and CSV output.
pub fn WindowKind::to_name(self : WindowKind) -> String {
  match self {
    Rectangular => "rectangular"
    Hann => "hann"
    Hamming => "hamming"
    Blackman => "blackman"
    BlackmanHarris => "blackman-harris"
    Kaiser => "kaiser"
  }
}

///|
/// Modified Bessel function of the first kind, order zero.
///
/// Evaluated through its power series
/// `I0(x) = sum_k (x^2 / 4)^k / (k!)^2`, which converges in a dozen terms for
/// the `beta <= 20` values a Kaiser window uses. The loop stops once a term is
/// negligible relative to the running sum, so the result is accurate to a few
/// units in the last place.
fn bessel_i0(x : Double) -> Double {
  let quarter = x * x * 0.25
  let mut term = 1.0
  let mut sum = 1.0
  let mut order = 1
  while order <= 64 {
    let k = order.to_double()
    term = term * quarter / (k * k)
    sum = sum + term
    if term.abs() <= sum.abs() * 1.0e-17 {
      break
    }
    order = order + 1
  }
  sum
}

///|
/// Taps of the symmetric window `self` sampled at `size` points.
///
/// The taps are normalised so they sum to exactly `1.0` (unity DC gain). That
/// makes the weights directly usable as a normalised analysis kernel and lets
/// the FFT helpers recover a signal's amplitude by dividing by the tap sum, no
/// matter which window was applied. As a consequence the taps are *not* the
/// textbook peak-normalised coefficients: multiply by `size` for the classic
/// form, whose sum is roughly `size / 2`.
///
/// `beta` only affects [`Kaiser`](WindowKind::Kaiser); other windows ignore it.
/// A `size` of zero or less yields an empty array and a `size` of one yields a
/// single tap of `1.0`, so the result is always usable.
pub fn WindowKind::coefficients(
  self : WindowKind,
  size : Int32,
  beta~ : Double = 8.6,
) -> Array[Double] {
  let count = size
  if count <= 0 {
    return []
  }
  let taps : Array[Double] = Array::make(count, 1.0)
  if count == 1 {
    return taps
  }
  let span = (count - 1).to_double()
  let step = 2.0 * @math.PI / span
  match self {
    Rectangular => ()
    Hann =>
      for index = 0; index < count; index = index + 1 {
        let angle = step * index.to_double()
        taps[index] = 0.5 - 0.5 * @math.cos(angle)
      }
    Hamming =>
      for index = 0; index < count; index = index + 1 {
        let angle = step * index.to_double()
        taps[index] = 0.54 - 0.46 * @math.cos(angle)
      }
    Blackman =>
      for index = 0; index < count; index = index + 1 {
        let angle = step * index.to_double()
        taps[index] = 0.42 -
          0.5 * @math.cos(angle) +
          0.08 * @math.cos(2.0 * angle)
      }
    BlackmanHarris =>
      for index = 0; index < count; index = index + 1 {
        let angle = step * index.to_double()
        taps[index] = 0.35875 -
          0.48829 * @math.cos(angle) +
          0.14128 * @math.cos(2.0 * angle) -
          0.01168 * @math.cos(3.0 * angle)
      }
    Kaiser => {
      let amount = beta.abs()
      let reference = bessel_i0(amount)
      for index = 0; index < count; index = index + 1 {
        let ratio = 2.0 * index.to_double() / span - 1.0
        let radius = (1.0 - ratio * ratio).max(0.0).sqrt()
        taps[index] = bessel_i0(amount * radius) / reference
      }
    }
  }
  let mut total = 0.0
  for tap in taps {
    total = total + tap
  }
  if total > 0.0 {
    for index = 0; index < count; index = index + 1 {
      taps[index] = taps[index] / total
    }
  }
  taps
}
