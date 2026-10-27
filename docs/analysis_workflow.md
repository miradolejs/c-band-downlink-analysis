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

The principal execution sequences are:

- **Noise statistics → SNR**
- **Noise statistics + JSON metadata → temperature–noise comparison**
- **PPS inventory + SNR + paired RAW recordings → frame comparison → summary visualization**

Standalone PCAP export is independent of the long-term frame comparison.

## 4. Shared spectral conventions

The spectral scripts normalize stored IQ components by **32767** and use a recorder-scale power reference of **1**.

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

The dBFS reference describes the recorder's digital scale. It is not a calibrated measurement of RF input power in dBm.

## 5. Spectrogram inspection and broadband interference

### 5.1. Paired spectrogram comparison

**Script:** `compare_spectrograms_dbfs.m`  
**Repository directory:** [`../analysis/spectrogram_comparison/`](../analysis/spectrogram_comparison/)

This script reads selected intervals from both stations and displays their spectrograms using a common colour scale.

The colour limits can be fixed manually or derived automatically from the rural recording. Fixed limits support visual comparisons between separate runs.

The figure is generated interactively; this script does not automatically export it. The displayed time axes are relative to each recording start, without PPS-based alignment.

### 5.2. Short-interval peak inspection

**Script:** `detect_broadband_peaks_dbfs.m`  
**Repository directory:** [`../analysis/broadband_bursts/`](../analysis/broadband_bursts/)

This script averages linear FFT-bin power over selected noise-reference frequencies, converts the resulting time series to dBFS, and detects local maxima above a threshold.

It displays the detections alongside the spectrogram for inspection.

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

These values count detected local maxima under the selected threshold and separation settings. They do not directly count independent transmitters or establish the full duration of interference events.

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

Each script saves a `temp_noise_results` MAT dataset and, when enabled, a PNG figure.

## 9. Combining analysis periods

**Script:** `merge_iq_analysis_results.m`

This utility combines compatible MAT datasets without rereading RAW recordings.

Supported datasets include:

- Noise statistics.
- Downlink SNR.
- Broadband peak counts.
- Urban temperature–noise results.
- Rural temperature–noise results.

Only one compatible analysis type is combined per run. The utility checks processing metadata before merging.

It can be used to assemble results from separately processed periods, provided their settings are compatible.

## 10. PPS inventory

**Main script:** `pps_inventar_batch.m`  
**Supporting functions:** `pps_nastroje.m`  
**Repository directory:** [`../analysis/downlink_frames/pps_inventory/`](../analysis/downlink_frames/pps_inventory/)

The inventory inspects up to the first five seconds of each RAW recording for the injected **1315 MHz IF** marker.

Detection uses frequency-domain and temporal criteria, including pulse width, contrast, and repetition. Each attempted recording receives an inventory row, including unsuccessful or uncertain detections.

Outputs include:

- `pps_results` MAT dataset and checkpoints.
- `PPS_vsechny_soubory.csv` — Recording-level inventory.
- `PPS_nejasne_a_chyby.csv` — Uncertain cases and errors.
- `PPS_pokryti_slozek.csv` — Directory coverage.
- Summary figures.

PPS inventory timing is a coarse reference. It does not provide sample-accurate edge estimates by itself.

Use `pps_sloucit_vysledky.m` to combine compatible PPS inventories. Single-recording inspection and detector-check utilities are supplied alongside the batch script.

## 11. Standalone downlink decoding and PCAP export

**Script:** `c_downlink_do_wiresharku.m`  
**Repository directory:** [`../analysis/downlink_frames/demodulation_pcap/`](../analysis/downlink_frames/demodulation_pcap/)

This decoder is configured for the observed **3839 MHz** downlink, using BPSK at a nominal symbol rate of **1.024 Msymbol/s**.

Processing includes channel extraction, carrier and symbol timing recovery, Viterbi decoding, descrambling, multiplex recovery, and HDLC frame checking.

Outputs are written to a new directory beside the input RAW file:

- `ethernet.pcap` — Recovered Ethernet frames passing the HDLC FCS check, with that FCS removed.
- `analyza.mat` — Decoded data and diagnostics.
- `souhrn.txt` — Configuration, results, and timing limitations.

PCAP timestamps are relative estimates based on nominal symbol timing and multiplex position. Their absolute calendar dates do not represent the measurement date or original network transmission time.

The decoder is specific to the observed signal; it is not a general DVB-S2 decoder.

## 12. Long-term paired frame analysis

**Entry point:** `spustit_analyzu_6_dni.m`  
**Main function:** `analyza_ramcu.m`  
**Configuration:** `frame_config.m`  
**Repository directory:** [`../analysis/downlink_frames/long_term_analysis/`](../analysis/downlink_frames/long_term_analysis/)

Required inputs are:

- Urban and rural RAW recording roots.
- A PPS inventory MAT file.
- A compatible SNR MAT dataset.

The supplied six-day launcher selects **25–30 September 2026**. It requests the first ten confirmed stable seconds per pair, with a minimum of five stable seconds.

Processing includes:

1. Pairing recordings and validating PPS observations.
2. SNR-based screening and classification.
3. Coarse alignment from PPS markers.
4. Fine alignment and drift estimation using cross-correlation.
5. Selection of stable intervals.
6. Independent decoding at both stations.
7. Matching recovered frames by byte content and compatible timing.
8. Reconciliation of overlapping decoding intervals.
9. Export of counts, statuses, and audit information.

Principal outputs include:

| Output | Purpose |
|---|---|
| `run_config.mat` | Run configuration and input/source signatures |
| `snr_calibration.mat` | SNR classification information |
| `*_frames.mat` | Per-recording frame observations and diagnostics |
| `*_seconds.csv` | Selected per-second results |
| `*_all_blocks.csv` | Additional block-level results where exported |
| `pair_audit.csv` | Pair processing statuses and exclusions |
| `all_seconds.csv` | Combined selected per-second results |
| `summary.csv` / `summary.mat` | Aggregate results |

Use `pokracovat_analyzu_ramcu.m` to resume an existing run.

The key counts are `City_Total`, `Village_Total`, `Common`, `City_Only`, and `Village_Only`.

```text
Common_Over_Village = Common / Village_Total
```

This ratio describes shared observations relative to frames recovered at the rural station. It is not an end-to-end network packet-loss measurement or a bit-error rate.

Missing, rejected, and unreliable intervals must remain distinct from successfully analyzed intervals containing zero recovered frames.

## 13. Summary visualization of long-term frame analysis

**Script:** `vykreslit_souhrn_6_dni.m`  
**Repository directory:** [`../analysis/downlink_frames/visualization/`](../analysis/downlink_frames/visualization/)

This script summarizes completed frame-analysis results without rereading RAW recordings or repeating synchronization and decoding.

It requires MATLAB R2020b or newer, with no additional toolboxes.

### Inputs and execution

Select the output directory of a single frame-analysis run containing:

- `all_seconds.csv` — Per-second results.
- `pair_audit.csv` — Recording-pair statuses and record-level SNR.
- `summary.csv` — Optional aggregate results used for a consistency check.

All input tables must originate from the same run.

Run interactively:

```matlab
R = vykreslit_souhrn_6_dni;
```

Alternatively, specify the input and output directories:

```matlab
R = vykreslit_souhrn_6_dni( ...
    'D:\results\FRAME_6D_run', ...
    'D:\results\frame_figures');
```

Without an explicit output directory, the script creates a timestamped `GRAFY_...` subdirectory within the input directory.

### Processing

The script checks recording and second identifiers for duplicates, validates frame-count identities, and aggregates rows with `Status = analyzed`.

Record-level SNR is taken from `pair_audit.csv` when the corresponding columns exist. Otherwise, available per-second SNR values are averaged in the linear domain and converted back to dB.

Recording, daily, and global frame-agreement ratios are calculated as:

```text
Common / village = sum(Common) / sum(Village_Total)
```

They are not arithmetic averages of individual percentages. Ratios with a zero denominator remain undefined.

Times are parsed from RAW filenames without timezone conversion.

### Generated figures

| Figure | Content |
|---|---|
| `01_time_series` | Recording-level frame agreement, urban and rural SNR, and frame counts per analyzed second |
| `02_daily_summary` | Daily frame-agreement ratios and frame counts per analyzed second |
| `03_snr_relationship` | Frame agreement versus urban and rural SNR, coloured by day |
| `04_coverage` | Daily counts of analyzed pairs, pairs skipped by SNR or PPS criteria, and other cases |
| `05_within_record_variability` | Distribution of within-record variability and its relationship to recording-level frame agreement |

Each figure is saved as:

- **PNG** at 250 dpi.
- **Vector PDF**.
- **Editable MATLAB FIG**.

Figure labels are in English.

### Summary datasets

| Output | Content |
|---|---|
| `records_summary.csv` | Per-recording counts, ratios, SNR, and variability |
| `daily_summary.csv` | Daily totals, coverage categories, and ratios |
| `global_summary.csv` | Aggregate counts, coverage, and overall ratio |
| `graph_summary.mat` | MATLAB structure containing the summary tables and output directory |

### Interpretation

Frame counts per analyzed second refer only to the selected, successfully analyzed blocks. They are not estimates of total traffic across each full recording or the complete campaign.

Within-record variability is the standard deviation of per-second frame-agreement percentages, expressed in **percentage points**. Seconds with zero rural frames have an undefined ratio and are excluded from this calculation. At least two defined per-second ratios are required.

The figures label SNR as measured over **1 MHz**, while paired frame decoding uses a **2 MHz synchronization channel**. The input SNR configuration must match this interpretation.

Skipped recordings create gaps in frame-agreement and frame-rate curves. SNR may still be available for those recordings. Coverage is reported relative to pairs listed in the audit, rather than every theoretically scheduled acquisition.

The script visualizes existing decoder results. It does not modify decoding decisions, and an association between SNR and frame agreement does not independently establish the source of interference.

## 14. Publication of analysis results

For each published result set, retain:

- Input period and station identifiers.
- Processing configuration and code version.
- Machine-readable result datasets.
- Figures and captions.
- Coverage and exclusion information.

Campaign coverage and analyzed coverage must be reported separately. The supplied scripts contain different date ranges and selected intervals; their presence in this repository does not imply that every analysis covers the complete measurement campaign.

Results should be stored under [`../results/`](../results/), grouped by analysis type and processing run.
