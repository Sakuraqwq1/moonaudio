# FLAC decoder internals

`src/flac` is the largest package in the repository, because FLAC is the only
format here that stores audio as a bit-packed prediction residual instead of
plain PCM. This page walks through what the decoder does and why each layer
exists.

## Stream layout

```
"fLaC"
metadata block*        STREAMINFO, PADDING, SEEKTABLE, VORBIS_COMMENT, PICTURE, ...
frame*                 header + subframes + padding + CRC-16
```

* `STREAMINFO` is mandatory and carries sample rate, channel count, bit depth,
  total sample count and the MD5 of the unencoded audio. `src/flac/metadata.mbt`
  parses it with the shared `BitReader` because the fields straddle byte
  boundaries (20 bits rate, 3 bits channels, 5 bits depth, 36 bits samples).
* `VORBIS_COMMENT` becomes `Array[(String, String)]` on `FlacInfo`, so callers can
  read `TITLE`, `ARTIST`, … without a second parser.
* Other blocks are inventoried in `FlacInfo.blocks` and skipped; a large
  `PADDING` or `PICTURE` block therefore costs nothing.

## Frame header

`parse_frame_header` reads, in order:

1. 14-bit sync code `0b11111111111110`, then the reserved bit (must be 0);
2. blocking strategy, block size code, sample rate code, channel assignment,
   sample size code, and the final reserved bit;
3. a UTF-8 style coded frame/sample number (1–7 bytes, extended to 36 bits);
4. optional 8/16-bit block size and sample rate escape values;
5. the header CRC-8, which the decoder recomputes over the header bytes.

Every reserved code (block size 0, sample rate 15, channel assignment 11–15,
sample size 3) raises `Invalid` rather than guessing.

## Subframes

`decode_subframe` handles the four kinds:

| Type | Payload |
| --- | --- |
| constant | one sample repeated for the whole block |
| verbatim | `block_size` raw samples |
| fixed 0–4 | warm-up samples + Rice residual, predictor coefficients are implicit |
| LPC 1–32 | warm-up samples + 4-bit precision + 5-bit shift + coefficients + residual |

Wasted bits are decoded first and re-applied after reconstruction
(`sample << wasted`), which is how FLAC stores signals whose low bits are always
zero.

Residual decoding (`decode_residual`) supports both Rice methods (4-bit and
5-bit parameters), any partition order, and escape partitions (raw fixed-width
residuals). The Rice → signed mapping is the zig-zag used by the specification:

```
value = (quotient << parameter) | remainder
sample = if value is odd { -((value >> 1) + 1) } else { value >> 1 }
```

## Channel decorrelation

For 2-channel frames the subframes store a transformed pair; `decorrelate`
inverts it:

| Assignment | Stored | Reconstruction |
| --- | --- | --- |
| 8 | left, side | `right = left - side` |
| 9 | side, right | `left = right + side` |
| 10 | mid, side | `mid = (mid << 1) | (side & 1)`, then `left = (mid + side) >> 1`, `right = (mid - side) >> 1` |

The side channel carries one extra bit, which is why `decode_frame` widens the
bit depth for that subframe.

## Verification

* **CRC-8** over the header catches a misread block size or sample rate before it
  can corrupt the subframe parse.
* **CRC-16** over the whole frame catches bit-stream misalignment at the end of
  the frame, which is exactly the failure mode a wrong Rice parameter produces.
* **Bit reader bounds** turn truncation into `Truncated` instead of a trap, so a
  cut-off file fails cleanly.

## How the tests build streams

`src/flac/flac_wbtest.mbt` contains an independent MSB-first **bit writer** and a
frame builder. It computes warm-up samples from real signals, derives the
residual by inverting the predictor, then writes header → subframes → padding →
CRC-16. The decoder must reconstruct the original integers exactly, and the
tests assert bit-exact equality.

That covers constant, verbatim, fixed 0–4, LPC, wasted bits, mid/side,
left/side, right/side, independent 3-channel frames, 8/12/16/20/24-bit streams,
frames with extended UTF-8 numbers, partitioned Rice with escape partitions,
variable block size streams, metadata comments, CRC rejection and truncation.

Known gap: the official `flac-test-files` corpus is not vendored (its smallest
subset files are hundreds of kilobytes). Running the decoder against that corpus
is tracked in the roadmap; the synthetic suite exercises every code path but is
not a substitute for real-world encoder variance.
