# Downlink SNR: 16–25 October 2026

Merged city and village SNR estimates, derived from the recordings and saved noise statistics.

| Figure suffix | RF center | SNR integration bandwidth |
| --- | --- | --- |
| `band01` | 3839 MHz | 1 MHz |
| `band02` | 3842 MHz | 0.5 MHz |

The 1 MHz SNR integration band differs from the 2 MHz channel used for synchronization and frame decoding. Estimated signal power is total band power minus estimated noise power. Nonpositive signal estimates do not yield a valid finite SNR. Additional in-band interference is not separated from the estimated signal contribution.

Processing workflow: [analyze_downlink_snr_ready.m](../../../analysis/snr/analyze_downlink_snr_ready.m). The MAT dataset retains analysis settings and separate station results. Figures are provided in PNG for viewing and MATLAB FIG for further inspection. The date interval identifies the result set; it does not independently establish uninterrupted acquisition or successful processing of every scheduled recording.

## Files

- [Merged_snr_20261016_20261025_20261030_061232_408.mat](Merged_snr_20261016_20261025_20261030_061232_408.mat)
- [Merged_snr_20261016_20261025_20261030_061232_408_band01.fig](Merged_snr_20261016_20261025_20261030_061232_408_band01.fig)
- [Merged_snr_20261016_20261025_20261030_061232_408_band01.png](Merged_snr_20261016_20261025_20261030_061232_408_band01.png)
- [Merged_snr_20261016_20261025_20261030_061232_408_band02.fig](Merged_snr_20261016_20261025_20261030_061232_408_band02.fig)
- [Merged_snr_20261016_20261025_20261030_061232_408_band02.png](Merged_snr_20261016_20261025_20261030_061232_408_band02.png)
