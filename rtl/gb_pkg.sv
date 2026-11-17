// gb_pkg.sv
// Shared definitions for the whole project.
//
// THE BUS (every module that touches memory uses these signals):
//   addr  [15:0]  which location the CPU wants (0x0000 - 0xFFFF)
//   wdata [7:0]   data the CPU is writing
//   rdata [7:0]   data returned to the CPU
//   rd, wr        the CPU is reading / writing this cycle
//
// TIMING RULE (agree on this on day 1):
//   Reads take ONE clock cycle. The CPU puts the address on the bus in
//   cycle N and gets valid rdata in cycle N+1. This matches how the
//   FPGA's block RAM works.

package gb_pkg;

  // Which device an address belongs to (the Game Boy memory map)
  typedef enum logic [3:0] {
    REG_ROM,      // 0x0000 - 0x7FFF  cartridge ROM
    REG_VRAM,     // 0x8000 - 0x9FFF  video RAM
    REG_CRAM,     // 0xA000 - 0xBFFF  cartridge RAM (unused for Tetris)
    REG_WRAM,     // 0xC000 - 0xFDFF  work RAM (includes the "echo" copy)
    REG_OAM,      // 0xFE00 - 0xFE9F  sprite list
    REG_UNUSED,   // 0xFEA0 - 0xFEFF  not usable
    REG_IO,       // 0xFF00 - 0xFF7F  I/O registers
    REG_HRAM,     // 0xFF80 - 0xFFFE  high RAM
    REG_IE        // 0xFFFF           interrupt enable register
  } region_t;

  function automatic region_t decode_region(input logic [15:0] a);
    if      (a < 16'h8000) return REG_ROM;
    else if (a < 16'hA000) return REG_VRAM;
    else if (a < 16'hC000) return REG_CRAM;
    else if (a < 16'hFE00) return REG_WRAM;   // echo RAM E000-FDFF shares the same low 13 address bits
    else if (a < 16'hFEA0) return REG_OAM;
    else if (a < 16'hFF00) return REG_UNUSED;
    else if (a < 16'hFF80) return REG_IO;
    else if (a < 16'hFFFF) return REG_HRAM;
    else                   return REG_IE;
  endfunction

endpackage