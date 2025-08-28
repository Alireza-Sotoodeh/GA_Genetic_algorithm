`timescale 1ns/1ps
/***************************************************************************************************
*  File Name   : population_memory.sv
*  Author      : Alireza Sotoodeh
*  Instructor  : Dr. Ali Mahani
*  Date        : 2025-08
*  Module Type : Genetic Algorithm - Population Memory
*
*  Description:
*    Stores chromosomes and fitness values in sorted order.
*    Supports reading parents, total fitness requests, and inserting new individuals
*    while preserving population ranking.
***************************************************************************************************/

(* keep_hierarchy = "yes" *)
module population_memory #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14,
    parameter MAX_POP_SIZE = 100,
    parameter ADDR_WIDTH = $clog2(MAX_POP_SIZE)
)(
    clk,
    rst,
    start_write,
    child_in,                   
    child_fitness_in,           
    read_addr1,                 
    read_addr2,                 
    request_fitness_values,     
    request_total_fitness,      
    parent1_out,                
    parent2_out,                
    fitness_values_out,         
    total_fitness_out,          
    write_done,
    population_size                 
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Inputs
    input  logic                                clk;
    input  logic                                rst;  
    input  logic                                start_write;
    input  logic [CHROMOSOME_WIDTH-1:0]         child_in;
    input  logic [FITNESS_WIDTH-1:0]            child_fitness_in;
    input  logic [ADDR_WIDTH-1:0]               read_addr1;
    input  logic [ADDR_WIDTH-1:0]               read_addr2;
    input  logic                                request_fitness_values;
    input  logic                                request_total_fitness;
    input  logic [ADDR_WIDTH-1:0]               population_size;

    // Outputs
    output logic [CHROMOSOME_WIDTH-1:0]         parent1_out;
    output logic [CHROMOSOME_WIDTH-1:0]         parent2_out;
    output logic [FITNESS_WIDTH-1:0]            fitness_values_out [MAX_POP_SIZE-1:0];
    output logic [FITNESS_WIDTH-1:0]            total_fitness_out;
    output logic                                write_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

    // Internal storage
    (* ram_style = "block" *) logic [CHROMOSOME_WIDTH-1:0] population [MAX_POP_SIZE-1:0];
    (* ram_style = "block" *) logic [FITNESS_WIDTH-1:0]    fitness_values [MAX_POP_SIZE-1:0];
							  logic [FITNESS_WIDTH:0]      internal_total_fitness;  

    // internal
    (* keep = "true" *) logic [ADDR_WIDTH-1:0] insert_pos;          
    (* keep = "true" *) logic                  insert_found;         
    (* keep = "true" *) logic [FITNESS_WIDTH-1:0] old_fitness_remove; 
    logic                  writing;               

    // =========================
    // Combinational preparation 
    // =========================
    always_comb begin
        // always can read
        parent1_out = population[read_addr1];
        parent2_out = population[read_addr2];
		// fitness value request 
        if (request_fitness_values) begin
            fitness_values_out = fitness_values;
        end else begin
            fitness_values_out = '{default: '0};
        end
		// total fitness value request 
        if (request_total_fitness) begin
            total_fitness_out = internal_total_fitness[FITNESS_WIDTH-1:0];  
        end else begin
            total_fitness_out = '0;
        end

        
        insert_pos = population_size - 1;  	// Default: replace worst
        insert_found = 1'b0;				// flag 
        old_fitness_remove = (population_size > 0) ? fitness_values[population_size-1] : '0;  
        for (int i = 0; i < MAX_POP_SIZE; i++) begin
            if (i < population_size && child_fitness_in > fitness_values[i]) begin
                insert_pos = i[ADDR_WIDTH-1:0];
                insert_found = 1'b1;
                break;  // Insert here, will shift rest down
            end
        end
    end

    // =========================
	// (Sequential part)
    // Main process 
    // =========================
    (* use_dsp = "no" *)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < MAX_POP_SIZE; i++) begin
                population[i] <= '0;
                fitness_values[i] <= '0;
            end
            internal_total_fitness <= '0;
            write_done <= 1'b0;
            writing <= 1'b0;
        end else begin
            write_done <= 1'b0; // Default
			//writing done in 2 cycle for safety pipeline
            if (start_write && !writing) begin
                writing <= 1'b1;
            end else if (writing) begin
                if (insert_found) begin
                    internal_total_fitness <= (internal_total_fitness - old_fitness_remove) + child_fitness_in;
                    for (int j = MAX_POP_SIZE-1; j >= 0; j--) begin
                        if (j > insert_pos && j < population_size) begin
                            population[j] <= population[j-1];
                            fitness_values[j] <= fitness_values[j-1];
                        end
                    end
                    population[insert_pos] <= child_in;
                    fitness_values[insert_pos] <= child_fitness_in;
                end else begin
                    if (child_fitness_in > old_fitness_remove && population_size > 0) begin
                        internal_total_fitness <= (internal_total_fitness - old_fitness_remove) + child_fitness_in;
                        population[insert_pos] <= child_in;
                        fitness_values[insert_pos] <= child_fitness_in;
                    end
                end
                write_done <= 1'b1;
                writing <= 1'b0;
            end
            if (internal_total_fitness[FITNESS_WIDTH]) begin
                internal_total_fitness <= {1'b0, {FITNESS_WIDTH{1'b1}}};  
            end
        end
    end
endmodule