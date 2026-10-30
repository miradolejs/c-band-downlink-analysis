# Third-party materials and dependencies

These notices identify third-party materials and dependencies associated with the repository. They do not grant rights to third-party content, replace upstream license notices, or certify permissions for every possible use. The license allocation and exclusions are specified in [LICENSING.md](LICENSING.md).

## Identified third-party imagery

| Repository path | Identified origin and treatment |
| --- | --- |
| `measurement_stations/hardware/photos/rural_installation_location.png` | Panorama imagery attributed in repository captions to [Mapy.com](https://mapy.com/). The project added an installation-location arrow. Underlying imagery is excluded from the general CC-BY-4.0 grant. |
| `measurement_stations/hardware/photos/rural_reception_view.png` | Panorama imagery attributed in repository captions to Mapy.com. Underlying imagery is excluded from the general CC-BY-4.0 grant. |
| `docs/figures/station_system_overview.png` | Includes representative equipment illustrations. Contains representative equipment illustrations; the complete image is excluded from the general CC-BY-4.0 grant unless separately identified otherwise. |

The Mapy.com attribution identifies a source, not a verified permission to redistribute, alter, or sublicense the imagery. Preserve original source credits and markings. Applicable panorama/map terms and permissions must be checked for the actual image source and intended distribution; this notice does not assign an upstream license. Material whose publication is not permitted must be replaced, removed, or separately authorized for the relevant distribution.

Third-party trademarks, product names, and logos retain their respective rights. The repository licenses do not grant trademark rights or imply endorsement by equipment manufacturers, ESA, JIC, Libre Space Foundation, UTB, or other named organizations.

## Captured and decoded communication content

The public I/Q excerpts in `data/examples/` and decoded PCAP files in `results/downlink_frames/demodulation_pcap/` derive from received signals. Their creation as measurement files does not by itself establish authority to license all underlying communication content. The default public grant therefore excludes those payloads and any copies embedded in other file formats. Publication or reuse of excluded content must rely on an applicable permission or other lawful basis, independently of the licenses for original project material.

Original measurement metadata, explanatory text, and numerical/statistical products remain separately assessable. No conclusion about the legality, confidentiality, personal-data status, or ownership of an entire received transmission is implied by these notices.

## External software dependencies

The following names are referenced by the current source code or processing requirements. They are dependencies, not components relicensed by this repository. A dependency list is not a complete license audit and does not establish the exact installed upstream version.

| Referenced dependency | Observed use | Treatment |
| --- | --- | --- |
| MATLAB, Signal Processing Toolbox, Communications Toolbox | MATLAB processing and demodulation | Obtain and use under MathWorks terms; no MathWorks license is supplied by the repository. |
| SoapySDR and FOBOS support/driver stack | Raspberry Pi receiver access | Retain and comply with licenses of the specific installed components. |
| NumPy | Raspberry Pi sample conversion | Retains its upstream license; project Apache notices do not replace it. |
| Flask | Raspberry Pi web monitoring | Retains its upstream license. |
| pyserial (`serial`) | Raspberry Pi environmental telemetry | Retains its upstream license. |
| TinyGPS++ (`TinyGPS++.h`) | Arduino GPS parsing | Retain the notices and license supplied with the specific upstream version. |
| ModbusMaster (`ModbusMaster.h`) | Arduino RS-485 communication | Retain the notices and license supplied with the specific upstream version. |
| Library providing `ModbusRTU.h` | Wemos RS-485 communication | The upstream package/version used determines its obligations; the header name alone does not identify a unique license. |
| Adafruit AHTX0 (`Adafruit_AHTX0.h`) and required support libraries | Wemos sensor access | Retain licenses and notices for the installed library and its dependencies. |
| SoftwareSerial, Wire, and the selected Arduino/ESP8266 cores | Firmware serial and I2C interfaces | Retain the relevant upstream terms; distributions of linked firmware require separate compatibility review. |
| Python standard library | Acquisition and dataset tools | Retains its upstream terms. |

The project license does not establish that external dependencies or any linked firmware binary are Apache-only. If upstream source, headers, templates, assets, or binaries are copied into the repository or a delivery package, preserve their license texts and required notices and check compatibility before redistribution. Directly incorporated code must be identified independently of imports and includes.

## Attribution and scope

Preserve existing author and copyright notices for incorporated content and dependencies. Where a directory contains both original project and third-party material, the narrower per-file or per-component terms apply. The presence of a file in this repository does not make UTB, the GitHub account holder, or the research team the owner of every element in that file.
