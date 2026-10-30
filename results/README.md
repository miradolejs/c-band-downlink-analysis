# Analysis results

Published data products from the dual-station C-band satellite downlink study at Zlín (city) and Hošťálkova (village).

## Coverage

Campaign result sets cover **18–30 September 2026** and **16–25 October 2026**. Selected examples and paired frame analysis have the narrower coverage specified below. Folder date ranges identify result sets; use MAT metadata and audit tables to assess actual acquisition and processing coverage.

| Product | September results | October results |
| --- | --- | --- |
| Broadband interference peak counts | [18–30 September](broadband_peaks/2026-09-18_2026-09-30/) | [16–25 October](broadband_peaks/2026-10-16_2026-10-25/) |
| Noise median and standard deviation | [18–30 September](noise_statistics/2026-09-18_2026-09-30/) | [16–25 October](noise_statistics/2026-10-16_2026-10-25/) |
| Downlink SNR | [18–30 September](snr/2026-09-18_2026-09-30/) | [16–25 October](snr/2026-10-16_2026-10-25/) |
| Temperature and noise, both stations | [18–30 September](noise_temperature/2026-09-18_2026-09-30/) | [16–25 October](noise_temperature/2026-10-16_2026-10-25/) |
| Selected spectrogram comparisons | [25 September, 03:00 and 18:00](spectrogram_comparison/2026-09-18_2026-09-30/) | [20 October, 03:00 and 18:00](spectrogram_comparison/2026-10-16_2026-10-25/) |
| Broadband peaks marked in spectrograms | [25 September, 03:00 and 18:00](broadband_peaks_mark_in_spectrogram/2026-09-18_2026-09-30/) | [20 October, 03:00 and 18:00](broadband_peaks_mark_in_spectrogram/2026-10-16_2026-10-25/) |
| Standalone city/village PCAP examples | [25 September, 03:00; offsets 10–15 s](downlink_frames/demodulation_pcap/2026-09-18_2026-09-30/1031_030000_250926/) | [20 October, 03:00; offsets 25–30 s](downlink_frames/demodulation_pcap/2026-10-16_2026-10-25/599_030000_201026/) |
| PPS inventory | [25–30 September](downlink_frames/pps_inventory/2026-09-25_2026-09-30/) | Not included |
| Long-term paired frame analysis | [25–30 September](downlink_frames/long_term_analysis/2026-09-25_2026-09-30/) | Not included |
| Frame-analysis summary figures and tables | [25–30 September](downlink_frames/visualization/2026-09-25_2026-09-30/) | Not included |

All dates in the table refer to 2026. Example times follow recording filenames without timezone conversion.

## Files and use

MAT files retain machine-readable datasets and processing metadata. PNG/PDF files support viewing and reports; FIG files can be opened in MATLAB. CSV tables provide numerical results. PCAP files can be inspected in Wireshark. Individual folders describe their metrics and contents.

Detailed per-record frame tables are distributed in `per_record_tables.zip`; primary aggregate tables remain directly accessible. `checksums.sha256` records SHA-256 hashes of distributed result files and README documents, using paths relative to this directory.

## Interpretation and further analysis

Independent PCAP examples use the same nominal recording and offsets within each campaign, without additional inter-station PPS or cross-correlation alignment. They are distinct from the synchronized paired frame analysis. PCAP timestamps are relative to each file's first exported packet, and their calendar dates are not measurement dates. Standalone frame counts must not be used directly to estimate reception loss.

Morning/evening examples represent expected lower and higher human activity, rather than independently measured terrestrial network load. Recorder-referenced dBFS values are not calibrated RF input powers in dBm. Check processing settings, detector thresholds, and displayed scales before comparing campaigns.

Paired synchronization and frame decoding are computationally intensive. The published PPS inventory and long-term frame comparison cover **25–30 September 2026**. Further dates from either campaign can be processed using the [published workflows](../analysis/) and corresponding RAW recordings, with matching PPS-inventory and SNR inputs and campaign-specific configuration. The repository does not bundle the full RAW recordings with these derived products.

See [Analysis Workflow](../docs/analysis_workflow.md) for processing dependencies, timing conventions, and interpretation. Shared-frame ratios describe decoded observations and must not be presented as BER or end-to-end network packet loss.
