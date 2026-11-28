// regfile.sv
// Game Boy (SM83) register file: A, F, B, C, D, E, H, L, SP and PC
//
// Reads are combinational. Writes happen on the rising clock edge.
//
// 8-bit registers are selected with the opcode's 3-bit code (R8_* in gb_pkg).

import gb_pkg::*;

module regfile (
    input  logic        clk,
    input  logic        rst,        // synchronous, active high

    // 8-bit read port
    input  logic [2:0]  rsel8,
    output logic [7:0]  rdata8,

    // 8-bit write port
    input  logic        we8,
    input  logic [2:0]  wsel8,
    input  logic [7:0]  wdata8,

    // 16-bit read port
    input  rp_t         rsel16,
    output logic [15:0] rdata16,

    // 16-bit write port
    input  logic        we16,
    input  rp_t         wsel16,
    input  logic [15:0] wdata16,

    // Flags (for the ALU)
    input  logic        flags_we,
    input  logic [3:0]  flags_in,   // {Z, N, H, C}
    output logic [3:0]  flags_out,  // {Z, N, H, C}

    // Program counter
    input  logic        pc_we,
    input  logic [15:0] pc_in,
    output logic [15:0] pc_out,

    // Registers the CPU needs all the time
    output logic [7:0]  a_out,      // ALU operand A
    output logic [15:0] hl_out,     // address for (HL)
    output logic [15:0] sp_out      // stack address
);

    logic [7:0]  a, b, c, d, e, h, l;
    logic [3:0]  f;                 // {Z, N, H, C}
    logic [15:0] sp, pc;

    // ================ Writes ================
    // Reset values are the state the boot ROM leaves behind
    always_ff @(posedge clk) begin
        if (rst) begin
            a  <= 8'h01;
            f  <= 4'hB;             // F = 0xB0
            b  <= 8'h00;
            c  <= 8'h13;
            d  <= 8'h00;
            e  <= 8'hD8;
            h  <= 8'h01;
            l  <= 8'h4D;
            sp <= 16'hFFFE;
            pc <= 16'h0100;
        end else begin
            // Later assignments override earlier ones (this sets the priority)
            if (we16) begin
                case (wsel16)
                    RP_BC:   {b, c} <= wdata16;
                    RP_DE:   {d, e} <= wdata16;
                    RP_HL:   {h, l} <= wdata16;
                    RP_SP:   sp     <= wdata16;
                    RP_AF: begin
                        a <= wdata16[15:8];
                        f <= wdata16[7:4];      // low nibble is dropped (POP AF)
                    end
                    default: ;
                endcase
            end

            if (we8) begin
                case (wsel8)
                    R8_B:    b <= wdata8;
                    R8_C:    c <= wdata8;
                    R8_D:    d <= wdata8;
                    R8_E:    e <= wdata8;
                    R8_H:    h <= wdata8;
                    R8_L:    l <= wdata8;
                    R8_A:    a <= wdata8;
                    default: ;                  // (HL) lives in memory
                endcase
            end

            if (flags_we) f  <= flags_in;
            if (pc_we)    pc <= pc_in;
        end
    end

    // ---------------- Reads ----------------
    always_comb begin
        case (rsel8)
            R8_B:    rdata8 = b;
            R8_C:    rdata8 = c;
            R8_D:    rdata8 = d;
            R8_E:    rdata8 = e;
            R8_H:    rdata8 = h;
            R8_L:    rdata8 = l;
            R8_A:    rdata8 = a;
            default: rdata8 = 8'hFF;
        endcase
    end

    always_comb begin
        case (rsel16)
            RP_BC:   rdata16 = {b, c};
            RP_DE:   rdata16 = {d, e};
            RP_HL:   rdata16 = {h, l};
            RP_SP:   rdata16 = sp;
            RP_AF:   rdata16 = {a, f, 4'h0};
            default: rdata16 = 16'h0000;
        endcase
    end

    assign flags_out = f;
    assign pc_out    = pc;
    assign a_out     = a;
    assign hl_out    = {h, l};
    assign sp_out    = sp;

endmodule
