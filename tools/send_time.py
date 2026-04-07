#!/usr/bin/env python3
"""
Send current time to the HDMI_VHDL FPGA clock over UART.

Accepted FPGA formats:
    HH:MM:SS\\n
    THH:MM:SS\\n

Examples:
    python3 tools/send_time.py /dev/tty.usbserial-0001
    python3 tools/send_time.py COM5 --prefix-t
    python3 tools/send_time.py /dev/ttyUSB0 --watch --interval 1
    python3 tools/send_time.py /dev/ttyUSB0 --time 12:34:56
    python3 tools/send_time.py ftdi://ftdi:2232h/2 --verbose
    python3 tools/send_time.py --tang-uart --ftdi-serial 2023030621 --verbose

Tang Nano 20K note:
    On the onboard debugger, channel 8209 is typically JTAG and
    channel 8210 is the UART side. If the OS does not expose a usable
    /dev/cu.* device, pyftdi can access the UART channel directly with
    ftdi://ftdi:2232h/2 or ftdi://ftdi:2232h:<serial>/2.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
import time

try:  # Optional dependency.
    import serial  # type: ignore
except ImportError:  # pragma: no cover
    serial = None

try:  # POSIX fallback for macOS/Linux.
    import termios
except ImportError:  # pragma: no cover
    termios = None

try:  # Optional direct FTDI access via libusb.
    from pyftdi.serialext import serial_for_url  # type: ignore
except ImportError:  # pragma: no cover
    serial_for_url = None


DEFAULT_BAUDRATE = 115200
DEFAULT_TANG_FTDI_URL = "ftdi://ftdi:2232h/2"


class PosixSerialWriter:
    def __init__(self, port: str, baudrate: int):
        if termios is None:
            raise RuntimeError(
                "pyserial is not installed and no POSIX termios backend is available."
            )

        baud_attr = getattr(termios, f"B{baudrate}", None)
        if baud_attr is None:
            raise RuntimeError(f"Unsupported baudrate for POSIX backend: {baudrate}")

        self._fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_SYNC)
        attrs = termios.tcgetattr(self._fd)

        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = baud_attr
        attrs[5] = baud_attr
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0

        termios.tcsetattr(self._fd, termios.TCSANOW, attrs)
        termios.tcflush(self._fd, termios.TCIOFLUSH)

    def write(self, data: bytes) -> None:
        os.write(self._fd, data)

    def flush(self) -> None:
        if termios is not None:
            termios.tcdrain(self._fd)

    def close(self) -> None:
        os.close(self._fd)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False


def tang_ftdi_url(serial_number: str | None) -> str:
    if serial_number:
        return f"ftdi://ftdi:2232h:{serial_number}/2"
    return DEFAULT_TANG_FTDI_URL


def open_serial_writer(port: str, baudrate: int):
    if port.startswith("ftdi://"):
        if serial_for_url is None:
            raise RuntimeError(
                "pyftdi non installato. Esegui: python3 -m pip install pyftdi"
            )
        return serial_for_url(port, baudrate=baudrate, timeout=0.2)
    if serial is not None:
        return serial.Serial(port, baudrate, timeout=0.2)
    return PosixSerialWriter(port, baudrate)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Send current time to the HDMI_VHDL FPGA over UART."
    )
    parser.add_argument(
        "port",
        nargs="?",
        help=(
            "Serial port name, for example /dev/tty.usbserial-0001 or COM5. "
            "On Tang Nano 20K the debugger usually exposes UART on channel 8210, "
            "or you can pass a pyftdi URL such as ftdi://ftdi:2232h/2."
        ),
    )
    parser.add_argument(
        "--tang-uart",
        action="store_true",
        help=(
            "Use Tang Nano 20K onboard debugger channel B directly through pyftdi "
            "(maps to ftdi://ftdi:2232h/2)."
        ),
    )
    parser.add_argument(
        "--ftdi-serial",
        help=(
            "Optional FTDI serial number used with --tang-uart, for example "
            "2023030621."
        ),
    )
    parser.add_argument(
        "--baudrate",
        type=int,
        default=DEFAULT_BAUDRATE,
        help=f"UART baudrate. Default: {DEFAULT_BAUDRATE}.",
    )
    parser.add_argument(
        "--time",
        dest="fixed_time",
        help="Explicit time to send in HH:MM:SS format. Defaults to local system time.",
    )
    parser.add_argument(
        "--utc",
        action="store_true",
        help="Use UTC instead of local time when --time is not provided.",
    )
    parser.add_argument(
        "--prefix-t",
        action="store_true",
        help="Send the alternate accepted frame format: THH:MM:SS.",
    )
    parser.add_argument(
        "--crlf",
        action="store_true",
        help="Terminate frames with CRLF instead of LF.",
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Continuously resend time at a fixed interval.",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Seconds between transmissions in --watch mode. Default: 1.0.",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=0,
        help="Number of frames to send in --watch mode. 0 means infinite.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print each transmitted frame.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Build and print frames without opening the serial port.",
    )
    return parser


def parse_hms(value: str) -> dt.time:
    try:
        return dt.datetime.strptime(value, "%H:%M:%S").time()
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"Invalid --time value '{value}'. Expected HH:MM:SS."
        ) from exc


def current_time(use_utc: bool) -> dt.time:
    now = dt.datetime.utcnow() if use_utc else dt.datetime.now()
    return now.time().replace(microsecond=0)


def make_frame(
    when: dt.time,
    prefix_t: bool,
    use_crlf: bool,
) -> bytes:
    payload = when.strftime("%H:%M:%S")
    if prefix_t:
        payload = "T" + payload
    suffix = "\r\n" if use_crlf else "\n"
    return (payload + suffix).encode("ascii")


def iter_frames(args: argparse.Namespace):
    sent = 0
    while True:
        when = parse_hms(args.fixed_time) if args.fixed_time else current_time(args.utc)
        yield make_frame(when, args.prefix_t, args.crlf)
        sent += 1
        if not args.watch:
            return
        if args.count > 0 and sent >= args.count:
            return
        time.sleep(args.interval)


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.interval <= 0:
        parser.error("--interval must be > 0")
    if args.count < 0:
        parser.error("--count must be >= 0")
    if args.tang_uart and args.port:
        parser.error("use either a port argument or --tang-uart, not both")
    if args.ftdi_serial and not args.tang_uart:
        parser.error("--ftdi-serial requires --tang-uart")
    if not args.port and not args.tang_uart:
        parser.error("port is required unless --tang-uart is used")

    port = tang_ftdi_url(args.ftdi_serial) if args.tang_uart else args.port

    try:
        if args.dry_run:
            for frame in iter_frames(args):
                sys.stdout.write(f"DRY RUN TX {frame!r}\n")
            return 0

        with open_serial_writer(port, args.baudrate) as ser:
            # Allow the adapter/device line state to settle before first frame.
            time.sleep(0.1)
            for frame in iter_frames(args):
                ser.write(frame)
                ser.flush()
                if args.verbose:
                    sys.stdout.write(f"TX {port} {frame!r}\n")
                    sys.stdout.flush()
    except Exception as exc:
        sys.stderr.write(f"Serial error: {exc}\n")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
