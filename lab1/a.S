.section ".text"
.global _start

_start:
    /* Configure GPIO Pins for Mini UART */
    // Set GPIO 14 & 15 to ALT5 (Mini UART mode)
    ldr x0, =0x3F200000 // GPIO base address from Section 6.1
    ldr w1, [x0, #4] // GPFSEL1, 32-bit R/W register
    bic w1, w1, #(63 << 12) // bitwise AND NOT (masking) of both FSEL14 and FSEL15
    orr w1, w1, #(2 << 12) // bitwise OR b'010 takes alternate function 5
    orr w1, w1, #(2 << 15)
    str w1, [x0, #4]

    // Disable pull-up/down for GPIO 14 & 15
    ldr w1, =0
    str w1, [x0, #0x94] // GPPUD, 32-bit R/W register
    // No need to use GPPUDCLKn, no need more setup and waiting

    /* Enable Mini UART */
    ldr x0, =0x3F215000 // Mini UART base address from Section 2.1

    // Enable Mini UART
    mov w1, #1
    str w1, [x0, #4] // AUX_ENABLES, 3-bit

    // Disable TX and RX while configuring
    str wzr, [x0, #0x60] // AUX_MU_CNTL_REG, 8-bit

    // Disable interrupts
    str wzr, [x0, #0x44] // AUX_MU_IER_REG, 8-bit

    // Set data size to 8-bit
    mov w1, #3
    str w1, [x0, #0x4C] // AUX_MU_LCR_REG, 8-bit

    // Disable flow control
    str wzr, [x0, #0x50] // AUX_MU_MCR_REG, 8-bit

    mov w1, #270
    str w1, [x0, #0x68] // AUX_MU_BAUD_REG, 16-bit

    mov w1, #6
    str w1, [x0, #0x48] // AUX_MU_IIR_REG, 8-bit

    // Enable TX and RX
    mov w1, #3
    str w1, [x0, #0x60] // AUX_MU_CNTL_REG, 8-bit

    /* Intialize Memory  */
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
    bl main

/* UART FUNCTION */
// Use w2 register for covention now

uart_send:
    ldr x0, =0x3F215000
.wait1:
    ldr w1, [x0, #0x54] // AUX_MU_LSR_REG, 8-bit
    and w1, w1, #0x20 // Transmitter Empty
    cbz w1, .wait1
    str w2, [x0, #0x40] // AUX_MU_IO_REG, 8-bit
    ret

uart_recv:
    ldr x0, =0x3F215000
.wait2:
    ldr w1, [x0, #0x54] // AUX_MU_LSR_REG
    and w1, w1, #0x01 // Data Ready
    cbz w1, .wait2
    ldr w2, [x0, #0x40] // AUX_MU_IO_REG
    ret

/* MAIN FUNCTION BELOW */

main:
  bl uart_recv
  bl uart_send
  b main
  ret

