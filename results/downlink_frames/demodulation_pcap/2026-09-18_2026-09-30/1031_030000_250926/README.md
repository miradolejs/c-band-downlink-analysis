# Standalone downlink decoding example

Both stations use the nominal recording `1031_030000_250926.raw`, starting on 25 September 2026 at 03:00:00. Each decoder processes recording offsets 10–15 s, at RF 3839 MHz.

| Station | Results | Exported Ethernet frames |
| --- | --- | ---: |
| City — Zlín | [city/](city/) | 69 |
| Village — Hošťálkova | [village/](village/) | 137 |

Each folder contains `summary.txt` with aggregate frame counts and FEC and HDLC validation diagnostics. The decoder's `ethernet.pcap`, `analysis.mat`, and diagnostic figure contain decoded third-party communication content and are not published. Only frames passing HDLC FCS validation and the decoder's Ethernet checks are exported; the HDLC FCS is removed.

These are standalone examples selected using the same nominal recording and offsets. No additional PPS-based or cross-correlation synchronization was applied between stations. The two frame counts must therefore not be interpreted as counts from an exactly aligned shared transmission interval or used directly to estimate reception loss.

Processing function: [decode_downlink_to_pcap.m](../../../../../analysis/downlink_frames/demodulation_pcap/decode_downlink_to_pcap.m). Re-encoding disagreement is a diagnostic value, not BER; CRC-valid observations alone do not identify the complete physical-layer standard.
