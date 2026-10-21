// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Minimal MSB-first bit writer used to synthesise FLAC streams in tests.
///
/// It mirrors the bit order of the specification but is written independently
/// of the decoder, so a roundtrip through `decode` exercises the reader from a
/// second implementation of the same layout.
struct BitWriter {
  bytes : Array[Byte]
  mut bit : Int32
}

///|
/// A fresh, empty bit writer.
fn BitWriter::new() -> BitWriter {
  BitWriter::{ bytes: [], bit: 0 }
}
///|
/// ASCII bytes for a text literal, avoiding the deprecated String::to_bytes.
fn ascii_bytes(text : String) -> Bytes {
  let writer = BitWriter::new()
  for c in text {
    writer.write_bits(c.to_int(), 8)
  }
  writer.to_bytes()
}

///|
/// Decode ytes and return the audio with the decoder's message (if any).
fn decode_or_message(bytes : Bytes) -> (@audio.AudioBuffer, String) {
  let mut message = "ok"
  let audio = decode(bytes) catch { (error : @audio.AudioError) => {
    message = error.message()
    @audio.AudioBuffer::new(0, 1)
  } }
  (audio, message)
}

///|
/// Decode ytes and report the error kind, or "ok".
fn decode_error_kind(bytes : Bytes) -> String {
  let mut kind = "ok"
  let _ = decode(bytes) catch { (error : @audio.AudioError) => {
    kind = error.kind()
    @audio.AudioBuffer::new(0, 1)
  } }
  kind
}


///|
/// Append one bit.
fn BitWriter::write_bit(self : BitWriter, value : Int32) -> Unit {
  if self.bit % 8 == 0 {
    self.bytes.push(0)
  }
  if value != 0 {
    let index = self.bytes.length() - 1
    self.bytes[index] = (self.bytes[index].to_int() | (1 << (7 - self.bit % 8))).to_byte()
  }
  self.bit = self.bit + 1
}

///|
/// Append `count` bits of `value`, most significant bit first.
fn BitWriter::write_bits(
  self : BitWriter,
  value : Int32,
  count : Int32,
) -> Unit {
  for index = count - 1; index >= 0; index = index - 1 {
    self.write_bit((value >> index) & 1)
  }
}

///|
/// Append `count` bits of a two's complement signed value.
fn BitWriter::write_signed(
  self : BitWriter,
  value : Int32,
  count : Int32,
) -> Unit {
  self.write_bits(value & ((1 << count) - 1), count)
}

///|
/// Append `zeros` zero bits followed by a one bit.
fn BitWriter::write_unary(self : BitWriter, zeros : Int32) -> Unit {
  for _index = 0; _index < zeros; _index = _index + 1 {
    self.write_bit(0)
  }
  self.write_bit(1)
}

///|
/// Pad with zero bits until the next byte boundary.
fn BitWriter::align(self : BitWriter) -> Unit {
  while self.bit % 8 != 0 {
    self.write_bit(0)
  }
}

///|
/// Byte offset of the next write.
fn BitWriter::byte_position(self : BitWriter) -> Int32 {
  self.bytes.length()
}

///|
/// Append a raw byte sequence.
fn BitWriter::write_raw(self : BitWriter, data : Bytes) -> Unit {
  for index = 0; index < data.length(); index = index + 1 {
    self.write_bits(data.at(index).to_int(), 8)
  }
}

///|
/// Append a little endian 32 bit value.
fn BitWriter::write_u32le(self : BitWriter, value : Int64) -> Unit {
  for shift = 0; shift <= 24; shift = shift + 8 {
    self.write_bits(((value >> shift) & 0xFFL).to_int(), 8)
  }
}

///|
/// Append a big endian 24 bit value.
fn BitWriter::write_u24be(self : BitWriter, value : Int32) -> Unit {
  self.write_bits((value >> 16) & 0xFF, 8)
  self.write_bits((value >> 8) & 0xFF, 8)
  self.write_bits(value & 0xFF, 8)
}

///|
/// Finish the stream and return its bytes.
fn BitWriter::to_bytes(self : BitWriter) -> Bytes {
  Bytes::from_array(self.bytes[:])
}

///|
/// FLAC's UTF-8 style number encoding (UTF-8 extended to 36 bits).
fn write_utf8_number(writer : BitWriter, value : Int64) -> Unit {
  if value < 0x80L {
    writer.write_bits(value.to_int(), 8)
  } else if value < 0x800L {
    writer.write_bits(0xC0 | (value >> 6).to_int(), 8)
    writer.write_bits(0x80 | (value & 0x3FL).to_int(), 8)
  } else if value < 0x10000L {
    writer.write_bits(0xE0 | (value >> 12).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 6) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | (value & 0x3FL).to_int(), 8)
  } else if value < 0x200000L {
    writer.write_bits(0xF0 | (value >> 18).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 12) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 6) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | (value & 0x3FL).to_int(), 8)
  } else if value < 0x4000000L {
    writer.write_bits(0xF8 | (value >> 24).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 18) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 12) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 6) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | (value & 0x3FL).to_int(), 8)
  } else if value < 0x80000000L {
    writer.write_bits(0xFC | (value >> 30).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 24) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 18) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 12) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | ((value >> 6) & 0x3FL).to_int(), 8)
    writer.write_bits(0x80 | (value & 0x3FL).to_int(), 8)
  } else {
    writer.write_bits(0xFE, 8)
    for shift = 30; shift >= 0; shift = shift - 6 {
      writer.write_bits(0x80 | ((value >> shift) & 0x3FL).to_int(), 8)
    }
  }
}

///|
/// Subframe flavour used by the synthetic stream builder.
enum SubKind {
  Constant
  Verbatim
  Fixed(Int32)
  Lpc(Int32, Array[Int32], Int32)
}

///|
/// Compute the residuals of a fixed predictor so that the decoder reconstructs
/// `samples` exactly.
fn fixed_residuals(samples : Array[Int32], order : Int32) -> Array[Int32] {
  let residual : Array[Int32] = []
  for index = order; index < samples.length(); index = index + 1 {
    let prediction = match order {
      0 => 0
      1 => samples[index - 1]
      2 => 2 * samples[index - 1] - samples[index - 2]
      3 =>
        3 * samples[index - 1] - 3 * samples[index - 2] + samples[index - 3]
      4 =>
        4 * samples[index - 1] -
        6 * samples[index - 2] +
        4 * samples[index - 3] -
        samples[index - 4]
      _ => 0
    }
    residual.push(samples[index] - prediction)
  }
  residual
}

///|
/// Compute LPC residuals for the given quantised coefficients and shift.
fn lpc_residuals(
  samples : Array[Int32],
  coefficients : Array[Int32],
  shift : Int32,
) -> Array[Int32] {
  let order = coefficients.length()
  let residual : Array[Int32] = []
  for index = order; index < samples.length(); index = index + 1 {
    let mut sum = 0L
    for tap = 0; tap < order; tap = tap + 1 {
      sum = sum +
        coefficients[tap].to_int64() * samples[index - 1 - tap].to_int64()
    }
    residual.push(samples[index] - (sum >> shift).to_int())
  }
  residual
}

///|
/// Emit one Rice-coded residual block (single partition, method 0).
fn write_rice(writer : BitWriter, residuals : Array[Int32], parameter : Int32) -> Unit {
  for value in residuals {
    let zigzag = if value < 0 { ((-value) << 1) - 1 } else { value << 1 }
    let quotient = if parameter == 0 { zigzag } else { zigzag >> parameter }
    let remainder = if parameter == 0 { 0 } else { zigzag & ((1 << parameter) - 1) }
    writer.write_unary(quotient)
    if parameter > 0 {
      writer.write_bits(remainder, parameter)
    }
  }
}

///|
/// Emit a subframe header and body for `samples`.
fn write_subframe(
  writer : BitWriter,
  samples : Array[Int32],
  bps : Int32,
  kind : SubKind,
) -> Unit {
  writer.write_bit(0)
  match kind {
    Constant => {
      writer.write_bits(0, 6)
      writer.write_bit(0)
      writer.write_signed(samples[0], bps)
    }
    Verbatim => {
      writer.write_bits(1, 6)
      writer.write_bit(0)
      for sample in samples {
        writer.write_signed(sample, bps)
      }
    }
    Fixed(order) => {
      writer.write_bits(8 + order, 6)
      writer.write_bit(0)
      for index = 0; index < order; index = index + 1 {
        writer.write_signed(samples[index], bps)
      }
      let residual = fixed_residuals(samples, order)
      writer.write_bits(0, 2)
      writer.write_bits(0, 4)
      let parameter = 4
      writer.write_bits(parameter, 4)
      write_rice(writer, residual, parameter)
    }
    Lpc(order, coefficients, shift) => {
      writer.write_bits(31 + order, 6)
      writer.write_bit(0)
      for index = 0; index < order; index = index + 1 {
        writer.write_signed(samples[index], bps)
      }
      writer.write_bits(3, 4)
      writer.write_signed(shift, 5)
      for coefficient in coefficients {
        writer.write_signed(coefficient, 4)
      }
      let residual = lpc_residuals(samples, coefficients, shift)
      writer.write_bits(0, 2)
      writer.write_bits(0, 4)
      let parameter = 6
      writer.write_bits(parameter, 4)
      write_rice(writer, residual, parameter)
    }
  }
}

///|
/// Emit a fixed-predictor subframe whose residual uses `partition_order`
/// Rice partitions and, for the first partition, the escape code.
fn write_fixed_partitioned(
  writer : BitWriter,
  samples : Array[Int32],
  bps : Int32,
  order : Int32,
  partition_order : Int32,
  escape_first? : Bool = false,
) -> Unit {
  writer.write_bit(0)
  writer.write_bits(8 + order, 6)
  writer.write_bit(0)
  for index = 0; index < order; index = index + 1 {
    writer.write_signed(samples[index], bps)
  }
  let residual = fixed_residuals(samples, order)
  let block_size = samples.length()
  writer.write_bits(0, 2)
  writer.write_bits(partition_order, 4)
  let partitions = 1 << partition_order
  let part_size = block_size >> partition_order
  let mut cursor = 0
  for partition = 0; partition < partitions; partition = partition + 1 {
    let count = if partition == 0 {
      part_size - order
    } else {
      part_size
    }
    let escaped = escape_first && partition == 0
    if escaped {
      writer.write_bits(0x0F, 4)
      writer.write_bits(16, 5)
      for _index = 0; _index < count; _index = _index + 1 {
        writer.write_signed(residual[cursor], 16)
        cursor = cursor + 1
      }
    } else {
      let parameter = 6
      writer.write_bits(parameter, 4)
      for _index = 0; _index < count; _index = _index + 1 {
        let value = residual[cursor]
        let zigzag = if value < 0 {
          ((-value) << 1) - 1
        } else {
          value << 1
        }
        writer.write_unary(zigzag >> parameter)
        writer.write_bits(zigzag & ((1 << parameter) - 1), parameter)
        cursor = cursor + 1
      }
    }
  }
}

///|
/// Emit a complete frame whose subframes follow `kinds`.
fn write_frame(
  writer : BitWriter,
  channels : Array[Array[Int32]],
  bps : Int32,
  sample_rate : Int32,
  blocking_strategy : Int32,
  frame_number : Int64,
  kinds : Array[SubKind],
  side_extra_bits? : Int32 = 0,
) -> Unit {
  let _ = sample_rate
  let block_size = channels[0].length()
  let channel_assignment = match channels.length() {
    1 => 0
    2 => 10
    8 => 7
    _ => channels.length() - 1
  }
  let start = writer.byte_position()
  writer.write_bits(0x3FFE, 14)
  writer.write_bit(0)
  writer.write_bit(blocking_strategy)
  writer.write_bits(7, 4)
  writer.write_bits(0, 4)
  writer.write_bits(channel_assignment, 4)
  writer.write_bits(0, 3)
  writer.write_bit(0)
  write_utf8_number(writer, frame_number)
  writer.write_bits(block_size - 1, 16)
  writer.align()
  let header_end = writer.byte_position()
  let header_crc = crc8(
    writer.to_bytes(),
    start,
    header_end,
  )
  writer.write_bits(header_crc, 8)
  for channel = 0; channel < channels.length(); channel = channel + 1 {
    let mut channel_bps = bps
    if channel_assignment == 9 && channel == 0 {
      channel_bps = bps + 1
    } else if (channel_assignment == 8 || channel_assignment == 10) &&
      channel == 1 {
      channel_bps = bps + side_extra_bits
    }
    write_subframe(writer, channels[channel], channel_bps, kinds[channel])
  }
  writer.align()
  let end = writer.byte_position()
  let frame_crc = crc16(writer.to_bytes(), start, end)
  writer.write_bits((frame_crc >> 8) & 0xFF, 8)
  writer.write_bits(frame_crc & 0xFF, 8)
}

///|
/// Emit a `STREAMINFO` metadata block.
fn write_stream_info(
  writer : BitWriter,
  sample_rate : Int32,
  channels : Int32,
  bps : Int32,
  total_samples : Int64,
  block_size : Int32,
) -> Unit {
  writer.write_bits(0x00, 8)
  writer.write_u24be(34)
  writer.write_bits(block_size >> 8, 8)
  writer.write_bits(block_size & 0xFF, 8)
  writer.write_bits(block_size >> 8, 8)
  writer.write_bits(block_size & 0xFF, 8)
  writer.write_u24be(0)
  writer.write_u24be(0)
  writer.write_bits(sample_rate, 20)
  writer.write_bits(channels - 1, 3)
  writer.write_bits(bps - 1, 5)
  writer.write_bits((total_samples >> 32).to_int(), 4)
  writer.write_bits((total_samples & 0xFFFFFFFFL).to_int(), 32)
  for _index = 0; _index < 16; _index = _index + 1 {
    writer.write_bits(0, 8)
  }
}

///|
/// Assemble a FLAC stream from per-frame sample blocks.
fn make_flac(
  sample_rate : Int32,
  channels : Int32,
  bps : Int32,
  total_samples : Int64,
  frames : Array[Array[Array[Int32]]],
  kinds : Array[Array[SubKind]],
  side_extra_bits? : Int32 = 0,
) -> Bytes {
  let writer = BitWriter::new()
  writer.write_bits(0x66, 8)
  writer.write_bits(0x4C, 8)
  writer.write_bits(0x61, 8)
  writer.write_bits(0x43, 8)
  write_stream_info(
    writer,
    sample_rate,
    channels,
    bps,
    total_samples,
    frames[0][0].length(),
  )
  // Mark STREAMINFO as the last metadata block.
  // The header byte written above is at offset 4.
  let bytes = writer.to_bytes()
  let patched : Array[Byte] = []
  for index = 0; index < bytes.length(); index = index + 1 {
    patched.push(
      if index == 4 {
        (bytes.at(index).to_int() | 0x80).to_byte()
      } else {
        bytes.at(index)
      },
    )
  }
  let out = BitWriter::new()
  out.write_raw(Bytes::from_array(patched[:]))
  for frame_index = 0; frame_index < frames.length(); frame_index = frame_index + 1 {
    write_frame(
      out,
      frames[frame_index],
      bps,
      sample_rate,
      0,
      frame_index.to_int64(),
      kinds[frame_index],
      side_extra_bits~,
    )
  }
  out.to_bytes()
}

///|
/// Deterministic pseudo random integer sequence in `[-range, range]`.
fn pseudo(seed : Int32, count : Int32, range : Int32) -> Array[Int32] {
  let out : Array[Int32] = []
  let mut state = seed
  for _index = 0; _index < count; _index = _index + 1 {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF
    let value = state % (range * 2 + 1) - range
    out.push(value)
  }
  out
}

///|
test "crc checksums match their published check values" {
  let data = ascii_bytes("123456789")
  let text = @utf8.decode_lossy(data[:])
  assert_eq(text, "123456789")
  assert_eq(crc8(data, 0, data.length()), 0xF4)
  assert_eq(crc16(data, 0, data.length()), 0xFEE8)
  // Incremental CRC-16 agrees with the one shot version.
  let incremental = Crc16::new()
  for index = 0; index < data.length(); index = index + 1 {
    incremental.update(data.at(index).to_int())
  }
  assert_eq(incremental.value(), 0xFEE8)
}

///|
test "bit writer and reader roundtrip" {
  let writer = BitWriter::new()
  writer.write_bits(0x2A, 6)
  writer.write_bits(0x1FFFF, 17)
  writer.write_signed(-3, 5)
  writer.write_unary(4)
  writer.write_bits(0, 3)
  writer.align()
  let bytes = writer.to_bytes()
  let reader = BitReader::new(bytes)
  assert_eq(reader.read_bits(6), 0x2A)
  assert_eq(reader.read_bits(17), 0x1FFFF)
  assert_eq(reader.read_signed(5), -3)
  assert_eq(reader.read_unary(), 4)
  assert_eq(reader.read_bits(3), 0)
  let empty = BitReader::new(Bytes::make(0, 0))
  let mut exhausted = "ok"
  let _ = empty.read_bit() catch { (error : @audio.AudioError) => {
    exhausted = error.kind()
    0
  } }
  assert_eq(exhausted, "truncated")
}

///|
test "utf8 coded numbers roundtrip" {
  let values : Array[Int64] = [0L, 1L, 127L, 128L, 4095L, 4096L, 100000L, 2097151L, 2097152L, 3000000000L]
  for value in values {
    let writer = BitWriter::new()
    write_utf8_number(writer, value)
    writer.align()
    let reader = BitReader::new(writer.to_bytes())
    assert_eq(reader.read_utf8_uint(), value)
  }
}

///|
test "stream info is parsed" {
  let samples = pseudo(7, 64, 1000)
  let stream = make_flac(48000, 1, 16, 64L, [[samples]], [[SubKind::Verbatim]])
  let info = parse_info(stream) catch { (_ : @audio.AudioError) => panic() }
  assert_eq(info.sample_rate, 48000)
  assert_eq(info.channels, 1)
  assert_eq(info.bits_per_sample, 16)
  assert_eq(info.total_samples, 64L)
  assert_eq(info.blocks.length(), 1)
  assert_true(info.describe().contains("48000 Hz"))
  assert_true(is_flac(stream))
}

///|
test "verbatim subframes decode exactly" {
  let samples = pseudo(11, 32, 2000)
  let stream = make_flac(44100, 1, 16, 32L, [[samples]], [[SubKind::Verbatim]])
  let (audio, decode_message) = decode_or_message(stream)
  assert_eq(decode_message, "ok")
  assert_eq(audio.frames(), 32)
  for index = 0; index < 32; index = index + 1 {
    let expected = samples[index].to_double() / 32768.0
    assert_true((audio.data[index] - expected).abs() < 1.0e-12)
  }
}

///|
test "constant subframes decode exactly" {
  let channel : Array[Int32] = Array::make(16, 1234)
  let stream = make_flac(8000, 1, 16, 16L, [[channel]], [[SubKind::Constant]])
  let (audio, decode_message) = decode_or_message(stream)
  assert_eq(decode_message, "ok")
  assert_eq(audio.frames(), 16)
  assert_true((audio.data[0] - 1234.0 / 32768.0).abs() < 1.0e-12)
}

///|
test "every fixed predictor order reconstructs" {
  for order = 0; order <= 4; order = order + 1 {
    let samples = pseudo(3 + order, 24, 500)
    let stream = make_flac(
      16000,
      1,
      16,
      24L,
      [[samples]],
      [[SubKind::Fixed(order)]],
    )
    let (audio, decode_message) = decode_or_message(stream)
  assert_eq(decode_message, "ok")
    assert_eq(audio.frames(), 24)
    for index = 0; index < 24; index = index + 1 {
      let expected = samples[index].to_double() / 32768.0
      assert_true((audio.data[index] - expected).abs() < 1.0e-12)
    }
  }
}

///|
test "lpc subframes reconstruct" {
  let samples = pseudo(19, 40, 3000)
  let coefficients : Array[Int32] = [2, -1]
  let stream = make_flac(
    44100,
    1,
    16,
    40L,
    [[samples]],
    [[SubKind::Lpc(2, coefficients, 1)]],
  )
  let (audio, decode_message) = decode_or_message(stream)
  assert_eq(decode_message, "ok")
  assert_eq(audio.frames(), 40)
  for index = 0; index < 40; index = index + 1 {
    let expected = samples[index].to_double() / 32768.0
    assert_true((audio.data[index] - expected).abs() < 1.0e-12)
  }
}

///|
test "mid side stereo is decorrelated" {
  let left = pseudo(23, 32, 4000)
  let right = pseudo(29, 32, 4000)
  // mid = (l + r) >> 1, side = l - r matches the decoder's reconstruction.
  let mid : Array[Int32] = Array::make(32, 0)
  let side : Array[Int32] = Array::make(32, 0)
  for index = 0; index < 32; index = index + 1 {
    mid[index] = (left[index] + right[index]) >> 1
    side[index] = left[index] - right[index]
  }
  let stream = make_flac(
    44100,
    2,
    16,
    32L,
    [[mid, side]],
    [[SubKind::Verbatim, SubKind::Verbatim]],
    side_extra_bits=1,
  )
  let (audio, decode_message) = decode_or_message(stream)
  assert_eq(decode_message, "ok")
  assert_eq(audio.channels, 2)
  for index = 0; index < 32; index = index + 1 {
    assert_true((audio.data[index * 2] - left[index].to_double() / 32768.0).abs() < 1.0e-9)
    assert_true((audio.data[index * 2 + 1] - right[index].to_double() / 32768.0).abs() < 1.0e-9)
  }
}

///|
test "independent multi channel frames decode" {
  let a = pseudo(31, 16, 100)
  let b = pseudo(37, 16, 100)
  let c = pseudo(41, 16, 100)
  let stream = make_flac(
    48000,
    3,
    16,
    16L,
    [[a, b, c]],
    [[SubKind::Verbatim, SubKind::Verbatim, SubKind::Verbatim]],
  )
  let (audio, decode_message) = decode_or_message(stream)
  assert_eq(decode_message, "ok")
  assert_eq(audio.channels, 3)
  for frame = 0; frame < 16; frame = frame + 1 {
    assert_true((audio.data[frame * 3] - a[frame].to_double() / 32768.0).abs() < 1.0e-9)
    assert_true((audio.data[frame * 3 + 1] - b[frame].to_double() / 32768.0).abs() < 1.0e-9)
    assert_true((audio.data[frame * 3 + 2] - c[frame].to_double() / 32768.0).abs() < 1.0e-9)
  }
}

///|
test "many frames are concatenated" {
  let first = pseudo(43, 8, 500)
  let second = pseudo(47, 8, 500)
  let stream = make_flac(
    8000,
    1,
    16,
    16L,
    [[first], [second]],
    [[SubKind::Verbatim], [SubKind::Verbatim]],
  )
  let (audio, decode_message) = decode_or_message(stream)
  assert_eq(decode_message, "ok")
  assert_eq(audio.frames(), 16)
  assert_true(
    (audio.data[8] - second[0].to_double() / 32768.0).abs() < 1.0e-9,
  )
}

///|
test "24 bit streams normalise by bit depth" {
  let samples = pseudo(53, 16, 100000)
  let stream = make_flac(
    96000,
    1,
    24,
    16L,
    [[samples]],
    [[SubKind::Verbatim]],
  )
  let (audio, decode_message) = decode_or_message(stream)
  assert_eq(decode_message, "ok")
  let expected = samples[0].to_double() / 8388608.0
  assert_true((audio.data[0] - expected).abs() < 1.0e-12)
}

///|
test "big frame numbers use the extended encoding" {
  let samples = pseudo(59, 8, 50)
  let stream = make_flac(
    44100,
    1,
    16,
    8L,
    [[samples]],
    [[SubKind::Verbatim]],
  )
  // Patch the frame number by writing a fresh frame with a large number.
  let writer = BitWriter::new()
  writer.write_raw(stream.exact_view(start=0, end=42).to_owned())
  write_frame(
    writer,
    [samples],
    16,
    44100,
    1,
    3000000L,
    [SubKind::Verbatim],
  )
  let (audio, decode_message) = decode_or_message(writer.to_bytes())
  assert_eq(decode_message, "ok")
  assert_eq(audio.frames(), 8)
}

///|
test "corrupt frame footer is rejected" {
  let samples = pseudo(61, 8, 50)
  let stream = make_flac(8000, 1, 16, 8L, [[samples]], [[SubKind::Verbatim]])
  let last = stream.length() - 1
  let broken : Array[Byte] = []
  for index = 0; index < stream.length(); index = index + 1 {
    let byte = if index == last {
      (stream.at(index).to_int() ^ 0xFF).to_byte()
    } else {
      stream.at(index)
    }
    broken.push(byte)
  }
  assert_eq(decode_error_kind(Bytes::from_array(broken[:])), "invalid")
}

///|
test "truncated stream is rejected" {
  let samples = pseudo(67, 8, 50)
  let stream = make_flac(8000, 1, 16, 8L, [[samples]], [[SubKind::Verbatim]])
  let cut = stream.exact_view(start=0, end=30).to_owned()
  let kind = decode_error_kind(cut)
  assert_true(kind == "truncated" || kind == "invalid")
}

///|
test "metadata comments are parsed" {
  let writer = BitWriter::new()
  writer.write_raw(ascii_bytes("fLaC"))
  write_stream_info(writer, 44100, 1, 16, 4L, 4)
  // Last-flag on STREAMINFO, then a VORBIS_COMMENT block.
  let bytes = writer.to_bytes()
  let patched : Array[Byte] = []
  for index = 0; index < bytes.length(); index = index + 1 {
    patched.push(
      if index == 4 {
        bytes.at(index)
      } else {
        bytes.at(index)
      },
    )
  }
  let stream = BitWriter::new()
  stream.write_raw(Bytes::from_array(patched[:]))
  let comment = BitWriter::new()
  let vendor = "moonaudio"
  let body = BitWriter::new()
  body.write_u32le(vendor.length().to_int64())
  body.write_raw(ascii_bytes(vendor))
  body.write_u32le(2L)
  for text in ["TITLE=Test", "ARTIST=Sakuraqwq1"] {
    body.write_u32le(text.length().to_int64())
    body.write_raw(ascii_bytes(text))
  }
  let payload = body.to_bytes()
  comment.write_bits(0x84, 8)
  comment.write_u24be(payload.length())
  comment.write_raw(payload)
  stream.write_raw(comment.to_bytes())
  let frame = BitWriter::new()
  write_frame(
    frame,
    [Array::make(4, 0)],
    16,
    44100,
    0,
    0L,
    [SubKind::Constant],
  )
  stream.write_raw(frame.to_bytes())
  let info = parse_info(stream.to_bytes()) catch {
    (_ : @audio.AudioError) => panic()
  }
  assert_eq(info.meta("TITLE"), Some("Test"))
  assert_eq(info.meta("ARTIST"), Some("Sakuraqwq1"))
  assert_eq(info.meta("ALBUM"), None)
  assert_eq(info.blocks.length(), 2)
}

///|
test "partitioned rice residuals with an escape partition" {
  let samples = pseudo(71, 16, 400)
  for partition_order = 0; partition_order <= 2; partition_order = partition_order + 1 {
    let writer = BitWriter::new()
    writer.write_raw(ascii_bytes("fLaC"))
    write_stream_info(writer, 8000, 1, 16, 16L, 16)
    let bytes = writer.to_bytes()
    let patched : Array[Byte] = []
    for index = 0; index < bytes.length(); index = index + 1 {
      patched.push(
        if index == 4 {
          (bytes.at(index).to_int() | 0x80).to_byte()
        } else {
          bytes.at(index)
        },
      )
    }
    let out = BitWriter::new()
    out.write_raw(Bytes::from_array(patched[:]))
    let frame = BitWriter::new()
    let start = frame.byte_position()
    frame.write_bits(0x3FFE, 14)
    frame.write_bit(0)
    frame.write_bit(0)
    frame.write_bits(7, 4)
    frame.write_bits(0, 4)
    frame.write_bits(0, 4)
    frame.write_bits(0, 3)
    frame.write_bit(0)
    write_utf8_number(frame, 0L)
    frame.write_bits(15, 16)
    frame.align()
    let header_end = frame.byte_position()
    let header_crc = crc8(frame.to_bytes(), start, header_end)
    frame.write_bits(header_crc, 8)
    write_fixed_partitioned(frame, samples, 16, 2, partition_order, escape_first=true)
    frame.align()
    let end = frame.byte_position()
    let frame_crc = crc16(frame.to_bytes(), start, end)
    frame.write_bits((frame_crc >> 8) & 0xFF, 8)
    frame.write_bits(frame_crc & 0xFF, 8)
    out.write_raw(frame.to_bytes())
    let (audio, message) = decode_or_message(out.to_bytes())
    assert_eq(message, "ok")
    assert_eq(audio.frames(), 16)
    for index = 0; index < 16; index = index + 1 {
      let expected = samples[index].to_double() / 32768.0
      assert_true((audio.data[index] - expected).abs() < 1.0e-9)
    }
  }
}

///|
test "12 and 20 bit streams normalise correctly" {
  for bps = 12; bps <= 20; bps = bps + 8 {
    let range = (1 << (bps - 1)) - 1
    let samples = pseudo(77 + bps, 16, range)
    let stream = make_flac(44100, 1, bps, 16L, [[samples]], [[SubKind::Verbatim]])
    let (audio, message) = decode_or_message(stream)
    assert_eq(message, "ok")
    let scale = 1.0 / (1 << (bps - 1)).to_double()
    for index = 0; index < 16; index = index + 1 {
      assert_true((audio.data[index] - samples[index].to_double() * scale).abs() < 1.0e-12)
    }
  }
}

///|
test "variable blocking strategy is accepted" {
  let samples = pseudo(83, 12, 300)
  let writer = BitWriter::new()
  writer.write_raw(ascii_bytes("fLaC"))
  write_stream_info(writer, 8000, 1, 16, 12L, 12)
  let bytes = writer.to_bytes()
  let patched : Array[Byte] = []
  for index = 0; index < bytes.length(); index = index + 1 {
    patched.push(
      if index == 4 {
        (bytes.at(index).to_int() | 0x80).to_byte()
      } else {
        bytes.at(index)
      },
    )
  }
  let out = BitWriter::new()
  out.write_raw(Bytes::from_array(patched[:]))
  let frame = BitWriter::new()
  let start = frame.byte_position()
  frame.write_bits(0x3FFE, 14)
  frame.write_bit(0)
  frame.write_bit(1)
  frame.write_bits(7, 4)
  frame.write_bits(0, 4)
  frame.write_bits(0, 4)
  frame.write_bits(0, 3)
  frame.write_bit(0)
  write_utf8_number(frame, 0L)
  frame.write_bits(11, 16)
  frame.align()
  let header_end = frame.byte_position()
  let header_crc = crc8(frame.to_bytes(), start, header_end)
  frame.write_bits(header_crc, 8)
  write_subframe(frame, samples, 16, SubKind::Verbatim)
  frame.align()
  let end = frame.byte_position()
  let frame_crc = crc16(frame.to_bytes(), start, end)
  frame.write_bits((frame_crc >> 8) & 0xFF, 8)
  frame.write_bits(frame_crc & 0xFF, 8)
  out.write_raw(frame.to_bytes())
  let (audio, message) = decode_or_message(out.to_bytes())
  assert_eq(message, "ok")
  assert_eq(audio.frames(), 12)
}
