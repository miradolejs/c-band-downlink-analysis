# Frame-analysis summary visualization

`plot_frame_analysis_summary.m` generates figures and summary datasets from one completed paired frame-analysis run. It reads CSV results and does not reread RAW recordings, PPS inventories, or SNR MAT files. The number of days is determined by the input results.

Requires MATLAB R2020b or later, with no additional toolboxes.

## Inputs and execution

Keep the script in the MATLAB Current Folder or on the MATLAB path. Select an analysis output folder containing:

- `all_seconds.csv` — Per-second results.
- `pair_audit.csv` — Pair statuses and record-level SNR.
- `summary.csv` — Optional aggregate counts for a consistency check.

All inputs must originate from the same run. Both `FRAME_FULL_...` and `FRAME_TEST_...` runs are supported when they contain analyzed seconds. Select the results folder, rather than a RAW data folder.

Run interactively:

```matlab
R = plot_frame_analysis_summary;
```

Or specify input and output directories:

```matlab
R = plot_frame_analysis_summary( ...
    'D:\results\FRAME_FULL_run', ...
    'D:\results\frame_figures');
```

Without an explicit output directory, a timestamped `FIGURES_<timestamp>` subfolder is created inside the input folder.

Exact CSV filenames take precedence. Downloaded variants such as `all_seconds(2).csv` are accepted when exactly one matching variant exists and no exact filename is present. The optional summary check is performed only when exactly one `summary*.csv` file is found.

## Processing

The script checks duplicate pair and filename/second identifiers, validates frame-count identities, and aggregates only rows with `Status = analyzed`. At least one analyzed second is required. Excluded pairs remain represented in the pair-level coverage summaries.

Record-level SNR is taken from `City_Record_SNR_dB` and `Village_Record_SNR_dB` in the audit when those columns exist. If a column is absent, finite per-second SNR values are averaged in the linear domain and converted back to dB. An existing audit column with missing values does not trigger this fallback.

Per-recording, daily, and global agreement ratios are calculated as:

```text
sum(Common) / sum(Village_Total)
```

These are not arithmetic averages of individual percentages. Zero denominators remain undefined. The global reference line is drawn only when the global ratio is finite.

Recording times are parsed from RAW filenames without timezone conversion. Date labels include the year. PPS coverage categories use the pair status and recognized rejection messages; other exclusions, including insufficient stable seconds and unclassified errors, remain in the other category.

## Outputs

| Figure | Content |
| --- | --- |
| `01_time_series` | Per-recording frame agreement, station SNR, and frame counts per analyzed second |
| `02_daily_summary` | Daily agreement ratios and frame counts per analyzed second |
| `03_snr_relationship` | Frame agreement versus city and village SNR, colored by day |
| `04_coverage` | Daily analyzed pairs, likely-noise exclusions, PPS exclusions, and other cases |
| `05_within_record_variability` | Within-record variation of per-second agreement ratios |

Each figure is saved as PNG at 250 dpi, vector PDF, and editable MATLAB FIG.

| Dataset | Contents |
| --- | --- |
| `records_summary.csv` | Pair-level counts, agreement, SNR, and variability |
| `daily_summary.csv` | Daily totals and coverage categories |
| `global_summary.csv` | Overall counts, coverage, and agreement |
| `graph_summary.mat` | Output structure `R` with summary tables and output directory |

## Interpretation

Frame counts per analyzed second describe the selected successfully analyzed blocks. They do not estimate complete traffic over a full recording or campaign. Coverage is relative to candidates listed in `pair_audit.csv`, rather than every theoretically scheduled acquisition. Skipped records produce gaps in agreement and frame-rate curves; their SNR can remain available.

Within-record variability is the standard deviation of defined per-second agreement percentages, expressed in percentage points. Seconds with zero village frames are excluded from this statistic. At least two defined ratios are required for a standard deviation.

SNR labels assume the 3839 MHz / 1 MHz integration band used by the paired analysis. Synchronization uses a 2 MHz channel. These are different quantities. Infinite or missing SNR values do not appear in finite-valued SNR scatter plots.

The figures summarize decoder observations without changing decoding decisions. Agreement ratios are not BER or end-to-end network packet loss, and their association with SNR does not independently establish the interference source.
