# Wemos Environmental Sensor Interface

Firmware for a Wemos D1 mini (ESP8266) reading an AHT10 temperature/humidity sensor and exposing readings over Modbus RTU on RS-485.

## Source and dependencies

Open `environmental_sensor/environmental_sensor.ino` in the Arduino IDE with the ESP8266 board platform and the appropriate D1 mini board selected.

Required libraries are:

- `Wire` from the ESP8266 board platform.
- A compatible Modbus library providing `ModbusRTU.h` and the API used in the sketch.
- Adafruit AHTX0 (`Adafruit_AHTX0.h`) and its dependencies.

Exact board-platform and library versions were not supplied.

## Pin assignments

| Wemos pin | Connection |
|---|---|
| D2 / GPIO4 | AHT10 SDA |
| D1 / GPIO5 | AHT10 SCL |
| TX / GPIO1 | RS-485 converter DI |
| RX / GPIO3 | RS-485 converter RO |
| D6 / GPIO12 | RS-485 converter DE and /RE |

The sketch uses hardware `Serial` without pin swapping. It does **not** configure RS-485 data on D5/D8. The existing wiring image showing D5/D8 must be checked against the deployed wiring before this repository is used as an assembly guide. This package documents the supplied code rather than silently changing its pin assignments.

The hardware UART is also connected to the D1 mini USB-to-serial interface. Normal application traffic is Modbus at 9600 baud, not a human-readable USB log. Firmware upload and wiring must account for the shared UART.

## Sensor acquisition

The I2C interface is initialized using `Wire.begin(D2, D1)`. Sensor readings are acquired once during setup and then nominally every **1000 ms**. The Modbus service is processed repeatedly between updates.

This sketch does not check the return value of `aht.begin()` or publish a separate sensor-validity flag or measurement timestamp in the register map.

## Modbus interface

| Parameter | Value |
|---|---|
| Role | Slave/server |
| Address | 1 |
| Serial settings | 9600 baud, 8 data bits, no parity, 1 stop bit |
| Register type | Holding registers |
| Addresses | 0–3, zero-based |

| Registers | Meaning | Unit |
|---|---|---|
| 0–1 | Temperature as a 32-bit float | degrees Celsius |
| 2–3 | Relative humidity as a 32-bit float | percent RH |

Each float is split through a union into two 16-bit words. On the intended platform, the low word is stored first. The paired Arduino firmware reconstructs the same layout.

The Arduino polls the registers approximately every two seconds and formats the values for the Raspberry Pi. The Wemos itself does not generate `ENV:` text messages.

## Related documentation

- [Arduino station controller](../arduino/README.md)
- [Hardware documentation](../hardware/README.md)
- [Raspberry Pi acquisition software](../raspberry_pi/README.md)

## Validation status

The Modbus address, baud rate, register layout, and float reconstruction were compared with the supplied Arduino source. Compilation and hardware communication have not been tested in this environment.
