# Licensing

Original project material in this repository is made available by **Tomas Bata University in Zlín (UTB)** under the licenses and scope specified below. This repository contains both software and non-software materials; the root software license does not automatically apply to every file.

Explicit per-file licenses and the exclusions in this document take precedence over directory-level defaults. Third-party material retains its applicable rights and terms. Merely including material in the repository does not establish ownership or authority to relicense it.

## Software: Apache License 2.0

Except for separately identified third-party components, the following original project software is licensed under the **Apache License, Version 2.0** (`Apache-2.0`):

- MATLAB source files in `analysis/`.
- Python source files and original HTML templates in `measurement_stations/raspberry_pi/`.
- Arduino and Wemos `.ino` source files in `measurement_stations/arduino/` and `measurement_stations/wemos/`.
- Python source files and the archive configuration in `data/tools/`.
- The acquisition software's `requirements.txt` dependency declaration, without relicensing any listed dependencies.
- Original project executable code examples embedded in documentation, unless marked otherwise.

The complete unmodified software license is in [LICENSE](LICENSE). Project attribution and the original software copyright notice are in [NOTICE](NOTICE). External libraries, device drivers, firmware cores, MATLAB, and its toolboxes retain their own licenses.

## Documentation and original data products: CC BY 4.0

Except for excluded or separately licensed material, the following original project material is licensed under **Creative Commons Attribution 4.0 International** (`CC-BY-4.0`):

- Markdown prose, explanatory tables, and other original documentation throughout the repository, including README files.
- Original report text and original report illustrations in `reports/`, when included in the repository.
- Original analytical graphs and statistical tables, and project-created analytical datasets in `results/`.
- Original recording catalogs and inventory summaries in `data/catalog/`.
- Original metadata and explanatory material associated with the public examples in `data/examples/`, excluding captured communication payloads.
- Original project photographs, wiring diagrams, and explanatory schematics for which UTB holds the necessary licensing rights, subject to the third-party exclusions below.

The complete unmodified license text is in [LICENSES/CC-BY-4.0.txt](LICENSES/CC-BY-4.0.txt). This grant covers only rights held by the licensor, including applicable copyright and database rights covered by CC-BY-4.0. It does not create exclusive rights in unprotectable facts or measurements.

## Exclusions

The public licenses above do not grant additional rights to:

1. **Mapy.com panorama/map content**, including `measurement_stations/hardware/photos/rural_installation_location.png` and `measurement_stations/hardware/photos/rural_reception_view.png`. An annotation added by the project does not grant rights over the underlying imagery.
2. **Third-party photographs, equipment illustrations, artwork, screenshots, datasheets, logos, and trademarks**, including third-party elements embedded in otherwise original project materials. `docs/figures/station_system_overview.png`, which includes representative equipment illustrations, is excluded from the general CC-BY-4.0 grant as a complete image unless a separate notice states otherwise. Images without an established original-project provenance are not included merely because they appear in the repository.
3. **Captured I/Q payloads and decoded third-party communications.** The `.raw` excerpts under `data/examples/` and the PCAP payloads under `results/downlink_frames/demodulation_pcap/` are excluded from the general public license allocation. The same exclusion applies to captured or decoded communication content embedded in MAT, FIG, JSON, or other containers. Original metadata, explanatory text, and statistical analysis are distinct from that content. This exclusion does not assert ownership of all underlying transmissions or restrict statutory exceptions.
4. **The full externally hosted RAW/JSON archive and other unpublished deliverables.** These repository licenses do not automatically apply to an external archive. Archive access and contractual rights are described separately in [data/data_access.md](data/data_access.md).
5. **External software and incorporated third-party components**, which retain their upstream license terms and required notices.
6. **Information or data supplied by JIC, ESA, or another third party under separate terms**, except where an authorized notice expressly includes it in a public license grant.

Exclusion from these grants is not itself a determination that publication or any particular use of excluded material is authorized. Applicable third-party terms and permissions remain relevant. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for identified materials and dependencies.

## Attribution

Preserve existing author, copyright, license, and other required notices associated with each work. For original CC-BY-4.0 material, attribution should identify the project, the credited creators and attribution parties supplied with the material, the source, the license, and any changes made, as required by that license.

A practical attribution is:

> DUAL-STATION SDR SPECTRUM MEASUREMENT — Miroslav Dolejš, Anton Džima, Stanislav Kovář, and Eliška Štrajtová; Faculty of Applied Informatics, Tomas Bata University in Zlín. Source: https://github.com/miradolejs/c-band-downlink-analysis. CC BY 4.0: https://creativecommons.org/licenses/by/4.0/. Indicate any changes made.

This example is guidance, not an additional condition beyond CC-BY-4.0. Research credits do not transfer rights in third-party material. Naming a university, funder, collaborator, manufacturer, or other organization does not imply endorsement of downstream use.

## Contractual rights

These public licenses permit commercial reuse within their scope. No additional non-commercial restriction is appended to either standard license.

The public licenses do not amend or replace the separate project agreement or applicable rights and obligations of UTB, JIC, or ESA. In particular, the licenses do not remove separately agreed delivery, correction, assistance, confidentiality, or intellectual-property obligations. Access to an external archive and the use of excluded third-party content remain separate matters.
