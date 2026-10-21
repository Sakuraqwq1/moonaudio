// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Parsed FLAC frame header.
pub(all) struct FrameHeader {
  block_size : Int32
  sample_rate : Int32
  channels : Int32
  bits_per_sample : Int32
  /// Raw channel assignment nibble: 0..7 independent, 8 left/side, 9
  /// right/side, 10 mid/side.
  channel_assignment : Int32
  /// 0 for fixed block size streams, 1 for variable block size streams.
  blocking_strategy : Int32
  /// Frame number (fixed) or first sample number (variable).
  number : Int64
  /// Byte offset of the first byte after the header (and after its CRC-8).
  payload_offset : Int32
  header_crc8 : Int32
}

///|
/// Parse one frame header starting at byte `offset`.
pub fn parse_frame_header(
  bytes : Bytes,
  offset : Int32,
  info : FlacInfo,
) -> FrameHeader raise @audio.AudioError {
  let reader = BitReader::new(bytes, bit=offset * 8)
  let sync = reader.read_bits(14)
  if sync != 0x3FFE {
    raise @audio.Invalid("frame at \{offset}: bad sync code 0x\{sync}")
  }
  if reader.read_bit() != 0 {
    raise @audio.Invalid("frame at \{offset}: reserved header bit is set")
  }
  let blocking_strategy = reader.read_bit()
  let block_code = reader.read_bits(4)
  let rate_code = reader.read_bits(4)
  let channel_assignment = reader.read_bits(4)
  let size_code = reader.read_bits(3)
  if reader.read_bit() != 0 {
    raise @audio.Invalid("frame at \{offset}: trailing reserved bit is set")
  }
  let number = reader.read_utf8_uint()
  let mut block_size = match block_code {
    0 => raise @audio.Invalid("frame at \{offset}: reserved block size code")
    1 => 192
    2 => 576
    3 => 1152
    4 => 2304
    5 => 4608
    6 => 0
    7 => 0
    _ => 256 << (block_code - 8)
  }
  if block_code == 6 {
    block_size = reader.read_bits(8) + 1
  } else if block_code == 7 {
    block_size = reader.read_bits(16) + 1
  }
  let sample_rate = match rate_code {
    0 => info.sample_rate
    1 => 88200
    2 => 176400
    3 => 192000
    4 => 8000
    5 => 16000
    6 => 22050
    7 => 24000
    8 => 32000
    9 => 44100
    10 => 48000
    11 => 96000
    12 => reader.read_bits(8) * 1000
    13 => reader.read_bits(16)
    14 => reader.read_bits(16) * 10
    _ => raise @audio.Invalid("frame at \{offset}: reserved sample rate code")
  }
  let channels = if channel_assignment <= 7 {
    channel_assignment + 1
  } else if channel_assignment <= 10 {
    2
  } else {
    raise @audio.Invalid(
      "frame at \{offset}: reserved channel assignment \{channel_assignment}",
    )
  }
  let bits = match size_code {
    0 => info.bits_per_sample
    1 => 8
    2 => 12
    4 => 16
    5 => 20
    6 => 24
    7 => 32
    _ => raise @audio.Invalid("frame at \{offset}: reserved sample size code")
  }
  reader.align()
  let header_bytes = reader.position() / 8 - offset
  if header_bytes <= 0 {
    raise @audio.Invalid("frame at \{offset}: empty header")
  }
  if offset + header_bytes + 1 > bytes.length() {
    raise @audio.Truncated("frame at \{offset}: header runs past end of file")
  }
  let computed = crc8(bytes, offset, offset + header_bytes)
  let stored_crc = reader.read_byte()
  if stored_crc != computed {
    raise @audio.Invalid(
      "frame at \{offset}: header CRC-8 mismatch (stored \{stored_crc}, computed \{computed})",
    )
  }
  FrameHeader::{
    block_size,
    sample_rate,
    channels,
    bits_per_sample: bits,
    channel_assignment,
    blocking_strategy,
    number,
    payload_offset: offset + header_bytes + 1,
    header_crc8: stored_crc,
  }
}

///|
/// Decode every subframe of one frame.
///
/// Returns one sample array per channel, with channel decorrelation already
/// undone, plus the byte offset of the frame footer.
pub fn decode_frame(
  bytes : Bytes,
  offset : Int32,
  info : FlacInfo,
  verify_crc? : Bool = true,
) -> (Array[Array[Int32]], FrameHeader, Int32) raise @audio.AudioError {
  let header = parse_frame_header(bytes, offset, info)
  let reader = BitReader::new(bytes, bit=header.payload_offset * 8)
  let channels : Array[Array[Int32]] = []
  for channel = 0; channel < header.channels; channel = channel + 1 {
    let mut bps = header.bits_per_sample
    let side_channel = match header.channel_assignment {
      8 => channel == 1
      9 => channel == 0
      10 => channel == 1
      _ => false
    }
    if side_channel {
      bps = bps + 1
    }
    channels.push(decode_subframe(reader, header.block_size, bps))
  }
  reader.align()
  let footer_offset = reader.position() / 8
  if verify_crc {
    if footer_offset + 2 > bytes.length() {
      raise @audio.Truncated("frame at \{offset}: missing CRC-16 footer")
    }
    let stored = @audio.read_u16be(bytes, footer_offset)
    let computed = crc16(bytes, offset, footer_offset)
    if stored != computed {
      raise @audio.Invalid(
        "frame at \{offset}: CRC-16 mismatch (stored \{stored}, computed \{computed})",
      )
    }
  }
  let restored = decorrelate(channels, header)
  (restored, header, footer_offset + 2)
}

///|
/// Undo FLAC's inter-channel decorrelation.
fn decorrelate(
  channels : Array[Array[Int32]],
  header : FrameHeader,
) -> Array[Array[Int32]] {
  match header.channel_assignment {
    8 => {
      let left = channels[0]
      let side = channels[1]
      let right : Array[Int32] = Array::make(side.length(), 0)
      for index = 0; index < side.length(); index = index + 1 {
        right[index] = left[index] - side[index]
      }
      [left, right]
    }
    9 => {
      let side = channels[0]
      let right = channels[1]
      let left : Array[Int32] = Array::make(side.length(), 0)
      for index = 0; index < side.length(); index = index + 1 {
        left[index] = right[index] + side[index]
      }
      [left, right]
    }
    10 => {
      let mid_raw = channels[0]
      let side = channels[1]
      let left : Array[Int32] = Array::make(side.length(), 0)
      let right : Array[Int32] = Array::make(side.length(), 0)
      for index = 0; index < side.length(); index = index + 1 {
        let mid = (mid_raw[index] << 1) | (side[index] & 1)
        left[index] = (mid + side[index]) >> 1
        right[index] = (mid - side[index]) >> 1
      }
      [left, right]
    }
    _ => channels
  }
}

///|
/// Decode one subframe into `block_size` integer samples.
fn decode_subframe(
  reader : BitReader,
  block_size : Int32,
  bps : Int32,
) -> Array[Int32] raise @audio.AudioError {
  if reader.read_bit() != 0 {
    raise @audio.Invalid("subframe padding bit is set")
  }
  let kind = reader.read_bits(6)
  let has_wasted = reader.read_bit() == 1
  let mut wasted = 0
  if has_wasted {
    wasted = reader.read_unary() + 1
  }
  let effective_bps = bps - wasted
  if effective_bps <= 0 || effective_bps > 33 {
    raise @audio.Invalid("subframe declares \{effective_bps} effective bits")
  }
  let samples = if kind == 0 {
    let value = reader.read_signed(effective_bps)
    let samples : Array[Int32] = Array::make(block_size, 0)
    for index = 0; index < block_size; index = index + 1 {
      samples[index] = value
    }
    samples
  } else if kind == 1 {
    let samples : Array[Int32] = Array::make(block_size, 0)
    for index = 0; index < block_size; index = index + 1 {
      samples[index] = reader.read_signed(effective_bps)
    }
    samples
  } else if kind >= 8 && kind <= 12 {
    decode_fixed(reader, block_size, effective_bps, kind - 8)
  } else if kind >= 32 {
    decode_lpc(reader, block_size, effective_bps, kind - 31)
  } else {
    raise @audio.Unsupported("subframe type \{kind}")
  }
  if wasted > 0 {
    for index = 0; index < samples.length(); index = index + 1 {
      samples[index] = samples[index] << wasted
    }
  }
  samples
}

///|
/// Decode a fixed-predictor subframe of the given order.
fn decode_fixed(
  reader : BitReader,
  block_size : Int32,
  bps : Int32,
  order : Int32,
) -> Array[Int32] raise @audio.AudioError {
  let samples : Array[Int32] = Array::make(block_size, 0)
  for index = 0; index < order; index = index + 1 {
    samples[index] = reader.read_signed(bps)
  }
  let residual = decode_residual(reader, block_size, order)
  for index = order; index < block_size; index = index + 1 {
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
      _ => raise @audio.Unsupported("fixed predictor order \{order}")
    }
    samples[index] = prediction + residual[index - order]
  }
  samples
}

///|
/// Decode an LPC subframe of the given order (1..=32).
fn decode_lpc(
  reader : BitReader,
  block_size : Int32,
  bps : Int32,
  order : Int32,
) -> Array[Int32] raise @audio.AudioError {
  if order < 1 || order > 32 {
    raise @audio.Invalid("LPC order \{order} out of range")
  }
  let samples : Array[Int32] = Array::make(block_size, 0)
  for index = 0; index < order; index = index + 1 {
    samples[index] = reader.read_signed(bps)
  }
  let precision_code = reader.read_bits(4)
  if precision_code == 0x0F {
    raise @audio.Invalid("LPC coefficient precision code 0b1111 is invalid")
  }
  let precision = precision_code + 1
  let shift = reader.read_signed(5)
  if shift < 0 {
    raise @audio.Unsupported("negative LPC shift \{shift}")
  }
  let coefficients : Array[Int32] = Array::make(order, 0)
  for index = 0; index < order; index = index + 1 {
    coefficients[index] = reader.read_signed(precision)
  }
  let residual = decode_residual(reader, block_size, order)
  for index = order; index < block_size; index = index + 1 {
    let mut sum = 0L
    for tap = 0; tap < order; tap = tap + 1 {
      sum = sum + coefficients[tap].to_int64() * samples[index - 1 - tap].to_int64()
    }
    let prediction = (sum >> shift).to_int()
    samples[index] = prediction + residual[index - order]
  }
  samples
}

///|
/// Decode the Rice-coded residual of a fixed or LPC subframe.
fn decode_residual(
  reader : BitReader,
  block_size : Int32,
  predictor_order : Int32,
) -> Array[Int32] raise @audio.AudioError {
  let rice_method = reader.read_bits(2)
  if rice_method > 1 {
    raise @audio.Unsupported("residual coding method \{rice_method}")
  }
  let parameter_bits = if rice_method == 0 { 4 } else { 5 }
  let escape = (1 << parameter_bits) - 1
  let partition_order = reader.read_bits(4)
  let partitions = 1 << partition_order
  if block_size % partitions != 0 {
    raise @audio.Invalid(
      "residual partition count \{partitions} does not divide block size \{block_size}",
    )
  }
  let partition_size = block_size >> partition_order
  if partition_size < predictor_order {
    raise @audio.Invalid("residual partition smaller than predictor order")
  }
  let total = block_size - predictor_order
  let residual : Array[Int32] = Array::make(total, 0)
  let mut cursor = 0
  for partition = 0; partition < partitions; partition = partition + 1 {
    let count = if partition == 0 {
      partition_size - predictor_order
    } else {
      partition_size
    }
    let parameter = reader.read_bits(parameter_bits)
    if parameter == escape {
      let raw_bits = reader.read_bits(5)
      for _index = 0; _index < count; _index = _index + 1 {
        residual[cursor] = if raw_bits == 0 {
          0
        } else {
          reader.read_signed(raw_bits)
        }
        cursor = cursor + 1
      }
    } else {
      for _index = 0; _index < count; _index = _index + 1 {
        residual[cursor] = read_rice(reader, parameter)
        cursor = cursor + 1
      }
    }
  }
  residual
}

///|
/// Read one Rice code with parameter `parameter` (0..=30).
fn read_rice(reader : BitReader, parameter : Int32) -> Int32 raise @audio.AudioError {
  let quotient = reader.read_unary()
  let remainder = if parameter == 0 { 0 } else { reader.read_bits(parameter) }
  let value = (quotient << parameter) | remainder
  if (value & 1) != 0 {
    -((value >> 1) + 1)
  } else {
    value >> 1
  }
}
