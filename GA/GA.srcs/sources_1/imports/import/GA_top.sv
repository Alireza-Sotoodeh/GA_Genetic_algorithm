module ga_top #(
    // General GA Parameters
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14,
    parameter POPULATION_SIZE = 16,

    // Derived Parameters
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE),
    parameter TOTAL_FIT_WIDTH = FITNESS_WIDTH + $clog2(POPULATION_SIZE) + 1, // Fixed: Correct width calculation
    parameter LFSR_WIDTH = 16
)(
    //''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Control & Clocking
    input  logic                                clk,
    input  logic                                rst,
    input  logic                                start_ga, // Pulse to start the entire GA process

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
    logic [FITNESS_WIDTH-1:0]    init_fitness_in;

    // Population Memory connections - Fixed signal widths
    logic [CHROMOSOME_WIDTH-1:0] pop_mem_parent1_out, pop_mem_parent2_out;
    logic [FITNESS_WIDTH-1:0]    pop_mem_fitness_values_out [POPULATION_SIZE-1:0];
    logic [TOTAL_FIT_WIDTH-1:0]  pop_mem_total_fitness_out; // Fixed: Use correct width

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

    // Selection
    selection #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE)
    ) select_inst (
        .clk(clk), .rst(rst), .start_selection(start_select),
        .fitness_values(pop_mem_fitness_values_out),
        .total_fitness(pop_mem_total_fitness_out[FITNESS_WIDTH-1:0]),
        .lfsr_input(rand_sel),
        .selected_index1(p_selected_idx1),
        .selected_index2(p_selected_idx2),
        .selection_done(select_done)
    );

    // Crossover
    crossover #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .LSFR_WIDTH(LFSR_WIDTH)
    ) cross_inst (
        .clk(clk), .rst(rst), .start_crossover(start_cross),
        .parent1(p_parent1), .parent2(p_parent2),
        .crossover_mode(crossover_mode),
        .crossover_single_double(crossover_single_double),
        .crossover_Single_point(crossover_single_point),
        .crossover_double_point1(crossover_double_point1),
        .crossover_double_point2(crossover_double_point2),
        .mask_uniform(uniform_crossover_mask),
        .uniform_random_enable(uniform_random_enable),
        .LSFR_input(rand_cross),
        .child(p_child_crossed),
        .crossover_done(cross_done)
    );

    // Mutation
    mutation #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .LSFR_WIDTH(LFSR_WIDTH)
    ) mutate_inst (
        .clk(clk), .rst(rst), .start_mutation(start_mutate),
        .child_in(p_child_crossed),
        .mutation_mode(mutation_mode),
        .mutation_rate(mutation_rate),
        .LSFR_input(rand_mut),
        .child_out(p_child_mutated),
        .mutation_done(mutate_done)
    );

    // Fitness Evaluator for Initialization
    fitness_evaluator #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH)
    ) eval_init_inst (
        .clk(clk), .rst(rst), .start_evaluation(start_eval_init),
        .chromosome(init_chromosome_in),
        .fitness(init_fitness_in),
        .evaluation_done(eval_done)  // Shared done for simplicity
    );

    // Fitness Evaluator for Pipeline
    fitness_evaluator #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH)
    ) eval_pipe_inst (
        .clk(clk), .rst(rst), .start_evaluation(start_eval_pipe),
        .chromosome(p_child_mutated),
        .fitness(p_child_fitness),
        .evaluation_done(eval_done)  // Shared done
    );

    // Population Memory
    population_memory #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE)
    ) pop_mem_inst (
        .clk(clk), .rst(rst), .start_write(start_pop_write),
        .child_in(pop_child_in),  // Muxed input
        .child_fitness_in(pop_child_fitness_in),  // Muxed input
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
// Corrections: Mux for population_memory inputs (init vs. runtime)
//======================================================================

    assign pop_child_in = (state == S_INIT) ? init_chromosome_in : p_child_mutated;
    assign pop_child_fitness_in = (state == S_INIT) ? init_fitness_in : p_child_fitness;

//======================================================================
// Sequential Logic - State Updates & Counters
//======================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            pipeline_state <= P_IDLE;
            iteration_count <= '0;
            init_counter <= '0;
            perfect_found_latch <= 1'b0;
            perfect_counter_reg <= '0;
            eval_init_pending <= 1'b0;
            eval_pipe_pending <= 1'b0;
            selection_valid <= 1'b0;
            crossover_valid <= 1'b0;
            mutation_valid <= 1'b0;
            p_parent1 <= '0;
            p_parent2 <= '0;
        end else begin
            state <= next_state;
            pipeline_state <= next_pipeline_state;

            // Parent registers (from population memory)
            p_parent1 <= pop_mem_parent1_out;
            p_parent2 <= pop_mem_parent2_out;

            // Iteration counter
            if (state == S_RUNNING && pipeline_state == P_UPDATE && pop_write_done) begin
                iteration_count <= iteration_count + 1;
            end

            // Init counter increment on write done
            if (state == S_INIT && pop_write_done) begin
                init_counter <= init_counter + 1;
            end

            // Validity flags
            if (select_done) selection_valid <= 1'b1;
            else if (pipeline_state != P_SELECT) selection_valid <= 1'b0;

            if (cross_done) crossover_valid <= 1'b1;
            else if (pipeline_state != P_CROSSOVER) crossover_valid <= 1'b0;

            if (mutate_done) mutation_valid <= 1'b1;
            else if (pipeline_state != P_MUTATION && pipeline_state != P_EVALUATE) mutation_valid <= 1'b0;

            // Evaluation pending flags
            if (start_eval_init) eval_init_pending <= 1'b1;
            else if (eval_done && eval_init_pending) eval_init_pending <= 1'b0;
            
            if (start_eval_pipe) eval_pipe_pending <= 1'b1;
            else if (eval_done && eval_pipe_pending) eval_pipe_pending <= 1'b0;

            // Latch perfect found status and counter
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
        // Default values for all start signals
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
        
        // Fixed: Proper initialization chromosome handling
        init_chromosome_in = load_initial_population ? data_in : rand_mut;

        //----------- Main FSM Logic -----------
        case(state)
            S_IDLE: begin
                if (start_ga) begin
                    next_state = S_INIT;
                    start_lfsrs = 1'b1; // Start LFSRs immediately
                end
            end

            S_INIT: begin
                start_lfsrs = 1'b1; // Keep LFSRs running
                
                // Fixed: Gate start_eval_init on load_initial_population
                if (load_initial_population && !eval_init_pending && !eval_done) begin
                    start_eval_init = 1'b1; // Start evaluation for current chromosome
                end else if (eval_done && !pop_write_done) begin
                    start_pop_write = 1'b1; // Start writing to population
                end

                // Transition when all chromosomes are initialized
                if (init_counter >= POPULATION_SIZE - 1 && pop_write_done) begin
                    next_state = S_RUNNING;
                    next_pipeline_state = P_SELECT;
                end
            end

            S_RUNNING: begin
                start_lfsrs = 1'b1; // Keep LFSRs running
                req_fitness = 1'b1;  // Always request fitness values
                req_total_fitness = 1'b1; // Always request total fitness

                //----------- Pipeline FSM Logic -----------
                case(pipeline_state)
                    P_SELECT: begin
                        if (!select_done) begin
                            start_select = 1'b1;
                        end else if (select_done && selection_valid) begin
                            next_pipeline_state = P_CROSSOVER;
                        end
                    end
                    
                    P_CROSSOVER: begin
                        if (!cross_done && selection_valid) begin
                            start_cross = 1'b1;
                        end else if (cross_done && crossover_valid) begin
                            next_pipeline_state = P_MUTATION;
                        end
                    end
                    
                    P_MUTATION: begin
                        if (!mutate_done && crossover_valid) begin
                            start_mutate = 1'b1;
                        end else if (mutate_done && mutation_valid) begin
                            next_pipeline_state = P_EVALUATE;
                        end
                    end
                    
                    P_EVALUATE: begin
                        if (!eval_pipe_pending && !eval_done && mutation_valid) begin
                            start_eval_pipe = 1'b1;
                        end else if (eval_done && eval_pipe_pending) begin
                            next_pipeline_state = P_UPDATE;
                        end
                    end
                    
                    P_UPDATE: begin
                        if (!pop_write_done) begin
                            start_pop_write = 1'b1;
                        end else if (pop_write_done) begin
                            // Check termination conditions
                            if (iteration_count >= target_iteration - 1 || perfect_found) begin
                                next_state = S_DONE;
                                next_pipeline_state = P_IDLE;
                            end else begin
                                next_pipeline_state = P_SELECT; // Continue to next generation
                            end
                        end
                    end
                    
                    default: next_pipeline_state = P_IDLE;
                endcase
            end

            S_DONE: begin
                next_pipeline_state = P_IDLE;
                // Stay in this state until reset
            end
        endcase
    end

//======================================================================
// Output Assignments
//======================================================================
    // Since population memory is sorted descending, best is always at index 0
    assign best_chromosome = pop_mem_inst.population[0];
    assign best_fitness = pop_mem_inst.fitness_values[0];

    // Status signals
    assign busy = (state == S_INIT || state == S_RUNNING);
    assign done = (state == S_DONE);

    // The "perfect" chromosome is all 1s, so its fitness equals its width
    assign perfect_found = (best_fitness == CHROMOSOME_WIDTH);
    assign crossovers_to_perfect = perfect_found_latch ? perfect_counter_reg : 0;

    // Legacy outputs from your request
    assign data_out = best_chromosome;
    assign number_of_chromosomes = POPULATION_SIZE[ADDR_WIDTH-1:0];

endmodule