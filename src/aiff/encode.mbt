// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Encode an [`@audio.AudioBuffer`] as an AIFF or AIFC file.
///
/// Integer formats produce a plain `AIFF` file holding big-endian PCM; the
/// default is signed 16 bit. [`@audio.F32`] and [`@audio.F64`] produce an
/// `AIFC` file with the `fl32` / `fl64` compression type and an `FVER` chunk,
/// because plain AIFF has no way to describe floating point samples.
pub fn encode(
  audio : @audio.AudioBuffer,
  format~ : @audio.SampleFormat = @audio.I16,
) -> Bytes raise @audio.AudioError {
  encode_with_metadata(audio, format, [])
}

///|
/// Encode a buffer and attach text metadata chunks.
///
/// Metadata keys are matched against the AIFF text chunks: `"NAME"`, `"AUTH"`,
/// `"(c) "` and `"ANNO"` (case insensitive) are written as the corresponding
/// chunk. Any other key is written as an `ANNO` annotation whose text is
/// `"key: value"`, so a foreign key still reaches other tools without
/// pretending to be a standard chunk. `MARK`, `INST` and `COMT` are read but
/// never written: their binary layouts carry information a
/// `(String, String)` map cannot express.
///
/// Values are stored as UTF-8 and padded with a NUL byte when their length is
/// odd, as the AIFF chunk rules require.
pub fn encode_with_metadata(
  audio : @audio.AudioBuffer,
  format : @audio.SampleFormat,
  metadata : Array[(String, String)],
) -> Bytes raise @audio.AudioError {
  if audio.channels <= 0 {
    raise @audio.OutOfRange("cannot encode a buffer with no channels")
  }
  if audio.sample_rate <= 0 {
    raise @audio.OutOfRange("cannot encode a buffer with no sample rate")
  }
  let bits = format.bits()
  let width = bits / 8
  let is_aifc = format.is_float()
  let frames = audio.frames()
  let sample_count = frames * audio.channels
  let sample_bytes = sample_count * width
  let text_chunks = build_text_chunks(metadata)
  let name = compression_name(format)
  let comm_payload = if is_aifc { 18 + 4 + pstring_size(name) } else { 18 }
  let mut body = 4 +
    8 +
    comm_payload +
    8 +
    8 +
    sample_bytes +
    (sample_bytes & 1)
  if is_aifc {
    body = body + 8 + 4
  }
  for chunk in text_chunks {
    let size = chunk.1.length()
    body = body + 8 + size + (size & 1)
  }
  let buffer = @buffer.Buffer::Buffer(size_hint=8 + body)
  buffer.write_string_utf8("FORM")
  write_u32be(buffer, body.to_int64())
  buffer.write_string_utf8(if is_aifc { "AIFC" } else { "AIFF" })
  if is_aifc {
    // AIFC requires the format version chunk to come first.
    buffer.write_string_utf8("FVER")
    write_u32be(buffer, 4L)
    write_u32be(buffer, 0xA2805140L)
  }
  buffer.write_string_utf8("COMM")
  write_u32be(buffer, comm_payload.to_int64())
  write_u16be(buffer, audio.channels)
  write_u32be(buffer, frames.to_int64())
  write_u16be(buffer, bits)
  buffer.write_bytes(double_to_ext_float(audio.sample_rate.to_double()))
  if is_aifc {
    buffer.write_string_utf8(compression_type(format))
    buffer.write_byte(name.length().to_byte())
    buffer.write_string_utf8(name)
    if (1 + name.length()) % 2 == 1 {
      buffer.write_byte(0)
    }
  }
  for chunk in text_chunks {
    buffer.write_string_utf8(chunk.0)
    write_u32be(buffer, chunk.1.length().to_int64())
    buffer.write_bytes(chunk.1)
    if chunk.1.length() % 2 == 1 {
      buffer.write_byte(0)
    }
  }
  buffer.write_string_utf8("SSND")
  write_u32be(buffer, (8 + sample_bytes).to_int64())
  write_u32be(buffer, 0L)
  write_u32be(buffer, 0L)
  for index = 0; index < sample_count; index = index + 1 {
    write_sample(buffer, audio.data[index], format)
  }
  if sample_bytes % 2 == 1 {
    buffer.write_byte(0)
  }
  buffer.to_bytes()
}

///|
/// AIFC compression type written for `format`.
fn compression_type(format : @audio.SampleFormat) -> String {
  match format {
    @audio.F32 => "fl32"
    @audio.F64 => "fl64"
    _ => "NONE"
  }
}

///|
/// AIFC `compressionName` pstring written for `format`.
fn compression_name(format : @audio.SampleFormat) -> String {
  match format {
    @audio.F32 => "32-bit floating point"
    @audio.F64 => "64-bit floating point"
    _ => ""
  }
}

///|
/// Size of a pstring holding `text`, including its length byte and the pad
/// byte that keeps the following chunk aligned.
fn pstring_size(text : String) -> Int32 {
  let raw = 1 + text.length()
  raw + (raw & 1)
}

///|
/// Build the `(chunk id, UTF-8 payload)` pairs for the metadata map.
fn build_text_chunks(
  metadata : Array[(String, String)],
) -> Array[(String, Bytes)] {
  let chunks : Array[(String, Bytes)] = []
  for entry in metadata {
    let (id, text) = match text_chunk_id(entry.0) {
      Some(id) => (id, entry.1)
      None => ("ANNO", entry.0 + ": " + entry.1)
    }
    chunks.push((id, utf8_bytes(text)))
  }
  chunks
}

///|
/// Canonical text chunk id for a metadata key, or `None` for a foreign key.
fn text_chunk_id(key : String) -> String? {
  let upper = key.to_upper()
  if upper == "NAME" {
    Some("NAME")
  } else if upper == "AUTH" {
    Some("AUTH")
  } else if upper == "ANNO" {
    Some("ANNO")
  } else if upper == "(C) " || upper == "(C)" {
    Some("(c) ")
  } else {
    None
  }
}

///|
/// Encode `text` as UTF-8 bytes.
fn utf8_bytes(text : String) -> Bytes {
  let buffer = @buffer.Buffer::Buffer(size_hint=text.length())
  buffer.write_string_utf8(text)
  buffer.to_bytes()
}

///|
/// Write one sample in the requested encoding, big-endian.
fn write_sample(
  buffer : @buffer.Buffer,
  sample : Double,
  format : @audio.SampleFormat,
) -> Unit {
  match format {
    // AIFF stores 8 bit samples as signed two's complement, so the unsigned
    // offset-binary code is shifted back into the signed range.
    @audio.U8 =>
      buffer.write_byte((@audio.quantize(sample, @audio.U8) - 128).to_byte())
    @audio.I16 => {
      let code = @audio.quantize(sample, @audio.I16)
      buffer.write_byte(((code >> 8) & 0xFF).to_byte())
      buffer.write_byte((code & 0xFF).to_byte())
    }
    @audio.I24 => {
      let code = @audio.quantize(sample, @audio.I24)
      buffer.write_byte(((code >> 16) & 0xFF).to_byte())
      buffer.write_byte(((code >> 8) & 0xFF).to_byte())
      buffer.write_byte((code & 0xFF).to_byte())
    }
    @audio.I32 => {
      let code = @audio.quantize(sample, @audio.I32)
      for shift = 24; shift >= 0; shift = shift - 8 {
        buffer.write_byte(((code >> shift) & 0xFF).to_byte())
      }
    }
    @audio.F32 => {
      let bits = @audio.double_to_f32_bits(sample)
      for shift = 24; shift >= 0; shift = shift - 8 {
        buffer.write_byte(((bits >> shift) & 0xFFL).to_byte())
      }
    }
    @audio.F64 => {
      let bits = sample.reinterpret_as_int64()
      for shift = 56; shift >= 0; shift = shift - 8 {
        buffer.write_byte(((bits >> shift) & 0xFFL).to_byte())
      }
    }
  }
}

///|
/// Write a big endian 16 bit value.
fn write_u16be(buffer : @buffer.Buffer, value : Int32) -> Unit {
  buffer.write_byte(((value >> 8) & 0xFF).to_byte())
  buffer.write_byte((value & 0xFF).to_byte())
}

///|
/// Write a big endian 32 bit value.
fn write_u32be(buffer : @buffer.Buffer, value : Int64) -> Unit {
  buffer.write_byte(((value >> 24) & 0xFFL).to_byte())
  buffer.write_byte(((value >> 16) & 0xFFL).to_byte())
  buffer.write_byte(((value >> 8) & 0xFFL).to_byte())
  buffer.write_byte((value & 0xFFL).to_byte())
}
