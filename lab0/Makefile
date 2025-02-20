ARCH = aarch64
MODEL = raspi3b
GDB = pwndbg

CROSS_COMPILE ?= $(ARCH)-linux-gnu-
CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
QEMU = qemu-system-$(ARCH)

TARGET = kernel8
ASM_SOURCES = a.S
LD_SCRIPT = linker.ld

OBJECTS = $(ASM_SOURCES:.S=.o)

.PHONY: all clean run debug flash

all: $(TARGET).img

%.o: %.S
	$(CC) -c $< -o $@

$(TARGET).elf: $(OBJECTS)
	$(LD) -T $(LD_SCRIPT) -o $@ $^

$(TARGET).img: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

run: $(TARGET).img
	$(QEMU) -M $(MODEL) -kernel $(TARGET).img -display none -d in_asm

debug: $(TARGET).img
	$(QEMU) -M $(MODEL) -kernel $(TARGET).img -display none -S -s & echo $$! > qemu.pid
	$(GDB) -ex "file $(TARGET).elf" -ex "target remote :1234"

flash:
	echo "Replace /dev/sdX with your SD card device!"
	sudo dd if=$(TARGET).img of=/dev/sdX bs=4M status=progress conv=fsync

clean:
	rm -f $(OBJECTS) $(TARGET).elf $(TARGET).img qemu.pid

