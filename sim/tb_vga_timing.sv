// tb_vga_timing.sv
// Self-checking testbench for rtl/video/vga_timing.sv.
// Runs two full frames and checks the standard 640x480 @ 60 Hz numbers:
//   - hsync is low for exactly 96 pixels on every row
//   - vsync is low for exactly 2 rows per frame
//   - exactly 640 x 480 = 307,200 pixels are "active" per frame
//   - hsync starts at column 656 and vsync at row 490
//   - the counters wrap at 800 columns and 525 rows
// pix_ce is held high, so it steps every clock cycle (fast to simulate).

module tb_vga_timing;

    localparam int H_TOTAL = 800;
    localparam int V_TOTAL = 525;
    localparam logic [9:0] H_LAST = 10'd799;
    localparam logic [9:0] V_LAST = 10'd524;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic       rst = 1'b1;
    logic [9:0] x, y;
    logic       active, hsync, vsync;

    vga_timing dut (
        .clk    (clk),
        .rst    (rst),
        .pix_ce (1'b1),
        .x      (x),
        .y      (y),
        .active (active),
        .hsync  (hsync),
        .vsync  (vsync)
    );

    int errors = 0;

    task automatic fail(input string msg);
        errors++;
        if (errors <= 10) $display("  FAIL @ %0t: %s", $time, msg);
    endtask

    int hs_low       = 0;   // hsync-low pixels in the current row
    int active_cnt   = 0;   // active pixels in the current frame
    int vs_low_rows  = 0;   // rows with vsync low in the current frame
    int frames       = 0;

    initial begin
        repeat (3) @(posedge clk);
        #1 rst = 1'b0;                       // release reset just after a clock edge

        // Idle level check: sync lines sit high before sync starts
        if (hsync !== 1'b1 || vsync !== 1'b1) fail("sync lines should idle high");

        while (frames < 2) begin
            // ---- look at the current pixel ----
            if (active) active_cnt++;
            if (!hsync) hs_low++;

            // hsync must start at column 656 and end at 751
            if (x == 10'd655 && hsync !== 1'b1) fail("hsync low too early");
            if (x == 10'd656 && hsync !== 1'b0) fail("hsync should start at column 656");
            if (x == 10'd752 && hsync !== 1'b1) fail("hsync should end at column 752");

            // vsync must start at row 490 and end at row 491
            if (x == 10'd0 && y == 10'd489 && vsync !== 1'b1) fail("vsync low too early");
            if (x == 10'd0 && y == 10'd490 && vsync !== 1'b0) fail("vsync should start at row 490");
            if (x == 10'd0 && y == 10'd492 && vsync !== 1'b1) fail("vsync should end at row 492");

            // active exactly when x < 640 and y < 480
            if (active !== ((x < 10'd640) && (y < 10'd480))) fail("active flag wrong");

            // ---- end of a row ----
            if (x == H_LAST) begin
                if (hs_low != 96) fail($sformatf("row %0d: hsync low for %0d pixels, expected 96", y, hs_low));
                hs_low = 0;
                if (!vsync) vs_low_rows++;

                // ---- end of a frame ----
                if (y == V_LAST) begin
                    if (active_cnt  != 640 * 480)
                        fail($sformatf("%0d active pixels in frame, expected %0d", active_cnt, 640 * 480));
                    if (vs_low_rows != 2)
                        fail($sformatf("vsync low for %0d rows, expected 2", vs_low_rows));
                    active_cnt  = 0;
                    vs_low_rows = 0;
                    frames++;
                end
            end

            // ---- advance one pixel ----
            @(posedge clk); #1;

            // counters must wrap correctly
            if (x > H_LAST || y > V_LAST) fail("counter went out of range");
        end

        if (errors == 0) $display("PASS: VGA timing correct for %0d frames", frames);
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    // Safety net: two frames take about 8.4 ms
    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule