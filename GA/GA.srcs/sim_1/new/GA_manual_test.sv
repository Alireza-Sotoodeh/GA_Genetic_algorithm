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
    
    //show enum in testbench 
    typedef GA_top_manual_tb.dut.state_t          state_t;
    typedef GA_top_manual_tb.dut.pipeline_state_t pipeline_state_t;
        state_t tb_state;
        state_t tb_next_state;
        pipeline_state_t tb_pipeline_state;
        pipeline_state_t tb_next_pipeline_state;
        
    // Example: tie TB wires to internal DUT signals
    assign tb_state              = dut.state;
    assign tb_next_state         = dut.next_state;
    assign tb_pipeline_state     = dut.pipeline_state;
    assign tb_next_pipeline_state= dut.next_pipeline_state;
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
    integer i;
reg [15:0] init_data [0:16]; 

initial begin
    init_data[0]  = 16'b0000000000000001; // 0x0001
    init_data[1]  = 16'b0000100000000010; // 0x0802
    init_data[2]  = 16'b0000000000000100; // 0x0004
    init_data[3]  = 16'b0000000000001000; // 0x0008
    init_data[4]  = 16'b1000000000100001; // 0x8021
    init_data[5]  = 16'b0000000000000000; // 0x0000
    init_data[6]  = 16'b0000000000000100; // 0x0004
    init_data[7]  = 16'b0000000000001000; // 0x0008
    init_data[8]  = 16'b0001000000000001; // 0x1001
    init_data[9]  = 16'b0000000000000010; // 0x0002
    init_data[10] = 16'b0000010000000100; // 0x0404
    init_data[11] = 16'b0000000000001000; // 0x0008
    init_data[12] = 16'b0001000010000001; // 0x1081
    init_data[13] = 16'b0000000001000010; // 0x0042
    init_data[14] = 16'b0010000000000100; // 0x2004
    init_data[15] = 16'b0000010000001000; // 0x0408
    // Wait until reset is released
    @(negedge rst);

    // Load each chromosome, one per clock cycle
    for (i = 0; i < 16; i = i + 1) begin
        @(posedge clk);
        data_in = init_data[i];
        load_initial_population = 1'b1;
        @(posedge clk);
        load_initial_population = 1'b0;
        @(negedge eval_init_pending);
    end
end
//```````````````````````````````````````````````````````````````````````````
    initial begin
        rst = 1;
        start_ga = 0;
        load_initial_population = 0;
        data_in = 0;
        crossover_mode = 2'b00;
        crossover_single_double = 1'b0;
        crossover_single_point = 4'b1000;
        crossover_double_point1 = 0;
        crossover_double_point2 = 0;
        uniform_crossover_mask = 16'h0000;
        uniform_random_enable = 0;
        mutation_mode = 3'b000;
        mutation_rate = 64;
        target_iteration = 300;
        #100;
        rst = 0;
        start_ga = 1;

    end
endmodule
