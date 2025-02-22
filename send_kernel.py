#!/usr/bin/env python3
"""
send_kernel
"""

import sys
import struct

START_BYTE = 0xAC


def send_kernel(tty_path: str, kernel_path: str) -> None:
    """
    send_kernel
    """
    with open(tty_path, "wb", buffering=0) as tty:
        with open(kernel_path, "rb") as f:
            data = f.read()

        size = len(data)
        print(f"Sending kernel of size {size} bytes")

        # Send start byte
        tty.write(bytes([START_BYTE]))

        # Send size as 4 bytes (little-endian)
        tty.write(struct.pack("<I", size))

        # Send the kernel binary data
        tty.write(data)

        print("Kernel sent successfully.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <tty_path> <kernel_path>")
        print(f"Example: {sys.argv[0]} /dev/ttyUSB0 kernel.bin")
        sys.exit(0)
    send_kernel(sys.argv[1], sys.argv[2])
