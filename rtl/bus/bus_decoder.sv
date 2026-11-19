// Securely decodes an incoming system address bus to generate peripheral select signals
module bus_decoder #(
    parameter int ADDR_WIDTH = 16,
    parameter int NUM_SLAVES = 4,
    
    // Define base addresses and masks for each peripheral
    parameter bit [ADDR_WIDTH-1:0] BASE_RAM   = 'h0000_0000,
    parameter bit [ADDR_WIDTH-1:0] MASK_RAM   = 32'hFFF0_0000, // 1MB Range
    
    parameter bit [ADDR_WIDTH-1:0] BASE_ROM   = 32'h1000_0000,
    parameter bit [ADDR_WIDTH-1:0] MASK_ROM   = 32'hFFFF_0000, // 64KB Range
    
    parameter bit [ADDR_WIDTH-1:0] BASE_UART  = 32'h4000_0000,
    parameter bit [ADDR_WIDTH-1:0] MASK_UART  = 32'hFFFF_F000, // 4KB Range
    
    parameter bit [ADDR_WIDTH-1:0] BASE_GPIO  = 32'h4000_1000,
    parameter bit [ADDR_WIDTH-1:0] MASK_GPIO  = 32'hFFFF_F000  // 4KB Range
)(
    input  logic [ADDR_WIDTH-1:0] master_addr,
    input  logic                  master_valid,
    
    // One-hot slave select lines
    output logic [NUM_SLAVES-1:0] slave_sel,
    // Target-relative offset address passed to the selected slave
    output logic [ADDR_WIDTH-1:0] slave_offset_addr,
    // Error flag triggered if master targets an unmapped memory region
    output logic                  decode_error
);

    // Named indices for clarity matching the slave vector array
    localparam int SLAVE_RAM  = 0;
    localparam int SLAVE_ROM  = 1;
    localparam int SLAVE_UART = 2;
    localparam int SLAVE_GPIO = 3;

    always_comb begin
        // Default safe assignments to avoid latches
        slave_sel         = '0;
        slave_offset_addr = '0;
        decode_error      = 1'b0;

        if (master_valid) begin
            // 'unique case' ensures parallel synthesis and catches design flaws (overlapping ranges)
            unique case (1'b1)
                // RAM Range Check
                ((master_addr & MASK_RAM) == BASE_RAM): begin
                    slave_sel[SLAVE_RAM] = 1'b1;
                    slave_offset_addr    = master_addr & ~MASK_RAM;
                end
                
                // ROM Range Check
                ((master_addr & MASK_ROM) == BASE_ROM): begin
                    slave_sel[SLAVE_ROM] = 1'b1;
                    slave_offset_addr    = master_addr & ~MASK_ROM;
                end
                
                // UART Range Check
                ((master_addr & MASK_UART) == BASE_UART): begin
                    slave_sel[SLAVE_UART] = 1'b1;
                    slave_offset_addr     = master_addr & ~MASK_UART;
                end
                
                // GPIO Range Check
                ((master_addr & MASK_GPIO) == BASE_GPIO): begin
                    slave_sel[SLAVE_GPIO] = 1'b1;
                    slave_offset_addr     = master_addr & ~MASK_GPIO;
                end
                
                // Fallthrough catch for unmapped spaces
                default: begin
                    decode_error = 1'b1;
                end
            endcase
        end
    end

endmodule
