module ga_top #(
    // General GA Parameters
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14,
    parameter POPULATION_SIZE = 16,

    // Derived Parameters
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE),
    parameter LFSR_WIDTH = 16
)(
    //''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Control & Clocking
    input  logic                                clk,
    input  logic                                rst,
    input  logic                                start_ga,
    // Initial Population Seeding (Optional)
    input  logic                                load_initial_population, // Pulse to load one seed chromosome
    input  logic [CHROMOSOME_WIDTH-1:0]         data_in,                 // The seed chromosome to load

    // Crossover Parameters
    input  logic [1:0]                          crossover_mode,
    input  logic                                crossover_single_double,
    input  logic [ADDR_WIDTH-1:0]               crossover_single_point,
    input  logic [ADDR_WIDTH-1:0]               crossover_double_point1,
    input  logic [ADDR_WIDTH-1:0]               crossover_double_point2,
    input  logic [CHROMOSOME_WIDTH-1:0]         uniform_crossover_mask,
    input  logic                                uniform_random_enable,

    // Mutation Parameters
    input  logic [2:0]                          mutation_mode,
    input  logic [7:0]                          mutation_rate,

    // Termination Condition
    input  logic [31:0]                         target_iteration, // How many generations to run

    //''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Status & Results Outputs
    output logic                                busy,                   // GA is currently running
    output logic                                done,                   // GA has finished
    output logic                                perfect_found,          // Flag for when the perfect chromosome is found
    output logic [CHROMOSOME_WIDTH-1:0]         best_chromosome,        // The best chromosome from the population
    output logic [FITNESS_WIDTH-1:0]            best_fitness,           // Fitness of the best chromosome
    output logic [31:0]                         iteration_count,        // Current generation number
    output logic [31:0]                         crossovers_to_perfect,  // Generations it took to find the perfect solution
    // Legacy outputs from original request
    output logic [CHROMOSOME_WIDTH-1:0]         data_out,
    output logic [ADDR_WIDTH-1:0]               number_of_chromosomes
);

//======================================================================
// State Machine Definitions
//======================================================================
    // Main FSM States
    localparam [1:0] S_IDLE = 2'b00,
                     S_INIT = 2'b01,
                     S_RUNNING = 2'b10,
                     S_DONE = 2'b11;
    logic [1:0] state, next_state;

    // Pipeline FSM States (controls the main GA loop)
    localparam [2:0] P_IDLE = 3'b000,
                     P_SELECT = 3'b001,
                     P_CROSSOVER = 3'b010,
                     P_MUTATION = 3'b011,
                     P_EVALUATE = 3'b100,
                     P_UPDATE = 3'b101;
    logic [2:0] pipeline_state, next_pipeline_state;

//======================================================================
// Internal Wires & Registers
//======================================================================
    // Handshake signals for all modules
    logic start_select, select_done;
    logic start_cross, cross_done;
    logic start_mutate, mutate_done;
    logic start_eval_init, start_eval_pipe, eval_done;
    logic start_pop_write, pop_write_done;
    logic req_fitness, req_total_fitness;

    // Data paths between pipeline stages
    logic [ADDR_WIDTH-1:0]      p_selected_idx1, p_selected_idx2;
    logic [CHROMOSOME_WIDTH-1:0] p_parent1, p_parent2;
    logic [CHROMOSOME_WIDTH-1:0] p_child_crossed, p_child_mutated;
    logic [FITNESS_WIDTH-1:0]    p_child_fitness;
    logic [CHROMOSOME_WIDTH-1:0] init_chromosome_in;
    logic [FITNESS_WIDTH-1:0]    init_fitness_in; // needs proper assignment

    // Population Memory connections - Fixed signal widths
    logic [CHROMOSOME_WIDTH-1:0] pop_mem_parent1_out, pop_mem_parent2_out;
    logic [FITNESS_WIDTH-1:0]    pop_mem_fitness_values_out [POPULATION_SIZE-1:0];
    logic [FITNESS_WIDTH-1:0]    pop_mem_total_fitness_out; // Corrected width to FITNESS_WIDTH

    // LFSR connections
    logic start_lfsrs;
    logic [LFSR_WIDTH-1:0] rand_sel, rand_cross, rand_mut;

    // Counters and control flags
    logic [ADDR_WIDTH-1:0] init_counter;
    logic [31:0]           perfect_counter_reg;
    logic                  perfect_found_latch;

    // Pipeline control registers - Added for proper synchronization
    logic                  eval_init_pending, eval_pipe_pending;
    logic                  selection_valid, crossover_valid, mutation_valid;

//======================================================================
// Module Instantiations
//======================================================================
    // Three independent LFSRs for Selection, Crossover, and Mutation
    lfsr_SudoRandom #(
        .WIDTH1(LFSR_WIDTH), .defualtSeed1(16'hACE1)
    ) lfsr_sel_inst (
        .clk(clk), .rst(rst), .start_lfsr(start_lfsrs),
        .load_seed(1'b0), .seed_in('0), .random_out(rand_sel)
    );

    lfsr_SudoRandom #(
        .WIDTH1(LFSR_WIDTH), .defualtSeed1(16'hBEEF)
    ) lfsr_cross_inst (
        .clk(clk), .rst(rst), .start_lfsr(start_lfsrs),
        .load_seed(1'b0), .seed_in('0), .random_out(rand_cross)
    );

    lfsr_SudoRandom #(
        .WIDTH1(LFSR_WIDTH), .defualtSeed1(16'hDEAD)
    ) lfsr_mut_inst (
        .clk(clk), .rst(rst), .start_lfsr(start_lfsrs),
        .load_seed(1'b0), .seed_in('0), .random_out(rand_mut)
    );

    // --- GA Core Modules ---
    selection #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE),
        .LFSR_WIDTH(LFSR_WIDTH)
    ) sel_inst (
        .clk(clk),
        .rst(rst),
        .start_selection(start_select),
        .fitness_values(pop_mem_fitness_values_out),
        .total_fitness(pop_mem_total_fitness_out), // Correct width now
        .lfsr_input(rand_sel),
        .selected_index1(p_selected_idx1),
        .selected_index2(p_selected_idx2),
        .selection_done(select_done)
    );

    crossover #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .LSFR_WIDTH(LFSR_WIDTH)
    ) cross_inst (
        .clk(clk),
        .rst(rst),
        .start_crossover(start_cross),
        .parent1(p_parent1),
        .parent2(p_parent2),
        .crossover_mode(crossover_mode),
        .crossover_single_double(crossover_single_double),
        .crossover_Single_point(crossover_single_point),
        .crossover_double_point1(crossover_double_point1),
        .crossover_double_point2(crossover_double_point2),
        .LSFR_input(rand_cross),
        .mask_uniform(uniform_crossover_mask),
        .uniform_random_enable(uniform_random_enable),
        .child(p_child_crossed),
        .crossover_done(cross_done)
    );

    mutation #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .LSFR_WIDTH(LFSR_WIDTH)
    ) mut_inst (
        .clk(clk),
        .rst(rst),
        .start_mutation(start_mutate),
        .child_in(p_child_crossed),
        .mutation_mode(mutation_mode),
        .mutation_rate(mutation_rate),
        .LSFR_input(rand_mut),
        .child_out(p_child_mutated),
        .mutation_done(mutate_done)
    );

    fitness_evaluator #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH)
    ) fit_eval_inst (
        .clk(clk),
        .rst(rst),
        .start_evaluation(start_eval_init || start_eval_pipe),
        .chromosome(start_eval_init ? init_chromosome_in : p_child_mutated),
        .fitness(p_child_fitness),
        .evaluation_done(eval_done)
    );

    population_memory #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE)
    ) pop_mem_inst (
        .clk(clk),
        .rst(rst),
        .start_write(start_pop_write),
        .child_in(start_eval_init ? init_chromosome_in : p_child_mutated),
        .child_fitness_in(start_eval_init ? init_fitness_in : p_child_fitness), // use proper fitness for init
        .read_addr1(p_selected_idx1),
        .read_addr2(p_selected_idx2),
        .request_fitness_values(req_fitness),
        .request_total_fitness(req_total_fitness),
        .parent1_out(pop_mem_parent1_out),
        .parent2_out(pop_mem_parent2_out),
        .fitness_values_out(pop_mem_fitness_values_out),
        .total_fitness_out(pop_mem_total_fitness_out),
        .write_done(pop_write_done)
    );

//======================================================================
// Main State Machine - Sequential Logic
//======================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

//======================================================================
// Pipeline & Counter State Machine - Sequential Logic
//======================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pipeline_state <= P_IDLE;
            init_counter <= '0;
            iteration_count <= '0;
            perfect_counter_reg <= '0;
            perfect_found_latch <= 1'b0;
            p_parent1 <= '0;
            p_parent2 <= '0;
            eval_init_pending <= 1'b0;
            eval_pipe_pending <= 1'b0;
            selection_valid <= 1'b0;
            crossover_valid <= 1'b0;
            mutation_valid <= 1'b0;
            init_fitness_in <= '0; // reset init fitness
        end else begin
            pipeline_state <= next_pipeline_state;

            if (state == S_INIT && pop_write_done && init_counter < POPULATION_SIZE) begin
                init_counter <= init_counter + 1;
            end
            if (pipeline_state == P_UPDATE && pop_write_done) begin
                iteration_count <= iteration_count + 1;
            end

            if (select_done && !selection_valid) begin
                p_parent1 <= pop_mem_parent1_out;
                p_parent2 <= pop_mem_parent2_out;
                selection_valid <= 1'b1;
            end else if (pipeline_state != P_SELECT && pipeline_state != P_CROSSOVER) begin
                selection_valid <= 1'b0;
            end

            if (cross_done) crossover_valid <= 1'b1;
            else if (pipeline_state != P_CROSSOVER && pipeline_state != P_MUTATION) crossover_valid <= 1'b0;

            if (mutate_done) mutation_valid <= 1'b1;
            else if (pipeline_state != P_MUTATION && pipeline_state != P_EVALUATE) mutation_valid <= 1'b0;

            if (start_eval_init) eval_init_pending <= 1'b1;
            else if (eval_done && eval_init_pending) eval_init_pending <= 1'b0;

            if (start_eval_pipe) eval_pipe_pending <= 1'b1;
            else if (eval_done && eval_pipe_pending) eval_pipe_pending <= 1'b0;

            // assign fitness after evaluation done in init phase
            if (eval_done && eval_init_pending) begin
                init_fitness_in <= p_child_fitness;
            end

            if (perfect_found && !perfect_found_latch) begin
                perfect_found_latch <= 1'b1;
                perfect_counter_reg <= iteration_count + 1;
            end
        end
    end

//======================================================================
// State Machines & Control - Combinational Logic
//======================================================================
    always_comb begin
        next_state = state;
        next_pipeline_state = pipeline_state;
        start_select = 1'b0;
        start_cross = 1'b0;
        start_mutate = 1'b0;
        start_eval_init = 1'b0;
        start_eval_pipe = 1'b0;
        start_pop_write = 1'b0;
        start_lfsrs = 1'b0;
        req_fitness = 1'b0;
        req_total_fitness = 1'b0;

        // Proper initialization chromosome assignment
        if (load_initial_population && state == S_INIT) begin
            init_chromosome_in = data_in;
        end else begin
            init_chromosome_in = rand_mut;
        end

        case(state)
            S_IDLE: if (start_ga) begin
                next_state = S_INIT;
                start_lfsrs = 1'b1;
            end

            S_INIT: begin
                start_lfsrs = 1'b1;
                if (!eval_init_pending && !eval_done) begin
                    start_eval_init = 1'b1;
                end else if (eval_done && !pop_write_done) begin
                    start_pop_write = 1'b1;
                end
                if (init_counter >= POPULATION_SIZE - 1 && pop_write_done) begin
                    next_state = S_RUNNING;
                    next_pipeline_state = P_SELECT;
                end
            end

            S_RUNNING: begin
                start_lfsrs = 1'b1;
                req_fitness = 1'b1;
                req_total_fitness = 1'b1;

                case(pipeline_state)
                    P_SELECT: if (!select_done) start_select = 1'b1;
                              else if (select_done && selection_valid) next_pipeline_state = P_CROSSOVER;
                    P_CROSSOVER: if (!cross_done && selection_valid) start_cross = 1'b1;
                                 else if (cross_done && crossover_valid) next_pipeline_state = P_MUTATION;
                    P_MUTATION: if (!mutate_done && crossover_valid) start_mutate = 1'b1;
                                else if (mutate_done && mutation_valid) next_pipeline_state = P_EVALUATE;
                    P_EVALUATE: if (!eval_pipe_pending && !eval_done && mutation_valid) start_eval_pipe = 1'b1;
                                 else if (eval_done && eval_pipe_pending) next_pipeline_state = P_UPDATE;
                    P_UPDATE: if (!pop_write_done) start_pop_write = 1'b1;
                              else if (pop_write_done) begin
                                  if (iteration_count >= target_iteration - 1 || perfect_found) begin
                                      next_state = S_DONE;
                                      next_pipeline_state = P_IDLE;
                                  end else begin
                                      next_pipeline_state = P_SELECT;
                                  end
                              end
                    default: next_pipeline_state = P_IDLE;
                endcase
            end
            S_DONE: next_pipeline_state = P_IDLE;
        endcase
    end

//======================================================================
// Output Assignments
//======================================================================
    assign best_chromosome = pop_mem_inst.population[0];
    assign best_fitness = pop_mem_inst.fitness_values[0];
    assign busy = (state == S_INIT || state == S_RUNNING);
    assign done = (state == S_DONE);
    assign perfect_found = (best_fitness == CHROMOSOME_WIDTH);
    assign crossovers_to_perfect = perfect_found_latch ? perfect_counter_reg : 0;
    assign data_out = best_chromosome;
    assign number_of_chromosomes = POPULATION_SIZE[ADDR_WIDTH-1:0];

endmodule
