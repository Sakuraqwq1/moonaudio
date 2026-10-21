# Changelog

All notable changes to `moonaudio` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `src/audio`: `AudioBuffer` (interleaved `Double` samples), sample formats
  (`U8`/`I16`/`I24`/`I32`/`F32`/`F64`), quantisation, dBFS helpers, G.711
  mu-law and A-law codecs, bounds-checked little/big endian byte readers.
- `src/wav`: RIFF/WAVE decoder and encoder for PCM 8/16/24/32, IEEE float 32/64,
  `WAVE_FORMAT_EXTENSIBLE`, RIFX big-endian files, mu-law/A-law decoding,
  `LIST/INFO` metadata and multi-chunk `data` handling.
- `src/flac`: native FLAC decoder — stream marker, metadata blocks
  (`STREAMINFO`, `VORBIS_COMMENT`), frame headers, constant/verbatim/fixed/LPC
  subframes, Rice partitions with escape codes, wasted bits, left/side,
  right/side and mid/side decorrelation, CRC-8 and CRC-16 verification.
- Facade API: `sniff`, `decode`, `decode_detected`, `describe`, `version`.
- CI: type check, tests, formatting and generated-interface checks on Linux,
  macOS and Windows, plus wasm-gc and native builds.

## [0.1.0] - 2026-10-21

### Added

- Initial module skeleton, Apache-2.0 license and project conventions.
