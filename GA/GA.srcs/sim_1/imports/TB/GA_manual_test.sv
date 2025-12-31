`timescale 1ns/1ps
module GA_top_manual_tb;

  
    // ============================================================
    //  Parameters (Easily adjustable for different population sizes)
    // ============================================================
    parameter int POPULATION_SIZE_TB    = 100;                 // Testbench population size (editable)
    localparam CHROMOSOME_WIDTH_TB      = 16;                // Chromosome bit width
    localparam FITNESS_WIDTH_TB         = 14;                // Fitness bit width
    localparam ADDR_WIDTH_TB            = $clog2(POPULATION_SIZE_TB); // Address width for population arrays
    
    // ============================================================
    //  DUT I/O Signals
    // ============================================================
    reg clk;
    reg rst;
    reg start_ga;
    reg [ADDR_WIDTH_TB-1:0] population_size;
    reg load_initial_population;
    reg [CHROMOSOME_WIDTH_TB-1:0] data_in;

    // Crossover configuration
    reg [1:0]  crossover_mode;
    reg        crossover_single_double;
    reg [$clog2(CHROMOSOME_WIDTH_TB):0] crossover_single_point;
    reg [$clog2(CHROMOSOME_WIDTH_TB):0] crossover_double_point1;
    reg [$clog2(CHROMOSOME_WIDTH_TB):0] crossover_double_point2;
    reg [15:0] uniform_crossover_mask;
    reg        uniform_random_enable;

    // Mutation configuration
    reg [2:0]  mutation_mode;
    reg [7:0]  mutation_rate;

    // Iteration target
    reg [31:0] target_iteration;

    // DUT outputs
    wire busy;
    wire done;
    wire perfect_found;
    wire [CHROMOSOME_WIDTH_TB-1:0] best_chromosome;
    wire [FITNESS_WIDTH_TB-1:0]    best_fitness;
    wire [31:0]                    iteration_count;
    wire                           load_data_now;
    wire [31:0]                    crossovers_to_perfect;
    wire [CHROMOSOME_WIDTH_TB-1:0] data_out;
    wire [ADDR_WIDTH_TB-1:0]       number_of_chromosomes;

    // Internal signals for debugging/logging
    wire [1:0]  state, next_state;
    wire [2:0]  pipeline_state, next_pipeline_state;
    wire start_select, select_done;
    wire start_cross,  cross_done;
    wire start_mutate, mutate_done;
    wire start_eval_init, start_eval_pipe, eval_done;
    wire start_pop_write, pop_write_done;
    wire req_fitness, req_total_fitness;
    wire [ADDR_WIDTH_TB-1:0] p_selected_idx1, p_selected_idx2;
    wire [CHROMOSOME_WIDTH_TB-1:0] p_parent1, p_parent2;
    wire [CHROMOSOME_WIDTH_TB-1:0] p_child_crossed, p_child_mutated;
    wire [FITNESS_WIDTH_TB-1:0]    p_child_fitness;
    wire [CHROMOSOME_WIDTH_TB-1:0] init_chromosome_in;
    wire [CHROMOSOME_WIDTH_TB-1:0] pop_mem_parent1_out, pop_mem_parent2_out;
    wire [FITNESS_WIDTH_TB-1:0]    pop_mem_fitness_values_out [POPULATION_SIZE_TB-1:0];
    wire [FITNESS_WIDTH_TB-1:0]    pop_mem_total_fitness_out;
    wire start_lfsrs;
    wire [CHROMOSOME_WIDTH_TB-1:0] rand_sel, rand_cross, rand_mut;
    wire [ADDR_WIDTH_TB-1:0] init_counter;
    wire [31:0] perfect_counter_reg;
    wire perfect_found_latch;
    wire eval_init_pending, eval_pipe_pending;
    wire [CHROMOSOME_WIDTH_TB-1:0] pop_mem_chromosomes [POPULATION_SIZE_TB-1:0];
    wire [CHROMOSOME_WIDTH_TB-1:0] child_in_memory;
    wire start_write_memory;
    
    
    // ============================================================
    //  DUT Instance
    // ============================================================
    ga_top dut (
        .clk(clk),
        .rst(rst),
        .start_ga(start_ga),
        .population_size(population_size),
        .load_initial_population(load_initial_population),
        .data_in(data_in),
        .crossover_mode(crossover_mode),
        .crossover_single_double(crossover_single_double),
        .crossover_single_point(crossover_single_point),
        .crossover_double_point1(crossover_double_point1),
        .crossover_double_point2(crossover_double_point2),
        .uniform_crossover_mask(uniform_crossover_mask),
        .uniform_random_enable(uniform_random_enable),
        .mutation_mode(mutation_mode),
        .mutation_rate(mutation_rate),
        .target_iteration(target_iteration),
        .busy(busy),
        .done(done),
        .load_data_now(load_data_now),
        .perfect_found(perfect_found),
        .best_chromosome(best_chromosome),
        .best_fitness(best_fitness),
        .iteration_count(iteration_count),
        .crossovers_to_perfect(crossovers_to_perfect),
        .data_out(data_out),
        .number_of_chromosomes(number_of_chromosomes)
    );
    
    // ============================================================
    //  Expose internal DUT signals for waveform & logging
    // ============================================================
    assign state                       = dut.state;
    assign next_state                  = dut.next_state;
    assign pipeline_state              = dut.pipeline_state;
    assign next_pipeline_state         = dut.next_pipeline_state;

    assign start_select = dut.start_select;
    assign select_done  = dut.select_done;
    assign start_cross  = dut.start_cross;
    assign cross_done   = dut.cross_done;
    assign start_mutate = dut.start_mutate;
    assign mutate_done  = dut.mutate_done;

    assign start_eval_init = dut.start_eval_init;
    assign start_eval_pipe = dut.start_eval_pipe;
    assign eval_done       = dut.eval_done;

    assign start_pop_write = dut.start_pop_write;
    assign pop_write_done  = dut.pop_write_done;

    assign req_fitness      = dut.req_fitness;
    assign req_total_fitness= dut.req_total_fitness;

    assign p_selected_idx1 = dut.p_selected_idx1;
    assign p_selected_idx2 = dut.p_selected_idx2;
    assign p_parent1       = dut.p_parent1;
    assign p_parent2       = dut.p_parent2;

    assign p_child_crossed = dut.p_child_crossed;
    assign p_child_mutated = dut.p_child_mutated;
    assign p_child_fitness = dut.p_child_fitness;

    assign init_chromosome_in  = dut.init_chromosome_in;
    assign pop_mem_parent1_out = dut.pop_mem_parent1_out;
    assign pop_mem_parent2_out = dut.pop_mem_parent2_out;

    assign pop_mem_fitness_values_out = dut.pop_mem_fitness_values_out;
    assign pop_mem_total_fitness_out  = dut.pop_mem_total_fitness_out;

    assign start_lfsrs = dut.start_lfsrs;
    assign rand_sel    = dut.rand_sel;
    assign rand_cross  = dut.rand_cross;
    assign rand_mut    = dut.rand_mut;

    assign init_counter         = dut.init_counter;
    assign perfect_counter_reg  = dut.perfect_counter_reg;
    assign perfect_found_latch  = dut.perfect_found_latch;
    assign eval_init_pending    = dut.eval_init_pending;
    assign eval_pipe_pending    = dut.eval_pipe_pending;

    assign pop_mem_chromosomes  = dut.pop_mem_inst.population;
    assign child_in_memory      = dut.pop_mem_inst.child_in;
    assign start_write_memory   = dut.pop_mem_inst.start_write;
    // ============================================================
    //  Clock Generator (100 MHz => period = 10 ns)
    // ============================================================
    initial begin
        clk = 0;
        forever #50 clk = ~clk; // 20 MHz in this case (50ns half-period)
    end

    // ============================================================
    //  Initial Population Seed Values
    // ============================================================
        logic [15:0] allowed_vals [0:5] = {
            16'h0300,
            16'h0101,
            16'h0010,
            16'h2001,
            16'h0003,
            16'h3004
        };
        int idx = 0;

    // ============================================================
    //  Main Test Sequence
    // ============================================================
    initial begin
        // reset and initialization
        rst = 1;
        start_ga = 0;
        load_initial_population = 0;
        data_in = 0;
        population_size = 10;
        // GA control settings
        crossover_mode = 2'b01;
        crossover_single_double = 1'b1;
        crossover_single_point = 8;
        crossover_double_point1 = 0;
        crossover_double_point2 = 0;
        uniform_crossover_mask = 16'h0000;
        uniform_random_enable = 1;
        mutation_mode = 3'b000;
        mutation_rate = 64;
        target_iteration = 10000;
        // Release reset and start GA 
        @(negedge clk)  
        rst = 0;
        start_ga = 1;
        load_initial_population = 1;
        data_in = 4'h0001; //first data in
        // Load initial population one chromosome per handshake
        for (int i = 0; i < population_size; i++) begin
        @(posedge load_data_now); // Wait for GA to signal readiness
        @(negedge clk); // Synchronize data_in update with clock
        idx = $urandom_range(5, 0);
        data_in = allowed_vals[idx]; // Set the seeded chromosome16'h0001;
    end
    @(negedge clk);
    // Done loading
    load_initial_population = 0;
    end
    
    // ============================================================
    //  Clock Counter for Simulation
    // ============================================================
    integer clk_counter;
    initial clk_counter = 0;
    always @(posedge clk) clk_counter <= clk_counter + 1;
 
    // ============================================================
    //  CSV Logger 
    // ============================================================
    integer log_file;
    integer i;
    initial begin
        log_file = $fopen("manual_test_ga.csv", "w");
        if (log_file == 0) begin
            $display("Error opening log file!");
            $finish;
        end
    
        // ---------- Header (Updated to include child_in_memory and start_write_memory) ----------
        $fwrite(log_file, "clk (Clock), clk_counter (Cycle), rst, start_ga, load_initial_population, data_in, ");
        $fwrite(log_file, "target_iteration, busy, done, perfect_found, best_chromosome, best_fitness, iteration_count, crossovers_to_perfect, data_out, ");
        $fwrite(log_file, "number_of_chromosomes, state, next_state, pipeline_state, next_pipeline_state, ");
        $fwrite(log_file, "start_select, select_done, start_cross, cross_done, start_mutate, mutate_done, start_eval_init, start_eval_pipe, eval_done, ");
        $fwrite(log_file, "start_pop_write, pop_write_done, req_fitness, req_total_fitness, ");
        $fwrite(log_file, "p_selected_idx1, p_selected_idx2, p_parent1, p_parent2, p_child_crossed, p_child_mutated, p_child_fitness, ");
        $fwrite(log_file, "pop_mem_parent1_out, pop_mem_parent2_out, ");
        for (i = 0; i < 16; i = i + 1)
            $fwrite(log_file, "pop_mem_fitness_values_out[%0d], ", i);
        // Headers for population chromosomes (from previous change)
        for (i = 0; i < 16; i = i + 1)
            $fwrite(log_file, "pop_mem_chromosomes[%0d], ", i);
        // New: Add headers for child_in_memory and start_write_memory
        $fwrite(log_file, "child_in_memory, start_write_memory, ");
        $fwrite(log_file, "pop_mem_total_fitness_out, start_lfsrs, rand_sel, rand_cross, rand_mut, ");
        $fwrite(log_file, "init_counter, perfect_counter_reg, perfect_found_latch, eval_init_pending, eval_pipe_pending, init_chromosome_in");
        $fdisplay(log_file, "");
    end
    
    // ---------- Data Logging (Updated to include child_in_memory and start_write_memory) ----------
    always @(posedge clk) begin
        // First group
        $fwrite(log_file, "%b,%0d,%b,%b,%b,%h,", clk, clk_counter, rst, start_ga, load_initial_population, data_in);
        $fwrite(log_file, "%0d,%b,%b,%b,%h,%0d,%0d,%0d,%h,", target_iteration, busy, done, perfect_found, best_chromosome, best_fitness, iteration_count, crossovers_to_perfect, data_out);
    
        // CORRECTED LINE: Added one more %b at the end for req_total_fitness
        $fwrite(log_file, "%0d,%0d,%0d,%0d,%0d,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,",
            number_of_chromosomes, state, next_state, pipeline_state, next_pipeline_state,
            start_select, select_done, start_cross, cross_done, start_mutate, mutate_done,
            start_eval_init, start_eval_pipe, eval_done, start_pop_write, pop_write_done,
            req_fitness, req_total_fitness);
    
        // Parent and child info
        $fwrite(log_file, "%0d,%0d,%h,%h,%h,%h,%0d,%h,%h,",
            p_selected_idx1, p_selected_idx2,
            p_parent1, p_parent2, p_child_crossed, p_child_mutated, p_child_fitness,
            pop_mem_parent1_out, pop_mem_parent2_out);
    
        // Fitness values
        for (i = 0; i < 16; i = i + 1) begin
            $fwrite(log_file, "%0d,", pop_mem_fitness_values_out[i]);
        end
    
        // Log population chromosomes (from previous change)
        for (i = 0; i < 16; i = i + 1) begin
            $fwrite(log_file, "%h,", pop_mem_chromosomes[i]);
        end
    
        // New: Log child_in_memory (hex) and start_write_memory (binary)
        $fwrite(log_file, "%h,%b,", child_in_memory, start_write_memory);
    
        // Remaining signals (last field has no trailing comma)
        $fwrite(log_file, "%0d,%b,%h,%h,%h,%0d,%0d,%b,%b,%b,%h",
            pop_mem_total_fitness_out, start_lfsrs, rand_sel, rand_cross, rand_mut,
            init_counter, perfect_counter_reg, perfect_found_latch, eval_init_pending, eval_pipe_pending, init_chromosome_in);
    
        $fdisplay(log_file, ""); // End of line
    end
    
    
    
    // ============================================================
    //  Stop Simulation When Perfect Solution Found
    // ============================================================
    always @(posedge clk) begin
        if (perfect_found) begin
            $display("** GA found perfect at t=%0t, iterations=%0d, best=0x%0h fitness=%0d",
                     $time, iteration_count, best_chromosome, best_fitness);
            repeat(2)@(posedge clk)$stop;
        end
    end
    
    // ============================================================
    //  Close log file at simulation end
    // ============================================================
    final $fclose(log_file); 
    
endmodule
    
