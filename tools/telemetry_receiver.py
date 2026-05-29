#!/usr/bin/env python3
"""telemetry_receiver.py

Receive and (optionally) live-plot RC-Flight-Sim UDP telemetry packets.

The packet format is documented in docs/telemetry_protocol.md and produced by
godot_project/scripts/net/telemetry_transmitter.gd.

Usage:
    # Print decoded packets to stdout:
    python3 telemetry_receiver.py --host 0.0.0.0 --port 9001

    # Live graph of airspeed / altitude (requires matplotlib):
    python3 telemetry_receiver.py --port 9001 --graph

This script has no required third-party dependencies for the print mode; the
--graph mode uses matplotlib if it is installed.
"""
from __future__ import annotations

import argparse
import socket
import struct
import sys
from collections import deque

# --- Protocol constants (keep in sync with telemetry_transmitter.gd) --------
MAGIC = 0x52434654  # "RCFT"
VERSION = 1

# Header: magic (uint32) + version (uint16). Payload: 19 little-endian float32:
#   timestamp,
#   pos.x, pos.y, pos.z,
#   quat.x, quat.y, quat.z, quat.w,
#   vel.x, vel.y, vel.z,
#   ang.x, ang.y, ang.z,
#   rpm,
#   aileron, elevator, rudder, throttle
HEADER_FMT = "<IH"
PAYLOAD_FMT = "<19f"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
PACKET_SIZE = HEADER_SIZE + struct.calcsize(PAYLOAD_FMT)

FIELD_NAMES = [
    "t", "px", "py", "pz",
    "qx", "qy", "qz", "qw",
    "vx", "vy", "vz",
    "wx", "wy", "wz",
    "rpm", "aileron", "elevator", "rudder", "throttle",
]


def decode(packet: bytes) -> dict | None:
    """Decode a single telemetry packet into a dict, or None if invalid."""
    if len(packet) != PACKET_SIZE:
        return None
    magic, version = struct.unpack_from(HEADER_FMT, packet, 0)
    if magic != MAGIC or version != VERSION:
        return None
    values = struct.unpack_from(PAYLOAD_FMT, packet, HEADER_SIZE)
    return dict(zip(FIELD_NAMES, values))


def airspeed(d: dict) -> float:
    return (d["vx"] ** 2 + d["vy"] ** 2 + d["vz"] ** 2) ** 0.5


def run_print(sock: socket.socket) -> None:
    print(f"Listening for telemetry (packet size {PACKET_SIZE} bytes)...")
    while True:
        packet, _addr = sock.recvfrom(2048)
        d = decode(packet)
        if d is None:
            print("  [skip] malformed/foreign packet")
            continue
        print(
            f"t={d['t']:8.2f}s  alt={d['py']:7.1f}m  "
            f"spd={airspeed(d) * 3.6:6.1f}km/h  rpm={d['rpm']:7.0f}  "
            f"thr={d['throttle']:.2f}"
        )


def run_graph(sock: socket.socket, window: int) -> None:
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib not installed; falling back to print mode.", file=sys.stderr)
        run_print(sock)
        return

    sock.setblocking(False)
    times: deque = deque(maxlen=window)
    spds: deque = deque(maxlen=window)
    alts: deque = deque(maxlen=window)

    plt.ion()
    fig, (ax_spd, ax_alt) = plt.subplots(2, 1, sharex=True)
    ax_spd.set_ylabel("Airspeed (km/h)")
    ax_alt.set_ylabel("Altitude (m)")
    ax_alt.set_xlabel("Time (s)")

    while True:
        # Drain all pending packets, keep the latest readings.
        try:
            while True:
                packet, _ = sock.recvfrom(2048)
                d = decode(packet)
                if d is None:
                    continue
                times.append(d["t"])
                spds.append(airspeed(d) * 3.6)
                alts.append(d["py"])
        except BlockingIOError:
            pass

        if times:
            ax_spd.cla(); ax_alt.cla()
            ax_spd.set_ylabel("Airspeed (km/h)")
            ax_alt.set_ylabel("Altitude (m)")
            ax_spd.plot(times, spds, color="tab:blue")
            ax_alt.plot(times, alts, color="tab:green")
        plt.pause(0.05)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0", help="Bind address")
    parser.add_argument("--port", type=int, default=9001, help="UDP port")
    parser.add_argument("--graph", action="store_true", help="Live plot (needs matplotlib)")
    parser.add_argument("--window", type=int, default=400, help="Graph sample window")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.host, args.port))

    try:
        if args.graph:
            run_graph(sock, args.window)
        else:
            run_print(sock)
    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        sock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
