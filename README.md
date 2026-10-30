# c-band-downlink-analysis
This analysis assesses the impact of terrestrial transmitters, particularly 5G networks, on C-band satellite downlink reception. Measurements using two identical stations in urban and rural locations reveal differences in reception quality and day–night stability, consistent with patterns of human activity and potential 5G interference.

Analysis results are available for **18–30 September 2026** and **16–25 October 2026**. Both campaigns include spectral and environmental analyses, selected spectrograms, broadband peak detection examples, and standalone downlink decoding examples. PPS-assisted long-term frame comparison is published for **25–30 September 2026**. See the [results overview](results/README.md) for coverage and interpretation.

## Repository contents

| Directory | Contents |
| --- | --- |
| [Documentation](docs/README.md) | Project overview, measurement methodology, station locations, data formats, and analysis workflow |
| [Measurement stations](measurement_stations/README.md) | Hardware design, wiring, photographs, Raspberry Pi acquisition software, and Arduino and Wemos firmware |
| [Analysis](analysis/README.md) | MATLAB processing and visualization scripts |
| [Results](results/README.md) | Published figures, numerical datasets, PCAP examples, and processing coverage for both campaigns |
| [Recorded datasets](data/README.md) | Archive organization, access status, catalog generation, and short IQ example tools |
| [Project reports](reports/README.md) | Public technical evaluation of the project, results, limitations, and further work |

## Licensing

Original project software is licensed under [Apache License 2.0](LICENSE). Original documentation and identified original data products are licensed under [CC BY 4.0](LICENSES/CC-BY-4.0.txt).

See [LICENSING.md](LICENSING.md) for the exact scope and exclusions, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party materials and dependencies. The default grants exclude Mapy.com imagery, captured I/Q and decoded third-party communication payloads, and other separately licensed materials. These repository licenses do not automatically apply to the full external IQ archive.
