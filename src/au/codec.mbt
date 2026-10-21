// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Sample encodings a `.au` file may use, after the numeric code in the header
/// has been resolved to a concrete byte layout.
///
/// Keeping the codec separate from the numeric code lets the decoder switch on
/// a small enumeration exactly once per file instead of per sample.
priv enum AuCodec {
  MuLaw
  Linear8
  Linear16
  Linear24
  Linear32
  Float32
  Float64
  ALaw
}

///|
/// Resolve a Sun/NeXT encoding code.
///
/// Codes 23, 24 and 25 are the G.721/G.722/G.723 ADPCM variants; they are
/// recognised but deliberately rejected with `Unsupported` so callers can
/// report them rather than silently decode noise.
fn AuCodec::resolve(encoding : Int32) -> AuCodec raise @audio.AudioError {
  match encoding {
    1 => MuLaw
    2 => Linear8
    3 => Linear16
    4 => Linear24
    5 => Linear32
    6 => Float32
    7 => Float64
    27 => ALaw
    23 | 24 | 25 =>
      raise @audio.Unsupported(
        "Sun ADPCM encoding \{encoding} is not supported",
      )
    _ => raise @audio.Unsupported("unknown Sun/NeXT .au encoding \{encoding}")
  }
}

///|
/// Codec written by the encoder for a requested sample format.
///
/// `U8` maps to Sun encoding 2 (signed 8 bit linear) because `.au` has no
/// unsigned 8 bit encoding; G.711 mu-law and A-law are decode-only here.
fn AuCodec::from_sample_format(format : @audio.SampleFormat) -> AuCodec {
  match format {
    @audio.U8 => Linear8
    @audio.I16 => Linear16
    @audio.I24 => Linear24
    @audio.I32 => Linear32
    @audio.F32 => Float32
    @audio.F64 => Float64
  }
}

///|
/// Numeric encoding code written into the header word at offset 12.
fn AuCodec::encoding(self : AuCodec) -> Int32 {
  match self {
    MuLaw => 1
    Linear8 => 2
    Linear16 => 3
    Linear24 => 4
    Linear32 => 5
    Float32 => 6
    Float64 => 7
    ALaw => 27
  }
}

///|
/// Bytes occupied by one sample of this codec.
fn AuCodec::width(self : AuCodec) -> Int32 {
  match self {
    MuLaw | Linear8 | ALaw => 1
    Linear16 => 2
    Linear24 => 3
    Linear32 | Float32 => 4
    Float64 => 8
  }
}

///|
/// Sample format reported to callers for this codec.
fn AuCodec::sample_format(self : AuCodec) -> @audio.SampleFormat {
  match self {
    MuLaw | ALaw => @audio.I16
    Linear8 => @audio.U8
    Linear16 => @audio.I16
    Linear24 => @audio.I24
    Linear32 => @audio.I32
    Float32 => @audio.F32
    Float64 => @audio.F64
  }
}

///|
/// Human readable codec name, stored in [`AuInfo::encoding_name`].
fn AuCodec::name(self : AuCodec) -> String {
  match self {
    MuLaw => "mu-law"
    Linear8 => "linear-8"
    Linear16 => "linear-16"
    Linear24 => "linear-24"
    Linear32 => "linear-32"
    Float32 => "float-32"
    Float64 => "float-64"
    ALaw => "a-law"
  }
}
