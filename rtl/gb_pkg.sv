// gb_pkg.sv
// Shared definitions for the whole project.
//
// THE BUS (every module that touches memory uses these signals):
//   addr  [15:0]  which location the CPU wants (0x0000 - 0xFFFF)
//   wdata [7:0]   data the CPU is writing
//   rdata [7:0]   data returned to the CPU
//   rd, wr        the CPU is reading / writing this cycle
//
// TIMING RULE (agree on this on day 1):
//   Reads take ONE clock cycle. The CPU puts the address on the bus in
//   cycle N and gets valid rdata in cycle N+1. This matches how the
//   FPGA's block RAM works.

package gb_pkg;

  // Which device an address belongs to (the Game Boy memory map)
  typedef enum logic [3:0] {
    REG_ROM,      // 0x0000 - 0x7FFF  cartridge ROM
    REG_VRAM,     // 0x8000 - 0x9FFF  video RAM
    REG_CRAM,     // 0xA000 - 0xBFFF  cartridge RAM (unused for Tetris)
    REG_WRAM,     // 0xC000 - 0xFDFF  work RAM (includes the "echo" copy)
    REG_OAM,      // 0xFE00 - 0xFE9F  sprite list
    REG_UNUSED,   // 0xFEA0 - 0xFEFF  not usable
    REG_IO,       // 0xFF00 - 0xFF7F  I/O registers
    REG_HRAM,     // 0xFF80 - 0xFFFE  high RAM
    REG_IE        // 0xFFFF           interrupt enable register
  } region_t;

  function automatic region_t decode_region(input logic [15:0] a);
    if      (a < 16'h8000) return REG_ROM;
    else if (a < 16'hA000) return REG_VRAM;
    else if (a < 16'hC000) return REG_CRAM;
    else if (a < 16'hFE00) return REG_WRAM;   // echo RAM E000-FDFF shares the same low 13 address bits
    else if (a < 16'hFEA0) return REG_OAM;
    else if (a < 16'hFF00) return REG_UNUSED;
    else if (a < 16'hFF80) return REG_IO;
    else if (a < 16'hFFFF) return REG_HRAM;
    else                   return REG_IE;
  endfunction

  // ALU operations (shared by alu.sv, ~decoder.sv, and ~tb_alu.sv)
  typedef enum logic [4:0] {
    ALU_ADD, ALU_ADC, ALU_SUB, ALU_SBC,
    ALU_AND, ALU_XOR, ALU_OR,  ALU_CP,
    ALU_INC, ALU_DEC,
    ALU_DAA, ALU_CPL, ALU_SCF, ALU_CCF,
    ALU_RLC, ALU_RRC, ALU_RL,  ALU_RR,
    ALU_SLA, ALU_SRA, ALU_SWAP, ALU_SRL,
    ALU_BIT, ALU_RES, ALU_SET,
    ALU_PASS
  } alu_op_t;

  // 3-bit register codes, same encoding the opcodes use
  localparam logic [2:0] R8_B = 3'd0, R8_C = 3'd1, R8_D = 3'd2, R8_E = 3'd3,
                         R8_H = 3'd4, R8_L = 3'd5, R8_HL_MEM = 3'd6, R8_A = 3'd7;

  // 16-bit register pairs. The first four match opcode bits [5:4];
  // PUSH/POP use AF where other instructions use SP.
  typedef enum logic [2:0] {
    RP_BC, RP_DE, RP_HL, RP_SP, RP_AF
  } rp_t;

  // Instruction groups produced by the decoder. The CPU's state machine uses
  // this to decide which bus cycles to run.
  typedef enum logic [5:0] {
    // control
    I_NOP, I_STOP, I_HALT, I_DI, I_EI, I_PREFIX_CB, I_ILLEGAL,
    // 8-bit loads (R8 code 110 means (HL))
    I_LD_R_R, I_LD_R_N,
    I_LD_A_IND, I_LD_IND_A,         // A <-> (BC), (DE), (HL+), (HL-)
    I_LD_A_NN,  I_LD_NN_A,          // A <-> (nn)
    I_LDH_A_N,  I_LDH_N_A,          // A <-> (0xFF00 + n)
    I_LDH_A_C,  I_LDH_C_A,          // A <-> (0xFF00 + C)
    // 16-bit loads and stack
    I_LD_RR_NN, I_LD_NN_SP, I_LD_SP_HL, I_LD_HL_SP_E, I_PUSH, I_POP,
    // 8-bit ALU
    I_ALU_R, I_ALU_N,               // A op register, A op immediate
    I_INCDEC_R,                     // INC / DEC register
    I_ACC,                          // DAA, CPL, SCF, CCF
    I_ROT_A,                        // RLCA, RRCA, RLA, RRA
    I_CB,                           // every CB-prefixed instruction
    // 16-bit arithmetic
    I_INC_RR, I_DEC_RR, I_ADD_HL_RR, I_ADD_SP_E,
    // jumps, calls, returns
    I_JP_NN, I_JP_HL, I_JR, I_CALL, I_RET, I_RETI, I_RST
  } instr_t;

  // Branch conditions, same encoding as opcode bits [4:3]
  typedef enum logic [1:0] {
    COND_NZ, COND_Z, COND_NC, COND_C
  } cond_t;

  // Flag bit positions inside F / the ALU flag bus {Z, N, H, C}
  localparam int FLAG_Z = 3;
  localparam int FLAG_N = 2;
  localparam int FLAG_H = 1;
  localparam int FLAG_C = 0;

endpackage