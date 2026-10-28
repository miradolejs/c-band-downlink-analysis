# Measurement Stations

This directory documents the design, hardware, and software of the two SDR stations used for C-band satellite downlink measurements.

The stations were deployed in Zlín and Hošťálková, Czech Republic. Both used the same principal equipment and acquisition settings, with installation differences documented in the measurement methodology.

## Directory structure

| Directory | Contents |
|---|---|
| [`hardware/`](hardware/) | Component list, schematics, wiring documentation, and installation photographs |
| [`raspberry_pi/`](raspberry_pi/) | IQ recording software, web interface, configuration, and service files |
| [`arduino/`](arduino/) | Arduino firmware and documentation for PPS marker timing and environmental data forwarding |

## Receiving system

Each station consisted of:

- Kathrein KEA 1000/G reflector, 100 cm diameter.
- Norsat 3620N C-band LNB with a 5150 MHz local oscillator.
- ZFBT-4R2GW-FT+ bias tee for LNB power supply.
- SSB Electronic Ecoflex 10 coaxial cable.
- FOBOS SDR receiver.
- Raspberry Pi 5 with 16 GB RAM.
- Leo Bodnar LBE-1425 two-port GPSDO.

The coaxial cable length was **17 m at the urban station** and **10 m at the rural station**.

Both antennas used nominal pointing settings of **180° azimuth**, **33° elevation**, and **horizontal receive polarization**.

A [functional overview of the station](../docs/project_overview.md#system-overview) is provided in the project documentation.

## IQ acquisition

The Raspberry Pi controlled the SDR, recorded IQ samples, and stored acquisition and environmental metadata.

| Parameter | Setting |
|---|---|
| IF centre frequency | 1312 MHz |
| Corresponding RF centre frequency | 3838 MHz |
| Sampling rate | 10 MS/s |
| Nominal recorded bandwidth | 10 MHz |
| SDR gain setting | 0 dB |
| Nominal recording duration | 60 seconds |
| Recording interval | 10 minutes |
| Stored sample format | Interleaved little-endian int16 I/Q |
| Recording files | RAW samples and matching JSON metadata |

Actual recording duration is determined from the stored sample count.

The acquisition software supports HDD recording, SSD buffering, and controlled storage replacement. A web interface provides access to recorder status and controls.

## Frequency and timing references

Each SDR used an external **10 MHz GPSDO reference** to improve frequency stability.

Recording starts were scheduled using the Raspberry Pi system clock synchronized through NTP. For finer alignment, GPSDO-derived PPS markers were injected into the recorded IF signal.

The marker subsystem used:

- HTOOL SA8 RF generator operating at **1315 MHz**.
- ADRF5144-EVALZ RF switch.
- Capacitive coupling into the receiving path.
- AND-gate control combining GPSDO PPS and an Arduino enable signal.
- NEO-7M GPS module for Arduino time synchronization.

A five-second enable window at the beginning of each recording allowed five nominal **100 ms** marker pulses. Four markers were used for alignment because the first was unsuitable due to recording-start timing.

Precise inter-station alignment was subsequently refined during analysis using cross-correlation. The external frequency reference alone does not establish phase coherence between the complete receiving chains.

## Environmental monitoring

An **AHT10 temperature and humidity sensor** was installed near each antenna inside a **TFA Dostmann 98.1114.02 radiation shield**.

A Wemos D1 mini read the sensor and transferred readings to the Arduino over RS-485. The Arduino forwarded environmental data to the Raspberry Pi over USB for inclusion in recording metadata.

The Wemos firmware should be retained alongside the Arduino documentation when added to this repository.

## Hardware documentation

The [`hardware/`](hardware/) directory is organized as follows:

| Path | Purpose |
|---|---|
| `component_list.csv` | Components and quantities |
| `schematics/` | Electrical and system schematics |
| `wiring/` | Cable connections, pin assignments, and installation notes |
| `photos/` | Photographs of both installations and their surroundings |

## Software setup

Installation instructions, dependencies, configuration examples, and startup procedures are documented in the respective software directories:

- [`raspberry_pi/`](raspberry_pi/)
- [`arduino/`](arduino/)

The acquisition schedule and local storage paths must be configured for the intended deployment.

## Related documentation

- [`Project overview`](../docs/project_overview.md)
- [`Measurement methodology`](../docs/measurement_methodology.md)
- [`Station locations`](../docs/station_locations.md)
- [`Data formats`](../docs/data_formats.md)
- [`Analysis workflow`](../docs/analysis_workflow.md)
