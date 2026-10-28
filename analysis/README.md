# Analysis scripts

MATLAB workflows for the dual-station C-band satellite downlink measurements.

| Folder | Purpose |
| --- | --- |
| [broadband_peaks](broadband_peaks/) | Long-term broadband peak counts |
| [broadband_bursts](broadband_bursts/) | Detect peaks in a recording and mark them on its spectrogram |
| [snr](snr/) | Downlink SNR analysis using saved noise statistics |
| [noise_statistics](noise_statistics/) | Median noise level and noise standard deviation |
| [noise_temperature](noise_temperature/) | Noise level and temperature comparison for each station |
| [spectrogram_comparison](spectrogram_comparison/) | Compare city and village spectrograms on a shared scale |
| [downlink_frames/demodulation_pcap](downlink_frames/demodulation_pcap/) | Demodulate the analyzed downlink and export Ethernet frames to PCAP |
| [downlink_frames/pps_inventory](downlink_frames/pps_inventory/) | Inventory injected PPS markers |
| [downlink_frames/long_term_analysis](downlink_frames/long_term_analysis/) | Synchronize recordings and compare frame observations over selected dates |
| [utilities](utilities/) | Merge compatible noise, SNR, impulse, or temperature/noise result datasets |

## Running the scripts

Set input paths, output paths, dates, and analysis parameters before running a script. Some scripts contain example or campaign-specific paths. Raw recordings and generated result datasets are supplied separately from the source code.

The workflows target MATLAB R2020b. Signal Processing Toolbox is used for spectral analysis and synchronization. The downlink decoders and paired frame analysis additionally require Communications Toolbox. See the local README files for the PPS inventory and long-term frame analysis workflows.

Noise statistics are an input to the SNR and temperature/noise workflows. Long-term paired frame analysis requires both a PPS inventory MAT file and an SNR MAT file. Keep the supporting MATLAB files for each multi-file workflow together.
