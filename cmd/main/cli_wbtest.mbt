// moonaudio — pure MoonBit audio decoding and DSP toolkit.
// Copyright 2026 Sakuraqwq1
// Licensed under the Apache License, Version 2.0.

///|
/// `--name value` lookup returns the value, and falls back when absent.
test "option reads the value after a flag" {
  let args : Array[String] = ["--rate", "48000", "--format", "s24"]
  assert_eq(option(args, "--rate", "0"), "48000")
  assert_eq(option(args, "--format", "s16"), "s24")
  assert_eq(option(args, "--missing", "default"), "default")
  // A flag at the end of the list has no value and must not read out of bounds.
  assert_eq(option(["--rate"], "--rate", "keep"), "keep")
}

///|
test "flag detects presence only" {
  let args : Array[String] = ["--svg", "--fft", "2048"]
  assert_true(flag(args, "--svg"))
  assert_true(flag(args, "--fft"))
  assert_true(!flag(args, "--csv"))
  // Only exact argument matches count as flags.
  assert_true(!flag(args, "--no-such-flag"))
}

///|
test "program name is dropped when the host includes it" {
  assert_eq(drop_program_name(["main.exe", "demo"]).length(), 1)
  assert_eq(drop_program_name(["moonaudio", "demo"])[0], "demo")
  assert_eq(drop_program_name(["demo"])[0], "demo")
  assert_eq(drop_program_name([]).length(), 0)
  // An unrelated first argument is kept.
  assert_eq(drop_program_name(["version"])[0], "version")
}

///|
test "integer and double options fall back on bad input" {
  let args : Array[String] = ["--rate", "44100", "--freq", "not-a-number"]
  assert_eq(int_option(args, "--rate", 0), 44100)
  assert_eq(int_option(args, "--hop", 512), 512)
  assert_eq(int_option(["--rate", "abc"], "--rate", 8000), 8000)
  assert_eq(double_option(["--freq", "220.5"], "--freq", 440.0), 220.5)
  assert_eq(double_option(args, "--freq", 440.0), 440.0)
  assert_eq(double_option([], "--freq", 440.0), 440.0)
}

///|
test "numeric rendering keeps three decimals" {
  assert_eq(format_double(0.0), "0.000")
  assert_eq(format_double(0.8), "0.800")
  assert_eq(format_double(-1.5), "-1.500")
  assert_eq(format_double(440.0), "440.000")
  assert_eq(format_double(0.0004), "0.000")
  assert_eq(pad3(7), "007")
  assert_eq(pad3(42), "042")
  assert_eq(pad3(123), "123")
}

///|
test "dbfs rendering keeps infinity readable" {
  assert_eq(format_dbfs(0.0), "0.000 dBFS")
  assert_eq(format_dbfs(-6.0206), "-6.021 dBFS")
  // dbfs(0.0) is negative infinity, which the renderer keeps readable.
  assert_eq(format_dbfs(@audio.dbfs(0.0)), "-inf dBFS")
  assert_eq(format_dbfs(@audio.from_dbfs(0.0)), "1.000 dBFS")
}

///|
test "dominant frequency finds a synthesised tone" {
  let tone = @dsp.tone(1000.0, 8000, 1024, amplitude=0.8) catch {
    (error : @audio.AudioError) => {
      println(error.message())
      return
    }
  }
  let peak = dominant_frequency(tone, 1024)
  // 1024-point FFT at 8 kHz gives 7.8125 Hz per bin, so a 1 kHz tone lands on
  // bin 128 exactly.
  assert_true((peak - 1000.0).abs() < 8.0)
}

///|
test "dominant frequency of silence is the DC bin" {
  let silent = @audio.AudioBuffer::silence(44100, 1, 256) catch {
    (error : @audio.AudioError) => {
      println(error.message())
      return
    }
  }
  assert_eq(dominant_frequency(silent, 256), 0.0)
}
