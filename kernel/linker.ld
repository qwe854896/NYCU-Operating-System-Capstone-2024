SECTIONS
{
    . = 0x80000;
    _flash_img_start = .;

    .text.boot : {
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

    .got : {
        *(.got)
        *(.got.*)
    }

    .data : {
        *(.data)
        *(.data.*)
    }

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        _bss_end = .;
    }

    . = ALIGN(16);
    _stack_top = . + 0x8000; /* Reserve 32KB for stack */

    _flash_img_end = _stack_top;
}

