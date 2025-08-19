module crossover #(
    parameter CHROMOSOME_WIDTH = 8
)(
    input logic clk,
    input logic rst_n,
    input logic start_crossover,
    input logic [CHROMOSOME_WIDTH-1:0] parent1,
    input logic [CHROMOSOME_WIDTH-1:0] parent2,
    input logic [2:0] crossover_point, // Point at which to split the chromosomes
    output logic [CHROMOSOME_WIDTH-1:0] child,
    output logic crossover_done
);
    // Crossover logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            child <= '0;
            crossover_done <= 1'b0;
        end else if (start_crossover) begin
            // Single-point crossover
			//child <= {parent1[CHROMOSOME_WIDTH-1:crossover_point], parent2[crossover_point-1:0]};
            child <= {parent1[CHROMOSOME_WIDTH-1:2], parent2[2:0]};
            crossover_done <= 1'b1;
        end else begin
            crossover_done <= 1'b0;
        end
    end
endmodule