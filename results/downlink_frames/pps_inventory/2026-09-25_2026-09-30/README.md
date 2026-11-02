# PPS inventory: 25–30 September 2026

The inventory inspects the first five seconds of each recording for the injected marker near 1315 MHz IF.

| Station | Attempted recordings | PPS detected | Not detected | Ambiguous/errors |
| --- | ---: | ---: | ---: | ---: |
| City | 864 | 864 | 0 | 0 |
| Village | 864 | 857 | 7 | 0 |

All six requested daily folders were found at both stations. Detection is based on the configured pulse-train model. `not_detected` is not proof of physical marker absence. Inventory pulse edges are coarse STFT estimates; precise paired-recording alignment is performed separately in the frame-analysis workflow.

The final `PPSInventory_*.mat` contains `pps_results`. `PPS_checkpoint.mat` is an intermediate state of the same run and must not be counted as another dataset. CSV exports provide recording and folder inventories; text reports and FIG/PNG files provide summaries.

## Files

- [PPSInventory_20260925_20260930_FULL_20261021_082921_166.mat](PPSInventory_20260925_20260930_FULL_20261021_082921_166.mat)
- [PPS_all_files.csv](PPS_all_files.csv)
- [PPS_ambiguous_and_errors.csv](PPS_ambiguous_and_errors.csv)
- [PPS_checkpoint.mat](PPS_checkpoint.mat)
- [PPS_folder_coverage.csv](PPS_folder_coverage.csv)
- [PPS_not_detected_city.txt](PPS_not_detected_city.txt)
- [PPS_not_detected_village.txt](PPS_not_detected_village.txt)
- [PPS_overview.fig](PPS_overview.fig)
- [PPS_overview.png](PPS_overview.png)
- [PPS_summary.txt](PPS_summary.txt)

Processing: [PPS inventory workflow](../../../../analysis/downlink_frames/pps_inventory/README.md).
