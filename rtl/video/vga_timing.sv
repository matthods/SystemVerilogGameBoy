// vga_timing.sv
// Generates the position counters and sync signals for a VGA monitor.
// Default settings are standard 640x480 at 60 Hz, which needs a pixel
// clock of about 25.175 MHz (25 MHz works fine on almost every monitor).
//
// A VGA monitor draws the picture one row at a time, left to right, then
// moves to the next row. Each row has extra time after the visible pixels:
//
//   |<-- visible 640 -->|front 16|<- sync 96 ->|back 48|   = 800 per row
//
// and the frame has extra rows after the visible 480:
//
//   |<-- visible 480 -->|front 10|sync 2|back 33|          = 525 rows
//
// hsync and vsync are ACTIVE LOW: they sit at 1 and dip to 0 during sync.
//
// This design runs everything on the fast board clock and uses "pix_ce"
// (clock enable, a one-cycle pulse once per pixel) to step forward at the
// pixel rate. That avoids a second clock.

module vga_timing #(
    parameter int H_VISIBLE = 640,
    parameter int H_FRONT   = 16,
    parameter int H_SYNC    = 96,
    parameter int H_BACK    = 48,
    parameter int V_VISIBLE = 480,
    parameter int V_FRONT   = 10,
    parameter int V_SYNC    = 2,
    parameter int V_BACK    = 33
)(
    input  logic       clk,
    input  logic       rst,       // active high
    input  logic       pix_ce,    // pulses once per pixel

    output logic [9:0] x,         // current column, 0 .. H_TOTAL-1
    output logic [9:0] y,         // current row,    0 .. V_TOTAL-1
    output logic       active,    // 1 while inside the visible area
    output logic       hsync,     // active low
    output logic       vsync      // active low
);

    localparam int H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;   // 800
    localparam int V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;   // 525

    // The same numbers as unsigned 10-bit constants, for comparing with x and y
    localparam logic [9:0] H_LAST   = 10'(H_TOTAL - 1);
    localparam logic [9:0] V_LAST   = 10'(V_TOTAL - 1);
    localparam logic [9:0] H_VIS    = 10'(H_VISIBLE);
    localparam logic [9:0] V_VIS    = 10'(V_VISIBLE);
    localparam logic [9:0] HS_START = 10'(H_VISIBLE + H_FRONT);
    localparam logic [9:0] HS_END   = 10'(H_VISIBLE + H_FRONT + H_SYNC);
    localparam logic [9:0] VS_START = 10'(V_VISIBLE + V_FRONT);
    localparam logic [9:0] VS_END   = 10'(V_VISIBLE + V_FRONT + V_SYNC);

    always_ff @(posedge clk) begin
        if (rst) begin
            x <= '0;
            y <= '0;
        end else if (pix_ce) begin
            if (x == H_LAST) begin
                x <= '0;
                if (y == V_LAST) y <= '0;
                else                       y <= y + 10'd1;
            end else begin
                x <= x + 10'd1;
            end
        end
    end

    assign active = (x < H_VIS) && (y < V_VIS);

    assign hsync = ~((x >= HS_START) && (x < HS_END));

    assign vsync = ~((y >= VS_START) && (y < VS_END));

endmodule