SECTIONS
{
    .text.bootloader 0x40000 : {
        *(.text.bootloader)
    }

    .text.boot : {
        _text_boot_start = .;
        *(.text.boot)
    }

    .text : {
        *(.text)
    }

    .rodata : {
        *(.rodata)
    }

    .data : {
        *(.data)
    }

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss)
        *(COMMON)
        _bss_end = .;
    }

    . = ALIGN(16);
    _stack_top = . + 0x8000; /* Reserve 32KB for stack */
}

