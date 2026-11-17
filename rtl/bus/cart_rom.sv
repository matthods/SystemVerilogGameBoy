// cart_rom.sv
// The game cartridge: 32 KB of read-only memory (no bank switching, which
// is enough for Tetris). The contents are loaded from a text file when
// Vivado builds the design.
//
// INIT_FILE is a text file with one hex byte per line, for example:
//   00
//   C3
//   50
// scripts/rom2mem.py produces it from a .gb file. The file must be added
// to the Vivado project as a memory initialization file.

module cart_rom #(
  parameter string INIT_FILE = "rom.mem"
)(
  input  logic        clk,
  input  logic [14:0] addr,
  output logic [7:0]  rdata
);

  (* rom_style = "block" *) logic [7:0] mem [0:32767];

  initial $readmemh(INIT_FILE, mem);

  always_ff @(posedge clk) rdata <= mem[addr];

endmodule