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

/// Boot Page Global Directory (PGD) attribute:
/// - Table descriptor type (points to PUD)
const boot_pgd_attr = pd_table;

/// Boot Page Upper Directory (PUD) attribute:
/// - Block descriptor type
/// - Access flag enabled
/// - Memory type index 0 (Device-nGnRnE)
const boot_pud_attr = pd_access | (mair_idx_device_ngnrne << 2) | pd_block;

/// Initialize MMU and set up initial identity mapping
/// Creates 2x1GB mappings for physical memory:
/// 1. 0x00000000-0x3FFFFFFF (first 1GB)
/// 2. 0x40000000-0x7FFFFFFF (second 1GB)
pub fn enableMMU() callconv(.Naked) void {
    asm volatile (
    // Initialize page table bases
        \\ mov x1, 0       // PGD at physical address 0x0
        \\ mov x2, 0x1000  // PUD at physical address 0x1000

        // Link PGD[0] -> PUD (0x1000 | attributes)
        \\ mov x3, %[pgd_attr]
        \\ orr x3, x2, x3  // Combine PUD address with table attributes
        \\ str x3, [x1]    // Store entry in PGD[0]

        // Create PUD entries (1GB block mappings)
        \\ mov x3, %[pud_attr]  // Load PUD entry template
        // First 1GB mapping (0x00000000)
        \\ mov x4, 0x00000000
        \\ orr x4, x3, x4  // Combine base address with attributes
        \\ str x4, [x2]    // Store in PUD[0]
        // Second 1GB mapping (0x40000000)
        \\ mov x4, 0x40000000
        \\ orr x4, x3, x4  // Combine base address with attributes
        \\ str x4, [x2, 8] // Store in PUD[1] (offset 8 bytes)

        // Activate translation tables
        \\ msr ttbr0_el1, x1  // Set TTBR0 to PGD base
        \\ msr ttbr1_el1, x1  // Also load PGD to the upper translation based register.

        // Enable MMU (SCTLR_EL1.M = 1)
        \\ mrs x3, sctlr_el1
        \\ orr x3, x3, 1      // Set bit 0 (MMU enable)
        \\ msr sctlr_el1, x3
        \\ ret
        :
        : [pgd_attr] "r" (boot_pgd_attr),
          [pud_attr] "r" (boot_pud_attr),
        : "x1", "x2", "x3", "x4", "memory"
    );
}
