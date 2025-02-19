.section ".text"
.global _start

_start:
    // Set up stack pointer
    ldr x0, =_stack_top
    mov sp, x0

    // Zero out .bss section
    ldr x1, =_bss_start
    ldr x2, =_bss_end
    mov x3, #0

1:  
    cmp x1, x2
    b.ge 2f
    str x3, [x1], #8
    b 1b

2:
    // Loop indefinitely (replace with actual kernel entry point)
    bl main

main:
  b .
  ret

