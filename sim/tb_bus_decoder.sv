// tb_bus_decoder.sv
// Self-checking testbench for rtl/bus/bus_decoder.sv.
// Prints "PASS" at the end if every check succeeded, otherwise prints
// the first few failures and "FAIL".
//
// What it tests:
//   1. Every one of the 65,536 addresses: exactly one device selected,
//      the right device, the right offset, correct write enable, no error
//   2. Echo RAM mirrors work RAM; ROM bank and WRAM bank 1 offsets
//   3. master_valid = 0 selects nothing
//   4. Read data return path (data arrives ONE clock after the address)
//   5. decode_error, using a second decoder with a deliberate gap in
//      its map (the real map has no gaps, so the error never fires there)

module tb_bus_decoder;

  localparam int NUM_SLAVES = 9;

  // Must match the device indices in bus_decoder.sv
  localparam int SLAVE_ROM          = 0;
  localparam int SLAVE_VRAM         = 1;
  localparam int SLAVE_EXTERNAL_RAM = 2;
  localparam int SLAVE_WRAM         = 3;
  localparam int SLAVE_OAM          = 4;
  localparam int SLAVE_NOT_USABLE   = 5;
  localparam int SLAVE_IO           = 6;
  localparam int SLAVE_HRAM         = 7;
  localparam int SLAVE_IE           = 8;

  // ---------------------------------------------------------------
  // Clock and signals
  // ---------------------------------------------------------------
  logic clk = 1'b0;
  always #5 clk = ~clk;          // 100 MHz

  logic [15:0] addr;
  logic        valid;
  logic        wr;

  // Main decoder outputs
  logic [7:0]            rdata;
  logic [NUM_SLAVES-1:0] sel, we;
  logic [15:0]           offset;
  logic                  err;

  // Decoder-with-a-gap outputs
  logic [7:0]            rdata_g;
  logic [NUM_SLAVES-1:0] sel_g, we_g;
  logic [15:0]           offset_g;
  logic                  err_g;

  // Fake devices: each one always returns a unique byte (A0, A1, ...),
  // so we can tell which device answered.
  logic [NUM_SLAVES-1:0][7:0] slave_rdata;

  function automatic logic [7:0] dev_id(input int idx);
    return 8'hA0 + idx[7:0];
  endfunction

  initial begin
    for (int i = 0; i < NUM_SLAVES; i++) slave_rdata[i] = dev_id(i);
  end

  // ---------------------------------------------------------------
  // Devices under test
  // ---------------------------------------------------------------
  bus_decoder dut (
    .clk              (clk),
    .master_addr      (addr),
    .master_valid     (valid),
    .master_wr        (wr),
    .master_rdata     (rdata),
    .slave_sel        (sel),
    .slave_we         (we),
    .slave_offset_addr(offset),
    .slave_rdata      (slave_rdata),
    .decode_error     (err)
  );

  // Same decoder, but the switchable ROM bank starts at 5000 instead of
  // 4000, leaving 4000-4FFF unmapped so decode_error has something to catch.
  bus_decoder #(.START_ROM_BANK(16'h5000)) dut_gap (
    .clk              (clk),
    .master_addr      (addr),
    .master_valid     (valid),
    .master_wr        (wr),
    .master_rdata     (rdata_g),
    .slave_sel        (sel_g),
    .slave_we         (we_g),
    .slave_offset_addr(offset_g),
    .slave_rdata      (slave_rdata),
    .decode_error     (err_g)
  );

  // ---------------------------------------------------------------
  // Reference model: written separately from the design, using plain
  // numbers, so a mistake in the decoder shows up as a mismatch.
  // ---------------------------------------------------------------
  function automatic int exp_slave(input logic [15:0] a);
    if      (a <= 16'h7FFF) return SLAVE_ROM;
    else if (a <= 16'h9FFF) return SLAVE_VRAM;
    else if (a <= 16'hBFFF) return SLAVE_EXTERNAL_RAM;
    else if (a <= 16'hFDFF) return SLAVE_WRAM;          // work RAM + echo
    else if (a <= 16'hFE9F) return SLAVE_OAM;
    else if (a <= 16'hFEFF) return SLAVE_NOT_USABLE;
    else if (a <= 16'hFF7F) return SLAVE_IO;
    else if (a <= 16'hFFFE) return SLAVE_HRAM;
    else                    return SLAVE_IE;
  endfunction

  function automatic logic [15:0] exp_offset(input logic [15:0] a);
    if      (a <= 16'h7FFF) return a;                   // ROM: banks run on from 0
    else if (a <= 16'h9FFF) return a - 16'h8000;
    else if (a <= 16'hBFFF) return a - 16'hA000;
    else if (a <= 16'hDFFF) return a - 16'hC000;        // work RAM
    else if (a <= 16'hFDFF) return a - 16'hE000;        // echo RAM
    else if (a <= 16'hFE9F) return a - 16'hFE00;
    else if (a <= 16'hFEFF) return a - 16'hFEA0;
    else if (a <= 16'hFF7F) return a - 16'hFF00;
    else if (a <= 16'hFFFE) return a - 16'hFF80;
    else                    return 16'h0000;
  endfunction

  // ---------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------
  int errors = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors <= 10) $display("  FAIL @ %0t ns: %s", $time, msg);
  endtask

  function automatic logic [NUM_SLAVES-1:0] one_hot(input int idx);
    logic [NUM_SLAVES-1:0] r;
    r      = '0;
    r[idx] = 1'b1;
    return r;
  endfunction

  logic [NUM_SLAVES-1:0] sel_ref;
  logic [15:0]           off_ref;

  // ---------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------
  initial begin
    addr  = 16'h0000;
    valid = 1'b0;
    wr    = 1'b0;
    repeat (2) @(posedge clk);

    // ---- Test 1: sweep every address ----
    $display("TEST 1: sweep all 65536 addresses");
    valid = 1'b1;
    for (int i = 0; i < 65536; i++) begin
      addr = i[15:0];
      wr   = i[0];                 // alternate reads and writes
      #1;
      if (sel !== one_hot(exp_slave(addr)))
        fail($sformatf("addr %04h: sel=%b, expected device %0d", addr, sel, exp_slave(addr)));
      if (offset !== exp_offset(addr))
        fail($sformatf("addr %04h: offset=%04h, expected %04h", addr, offset, exp_offset(addr)));
      if (we !== (wr ? sel : '0))
        fail($sformatf("addr %04h: write enable wrong (wr=%b, we=%b)", addr, wr, we));
      if (err !== 1'b0)
        fail($sformatf("addr %04h: unexpected decode_error", addr));
    end

    // ---- Test 2: specific cases worth seeing by name ----
    $display("TEST 2: echo RAM, WRAM bank 1, ROM bank");
    wr = 1'b0;

    addr = 16'hC123; #1;                       // work RAM
    sel_ref = sel; off_ref = offset;
    addr = 16'hE123; #1;                       // same spot through echo RAM
    if (sel !== sel_ref || offset !== off_ref)
      fail("echo RAM E123 does not match work RAM C123");

    addr = 16'hD000; #1;                       // start of WRAM bank 1
    if (sel !== one_hot(SLAVE_WRAM) || offset !== 16'h1000)
      fail("D000 should be work RAM, offset 1000");

    addr = 16'h4000; #1;                       // start of switchable ROM bank
    if (sel !== one_hot(SLAVE_ROM) || offset !== 16'h4000)
      fail("4000 should be ROM, offset 4000");

    addr = 16'hFFFF; #1;                       // interrupt enable register
    if (sel !== one_hot(SLAVE_IE) || offset !== 16'h0000)
      fail("FFFF should be the IE register, offset 0");

    // ---- Test 3: master_valid = 0 selects nothing ----
    $display("TEST 3: master_valid low");
    valid = 1'b0;
    wr    = 1'b1;
    addr  = 16'h8000; #1;
    if (sel !== '0 || we !== '0 || err !== 1'b0)
      fail("nothing should be selected when master_valid = 0");

    // ---- Test 4: read data return path (one clock of latency) ----
    $display("TEST 4: read data return path");
    valid = 1'b1;
    wr    = 1'b0;

    addr = 16'h0100;                           // read from ROM
    @(posedge clk); #1;
    if (rdata !== dev_id(SLAVE_ROM))
      fail("read from ROM did not return ROM data one clock later");

    addr = 16'h8000; #1;                       // new address, clock edge not here yet
    if (rdata !== dev_id(SLAVE_ROM))
      fail("read data should still come from the PREVIOUS device before the clock edge");

    @(posedge clk); #1;                        // one clock after the new address
    if (rdata !== dev_id(SLAVE_VRAM))
      fail("read from VRAM did not return VRAM data one clock later");

    valid = 1'b0;                              // bus idle
    @(posedge clk); #1;
    if (rdata !== 8'hFF)
      fail("with nothing selected, reads should return FF");

    // ---- Test 5: decode_error, using the decoder with a gap ----
    $display("TEST 5: decode_error");
    valid = 1'b1;
    wr    = 1'b0;

    addr = 16'h4000; #1;                       // inside the gap (4000-4FFF)
    if (err_g !== 1'b1 || sel_g !== '0)
      fail("4000 should be unmapped in the gap decoder");
    if (err !== 1'b0)
      fail("main decoder should not flag 4000");

    addr = 16'h4FFF; #1;                       // last unmapped address
    if (err_g !== 1'b1)
      fail("4FFF should be unmapped in the gap decoder");

    addr = 16'h5000; #1;                       // first mapped address after the gap
    if (err_g !== 1'b0 || sel_g !== one_hot(SLAVE_ROM))
      fail("5000 should map to ROM in the gap decoder");

    addr = 16'h3FFF; #1;                       // just before the gap
    if (err_g !== 1'b0 || sel_g !== one_hot(SLAVE_ROM))
      fail("3FFF should map to ROM in the gap decoder");

    // ---- Summary ----
    if (errors == 0) $display("PASS: all tests passed");
    else             $display("FAIL: %0d errors", errors);
    $finish;
  end

  // Safety net: stop if something hangs
  initial begin
    #2_000_000;
    $display("TIMEOUT");
    $finish;
  end

endmodule