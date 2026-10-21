// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// CRC-8 used by the FLAC frame header (polynomial `x^8 + x^2 + x + 1`).
///
/// Implemented as a bitwise loop instead of a 256 entry table: frames are small
/// and the code stays allocation free, which matters for the wasm target.
pub fn crc8(data : Bytes, start : Int32, end : Int32) -> Int32 {
  let mut crc = 0
  for index = start; index < end; index = index + 1 {
    crc = crc.lxor(data.at(index).to_int().land(0xFF))
    for _bit = 0; _bit < 8; _bit = _bit + 1 {
      if (crc & 0x80) != 0 {
        crc = ((crc << 1) ^ 0x07).land(0xFF)
      } else {
        crc = (crc << 1).land(0xFF)
      }
    }
  }
  crc
}

///|
/// CRC-16 used by the FLAC frame footer (polynomial `x^16 + x^15 + x^2 + 1`,
/// i.e. `0x8005`, MSB first, zero initial value).
pub fn crc16(data : Bytes, start : Int32, end : Int32) -> Int32 {
  let mut crc = 0
  for index = start; index < end; index = index + 1 {
    crc = crc.lxor(data.at(index).to_int().land(0xFF) << 8)
    for _bit = 0; _bit < 8; _bit = _bit + 1 {
      if (crc & 0x8000) != 0 {
        crc = ((crc << 1) ^ 0x8005).land(0xFFFF)
      } else {
        crc = (crc << 1).land(0xFFFF)
      }
    }
  }
  crc
}

///|
/// Incremental CRC-16 helper for callers that walk a stream byte by byte.
pub(all) struct Crc16 {
  mut value : Int32
}

///|
/// A fresh CRC-16 accumulator (initial value 0).
pub fn Crc16::new() -> Crc16 {
  Crc16::{ value: 0 }
}

///|
/// Feed one byte into the accumulator.
pub fn Crc16::update(self : Crc16, byte : Int32) -> Unit {
  let mut crc = self.value.lxor(byte.land(0xFF) << 8)
  for _bit = 0; _bit < 8; _bit = _bit + 1 {
    if (crc & 0x8000) != 0 {
      crc = ((crc << 1) ^ 0x8005).land(0xFFFF)
    } else {
      crc = (crc << 1).land(0xFFFF)
    }
  }
  self.value = crc
}

///|
/// Current CRC-16 value.
pub fn Crc16::value(self : Crc16) -> Int32 {
  self.value
}
