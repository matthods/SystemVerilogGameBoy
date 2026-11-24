// alu.sv
//
// Purely combinational: outputs change as soon as the inputs change.
// The CPU decides when to latch `result` into a register and `flags_out` into F.
//
// Flag bus layout (matches the upper nibble of the F register):
//   flags[3] = Z  zero          result was 0
//   flags[2] = N  subtract      last op was a subtraction
//   flags[1] = H  half-carry    carry out of bit 3 (or borrow into bit 4)
//   flags[0] = C  carry         carry out of bit 7 (or borrow)
//
// 16-bit ops (ADD HL,rr / ADD SP,e8 / INC rr / DEC rr) are not handled here.
// The CPU can do them as two 8-bit passes (ADD on the low byte, ADC on the high
// byte), or with a small dedicated 16-bit adder.

import gb_pkg::*;

module alu (
    input  alu_op_t     op,         // Specifies operation to perform
    input  logic [7:0]  a,          // The first operand (usually register A)
    input  logic [7:0]  b,          // The second operand (register, immediate, or (HL))
    input  logic [2:0]  bit_sel,    // Bit number for BIT / RES / SET (from opcode bits 5:3)
    input  logic [3:0]  flags_in,   // Current flags {Z, N, H, C}

    output logic [7:0]  result,     // Operation result
    output logic [3:0]  flags_out   // New flags {Z, N, H, C}
);

    logic [8:0] sum;    // 9-bit scratch result; bit 8 is the carry/borrow out
    logic [7:0] adjust; // DAA correction value (0x00, 0x06, 0x60 or 0x66)
    logic       daa_c;  // DAA carry out

    always_comb begin
        // Defaults: avoid latches, keep flags unchanged unless an op sets them.
        result    = a;
        flags_out = flags_in;
        sum       = 9'b0;
        adjust    = 8'b0;
        daa_c     = 1'b0;

        unique case (op)
            ALU_ADD, ALU_ADC: begin
                sum     = {1'b0, a} + {1'b0, b} + ((op == ALU_ADC) ? flags_in[FLAG_C] : 1'b0);
                result  = sum[7:0];

                flags_out[FLAG_Z] = (result == 8'b0) ? 1 : 0;
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = ((a[3:0] + b[3:0] + ((op == ALU_ADC) ? flags_in[FLAG_C] : 1'b0)) > 5'd15);
                flags_out[FLAG_C] = sum[8];
            end

            ALU_SUB, ALU_SBC: begin
                // SBC also subtracts the carry flag (acts as a borrow-in)
                sum     = {1'b0, a} - {1'b0, b} - ((op == ALU_SBC) ? flags_in[FLAG_C] : 1'b0);
                result  = sum[7:0];

                flags_out[FLAG_Z] = (result == 8'b0) ? 1 : 0;
                flags_out[FLAG_N] = 1'b1;
                flags_out[FLAG_H] = ({1'b0, a[3:0]} < ({1'b0, b[3:0]} + ((op == ALU_SBC) ? flags_in[FLAG_C] : 1'b0)));
                flags_out[FLAG_C] = sum[8];
            end

            ALU_AND: begin
                result      = a & b;
                flags_out   = {(result == 8'b0), 1'b0, 1'b1, 1'b0};
            end

            ALU_XOR: begin
                result      = a ^ b;
                flags_out   = {(result == 8'b0), 1'b0, 1'b0, 1'b0};
            end

            ALU_OR: begin
                result      = a | b;
                flags_out   = {(result == 8'b0), 1'b0, 1'b0, 1'b0};
            end

            ALU_CP: begin
                flags_out[FLAG_Z] = (a == b);
                flags_out[FLAG_N] = 1'b1;
                flags_out[FLAG_H] = (a[3:0] < b[3:0]);
                flags_out[FLAG_C] = (a < b);
            end

            ALU_INC: begin
                result = a + 1'b1;

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = (a[3:0] == 4'hF);   // carry out of bit 3
            end

            ALU_DEC: begin
                result = a - 1'b1;

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b1;
                flags_out[FLAG_H] = (a[3:0] == 4'h0);   // borrow from bit 4
            end

            ALU_DAA: begin
                // Adjust A back to valid BCD after an add or subtract, using N, H and C from the last op
                adjust = 8'h00;
                daa_c  = flags_in[FLAG_C];

                if (!flags_in[FLAG_N]) begin
                    // After an addition
                    if (flags_in[FLAG_H] || (a[3:0] > 4'd9)) adjust = adjust | 8'h06;
                    if (flags_in[FLAG_C] || (a > 8'h99)) begin
                        adjust = adjust | 8'h60;
                        daa_c  = 1'b1;
                    end
                    result = a + adjust;
                end else begin
                    // After a subtraction (C is never newly set here)
                    if (flags_in[FLAG_H]) adjust = adjust | 8'h06;
                    if (flags_in[FLAG_C]) adjust = adjust | 8'h60;
                    result = a - adjust;
                end

                flags_out[FLAG_Z] = (result == 8'b0) ? 1 : 0;
                flags_out[FLAG_N] = flags_in[FLAG_N];
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = daa_c;
            end
            
            ALU_CPL: begin
                // Flip every bit of A
                result = ~a;

                flags_out[FLAG_N] = 1'b1;
                flags_out[FLAG_H] = 1'b1;
            end

            ALU_SCF: begin
                // Set the carry flag
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = 1'b1;
            end

            ALU_CCF: begin
                // Invert the carry flag
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = ~flags_in[FLAG_C];
            end

            ALU_RLC: begin
                // Rotate left; old bit 7 goes to both bit 0 and carry
                result = {a[6:0], a[7]};

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = a[7];
            end

            ALU_RRC: begin
                // Rotate right; old bit 0 goes to both bit 7 and carry
                result = {a[0], a[7:1]};

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = a[0];
            end

            ALU_RL: begin
                // Rotate left through carry; old carry goes into bit 0, old bit 7 into carry
                result = {a[6:0], flags_in[FLAG_C]};

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = a[7];
            end

            ALU_RR: begin
                // Rotate right through carry; old carry goes into bit 7, old bit 0 into carry
                result = {flags_in[FLAG_C], a[7:1]};

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = a[0];
            end

            ALU_SLA: begin
                // Shift left; bit 0 becomes 0, old bit 7 goes to carry
                result = {a[6:0], 1'b0};

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = a[7];
            end

            ALU_SRA: begin
                // Arithmetic shift right; bit 7 is kept (sign), old bit 0 goes to carry
                result = {a[7], a[7:1]};

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = a[0];
            end

            ALU_SWAP: begin
                // Swap the upper and lower nibbles
                result = {a[3:0], a[7:4]};

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = 1'b0;
            end

            ALU_SRL: begin
                // Logical shift right; bit 7 becomes 0, old bit 0 goes to carry
                result = {1'b0, a[7:1]};

                flags_out[FLAG_Z] = (result == 8'b0);
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b0;
                flags_out[FLAG_C] = a[0];
            end

            ALU_BIT: begin
                // Test bit bit_sel of a; result is unchanged, C is unchanged
                flags_out[FLAG_Z] = ~a[bit_sel];
                flags_out[FLAG_N] = 1'b0;
                flags_out[FLAG_H] = 1'b1;
            end

            ALU_RES: begin
                // Clear bit bit_sel of a; no flags change
                result = a & ~(8'b1 << bit_sel);
            end

            ALU_SET: begin
                // Set bit bit_sel of a; no flags change
                result = a | (8'b1 << bit_sel);
            end

            ALU_PASS: begin
                // Pass b through unchanged; no flags change
                result = b;
            end

            default: ;
        endcase
    end

endmodule

