# Architecture

`moonaudio` is deliberately layered so that every decoder produces the same
value type and every analysis tool consumes it. Nothing in the library touches
the host filesystem, the network or a platform audio API, which is why the same
code runs under wasm, wasm-gc and native unchanged.

```
            ┌──────────────────────────────────────────────┐
 bytes ───▶ │ src/wav  src/aiff  src/au  src/flac          │  container layer
            └───────────────┬──────────────────────────────┘
                            │  AudioBuffer (interleaved f64, [-1, 1])
            ┌───────────────▼──────────────────────────────┐
            │ src/audio   buffer · sample formats · PCM    │  signal layer
            │             quantisation · dBFS · G.711      │
            └───────┬───────────────────────┬──────────────┘
                    │                       │
        ┌───────────▼─────────┐   ┌─────────▼─────────────┐
        │ src/dsp             │   │ src/resample          │  analysis layer
        │ windows · FFT       │   │ linear · cubic · sinc │
        │ spectra · filters   │   └───────────────────────┘
        │ stats · fades · mix │
        └─────────────────────┘
                    │
            ┌───────▼────────┐
            │ lib.mbt facade │  sniff / decode / describe / version
            └───────┬────────┘
            ┌───────▼────────┐
            │ cmd/main       │  CLI demo (argv + base64 payloads)
            └────────────────┘
```

## Packages

| Package | Responsibility | Depends on |
| --- | --- | --- |
| `src/audio` | `AudioBuffer`, `SampleFormat`, quantisation, dBFS, G.711, bounds-checked byte readers | core only |
| `src/wav` | RIFF/WAVE decode + encode, `LIST/INFO`, extensible headers | `audio` |
| `src/aiff` | AIFF/AIFC decode + encode, 80-bit extended sample rate | `audio` |
| `src/au` | Sun/NeXT `.au` decode + encode | `audio` |
| `src/flac` | Native FLAC decode: metadata, frames, subframes, Rice, CRC | `audio` |
| `src/dsp` | Windows, FFT, spectra, spectrogram, biquad filters, statistics | `audio` |
| `src/resample` | Sample rate conversion | `audio` |
| root `lib.mbt` | Container sniffing and dispatch | all containers |
| `cmd/main` | Runnable CLI demonstration | facade + dsp |

## Data model

`AudioBuffer` stores interleaved `Double` samples in `[-1.0, 1.0]`:

```
frame f, channel c  ->  data[f * channels + c]
```

Why interleaved doubles:

* every integer PCM width up to 32 bit (and float 32/64) converts exactly into
  `Double`, so decoding never loses precision before DSP runs;
* interleaving is what encoders, resamplers and filters want to walk linearly;
* one representation means a FLAC file, a WAV file and a synthetic tone are
  interchangeable inputs to every analysis function.

The cost is memory (8 bytes per sample). A future `AudioSink`/streaming API is
tracked in the roadmap; today the library targets files up to a few hundred
megabytes.

## Error model

All fallible functions raise a single `@audio.AudioError`:

| Variant | Meaning | Typical cause |
| --- | --- | --- |
| `Truncated` | input ended early | short file, corrupt chunk length |
| `Unsupported` | valid but unimplemented | AIFC `ima4`, WAV ADPCM, reserved FLAC codes |
| `Invalid` | violates the specification | bad magic, CRC mismatch, reserved bits |
| `OutOfRange` | caller supplied a bad value | non-positive sample rate, Q <= 0 |

Every multi-byte read is bounds checked (`@audio.require_bytes`), so a malformed
file produces an error instead of a trap. That property is what makes the
decoders safe to point at untrusted uploads.

## Determinism

* The FLAC decoder verifies CRC-8 (header) and CRC-16 (frame) on every frame.
* `white_noise` uses an explicit xorshift generator seeded by the caller, so
  test fixtures are reproducible across backends.
* FFT and resampler outputs are pure functions of their inputs; no global state
  or hidden platform floating point settings are used.
