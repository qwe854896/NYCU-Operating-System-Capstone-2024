############################################################################
#
#  Utility commands
#
############################################################################

default:
  @just --list

debug:
  @pwndbg zig-out/bin/kernel8.elf -ex "target remote :1234"

flash dev:
  @python3 scripts/send_kernel.py {{dev}} zig-out/bin/kernel8.img

connect dev:
  @minicom -b 115200 -D {{dev}}

clean:
  @rm -rf .zig-cache zig-out

