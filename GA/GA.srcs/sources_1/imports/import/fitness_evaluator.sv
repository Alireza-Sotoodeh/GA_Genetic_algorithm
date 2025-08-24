module fitness_evaluator #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14
)(
    clk,
    rst,
    start_evaluation,
    chromosome,
    fitness,
    evaluation_done
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    input logic clk;
    input logic rst;
    input logic start_evaluation;
    input logic [CHROMOSOME_WIDTH-1:0] chromosome;
    output logic [FITNESS_WIDTH-1:0] fitness;
    output logic evaluation_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

    logic [FITNESS_WIDTH-1:0] raw_fitness;  // Combinational result
    logic evaluating;  // New: Internal flag for two-cycle

    // Combinational fitness calculation (synthesizable popcount using loop)
    always_comb begin
        raw_fitness = {FITNESS_WIDTH{1'b0}};  // Initialize to 0
        for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
            raw_fitness += { {(FITNESS_WIDTH-1){1'b0}}, chromosome[i] };  // Add 1 if bit is set (zero-extend to avoid overflow)
        end
        // Clamp to max value to avoid overflow in GA summation (optional for small CHROMOSOME_WIDTH)
        if (raw_fitness > {FITNESS_WIDTH{1'b1}}) begin
            raw_fitness = {FITNESS_WIDTH{1'b1}};
        end
    end

    // Sequential registration and handshaking (unchanged)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fitness <= '0;
            evaluation_done <= 1'b0;
            evaluating <= 1'b0;  // Reset the new flag
        end else begin
            // Default: Deassert done to ensure one-cycle pulse
            evaluation_done <= 1'b0;

            if (start_evaluation && !evaluating) begin
                // Cycle 1: Start evaluation, register fitness, set flag
                fitness <= raw_fitness;
                evaluating <= 1'b1;
            end else if (evaluating) begin
                // Cycle 2: Pulse done and clear flag
                evaluation_done <= 1'b1;
                evaluating <= 1'b0;
            end
            // Note: If start_evaluation is held high, it won't re-trigger until evaluating clears
        end
    end
    
endmodule
