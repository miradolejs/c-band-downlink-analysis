# IQ excerpts (not published)

Short IQ excerpts are **not published** in this repository. They contain raw I/Q samples with a decodable third-party satellite signal that is not intended for the public. In line with the project application, raw IQ data with a decodable signal are not made publicly available.

Excerpts can be provided **non-publicly**, for example to ESA together with the full IQ archive. See [data access](../data_access.md).

## Format

Excerpts are generated as a city/village pair from the same nominal recording time with [extract_iq_examples.py](../tools/extract_iq_examples.py). Each excerpt normally contains one second of unmodified interleaved little-endian int16 I/Q (40,000,000 bytes per station at 10 MS/s), plus metadata:

| File | Contents |
| --- | --- |
| `city/<source_stem>_excerpt.raw` | Extracted city I/Q samples |
| `city/<source_stem>_excerpt.json` | Excerpt metadata (`iq_excerpt_metadata` schema), sample offset, length, and RAW hash |
| `city/<source_stem>_source.json` | Byte-for-byte copy of the original recording JSON |
| `village/…` | Equivalent village files |
| `pair_manifest.json` | Shared selection, source identification, and timing limitations |
| `checksums.sha256` | Hashes of the generated files |

A default start offset of 10 s places the excerpt after the initial PPS marker interval. The same sample offset is used for both stations; excerpts are not additionally aligned using PPS or cross-correlation. The tool does not resample, normalize, filter, demodulate, or change the sample values.

Original software timestamps are kept as `source_start_iso` and `source_start_unix`; they are not verified first-sample timestamps. For MATLAB, the [binary loading example](../../docs/data_formats.md#7-matlab-loading-example) applies with `start_sec=0`, `duration_sec=1`, and the excerpt paths.

Write generated excerpts to a directory **outside** this repository. The repository `.gitignore` blocks excerpt files as a safeguard.
