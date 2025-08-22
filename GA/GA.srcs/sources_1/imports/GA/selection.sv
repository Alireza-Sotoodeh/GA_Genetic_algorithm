(* keep_hierarchy = "yes" *)
module selection #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter POPULATION_SIZE = 16,
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE),
    parameter FITNESS_WIDTH = 14,  // Matches fitness_evaluator
    parameter LSFR_WIDTH = 16      // Matches crossover for random input
)(
	clk,
	rst,
	start_selection,
	fitness_values,
	total_fitness,
	LSFR_input,
	selected_parent,
	selection_done
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Inputs (similar to crossover style)
    input logic clk;
    input logic rst;  // Note: posedge rst like crossover and fitness_evaluator
    input logic start_selection;
    input logic [FITNESS_WIDTH-1:0] fitness_values [POPULATION_SIZE-1:0];
    input logic [FITNESS_WIDTH-1:0] total_fitness;
    input logic [LSFR_WIDTH-1:0] LSFR_input;  // External random like crossover

    // Outputs
    (* use_dsp = "no" *)
    output logic [ADDR_WIDTH-1:0] selected_parent;
    output logic selection_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''


    // Internal signals (simple, like crossover masks)
    (* keep = "true" *) logic [FITNESS_WIDTH + LSFR_WIDTH - 1:0] roulette_position;  // Wide for scaling
    (* keep = "true" *) logic [FITNESS_WIDTH-1:0] fitness_sum;
    (* keep = "true" *) logic total_fitness_zero;
    (* keep = "true" *) logic selecting;  // Internal flag for process (like evaluating in fitness_evaluator)
    (* keep = "true" *) logic [ADDR_WIDTH-1:0] selected_parent_comb;  // New internal comb signal to avoid multi-driver
    // =========================
    // Combinational preparation (like crossover always_comb)
    // =========================
    always_comb begin
        // Detect zero total fitness
        total_fitness_zero = (total_fitness == '0);

        // Scale random value to total fitness range or uniform for zero case
        if (total_fitness_zero) begin
            roulette_position = LSFR_input % POPULATION_SIZE;  // Uniform random index (edge case handler)
        end else begin
            // Explicit wide multiplication to avoid overflow
            logic [FITNESS_WIDTH + LSFR_WIDTH - 1:0] product;
            product = LSFR_input * total_fitness;
            roulette_position = product >> LSFR_WIDTH;  // Scale down
        end

        // Combinational loop for selection (unrollable, single-cycle)
        fitness_sum = '0;
        selected_parent_comb = '0;  // Default
        for (int i = 0; i < POPULATION_SIZE; i++) begin
            if (fitness_sum + fitness_values[i] >= roulette_position) begin
                selected_parent_comb = i[ADDR_WIDTH-1:0];
                break;
            end
            fitness_sum += fitness_values[i];
        end
        // Force last index if no match (edge case: position > max sum)
        if (fitness_sum < roulette_position) begin
            selected_parent_comb = POPULATION_SIZE - 1;
        end
    end

    // =========================
    // Sequential process (like crossover and fitness_evaluator)
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            selected_parent <= '0;
            selection_done <= 1'b0;
            selecting <= 1'b0;
        end else begin
            // Default: Deassert done to ensure one-cycle pulse
            selection_done <= 1'b0;

            if (start_selection && !selecting) begin
                // Start selection, use comb results, set flag
                // selected_parent already set in comb
                selected_parent <= selected_parent_comb;  // Sample comb value here (single driver)
                selecting <= 1'b1;
            end else if (selecting) begin
                // Pulse done and clear flag (single-cycle completion)
                selection_done <= 1'b1;
                selecting <= 1'b0;
            end
            // Note: If start_selection held high, won't re-trigger until selecting clears
        end
    end

    // Assertion for validation (debug, optional) can be removed later
    `ifdef SYNTHESIS
    `else
    always @(posedge clk) begin
        assert (total_fitness >= '0) else $error("Negative total_fitness detected!");
        if (total_fitness_zero) assert (selected_parent < POPULATION_SIZE) else $error("Invalid uniform selection!");
    end
    `endif

endmodule
