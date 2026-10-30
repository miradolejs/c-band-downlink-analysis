# Dataset inventory and excerpt tools

All three scripts use **Python 3.9 or later and the standard library only**. No NumPy, MATLAB, SDR driver, or third-party package is required. Run them against a mounted archive or a filesystem share; authenticated web download URLs are not supported as input paths.

Commands below are run from the repository root. On Windows, `py -3` invokes Python; use `python3` instead on a system configured with that executable.

## 1. Generate the recording catalogs

Configure the archive layout in [archive_layout.json](archive_layout.json). Its eight source-directory names match the documented archive structure. Each source explicitly identifies a station and campaign; the script does not guess station identity from a filename.

```powershell
py -3 data/tools/catalog_recordings.py --archive-root "D:/" --output "data/catalog"
```

`D:\` is an example root containing all eight source directories, not a required disk label. A mounted server path can be used instead:

```powershell
py -3 data/tools/catalog_recordings.py --archive-root "\\server\share\iq_archive" --output "data/catalog"
```

For a source tree under another directory, point `--archive-root` there. Edit the JSON configuration if source directory names differ. Output must not be inside one of the scanned source directories.

The script prints total RAW/JSON counts, logical byte volume, entries with issues, and source availability. It also saves a machine-readable `catalog_snapshot.json` for later offline merging. It writes the two campaign catalogs, an outside/invalid-date catalog, issue list, and CSV/JSON summaries. Generated catalog files with the same names are replaced when rerun. Source recordings and metadata are never modified.

### Exit status and review

| Exit code | Meaning |
| --- | --- |
| `0` | All configured source directories were scanned without directory/stat errors. Individual recording issues can still exist. |
| `1` | Configuration, output, or other fatal error. Inspect the error message. |
| `2` | Catalogs were generated from an incomplete scan because sources were missing or scan errors occurred. |

After running, inspect `archive_summary.json` and `catalog_issues.csv`. Do not describe a partial scan as the complete archive. For separately attached disks, use the per-disk workflow below. Rerunning an inventory into the same output directory replaces that snapshot rather than accumulating new disks.

Full-archive RAW checksums are intentionally not generated: hashing would require reading every byte of the multi-terabyte dataset.

## 2. Inventory disks one at a time

Keep per-disk outputs on the computer's internal drive so they remain available after each archive disk is disconnected. Use the same `archive_layout.json` for every disk. The source-directory names remain unchanged; `--archive-root` points to the root of whichever disk is connected.

From the repository root on Windows:

```powershell
py -3 data/tools/catalog_recordings.py --archive-root "D:/" --output "C:/iq_catalog_runs/disk_1" --allow-partial
```

After safely disconnecting the first disk and attaching the second:

```powershell
py -3 data/tools/catalog_recordings.py --archive-root "D:/" --output "C:/iq_catalog_runs/disk_2" --allow-partial
```

Repeat with output directories `disk_3` and `disk_4`. Adjust the archive drive letter if Windows assigns a different one. Always use a distinct output directory per disk; replace a disk's previous snapshot only when deliberately rescanning that same disk.

`--allow-partial` makes missing configured source directories an expected per-disk condition and allows exit status 0. It does not suppress errors while scanning an available directory. The summaries still explicitly record missing source directories. Check that the expected folders on the connected disk were found; a wrong root can otherwise produce an empty partial inventory.

### Merge the four saved snapshots

The archive disks no longer need to be connected:

```powershell
py -3 data/tools/merge_recording_catalogs.py --inputs "C:/iq_catalog_runs/disk_1" "C:/iq_catalog_runs/disk_2" "C:/iq_catalog_runs/disk_3" "C:/iq_catalog_runs/disk_4" --output "data/catalog"
```

Inputs may be scan directories or explicit `catalog_snapshot.json` paths. Merging reads only these local JSON snapshots. It generates the same campaign CSV catalogs, issue CSV, and archive summaries as a direct inventory, plus a merged snapshot. Do not manually concatenate CSV files or add up input summary totals.

The merger validates that all inputs use the same archive configuration and station assignments. Repeated observations of an identical archive-relative recording path are counted once only when the saved catalog fields agree. Conflicting observations stop the merge without replacing the final catalog. No RAW hashes are available, so matching observations certify matching recorded sizes and metadata, not byte-for-byte RAW identity. Complementary RAW-only and JSON-only observations for one path require a rescan with the pair together; they are not silently combined.

If the same nominal recording appears at different archive-relative paths, both entries remain and the repeated recording key is flagged for review. Volumes are recomputed from retained paths, not summed from disk summaries. Missing directories are assessed across all input snapshots; a directory absent from one disk is not treated as missing from the combined archive when another disk contains it.

The merger uses exit code 2 when configured sources remain missing or scan errors were recorded. Exit code 0 means those checks passed; it does not prove complete acquisition or that no files were omitted before scanning. Review recording-level issues separately. Resolve scan errors by replacing the affected disk's snapshot and merging again.

## 3. Extract a one-second city/village pair

The example below selects the September nominal recording used for the standalone decoding examples. Confirm that these exact source files exist in your archive. Another pair can be supplied using the same arguments.

```powershell
py -3 data/tools/extract_iq_examples.py --city-raw "D:\1_Zlin_250926_300926\250926\1031_030000_250926.raw" --village-raw "D:\1_Hostalkova_250926_300926\250926\1031_030000_250926.raw" --offset 10 --duration 1 --output "data/examples"
```

Each RAW must have a matching `.json` beside it. Required checks include int16 format, positive matching sampling rates and centre frequencies, matching nominal filename dates/times, file size equal to `4 * samples_recorded`, `write_error=false`, and sufficient available samples. Measurement counters need not match between stations. If both source Unix timestamps are available, a difference greater than two seconds causes rejection, including accidental pairing of repeated local hours.

The two sources must be distinct files. The tool refuses to overwrite existing generated outputs or write inside a source-recording directory. Default offset and duration are 10 s and 1 s, respectively. Other nonnegative offsets and positive durations can be selected with the same options.

Only the selected byte ranges are copied in bounded chunks. SHA-256 is computed for generated excerpts and metadata, not for complete source RAW recordings. Original source JSON files are preserved byte-for-byte in `*_source.json`, while separate excerpt JSON files describe the new sample counts and offsets.

A one-second 10 MS/s pair reads approximately 80 MB of source I/Q data in total and writes the same amount, plus metadata. This is a bounded extraction, unlike a full RAW archive scan. Source size and modification time are checked before and after copying.

The [example documentation](../examples/README.md) explains the resulting files and timing limitations. Use GitHub Desktop to review and publish selected files after generation; the scripts do not commit or upload anything.
