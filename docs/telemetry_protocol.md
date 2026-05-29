# Telemetry Protocol (UDP)

RC-Flight-Sim can stream the live flight state of the active aircraft as a
compact binary UDP datagram. This is intended for external tools: live
plotting, data logging, motion platforms and research.

- **Transmitter:** `godot_project/scripts/net/telemetry_transmitter.gd`
  (autoload `TelemetryTransmitter`).
- **Reference receiver:** `tools/telemetry_receiver.py`.

## Enabling the stream

The stream is **off by default**. Enable it via `SettingsManager`:

| Setting key          | Default       | Meaning                          |
|----------------------|---------------|----------------------------------|
| `telemetry_enabled`  | `false`       | Master on/off switch             |
| `telemetry_host`     | `"127.0.0.1"` | Destination IP address           |
| `telemetry_port`     | `9001`        | Destination UDP port             |
| `telemetry_rate_hz`  | `20.0`        | Packet rate (Hz)                 |

At runtime: register the aircraft and turn the stream on.

```gdscript
TelemetryTransmitter.register_aircraft(aircraft_node)
TelemetryTransmitter.set_enabled(true)
```

## Packet layout

All multi-byte values are **little-endian**. Floats are IEEE-754 **32-bit**.
The total packet size is **82 bytes**.

| Offset | Type     | Field            | Notes                              |
|-------:|----------|------------------|------------------------------------|
| 0      | uint32   | magic            | `0x52434654` ("RCFT")              |
| 4      | uint16   | version          | currently `1`                      |
| 6      | float32  | timestamp        | seconds since engine start         |
| 10     | float32  | position.x       | metres, world space (X=East)       |
| 14     | float32  | position.y       | metres (Y=Up)                      |
| 18     | float32  | position.z       | metres (Z=South)                   |
| 22     | float32  | attitude.x       | orientation quaternion x           |
| 26     | float32  | attitude.y       | quaternion y                       |
| 30     | float32  | attitude.z       | quaternion z                       |
| 34     | float32  | attitude.w       | quaternion w                       |
| 38     | float32  | velocity.x       | m/s, world space                   |
| 42     | float32  | velocity.y       | m/s                                |
| 46     | float32  | velocity.z       | m/s                                |
| 50     | float32  | ang_velocity.x   | rad/s, body frame                  |
| 54     | float32  | ang_velocity.y   | rad/s                              |
| 58     | float32  | ang_velocity.z   | rad/s                              |
| 62     | float32  | motor_rpm        | propeller / engine RPM             |
| 66     | float32  | aileron          | command deflection [-1, 1]         |
| 70     | float32  | elevator         | command deflection [-1, 1]         |
| 74     | float32  | rudder           | command deflection [-1, 1]         |
| 78     | float32  | throttle         | command [0, 1]                     |

Equivalent Python `struct` formats:

```python
HEADER_FMT  = "<IH"    # magic, version
PAYLOAD_FMT = "<19f"   # timestamp + 18 state floats
```

## Versioning

Increment `PROTOCOL_VERSION` in `telemetry_transmitter.gd` whenever the layout
changes, and update both this document and the receiver's `VERSION` constant.
Receivers must reject packets whose `magic` or `version` does not match.

## Example

```bash
# Print decoded packets
python3 tools/telemetry_receiver.py --port 9001

# Live airspeed/altitude graph (requires matplotlib)
python3 tools/telemetry_receiver.py --port 9001 --graph
```
