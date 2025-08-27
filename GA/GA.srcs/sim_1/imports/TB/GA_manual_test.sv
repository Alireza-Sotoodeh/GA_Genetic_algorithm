`timescale 1ns/1ps
module GA_top_manual_tb;

    reg clk;
    reg rst;
    reg start_ga;
    reg load_initial_population;
    reg [15:0] data_in;
    reg [1:0] crossover_mode;
    reg crossover_single_double;
    reg [$clog2(16):0] crossover_single_point;
    reg [$clog2(16):0] crossover_double_point1;
    reg [$clog2(16):0] crossover_double_point2;
    reg [15:0] uniform_crossover_mask;
    reg uniform_random_enable;
    reg [2:0] mutation_mode;
    reg [7:0] mutation_rate;
    reg [31:0] target_iteration;

    wire busy;
    wire done;
    wire perfect_found;
    wire [15:0] best_chromosome;
    wire [13:0] best_fitness;
    wire [31:0] iteration_count;
    wire [31:0] crossovers_to_perfect;
    wire [15:0] data_out;
    wire [3:0]  number_of_chromosomes;

    wire [1:0] state, next_state;
    wire [2:0] pipeline_state, next_pipeline_state;
    wire start_select, select_done;
    wire start_cross, cross_done;
    wire start_mutate, mutate_done;
    wire start_eval_init, start_eval_pipe, eval_done;
    wire start_pop_write, pop_write_done;
    wire req_fitness, req_total_fitness;
    wire [3:0] p_selected_idx1, p_selected_idx2;
    wire [15:0] p_parent1, p_parent2;
    wire [15:0] p_child_crossed, p_child_mutated;
    wire [13:0] p_child_fitness;
    wire [15:0] init_chromosome_in;
    wire [15:0] pop_mem_parent1_out, pop_mem_parent2_out;
    wire [13:0] pop_mem_fitness_values_out [15:0];
    wire [13:0] pop_mem_total_fitness_out;
    wire start_lfsrs;
    wire [15:0] rand_sel, rand_cross, rand_mut;
    wire [3:0] init_counter;
    wire [31:0] perfect_counter_reg;
    wire perfect_found_latch;
    wire eval_init_pending, eval_pipe_pending;

    // ==== DUT ====
    ga_top dut (
        .clk(clk),
        .rst(rst),
        .start_ga(start_ga),
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
        .perfect_found(perfect_found),
        .best_chromosome(best_chromosome),
        .best_fitness(best_fitness),
        .iteration_count(iteration_count),
        .crossovers_to_perfect(crossovers_to_perfect),
        .data_out(data_out),
        .number_of_chromosomes(number_of_chromosomes)
    );
    
    // Example: tie TB wires to internal DUT signals
    assign state                   = GA_top_manual_tb.dut.state;
    assign next_state              = GA_top_manual_tb.dut.next_state;
    assign pipeline_state          = GA_top_manual_tb.dut.pipeline_state;
    assign next_pipeline_state     = GA_top_manual_tb.dut.next_pipeline_state;
    assign start_select            = GA_top_manual_tb.dut.start_select;
    assign select_done             = GA_top_manual_tb.dut.select_done;
    assign start_cross             = GA_top_manual_tb.dut.start_cross;
    assign cross_done              = GA_top_manual_tb.dut.cross_done;
    assign start_mutate            = GA_top_manual_tb.dut.start_mutate;
    assign mutate_done             = GA_top_manual_tb.dut.mutate_done;
    assign start_eval_init         = GA_top_manual_tb.dut.start_eval_init;
    assign start_eval_pipe         = GA_top_manual_tb.dut.start_eval_pipe;
    assign eval_done               = GA_top_manual_tb.dut.eval_done;
    assign start_pop_write         = GA_top_manual_tb.dut.start_pop_write;
    assign pop_write_done          = GA_top_manual_tb.dut.pop_write_done;
    assign req_fitness             = GA_top_manual_tb.dut.req_fitness;
    assign req_total_fitness       = GA_top_manual_tb.dut.req_total_fitness;
    assign p_selected_idx1         = GA_top_manual_tb.dut.p_selected_idx1;
    assign p_selected_idx2         = GA_top_manual_tb.dut.p_selected_idx2;
    assign p_parent1               = GA_top_manual_tb.dut.p_parent1;
    assign p_parent2               = GA_top_manual_tb.dut.p_parent2;
    assign p_child_crossed         = GA_top_manual_tb.dut.p_child_crossed;
    assign p_child_mutated         = GA_top_manual_tb.dut.p_child_mutated;
    assign p_child_fitness         = GA_top_manual_tb.dut.p_child_fitness;
    assign init_chromosome_in      = GA_top_manual_tb.dut.init_chromosome_in;
    assign pop_mem_parent1_out     = GA_top_manual_tb.dut.pop_mem_parent1_out;
    assign pop_mem_parent2_out     = GA_top_manual_tb.dut.pop_mem_parent2_out;
    assign pop_mem_fitness_values_out = GA_top_manual_tb.dut.pop_mem_fitness_values_out;
    assign pop_mem_total_fitness_out  = GA_top_manual_tb.dut.pop_mem_total_fitness_out;
    assign start_lfsrs             = GA_top_manual_tb.dut.start_lfsrs;
    assign rand_sel                = GA_top_manual_tb.dut.rand_sel;
    assign rand_cross              = GA_top_manual_tb.dut.rand_cross;
    assign rand_mut                = GA_top_manual_tb.dut.rand_mut;
    assign init_counter            = GA_top_manual_tb.dut.init_counter;
    assign perfect_counter_reg     = GA_top_manual_tb.dut.perfect_counter_reg;
    assign perfect_found_latch     = GA_top_manual_tb.dut.perfect_found_latch;
    assign eval_init_pending       = GA_top_manual_tb.dut.eval_init_pending;
    assign eval_pipe_pending       = GA_top_manual_tb.dut.eval_pipe_pending;
    

//```````````````````````````````````````````````````````````````````````````
    initial begin
        clk = 0;
        forever #50 clk = ~clk;
    end
//```````````````````````````````````````````````````````````````````````````

    initial begin
        rst = 1;
        start_ga = 0;
        load_initial_population = 0;
        data_in = 0;
        crossover_mode = 2'b00;
        crossover_single_double = 1'b0;
        crossover_single_point = 8;
        crossover_double_point1 = 0;
        crossover_double_point2 = 0;
        uniform_crossover_mask = 16'h0000;
        uniform_random_enable = 1;
        mutation_mode = 3'b000;
        mutation_rate = 64;
        target_iteration = 10000;
        
        @(negedge clk)
        rst = 0;
        start_ga = 1;
        load_initial_population = 1;
        data_in = 4'h0001;
        @(next_pipeline_state!=00);
        load_initial_population = 0;
        data_in = 4'h0000;
    end
    

// Clock cycle counter for logging
integer clk_counter;
initial clk_counter = 0;
always @(posedge clk) clk_counter <= clk_counter + 1;

integer log_file;
integer i;

initial begin
    log_file = $fopen("manual_test_ga.csv", "w");
    if (log_file == 0) begin
        $display("Error opening log file!");
        $finish;
    end

    // ---------- Header (This part was already correct) ----------
    $fwrite(log_file, "clk (Clock), clk_counter (Cycle), rst, start_ga, load_initial_population, data_in, ");
    $fwrite(log_file, "target_iteration, busy, done, perfect_found, best_chromosome, best_fitness, iteration_count, crossovers_to_perfect, data_out, ");
    $fwrite(log_file, "number_of_chromosomes, state, next_state, pipeline_state, next_pipeline_state, ");
    $fwrite(log_file, "start_select, select_done, start_cross, cross_done, start_mutate, mutate_done, start_eval_init, start_eval_pipe, eval_done, ");
    $fwrite(log_file, "start_pop_write, pop_write_done, req_fitness, req_total_fitness, ");
    $fwrite(log_file, "p_selected_idx1, p_selected_idx2, p_parent1, p_parent2, p_child_crossed, p_child_mutated, p_child_fitness, ");
    $fwrite(log_file, "pop_mem_parent1_out, pop_mem_parent2_out, ");
    for (i = 0; i < 16; i = i + 1)
        $fwrite(log_file, "pop_mem_fitness_values_out[%0d], ", i);
    $fwrite(log_file, "pop_mem_total_fitness_out, start_lfsrs, rand_sel, rand_cross, rand_mut, ");
    $fwrite(log_file, "init_counter, perfect_counter_reg, perfect_found_latch, eval_init_pending, eval_pipe_pending, init_chromosome_in");
    $fdisplay(log_file, "");
end

// ---------- Data Logging (With the fix applied) ----------
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

    // Remaining signals (last field has no trailing comma)
    $fwrite(log_file, "%0d,%b,%h,%h,%h,%0d,%0d,%b,%b,%b,%h",
        pop_mem_total_fitness_out, start_lfsrs, rand_sel, rand_cross, rand_mut,
        init_counter, perfect_counter_reg, perfect_found_latch, eval_init_pending, eval_pipe_pending, init_chromosome_in);

    $fdisplay(log_file, ""); // End of line
end

// ---------- Close file ----------
always @(posedge clk) begin
    if (done) begin
        $display("** GA Done at t=%0t, iterations=%0d, best=0x%0h fitness=%0d",
                 $time, iteration_count, best_chromosome, best_fitness);
        #100 $finish;
        $stop;
    end
end

final begin
$fclose(log_file); end
    
endmodule

