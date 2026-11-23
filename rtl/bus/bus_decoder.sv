// bus_decoder.sv
// Decodes the CPU address into:
//   - one-hot slave selects (which device is being addressed)
//   - write enables (select AND write)
//   - an offset address inside the selected device
// and sends the selected device's read data back to the CPU.
//
// GAME BOY MEMORY MAP (what each range is):
//   0000-3FFF  ROM bank 0           16 KB  fixed part of the game
//   4000-7FFF  ROM bank 1..N        16 KB  switchable part of the game
//   8000-9FFF  VRAM                  8 KB  tile pictures and tile maps
//   A000-BFFF  External RAM          8 KB  RAM on the cartridge
//   C000-CFFF  Work RAM bank 0       4 KB  CPU scratch space
//   D000-DFFF  Work RAM bank 1..N    4 KB  more scratch space
//   E000-FDFF  Echo RAM                    mirror of C000-DDFF
//   FE00-FE9F  OAM                 160 B   sprite list
//   FEA0-FEFF  Not usable
//   FF00-FF7F  I/O registers               joypad, timer, serial, PPU...
//   FF80-FFFE  HRAM                127 B   small fast RAM
//   FFFF       IE                    1 B   interrupt enable register
//
// Every range has its own named parameter so the map is documented in
// code. Ranges that are the same physical memory on the original Game
// Boy (ROM banks, WRAM banks, echo RAM) share one slave device.

module bus_decoder #(
    parameter int ADDR_WIDTH = 16,
    parameter int DATA_WIDTH = 8,
    parameter int NUM_SLAVES = 9,

    // Cartridge ROM, bank 0 (fixed)
    parameter bit [ADDR_WIDTH-1:0] START_ROM          = 16'h0000,
    parameter bit [ADDR_WIDTH-1:0] END_ROM            = 16'h3FFF,

    // Cartridge ROM, switchable bank (same ROM until you add an MBC)
    parameter bit [ADDR_WIDTH-1:0] START_ROM_BANK     = 16'h4000,
    parameter bit [ADDR_WIDTH-1:0] END_ROM_BANK       = 16'h7FFF,

    // Video RAM: tile data and tile maps
    parameter bit [ADDR_WIDTH-1:0] START_VRAM         = 16'h8000,
    parameter bit [ADDR_WIDTH-1:0] END_VRAM           = 16'h9FFF,

    // RAM on the cartridge
    parameter bit [ADDR_WIDTH-1:0] START_EXTERNAL_RAM = 16'hA000,
    parameter bit [ADDR_WIDTH-1:0] END_EXTERNAL_RAM   = 16'hBFFF,

    // Work RAM, first 4 KB
    parameter bit [ADDR_WIDTH-1:0] START_WRAM         = 16'hC000,
    parameter bit [ADDR_WIDTH-1:0] END_WRAM           = 16'hCFFF,

    // Work RAM, second 4 KB (switchable only on Game Boy Color)
    parameter bit [ADDR_WIDTH-1:0] START_WRAM_CGB     = 16'hD000,
    parameter bit [ADDR_WIDTH-1:0] END_WRAM_CGB       = 16'hDFFF,

    // Echo RAM: mirror of work RAM
    parameter bit [ADDR_WIDTH-1:0] START_ECHO_RAM     = 16'hE000,
    parameter bit [ADDR_WIDTH-1:0] END_ECHO_RAM       = 16'hFDFF,

    // Object Attribute Memory: the sprite list
    parameter bit [ADDR_WIDTH-1:0] START_OAM          = 16'hFE00,
    parameter bit [ADDR_WIDTH-1:0] END_OAM            = 16'hFE9F,

    // Prohibited area
    parameter bit [ADDR_WIDTH-1:0] START_NOT_USABLE   = 16'hFEA0,
    parameter bit [ADDR_WIDTH-1:0] END_NOT_USABLE     = 16'hFEFF,

    // I/O registers
    parameter bit [ADDR_WIDTH-1:0] START_IO           = 16'hFF00,
    parameter bit [ADDR_WIDTH-1:0] END_IO             = 16'hFF7F,

    // High RAM
    parameter bit [ADDR_WIDTH-1:0] START_HRAM         = 16'hFF80,
    parameter bit [ADDR_WIDTH-1:0] END_HRAM           = 16'hFFFE,

    // Interrupt enable register (a single address)
    parameter bit [ADDR_WIDTH-1:0] START_IE           = 16'hFFFF,
    parameter bit [ADDR_WIDTH-1:0] END_IE             = 16'hFFFF
)(
    input  logic                                   clk,

    // ---- CPU side ----
    input  logic [ADDR_WIDTH-1:0]                  master_addr,
    input  logic                                   master_valid,   // using bus this cycle
    input  logic                                   master_wr,      // 1 = write, 0 = read
    output logic [DATA_WIDTH-1:0]                  master_rdata,

    // ---- Device side ----
    output logic [NUM_SLAVES-1:0]                  slave_sel,          // one-hot: which device
    output logic [NUM_SLAVES-1:0]                  slave_we,           // write enable per device
    output logic [ADDR_WIDTH-1:0]                  slave_offset_addr,  // address inside the device
    input  logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]  slave_rdata,        // read data from each device

    // Error flag: CPU addressed a location that no range claims
    output logic                                   decode_error
);

    // Index of each physical device in the slave vectors.
    // Several address ranges can map to the same device.
    localparam int SLAVE_ROM          = 0;   // ROM bank 0 + switchable bank
    localparam int SLAVE_VRAM         = 1;
    localparam int SLAVE_EXTERNAL_RAM = 2;
    localparam int SLAVE_WRAM         = 3;   // WRAM + WRAM bank 1 + echo RAM
    localparam int SLAVE_OAM          = 4;
    localparam int SLAVE_NOT_USABLE   = 5;
    localparam int SLAVE_IO           = 6;
    localparam int SLAVE_HRAM         = 7;
    localparam int SLAVE_IE           = 8;

    // True when address a is between s and e (inclusive)
    function automatic logic in_range(
        input logic [ADDR_WIDTH-1:0] a,
        input logic [ADDR_WIDTH-1:0] s,
        input logic [ADDR_WIDTH-1:0] e
    );
        return (a >= s) && (a <= e);
    endfunction

    // ---------------------------------------------------------------
    // Address decode (purely combinational)
    // ---------------------------------------------------------------
    always_comb begin
        // Defaults avoid latches
        slave_sel         = '0;
        slave_offset_addr = '0;
        decode_error      = 1'b0;

        if (master_valid) begin
            if (in_range(master_addr, START_ROM, END_ROM)) begin
                slave_sel[SLAVE_ROM] = 1'b1;
                slave_offset_addr    = master_addr - START_ROM;
            end
            else if (in_range(master_addr, START_ROM_BANK, END_ROM_BANK)) begin
                // Same ROM device; offset continues from bank 0
                slave_sel[SLAVE_ROM] = 1'b1;
                slave_offset_addr    = master_addr - START_ROM;
            end
            else if (in_range(master_addr, START_VRAM, END_VRAM)) begin
                slave_sel[SLAVE_VRAM] = 1'b1;
                slave_offset_addr     = master_addr - START_VRAM;
            end
            else if (in_range(master_addr, START_EXTERNAL_RAM, END_EXTERNAL_RAM)) begin
                slave_sel[SLAVE_EXTERNAL_RAM] = 1'b1;
                slave_offset_addr             = master_addr - START_EXTERNAL_RAM;
            end
            else if (in_range(master_addr, START_WRAM, END_WRAM)) begin
                slave_sel[SLAVE_WRAM] = 1'b1;
                slave_offset_addr     = master_addr - START_WRAM;
            end
            else if (in_range(master_addr, START_WRAM_CGB, END_WRAM_CGB)) begin
                // Same WRAM device; offset continues from the first 4 KB
                slave_sel[SLAVE_WRAM] = 1'b1;
                slave_offset_addr     = master_addr - START_WRAM;
            end
            else if (in_range(master_addr, START_ECHO_RAM, END_ECHO_RAM)) begin
                // Echo RAM: same physical memory as WRAM
                slave_sel[SLAVE_WRAM] = 1'b1;
                slave_offset_addr     = master_addr - START_ECHO_RAM;
            end
            else if (in_range(master_addr, START_OAM, END_OAM)) begin
                slave_sel[SLAVE_OAM] = 1'b1;
                slave_offset_addr    = master_addr - START_OAM;
            end
            else if (in_range(master_addr, START_NOT_USABLE, END_NOT_USABLE)) begin
                slave_sel[SLAVE_NOT_USABLE] = 1'b1;
                slave_offset_addr           = master_addr - START_NOT_USABLE;
            end
            else if (in_range(master_addr, START_IO, END_IO)) begin
                slave_sel[SLAVE_IO] = 1'b1;
                slave_offset_addr   = master_addr - START_IO;
            end
            else if (in_range(master_addr, START_HRAM, END_HRAM)) begin
                slave_sel[SLAVE_HRAM] = 1'b1;
                slave_offset_addr     = master_addr - START_HRAM;
            end
            else if (in_range(master_addr, START_IE, END_IE)) begin
                slave_sel[SLAVE_IE] = 1'b1;
                slave_offset_addr   = master_addr - START_IE;
            end
            else begin
                decode_error = 1'b1;   // unmapped address
            end
        end
    end

    // A device only sees a write enable if it is selected AND the CPU is writing
    assign slave_we = master_wr ? slave_sel : '0;

    // ---------------------------------------------------------------
    // Read data return path
    // Block RAM returns data ONE CLOCK after the address, so remember
    // which device was selected and use that on the next cycle.
    // ---------------------------------------------------------------
    logic [NUM_SLAVES-1:0] slave_sel_q;

    always_ff @(posedge clk) slave_sel_q <= slave_sel;

    always_comb begin
        master_rdata = {DATA_WIDTH{1'b1}};   // nothing selected: reads return 0xFF
        for (int i = 0; i < NUM_SLAVES; i++) begin
            if (slave_sel_q[i]) master_rdata = slave_rdata[i];
        end
    end

endmodule
