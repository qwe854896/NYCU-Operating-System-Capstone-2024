ARCH = aarch64
MODEL = raspi3b
GDB = pwndbg

CROSS_COMPILE ?= $(ARCH)-linux-gnu-
CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
QEMU = qemu-system-$(ARCH)
ZIG = zig

TARGET = kernel8
ASM_SOURCES = a.S
ZIG_SOURCES = main.zig
LD_SCRIPT = linker.ld

OBJECTS = $(ASM_SOURCES:.S=.o) $(ZIG_SOURCES:.zig=.o)

.PHONY: all clean run debug flash

all: $(TARGET).img

%.o: %.S
	$(CC) -g -c $< -o $@

%.o: %.zig
	$(ZIG) build-obj -target aarch64-freestanding-eabihf -mcpu=cortex_a53 $<

$(TARGET).elf: $(OBJECTS)
	$(LD) -T $(LD_SCRIPT) -o $@ $^

$(TARGET).img: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

run: $(TARGET).img
	$(QEMU) -M $(MODEL) -kernel $(TARGET).img -display none -serial null -serial stdio

debug: $(TARGET).img
	$(QEMU) -M $(MODEL) -kernel $(TARGET).img -display none -serial null -serial stdio -S -s & echo $$! > qemu.pid
	$(GDB) -ex "file $(TARGET).elf" -ex "target remote :1234"

flash:
	echo "Replace /dev/sdX with your SD card device!"
	sudo dd if=$(TARGET).img of=/dev/sdX bs=4M status=progress conv=fsync

clean:
	rm -f $(OBJECTS) $(TARGET).elf $(TARGET).img qemu.pid main.o.o

