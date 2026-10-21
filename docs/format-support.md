# Container support

This page records exactly what `moonaudio` accepts and what it deliberately
rejects, so integrators can decide whether a file needs a fallback decoder.

Legend: ✅ decoded and encoded · 🔵 decoded only · ❌ rejected with a clear error.

## WAV (RIFF/WAVE)

| Feature | Status | Notes |
| --- | --- | --- |
| RIFF little-endian | ✅ | canonical WAVE |
| RIFX big-endian | 🔵 | decoded; encoding always writes RIFF |
| RF64 | 🔵 | magic accepted, sizes treated as 32-bit |
| PCM 8-bit unsigned | ✅ | offset binary |
| PCM 16 / 24 / 32-bit | ✅ | 1 LSB roundtrip in tests |
| IEEE float 32 / 64 | ✅ | `WAVE_FORMAT_IEEE_FLOAT` (tag 3) |
| `WAVE_FORMAT_EXTENSIBLE` | 🔵 | sub-format resolved, channel mask surfaced |
| μ-law / A-law | 🔵 | expanded to float; encoding picks PCM |
| ADPCM / MP3-in-WAV | ❌ | `Unsupported` |
| `LIST/INFO` (INAM, IART, …) | ✅ | decoded and written |
| Multiple `data` chunks | 🔵 | concatenated |
| Odd-sized chunk padding | ✅ | handled |
| Truncated payloads | — | `Truncated` error, never a trap |

## AIFF / AIFC

| Feature | Status | Notes |
| --- | --- | --- |
| AIFF `FORM`/`AIFF` | ✅ | big-endian PCM |
| AIFC `FORM`/`AIFC` | ✅ | `NONE`, `twos`, `sowt`, `raw `, `fl32`, `fl64` |
| 80-bit extended sample rate | ✅ | exact for 8000/11025/22050/44100/48000/96000 |
| 8 / 16 / 24 / 32-bit PCM | ✅ | 8-bit signed on the wire |
| IEEE float 32 / 64 | ✅ | `FVER` chunk written for AIFC |
| `SSND` offset / block size | 🔵 | offset honoured |
| `NAME`, `AUTH`, `(c) `, `ANNO` | ✅ | metadata roundtrip |
| `MARK`, `INST`, `COMT`, `ID3 ` | 🔵 | inventoried and skipped |
| ima4 / MAC3 / MAC6 / GSM / ADPCM | ❌ | `Unsupported` |
| Non byte-aligned sample sizes | ❌ | `Unsupported` |

## Sun `.au`

| Feature | Status | Notes |
| --- | --- | --- |
| `.snd` magic | ✅ | big-endian header |
| Encoding 1 (μ-law) | 🔵 | expanded to float |
| Encoding 2 (8-bit linear) | ✅ | signed |
| Encoding 3 / 4 / 5 (16/24/32-bit linear) | ✅ | |
| Encoding 6 / 7 (float32/float64) | ✅ | |
| Encoding 27 (A-law) | 🔵 | expanded to float |
| Encodings 23/24/25 (ADPCM) | ❌ | `Unsupported` |
| Annotation block | ✅ | decoded and written |
| `data size = 0xFFFFFFFF` | 🔵 | read until end of buffer |

## FLAC

| Feature | Status | Notes |
| --- | --- | --- |
| Stream marker + metadata blocks | 🔵 | `STREAMINFO`, `VORBIS_COMMENT` parsed; others inventoried |
| Fixed / variable block size | 🔵 | both header forms |
| Block sizes 192…4608 and 8/16-bit custom | 🔵 | |
| Sample rates incl. 8/16-bit custom codes | 🔵 | |
| Bit depth 4…32 | 🔵 | normalised by declared depth |
| Constant subframes | 🔵 | |
| Verbatim subframes | 🔵 | |
| Fixed predictors 0…4 | 🔵 | |
| LPC predictors 1…32 | 🔵 | with coefficient precision and shift |
| Rice partitions, method 0/1 | 🔵 | including escape partitions |
| Wasted bits | 🔵 | |
| Left/side, right/side, mid/side | 🔵 | |
| Channel count 1…8 | 🔵 | |
| CRC-8 header / CRC-16 frame | 🔵 | verified on every frame |
| FLAC encoding | ❌ | decode-only for now |
| Ogg FLAC | ❌ | native FLAC streams only |

## Deliberate gaps

* No FLAC encoder: writing a bit-exact encoder is a separate project with its own
  conformance burden, and the library already covers encode for WAV/AIFF/AU.
* No Ogg container: Vorbis/Opus decoding needs an entirely different stack.
* No file IO: MoonBit core has no portable filesystem API, so callers pass
  `Bytes`; see [`README.md`](../README.md#命令行-demo) for how the CLI works
  around that with base64.
