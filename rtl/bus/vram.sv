// vram.sv
// Video RAM: 8 KB holding tile pictures and tile maps.
// DUAL PORT: two independent ports onto the same memory.
//   Port A: the CPU (read and write), connected through the bus decoder.
//   Port B: the PPU (read only), so the graphics unit can fetch tiles
//           at the same time the CPU is running.

module vram (
  input  logic        clk,

  // Port A: CPU
  input  logic        we_a,
  input  logic [12:0] addr_a,
  input  logic [7:0]  wdata_a,
  output logic [7:0]  rdata_a,

  // Port B: PPU (read only)
  input  logic [12:0] addr_b,
  output logic [7:0]  rdata_b
);

  (* ram_style = "block" *) logic [7:0] mem [0:8191];

  always_ff @(posedge clk) begin
    if (we_a) mem[addr_a] <= wdata_a;
    rdata_a <= mem[addr_a];
    rdata_b <= mem[addr_b];
  end

endmodule