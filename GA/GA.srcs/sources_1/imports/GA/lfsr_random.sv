module lfsr_random #(
    parameter WIDTH = 8
)(
    input logic clk,
    input logic rst_n,
    input logic enable,
    output logic [WIDTH-1:0] random_out
);
    // LFSR polynomial taps for maximum period
    // Using x^8 + x^6 + x^5 + x^4 + 1 for 8-bit LFSR
    logic [WIDTH-1:0] lfsr_reg;
    logic feedback;
    
    assign feedback = lfsr_reg[7] ^ lfsr_reg[5] ^ lfsr_reg[4] ^ lfsr_reg[3];
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Non-zero seed value
            lfsr_reg <= 8'hFF;
        end else if (enable) begin
            // Shift right and insert feedback bit
            lfsr_reg <= {feedback, lfsr_reg[WIDTH-1:1]};
        end
    end
    
    assign random_out = lfsr_reg;
endmodule
