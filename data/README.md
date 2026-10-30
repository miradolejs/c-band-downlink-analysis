# Recorded datasets

This directory documents the IQ recordings from the dual-station C-band measurement campaigns. Derived analysis products are published separately in [results/](../results/README.md).

| Campaign | Recording dates | Stations |
| --- | --- | --- |
| September | 18–30 September 2026 | City — Zlín; village — Hošťálkova |
| October | 16–25 October 2026 | City — Zlín; village — Hošťálkova |

Each station recorded nominally 60 seconds every ten minutes, at 10 MS/s with interleaved little-endian int16 I/Q. The recorded IF centre is 1312 MHz, corresponding to RF 3838 MHz for the 5150 MHz LNB oscillator. Actual duration is determined by the stored sample count.

## Contents

| Path | Purpose |
| --- | --- |
| [data_access.md](data_access.md) | Full-archive access status and intended distribution |
| [catalog/](catalog/README.md) | Catalog fields, inventory generation, coverage, and size summaries |
| [examples/](examples/README.md) | Public excerpt format and generation instructions |
| [tools/](tools/README.md) | Per-disk inventory, offline catalog merging, and excerpt extraction tools |

The full RAW archive is not stored in this Git repository. The supplied tools generate catalogs from the archive and extract short examples from selected original recordings. See the corresponding directories for the available files and usage instructions.

## Archive organization

The archive root contains the following station-specific source directories. Paths are independent of the disk mount or server address.

| Source directory | Station | Campaign |
| --- | --- | --- |
| `1_Hostalkova_180926_240926/` | Village | September |
| `1_Hostalkova_250926_300926/` | Village | September |
| `1_Zlin_180926_240926/` | City | September |
| `1_Zlin_250926_300926/` | City | September |
| `2_Hostalkova_151026_191026/` | Village | October |
| `2_Hostalkova_201026_251026/` | Village | October |
| `2_Zlin_151026_191026/` | City | October |
| `2_Zlin_201026_251026/` | City | October |

Each source contains daily `DDMMYY` directories with matching `N_HHMMSS_DDMMYY.raw` and `.json` files. For example:

```text
2_Zlin_201026_251026/201026/581_000000_201026.raw
2_Zlin_201026_251026/201026/581_000000_201026.json
```

The `151026` labels in two source-directory names do not change the published October campaign start of **16 October 2026**. The catalog uses the recording filename date to determine campaign membership. Earlier preparatory files, if present, are listed separately rather than silently discarded.

## Time conventions

Filenames and offset-free JSON `start_iso` timestamps use local Czech time (`Europe/Prague`). Use JSON `start_unix` for an absolute software time reference. These timestamps are not verified hardware timestamps of the first sample; fine station alignment requires PPS markers and signal correlation.

During the October campaign, the recorder did not acquire the repeated 02:00–02:59 hour following the return to standard time on **25 October 2026**. Its next scheduled local time was 03:00. The wait from approximately 02:50 CEST to 03:00 CET was therefore approximately 70 elapsed minutes. The catalog preserves the original local times and derives UTC from explicit metadata, without inventing recordings for the skipped hour.

See [Data formats](../docs/data_formats.md) for sample layout and metadata interpretation.
