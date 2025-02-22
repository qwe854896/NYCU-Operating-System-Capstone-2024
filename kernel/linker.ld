SECTIONS
{
    .text.boot 0x100000 : {
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

