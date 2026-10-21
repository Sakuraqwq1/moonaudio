// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Encode an [`@audio.AudioBuffer`] as a Sun/NeXT `.au` file.
///
/// Samples are stored big endian and the header always uses the minimal 24 byte
/// form (no annotation). `format` picks the on-disk encoding: `U8` becomes 8 bit
/// linear PCM (Sun encoding 2, which — unlike WAV's `U8` — is *signed*), `I16`,
/// `I24` and `I32` become linear PCM and `F32`/`F64` become IEEE float. G.711
/// mu-law and A-law are decode-only for this encoder.
pub fn encode(
  audio : @audio.AudioBuffer,
  format~ : @audio.SampleFormat = @audio.I16,
) -> Bytes raise @audio.AudioError {
  encode_with_annotation(audio, format, "")
}

///|
/// Encode a buffer and store `annotation` between the 24 byte header and the
/// sample data.
///
/// The data offset in the header grows to `24 + annotation byte length`, which
/// is exactly the layout `sox`, `ffmpeg` and Sun's own tools accept. The
/// annotation is written as UTF-8; a reader that expects ASCII still sees the
/// same bytes for ASCII text.
pub fn encode_with_annotation(
  audio : @audio.AudioBuffer,
  format : @audio.SampleFormat,
  annotation : String,
) -> Bytes raise @audio.AudioError {
  if audio.channels <= 0 {
    raise @audio.OutOfRange("cannot encode a buffer with no channels")
  }
  if audio.sample_rate <= 0 {
    raise @audio.OutOfRange("cannot encode a buffer with no sample rate")
  }
  let codec = AuCodec::from_sample_format(format)
  let width = codec.width()
  let data_len = audio.data.length() * width
  let note = @buffer.Buffer::Buffer(size_hint=annotation.length() + 1)
  note.write_string_utf8(annotation)
  let note_bytes = note.to_bytes()
  let data_offset = au_header_size + note_bytes.length()
  let out = @buffer.Buffer::Buffer(size_hint=data_offset + data_len + 8)
  out.write_string_utf8(".snd")
  write_u32be(out, data_offset.to_int64())
  write_u32be(out, data_len.to_int64())
  write_u32be(out, codec.encoding().to_int64())
  write_u32be(out, audio.sample_rate.to_int64())
  write_u32be(out, audio.channels.to_int64())
  out.write_bytes(note_bytes)
  for sample in audio.data {
    write_sample(out, sample, codec)
  }
  out.to_bytes()
}

///|
/// Write one sample in the requested codec, big endian.
fn write_sample(
  buffer : @buffer.Buffer,
  sample : Double,
  codec : AuCodec,
) -> Unit {
  match codec {
    MuLaw => buffer.write_byte(@audio.mulaw_encode(sample).to_byte())
    Linear8 =>
      buffer.write_byte((@audio.quantize(sample, @audio.I16) >> 8).to_byte())
    Linear16 => {
      let code = @audio.quantize(sample, @audio.I16)
      buffer.write_byte(((code >> 8) & 0xFF).to_byte())
      buffer.write_byte((code & 0xFF).to_byte())
    }
    Linear24 => {
      let code = @audio.quantize(sample, @audio.I24)
      buffer.write_byte(((code >> 16) & 0xFF).to_byte())
      buffer.write_byte(((code >> 8) & 0xFF).to_byte())
      buffer.write_byte((code & 0xFF).to_byte())
    }
    Linear32 =>
      write_u32be(buffer, @audio.quantize(sample, @audio.I32).to_int64())
    Float32 => write_u32be(buffer, @audio.double_to_f32_bits(sample))
    Float64 => write_u64be(buffer, sample.reinterpret_as_int64())
    ALaw => buffer.write_byte(@audio.alaw_encode(sample).to_byte())
  }
}

///|
/// Write a big endian 32 bit value.
fn write_u32be(buffer : @buffer.Buffer, value : Int64) -> Unit {
  buffer.write_byte(((value >> 24) & 0xFFL).to_byte())
  buffer.write_byte(((value >> 16) & 0xFFL).to_byte())
  buffer.write_byte(((value >> 8) & 0xFFL).to_byte())
  buffer.write_byte((value & 0xFFL).to_byte())
}

///|
/// Write a big endian 64 bit value.
fn write_u64be(buffer : @buffer.Buffer, value : Int64) -> Unit {
  for shift = 56; shift >= 0; shift = shift - 8 {
    buffer.write_byte(((value >> shift) & 0xFFL).to_byte())
  }
}
