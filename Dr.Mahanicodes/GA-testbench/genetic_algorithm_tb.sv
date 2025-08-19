`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:
// Design Name: 
// Module Name: genetic_algorithm_tb
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


module genetic_algorithm_tb;
    // Parameters
    parameter CHROMOSOME_WIDTH = 8;
    parameter POPULATION_SIZE = 16;
    parameter MAX_GENERATIONS = 100;
    parameter FITNESS_WIDTH = 10;
    
    // Signals
    logic clk;
    logic rst_n;
    logic start_ga;
    logic [CHROMOSOME_WIDTH-1:0] initial_population [POPULATION_SIZE-1:0];
    logic [CHROMOSOME_WIDTH-1:0] best_chromosome;
    logic [FITNESS_WIDTH-1:0] best_fitness;
    logic ga_done;
    
    // Instantiate GA module
    genetic_algorithm #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE),
        .MAX_GENERATIONS(MAX_GENERATIONS),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .MUTATION_RATE(8'h10)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_ga(start_ga),
        .initial_population(initial_population),
        .best_chromosome(best_chromosome),
        .best_fitness(best_fitness),
        .ga_done(ga_done)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test sequence
    initial begin
        // Initialize signals
        rst_n = 0;
        start_ga = 0;
        
        // Initialize population with random values
        for (int i = 0; i < POPULATION_SIZE; i++) begin
            initial_population[i] = $random;
        end
        
        // Reset release
        #20 rst_n = 1;
        
        // Start GA
        #10 start_ga = 1;
        
        // Wait for GA to complete
        @(posedge ga_done);
        
        // Display results
        $display("GA completed!");
        $display("Best chromosome: %h", best_chromosome);
        $display("Best fitness: %d", best_fitness);
        
        // End simulation
        #100 $finish;
    end
    
    // Monitor progress
    always @(posedge clk) begin
        if (ga_done) begin
            $display("Best chromosome: %h, Fitness: %d", best_chromosome, best_fitness);
        end
    end
endmodule