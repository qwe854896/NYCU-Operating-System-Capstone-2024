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

flash:
	echo "Replace /dev/sdX with your SD card device!"
	sudo dd if=$(TARGET).img of=/dev/sdX bs=4M status=progress conv=fsync

clean:
	rm -rf qemu.pid .zig-cache zig-out

