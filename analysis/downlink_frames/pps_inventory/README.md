# PPS marker inventory

This stage identifies RAW recordings containing an injected PPS pulse train in their first five seconds. It records marker availability and frequency estimates for subsequent synchronization. It does not align station recordings, count Ethernet frames, or calculate frame comparison metrics.

## Files and requirements

| File | Purpose |
| --- | --- |
| `pps_inventory_batch.m` | Select dates and analyze recordings from both stations |
| `pps_check_single_raw.m` | Inspect one RAW file and save detailed diagnostics |
| `pps_merge_results.m` | Merge partial PPS inventories from multiple runs or computers |
| `pps_tools.m` | Shared detector, result schema, reports, and plots |
| `pps_test_detector.m` | Synthetic detector tests and RAW input integration test |

Keep all five MATLAB files in the same folder and select that folder as the MATLAB Current Folder, or add it to the MATLAB path.

Requires MATLAB R2020b or later and Signal Processing Toolbox. Communications Toolbox and Parallel Computing Toolbox are not required for this stage.

## Batch workflow

1. Optionally run `pps_test_detector`. All assertions should pass.
2. In `pps_inventory_batch`, configure `dir_city`, `dir_village`, `analysis_start_date`, `analysis_end_date`, and `output_dir`. The date range includes both endpoints. Each input root must contain daily folders named `ddMMyy`, such as `250926`. RAW filenames follow `<index>_<HHMMSS>_<ddMMyy>.raw`.
3. Set `test_mode = true` and, for example, `max_test_files = 5` for an initial inspection. The limit applies separately to each station and includes files that produce errors. The supplied script currently has `test_mode = false`; enable test mode explicitly before a limited trial.
4. Run the complete script. Inspect `test_city_*.png` and `test_village_*.png` for approximately 100 ms pulses recurring every second and a narrow spectral line above the local background.
5. After checking the detector settings, set `test_mode = false` for the full selected date range.

Files with invalid filename timestamps are retained and analyzed. Their `File_Start_Time` is `NaT` and `Filename_Time_Valid` is false. Selection is determined by the daily folder containing the file.

When a companion JSON contains `sample_rate` or `center_freq`, these values are checked against the configuration. A mismatch is recorded as a separate error, rather than as a missing PPS marker.

## Single-file diagnostics

Run `pps_check_single_raw`, select a RAW recording, then choose where to save the diagnostic MAT file. The script uses the default configuration from `pps_tools` and inspects up to the first five seconds.

The MAT output contains `row`, `row_plain`, `detail`, `C`, and `runtime_info`. `row_plain` provides a structure with readable character representations of strings and timestamps. A CSV result is also written; a PNG is written when time-frequency diagnostics are available. Runtime diagnostics include the MATLAB version, resolved function paths, a double-precision `upfirdn` probe, and error details when available.

## Recording and detector configuration

| Parameter | Default |
| --- | --- |
| RAW format | Little-endian interleaved int16 I,Q |
| IQ normalization divisor | 32767 |
| RAW sample rate | 10 MHz |
| SDR / IF center frequency | 1312 MHz |
| Nominal injected marker IF | 1315 MHz |
| Frequency search interval | 1314.950 to 1315.050 MHz |
| Inspected interval | First `min(5 s, available RAW duration)` |
| Channel decimation | 50, yielding 200 kHz |
| STFT window | Periodic Hann, 4096 samples |
| STFT hop | 1000 samples, or 5 ms |
| FFT bin width | 48.828125 Hz |
| Minimum temporal contrast | 10 dB |
| Minimum line-to-background ratio | 10 dB |
| Expected pulse width | 100 ms |
| Accepted pulse widths | 40 to 250 ms |
| Minimum pulse count | 2 |
| Expected pulse period | 1 s |
| Period tolerance | 35 ms |
| Maximum accepted inter-pulse gap | 4 periods |

The marker frequency is measured directly in the recorded IF band. No LNB conjugation or LO-based RF conversion is applied to the marker.

The RAW file is read in blocks. Causal polyphase FIR decimation retains overlap and sampling phase across blocks. A continuous tone alone does not satisfy the pulse-train model; broadband pulses must also satisfy the narrow spectral-line criterion. Gaps of two, three, or four seconds are accepted when pulses are missing. Multiple comparably strong frequencies matching the model produce an `ambiguous` result.

The expected 100 ms width corresponds to the measurement setup. The detector accepts a wider range to accommodate detection at the configured STFT resolution. Check the settings against measured recordings before processing another setup. A periodic interfering line can mimic the pulse model: a positive result means that the configured detector criteria were met.

Fine frequency is estimated from the slope of unwrapped phase within each pulse, using separate phase intercepts. The reported estimate is the median across usable pulses. Its absolute accuracy depends on the SDR frequency reference, actual sample rate, generator stability, and SNR.

`Pulse_Frequency_Spread_Hz` is `1.4826 * MAD` of the per-pulse frequency estimates. It is not absolute frequency uncertainty and is `NaN` when fewer than two usable estimates are available. Selected frequency and dB metrics are rounded to three decimal places, and pulse times to microseconds. This is storage resolution, not measurement accuracy.

`Clipped_Sample_Fraction` counts complex samples for which at least one stored I/Q component has magnitude at least 32767. This is an indicator of digital scale endpoints; it does not independently establish physical ADC clipping.

## Outputs

Each batch run creates a new `PPS_TEST_<run_id>` or `PPS_FULL_<run_id>` folder.

| Output | Contents |
| --- | --- |
| `PPSInventory_*.mat` | Final `pps_results` dataset |
| `PPS_all_files.csv` | All attempted RAW analyses |
| `PPS_not_detected_city.txt` | City files with status `not_detected` |
| `PPS_not_detected_village.txt` | Village files with status `not_detected` |
| `PPS_ambiguous_and_errors.csv` | All statuses other than `present` and `not_detected` |
| `PPS_folder_coverage.csv` | Daily folder existence and discovered RAW file counts |
| `PPS_summary.txt` | Counts, frequency summaries, and interpretation limits |
| `PPS_overview.fig`, `PPS_overview.png` | Frequency offsets and status counts |
| `test_city_*.png`, `test_village_*.png` | Per-file diagnostics when enabled in test mode |
| `PPS_checkpoint.mat` | Intermediate state of the same analysis run |

### MAT structure

The MAT file contains one `pps_results` structure:

- `format_version = 1`
- `schema_name = 'iq_analysis_results'`, `schema_version = 1`
- `analysis_type = 'pps_marker_inventory'`
- `run_id`, `created_at`, and `metadata`
- `city` and `village`, each containing `source_directory`, `discovery`, `days`, and `data`

`metadata.detector` retains the full detector configuration for compatibility checks when merging. Requested dates and test-mode settings are stored separately.

`data` is a MATLAB table with one row per attempted RAW analysis. A table is used instead of a timetable so that files with invalid timestamps remain represented. `File_Start_Time` preserves the filename clock without timezone conversion; its timezone is unspecified.

`Measurement_ID` is `ddMMyy/filename.raw`, interpreted separately for each station. Drive letters and root paths are excluded. This assumes that the same station, day folder, and filename identify the same recording; it is not a cryptographic check of RAW contents.

Main result columns:

```text
Measurement_ID, Source_File, File_Name, Day_Folder, File_Start_Time
Filename_Time_Valid, File_Size_Bytes, Analyzed_Duration_s, Complete_First5s
Status, PPS_Detected, Pulse_Count, Candidate_Pulse_Count
Marker_IF_Hz, Marker_Offset_Hz, Pulse_Frequency_Spread_Hz
Coarse_Candidate_IF_Hz, FFT_Bin_Width_Hz, Max_Period_Residual_s
Median_Line_SNR_dB, Median_Temporal_Contrast_dB, Clipped_Sample_Fraction
Metadata_Status, Message
Pulse_Onsets_s, Pulse_Ends_s, Pulse_Frequencies_IF_Hz, Pulse_Line_SNR_dB
```

The last four columns contain vectors in cell arrays and are retained only in MAT outputs, rather than in the flattened CSV reports.

`discovery` lists all RAW files found in the requested daily folders, including files excluded by the test limit. `days` records whether each requested daily folder exists and how many RAW files it contains. A missing folder does not create fictitious files classified as missing PPS.

## Detection statuses

| Status | Meaning |
| --- | --- |
| `present` | One sufficiently strong candidate frequency has the required periodic pulse count; `PPS_Detected = true` |
| `not_detected` | The complete requested initial interval was processed without confirming a pulse train |
| `ambiguous` | Isolated pulses, unconfirmed periodicity, or multiple comparable candidates |
| `incomplete_window` | A shorter recording without positive PPS confirmation, or too few samples for STFT analysis |
| `empty_file`, `invalid_format`, `invalid_signal`, `read_error`, `invalid_metadata`, `metadata_mismatch`, `error` | The recording could not be evaluated normally |

A short file can still have status `present` if it contains enough qualifying pulses; `Complete_First5s` remains false. Failure to detect a marker at the configured thresholds does not prove its physical absence. Errors and ambiguous results are kept separate from `not_detected`.

`Pulse_Onsets_s` and `Pulse_Ends_s` are coarse STFT threshold-crossing estimates corrected for FIR group delay. They are starting points for subsequent correlation, rather than sample-accurate alignment timestamps. Clock drift and RF path delays require separate treatment during synchronization.

## Merging results

Keep all detector parameters `C.*` identical across computers. Split the requested dates and configure the relevant roots and output folders. After processing, run `pps_merge_results` and select the final `PPSInventory_*.mat` files using Ctrl/Shift, or populate `input_files` with absolute paths. Use this PPS-specific merger for these datasets.

The merger checks the data schema, complete detector configuration, and timestamp convention. Identical results for the same station and `Measurement_ID` are retained once. Different `Source_File` root paths are ignored. Conflicting file sizes, statuses, or metrics stop the merge. Summaries are recalculated from unique result rows; daily discovery inventories are retained separately per input to avoid summing overlapping days.

Checkpoints can also be merged if necessary. `is_complete_run = false` indicates an unfinished selected workload. A checkpoint normally need not be included alongside its final dataset. A true value means the selected workload completed; it does not establish complete campaign coverage. Test runs remain limited, and the minimum/maximum requested dates do not establish that every expected file or day was available.

## Included tests

`pps_test_detector` exercises positive and negative frequency offsets, noise only, a continuous tone, a single pulse, broadband pulses, competing tones, and a missing first pulse. It also creates a temporary interleaved int16 RAW file to exercise reading, filtering, and detection together.

Synthetic tests check detector behavior under the generated cases. Inspect measured recordings and their diagnostic plots to assess the configured thresholds for the actual measurement setup.
