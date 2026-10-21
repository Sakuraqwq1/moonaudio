// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Parse a complete FLAC stream: metadata plus decoded audio.
pub fn parse(bytes : Bytes) -> FlacFile raise @audio.AudioError {
  let info = parse_info(bytes)
  let audio = decode_with_info(bytes, info)
  FlacFile::{ info, audio, }
}

///|
/// Decode the audio of a FLAC stream.
pub fn decode(bytes : Bytes) -> @audio.AudioBuffer raise @audio.AudioError {
  let file = parse(bytes)
  file.audio
}

///|
/// Decode the audio of a stream whose metadata has already been parsed.
///
/// The decoder walks frames until end of file or until `total_samples` are
/// collected, verifies both frame CRCs, undoes channel decorrelation and
/// normalises integer samples to `[-1.0, 1.0]`.
pub fn decode_with_info(
  bytes : Bytes,
  info : FlacInfo,
  verify_crc~ : Bool = true,
) -> @audio.AudioBuffer raise @audio.AudioError {
  if info.channels <= 0 {
    raise @audio.Invalid("stream declares \{info.channels} channels")
  }
  if info.sample_rate <= 0 {
    raise @audio.Invalid("stream declares \{info.sample_rate} Hz")
  }
  if info.bits_per_sample <= 0 || info.bits_per_sample > 33 {
    raise @audio.Invalid(
      "stream declares \{info.bits_per_sample} bits per sample",
    )
  }
  let total = info.total_samples
  let channel_planar : Array[Array[Double]] = []
  for _channel = 0; _channel < info.channels; _channel = _channel + 1 {
    channel_planar.push([])
  }
  let scale = @math.pow(2.0, (info.bits_per_sample - 1).to_double())
  let mut offset = info.stream_offset
  let mut collected = 0L
  let mut frames = 0
  while offset + 2 <= bytes.length() {
    if total > 0L && collected >= total {
      break
    }
    let (channels, header, next) = decode_frame(
      bytes,
      offset,
      info,
      verify_crc~,
    )
    if channels.length() != info.channels {
      raise @audio.Invalid(
        "frame at \{offset} has \{channels.length()} channels, expected \{info.channels}",
      )
    }
    let block = header.block_size
    if block <= 0 {
      raise @audio.Invalid("frame at \{offset} declares block size \{block}")
    }
    let mut usable = block
    if total > 0L {
      let remaining = (total - collected).to_int()
      if remaining < usable {
        usable = remaining
      }
    }
    for sample = 0; sample < usable; sample = sample + 1 {
      for channel = 0; channel < info.channels; channel = channel + 1 {
        channel_planar[channel].push(
          channels[channel][sample].to_double() / scale,
        )
      }
    }
    collected = collected + usable.to_int64()
    frames = frames + 1
    if next <= offset {
      raise @audio.Invalid("frame at \{offset} did not advance the stream")
    }
    offset = next
  }
  if frames == 0 {
    raise @audio.Invalid("stream contains no audio frames")
  }
  if collected == 0L {
    raise @audio.Invalid("stream decodes to zero samples")
  }
  let data : Array[Double] = []
  let count = channel_planar[0].length()
  for index = 0; index < count; index = index + 1 {
    for channel = 0; channel < info.channels; channel = channel + 1 {
      data.push(channel_planar[channel][index])
    }
  }
  @audio.AudioBuffer::{
    sample_rate: info.sample_rate,
    channels: info.channels,
    data,
  }
}

///|
/// Number of frames a stream declares, as an `Int32` capped at `Int32::max`.
pub fn declared_frames(info : FlacInfo) -> Int32 {
  if info.total_samples > 2147483647L {
    2147483647
  } else if info.total_samples < 0L {
    0
  } else {
    info.total_samples.to_int()
  }
}

///|
/// `true` when the bytes start with the FLAC stream marker.
pub fn is_flac(bytes : Bytes) -> Bool {
  @audio.ascii_is(bytes, 0, 4, "fLaC")
}
