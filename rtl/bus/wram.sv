// wram.sv
// Work RAM: the CPU's scratch space. 8 KB, so 13 address bits.
// Written in the style Vivado recognizes as "block RAM" (the FPGA's
// built-in memory). The read is registered, so data appears one clock
// after the address (matches the bus timing rule in gb_pkg.sv).

module wram (
  input  logic        clk,
  input  logic        we,
  input  logic [12:0] addr,
  input  logic [7:0]  wdata,
  output logic [7:0]  rdata
);

  (* ram_style = "block" *) logic [7:0] mem [0:8191];

  always_ff @(posedge clk) begin
    if (we) mem[addr] <= wdata;
    rdata <= mem[addr];
  end

endmodule