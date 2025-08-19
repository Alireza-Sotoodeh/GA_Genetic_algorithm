`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:
// Design Name: 
// Module Name: mutation
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mutation #(
    parameter CHROMOSOME_WIDTH = 8
)(
    input logic clk,
    input logic rst_n,
    input logic start_mutation,
    input logic [CHROMOSOME_WIDTH-1:0] child_in,
    input logic [CHROMOSOME_WIDTH-1:0] mutation_mask, // Random bits to determine mutation
    input logic [7:0] mutation_rate, // 0-255, higher means more likely to mutate
    output logic [CHROMOSOME_WIDTH-1:0] child_out,
    output logic mutation_done
);
    // Mutation logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            child_out <= '0;
            mutation_done <= 1'b0;
        end else if (start_mutation) begin
            // For each bit, apply mutation if random value < mutation_rate
            for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
                // If random bit < mutation_rate, flip the bit
                child_out[i] <= (mutation_mask[i] < mutation_rate) ? ~child_in[i] : child_in[i];
                // how???
            end
            mutation_done <= 1'b1;
        end else begin
            mutation_done <= 1'b0;
        end
    end
endmodule