// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Interpolation kernel used by [`resample`].
///
/// The three variants trade quality for speed. `Linear` is the classic
/// two-point interpolator; `Cubic` is a four-point Catmull-Rom spline, which is
/// still cheap but keeps the passband flatter; `Sinc` is a windowed-sinc
/// (Blackman-Harris) lowpass and is the only variant that also filters when
/// downsampling, at a cost of `2 * taps` multiply-accumulates per output sample.
pub(all) enum ResampleQuality {
  /// Two point linear interpolation; fastest, mildly dull at high frequencies.
  Linear
  /// Four point Catmull-Rom cubic interpolation.
  Cubic
  /// Windowed-sinc interpolation with a Blackman-Harris window.
  Sinc
}
