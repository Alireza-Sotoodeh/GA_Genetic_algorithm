`timescale 1ns/1ps

module selection #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14,
    parameter POPULATION_SIZE = 16,
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE),
    parameter LFSR_WIDTH = 16      // For random input, matches crossover
)(
    clk,
    rst,
    start_selection,
    fitness_values,             // From population_memory (array)
    total_fitness,              // From population_memory (accumulator)
    lfsr_input,                 // External random like crossover
    selected_index1,            // Output index1 for parent1 (to population_memory read_addr1)
    selected_index2,            // Output index2 for parent2 (to population_memory read_addr2)
    selection_done
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Inputs (similar to crossover style)
    input  logic                                clk;
    input  logic                                rst;  // Active-high like crossover
    input  logic                                start_selection;
    input  logic [FITNESS_WIDTH-1:0]            fitness_values [POPULATION_SIZE-1:0];
    input  logic [FITNESS_WIDTH-1:0]            total_fitness;
    input  logic [LFSR_WIDTH-1:0]               lfsr_input;  // External random

    // Outputs
    output logic [ADDR_WIDTH-1:0]               selected_index1;
    output logic [ADDR_WIDTH-1:0]               selected_index2;
    output logic                                selection_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

    // Internal signals (like crossover masks/prep)
    (* keep = "true" *) logic [FITNESS_WIDTH + LFSR_WIDTH - 1:0] roulette_pos1, roulette_pos2;  // Wide for scaling, two different positions
    (* keep = "true" *) logic [FITNESS_WIDTH + ADDR_WIDTH -1:0] fitness_sum1, fitness_sum2;  // Increased width to prevent overflow
    (* keep = "true" *) logic                  total_fitness_zero;
    (* keep = "true" *) logic                  selecting;  // Internal flag like crossover (for two-cycle)
    (* keep = "true" *) logic [ADDR_WIDTH-1:0] selected_index1_comb, selected_index2_comb;  // Comb results

    // =========================
    // Combinational preparation (like crossover: prepare two different roulette positions and comb selection)
    // =========================
    always_comb begin
        automatic logic found1 = 1'b0;
        automatic logic found2 = 1'b0;
        // Detect zero total fitness
        total_fitness_zero = (total_fitness == '0);
        
        // Generate two different positions (use lfsr_input split/modified for difference)
        if (total_fitness_zero) begin
            roulette_pos1 = lfsr_input % POPULATION_SIZE;  // Uniform random index
            roulette_pos2 = (lfsr_input ^ (lfsr_input >> (LFSR_WIDTH/2))) % POPULATION_SIZE;  // XOR for difference (ensure != pos1)
            selected_index1_comb = roulette_pos1[ADDR_WIDTH-1:0];
            selected_index2_comb = roulette_pos2[ADDR_WIDTH-1:0];
            fitness_sum1 = '0;
            fitness_sum2 = '0;
        end else begin
            // Wide multiplication for scaling (avoid overflow)
            logic [(FITNESS_WIDTH + LFSR_WIDTH)-1:0] product1, product2;
            product1 = lfsr_input * total_fitness;
            roulette_pos1 = product1 >> LFSR_WIDTH;  // Scale down
            product2 = (lfsr_input ^ (lfsr_input >> 8)) * total_fitness;  // Modify for second different value
            roulette_pos2 = product2 >> LFSR_WIDTH;

            // Comb loop for selection1 (unrollable, single-cycle, using flag instead of break)
            fitness_sum1 = '0;
            selected_index1_comb = '0;
            for (int i = 0; i < POPULATION_SIZE; i++) begin
                if (!found1 && (fitness_sum1 + fitness_values[i] > roulette_pos1)) begin
                    selected_index1_comb = i[ADDR_WIDTH-1:0];
                    found1 = 1'b1;
                end
                fitness_sum1 += fitness_values[i];
            end
            if (!found1) selected_index1_comb = POPULATION_SIZE - 1;  // Edge: last

            // Comb loop for selection2 (parallel)
            fitness_sum2 = '0;
            selected_index2_comb = '0;
            for (int i = 0; i < POPULATION_SIZE; i++) begin
                if (!found2 && (fitness_sum2 + fitness_values[i] > roulette_pos2)) begin
                    selected_index2_comb = i[ADDR_WIDTH-1:0];
                    found2 = 1'b1;
                end
                fitness_sum2 += fitness_values[i];
            end
            if (!found2) selected_index2_comb = POPULATION_SIZE - 1;
        end

        // Ensure different indices (re-assign if same; simple: swap with next if equal)
        if (selected_index1_comb == selected_index2_comb) begin
            selected_index2_comb = (selected_index2_comb + 1) % POPULATION_SIZE;
        end
    end

    // =========================
    // Sequential process (like crossover: register comb results, handshake)
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            selected_index1 <= '0;
            selected_index2 <= '0;
            selection_done <= 1'b0;
            selecting <= 1'b0;
        end else begin
            // Default: Deassert done for one-cycle pulse
            selection_done <= 1'b0;

            if (start_selection && !selecting) begin
                // Cycle 1: Sample comb, set flag
                selected_index1 <= selected_index1_comb;
                selected_index2 <= selected_index2_comb;
                selecting <= 1'b1;
            end else if (selecting) begin
                // Cycle 2: Pulse done, clear flag
                selection_done <= 1'b1;
                selecting <= 1'b0;
            end
        end
    end

    // Notes on structure and potential issues:
    // - Pipelined: Selection takes 2 cycles (prep + done), outputs indices for immediate comb read in population_memory.
    // - Roulette wheel: Two different positions from modified random; ensures indices differ (avoids same parent).
    // - Ties: Uses > for selection (prefers higher if tie); population sorted helps.
    // - Zero total_fitness: Falls to uniform random, ensures different.
    // - Overflow: Wide multiplication prevents; assumes total_fitness fits (from population_memory handling).
    // - Connection: In top, connect selected_index1/2 to population_memory's read_addr1/2, get parent1_out/parent2_out to crossover.
    // - For true pipeline, if loops slow, unroll further; current fine for POP_SIZE=16.

endmodule