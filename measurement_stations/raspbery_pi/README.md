# Raspberry Pi IQ Acquisition Software

This directory contains the acquisition and monitoring software supplied from the measurement station. The four files under `src/` are preserved unchanged, including their original Czech comments and interface messages.

## Directory structure

```text
raspberry_pi/
├── README.md
├── requirements.txt
├── .gitignore
└── src/
    ├── recorder.py
    ├── shared_state.py
    ├── web.py
    └── templates/
        └── index.html
```

| File | Purpose |
|---|---|
| `src/recorder.py` | SDR initialization, acquisition scheduling, RAW/JSON writing, environmental input, SSD buffering, and disk exchange control |
| `src/shared_state.py` | Default process-local status dictionary and thread lock |
| `src/web.py` | Flask status interface and disk exchange endpoints |
| `src/templates/index.html` | Browser interface with status polling and exchange controls |

The original `venv/` and empty runtime directories are not included. A new environment should be created on the target Raspberry Pi.

## Dependencies

The supplied virtual environment configuration identifies **Python 3.13.5** and `include-system-site-packages = true`. It contains pip 25.1.1 but no application dependency distributions from which an exact version lock could be reconstructed.

Required components are:

- Python 3 and NumPy.
- Flask for the web interface.
- pyserial for environmental telemetry.
- SoapySDR, including Python bindings accessible to the selected interpreter.
- The FOBOS device library and compatible SoapySDR support module.

`requirements.txt` lists direct Python dependencies without version pins. It is not a lock file or a complete record of the original system installation. Installing these dependencies alone does not install the SDR driver stack.

The following environment setup mirrors the original use of system packages. Run it from this directory, after the system-level SDR prerequisites are available:

```bash
python3 -m venv --system-site-packages venv
source venv/bin/activate
python -m pip install -r requirements.txt
```

This package was checked by parsing the Python sources. Acquisition, USB access, the web interface, and package compatibility have not been tested here on Raspberry Pi hardware.

## Configuration before acquisition

Configuration is embedded in the supplied source files; there is no separate configuration loader.

### Acquisition parameters

In `src/recorder.py`:

| Setting | Supplied value |
|---|---|
| `SAMPLE_RATE` | `10e6` complex samples/s |
| `FREQ` | `1312e6` Hz, IF after LNB conversion |
| `GAIN` | `0` dB, passed to the overall SoapySDR gain setter |
| `BLOCK_SIZE` | `4096` complex samples per read request |
| External reference selection | `sdr.writeSetting("clock_source", "1")` |
| SoapySDR stream format | `CF32` |
| Stored component format | Native-endian `int16`; little-endian on the acquisition platform |

The device is opened using `SoapySDR.Device()` without a serial-number selector. Ensure that this selects the intended receiver. The clock-source setting depends on the installed FOBOS support module.

### Schedule in this source snapshot

| Constant | Local system time |
|---|---|
| `START_PHASE1` | 15 October 2026, 23:55:00 |
| `START_PHASE2` | 16 October 2026, 00:00:00 |
| `END_TIME` | 25 October 2026, 23:59:00 |

Phase 1 requests 50-second recordings every minute. Phase 2 requests 60-second recordings every ten minutes. Scheduled slots already passed when the program starts are skipped during initial schedule alignment.

The second measurement campaign began on 16 October 2026 at 00:00 local time, corresponding to START_PHASE2. START_PHASE1 defines the preceding preparatory schedule and is not the start of the published dataset.

These are historical configuration values, not reusable defaults. Change them before a new deployment.

The scheduler uses local system time. NTP configuration is external to this program. Fine inter-station timing is established later using recorded markers and signal analysis.

### Storage paths

| Setting | Supplied path |
|---|---|
| `HDD_MOUNT` | `/media/admin/Elements` |
| `HDD_DIR` | `/media/admin/Elements/iq_data` |
| `SSD_DIR` | `/home/admin/iq_recorder/ssd_buffer` |

Adapt these paths to the target installation and verify write permissions. `SSD_DIR` must actually reside on the intended SSD; its name alone does not select a storage device.

Update `HDD_DIR` in `src/web.py` as well if the HDD location changes. The original empty `data/` and `logs/` directories are not used as output destinations by the supplied scripts. Console output is not automatically written to a log file.

### Environmental input

The recorder opens `/dev/ttyUSB0` at **115200 baud**, with a 0.2-second read timeout. Update the device path if required.

Expected serial message format:

```text
ENV:T:10.13,H:100.00
```

Environmental input is read after each acquisition. A missing or unparseable message produces null environmental values and `env_valid = false`. This version does not check reading age. If the serial port cannot be opened during initialization, it is not automatically reopened later.

## Starting the programs

Use the same configured Python environment in two separate terminals. From this directory, start acquisition with:

```bash
python src/recorder.py
```

Start monitoring separately:

```bash
python src/web.py
```

The browser interface is served at:

```text
http://<raspberry-pi-address>:5000/
```

The web process binds to `0.0.0.0:5000`. The supplied interface has no authentication and is intended for the controlled station network.

The web application does not start or stop acquisition or edit the schedule. No systemd units or other automatic startup scripts were included in the supplied archive.

## Status and process communication

The recorder and web application are separate processes. They communicate through files rather than a shared in-memory dictionary:

| Path | Purpose |
|---|---|
| `/tmp/recorder_status.json` | Recorder status read by the web application |
| `/tmp/swap_flag` | Request to prepare for HDD exchange |
| `/tmp/confirm_swap_flag` | Confirmation that the replacement HDD is available |

The recorder replaces the status JSON using a temporary file. If it is unavailable, the web application returns its own default status dictionary. Displayed status should therefore be interpreted together with recorder operation and logs.

Run only one recorder instance per station and ensure that both processes have compatible permissions for these files.

## Manual HDD exchange and SSD buffering

The browser controls retain their original Czech labels:

1. Select **Výměna disku** to request exchange.
2. Wait for **Můžeš odpojit disk**. The recorder waits until idle, calls `os.sync()`, and selects SSD buffering.
3. Unmount the old HDD using the operating system before physically disconnecting it. The application does not perform an unmount or device power-off itself.
4. Connect and mount the replacement HDD at the configured mount point. Verify the output directory and permissions.
5. Select **Disk vyměněn** to confirm the exchange.

In phase 2, pending buffered recordings are moved to the HDD between scheduled acquisitions. RAW files and their matching JSON metadata are moved together where metadata is available. Transfer is sequential and may delay a scheduled recording if it takes too long.

The recorder also selects SSD storage at the start of a recording if the HDD mount is unavailable. A write error during an active HDD recording ends that recording; the same file is not seamlessly continued on SSD.

Below 5 GiB of free SSD space the program logs a warning. Below 1 GiB it returns without starting the sample-writing loop. Free-space thresholds do not reserve enough space for a complete recording.

## Recorded files

Daily directories use `DDMMYY`. Each recording produces matching files:

```text
N_HHMMSS_DDMMYY.raw
N_HHMMSS_DDMMYY.json
```

I and Q components are clipped independently to `[-1, 1]`, multiplied by 32767, converted to `int16`, and written in interleaved order without a header. Actual sample-based duration is `samples_recorded / sample_rate`, rather than necessarily the nominal wall-clock duration.

The JSON `write_error` flag records caught sample-write errors, not every possible SDR streaming error. Timestamps are software references rather than hardware timestamps of the first sample.

See [Data formats](../../docs/data_formats.md) for the complete recording specification.

## Related documentation

- [Measurement stations](../README.md)
- [Hardware](../hardware/README.md)
- [Measurement methodology](../../docs/measurement_methodology.md)
- [Data formats](../../docs/data_formats.md)
