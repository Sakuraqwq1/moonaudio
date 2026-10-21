# Changelog

All notable changes to `moonaudio` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-10-21

### Fixed

- CI runs on Windows: checked-out `pkg.generated.mbti` files were converted to
  CRLF by the runner's `core.autocrlf=true`, so the interface-freshness check
  saw eleven modified files. The repository now pins `eol=lf` in
  `.gitattributes`.
- `moon.pkg` files carried redundant import aliases that `moon fmt` removes;
  the formatting check would have failed on the first CI run.

### Changed

- README no longer describes the package as unpublished.

## [0.3.0] - 2026-10-21

### Added

- **`src/audio`** — `AudioBuffer` (interleaved `Double` samples in `[-1, 1]`),
  sample formats (`U8`/`I16`/`I24`/`I32`/`F32`/`F64`), quantisation and
  dequantisation, dBFS helpers, peak/RMS/normalisation, channel remixing,
  slicing and appending, G.711 mu-law and A-law codecs, bounds-checked
  little/big endian byte readers, IEEE-754 single precision bit conversion.
- **`src/wav`** — RIFF/WAVE decoder and encoder: PCM 8/16/24/32, IEEE float
  32/64, `WAVE_FORMAT_EXTENSIBLE`, RIFX big-endian, mu-law/A-law decoding,
  `LIST/INFO` metadata, multi-chunk `data`, odd-sized chunk padding.
- **`src/aiff`** — AIFF/AIFC decoder and encoder: `NONE`/`twos`/`sowt`/`raw `/
  `fl32`/`fl64` compression, exact 80-bit extended sample rate parsing and
  writing, `SSND` offset, `NAME`/`AUTH`/`(c) `/`ANNO` metadata, `FVER` on write.
- **`src/au`** — Sun/NeXT `.au` decoder and encoder: 8/16/24/32-bit linear,
  float32/float64, mu-law and A-law expansion, annotations, `data size =
  0xFFFFFFFF` streaming files.
- **`src/flac`** — native FLAC decoder: MSB-first bit reader, CRC-8 and CRC-16
  verification, `STREAMINFO` and `VORBIS_COMMENT` parsing, constant/verbatim/
  fixed/LPC subframes, Rice partitions including escape codes, wasted bits,
  left/side, right/side and mid/side decorrelation, 1–8 channels, 4–32 bit
  depths, fixed and variable block sizes, extended UTF-8 frame numbers.
- **`src/dsp`** — window functions (rectangular, Hann, Hamming, Blackman,
  Blackman-Harris, Kaiser with a series Bessel I0), radix-2 FFT, inverse FFT,
  real-input FFT, magnitude and power spectra, spectrogram with CSV and SVG
  output, RBJ biquad filters (low pass, high pass, band pass, notch, peaking,
  low shelf, high shelf) with streaming state, statistics (`AudioStats`),
  silence trimming, DC removal, fades, mixing, sine synthesis and deterministic
  xorshift white noise.
- **`src/resample`** — linear, Catmull-Rom cubic and windowed-sinc sample rate
  conversion with anti-alias cutoff, ratio reduction and deterministic output
  length.
- **Facade** — `sniff`, `decode`, `decode_detected`, `describe`, `version` and a
  `Container` enum covering WAV, AIFF, AU and FLAC.
- **`cmd/main`** — CLI with `demo`, `version`, `info`, `stats`, `spectrum`,
  `spectrogram`, `convert` and `tone` commands over base64 payloads.
- **Examples** — `examples/basic` (minimal end-to-end) and `examples/tour`
  (synthesis, analysis, filtering, resampling, containers).
- **Docs** — README, `docs/architecture.md`, `docs/format-support.md`,
  `docs/flac.md`, `docs/publishing.md`, `CONTRIBUTING.md` and `proposal.md`.
- **CI** — `moon check --deny-warn`, `moon test --deny-warn`, `moon fmt --check`
  (with a bundled `moonfmt` fallback when the formatter cannot be fetched) and
  generated-interface freshness on Linux, macOS and Windows, plus wasm-gc and
  native builds and a CLI smoke test. A separate informational workflow decodes
  a real FLAC file from the official test corpus.
- 138 unit tests covering roundtrips, error paths, spec corner cases and CLI helpers.

### Known limitations

- FLAC is decode-only; there is no FLAC encoder yet.
- Ogg-wrapped FLAC is not accepted; native FLAC streams only.
- The official `flac-test-files` corpus is not vendored (see roadmap).
- No file IO: callers pass `Bytes`, the CLI uses base64 payloads.

## [0.1.0] - 2026-10-21

### Added

- Initial module skeleton, Apache-2.0 license and project conventions.
