SECTIONS
{
    .text.boot 0x80000 : {
        KEEP(*(.text.boot))
    }

    .text : {
        *(.text)
        *(.text.*)
    }

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    }

    .eh_frame_hdr : { *(.eh_frame_hdr) }
    .eh_frame : { *(.eh_frame) }

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

