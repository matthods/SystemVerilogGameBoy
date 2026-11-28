// tb_regfile.sv
// Self-checking testbench for rtl/cpu/regfile.sv.
//
// Run from sim/ so the generated files land there (scripts/clean_sim.bat removes them):
//   xvlog -sv ../rtl/gb_pkg.sv ../rtl/cpu/regfile.sv tb_regfile.sv
//   xelab tb_regfile -s tb_regfile_sim
//   xsim tb_regfile_sim -runall

`timescale 1ns/1ps

module tb_regfile;
    import gb_pkg::*;

    logic        clk = 1'b0;
    logic        rst;
    logic [2:0]  rsel8, wsel8;
    logic [7:0]  rdata8, wdata8, a_out;
    logic        we8, we16, flags_we, pc_we;
    rp_t         rsel16, wsel16;
    logic [15:0] rdata16, wdata16, pc_in, pc_out, hl_out, sp_out;
    logic [3:0]  flags_in, flags_out;

    regfile dut (.*);

    always #5 clk = ~clk;           // 100 MHz, like the Nexys A7

    int tests  = 0;
    int errors = 0;

    task automatic expect_val(input string name, input logic [15:0] got, input logic [15:0] exp);
        tests++;
        if (got !== exp) begin
            errors++;
            $display("FAIL %-24s got=%04h exp=%04h", name, got, exp);
        end
    endtask

    task automatic check8(input string name, input logic [2:0] sel, input logic [7:0] exp);
        rsel8 = sel;
        #1;
        expect_val(name, {8'h00, rdata8}, {8'h00, exp});
    endtask

    task automatic check16(input string name, input rp_t sel, input logic [15:0] exp);
        rsel16 = sel;
        #1;
        expect_val(name, rdata16, exp);
    endtask

    // Turn every write enable off
    task automatic idle();
        we8 = 0;  we16 = 0;  flags_we = 0;  pc_we = 0;
    endtask

    // Let one rising edge capture the inputs, then drop the write enables.
    // Inputs are changed just after the falling edge, away from the rising edge.
    task automatic tick();
        @(posedge clk);
        @(negedge clk);
        idle();
    endtask

    task automatic write8(input logic [2:0] sel, input logic [7:0] val);
        we8 = 1;  wsel8 = sel;  wdata8 = val;
        tick();
    endtask

    task automatic write16(input rp_t sel, input logic [15:0] val);
        we16 = 1;  wsel16 = sel;  wdata16 = val;
        tick();
    endtask

    task automatic check_reset_values();
        check16("reset AF", RP_AF, 16'h01B0);
        check16("reset BC", RP_BC, 16'h0013);
        check16("reset DE", RP_DE, 16'h00D8);
        check16("reset HL", RP_HL, 16'h014D);
        check16("reset SP", RP_SP, 16'hFFFE);
        expect_val("reset PC",    pc_out, 16'h0100);
        expect_val("reset flags", {12'h000, flags_out}, 16'h000B);
    endtask

    initial begin
        static logic [2:0] regs [7] = '{R8_B, R8_C, R8_D, R8_E, R8_H, R8_L, R8_A};

        $display("tb_regfile: starting");
        idle();
        rsel8 = R8_B;  wsel8 = R8_B;  wdata8 = 0;
        rsel16 = RP_BC;  wsel16 = RP_BC;  wdata16 = 0;
        flags_in = 0;  pc_in = 0;

        // ---------------- Reset ----------------
        rst = 1;
        @(negedge clk);
        tick();
        rst = 0;
        check_reset_values();

        // ---------------- 8-bit writes ----------------
        // Write all registers first, then read all, to catch writes hitting two registers
        foreach (regs[i]) write8(regs[i], 8'h10 + i);
        foreach (regs[i]) check8($sformatf("r8 code %0d", regs[i]), regs[i], 8'h10 + i);

        // Pairs are built high byte first
        check16("pair BC", RP_BC, 16'h1011);
        check16("pair DE", RP_DE, 16'h1213);
        check16("pair HL", RP_HL, 16'h1415);
        expect_val("a_out",  {8'h00, a_out}, 16'h0016);
        expect_val("hl_out", hl_out, 16'h1415);

        // (HL) is not a register: reads 0xFF and writes change nothing
        write8(R8_HL_MEM, 8'h99);
        check8("(HL) read", R8_HL_MEM, 8'hFF);
        foreach (regs[i]) check8($sformatf("after (HL) write %0d", regs[i]), regs[i], 8'h10 + i);

        // ---------------- 16-bit writes ----------------
        write16(RP_BC, 16'hABCD);
        write16(RP_DE, 16'h1234);
        write16(RP_HL, 16'hC0DE);
        write16(RP_SP, 16'hDFF0);
        check16("write BC", RP_BC, 16'hABCD);
        check16("write DE", RP_DE, 16'h1234);
        check16("write HL", RP_HL, 16'hC0DE);
        check16("write SP", RP_SP, 16'hDFF0);
        expect_val("sp_out", sp_out, 16'hDFF0);
        check8("B after BC write", R8_B, 8'hAB);
        check8("C after BC write", R8_C, 8'hCD);

        // POP AF: the low nibble of F is dropped
        write16(RP_AF, 16'h5AFF);
        check16("AF masking", RP_AF, 16'h5AF0);
        expect_val("flags after AF", {12'h000, flags_out}, 16'h000F);
        check8("A after AF write", R8_A, 8'h5A);

        // ---------------- Flags and PC ----------------
        flags_we = 1;  flags_in = 4'b0101;
        tick();
        expect_val("flags write", {12'h000, flags_out}, 16'h0005);
        check16("AF after flags", RP_AF, 16'h5A50);

        pc_we = 1;  pc_in = 16'h0150;
        tick();
        expect_val("pc write", pc_out, 16'h0150);

        // ---------------- Write enables off ----------------
        wsel8 = R8_B;    wdata8  = 8'h00;
        wsel16 = RP_HL;  wdata16 = 16'h0000;
        flags_in = 4'b1010;  pc_in = 16'hFFFF;
        tick();
        check16("hold BC", RP_BC, 16'hABCD);
        check16("hold HL", RP_HL, 16'hC0DE);
        check16("hold AF", RP_AF, 16'h5A50);
        expect_val("hold PC", pc_out, 16'h0150);

        // Nothing changes before the clock edge
        we8 = 1;  wsel8 = R8_B;  wdata8 = 8'h77;
        check8("before edge", R8_B, 8'hAB);
        tick();
        check8("after edge", R8_B, 8'h77);

        // ---------------- Same-cycle writes ----------------
        // ALU result and flags in one cycle (the normal case)
        we8 = 1;  wsel8 = R8_A;  wdata8 = 8'h42;
        flags_we = 1;  flags_in = 4'b1000;
        tick();
        check16("A + flags", RP_AF, 16'h4280);

        // we8 beats we16 on the same byte; the other byte still takes the 16-bit value
        we16 = 1;  wsel16 = RP_BC;  wdata16 = 16'h1122;
        we8  = 1;  wsel8  = R8_B;   wdata8  = 8'h99;
        tick();
        check16("we8 over we16", RP_BC, 16'h9922);

        // flags_we beats a POP AF style write
        we16 = 1;  wsel16 = RP_AF;  wdata16 = 16'h33F0;
        flags_we = 1;  flags_in = 4'b0010;
        tick();
        check16("flags_we over we16", RP_AF, 16'h3320);

        // ---------------- Reset wins over writes ----------------
        rst = 1;
        we16 = 1;  wsel16 = RP_BC;  wdata16 = 16'hFFFF;
        pc_we = 1;  pc_in = 16'hFFFF;
        tick();
        rst = 0;
        check_reset_values();

        $display("tb_regfile: %0d tests, %0d errors", tests, errors);
        if (errors == 0) $display("tb_regfile: PASSED");
        else             $display("tb_regfile: FAILED");
        $finish;
    end

endmodule
