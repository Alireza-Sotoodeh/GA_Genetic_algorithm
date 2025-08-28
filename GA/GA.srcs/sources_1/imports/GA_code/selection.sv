`timescale 1ns/1ps
/***************************************************************************************************
*  File Name   : selection.sv
*  Author      : Alireza Sotoodeh
*  Instructor  : Dr. Ali Mahani
*  Date        : 2025-08
*  Module Type : Genetic Algorithm - Selection Unit
*
*  Description:
*    Selects two parent indices from the population using roulette-wheel method.
***************************************************************************************************/

module selection #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14,
    parameter MAX_POP_SIZE = 100,
    parameter ADDR_WIDTH = $clog2(MAX_POP_SIZE),
    parameter LFSR_WIDTH = 16      
)(
    clk,
    rst,
    start_selection,
    fitness_values,             
    total_fitness,              
    lfsr_input,                 
    selected_index1,            
    selected_index2,          
    selection_done,
    population_size
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Inputs 
    input  logic                                clk;
    input  logic                                rst;  
    input  logic                                start_selection;
    input  logic [FITNESS_WIDTH-1:0]            fitness_values [MAX_POP_SIZE-1:0];
    input  logic [FITNESS_WIDTH-1:0]            total_fitness;
    input  logic [LFSR_WIDTH-1:0]               lfsr_input;  
    input  logic [ADDR_WIDTH-1:0]               population_size;

    // Outputs
    output logic [ADDR_WIDTH-1:0]               selected_index1;
    output logic [ADDR_WIDTH-1:0]               selected_index2;
    output logic                                selection_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

    // Internal signals 
    (* keep = "true" *) logic [FITNESS_WIDTH + LFSR_WIDTH - 1:0] roulette_pos1, roulette_pos2;
    (* keep = "true" *) logic [FITNESS_WIDTH + ADDR_WIDTH -1:0] fitness_sum1, fitness_sum2;  
    (* keep = "true" *) logic                  total_fitness_zero;
    (* keep = "true" *) logic                  selecting;  
    (* keep = "true" *) logic [ADDR_WIDTH-1:0] selected_index1_comb, selected_index2_comb;  

    // =========================
    // Combinational preparation
    // =========================
    always_comb begin
        automatic logic found1 = 1'b0;
        automatic logic found2 = 1'b0;
		// edge handler
        total_fitness_zero = (total_fitness == '0);
        if (total_fitness_zero) begin
            roulette_pos1 = lfsr_input % population_size;  
            roulette_pos2 = (lfsr_input ^ (lfsr_input >> (LFSR_WIDTH/2))) % population_size;  // XOR for difference (ensure != pos1)
            selected_index1_comb = roulette_pos1[ADDR_WIDTH-1:0];
            selected_index2_comb = roulette_pos2[ADDR_WIDTH-1:0];
            fitness_sum1 = '0;
            fitness_sum2 = '0;
        end else begin
            logic [(FITNESS_WIDTH + LFSR_WIDTH)-1:0] product1, product2;
            product1 = lfsr_input * total_fitness;
            roulette_pos1 = product1 >> LFSR_WIDTH;  
            product2 = (lfsr_input ^ (lfsr_input >> 8)) * total_fitness;  // Modify for second different value
            roulette_pos2 = product2 >> LFSR_WIDTH;

            // Comb loop for selection1 
            fitness_sum1 = '0;
            selected_index1_comb = '0;
            for (int i = 0; i < MAX_POP_SIZE; i++) begin
                if (i < population_size && !found1 && (fitness_sum1 + fitness_values[i] > roulette_pos1)) begin
                    selected_index1_comb = i[ADDR_WIDTH-1:0];
                    found1 = 1'b1;
                end
                if (i < population_size) fitness_sum1 += fitness_values[i];
            end
            if (!found1 && population_size > 0) selected_index1_comb = population_size - 1;  

            // Comb loop for selection2 (parallel)
            fitness_sum2 = '0;
            selected_index2_comb = '0;
            for (int i = 0; i < MAX_POP_SIZE; i++) begin
                if (i < population_size && !found2 && (fitness_sum2 + fitness_values[i] > roulette_pos2)) begin
                    selected_index2_comb = i[ADDR_WIDTH-1:0];
                    found2 = 1'b1;
                end
                if (i < population_size) fitness_sum2 += fitness_values[i];
            end
            if (!found2 && population_size > 0) selected_index2_comb = population_size - 1;
        end

        // Ensure different indices (re-assign if same)
        if (selected_index1_comb == selected_index2_comb && population_size > 1) begin
            selected_index2_comb = (selected_index2_comb + 1) % population_size;
        end
    end

    // =========================
    // Sequential process 
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            selected_index1 <= '0;
            selected_index2 <= '0;
            selection_done <= 1'b0;
            selecting <= 1'b0;
        end else begin
            selection_done <= 1'b0; // Default
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

endmodule