# Contributing

Thanks for looking at `moonaudio`. This page describes how to build, test and
extend the library without breaking its two core promises: **no panic on
malformed input** and **no dependency outside `moonbitlang/core`**.

## Setup

```bash
git clone https://github.com/Sakuraqwq1/moonaudio
cd moonaudio
moon version --all      # 0.1.x toolchain or newer
moon check
moon test
```

The repository ships a pre-commit hook that runs `moon check`:

```bash
git config core.hooksPath .githooks
```

## Local checks before pushing

```bash
moon check --deny-warn
moon test  --deny-warn
moon fmt --check          # needs network: it runs the mooncakes formatter
moon info                 # regenerate pkg.generated.mbti when the API changes
git diff --stat -- '*.mbti'
```

`moon fmt` downloads `moonbitlang/parser/cmd/moonfmt` on first use, so it needs
network access. Offline, use the bundled `moonfmt -w <file>` binary from
`~/.moon/bin` instead; CI still enforces the official check.

## Adding a decoder

1. Create `src/<format>/` with a `moon.pkg` that imports `@audio` (and
   `moonbitlang/core/buffer` if you build output bytes).
2. Reuse `@audio` helpers rather than re-implementing them:
   `read_u16le/be`, `read_u24le/be`, `read_u32le/be`, `read_f32le/be`,
   `read_f64le/be`, `read_ascii`, `ascii_is`, `require_bytes`,
   `quantize/dequantize`, `sign_extend`.
3. Expose `parse_info`, `decode` (returning `@audio.AudioBuffer`) and, if
   writing is supported, `encode`. Keep metadata on a small `*Info` struct with a
   `describe()` method so the CLI and facade can print it.
4. Raise `@audio.AudioError` for every failure: `Truncated` when the bytes end
   early, `Unsupported` for valid-but-unimplemented features, `Invalid` for
   spec violations, `OutOfRange` for bad caller arguments.
5. Add `src/<format>/<format>_wbtest.mbt` with roundtrip tests for each supported
   sample width plus tests for every error path you wrote.
6. Wire the container into `lib.mbt` (`Container`, `sniff`, `decode`,
   `decode_detected`, `describe`) and into `cmd/main` if it has an encoder.
7. Update `docs/format-support.md` and `CHANGELOG.md`.

## Style

* `///|` separates top-level blocks; keep blocks small and independent.
* Document *why* a branch exists, not just what it does. Reserved-code rejection
  and bounds checks deserve a sentence each.
* Avoid `derive(...)`: this toolchain warns on the implicit method promotion it
  generates. Write explicit helpers such as `SampleFormat::to_name` instead.
* No new dependencies. If something genuinely needs an external package, open an
  issue first.
* Keep `AudioBuffer` the single interchange type. A decoder that returns
  something else cannot be used by the DSP pipeline.

## Reporting bugs

Please include the toolchain version (`moon version --all`), the failing input if
it can be shared (or a minimal synthesised equivalent), and the exact error
(`AudioError::kind()` plus `message()`). For decoder bugs, a hex dump of the
first 64 bytes is usually enough to reproduce the parse failure.
