# DUAL-STATION SDR SPECTRUM MEASUREMENT

## Project overview

This project investigates the impact of terrestrial transmissions, particularly 5G networks, on C-band satellite downlink reception. Two identical software-defined radio (SDR) measurement stations were deployed at an urban site in Zlín and a rural reference site in Hošťálková, Czech Republic.

The project was funded by ESA / Libre Space Foundation through the ESA Spectrum Sharing Makerspace programme and carried out by a research team from the Faculty of Applied Informatics, Tomas Bata University in Zlín.

## Objectives

- Compare satellite downlink reception in urban and rural environments.
- Characterize broadband interference and its variation over time.
- Evaluate the signal-to-noise ratio (SNR), noise statistics, and reception stability.
- Assess daytime and nighttime differences in reception quality.
- Demodulate and decode selected satellite signals and evaluate data frame recovery across the recordings.

## Measurement sites

- **Zlín — urban site:** Located near terrestrial transmitters, representing an environment with potential interference from mobile networks and other terrestrial sources.
- **Hošťálková — rural reference site:** Located in an open area with few nearby terrestrial transmitters and no expected 5G coverage, providing a reference environment with lower anticipated interference.

Both stations used identical measurement equipment and acquisition settings to support comparison between the two environments.

## Measurement campaign

Measurements were conducted during two periods:

- **18–30 September 2026**
- **15–25 October 2026**

Each station recorded one minute of IQ data every ten minutes.

| Parameter | Value |
|---|---|
| Recorded IF centre frequency | 1312 MHz |
| LNB local oscillator frequency | 5150 MHz |
| Corresponding RF centre frequency | 3838 MHz |
| Recorded bandwidth | 10 MHz |
| Approximate RF coverage | 3833–3843 MHz |
| Downlink of interest 1 | 3839 MHz, approximately 2 MHz bandwidth |
| Downlink of interest 2 | 3842 MHz, approximately 0.5 MHz bandwidth |
| Recording schedule | 60 seconds every 10 minutes |
| Total recorded data | Approximately 14.34 TB across both stations |

## Analysis scope

The analysis covers broadband interference peaks and bursts, SNR, the median and standard deviation of noise levels, the relationship between noise levels and temperature, and spectrogram comparisons.

Selected downlink recordings were also demodulated and decoded to reconstruct data frames. Recovered network traffic was exported to PCAP files for inspection in Wireshark. Long-term frame analysis was preceded by a PPS marker inventory to support timing alignment between the stations.

## Main findings

Broadband interference analysis, SNR evaluation, and data frame recovery indicate that reception quality varies between daytime and nighttime in a pattern consistent with changes in human activity.

Demodulation and decoding of the downlink centred at 3839 MHz revealed that the recovered data carried network traffic.

Taken together, the observations support the hypothesis that 5G transmitters are a major source of interference affecting reception in the urban environment. However, the comparison between sites and the observed temporal patterns alone do not conclusively establish 5G transmissions as the dominant cause.

## Project outputs

This repository provides:

- Measurement station design, schematics, and wiring documentation.
- Raspberry Pi acquisition software and Arduino PPS marker firmware.
- Data analysis and visualization scripts.
- Analysis results, tables, and figures.
- Documentation and the final report.
- Information on the recorded datasets and access to the full IQ archive.

## Research team

- Ing. Miroslav Dolejš
- Ing. Anton Džima
- Ing. Stanislav Kovář, Ph.D.
- Ing. Eliška Štrajtová

Faculty of Applied Informatics, Tomas Bata University in Zlín, Czech Republic.

## Project status

The planned measurement campaigns and analyses have been completed. This repository documents the final methods and results.
