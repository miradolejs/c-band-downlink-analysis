# Analysis results

Published data products from the dual-station C-band satellite downlink study at Zlín (city) and Hošťálkova (village).

## Coverage

| Product | Published September coverage | Results |
| --- | --- | --- |
| Broadband interference peak counts | 18–30 September 2026 | [broadband_peaks/2026-09-18_2026-09-30/](broadband_peaks/2026-09-18_2026-09-30/) |
| Broadband peak detection examples with marked spectrograms | 25 September 2026, 03:00 and 18:00 | [broadband_peaks_mark_in_spectrogram/2026-09-18_2026-09-30/](broadband_peaks_mark_in_spectrogram/2026-09-18_2026-09-30/) |
| Noise median and standard deviation | 18–30 September 2026 | [noise_statistics/2026-09-18_2026-09-30/](noise_statistics/2026-09-18_2026-09-30/) |
| Downlink SNR | 18–30 September 2026 | [snr/2026-09-18_2026-09-30/](snr/2026-09-18_2026-09-30/) |
| Temperature and noise comparisons, both stations | 18–30 September 2026 | [noise_temperature/2026-09-18_2026-09-30/](noise_temperature/2026-09-18_2026-09-30/) |
| Selected spectrogram examples | 25 September 2026, 03:00 and 18:00 | [spectrogram_comparison/2026-09-18_2026-09-30/](spectrogram_comparison/2026-09-18_2026-09-30/) |
| Standalone city/village PCAP examples | 25 September 2026, nominal 03:00 recording | [downlink_frames/demodulation_pcap/2026-09-18_2026-09-30/1031_030000_250926/](downlink_frames/demodulation_pcap/2026-09-18_2026-09-30/1031_030000_250926/) |
| PPS inventory | 25–30 September 2026 | [downlink_frames/pps_inventory/2026-09-25_2026-09-30/](downlink_frames/pps_inventory/2026-09-25_2026-09-30/) |
| Long-term paired frame analysis | 25–30 September 2026 | [downlink_frames/long_term_analysis/2026-09-25_2026-09-30/](downlink_frames/long_term_analysis/2026-09-25_2026-09-30/) |
| Frame-analysis summary figures and tables | 25–30 September 2026 | [downlink_frames/visualization/2026-09-25_2026-09-30/](downlink_frames/visualization/2026-09-25_2026-09-30/) |

Results for the second measurement interval, **16–25 October 2026**, are not included in this release. Campaign-level spectral and environmental datasets cover their stated analysis interval; the selected examples and paired frame-analysis subset have the narrower coverage shown above. Use result metadata and audit tables to assess actual processing coverage.

## Files and use

MAT files retain machine-readable analysis datasets and metadata. PNG/PDF files support viewing and reports; FIG files can be opened in MATLAB. CSV tables provide the exported numerical results. PCAP files can be inspected in Wireshark. Individual folders describe their metrics and contents.

Detailed per-record frame tables are distributed in `per_record_tables.zip`; primary aggregate tables remain directly accessible. `checksums.sha256` records SHA-256 hashes of the distributed result files and README documents.

The independent PCAP examples share a nominal recording time and offset, but were not additionally aligned between stations. They are distinct from the PPS-assisted, cross-correlated paired frame analysis. Morning/evening spectrogram examples represent expected activity conditions, rather than independently measured terrestrial network load.

Paired synchronization and frame decoding are computationally intensive. The published PPS inventory and long-term frame comparison cover **25–30 September 2026**. Further days can be analyzed using the [published workflows](../analysis/) and the corresponding RAW data, with matching PPS-inventory and SNR inputs. The repository does not bundle the full RAW recordings with these derived products.

See [Analysis Workflow](../docs/analysis_workflow.md) for dependencies, settings, timing conventions, and interpretation. Shared-frame ratios describe decoded observations and must not be presented as BER or end-to-end network packet loss.
