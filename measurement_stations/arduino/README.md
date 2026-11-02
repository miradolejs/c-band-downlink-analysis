# Arduino Station Controller

Firmware for the Arduino UNO R3 used for GPS-based marker enable timing and environmental telemetry forwarding.

## Source

Open `station_controller/station_controller.ino` in the Arduino IDE and select the Arduino UNO board and the appropriate serial port. The sketch and its containing directory have matching names.

Required libraries are **TinyGPSPlus** (header `TinyGPS++.h`), **ModbusMaster**, and **SoftwareSerial** from the AVR board platform. Exact library versions were not supplied.

## Pin assignments

| Arduino pin | Connection |
|---|---|
| D4, software RX | NEO-7M TX |
| D3, software TX | NEO-7M RX through the documented interface network |
| D2, output | Custom relay control input |
| D10, software RX | RS-485 converter RO |
| D13, software TX | RS-485 converter DI |
| D11, output | RS-485 converter DE and /RE |
| USB serial | Raspberry Pi, 115200 baud |

GPS and RS-485 serial links both operate at 9600 baud. The code switches the active SoftwareSerial listener between them.

See the [hardware wiring diagrams](../hardware/README.md) for power connections and circuit details.

## Marker enable timing

The sketch parses GPS date and time. It includes Czech local-time conversion, although the relay trigger uses only the seconds field.

On observing a new GPS second equal to **59**, it sets D2 high and records `millis()`. D2 is set low after at least **5500 ms**, when the loop next checks the elapsed interval.

Thus the nominal enable window starts near the end of the preceding minute and extends approximately 4.5 seconds into the next minute. GPS message arrival, loop execution, and blocking Modbus transactions affect the actual switching time.

The enable event occurs **every minute**, not only at ten-minute recording slots. The Arduino does not receive acquisition start notifications from the Raspberry Pi.

The Arduino does not generate the precise PPS edges or the 100 ms marker pulse width. Its output enables the external relay/optocoupler control path; the GPSDO PPS and external RF switch define the injected marker pulses. The number and completeness of pulses captured at the start of a recording must be determined from the IQ data.

The sketch checks GPS date/time validity but does not impose a freshness timeout. Loss of fresh GPS messages is therefore not equivalent to an explicit invalid-time state in this implementation.

## Environmental telemetry

Approximately every **2 seconds**, the controller reads four holding registers from Modbus RTU slave **1**, starting at zero-based address **0**.

| Registers | Quantity |
|---|---|
| 0–1 | Temperature, 32-bit float |
| 2–3 | Relative humidity, 32-bit float |

The word layout is reconstructed using a `float`/`uint16_t[2]` union matching the Wemos firmware. The first register contains the low 16-bit word on the intended platforms. Modbus byte transport is handled by the libraries.

Successful readings are forwarded over USB as:

```text
ENV:T:10.13,H:65.20
```

This format matches the parser in [`../raspberry_pi/src/recorder.py`](../raspberry_pi/src/recorder.py).

Failed requests produce `Modbus chyba`. Other diagnostic lines can also appear when GPS time or GPS input is unavailable. These lines are not environmental messages. The Raspberry Pi parser rejects non-`ENV:` lines; a recording may therefore have invalid environmental metadata even when other readings succeeded.

## Related firmware

The matching Modbus sensor firmware is documented in [`../wemos/README.md`](../wemos/README.md).

## Validation status

This package preserves the supplied source and documents its behavior by code inspection. It has not been compiled or tested on hardware in this environment.
