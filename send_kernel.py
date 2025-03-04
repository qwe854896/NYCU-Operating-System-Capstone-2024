#!/usr/bin/env python3
"""
send_kernel
"""

import sys
import struct
import serial

START_BYTE = 0xAC


def send_kernel(tty_path: str, kernel_path: str) -> None:
    """
    send_kernel
    """

    tty = serial.Serial(tty_path, baudrate=115200, timeout=1)

    with open(kernel_path, "rb") as f:
        data = f.read()

    size = len(data)
    print(f"Sending kernel of size {size} bytes")

    # Send start byte
    tty.write(bytes([START_BYTE]))
    tty.flush()

    # Send size as 4 bytes (little-endian)
    tty.write(struct.pack("<I", size))
    tty.flush()

    # Send the kernel binary data
    tty.write(data)
    tty.flush()

    print("Kernel sent successfully.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <tty_path> <kernel_path>")
        print(f"Example: {sys.argv[0]} /dev/ttyUSB0 kernel.bin")
        sys.exit(0)
    send_kernel(sys.argv[1], sys.argv[2])
