// vga_test_top.sv
// Temporary top level that shows a test pattern on the VGA monitor.
// Use it to prove that the board, cable, and video timing all work.
// When the Game Boy pieces are ready, switch the project's top module
// back to gb_top and feed the PPU's picture in place of the test pattern.
//
//   SW[1:0]      choose the pattern (0 bars, 1 gradient, 2 checkerboard, 3 Game Boy outline)
//   CPU_RESETN   red button, resets the video timing

module vga_test_top (
    input  logic       CLK100MHZ,
    input  logic       CPU_RESETN,   // active low
    input  logic [1:0] SW,
    output logic [3:0] VGA_R,
    output logic [3:0] VGA_G,
    output logic [3:0] VGA_B,
    output logic       VGA_HS,
    output logic       VGA_VS
);

    // ---- Pixel clock enable: 100 MHz / 4 = 25 MHz ----
    logic [1:0] div = 2'd0;
    logic       pix_ce;

    always_ff @(posedge CLK100MHZ) div <= div + 2'd1;
    assign pix_ce = (div == 2'd3);

    // ---- Bring the button and switches into the clock domain ----
    // Two flip-flops in a row (a 2-flop synchronizer) stop glitches when
    // an input changes at the same moment as the clock.
    logic [1:0] rst_sync = 2'b11;
    logic [1:0] sw_meta  = 2'b00;
    logic [1:0] sw_sync  = 2'b00;
    logic       rst;

    always_ff @(posedge CLK100MHZ) begin
        rst_sync <= {rst_sync[0], ~CPU_RESETN};
        sw_meta  <= SW;
        sw_sync  <= sw_meta;
    end
    assign rst = rst_sync[1];

    // ---- Video timing and pattern ----
    logic [9:0] x, y;
    logic       active, hs, vs;
    logic [3:0] r, g, b;

    vga_timing timing (
        .clk    (CLK100MHZ),
        .rst    (rst),
        .pix_ce (pix_ce),
        .x      (x),
        .y      (y),
        .active (active),
        .hsync  (hs),
        .vsync  (vs)
    );

    vga_test_pattern pattern (
        .x   (x),
        .y   (y),
        .sel (sw_sync),
        .r   (r),
        .g   (g),
        .b   (b)
    );

    // ---- Register all outputs together so color and sync stay aligned.
    // Colors must be black outside the visible area. ----
    always_ff @(posedge CLK100MHZ) begin
        if (pix_ce) begin
            VGA_R  <= active ? r : 4'h0;
            VGA_G  <= active ? g : 4'h0;
            VGA_B  <= active ? b : 4'h0;
            VGA_HS <= hs;
            VGA_VS <= vs;
        end
    end

endmodule