# Documentation

This directory contains documentation for the C-band satellite downlink measurement and analysis project.

The experiment compares reception at two locations using identical measurement stations: an urban site in Zlín near terrestrial transmitters and a rural reference site in Hošťálkova. The aim is to assess the potential impact of terrestrial transmissions, particularly 5G networks, on satellite reception, including variations between daytime and nighttime.

## Documentation structure

| Document | Description |
|---|---|
| [project_overview.md](project_overview.md) | Project objectives, scope, and research questions. |
| [measurement_methodology.md](measurement_methodology.md) | Measurement setup, acquisition parameters, timing synchronization, and measurement procedure. |
| [station_locations.md](station_locations.md) | Description of both sites, installation conditions, and relevant environmental differences. |
| [data_formats.md](data_formats.md) | IQ recording format, file naming conventions, metadata, and analysis output formats. |
| [analysis_workflow.md](analysis_workflow.md) | Overview of the analysis methods, required inputs, processing order, and generated outputs. |

## Related directories

- [`../measurement_stations/`](../measurement_stations/) — Hardware schematics, wiring, Raspberry Pi software, and Arduino and Wemos firmware.
- [`../analysis/`](../analysis/) — Data processing and visualization scripts.
- [`../results/`](../results/) — Analysis outputs, tables, and figures.
- [`../data/`](../data/README.md) — Archive organization, access status, catalog generation, and short IQ example tools.
- [`../reports/`](../reports/README.md) — Public technical evaluation of the project and its outputs.
