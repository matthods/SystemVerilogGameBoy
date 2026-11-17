// hram.sv
// High RAM: 127 bytes at 0xFF80 - 0xFFFE. Same pattern as wram.sv,
// just smaller (7 address bits).

module hram (
  input  logic       clk,
  input  logic       we,
  input  logic [6:0] addr,
  input  logic [7:0] wdata,
  output logic [7:0] rdata
);

  logic [7:0] mem [0:127];

  always_ff @(posedge clk) begin
    if (we) mem[addr] <= wdata;
    rdata <= mem[addr];
  end

endmodule