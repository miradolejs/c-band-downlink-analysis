# Paired frame analysis: 25–30 September 2026

This result set covers six days within the September campaign. It contains 864 candidate recording pairs, with 144 nominal recordings per day.

| Outcome | Recording pairs |
| --- | ---: |
| Included in analyzed frame counts | 747 |
| Skipped by joint whole-record SNR screening | 110 |
| Excluded because of PPS criteria | 7 |
| Total candidates | 864 |

The included pairs contribute 7,470 selected analyzed seconds: the first 10 confirmed stable seconds of each included pair. The processing method requires at least 5 successfully decoded selected seconds per included pair. The selected seconds are not a random sample or complete decoding of each full recording.

| Metric | Count |
| --- | ---: |
| City frame occurrences | 143,803 |
| Village frame occurrences | 263,171 |
| Common occurrences | 141,026 |
| City-only occurrences | 2,777 |
| Village-only occurrences | 122,145 |

The aggregate common/village ratio is **53.5872%**, calculated as `sum(Common) / sum(Village_Total)`. It describes matched decoded observations, rather than end-to-end network packet loss or BER. The byte and timing criteria, guards, and exclusions described in the processing workflow determine which occurrences enter the counts.

## Published files

- [all_seconds.csv](all_seconds.csv)
- [pair_audit.csv](pair_audit.csv)
- [per_record_tables.zip](per_record_tables.zip)
- [run_config.mat](run_config.mat)
- [snr_calibration.mat](snr_calibration.mat)
- [summary.csv](summary.csv)
- [summary.mat](summary.mat)

`all_seconds.csv` and `pair_audit.csv` are the primary tabular results. `per_record_tables.zip` contains all 1,715 supplied per-record `_seconds.csv` and `_all_blocks.csv` exports in a `per_record_tables/` folder. Extract it for detailed per-record inspection. The MAT files retain summary, configuration, and SNR calibration information. Per-pair `*_frames.mat` checkpoint files are not included in this published result set.

`Excluded_Seconds = 0` in the summary applies to the selected exported report rows. It does not imply that no recordings were excluded or that every second of each recording was analyzed; the 117 excluded pairs are documented in the audit.

Paired synchronization and decoding are computationally intensive. Published frame-analysis and PPS-inventory results currently cover 25–30 September 2026. Additional days can be processed using the [published analysis scripts](../../../../analysis/downlink_frames/long_term_analysis/README.md) and the corresponding RAW recordings, after preparing their PPS inventory and SNR inputs.

The saved configuration documents this result set. Recomputations should retain the reported selection rules and parameter settings for a comparable result.
