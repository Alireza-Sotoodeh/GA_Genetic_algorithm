module fitness_evaluator #(
    parameter CHROMOSOME_WIDTH = 8,
    parameter FITNESS_WIDTH = 10
)(
    input logic clk,
    input logic rst_n,
    input logic start_evaluation,
    input logic [CHROMOSOME_WIDTH-1:0] chromosome,
    output logic [FITNESS_WIDTH-1:0] fitness,
    output logic evaluation_done
);
    // Example fitness function: count number of '1' bits (maximize)
    // Replace with your specific fitness function
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fitness <= '0;
            evaluation_done <= 1'b0;
        end else if (start_evaluation) begin
            fitness <= '0;
            // Count '1' bits
            for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
                if (chromosome[i]) begin
                    fitness <= fitness + 1'b1;
                end
            end
            evaluation_done <= 1'b1;
        end else begin
            evaluation_done <= 1'b0;
        end
    end
endmodule