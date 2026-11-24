// tb_alu.sv
// Self-checking testbench for rtl/cpu/alu.sv.
//
// Part 1: hand-picked vectors for every operation, including the flag edge cases.
// Part 2: exhaustive check of ADD/ADC/SUB/SBC/CP against an independent reference model.
//
// Flag literals are written as 4'bZNHC.
//
// Compile order (gb_pkg.sv must come first):
//   xvlog -sv rtl/gb_pkg.sv rtl/cpu/alu.sv sim/tb_alu.sv
//   xelab tb_alu -s tb_alu_sim
//   xsim tb_alu_sim -runall

`timescale 1ns/1ps

module tb_alu;
    import gb_pkg::*;

    alu_op_t     op;
    logic [7:0]  a, b;
    logic [2:0]  bit_sel;
    logic [3:0]  flags_in;
    logic [7:0]  result;
    logic [3:0]  flags_out;

    alu dut (
        .op       (op),
        .a        (a),
        .b        (b),
        .bit_sel  (bit_sel),
        .flags_in (flags_in),
        .result   (result),
        .flags_out(flags_out)
    );

    int tests  = 0;
    int errors = 0;

    // Apply one set of inputs, wait for the combinational logic, and compare.
    task automatic check(
        input string      name,
        input alu_op_t    t_op,
        input logic [7:0] t_a,
        input logic [7:0] t_b,
        input logic [3:0] t_fin,
        input logic [2:0] t_bit,
        input logic [7:0] exp_result,
        input logic [3:0] exp_flags
    );
        op       = t_op;
        a        = t_a;
        b        = t_b;
        flags_in = t_fin;
        bit_sel  = t_bit;
        #1;
        tests++;
        if (result !== exp_result || flags_out !== exp_flags) begin
            errors++;
            $display("FAIL %-12s a=%02h b=%02h fin=%04b bit=%0d | got result=%02h flags=%04b | exp result=%02h flags=%04b",
                     name, t_a, t_b, t_fin, t_bit, result, flags_out, exp_result, exp_flags);
        end
    endtask

    // Shorthand for ops that do not use bit_sel
    task automatic chk(
        input string      name,
        input alu_op_t    t_op,
        input logic [7:0] t_a,
        input logic [7:0] t_b,
        input logic [3:0] t_fin,
        input logic [7:0] exp_result,
        input logic [3:0] exp_flags
    );
        check(name, t_op, t_a, t_b, t_fin, 3'd0, exp_result, exp_flags);
    endtask

    // Reference model for the exhaustive test (plain integer math, no shared code with the DUT)
    task automatic ref_addsub(
        input  alu_op_t    t_op,
        input  int         ra, rb, rc,
        output logic [7:0] exp_result,
        output logic [3:0] exp_flags
    );
        int full, lo;
        logic z, n, h, c;
        case (t_op)
            ALU_ADD, ALU_ADC: begin
                full = ra + rb + rc;
                lo   = (ra & 15) + (rb & 15) + rc;
                n = 0;  h = (lo > 15);  c = (full > 255);
            end
            default: begin   // SUB, SBC, CP
                full = ra - rb - rc;
                lo   = (ra & 15) - (rb & 15) - rc;
                n = 1;  h = (lo < 0);   c = (full < 0);
            end
        endcase
        exp_result = full[7:0];
        z          = (exp_result == 8'h00);
        exp_flags  = {z, n, h, c};
        if (t_op == ALU_CP) exp_result = ra[7:0];   // CP does not change the result
    endtask

    initial begin
        logic [7:0] er;
        logic [3:0] ef;
        static alu_op_t ops [5] ='{ALU_ADD, ALU_ADC, ALU_SUB, ALU_SBC, ALU_CP};

        $display("tb_alu: starting");

        // ---------------- ADD / ADC ----------------
        chk("ADD",   ALU_ADD, 8'h3A, 8'hC6, 4'b0000, 8'h00, 4'b1011);  // wraps to 0, H and C set
        chk("ADD",   ALU_ADD, 8'h0F, 8'h01, 4'b0000, 8'h10, 4'b0010);  // half carry only
        chk("ADD",   ALU_ADD, 8'h80, 8'h80, 4'b0000, 8'h00, 4'b1001);  // carry only
        chk("ADD",   ALU_ADD, 8'h01, 8'h02, 4'b1111, 8'h03, 4'b0000);  // old carry must be ignored
        chk("ADC",   ALU_ADC, 8'hE1, 8'h0F, 4'b0001, 8'hF1, 4'b0010);
        chk("ADC",   ALU_ADC, 8'hFF, 8'h00, 4'b0001, 8'h00, 4'b1011);

        // ---------------- SUB / SBC ----------------
        chk("SUB",   ALU_SUB, 8'h3E, 8'h3E, 4'b0000, 8'h00, 4'b1100);  // zero
        chk("SUB",   ALU_SUB, 8'h3E, 8'h0F, 4'b0000, 8'h2F, 4'b0110);  // half borrow
        chk("SUB",   ALU_SUB, 8'h3E, 8'h40, 4'b0000, 8'hFE, 4'b0101);  // full borrow
        chk("SUB",   ALU_SUB, 8'h05, 8'h03, 4'b0001, 8'h02, 4'b0100);  // old carry must be ignored
        chk("SBC",   ALU_SBC, 8'h3B, 8'h2A, 4'b0001, 8'h10, 4'b0100);
        chk("SBC",   ALU_SBC, 8'h00, 8'h00, 4'b0001, 8'hFF, 4'b0111);
        chk("SBC",   ALU_SBC, 8'h10, 8'h0F, 4'b0001, 8'h00, 4'b1110);

        // ---------------- AND / XOR / OR ----------------
        chk("AND",   ALU_AND, 8'hF0, 8'h0F, 4'b1111, 8'h00, 4'b1010);  // H always set, C cleared
        chk("AND",   ALU_AND, 8'h5A, 8'hFF, 4'b0000, 8'h5A, 4'b0010);
        chk("XOR",   ALU_XOR, 8'hFF, 8'hFF, 4'b1111, 8'h00, 4'b1000);
        chk("XOR",   ALU_XOR, 8'hF0, 8'h0F, 4'b0000, 8'hFF, 4'b0000);
        chk("OR",    ALU_OR,  8'h00, 8'h00, 4'b1111, 8'h00, 4'b1000);
        chk("OR",    ALU_OR,  8'h0F, 8'hF0, 4'b0000, 8'hFF, 4'b0000);

        // ---------------- CP (result is not changed) ----------------
        chk("CP",    ALU_CP,  8'h3C, 8'h2F, 4'b0000, 8'h3C, 4'b0110);
        chk("CP",    ALU_CP,  8'h3C, 8'h3C, 4'b0000, 8'h3C, 4'b1100);
        chk("CP",    ALU_CP,  8'h3C, 8'h40, 4'b0000, 8'h3C, 4'b0101);

        // ---------------- INC / DEC (C is unchanged) ----------------
        chk("INC",   ALU_INC, 8'hFF, 8'h00, 4'b0001, 8'h00, 4'b1011);
        chk("INC",   ALU_INC, 8'h0F, 8'h00, 4'b0000, 8'h10, 4'b0010);
        chk("INC",   ALU_INC, 8'h1F, 8'h00, 4'b0000, 8'h20, 4'b0010);  // half carry on a non-0x0F value
        chk("INC",   ALU_INC, 8'h10, 8'h00, 4'b0000, 8'h11, 4'b0000);
        chk("DEC",   ALU_DEC, 8'h01, 8'h00, 4'b0000, 8'h00, 4'b1100);
        chk("DEC",   ALU_DEC, 8'h00, 8'h00, 4'b0001, 8'hFF, 4'b0111);
        chk("DEC",   ALU_DEC, 8'h10, 8'h00, 4'b0000, 8'h0F, 4'b0110);
        chk("DEC",   ALU_DEC, 8'h11, 8'h00, 4'b0000, 8'h10, 4'b0100);  // no half borrow

        // ---------------- DAA ----------------
        chk("DAA add",   ALU_DAA, 8'h7D, 8'h00, 4'b0000, 8'h83, 4'b0000);  // 45 + 38
        chk("DAA add",   ALU_DAA, 8'h9A, 8'h00, 4'b0000, 8'h00, 4'b1001);  // 99 + 01 -> 00 with carry
        chk("DAA add",   ALU_DAA, 8'h05, 8'h00, 4'b0001, 8'h65, 4'b0001);  // carry already set
        chk("DAA sub",   ALU_DAA, 8'h3D, 8'h00, 4'b0110, 8'h37, 4'b0100);  // 45 - 08

        // ---------------- CPL / SCF / CCF ----------------
        chk("CPL",   ALU_CPL, 8'h35, 8'h00, 4'b1001, 8'hCA, 4'b1111);
        chk("SCF",   ALU_SCF, 8'h77, 8'h00, 4'b1110, 8'h77, 4'b1001);
        chk("CCF",   ALU_CCF, 8'h77, 8'h00, 4'b0001, 8'h77, 4'b0000);
        chk("CCF",   ALU_CCF, 8'h77, 8'h00, 4'b1000, 8'h77, 4'b1001);
        chk("CCF",   ALU_CCF, 8'h77, 8'h00, 4'b0110, 8'h77, 4'b0001);

        // ---------------- Rotates ----------------
        chk("RLC",   ALU_RLC, 8'h85, 8'h00, 4'b0000, 8'h0B, 4'b0001);
        chk("RLC",   ALU_RLC, 8'h00, 8'h00, 4'b0001, 8'h00, 4'b1000);
        chk("RRC",   ALU_RRC, 8'h01, 8'h00, 4'b0000, 8'h80, 4'b0001);
        chk("RRC",   ALU_RRC, 8'h00, 8'h00, 4'b0001, 8'h00, 4'b1000);
        chk("RL",    ALU_RL,  8'h80, 8'h00, 4'b0000, 8'h00, 4'b1001);
        chk("RL",    ALU_RL,  8'h11, 8'h00, 4'b0001, 8'h23, 4'b0000);
        chk("RR",    ALU_RR,  8'h01, 8'h00, 4'b0000, 8'h00, 4'b1001);
        chk("RR",    ALU_RR,  8'h8A, 8'h00, 4'b0001, 8'hC5, 4'b0000);

        // ---------------- Shifts / SWAP ----------------
        chk("SLA",   ALU_SLA, 8'h80, 8'h00, 4'b0000, 8'h00, 4'b1001);
        chk("SLA",   ALU_SLA, 8'hFF, 8'h00, 4'b0000, 8'hFE, 4'b0001);
        chk("SRA",   ALU_SRA, 8'h8A, 8'h00, 4'b0000, 8'hC5, 4'b0000);  // sign bit kept
        chk("SRA",   ALU_SRA, 8'h01, 8'h00, 4'b0000, 8'h00, 4'b1001);
        chk("SRL",   ALU_SRL, 8'h01, 8'h00, 4'b0000, 8'h00, 4'b1001);
        chk("SRL",   ALU_SRL, 8'hFF, 8'h00, 4'b0000, 8'h7F, 4'b0001);  // bit 7 becomes 0
        chk("SWAP",  ALU_SWAP, 8'hF0, 8'h00, 4'b1111, 8'h0F, 4'b0000);
        chk("SWAP",  ALU_SWAP, 8'h00, 8'h00, 4'b0001, 8'h00, 4'b1000);

        // ---------------- BIT / RES / SET / PASS ----------------
        check("BIT set",   ALU_BIT, 8'h80, 8'h00, 4'b0001, 3'd7, 8'h80, 4'b0011);  // Z=0, C kept
        check("BIT clear", ALU_BIT, 8'h80, 8'h00, 4'b0000, 3'd0, 8'h80, 4'b1010);  // Z=1
        check("RES",       ALU_RES, 8'hFF, 8'h00, 4'b1111, 3'd3, 8'hF7, 4'b1111);  // flags untouched
        check("SET",       ALU_SET, 8'h00, 8'h00, 4'b0101, 3'd5, 8'h20, 4'b0101);  // flags untouched
        chk("PASS",  ALU_PASS, 8'h11, 8'h42, 4'b1010, 8'h42, 4'b1010);

        // ---------------- Exhaustive ADD/ADC/SUB/SBC/CP ----------------
        $display("tb_alu: exhaustive add/sub check (%0d cases)", 5 * 256 * 256 * 2);
        foreach (ops[i]) begin
            for (int ia = 0; ia < 256; ia++) begin
                for (int ib = 0; ib < 256; ib++) begin
                    for (int ic = 0; ic < 2; ic++) begin
                        // Only ADC/SBC use the carry flag. For ADD/SUB/CP the flag is still
                        // driven (ic) to prove it is ignored, but the model uses carry 0.
                        ref_addsub(ops[i], ia, ib,
                                   (ops[i] == ALU_ADC || ops[i] == ALU_SBC) ? ic : 0,
                                   er, ef);
                        check(ops[i].name(), ops[i], ia[7:0], ib[7:0], {3'b000, ic[0]}, 3'd0, er, ef);
                    end
                end
            end
        end

        $display("tb_alu: %0d tests, %0d errors", tests, errors);
        if (errors == 0) $display("tb_alu: PASSED");
        else             $display("tb_alu: FAILED");
        $finish;
    end

endmodule
