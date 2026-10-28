# Long-term paired frame analysis

This workflow compares CRC-valid Ethernet frame observations in recordings from the city and village stations. It uses the PPS inventory for initial alignment, cross-correlation of the downlink for local synchronization, and the SNR dataset for screening and contextual information.

`run_frame_analysis.m` supports a full run over a configurable calendar interval and a limited test run. By default, it reports the first 10 confirmed stable seconds from each eligible recording pair, with a minimum of 5 successfully decoded selected seconds. This is a survey of selected stable intervals, rather than complete decoding of every minute-long recording.

## Requirements and inputs

Requires MATLAB R2020b or later, Signal Processing Toolbox, and Communications Toolbox. Keep all MATLAB files in this folder and select it as the MATLAB Current Folder, or add it to the MATLAB path.

Prepare these inputs:

- A PPS inventory MAT file containing `pps_results`, including the city and village file tables and pulse onset/end vectors.
- An SNR MAT file containing `snr_results`, a `metadata.bands` table with the 3839 MHz / 1 MHz band, and five-second SNR timetables for both stations.
- City and village RAW roots, each containing daily `ddMMyy` folders with `<index>_<HHMMSS>_<ddMMyy>.raw` recordings.
- Companion JSON metadata, when available, with sample rate and center frequency matching the recording configuration.

The RAW format is little-endian interleaved int16 I,Q, at 10 MS/s with an IF center of 1312 MHz. The analyzed downlink is at RF 3839 MHz, corresponding to IF 1311 MHz for a 5150 MHz LNB LO. Synchronization uses a 2 MHz channel; the imported SNR band has a 1 MHz bandwidth.

## Select dates and run

Edit section 1 of `run_frame_analysis.m` to set the actual locations of the two input MAT files and the two RAW roots. The supplied paths are examples and must be updated before use. Use MAT files directly, rather than ZIP archives.

Set the inclusive date bounds:

```matlab
C.analysisStartDate=datetime(2026,9,25);
C.analysisEndDate=datetime(2026,9,30);
```

Change either date to select the desired number of days. To analyze one day, use the same start and end date. To use every date represented in the inventory, set both to `[]`.

Dates are read from the RAW filenames without timezone conversion. With an active date filter, filenames without a valid date are excluded with a warning. The selected dates limit candidate recording pairs; they do not create missing recordings or establish complete campaign coverage. Both input MAT datasets and the available RAW files must cover the requested recordings.

Optional `C.fileNames` restricts the selection to explicit filenames within the date range. Leave it as `strings(0,1)` for all candidate pairs in that range. Names requested explicitly must be present after date filtering.

Run:

```matlab
run_frame_analysis
```

A new `results/FRAME_FULL_<timestamp>` folder is created alongside the scripts. Missing station counterparts remain in the candidate list so that exclusions can be recorded in `pair_audit.csv`.

## Limited test mode

In section 2, set:

```matlab
test_mode=true;
max_test_pairs=5;
```

This uses the same synchronization, decoding, screening, and export logic as a full run, but processes at most the first five selected candidate filenames. The limit counts attempted pairs, including excluded or failed pairs. It is applied after the date and optional filename filters. It follows inventory-name ordering and does not select a random sample or five guaranteed successful pairs.

Use `C.fileNames` to target specific recordings when testing. Inspect `pair_audit.csv`, per-pair MAT diagnostics, `all_seconds.csv`, and `summary.csv` before starting a larger run. Test output is written to a separate `results/FRAME_TEST_<timestamp>` folder. Set `test_mode=false` to process all selected pairs.

## Stable-second selection

The launcher sets:

```matlab
C.firstStableSeconds=10;
C.minimumStableSeconds=5;
C.analysisIntervalS=[];
```

The algorithm scans forward after the PPS interval until enough stable seconds and supporting context have been confirmed. Stable seconds may come from separate accepted runs; isolated runs shorter than three consecutive stable seconds do not qualify. If fewer than 10 are available, the selected seconds remain eligible only if the minimum requirements are met. At least 5 selected seconds must also decode successfully for the pair to contribute frame counts.

The selected report seconds are fixed before decoding. A later context second does not replace a selected second that fails decoding. Context windows may require synchronizing and decoding additional seconds beyond the reported selection.

The target and minimum can be changed in the launcher. For full available-second analysis, set `C.firstStableSeconds=0` and keep `C.analysisIntervalS=[]`. To report a fixed interval on the city RAW axis instead, set `C.firstStableSeconds=0` and, for example, `C.analysisIntervalS=[5 15]` for whole-second blocks beginning at 5 through 14 seconds. First-stable selection and a fixed interval cannot be enabled together.

The first stable seconds are not a random time sample. Report the chosen selection mode with any long-term results.

## Synchronization and acceptance

Recording pairs are identified by the RAW filename. Both stations must have a positive PPS inventory result and four complete, consecutive final PPS pulses with usable onset and end estimates. The initial truncated pulse is excluded by these checks. File sizes are checked against the inventory; available JSON sample-rate and center-frequency metadata are also validated.

Analysis starts no earlier than 5 seconds and after the PPS guard interval. Only whole city seconds are planned. A mapped village interval must also fit inside its RAW recording.

Each second is checked using probes at offsets 0.03, 0.49, and 0.95 seconds. Each probe uses a 1 ms correlation pilot and a separate validation segment at 10 to 18 ms. The search jointly estimates delay and carrier-frequency offset, within a CFO range of +/-20 kHz.

Default acceptance requires correlation of at least 0.20, a primary-to-secondary peak ratio of at least 1.30, a maximum away from the search boundaries, and pilot/validation delay agreement within 20 microseconds. A local search spans +/-0.5 ms around the last confirmed delay. If it fails, candidate discovery spans +/-0.5 seconds around the coarse PPS delay using a narrower 200 kHz channel, followed by confirmation in the full 2 MHz channel.

All three probes must pass. The affine delay model must have residuals no larger than 20 microseconds and drift magnitude no larger than 100 ppm. Adjacent usable seconds must agree at their common boundary within 40 microseconds. At least three consecutive stable seconds are required per accepted run. An unresolved second or delay jump breaks continuity.

These are operational acceptance criteria. They do not prove sample continuity between probes or establish UTC timing accuracy.

## Decoding and frame comparison

The decoder performs BPSK carrier and symbol synchronization, convolutional FEC decoding with constraint length 7 and generators `[133 171]`, descrambling, recovery of the `496 + 16*(280+9)` multiplex, HDLC bit destuffing, and FCS validation.

Only payloads passing HDLC FCS-16 and basic Ethernet format checks are compared. The HDLC FCS is removed before comparison. A separate Ethernet FCS is not validated, and the complete physical-layer standard is not identified.

Matches require equality of every exported frame byte and compatible synchronized time intervals within the configured 2 ms matching tolerance. Repeated transmissions of identical bytes are separate occurrences, matched one to one.

| Field | Meaning |
| --- | --- |
| `City_Total` | Counted valid frame occurrences at the city station |
| `Village_Total` | Counted valid frame occurrences at the village station |
| `Common` | Matching occurrences observed at both stations |
| `City_Only` | Counted city occurrences without a compatible village counterpart |
| `Village_Only` | Counted village occurrences without a compatible city counterpart |
| `Common_Over_Village` | `Common / Village_Total`, or `NaN` when the denominator is zero |

The count identities are `Common + City_Only = City_Total` and `Common + Village_Only = Village_Total`. The aggregate ratio is the sum of `Common` divided by the sum of `Village_Total`, rather than the mean of per-second ratios. `Ambiguous_Repeated_Matches` flags additional nearby possible counterparts with identical bytes.

These metrics describe successfully observed and decoded frame occurrences. They are not direct measurements of BER or end-to-end network packet loss. Zero decoded frames alone does not establish that no traffic was transmitted.

### Timing, context, and boundaries

Frame positions are traced back through the multiplex, descrambler, FEC, and symbol synchronizer to the RAW time axis. Relative timestamps from PCAP exports are not used. FIR group delay and decoder trimming are accounted for.

The variable-rate symbol synchronizer processes 2048-sample chunks at 4.096 MHz. Symbol times are assigned conservative intervals spanning the consumed input chunk, extended by 32 symbols at each end. The resulting interval width is approximately 0.5625 ms; this is an engineering timing guard, rather than a calibrated UTC uncertainty. The incomplete final input chunk is discarded. Symbol-count consistency checks can reject unreliable timing, but passing them alone does not prove symbol lock.

Each second is decoded with up to 0.4 seconds of context on both sides, within its accepted stable run. Observations from overlapping windows are reconciled per station before station matching. Duplicate observations of one occurrence are combined while preserving repeated transmissions. Ambiguous associations and boundary counterparts are excluded jointly so that they do not become false station-only counts.

Counted start times must lie safely inside a second, with 3 ms boundary guards. Stable-run boundaries also apply a 30 ms decoder startup guard and a 20 ms tail guard. The entire frame, including its closing HDLC flag, must lie in the usable stable run. `Counted_Start_Interval_Lo_s` and `Counted_Start_Interval_Hi_s` record the counted start interval.

Counts therefore cover safely assignable occurrences, rather than a guaranteed complete inventory of every frame in the full second. `Excluded_Context_Or_Boundary_*` includes intentional context outside the counted second and must not be summed across seconds as a count of unique lost frames.

## SNR screening

Imported five-second SNR bins are aligned to each recording using the timetable timestamp and the nominal RAW filename time. They are not treated as new one-second SNR measurements. The village query uses the corresponding mapped time interval.

Two screening stages are retained:

1. Whole-record screening uses a duration-weighted mean of linear SNR ratios. By default, both stations must have mean SNR no greater than 0 dB, at least 80% valid coverage, and no valid bin above the threshold when burst protection is enabled. Only then is the pair skipped as `record_likely_noise_snr`. Set `C.skipRecordLikelyNoise=false` to disable this stage.
2. Per-second screening classifies overlapping SNR bins as `likely_noise`, `signal_likely`, `uncertain`, or `unknown`. It requires complete processed coverage for a conclusive classification. A second is skipped as `joint_likely_noise` only when both stations are classified as likely noise. Set `C.skipJointLikelyNoise=false` to retain such blocks.

Weak city reception alone does not trigger either joint exclusion. Missing coverage does not by itself establish likely noise.

The optional per-second calibration uses the campaign-specific reference interval in `frame_config`: nominal RAW starts from 26 September 2026 at 13:00 to 27 September 2026 at 07:30, excluding the endpoint. Change `C.noiseReference` for another campaign, or set `C.useNoiseCalibration=false`.

For each station, calibration compares the 99th percentile of finite reference SNR values with the 1st percentile of the remaining finite values. With at least 20 values in each group and separation of at least 2 dB, the threshold is placed midway with an uncertainty margin of +/-1 dB. Otherwise, threshold-based classification is disabled. Nonpositive estimated signal power can still support a likely-noise classification. Low SNR is not proof of a service outage, and high SNR can also reflect interference.

Calibration uses the supplied SNR dataset; the recording date filter selects pairs without trimming that calibration dataset. Audit per-second SNR values are overlap-weighted averages in dB, distinct from the linear-ratio whole-record screening calculation. Calibration parameters are saved in `snr_calibration.mat`.

## Outputs

| File | Contents |
| --- | --- |
| `pair_audit.csv` | Pair status, exclusion/error messages, selected and analyzed seconds, record SNR, coverage, and processing times |
| `all_seconds.csv` | Reported seconds from processed pairs, with status, delay, drift, SNR, frame counts, and ratios |
| `*_seconds.csv` | Reported results for one recording pair |
| `*_all_blocks.csv` | All planned blocks, including context/selection flags when applicable |
| `*_frames.mat` | Per-pair `P` structure with synchronization probes, models, SNR, decoder diagnostics, frame bytes, and matching details |
| `summary.csv`, `summary.mat` | Aggregate counts, ratio, and pair inclusion/exclusion totals |
| `run_config.mat` | Saved configuration and compatibility identity |
| `snr_calibration.mat` | SNR calibration and thresholds |

Excluded or unreliable seconds have frame counts `NaN`; successfully decoded seconds with no frames have zero counts. A pair status of `processed` means the workflow completed for that pair, rather than that every planned second decoded successfully. Inspect per-second status and decoder diagnostics, including FEC checks and `framing.independently_validated`.

Other important statuses include `insufficient_stable_seconds`, `record_likely_noise_snr`, `joint_likely_noise`, `unresolved_sync`, `unstable_within_second`, `mapped_interval_outside_raw`, `unconfirmed_short_run`, `timing_unreliable`, and `decode_error`.

`Excluded_Seconds` summarizes excluded rows in the reported selection. It does not represent the first PPS seconds, unused portions outside the selected mode, partial file tails, or complete missing pairs. Pair-level exclusions are documented in the audit. Processing-time columns describe the current invocation, rather than cumulative time across resumptions.

## Resume an interrupted run

Checkpoints are saved after synchronization and decoding steps. To resume:

```matlab
R=resume_frame_analysis;
```

Select the existing output folder containing `run_config.mat`, or pass its path directly:

```matlab
R=resume_frame_analysis('D:\results\FRAME_FULL_20261028_120000_000');
```

The saved configuration is restored, compatible completed steps are reused, and an interrupted unsaved step may be repeated. Running `run_frame_analysis` starts a new run.

Use the same source package, input MAT files, RAW files, and analysis configuration when resuming. Compatibility checks use file sizes and modification times along with the configuration; these are not cryptographic content hashes. Changed date bounds or processing settings require a new output folder. Completed `decode_error` blocks are not automatically retried; after addressing their cause, start a new run for the affected selection.

## File roles

| File or group | Role |
| --- | --- |
| `run_frame_analysis.m` | User configuration, date range, and full/test mode |
| `resume_frame_analysis.m` | Restore an interrupted run |
| `analyze_frames.m` | Pair scheduling, processing, checkpointing, and exports |
| `frame_config.m`, `frame_select_dates.m`, `frame_input.m` | Defaults, date filtering, and input validation |
| `frame_sync_dsp.m`, `frame_sync_probe.m`, `frame_stable_runs.m` | Cross-correlation, local delay models, and stable runs |
| `frame_first_stable_pick.m`, `frame_interval_selection.m` | Report-second and context selection |
| `frame_decode.m`, `frame_timing_guard.m` | Frame decoding and symbol timing checks |
| `frame_snr.m` | SNR import, calibration, and screening |
| `frame_compare.m`, `frame_reconcile.m` | Occurrence matching and overlap reconciliation |
| `frame_result_table.m` | Per-second and aggregate result tables |
