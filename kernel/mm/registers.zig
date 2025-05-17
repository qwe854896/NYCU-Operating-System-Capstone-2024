// Translation Control Register (TCR_EL1) Configuration
// ---------------------------------------------------
/// Configure 48-bit virtual address space (64-48=16 for both TTBR0/TTBR1)
/// TCR_EL1.T0SZ = 16 (bits 0-5), TCR_EL1.T1SZ = 16 (bits 16-21)
const tcr_config_region_48bit = (((64 - 48) << 0) | ((64 - 48) << 16));

/// Set 4KB granule size for both TTBR0/TTBR1:
/// - TG0 = 0b00 (4KB, bits 14-15)
/// - TG1 = 0b10 (4KB, bits 30-31)
const tcr_config_4kb = ((0b00 << 14) | (0b10 << 30));

/// Combined TCR configuration for 48-bit VA with 4KB pages
const tcr_config_default = (tcr_config_region_48bit | tcr_config_4kb);

/// Initialize Translation Control Register (TCR_EL1)
/// Naked function: No prologue/epilogue to prevent stack corruption
pub fn tcrInit() callconv(.Naked) void {
    asm volatile (
        \\ mov x1, %[arg0]  // Load prepared TCR configuration
        \\ msr tcr_el1, x1  // Write to TCR_EL1 register
        \\ ret
        :
        : [arg0] "r" (tcr_config_default),
        : "x1"
    );
}

// Memory Attribute Indirection Register (MAIR_EL1) Configuration
// --------------------------------------------------------------
/// Device-nGnRnE memory attribute (strongly ordered, no caching)
const mair_device_ngnrne = 0b00000000;

/// Normal Non-Cacheable memory attribute
const mair_normal_nocache = 0b01000100;

/// MAIR index assignments
const mair_idx_device_ngnrne = 0; // Index 0: Device-nGnRnE memory type
const mair_idx_normal_nocache = 1; // Index 1: Normal Non-Cacheable

/// Pack memory attributes into MAIR_EL1 register format:
/// - Attribute[0] at bits 0-7
/// - Attribute[1] at bits 8-15
const mair_config_default = (mair_device_ngnrne << (mair_idx_device_ngnrne << 3)) |
    (mair_normal_nocache << (mair_idx_normal_nocache << 3));

/// Initialize Memory Attribute Indirection Register (MAIR_EL1)
pub fn mairInit() callconv(.Naked) void {
    asm volatile (
        \\ mov x1, %[arg0]  // Load MAIR configuration
        \\ msr mair_el1, x1 // Write to MAIR_EL1 register
        \\ ret
        :
        : [arg0] "r" (mair_config_default),
        : "x1"
    );
}

// Page Table Configuration
// ------------------------
/// Page table entry types
const pd_table = 0b11; // Level 0/1/2 descriptor (points to next table)
const pd_block = 0b01; // Level 1/2 block entry (directly maps memory)

/// Access flag (bit 10) - indicates entry has been accessed
const pd_access = (1 << 10);

/// Special constants for table entries
const pgd_entry_0 = 0x0000000000002003; // PGD[0] value
const pud_entry_0 = 0x0000000000003003; // PUD[0] value
const pud_entry_1 = 0x0060000040000401; // PUD[1] value
const pmd_base1 = 0x0040000000000405; // PMD base pattern 1
const pmd_base2 = 0x006000003c000401; // PMD base pattern 2

pub fn enableMMU() callconv(.Naked) void {
    asm volatile (
    // Initialize page table bases
        \\ mov x1, 0x1000       // PGD at 0x1000
        \\ mov x2, 0x2000       // PUD at 0x2000
        \\ mov x5, 0x3000       // PMD at 0x3000

        // Set up PGD[0]
        \\ mov x3, %[pgd_entry_0]
        \\ str x3, [x1]

        // Set up PUD entries
        \\ mov x3, %[pud_entry_0]
        \\ str x3, [x2]         // PUD[0]
        \\ mov x3, %[pud_entry_1]
        \\ str x3, [x2, #8]     // PUD[1]

        // Initialize PMD entries (0-479)
        \\ mov x6, #0            // i = 0
        \\ mov x7, %[pmd_base1]  // Load base pattern
        \\ mov x8, #480          // Loop limit
        \\ 1:
        \\ lsl x9, x6, #21       // i * 0x200000
        \\ add x10, x7, x9       // Create entry value
        \\ str x10, [x5, x6, lsl #3]  // Store at PMD[i]
        \\ add x6, x6, #1        // i++
        \\ cmp x6, x8
        \\ b.lt 1b

        // Initialize PMD entries (480-511)
        \\ mov x6, #0            // Reset counter
        \\ mov x7, %[pmd_base2]  // Load second base pattern
        \\ mov x8, #32           // 32 entries
        \\ 2:
        \\ lsl x9, x6, #21       // i * 0x200000
        \\ add x10, x7, x9       // Create entry value
        \\ add x11, x5, #3840    // 480*8 = 3840
        \\ str x10, [x11, x6, lsl #3]  // Store at PMD[480+i]
        \\ add x6, x6, #1        // i++
        \\ cmp x6, x8
        \\ b.lt 2b

        // Activate translation tables
        \\ msr ttbr0_el1, x1     // Set TTBR0 to PGD
        \\ msr ttbr1_el1, x1     // Set TTBR1 to PGD

        // Enable MMU
        \\ mrs x3, sctlr_el1
        \\ orr x3, x3, #1        // Set MMU enable bit
        \\ msr sctlr_el1, x3
        \\ ret
        :
        : [pgd_entry_0] "r" (pgd_entry_0),
          [pud_entry_0] "r" (pud_entry_0),
          [pud_entry_1] "r" (pud_entry_1),
          [pmd_base1] "r" (pmd_base1),
          [pmd_base2] "r" (pmd_base2),
        : "x1", "x2", "x3", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "memory"
    );
}
