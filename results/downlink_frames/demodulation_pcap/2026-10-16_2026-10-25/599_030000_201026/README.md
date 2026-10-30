# Standalone downlink decoding example

Both stations use the nominal recording `599_030000_201026.raw`, starting on 20 October 2026 at 03:00:00. Each decoder processes recording offsets 25–30 s, at RF 3839 MHz.

| Station | Results | Exported Ethernet frames |
| --- | --- | ---: |
| City — Zlín | [city/](city/) | 74 |
| Village — Hošťálkova | [village/](village/) | 162 |

Each folder contains `ethernet.pcap`, `analysis.mat`, `summary.txt`, and `downlink_decoding_diagnostic.fig`. The summaries include FEC and HDLC validation diagnostics. Only frames passing HDLC FCS validation and the decoder's Ethernet checks are exported; the HDLC FCS is removed.

These are standalone examples selected using the same nominal recording and offsets. No additional PPS-based or cross-correlation synchronization was applied between stations. The two frame counts must therefore not be interpreted as counts from an exactly aligned shared transmission interval or used directly to estimate reception loss.

PCAP time is relative to the first exported packet in each file. Its calendar date is not the measurement date, and zero-relative-time packets in the two PCAP files need not represent the same transmission. Open either PCAP in Wireshark using relative time for inspection.

Processing function: [decode_downlink_to_pcap.m](../../../../../analysis/downlink_frames/demodulation_pcap/decode_downlink_to_pcap.m). Re-encoding disagreement is a diagnostic value, not BER; CRC-valid observations alone do not identify the complete physical-layer standard.

## Decoder diagnostics

The city summary reports 73 HDLC FCS passes in the first half of the analyzed interval and 1 in the held-out second half. The village summary reports 82 and 80, respectively. The city total therefore combines markedly different recovery counts within this short example. The summaries report re-encoding disagreement of 11.517675% for the city and 0.006893% for the village; these are decoder diagnostics, not BER estimates.
