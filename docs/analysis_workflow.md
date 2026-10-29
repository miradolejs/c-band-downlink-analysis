# Analysis Workflow

## 1. Overview

The analysis compares C-band satellite downlink reception at the urban station in Zlín and the rural reference station in Hošťálková.

Processing is organized into complementary branches:

- Spectrogram inspection and broadband interference detection.
- Noise statistics, downlink SNR, and environmental comparisons.
- Selected downlink demodulation and PCAP export.
- PPS-assisted alignment and long-term comparison of recovered frames.

These branches do not form a single sequential pipeline. Some analyses operate directly on RAW recordings, while others require previously generated MAT datasets.

## 2. Software and input preparation

The scripts use MATLAB. Spectral processing and PPS detection require Signal Processing Toolbox. Downlink decoding and paired frame analysis additionally require Communications Toolbox.

Before running an analysis:

1. Set the urban and rural recording directories.
2. Select the analysis dates or individual recordings.
3. Check the sampling rate, IF centre frequency, and LNB oscillator frequency.
4. Set the analyzed time intervals, frequency bands, and output directory.
5. Keep supporting functions available on the MATLAB path.
6. Preserve the configuration used to generate each published result.

The supplied scripts contain local Windows paths and example date ranges. These must be adapted to the dataset being processed.

Input files are interleaved little-endian `int16` IQ recordings with associated JSON metadata. See [`data_formats.md`](data_formats.md).

## 3. Processing dependencies

| Analysis | Required inputs | Main output |
|---|---|---|
| Spectrogram comparison | Selected RAW recording from each station | Paired spectrogram figure |
| Short-interval peak detection | Selected RAW recording | Spectrogram with detections and threshold plot |
| Long-term broadband peak analysis | RAW recordings over selected dates | `impulse_results` MAT dataset and figures |
| Noise statistics | RAW recordings over selected dates | `noise_results` MAT dataset |
| Downlink SNR | RAW recordings and matching `noise_results` | `snr_results` MAT dataset and figures |
| Temperature–noise comparison | `noise_results` and recording JSON files | `temp_noise_results` MAT dataset and figure |
| Result merging | Compatible MAT datasets of one analysis type | Combined dataset and figures |
| PPS inventory | Beginning of each RAW recording | `pps_results` MAT dataset, CSV inventories, and figures |
| Standalone downlink decoding | Selected RAW recording interval | PCAP, MAT diagnostics, and text summary |
| Long-term frame comparison | Paired RAW recordings, PPS inventory, and SNR dataset | Frame observations, CSV tables, audits, and MAT results |
| Frame-summary visualization | CSV outputs from one frame-analysis run | Summary tables and PNG/PDF/FIG figures |

The principal execution sequences are:

- **Noise statistics → SNR**
- **Noise statistics + JSON metadata → temperature–noise comparison**
- **PPS inventory + SNR + paired RAW recordings → long-term frame comparison → summary visualization**

Standalone PCAP export is independent of the long-term frame comparison.

## 4. Shared spectral conventions

The spectrogram, broadband peak, noise-statistics, and SNR scripts normalize stored IQ components by **32767** and use a recorder-scale power reference of **1**. These spectral conventions do not describe every normalization step inside the downlink decoders.

For the supplied spectral configuration:

| Parameter | Value |
|---|---|
| Sampling rate | 10 MS/s |
| IF centre frequency | 1312 MHz |
| LNB oscillator frequency | 5150 MHz |
| Window | Kaiser, β = 5 |
| Window length | 8192 samples |
| FFT length | 8192 |
| Overlap | 4096 samples |
| FFT bin spacing | Approximately 1220.7 Hz |
| STFT time step | 0.4096 ms |

Normalized FFT-bin power is calculated as:

```text
P_bin = |STFT|² / (NFFT × sum(|window|²))
```

Frequency conversion follows:

```text
RF = LO − IF
```

The resulting frequency reversal must be accounted for when displaying RF spectra.

The dBFS reference describes the recorder's digital scale. A complex constant-envelope tone with `|IQ| = 1` has total power 0 dBFS under this convention. Physical ADC full scale has not been verified, and these values are not calibrated RF input power in dBm. Noise-level standard deviation is a spread in dB, rather than a power level in dBFS.

## 5. Spectrogram inspection and broadband interference

### 5.1. Paired spectrogram comparison

**Script:** `compare_spectrograms_dbfs.m`  
**Repository directory:** [`../analysis/spectrogram_comparison/`](../analysis/spectrogram_comparison/)

This script reads selected intervals from both stations and displays their spectrograms using a common colour scale.

The colour limits can be fixed manually or derived automatically from the rural recording. Fixed limits support visual comparisons between separate runs.

The figure is generated interactively; this script does not automatically export it. The displayed time axes are relative to each recording start, without PPS-based alignment.

### 5.2. Short-interval peak inspection

**Script:** `detect_broadband_peaks_dbfs.m`  
**Repository directory:** [`../analysis/broadband_peaks_mark_in_spectrogram/`](../analysis/broadband_peaks_mark_in_spectrogram/)

This script averages linear FFT-bin power over selected noise-reference frequencies, converts the resulting time series to dBFS, and detects local maxima above a threshold.

Set `file_recorded` to a RAW file from either station. The script displays detections alongside the spectrogram and the mean-bin-power trace. It generates the figure interactively without automatically exporting it.

Set `threshold_dbfs` directly, or leave it empty to convert the configured unnormalized threshold to the recorder-referenced mean FFT-bin power scale.

The supplied reference band is **3836.5–3837.5 MHz RF**. The minimum peak separation is configured in STFT time steps, rather than raw IQ samples.

### 5.3. Long-term peak counts

**Script:** `analyze_broadband_impulses_dbfs.m`  
**Repository directory:** [`../analysis/broadband_peaks/`](../analysis/broadband_peaks/)

The batch script applies the peak detector across daily recording directories at both sites.

The supplied configuration processes eleven five-second chunks per recording, beginning at zero seconds. The main metric is:

```text
Peaks_per_5s
```

Outputs include the `impulse_results` MAT dataset and FIG/PNG figures.

Detection is performed independently in each chunk; events crossing chunk boundaries are subject to that processing boundary. These values count detected local maxima under the selected threshold and separation settings. They do not directly count independent transmitters or establish the full duration of interference events.

## 6. Noise statistics

**Script:** `analyze_noise_statistics_dbfs.m`  
**Repository directory:** [`../analysis/noise_statistics/`](../analysis/noise_statistics/)

For each analyzed chunk, the script:

1. Computes the STFT.
2. Selects bins within the configured noise-reference bands.
3. Averages their power in the linear domain at each STFT time step.
4. Converts that time series to dBFS.
5. Calculates its median and standard deviation.

The supplied configuration uses **3836.5–3837.5 MHz RF** and ten consecutive five-second chunks beginning five seconds into each recording.

The output MAT file contains `noise_results`, including processing metadata and separate urban and rural timetables.

The principal metrics are:

- `Median_Noise_dB` — Median of the logarithmic noise-level time series.
- `Noise_Std_dB` — Standard deviation of that logarithmic time series, expressed in dB.

This dataset is required by the SNR and temperature–noise scripts.

## 7. Downlink SNR

**Script:** `analyze_downlink_snr_ready.m`  
**Repository directory:** [`../analysis/snr/`](../analysis/snr/)

This script loads `noise_results` and processes the corresponding RAW intervals using compatible spectral settings.

For each downlink band:

- `T` is the temporal median of the summed FFT-bin power.
- `N` is the estimated noise power, obtained by scaling the reference noise-bin power by the number of selected downlink bins.
- Estimated signal power is `T − N`.

The reported estimate is:

```text
SNR_dB = 10 × log10((T − N) / N)
```

Non-positive estimated signal power does not yield a valid finite SNR.

The supplied integration bands are:

| RF centre frequency | Integration bandwidth |
|---|---:|
| 3839 MHz | 1 MHz |
| 3842 MHz | 0.5 MHz |

The **1 MHz integration bandwidth** for the first signal differs from its approximately **2 MHz occupied bandwidth** described in the project overview. These quantities must remain distinguished when reporting results.

The method assumes that noise in the reference band represents noise within the selected downlink band. It does not separate additional in-band interference from the estimated signal contribution.

Outputs include `snr_results` and FIG/PNG figures.

## 8. Temperature–noise comparison

**Scripts:**

- `analyze_temperature_noise_city_dbsf.m`
- `analyze_temperature_noise_village_dbsf.m`

**Repository directory:** [`../analysis/noise_temperature/`](../analysis/noise_temperature/)

These scripts use previously calculated noise statistics and match each chunk to the JSON metadata of its source recording.

One temperature value is associated with all analyzed chunks from that recording. It is not an independent temperature measurement for every chunk.

Unavailable or invalid temperatures remain missing and receive a status label. Values are not interpolated.

Each script saves a `temp_noise_results` MAT dataset and, when `save_figures` is enabled, FIG and PNG figures. No RAW IQ samples are read by these temperature–noise scripts.

## 9. Combining analysis periods

**Script:** `merge_iq_analysis_results.m`  
**Repository directory:** [`../analysis/utilities/`](../analysis/utilities/)

This utility combines compatible MAT datasets without rereading RAW recordings.

Supported datasets include:

- Noise statistics.
- Downlink SNR.
- Broadband peak counts.
- Urban temperature–noise results.
- Rural temperature–noise results.

Only one compatible analysis type is combined per run. The utility checks processing metadata before merging.

It can be used to assemble results from separately processed periods, provided their settings are compatible. Rows with identical timestamps and matching values are retained once; conflicting values stop the merge. Source-file paths are excluded from duplicate comparisons because the same recording can have different paths on different computers. Urban and rural temperature–noise datasets remain separate analysis types.

PPS inventories use their own merger, `pps_merge_results.m`, rather than this utility. Long-term frame-analysis results are not supported by either merger.

## 10. PPS inventory

**Main script:** [`pps_inventory_batch.m`](../analysis/downlink_frames/pps_inventory/pps_inventory_batch.m)  
**Shared functions:** `pps_tools.m`  
**Repository directory:** [`../analysis/downlink_frames/pps_inventory/`](../analysis/downlink_frames/pps_inventory/)

The inventory inspects up to the first five seconds of each RAW recording for the injected **1315 MHz IF** marker. This marker is measured directly in the recorded IF band; it is not converted to RF using the LNB oscillator frequency.

Detection combines a narrow spectral line with temporal contrast, line-to-background ratio, accepted pulse widths, and repetition. The expected width is 100 ms and the period is 1 second. The default detector accepts widths from 40 to 250 ms and requires at least two qualifying pulses. Each attempted recording receives a table row, including uncertain detections and errors. Invalid filename times are retained as `NaT`.

Configure the station roots, inclusive start/end dates, and output directory in `pps_inventory_batch.m`. Set `test_mode=true` for a limited run and use `max_test_files` to set the limit separately for each station. The supplied configuration has test mode disabled. Per-file diagnostic PNGs are generated in test mode when enabled.

| Script | Purpose |
|---|---|
| `pps_inventory_batch.m` | Batch inventory for the selected dates and stations |
| `pps_check_single_raw.m` | Inspect one recording and save detailed diagnostics |
| `pps_merge_results.m` | Combine compatible PPS inventory MAT files |
| `pps_test_detector.m` | Synthetic detector checks and RAW input integration test |
| `pps_tools.m` | Shared detector, result schema, exports, and plots |

The batch output directory contains:

| Output | Purpose |
|---|---|
| `PPSInventory_*.mat` | Final `pps_results` dataset |
| `PPS_checkpoint.mat` | Intermediate state of the same run |
| `PPS_all_files.csv` | All attempted recording analyses |
| `PPS_not_detected_city.txt` / `PPS_not_detected_village.txt` | Files classified as `not_detected` |
| `PPS_ambiguous_and_errors.csv` | Cases other than `present` and `not_detected` |
| `PPS_folder_coverage.csv` | Daily folder existence and discovered RAW counts |
| `PPS_summary.txt` | Counts, frequency estimates, and interpretation limits |
| `PPS_overview.fig` / `PPS_overview.png` | Frequency-offset and status summaries |
| `test_city_*.png` / `test_village_*.png` | Per-file plots when enabled in test mode |

PPS inventory timing consists of coarse STFT edge estimates corrected for FIR group delay. It is not sample-accurate alignment. `not_detected` means the pulse train was not confirmed under the configured criteria; errors and ambiguous cases remain separate.

`pps_merge_results.m` validates the schema and detector settings and deduplicates by station and `Measurement_ID`, excluding root-path differences. Conflicting results stop the merge. The inventory accepts two qualifying pulses, but the frame-analysis stage below requires four complete consecutive final pulses and can therefore reject an inventory row marked `present`.

See the [PPS inventory README](../analysis/downlink_frames/pps_inventory/README.md) for the complete data schema and detector settings.

## 11. Standalone downlink decoding and PCAP export

**Function:** [`decode_downlink_to_pcap.m`](../analysis/downlink_frames/demodulation_pcap/decode_downlink_to_pcap.m)  
**Repository directory:** [`../analysis/downlink_frames/demodulation_pcap/`](../analysis/downlink_frames/demodulation_pcap/)

This decoder is configured for the observed **3839 MHz** downlink, using BPSK at a nominal symbol rate of **1.024 Msymbol/s**.

Processing includes channel extraction, carrier and symbol timing recovery, Viterbi decoding, descrambling, recovery of the `496 + 16*(280+9)` multiplex, and HDLC FCS checking.

Run interactively to select a RAW file and decode the default 15–20 second interval:

```matlab
decode_downlink_to_pcap
```

Alternatively, specify the recording, start offset, and duration:

```matlab
R = decode_downlink_to_pcap('D:\data\recording.raw', 25, 5);
```

Outputs are written to a new directory beside the input RAW file:

- `ethernet.pcap` — Recovered Ethernet frames passing the HDLC FCS check, with that FCS removed. This file is created only when eligible frames are recovered.
- `analysis.mat` — Decoded data and diagnostics.
- `summary.txt` — Configuration, results, and timing limitations.

PCAP timestamps are relative estimates based on nominal symbol timing and position in the multiplex. Their absolute calendar dates do not represent the measurement date, and the timestamps do not establish exact network packet reception or transmission times.

The decoder is specific to the observed signal. The physical-layer standard and specific modem are not identified. FEC re-encoding disagreement and HDLC CRC ratios are diagnostic quantities, rather than estimates of BER or network packet loss.

## 12. Long-term paired frame analysis

**Entry point:** [`run_frame_analysis.m`](../analysis/downlink_frames/long_term_analysis/run_frame_analysis.m)  
**Main function:** `analyze_frames.m`  
**Defaults:** `frame_config.m`  
**Resume function:** `resume_frame_analysis.m`  
**Repository directory:** [`../analysis/downlink_frames/long_term_analysis/`](../analysis/downlink_frames/long_term_analysis/)

Required inputs are urban and rural RAW recording roots, a PPS inventory MAT file, and a compatible SNR MAT dataset. Both stations must have usable PPS observations for a pair to proceed.

### 12.1. Date selection and test mode

Set paths and inclusive calendar date bounds in `run_frame_analysis.m`:

```matlab
C.analysisStartDate = datetime(2026,9,25);
C.analysisEndDate = datetime(2026,9,30);
```

These are example bounds. Change them to select any interval covered by the inputs. Use the same date for a single day, or set both to `[]` to select all dates available in the inventory.

`frame_select_dates.m` filters by the date encoded in each RAW filename, without timezone conversion. Invalid filename dates are excluded with a warning when date filtering is active. Optional `C.fileNames` further restricts the selected recordings. Date selection precedes explicit filename filtering and the test-pair limit; it does not imply complete measurement coverage.

For a limited test run, set:

```matlab
test_mode = true;
max_test_pairs = 5;
```

The test runs the same processing logic on at most the first five selected candidate filenames, including candidates that are subsequently excluded or fail. It follows inventory-name ordering and is not a random sample or a guarantee of five successful pairs. Use `C.fileNames` to target specific recordings.

Set `test_mode=false` for all selected candidates. Each launch creates a new `results/FRAME_TEST_<timestamp>` or `results/FRAME_FULL_<timestamp>` folder alongside the scripts.

### 12.2. Stable-second selection

The launcher requests the first **10 confirmed stable seconds** per pair. At least **5 selected seconds must be successfully decoded** for the pair to contribute frame counts. Confirmed runs contain at least three consecutive stable seconds; the final selection can span separate accepted runs. Additional synchronized and decoded context seconds can be needed outside the reported selection.

Configure this using `C.firstStableSeconds` and `C.minimumStableSeconds`. The selected report seconds are fixed before decoding; failed selected seconds are not replaced by later context seconds.

For all available whole seconds after PPS, set `C.firstStableSeconds=0` and `C.analysisIntervalS=[]`. For a fixed interval instead, set `C.firstStableSeconds=0` and, for example, `C.analysisIntervalS=[5 15]` to report blocks starting at 5 through 14 seconds on the city RAW axis.

The default long-term mode is a survey of selected stable intervals. It is neither full decoding of every minute-long recording nor a random time sample.

### 12.3. Processing

1. Pair inventory filenames, retain missing counterparts for the exclusion audit, and validate RAW inputs.
2. Select the final four complete consecutive PPS pulses at both stations and estimate the coarse delay.
3. Apply joint whole-record SNR screening where its criteria are satisfied.
4. Estimate local delay and drift from downlink cross-correlation using three probes per second.
5. Identify stable runs and select report seconds with supporting context.
6. Decode each station independently, with symbol-timing consistency checks.
7. Match frame occurrences using complete byte equality and compatible synchronized timing.
8. Reconcile observations from overlapping decode windows within stable runs.
9. Export per-second results, summaries, checkpoints, and audit information.

Low city SNR alone does not exclude a pair. Whole-record screening requires low SNR at both stations, sufficient valid coverage, and the configured burst-protection conditions. Per-second screening also skips blocks only when both stations are classified as likely noise. The campaign-specific noise calibration interval is configured in `frame_config.m`; update it or disable calibration for another campaign. The pair-date filter does not trim the SNR dataset used for calibration.

Frame starts are assigned conservative timing intervals. Context and boundary guards exclude uncertain assignments from both stations. Repeated transmissions of identical bytes remain separate occurrences; duplicate observations from overlapping windows are reconciled.

### 12.4. Outputs and interpretation

| Output | Purpose |
|---|---|
| `run_config.mat` | Saved configuration, date selection, and input/source compatibility signatures |
| `snr_calibration.mat` | SNR classification information |
| `*_frames.mat` | Per-pair observations, synchronization models, decoder diagnostics, and frame bytes |
| `*_seconds.csv` | Selected per-second results |
| `*_all_blocks.csv` | All planned blocks and selection/context flags where exported |
| `pair_audit.csv` | Pair statuses, exclusions, SNR coverage, selected/analyzed seconds, and processing times |
| `all_seconds.csv` | Combined reported per-second results |
| `summary.csv` / `summary.mat` | Aggregate counts, ratio, and pair totals |

The key counts are `City_Total`, `Village_Total`, `Common`, `City_Only`, and `Village_Only`. Matching is one to one between compatible occurrences.

```text
Common_Over_Village = Common / Village_Total
```

The aggregate ratio is `sum(Common) / sum(Village_Total)` over successfully analyzed report seconds. It is not the arithmetic mean of per-second ratios. A zero denominator gives an undefined ratio.

This metric describes shared decoded observations relative to frames recovered at the rural station. It is not end-to-end network packet loss or BER. Counts refer to safely assignable occurrences inside the accepted intervals and guards, rather than a guaranteed complete inventory of every frame in the full recording.

Missing, rejected, and unreliable intervals retain `NaN` counts and remain distinct from successfully analyzed intervals with zero recovered frames. Inspect per-second statuses and decoder diagnostics even when the pair audit reports `processed`. `Excluded_Seconds` covers excluded rows in the reported selection, rather than all unprocessed campaign time or complete missing pairs.

### 12.5. Resume an interrupted run

Run:

```matlab
R = resume_frame_analysis;
```

Select the existing output directory containing `run_config.mat`, or pass that directory directly to the function. The saved configuration is restored and compatible completed steps are reused. Running `run_frame_analysis` again starts a new run.

Keep source files, inputs, date bounds, and processing settings consistent when resuming. Changes to the analysis configuration require a new output folder. Compatibility signatures use sizes and modification times rather than cryptographic hashes. Completed decode-error blocks are not automatically retried.

See the [long-term analysis README](../analysis/downlink_frames/long_term_analysis/README.md) for the detailed acceptance criteria, SNR screening, timing guards, and file roles.

## 13. Summary visualization of long-term frame analysis

**Function:** [`plot_frame_analysis_summary.m`](../analysis/downlink_frames/visualization/plot_frame_analysis_summary.m)  
**Repository directory:** [`../analysis/downlink_frames/visualization/`](../analysis/downlink_frames/visualization/)

This function summarizes completed CSV results without rereading RAW recordings or repeating synchronization and decoding. It supports the selected date range in either a full or limited test run, provided at least one analyzed second is available. MATLAB R2020b or later is required, without additional toolboxes.

Select one output folder containing `all_seconds.csv`, `pair_audit.csv`, and optionally `summary.csv`. All inputs must originate from the same run.

```matlab
R = plot_frame_analysis_summary;
```

Or specify the input and output folders:

```matlab
R = plot_frame_analysis_summary( ...
    'D:\results\FRAME_FULL_run', ...
    'D:\results\frame_figures');
```

By default, outputs are saved in a timestamped `FIGURES_<timestamp>` subfolder of the input directory.

The function validates duplicate identifiers and frame-count identities, then aggregates rows with `Status = analyzed`. Record-level SNR comes from the pair audit when its columns exist; otherwise finite per-second SNR values are averaged in the linear domain. Date labels use the filename clock without timezone conversion.

| Figure | Content |
|---|---|
| `01_time_series` | Recording-level agreement, station SNR, and frame counts per analyzed second |
| `02_daily_summary` | Daily agreement and frame counts per analyzed second |
| `03_snr_relationship` | Agreement versus SNR, colored by day |
| `04_coverage` | Daily analyzed pairs and SNR, PPS, or other exclusions |
| `05_within_record_variability` | Variation across defined per-second agreement percentages |

Each figure is saved as PNG at 250 dpi, vector PDF, and editable FIG. Machine-readable outputs are `records_summary.csv`, `daily_summary.csv`, `global_summary.csv`, and `graph_summary.mat`.

Recording, daily, and global ratios use `sum(Common) / sum(Village_Total)`. Zero denominators remain undefined. Within-record variability is a standard deviation in percentage points and requires at least two defined per-second ratios; zero-village-frame seconds are excluded from that statistic.

Frame rates and variability refer only to the selected analyzed seconds. Coverage is relative to pairs in the audit, and SNR labels assume the supplied 1 MHz integration band. The figures preserve decoder results and do not independently establish the cause of interference.

See the [visualization README](../analysis/downlink_frames/visualization/README.md) for input handling and interpretation details.

## 14. Publication of analysis results

For each published result set, retain:

- Input period and station identifiers.
- Processing configuration and code version.
- Machine-readable result datasets.
- Figures and captions.
- Coverage and exclusion information.
