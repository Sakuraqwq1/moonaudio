// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// Text printed when the CLI is invoked without a recognised command.
fn usage() -> Unit {
  println("moonaudio \{@moonaudio.version()} — pure MoonBit audio toolkit")
  println("")
  println("usage:")
  println(
    "  moonaudio demo                          self check with a Markdown report",
  )
  println("  moonaudio version                       print the module version")
  println(
    "  moonaudio info <base64>                 container, format and metadata summary",
  )
  println(
    "  moonaudio stats <base64>                peak/RMS/duration for decoded audio",
  )
  println(
    "  moonaudio convert <base64> [options]    decode, optionally resample, re-encode",
  )
  println("      --rate <hz>         target sample rate (default: keep)")
  println("      --channels <n>      target channel count (default: keep)")
  println("      --format <name>     u8|s16|s24|s32|f32|f64 (default: s16)")
  println("      --container <name>  wav|aiff|au (default: wav)")
  println(
    "  moonaudio tone [options]                synthesise a sine wave as WAV",
  )
  println("      --freq <hz> --rate <hz> --ms <ms> --format <name>")
  println("")
  println(
    "Binary payloads travel as base64 on the command line, because MoonBit",
  )
  println(
    "core has no portable filesystem API. Decode the output to get a file:",
  )
  println("  moon run cmd/main -- tone --freq 440 > tone.b64")
}

///|
/// Entry point.
fn main {
  let argv = @env.args()
  let args = drop_program_name(argv)
  if args.length() == 0 {
    usage()
    return
  }
  let command = args[0]
  let rest = if args.length() > 1 { args[1:].to_owned() } else { [] }
  if command == "version" || command == "--version" || command == "-V" {
    println("moonaudio \{@moonaudio.version()}")
  } else if command == "help" || command == "--help" || command == "-h" {
    usage()
  } else if command == "demo" {
    run_demo()
  } else if command == "info" {
    if rest.length() == 0 {
      println("error: `info` needs a base64 payload")
      usage()
    } else {
      run_info(rest[0])
    }
  } else if command == "stats" {
    if rest.length() == 0 {
      println("error: `stats` needs a base64 payload")
      usage()
    } else {
      run_stats(rest[0])
    }
  } else if command == "convert" {
    if rest.length() == 0 {
      println("error: `convert` needs a base64 payload")
      usage()
    } else {
      run_convert(rest[0], rest[1:].to_owned())
    }
  } else if command == "tone" {
    run_tone(rest)
  } else {
    println("error: unknown command \"\{command}\"")
    usage()
  }
}

///|
/// Drop the leading program path that some hosts include in `args()`.
fn drop_program_name(argv : Array[String]) -> Array[String] {
  if argv.length() == 0 {
    return argv
  }
  let first = argv[0]
  if first.has_suffix("main") ||
    first.has_suffix("main.exe") ||
    first.has_suffix("main.wasm") ||
    first.has_suffix("moonaudio") {
    argv[1:].to_owned()
  } else {
    argv
  }
}

///|
/// Value of `--name value`, or the fallback when absent.
fn option(args : Array[String], name : String, fallback : String) -> String {
  let mut index = 0
  while index + 1 < args.length() {
    if args[index] == name {
      return args[index + 1]
    }
    index = index + 1
  }
  fallback
}

///|
/// Report a raised error and stop.
fn report_error(error : @audio.AudioError) -> Unit {
  println("error: \{error.message()}")
}

///|
/// Decode a base64 payload into bytes.
///
/// A payload of the form `@NAME` is read from the environment variable `NAME`,
/// which sidesteps the command line length limit for anything larger than a few
/// kilobytes.
fn decode_payload(payload : String) -> Bytes? {
  let text = if payload.has_prefix("@") {
    let name = payload[1:].to_owned()
    match @env.get_env_var(name) {
      Some(value) => value
      None => {
        println("error: environment variable \{name} is not set")
        return None
      }
    }
  } else {
    payload
  }
  let decoded = @base64.decode(text) catch {
    (_ : @base64.Malformed) => {
      println("error: payload is not valid base64")
      return None
    }
  }
  Some(decoded)
}

///|
/// `info` command: container and metadata summary.
fn run_info(payload : String) -> Unit {
  let bytes = match decode_payload(payload) {
    Some(bytes) => bytes
    None => return
  }
  let kind = match @moonaudio.sniff(bytes) {
    Some(kind) => kind.to_name()
    None => "unknown"
  }
  println("container: \{kind}")
  let description = @moonaudio.describe(bytes) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  println("summary:   \{description}")
}

///|
/// `stats` command: decode and print measured levels.
fn run_stats(payload : String) -> Unit {
  let bytes = match decode_payload(payload) {
    Some(bytes) => bytes
    None => return
  }
  let audio = @moonaudio.decode(bytes) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  println("sample rate: \{audio.sample_rate} Hz")
  println("channels:    \{audio.channels}")
  println("frames:      \{audio.frames()}")
  println("duration:    \{format_seconds(audio.duration_seconds())}")
  println("peak:        \{format_dbfs(audio.peak_dbfs())}")
  println("rms:         \{format_dbfs(audio.rms_dbfs())}")
}

///|
/// `convert` command: decode, resample, remix, re-encode.
fn run_convert(payload : String, options : Array[String]) -> Unit {
  let bytes = match decode_payload(payload) {
    Some(bytes) => bytes
    None => return
  }
  let audio = @moonaudio.decode(bytes) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let rate = @string.parse_int(option(options, "--rate", "0")) catch {
    (_ : Error) => 0
  }
  let target = if rate > 0 { rate } else { audio.sample_rate }
  let resampled = if target == audio.sample_rate {
    audio
  } else {
    @resample.resample(audio, target) catch {
      (error : @audio.AudioError) => {
        report_error(error)
        return
      }
    }
  }
  let channels = @string.parse_int(option(options, "--channels", "0")) catch {
    (_ : Error) => 0
  }
  let mixed = if channels > 0 && channels != resampled.channels {
    resampled.remix(channels) catch {
      (error : @audio.AudioError) => {
        report_error(error)
        return
      }
    }
  } else {
    resampled
  }
  let format = @audio.SampleFormat::parse(option(options, "--format", "s16")) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let container = option(options, "--container", "wav")
  let encoded = if container == "wav" {
    @wav.encode(mixed, format~) catch {
      (error : @audio.AudioError) => {
        report_error(error)
        return
      }
    }
  } else if container == "aiff" {
    @aiff.encode(mixed, format~) catch {
      (error : @audio.AudioError) => {
        report_error(error)
        return
      }
    }
  } else if container == "au" {
    @au.encode(mixed, format~) catch {
      (error : @audio.AudioError) => {
        report_error(error)
        return
      }
    }
  } else {
    println("error: unknown container \"\{container}\"")
    return
  }
  println(@base64.encode(encoded[:]))
}

///|
/// `tone` command: synthesise a sine wave and print it as a WAV file.
fn run_tone(options : Array[String]) -> Unit {
  let frequency = parse_double_option(options, "--freq", 440.0)
  let rate = @string.parse_int(option(options, "--rate", "44100")) catch {
    (_ : Error) => 44100
  }
  let milliseconds = @string.parse_int(option(options, "--ms", "500")) catch {
    (_ : Error) => 500
  }
  let format = @audio.SampleFormat::parse(option(options, "--format", "s16")) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let frames = if milliseconds > 0 { rate * milliseconds / 1000 } else { 0 }
  let audio = sine(frequency, rate, frames, 0.8) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let encoded = @wav.encode(audio, format~) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  println(@base64.encode(encoded[:]))
}

///|
/// Deterministic sine oscillator used by `tone` and `demo`.
fn sine(
  frequency : Double,
  sample_rate : Int32,
  frames : Int32,
  amplitude : Double,
) -> @audio.AudioBuffer raise @audio.AudioError {
  let buffer = @audio.AudioBuffer::silence(sample_rate, 1, frames)
  let step = 2.0 * @math.PI * frequency / sample_rate.to_double()
  for frame = 0; frame < frames; frame = frame + 1 {
    buffer.data[frame] = amplitude * @math.sin(step * frame.to_double())
  }
  buffer
}

///|
/// Parse a floating point command line option.
fn parse_double_option(
  args : Array[String],
  name : String,
  fallback : Double,
) -> Double {
  let text = option(args, name, "")
  if text.length() == 0 {
    fallback
  } else {
    @string.parse_double(text) catch {
      (_ : Error) => fallback
    }
  }
}

///|
/// Human readable seconds with millisecond precision.
fn format_seconds(seconds : Double) -> String {
  let total_ms = (seconds * 1000.0).round().to_int()
  let minutes = total_ms / 60000
  let secs = total_ms % 60000 / 1000
  let millis = total_ms % 1000
  "\{minutes}m \{pad3(secs)}.\{pad3(millis)}s"
}

///|
/// Zero padded three digit number.
fn pad3(value : Int32) -> String {
  if value < 10 {
    "00\{value}"
  } else if value < 100 {
    "0\{value}"
  } else {
    value.to_string()
  }
}

///|
/// Three decimal places rendering of a level.
fn format_double(value : Double) -> String {
  let scaled = (value * 1000.0).round().to_int()
  let sign = if scaled < 0 { "-" } else { "" }
  let magnitude = if scaled < 0 { -scaled } else { scaled }
  let whole = magnitude / 1000
  let fraction = magnitude % 1000
  "\{sign}\{whole}.\{pad3(fraction)}"
}

///|
/// dBFS rendering that keeps `-inf` readable.
fn format_dbfs(value : Double) -> String {
  if value.is_inf() && value < 0.0 {
    "-inf dBFS"
  } else if value.is_nan() {
    "nan dBFS"
  } else {
    "\{format_double(value)} dBFS"
  }
}

///|
/// `demo` command: build, encode, decode, analyse and resample in one run and
/// print a Markdown report. This is the runnable example the README points at.
fn run_demo() -> Unit {
  println("# moonaudio demo")
  println("")
  println("- module version: `\{@moonaudio.version()}`")
  let tone = sine(440.0, 44100, 44100, 0.8) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  println(
    "- generated: 1.000 s of 440 Hz at 44.1 kHz, peak \{format_double(tone.peak())}",
  )
  let wav_bytes = @wav.encode(tone) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let kind = match @moonaudio.sniff(wav_bytes) {
    Some(kind) => kind.to_name()
    None => "unknown"
  }
  println("- encoded: \{wav_bytes.length()} byte WAV, sniffed as \{kind}")
  let description = @moonaudio.describe(wav_bytes) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  println("- header: \{description}")
  let decoded = @moonaudio.decode(wav_bytes) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  println(
    "- roundtrip: \{decoded.frames()} frames, peak \{format_dbfs(decoded.peak_dbfs())}, rms \{format_dbfs(decoded.rms_dbfs())}",
  )
  let aiff_bytes = @aiff.encode(tone, format=@audio.I24) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let from_aiff = @moonaudio.decode(aiff_bytes) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  println(
    "- AIFF 24-bit: \{aiff_bytes.length()} bytes, decoded peak \{format_double(from_aiff.peak())}",
  )
  let au_bytes = @au.encode(tone, format=@audio.F64) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let from_au = @moonaudio.decode(au_bytes) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  println(
    "- AU float64: \{au_bytes.length()} bytes, decoded peak \{format_double(from_au.peak())}",
  )
  let upsampled = @resample.resample(tone, 48000) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  println(
    "- resampled 44.1 kHz -> 48 kHz: \{upsampled.frames()} frames, peak \{format_double(upsampled.peak())}",
  )
  println("")
  println(
    "Every decoder produced the same normalised `AudioBuffer`, which is what lets",
  )
  println("the CLI pipe any container through any analysis stage.")
}
