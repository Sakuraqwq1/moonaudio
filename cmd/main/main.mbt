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
    "  moonaudio stats <base64>                peak/RMS/crest/DC/zero crossings",
  )
  println(
    "  moonaudio spectrum <base64> [options]   dominant frequency and spectral peak",
  )
  println("      --fft <n>           FFT size, power of two (default: 1024)")
  println("  moonaudio spectrogram <base64> [options]")
  println("      --fft <n> --hop <n> --window <name> --svg")
  println("      prints CSV (default) or a grayscale SVG heat map")
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
  println("  export AUDIO_B64=$(cat tone.b64)")
  println("  moon run cmd/main -- stats @AUDIO_B64")
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
  match command {
    "version" | "--version" | "-V" =>
      println("moonaudio \{@moonaudio.version()}")
    "help" | "--help" | "-h" => usage()
    "demo" => run_demo()
    "info" =>
      if rest.length() == 0 {
        println("error: `info` needs a base64 payload")
      } else {
        run_info(rest[0])
      }
    "stats" =>
      if rest.length() == 0 {
        println("error: `stats` needs a base64 payload")
      } else {
        run_stats(rest[0])
      }
    "spectrum" =>
      if rest.length() == 0 {
        println("error: `spectrum` needs a base64 payload")
      } else {
        run_spectrum(rest[0], rest[1:].to_owned())
      }
    "spectrogram" =>
      if rest.length() == 0 {
        println("error: `spectrogram` needs a base64 payload")
      } else {
        run_spectrogram(rest[0], rest[1:].to_owned())
      }
    "convert" =>
      if rest.length() == 0 {
        println("error: `convert` needs a base64 payload")
      } else {
        run_convert(rest[0], rest[1:].to_owned())
      }
    "tone" => run_tone(rest)
    _ => {
      println("error: unknown command \"\{command}\"")
      usage()
    }
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
/// `true` when the flag `--name` appears in `args`.
fn flag(args : Array[String], name : String) -> Bool {
  for argument in args {
    if argument == name {
      return true
    }
  }
  false
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
/// Load a payload and decode it as audio, reporting any error.
fn load_audio(payload : String) -> @audio.AudioBuffer? {
  let bytes = match decode_payload(payload) {
    Some(bytes) => bytes
    None => return None
  }
  let audio = @moonaudio.decode(bytes) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return None
    }
  }
  Some(audio)
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
  let audio = match load_audio(payload) {
    Some(audio) => audio
    None => return
  }
  println(@dsp.analyse(audio).to_lines())
}

///|
/// `spectrum` command: dominant frequency of the loudest FFT frame.
fn run_spectrum(payload : String, options : Array[String]) -> Unit {
  let audio = match load_audio(payload) {
    Some(audio) => audio
    None => return
  }
  let fft_size = int_option(options, "--fft", 1024)
  let peak = dominant_frequency(audio, fft_size)
  println("fft size:  \{fft_size}")
  println("dominant:  \{format_double(peak)} Hz")
  println("expected:  \{format_double(440.0)} Hz for the CLI tone command")
}

///|
/// `spectrogram` command: CSV or SVG rendering.
fn run_spectrogram(payload : String, options : Array[String]) -> Unit {
  let audio = match load_audio(payload) {
    Some(audio) => audio
    None => return
  }
  let fft_size = int_option(options, "--fft", 1024)
  let hop = int_option(options, "--hop", fft_size / 4)
  let window_name = option(options, "--window", "hann")
  let window = match window_name {
    "rect" | "rectangular" => @dsp.WindowKind::Rectangular
    "hamming" => @dsp.WindowKind::Hamming
    "blackman" => @dsp.WindowKind::Blackman
    "blackman-harris" => @dsp.WindowKind::BlackmanHarris
    "kaiser" => @dsp.WindowKind::Kaiser
    _ => @dsp.WindowKind::Hann
  }
  let spectrogram = @dsp.spectrogram(audio, fft_size~, hop~, window~) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  if flag(options, "--svg") {
    println(spectrogram.to_svg())
  } else {
    println(spectrogram.to_csv())
  }
}

///|
/// `convert` command: decode, resample, remix, re-encode.
fn run_convert(payload : String, options : Array[String]) -> Unit {
  let audio = match load_audio(payload) {
    Some(audio) => audio
    None => return
  }
  let rate = int_option(options, "--rate", 0)
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
  let channels = int_option(options, "--channels", 0)
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
  let frequency = double_option(options, "--freq", 440.0)
  let rate = int_option(options, "--rate", 44100)
  let milliseconds = int_option(options, "--ms", 500)
  let format = @audio.SampleFormat::parse(option(options, "--format", "s16")) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let frames = if milliseconds > 0 { rate * milliseconds / 1000 } else { 0 }
  let audio = @dsp.tone(frequency, rate, frames, amplitude=0.8) catch {
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
/// Frequency of the strongest FFT bin of the whole buffer.
fn dominant_frequency(audio : @audio.AudioBuffer, fft_size : Int32) -> Double {
  let size = if fft_size < 2 { 2 } else { fft_size }
  let samples = audio.data
  let count = if samples.length() < size { samples.length() } else { size }
  let slice : Array[Double] = Array::make(size, 0.0)
  for index = 0; index < count; index = index + 1 {
    slice[index] = samples[index]
  }
  let spectrum = @dsp.real_fft(slice)
  let magnitudes = @dsp.magnitude(spectrum, n=size)
  let mut best_index = 0
  let mut best = 0.0
  for index = 0; index < magnitudes.length(); index = index + 1 {
    if magnitudes[index] > best {
      best = magnitudes[index]
      best_index = index
    }
  }
  best_index.to_double() * audio.sample_rate.to_double() / size.to_double()
}

///|
/// Integer command line option.
fn int_option(args : Array[String], name : String, fallback : Int32) -> Int32 {
  @string.parse_int(option(args, name, "")) catch {
    (_ : Error) => fallback
  }
}

///|
/// Floating point command line option.
fn double_option(
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
  let tone = @dsp.tone(440.0, 44100, 44100, amplitude=0.8) catch {
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
  let stats = @dsp.analyse(decoded)
  println(
    "- roundtrip: \{decoded.frames()} frames, peak \{format_dbfs(stats.peak_dbfs)}, rms \{format_dbfs(stats.rms_dbfs)}, crest \{format_double(stats.crest_factor)}",
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
  let dominant = dominant_frequency(tone, 4096)
  println(
    "- FFT peak: \{format_double(dominant)} Hz for the 440 Hz tone (\{format_double(44100.0 / 4096.0)} Hz per bin)",
  )
  let spectrogram = @dsp.spectrogram(
    tone,
    fft_size=1024,
    hop=256,
    window=@dsp.WindowKind::Hann,
  ) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let (frames, bins) = spectrogram.size()
  println(
    "- spectrogram: \{frames} frames x \{bins} bins, bin width \{format_double(spectrogram.bin_hz())} Hz, frame 0 peak \{format_double(spectrogram.peak_frequency(0))} Hz",
  )
  let high_pass = @dsp.Biquad::new(@dsp.HighPass, 44100, 200.0) catch {
    (error : @audio.AudioError) => {
      report_error(error)
      return
    }
  }
  let filtered = high_pass.apply_buffer(tone)
  println(
    "- high pass 200 Hz: peak \{format_double(filtered.peak())}, rms \{format_double(filtered.rms())}",
  )
  println("")
  println(
    "Every decoder produced the same normalised `AudioBuffer`, which is what lets",
  )
  println("the CLI pipe any container through any analysis stage.")
}
