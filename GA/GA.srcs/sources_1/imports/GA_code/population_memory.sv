`timescale 1ns/1ps
/***************************************************************************************************
*  File Name   : population_memory.sv
*  Author      : Alireza Sotoodeh  (Optimized for Block RAM)
*  Instructor  : Dr. Ali Mahani
*  Date        : 2025-08
*  Module Type : Genetic Algorithm - Population Memory
*
*  Description:
*    Stores chromosomes and fitness values in sorted order using true Block RAM.
*    Insertion is performed in multi-cycle manner to allow BRAM-based shifting.
***************************************************************************************************/

(* keep_hierarchy = "yes" *)
module population_memory #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH    = 14,
    parameter MAX_POP_SIZE     = 100,
    parameter ADDR_WIDTH       = $clog2(MAX_POP_SIZE)
)(
    input  logic clk,
    input  logic rst,

    // Insert / Write signals
    input  logic start_write,
    input  logic [CHROMOSOME_WIDTH-1:0] child_in,
    input  logic [FITNESS_WIDTH-1:0]    child_fitness_in,

    // Parent read
    input  logic [ADDR_WIDTH-1:0] read_addr1,
    input  logic [ADDR_WIDTH-1:0] read_addr2,

    // Fitness requests
    input  logic request_fitness_values,
    input  logic request_total_fitness,
    input  logic [ADDR_WIDTH-1:0] population_size,

    output logic [CHROMOSOME_WIDTH-1:0] parent1_out,
    output logic [CHROMOSOME_WIDTH-1:0] parent2_out,
    output logic [FITNESS_WIDTH-1:0]    fitness_values_out [MAX_POP_SIZE-1:0],
    output logic [FITNESS_WIDTH-1:0]    total_fitness_out,
    output logic                        write_done
);

    // ===== Internal Block RAM storage =====
    (* ram_style = "block" *)logic [CHROMOSOME_WIDTH-1:0] population    [0:MAX_POP_SIZE-1];
    (* ram_style = "block" *)logic [FITNESS_WIDTH-1:0]    fitness_values[0:MAX_POP_SIZE-1];
    logic [FITNESS_WIDTH:0]      internal_total_fitness;

    // ===== Insert position search =====
    logic [ADDR_WIDTH-1:0] insert_pos;
    logic insert_found;
    logic [FITNESS_WIDTH-1:0] old_fitness_remove;

    always_comb begin
        // Read parents (Dual-port read possible)
        parent1_out = population[read_addr1];
        parent2_out = population[read_addr2];

        if (request_fitness_values)
            fitness_values_out = fitness_values;
        else
            fitness_values_out = '{default: '0};

        if (request_total_fitness)
            total_fitness_out = internal_total_fitness[FITNESS_WIDTH-1:0];
        else
            total_fitness_out = '0;

        insert_pos = population_size - 1;
        insert_found = 1'b0;
        old_fitness_remove = (population_size > 0) ? fitness_values[population_size-1] : '0;

        // Find position to insert
        for (int i = 0; i < MAX_POP_SIZE; i++) begin
            if (i < population_size && child_fitness_in > fitness_values[i]) begin
                insert_pos = i[ADDR_WIDTH-1:0];
                insert_found = 1'b1;
                break;
            end
        end
    end

    // ===== Multi-cycle shifter FSM =====
    typedef enum logic [1:0] {IDLE, SHIFT, INSERT, DONE} state_t;
    state_t state;
    logic [ADDR_WIDTH-1:0] shift_index;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            write_done <= 1'b0;
            internal_total_fitness <= '0;
            for (int i=0; i<MAX_POP_SIZE; i++) begin
                population[i] <= '0;
                fitness_values[i] <= '0;
            end
        end else begin
            write_done <= 1'b0;
            case (state)
                IDLE: begin
                    if (start_write) begin
                        if (insert_found || (child_fitness_in > old_fitness_remove && population_size > 0)) begin
                            shift_index <= population_size - 1;
                            state <= SHIFT;
                        end else begin
                            // no insert, just done
                            write_done <= 1'b1;
                        end
                    end
                end

                SHIFT: begin
                    if (shift_index > insert_pos) begin
                        population[shift_index] <= population[shift_index-1];
                        fitness_values[shift_index] <= fitness_values[shift_index-1];
                        shift_index <= shift_index - 1;
                    end else begin
                        state <= INSERT;
                    end
                end

                INSERT: begin
                    population[insert_pos] <= child_in;
                    fitness_values[insert_pos] <= child_fitness_in;
                    internal_total_fitness <= (internal_total_fitness - old_fitness_remove) + child_fitness_in;
                    state <= DONE;
                end

                DONE: begin
                    write_done <= 1'b1;
                    state <= IDLE;
                end
            endcase

            // Prevent overflow
            if (internal_total_fitness[FITNESS_WIDTH])
                internal_total_fitness <= {1'b0, {FITNESS_WIDTH{1'b1}}};
        end
    end

endmodule
