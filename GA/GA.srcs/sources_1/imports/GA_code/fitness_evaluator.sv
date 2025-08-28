`timescale 1ns/1ps
/***************************************************************************************************
*  File Name   : fitness_evaluator.sv
*  Author      : Alireza Sotoodeh
*  Instructor  : Dr. Ali Mahani
*  Date        : 2025-08
*  Module Type : Genetic Algorithm - Fitness Evaluator
*
*  Description:
*    Calculates the fitness score by summing the bits of the given chromosome.
*    Outputs the final fitness value and a done flag when evaluation completes.
***************************************************************************************************/

(* keep_hierarchy = "yes" *)
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
	// inputs 
    input 	logic 								clk;
    input 	logic 								rst;
    input 	logic 								start_evaluation;
    input 	logic [CHROMOSOME_WIDTH-1:0] 		chromosome;
	
	// outputs
    output 	logic [FITNESS_WIDTH-1:0] 			fitness;
    output 	logic 								evaluation_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

	// Internal signals
	(* use_dsp = "no" *)
    (* keep = "true" *) 
	logic [FITNESS_WIDTH-1:0] raw_fitness;  

     // =========================
    // Combinational preparation
    // =========================
    always_comb begin
        raw_fitness = {FITNESS_WIDTH{1'b0}};  // Initialize to 0
        for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
            raw_fitness += { {(FITNESS_WIDTH-1){1'b0}}, chromosome[i] };  // calculate
        end
        // raw_fitness cant be more then bit size! (for safety)
        if (raw_fitness > {FITNESS_WIDTH{1'b1}}) begin
            raw_fitness = {FITNESS_WIDTH{1'b1}};
        end
    end

    // ==============================
	// (Sequential part)
    // Main fitness_evaluator process 
    // ==============================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fitness <= '0;
            evaluation_done <= 1'b0;
        end else begin
            evaluation_done <= 1'b0; // Default
            if (start_evaluation) begin
                fitness <= raw_fitness;
                evaluation_done <= 1'b1;
            end
        end
    end
    
endmodule