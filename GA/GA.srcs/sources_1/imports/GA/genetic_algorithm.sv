`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:
// Design Name: 
// Module Name: genetic_algorithm
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


module genetic_algorithm #(
    parameter CHROMOSOME_WIDTH = 8,
    parameter POPULATION_SIZE = 16,
    parameter MAX_GENERATIONS = 100,
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE),
    parameter FITNESS_WIDTH = 10,
    parameter MUTATION_RATE = 8'h10  // Low mutation rate (16/256)
)(
    input logic clk,
    input logic rst_n,
    input logic start_ga,
    input logic [CHROMOSOME_WIDTH-1:0] initial_population [POPULATION_SIZE-1:0],
    output logic [CHROMOSOME_WIDTH-1:0] best_chromosome,
    output logic [FITNESS_WIDTH-1:0] best_fitness,
    output logic ga_done
);
    // States for GA FSM
    typedef enum logic [3:0] {
        IDLE,
        INIT_POPULATION,
        EVALUATE_FITNESS,
        CALC_TOTAL_FITNESS,
        SELECT_PARENT1,
        SELECT_PARENT2,
        CROSSOVER,
        MUTATION,
        EVALUATE_CHILD,
        REPLACE_WORST,
        CHECK_TERMINATION,
        DONE
    } state_t;
    
    state_t state, next_state;
    
    // Counters and control signals
    logic [7:0] generation_count;
    logic [ADDR_WIDTH-1:0] individual_idx;
    logic [ADDR_WIDTH-1:0] worst_idx;
    logic [FITNESS_WIDTH-1:0] worst_fitness;
    
    // Population memory signals
    logic mem_write_enable;
    logic [ADDR_WIDTH-1:0] mem_write_addr;
    logic [ADDR_WIDTH-1:0] mem_read_addr;
    logic [CHROMOSOME_WIDTH-1:0] mem_write_data;
    logic [CHROMOSOME_WIDTH-1:0] mem_read_data;
    
    // Fitness storage
    logic [FITNESS_WIDTH-1:0] fitness_values [POPULATION_SIZE-1:0];
    logic [FITNESS_WIDTH-1:0] total_fitness;
    
    // Parent and child chromosomes
    logic [CHROMOSOME_WIDTH-1:0] parent1, parent2, child;
    logic [FITNESS_WIDTH-1:0] child_fitness;
    
    // Module control signals
    logic start_selection, selection_done;
    logic start_crossover, crossover_done;
    logic start_mutation, mutation_done;
    logic start_evaluation, evaluation_done;
    
    // Random number generation for mutation and crossover
    logic lfsr_enable;
    logic [CHROMOSOME_WIDTH-1:0] random_value;
    logic [2:0] crossover_point;
    
    // Instantiate LFSR
    lfsr_random #(
        .WIDTH(CHROMOSOME_WIDTH)
    ) lfsr_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(lfsr_enable),
        .random_out(random_value)
    );
    
    // Instantiate population memory
    population_memory #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE)
    ) pop_mem (
        .clk(clk),
        .rst_n(rst_n),
        .write_enable(mem_write_enable),
        .write_addr(mem_write_addr),
        .read_addr(mem_read_addr),
        .write_data(mem_write_data),
        .read_data(mem_read_data)
    );
    
    // Instantiate selection module
    logic [ADDR_WIDTH-1:0] selected_parent;
    
    selection #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE),
        .FITNESS_WIDTH(FITNESS_WIDTH)
    ) selection_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_selection(start_selection),
        .fitness_values(fitness_values),
        .total_fitness(total_fitness),
        .selected_parent(selected_parent),
        .selection_done(selection_done)
    );
    
    // Instantiate crossover module
    crossover #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH)
    ) crossover_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_crossover(start_crossover),
        .parent1(parent1),
        .parent2(parent2),
        .crossover_point(crossover_point),
        .child(child),
        .crossover_done(crossover_done)
    );
    
    // Instantiate mutation module
    logic [CHROMOSOME_WIDTH-1:0] mutated_child;
    
    mutation #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH)
    ) mutation_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_mutation(start_mutation),
        .child_in(child),
        .mutation_mask(random_value),
        .mutation_rate(MUTATION_RATE),
        .child_out(mutated_child),
        .mutation_done(mutation_done)
    );
    
    // Instantiate fitness evaluator
    fitness_evaluator #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH)
    ) fitness_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start_evaluation(start_evaluation),
        .chromosome(mem_read_data),
        .fitness(child_fitness),
        .evaluation_done(evaluation_done)
    );
    
    // Main FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            generation_count <= '0;
            individual_idx <= '0;
            best_chromosome <= '0;
            best_fitness <= '0;
            worst_idx <= '0;
            worst_fitness <= {FITNESS_WIDTH{1'b1}}; // Max value
            ga_done <= 1'b0;
            total_fitness <= '0;
            
            // Reset control signals
            start_selection <= 1'b0;
            start_crossover <= 1'b0;
            start_mutation <= 1'b0;
            start_evaluation <= 1'b0;
            mem_write_enable <= 1'b0;
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    generation_count <= '0;
                    individual_idx <= '0;
                    ga_done <= 1'b0;
                    total_fitness <= '0;
                end
                
                INIT_POPULATION: begin
                    // Load initial population from input
                    mem_write_enable <= 1'b1;
                    mem_write_addr <= individual_idx;
                    mem_write_data <= initial_population[individual_idx];
                    
                    if (individual_idx == POPULATION_SIZE-1) begin
                        individual_idx <= '0;
                    end else begin
                        individual_idx <= individual_idx + 1'b1;
                    end
                end
                
                EVALUATE_FITNESS: begin
                    mem_read_addr <= individual_idx;
                    start_evaluation <= 1'b1;
                    
                    if (evaluation_done) begin
                        start_evaluation <= 1'b0;
                        fitness_values[individual_idx] <= child_fitness;
                        
                        // Track best individual
                        if (child_fitness > best_fitness) begin
                            best_fitness <= child_fitness;
                            best_chromosome <= mem_read_data;
                        end
                        
                        // Track worst individual
                        if (child_fitness < worst_fitness) begin
                            worst_fitness <= child_fitness;
                            worst_idx <= individual_idx;
                        end
                        
                        if (individual_idx == POPULATION_SIZE-1) begin
                            individual_idx <= '0;
                        end else begin
                            individual_idx <= individual_idx + 1'b1;
                        end
                    end
                end
                
                CALC_TOTAL_FITNESS: begin
                    // Calculate total fitness for selection
                    total_fitness <= total_fitness + fitness_values[individual_idx];
                    
                    if (individual_idx == POPULATION_SIZE-1) begin
                        individual_idx <= '0;
                    end else begin
                        individual_idx <= individual_idx + 1'b1;
                    end
                end
                
                SELECT_PARENT1: begin
                    start_selection <= 1'b1;
                    
                    if (selection_done) begin
                        start_selection <= 1'b0;
                        mem_read_addr <= selected_parent;
                        parent1 <= mem_read_data;
                    end
                end
                
                SELECT_PARENT2: begin
                    start_selection <= 1'b1;
                    
                    if (selection_done) begin
                        start_selection <= 1'b0;
                        mem_read_addr <= selected_parent;
                        parent2 <= mem_read_data;
                    end
                end
                
                CROSSOVER: begin
                    lfsr_enable <= 1'b1; // Generate random crossover point
                    crossover_point <= random_value[2:0]; // Use 3 bits for crossover point
                    start_crossover <= 1'b1;
                    
                    if (crossover_done) begin
                        start_crossover <= 1'b0;
                        lfsr_enable <= 1'b0;
                    end
                end
                
                MUTATION: begin
                    lfsr_enable <= 1'b1; // Generate random mutation mask
                    start_mutation <= 1'b1;
                    
                    if (mutation_done) begin
                        start_mutation <= 1'b0;
                        lfsr_enable <= 1'b0;
                    end
                end
                
                EVALUATE_CHILD: begin
                    start_evaluation <= 1'b1;
                    
                    if (evaluation_done) begin
                        start_evaluation <= 1'b0;
                    end
                end
                
                REPLACE_WORST: begin
                    // Replace worst individual with new child if child is better
                    if (child_fitness > worst_fitness) begin
                        mem_write_enable <= 1'b1;
                        mem_write_addr <= worst_idx;
                        mem_write_data <= mutated_child;
                        fitness_values[worst_idx] <= child_fitness;
                        
                        // Update best if needed
                        if (child_fitness > best_fitness) begin
                            best_fitness <= child_fitness;
                            best_chromosome <= mutated_child;
                        end
                    end
                end
                
                CHECK_TERMINATION: begin
                    generation_count <= generation_count + 1'b1;
                    
                    // Reset for next generation
                    worst_fitness <= {FITNESS_WIDTH{1'b1}}; // Max value
                    mem_write_enable <= 1'b0;
                    total_fitness <= '0;
                end
                
                DONE: begin
                    ga_done <= 1'b1;
                end
            endcase
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (start_ga) begin
                    next_state = INIT_POPULATION;
                end
            end
            
            INIT_POPULATION: begin
                if (individual_idx == POPULATION_SIZE-1) begin
                    next_state = EVALUATE_FITNESS;
                end
            end
            
            EVALUATE_FITNESS: begin
                if (evaluation_done && individual_idx == POPULATION_SIZE-1) begin
                    next_state = CALC_TOTAL_FITNESS;
                end
            end
            
            CALC_TOTAL_FITNESS: begin
                if (individual_idx == POPULATION_SIZE-1) begin
                    next_state = SELECT_PARENT1;
                end
            end
            
            SELECT_PARENT1: begin
                if (selection_done) begin
                    next_state = SELECT_PARENT2;
                end
            end
            
            SELECT_PARENT2: begin
                if (selection_done) begin
                    next_state = CROSSOVER;
                end
            end
            
            CROSSOVER: begin
                if (crossover_done) begin
                    next_state = MUTATION;
                end
            end
            
            MUTATION: begin
                if (mutation_done) begin
                    next_state = EVALUATE_CHILD;
                end
            end
            
            EVALUATE_CHILD: begin
                if (evaluation_done) begin
                    next_state = REPLACE_WORST;
                end
            end
            
            REPLACE_WORST: begin
                next_state = CHECK_TERMINATION;
            end
            
            CHECK_TERMINATION: begin
                if (generation_count >= MAX_GENERATIONS) begin
                    next_state = DONE;
                end else begin
                    next_state = EVALUATE_FITNESS;
                end
            end
            
            DONE: begin
                if (!start_ga) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
endmodule