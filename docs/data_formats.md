# Data Formats

## 1. Recording structure

Each measurement consists of two files with the same base name:

- **`.raw`** — Binary complex IQ samples.
- **`.json`** — Acquisition parameters, timestamps, sample count, and environmental metadata.

Recordings are grouped into daily directories using the `DDMMYY` date format. Separate parent directories identify the measurement site and campaign.

Archive paths are relative to the archive root. For example:

```text
2_Zlin_201026_251026/201026/581_000000_201026.raw
2_Zlin_201026_251026/201026/581_000000_201026.json
```

`Zlin` identifies the city station and `Hostalkova` the village station. The eight source-directory names and their campaign assignments are documented in [Recorded datasets](../data/README.md#archive-organization).

## 2. File naming convention

```text
N_HHMMSS_DDMMYY.raw
N_HHMMSS_DDMMYY.json
```

| Element | Meaning |
|---|---|
| `N` | Measurement counter within a recorder execution |
| `HHMMSS` | Local system time when the filename was generated |
| `DDMMYY` | Local calendar date |
| `.raw` / `.json` | IQ recording / metadata |

For example:

```text
1013_000000_250926.raw
1013_000000_250926.json
```

This pair represents measurement counter **1013**, with a filename timestamp of **25 September 2026 at 00:00:00 local time**.

The counter starts at 1 when the recorder is launched. It is not a globally unique identifier and must not be used alone to match recordings between stations. Preserve the site and campaign context alongside each filename.

The filename timestamp is generated before the acquisition loop begins. It may differ slightly from the more precise timestamp stored in the metadata.

## 3. Binary IQ format

The RAW file contains only sample data, with no header, embedded timestamps, or block separators.

| Property | Value |
|---|---|
| Stored component type | Signed 16-bit integer |
| Byte order | Little-endian on the Raspberry Pi acquisition platform |
| Component order | Interleaved I, Q |
| Bytes per component | 2 |
| Bytes per complex sample | 4 |
| Sampling rate | 10,000,000 complex samples/s |
| Recorded IF centre frequency | 1,312,000,000 Hz |

The stored sequence is:

```text
I₀, Q₀, I₁, Q₁, I₂, Q₂, …
```

The recorder requests complex float32 samples from SoapySDR. Each real and imaginary component is converted independently using:

```python
stored_component = (
    np.clip(component, -1.0, 1.0) * 32767
).astype(np.int16)
```

The conversion clips each component to `[-1, 1]`, scales it by 32767, and truncates it toward zero during integer conversion. Under this conversion, the intended stored range is `-32767` to `32767`.

The recorder uses NumPy's native byte order rather than explicitly specifying an endian format. Readers should use little-endian for files produced on the Raspberry Pi acquisition systems.

### Recovering normalized complex samples

Normalized samples are reconstructed as:

```text
x[n] = I[n] / 32767 + j · Q[n] / 32767
```

The normalization applies separately to I and Q. It does not imply that the complex magnitude is always less than or equal to 1.

## 4. Recording size and duration

At 10 MS/s with four bytes per complex sample:

```text
Data rate = 10,000,000 × 4 = 40,000,000 bytes/s
```

An exact 60-second recording would therefore occupy:

```text
2,400,000,000 bytes = 2.4 GB
```

The recorder controls acquisition duration using elapsed system time rather than a fixed target sample count. Actual sample counts and durations may therefore differ from the nominal 60 seconds.

For a file containing `N` complex samples:

```text
Expected file size in bytes = 4 × N
Sample-based duration in seconds = N / sample_rate
```

For the example metadata:

```text
N = 597,954,560 complex samples
Expected file size = 2,391,818,240 bytes
Sample-based duration = 59.795456 seconds
```

The sample-based duration describes the amount of stored signal. It does not independently establish uninterrupted acquisition if samples were lost during streaming.

## 5. JSON metadata

Example:

```json
{
    "start_iso": "2026-09-25T00:00:00.059963",
    "sample_rate": 10000000.0,
    "center_freq": 1312000000.0,
    "gain": 0,
    "format": "int16",
    "samples_recorded": 597954560,
    "start_unix": 1790287200.0599625,
    "write_error": false,
    "temperature_c": 10.13,
    "humidity_percent": 100.0,
    "env_valid": true
}
```

| Field | Meaning |
|---|---|
| `start_iso` | Local system time at the beginning of the acquisition loop, formatted as ISO 8601 without a timezone offset |
| `sample_rate` | Configured complex sampling rate in samples/s |
| `center_freq` | Configured SDR centre frequency in Hz, referring to IF after LNB conversion |
| `gain` | Overall gain value passed to the SoapySDR `setGain` call, in dB |
| `format` | Stored component type: `int16` |
| `samples_recorded` | Number of complex samples counted after successful write calls |
| `start_unix` | System-clock Unix timestamp captured at the beginning of the acquisition loop |
| `write_error` | Whether an `OSError` was caught during sample writing |
| `temperature_c` | Environmental temperature in °C, or `null` if unavailable |
| `humidity_percent` | Relative humidity in %, or `null` if unavailable |
| `env_valid` | Whether an environmental serial message was successfully parsed |

The metadata does not record individual SDR gain-stage settings, the LNB oscillator frequency, the station identity, or hardware timestamps. These must be obtained from the accompanying documentation and dataset context.

### Time interpretation

The filename and `start_iso` use the acquisition computer's local timezone. The supplied example is consistent with `Europe/Prague` summer time:

```text
2026-09-25 00:00:00.059963 local time
2026-09-24 22:00:00.059963 UTC
```

Use `start_unix` when comparing absolute times across datasets, converting it explicitly to UTC or the desired timezone.

The SDR stream is activated before `start_unix` is captured. This timestamp is therefore a software acquisition reference, not a verified timestamp of the first stored sample. Precise alignment uses recorded PPS markers and subsequent signal alignment.

### Return to standard time on 25 October 2026

The repeated local 02:00–02:59 hour was not acquired by the recorder. After a recording around 02:50 CEST, the next scheduled local time remained 03:00; the return to standard time therefore extended the wait to approximately 70 elapsed minutes. The archive does not contain an additional set of recordings for that repeated hour.

Preserve local filename timestamps and use `start_unix` to distinguish elapsed time from local wall-clock time. The catalog derives UTC only from explicit metadata timestamps; it does not assume an offset for ambiguous offset-free local times.

### Environmental metadata

Environmental data is read after IQ acquisition finishes. The values are associated with the recording but are not a continuous environmental time series or an average over the recording.

In this recorder version, `env_valid` indicates successful parsing. It does not verify sensor accuracy, physical plausibility, or reading age.

### Error interpretation

`write_error: false` means that no `OSError` was caught within the sample-writing block.

Negative SoapySDR read results are logged separately and are not included in this flag. The JSON therefore does not certify that the stream was free from overflows, missing samples, or other acquisition errors.

## 6. Frequency interpretation

The metadata centre frequency refers to IF after LNB conversion.

For an LNB oscillator frequency of 5150 MHz:

```text
RF frequency = 5150 MHz − IF frequency
```

| Signal | IF frequency | Corresponding RF frequency |
|---|---:|---:|
| Recording centre | 1312 MHz | 3838 MHz |
| Downlink 1 | 1311 MHz | 3839 MHz |
| Downlink 2 | 1308 MHz | 3842 MHz |
| Injected timing marker | 1315 MHz | Not a received satellite signal |

The timing marker is injected into the receiving path at IF. It must not be interpreted as an external transmission at the frequency obtained by applying the LNB conversion formula.

The LNB conversion reverses frequency ordering. RF plots must account for this when constructing and sorting their frequency axes.

## 7. MATLAB loading example

The following example reads a selected interval without loading the entire recording:

```matlab
raw_path = '1013_000000_250926.raw';
json_path = '1013_000000_250926.json';

meta = jsondecode(fileread(json_path));
fs = meta.sample_rate;

start_sec = 0;
duration_sec = 5;

start_sample = round(start_sec * fs);
num_samples = round(duration_sec * fs);

fid = fopen(raw_path, 'rb', 'ieee-le');
assert(fid >= 0, 'Cannot open RAW file.');
cleanup = onCleanup(@() fclose(fid));

status = fseek(fid, 4 * start_sample, 'bof');
assert(status == 0, 'Cannot seek to requested position.');

components = fread(fid, 2 * num_samples, 'int16=>double');
assert(numel(components) == 2 * num_samples, ...
    'The file does not contain the full requested interval.');

iq = complex(components(1:2:end), components(2:2:end)) / 32767;
```

The byte offset is four times the zero-based complex sample index.

## 8. Digital power reference

Some analysis scripts express power in dBFS relative to the recorder's normalized digital scale.

The reference is:

```text
P_ref = 1
```

A complex constant-envelope tone with `|IQ| = 1` has a total power of 0 dBFS under this convention.

This reference has not been verified against the physical full-scale input of the ADC. Values must not be interpreted as calibrated RF input power in dBm.

For spectral outputs, distinguish between power per FFT bin and power spectral density. The analysis script must document the window normalization, FFT length, bin width, and reference used.

## 9. Basic consistency checks

Before processing a recording:

- Confirm that the RAW and JSON filenames match.
- Verify that the RAW file size is divisible by four.
- Compare the file size with `4 × samples_recorded`.
- Calculate the available sample-based duration.
- Check `write_error` and environmental validity separately.
- Preserve station and campaign identifiers when pairing recordings.
- Use PPS markers for analyses requiring precise temporal alignment.

A matching file size confirms structural consistency with the sample count; it does not independently prove continuous acquisition.

## 10. Analysis output formats

Output formats and field definitions are documented alongside the individual analysis scripts and result directories.

See:

- [`../analysis/`](../analysis/) — Processing scripts and output definitions.
- [`../results/`](../results/) — Tables, figures, and other analysis products.
- [`analysis_workflow.md`](analysis_workflow.md) — Processing sequence and dependencies.

## 11. Public IQ excerpts

Short examples are derived files with `_excerpt.raw` and `_excerpt.json` names. Their JSON uses the `iq_excerpt_metadata` schema, records the actual excerpt sample count and source-relative sample offset, and preserves original timestamps in `source_*` fields. A separate `*_source.json` retains the original recording metadata byte-for-byte.

These excerpts are not original full recorder files and are not automatically discovered by the full-recording batch filename pattern. Load them explicitly using the excerpt JSON and a zero start offset. Equal nominal times and equal sample offsets do not establish PPS-assisted inter-station synchronization. See [Short IQ examples](../data/examples/README.md) for generation and timing conventions.
