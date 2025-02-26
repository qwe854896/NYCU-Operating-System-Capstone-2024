GDB = pwndbg
TARGET = zig-out/bin/kernel8

.PHONY: all clean run debug flash

all:
	zig build

run:
	zig build run

debug:
	zig build debug & echo $$! > qemu.pid
	$(GDB) -ex "file $(TARGET).elf" -ex "target remote :1234"

clean:
	rm -rf qemu.pid .zig-cache zig-out

