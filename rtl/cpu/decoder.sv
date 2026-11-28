// decoder.sv
// Game Boy (SM83) instruction decoder
//
// Purely combinational: turns one opcode byte into control signals. It does not
// sequence anything. cpu.sv fetches the bytes and runs the bus cycles.
//
// Opcode fields used below (x = opcode[7:6], y = opcode[5:3], z = opcode[2:0]):
//   y       destination register, ALU operation, bit number, or RST target / 8
//   z       source register
//   y[2:1]  register pair   (opcode[5:4])
//   y[1:0]  branch condition (opcode[4:3])

import gb_pkg::*;

module decoder (
    input  logic [7:0] opcode,
    input  logic       cb_prefix,    // opcode is the byte that followed 0xCB

    output instr_t     instr,        // instruction group
    output alu_op_t    alu_op,       // ALU operation, if the instruction uses the ALU
    output logic [2:0] dst_r8,       // destination register code (R8_*)
    output logic [2:0] src_r8,       // source register code (R8_*)
    output rp_t        rp,           // register pair
    output logic       hl_inc,       // (HL+): increment HL after the access
    output logic       hl_dec,       // (HL-): decrement HL after the access
    output logic       conditional,  // JP / JR / CALL / RET only happens if cond is true
    output cond_t      cond,         // which condition to test
    output logic [2:0] bit_sel,      // bit number for BIT / RES / SET
    output logic       clear_z,      // force Z = 0 (RLCA, RRCA, RLA, RRA)
    output logic [7:0] rst_vec       // target address for RST (high byte is 0x00)
);

    logic [1:0] x;
    logic [2:0] y, z;

    assign x = opcode[7:6];
    assign y = opcode[5:3];
    assign z = opcode[2:0];

    always_comb begin
        // Defaults: the plain field positions. Each case only overrides what differs.
        instr       = I_ILLEGAL;
        alu_op      = ALU_PASS;
        dst_r8      = y;
        src_r8      = z;
        rp          = rp_t'({1'b0, opcode[5:4]});
        hl_inc      = 1'b0;
        hl_dec      = 1'b0;
        conditional = 1'b0;
        cond        = cond_t'(opcode[4:3]);
        bit_sel     = y;
        clear_z     = 1'b0;
        rst_vec     = {2'b00, y, 3'b000};

        if (cb_prefix) begin
            // ======================== CB-prefixed ========================
            instr  = I_CB;
            dst_r8 = z;                                     // operand and destination match
            case (x)
                2'b00:   alu_op = alu_op_t'(ALU_RLC + y);   // RLC RRC RL RR SLA SRA SWAP SRL
                2'b01:   alu_op = ALU_BIT;
                2'b10:   alu_op = ALU_RES;
                default: alu_op = ALU_SET;
            endcase
        end else begin
            case (x)
                // ======================== 0x00 - 0x3F ========================
                2'b00: begin
                    case (z)
                        3'd0: begin
                            case (y)
                                3'd0: instr = I_NOP;            // 00
                                3'd1: begin                     // 08  LD (nn),SP
                                    instr = I_LD_NN_SP;
                                    rp    = RP_SP;
                                end
                                3'd2: instr = I_STOP;           // 10
                                3'd3: instr = I_JR;             // 18  JR e
                                default: begin                  // 20 28 30 38  JR cc,e
                                    instr       = I_JR;
                                    conditional = 1'b1;
                                end
                            endcase
                        end

                        3'd1: instr = opcode[3] ? I_ADD_HL_RR : I_LD_RR_NN;

                        3'd2: begin                             // A <-> (BC) (DE) (HL+) (HL-)
                            if (opcode[3]) begin
                                instr  = I_LD_A_IND;
                                dst_r8 = R8_A;
                            end else begin
                                instr  = I_LD_IND_A;
                                src_r8 = R8_A;
                            end
                            if (opcode[5]) begin                // pair codes 2 and 3 use HL
                                rp     = RP_HL;
                                hl_inc = ~opcode[4];
                                hl_dec =  opcode[4];
                            end
                        end

                        3'd3: instr = opcode[3] ? I_DEC_RR : I_INC_RR;

                        3'd4, 3'd5: begin                       // INC r / DEC r
                            instr  = I_INCDEC_R;
                            alu_op = z[0] ? ALU_DEC : ALU_INC;
                            src_r8 = y;
                        end

                        3'd6: instr = I_LD_R_N;                 // LD r,n

                        default: begin                          // z = 7: A / flag operations
                            src_r8 = R8_A;
                            dst_r8 = R8_A;
                            if (!y[2]) begin                    // RLCA RRCA RLA RRA
                                instr   = I_ROT_A;
                                alu_op  = alu_op_t'(ALU_RLC + y);
                                clear_z = 1'b1;
                            end else begin                      // DAA CPL SCF CCF
                                instr  = I_ACC;
                                alu_op = alu_op_t'(ALU_DAA + y[1:0]);
                            end
                        end
                    endcase
                end

                // ======================== 0x40 - 0x7F ========================
                2'b01: begin
                    // 0x76 would be LD (HL),(HL); it is HALT instead
                    instr = (opcode == 8'h76) ? I_HALT : I_LD_R_R;
                end

                // ======================== 0x80 - 0xBF ========================
                2'b10: begin
                    instr  = I_ALU_R;
                    alu_op = alu_op_t'({2'b00, y});             // ADD ADC SUB SBC AND XOR OR CP
                    dst_r8 = R8_A;
                end

                // ======================== 0xC0 - 0xFF ========================
                default: begin
                    case (z)
                        3'd0: begin
                            case (y)
                                3'd4: begin                     // E0  LDH (n),A
                                    instr  = I_LDH_N_A;
                                    src_r8 = R8_A;
                                end
                                3'd5: begin                     // E8  ADD SP,e
                                    instr = I_ADD_SP_E;
                                    rp    = RP_SP;
                                end
                                3'd6: begin                     // F0  LDH A,(n)
                                    instr  = I_LDH_A_N;
                                    dst_r8 = R8_A;
                                end
                                3'd7: begin                     // F8  LD HL,SP+e
                                    instr = I_LD_HL_SP_E;
                                    rp    = RP_SP;
                                end
                                default: begin                  // C0 C8 D0 D8  RET cc
                                    instr       = I_RET;
                                    conditional = 1'b1;
                                end
                            endcase
                        end

                        3'd1: begin
                            if (!opcode[3]) begin               // C1 D1 E1 F1  POP rr
                                instr = I_POP;
                                if (opcode[5:4] == 2'b11) rp = RP_AF;
                            end else begin
                                case (opcode[5:4])
                                    2'd0: instr = I_RET;        // C9
                                    2'd1: instr = I_RETI;       // D9
                                    2'd2: begin                 // E9  JP HL
                                        instr = I_JP_HL;
                                        rp    = RP_HL;
                                    end
                                    default: begin              // F9  LD SP,HL
                                        instr = I_LD_SP_HL;
                                        rp    = RP_HL;
                                    end
                                endcase
                            end
                        end

                        3'd2: begin
                            case (y)
                                3'd4: begin                     // E2  LDH (C),A
                                    instr  = I_LDH_C_A;
                                    src_r8 = R8_A;
                                end
                                3'd5: begin                     // EA  LD (nn),A
                                    instr  = I_LD_NN_A;
                                    src_r8 = R8_A;
                                end
                                3'd6: begin                     // F2  LDH A,(C)
                                    instr  = I_LDH_A_C;
                                    dst_r8 = R8_A;
                                end
                                3'd7: begin                     // FA  LD A,(nn)
                                    instr  = I_LD_A_NN;
                                    dst_r8 = R8_A;
                                end
                                default: begin                  // C2 CA D2 DA  JP cc,nn
                                    instr       = I_JP_NN;
                                    conditional = 1'b1;
                                end
                            endcase
                        end

                        3'd3: begin
                            case (y)
                                3'd0:    instr = I_JP_NN;       // C3
                                3'd1:    instr = I_PREFIX_CB;   // CB
                                3'd6:    instr = I_DI;          // F3
                                3'd7:    instr = I_EI;          // FB
                                default: instr = I_ILLEGAL;     // D3 DB E3 EB
                            endcase
                        end

                        3'd4: begin
                            if (!y[2]) begin                    // C4 CC D4 DC  CALL cc,nn
                                instr       = I_CALL;
                                conditional = 1'b1;
                            end                                 // E4 EC F4 FC are illegal
                        end

                        3'd5: begin
                            if (!opcode[3]) begin               // C5 D5 E5 F5  PUSH rr
                                instr = I_PUSH;
                                if (opcode[5:4] == 2'b11) rp = RP_AF;
                            end else if (opcode[5:4] == 2'b00) begin
                                instr = I_CALL;                 // CD
                            end                                 // DD ED FD are illegal
                        end

                        3'd6: begin                             // ALU A,n
                            instr  = I_ALU_N;
                            alu_op = alu_op_t'({2'b00, y});
                            dst_r8 = R8_A;
                        end

                        default: instr = I_RST;                 // z = 7
                    endcase
                end
            endcase
        end
    end

endmodule
