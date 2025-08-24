`timescale 1us / 1ps

// -----------------------------------------------------------
// 1. Interface - bundles DUT I/O signals
// -----------------------------------------------------------
interface ga_if #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH    = 14,
    parameter POPULATION_SIZE  = 16
)(input logic clk, input logic rst);
    // Inputs
    logic                                start_ga;
    logic                                load_initial_population;
    logic [CHROMOSOME_WIDTH-1:0]         data_in;

    logic [1:0]                          crossover_mode;
    logic                                crossover_single_double;
    logic [$clog2(CHROMOSOME_WIDTH)-1:0] crossover_single_point;
    logic [$clog2(CHROMOSOME_WIDTH)-1:0] crossover_double_point1;
    logic [$clog2(CHROMOSOME_WIDTH)-1:0] crossover_double_point2;
    logic [CHROMOSOME_WIDTH-1:0]         uniform_crossover_mask;
    logic                                uniform_random_enable;

    logic [2:0]                          mutation_mode;
    logic [7:0]                          mutation_rate;

    logic [31:0]                         target_iteration;

    // Outputs
    logic                                busy;
    logic                                done;
    logic                                perfect_found;
    logic [CHROMOSOME_WIDTH-1:0]         best_chromosome;
    logic [FITNESS_WIDTH-1:0]            best_fitness;
    logic [31:0]                         iteration_count;
    logic [31:0]                         crossovers_to_perfect;

    // Legacy outputs
    logic [CHROMOSOME_WIDTH-1:0]         data_out;
    logic [$clog2(POPULATION_SIZE)-1:0]  number_of_chromosomes;
endinterface

// -----------------------------------------------------------
// 2. Testbench module
// -----------------------------------------------------------
module ga_top_tb;
    // Clock
    logic CLK = 0;
    always #50 CLK = ~CLK; // 100 us period -> 10 kHz clock

    // Reset
    logic RST;
    initial begin
        RST = 1'b1;
        #100;
        RST = 1'b0;
    end

    // Interface instance
    ga_if #(.CHROMOSOME_WIDTH(16), .FITNESS_WIDTH(14), .POPULATION_SIZE(16)) intf(.clk(CLK), .rst(RST));

    // DUT instantiation
    ga_top #(
        .CHROMOSOME_WIDTH(16),
        .FITNESS_WIDTH(14),
        .POPULATION_SIZE(16)
    ) DUT (
        .clk                       (intf.clk),
        .rst                       (intf.rst),
        .start_ga                  (intf.start_ga),

        .load_initial_population   (intf.load_initial_population),
        .data_in                   (intf.data_in),

        .crossover_mode            (intf.crossover_mode),
        .crossover_single_double   (intf.crossover_single_double),
        .crossover_single_point    (intf.crossover_single_point),
        .crossover_double_point1   (intf.crossover_double_point1),
        .crossover_double_point2   (intf.crossover_double_point2),
        .uniform_crossover_mask    (intf.uniform_crossover_mask),
        .uniform_random_enable     (intf.uniform_random_enable),

        .mutation_mode             (intf.mutation_mode),
        .mutation_rate             (intf.mutation_rate),

        .target_iteration          (intf.target_iteration),

        .busy                      (intf.busy),
        .done                      (intf.done),
        .perfect_found             (intf.perfect_found),
        .best_chromosome           (intf.best_chromosome),
        .best_fitness              (intf.best_fitness),
        .iteration_count           (intf.iteration_count),
        .crossovers_to_perfect     (intf.crossovers_to_perfect),

        .data_out                  (intf.data_out),
        .number_of_chromosomes     (intf.number_of_chromosomes)
    );

    // Signals for display
    logic [15:0] BestChr, DataOut;
    logic [13:0] BestFit;
    logic Busy, Done, Perfect;
    logic [31:0] IterCount;

    assign BestChr    = intf.best_chromosome;
    assign BestFit    = intf.best_fitness;
    assign Busy       = intf.busy;
    assign Done       = intf.done;
    assign Perfect    = intf.perfect_found;
    assign DataOut    = intf.data_out;
    assign IterCount  = intf.iteration_count;

    // -------------------------------------------------------
    // 4. Generator - Load initial population from memory array
    // -------------------------------------------------------
    logic [15:0] population_mem [0:15];

    // *** NEW: Initialize population directly in the testbench ***
    initial begin
        $display("Initializing population memory directly in testbench...");
        population_mem[0]  = 16'h0001; // 0000000000000001
        population_mem[1]  = 16'h090F; // 0000100100001111
        population_mem[2]  = 16'h0F02; // 0000111100000010
        population_mem[3]  = 16'h1234; // 0001001000110100
        population_mem[4]  = 16'hABCD; // 1010101111001101
        population_mem[5]  = 16'h5555; // 0101010101010101
        population_mem[6]  = 16'hAAAA; // 1010101010101010
        population_mem[7]  = 16'h0ACE; // 0000101011001110
        population_mem[8]  = 16'hD2AD; // 1101001010101101
        population_mem[9]  = 16'hB2EF; // 1011001011101111
        population_mem[10] = 16'h0000; // 0000000000000000
        population_mem[11] = 16'h1111; // 0001000100010001
        population_mem[12] = 16'h2222; // 0010001000100010
        population_mem[13] = 16'h3333; // 0011001100110011
        population_mem[14] = 16'h4444; // 0100010001000100
        population_mem[15] = 16'h0601; // 0000011000000001
    end

    // *** RENAMED: Task to run the test ***
    task run_ga_test;
        integer i;
        begin
            $display("Population initialized. Starting GA process...");

            // Start INIT
            intf.start_ga = 1'b1;
            @(posedge CLK);
            intf.start_ga = 1'b0;

            // --- Robust synchronization loop for loading initial population ---
            for (i = 0; i < 16; i = i + 1) begin
                // Fixed: Wait for DUT ready (state INIT and counter == i), plus extra cycle for stability
                wait (DUT.state == DUT.S_INIT && DUT.init_counter == i);
                @(posedge CLK);  // Wait one more cycle to ensure stability
                intf.data_in = population_mem[i];  // Set data_in first
                @(posedge CLK);  // Allow DUT to see data_in
                intf.load_initial_population = 1'b1;
                @(posedge CLK);
                intf.load_initial_population = 1'b0;
                // Wait for write completion before next
                wait (DUT.pop_write_done);
            end

            // Wait for the simulation to complete.
            wait(intf.done);
            $display("Done signal received. Testbench finished.");
        end
    endtask

// -------------------------------------------------------
// 5. Detailed, cycle-by-cycle file logging
// -------------------------------------------------------

integer logfile;

initial begin
    // Using a relative path for the log file makes the project more portable.
    logfile  = $fopen("ga_detailed_log.txt", "w");
    if (!logfile) begin
        $display("ERROR: Cannot open ga_detailed_log.txt");
        $finish;
    end

    // Write a detailed CSV-style header for our log file.
    $fdisplay(logfile, "Time,RST,start_ga,load_initial_population,data_in,GA_State,Pipe_State,init_cnt,iter_cnt,busy,done,perfect,best_chr,best_fit,req_fit,req_tot_fit,start_sel,sel_done,sel_idx1,sel_idx2,parent1,parent2,start_cross,cross_done,child_cross,start_mut,mut_done,child_mut,start_eval_init,start_eval_pipe,eval_done,child_fit,start_pop_write,pop_write_done");
    $fdisplay(logfile, "# GA State Key: 0=S_IDLE, 1=S_INIT, 2=S_RUNNING, 3=S_DONE");
    $fdisplay(logfile, "# Pipeline State Key: 0=P_IDLE, 1=P_SELECT, 2=P_CROSSOVER, 3=P_MUTATION, 4=P_EVALUATE, 5=P_UPDATE");
end

// This block captures the state of the DUT on every single rising clock edge.
always @(posedge CLK) begin
    if (!RST) begin
        $fdisplay(logfile, "%0t,%b,%b,%b,%h,%d,%d,%d,%d,%b,%b,%b,%h,%d,%b,%b,%b,%b,%d,%d,%h,%h,%b,%b,%h,%b,%b,%h,%b,%b,%b,%d,%b,%b",
            $time, RST, intf.start_ga, intf.load_initial_population, intf.data_in,
            DUT.state, DUT.pipeline_state, DUT.init_counter, intf.iteration_count,
            intf.busy, intf.done, intf.perfect_found, intf.best_chromosome, intf.best_fitness,
            DUT.req_fitness, DUT.req_total_fitness,
            DUT.start_select, DUT.select_done, DUT.p_selected_idx1, DUT.p_selected_idx2,
            DUT.p_parent1, DUT.p_parent2,
            DUT.start_cross, DUT.cross_done, DUT.p_child_crossed,
            DUT.start_mutate, DUT.mutate_done, DUT.p_child_mutated,
            DUT.start_eval_init, DUT.start_eval_pipe, DUT.eval_done, DUT.p_child_fitness,
            DUT.start_pop_write, DUT.pop_write_done
        );
    end
end

// -------------------------------------------------------
// 6. Display monitor & Simulation Control
// -------------------------------------------------------
initial begin
    $display("--------------------------------------------------------------------------");
    $display("| Time | Busy | Done | Iter | BestChr(hex) | BestFit | Perfect | DataOut |");
    $display("--------------------------------------------------------------------------");
    $monitor("%0t |   %b   |  %b  | %3d  |    0x%0h    |   %0d    |   %b    | 0x%0h",
             $time, Busy, Done, IterCount, BestChr, BestFit, Perfect, DataOut);
end

always @(posedge CLK) begin
    if (Perfect) begin
        $display("** Perfect found at t=%0t, iteration=%0d, best=0x%0h fitness=%0d",
                 $time, IterCount, BestChr, BestFit);
    end
    if (Done) begin
        $display("** GA Done at t=%0t, iterations=%0d, best=0x%0h fitness=%0d",
                 $time, IterCount, BestChr, BestFit);
        if (logfile) begin
            $fdisplay(logfile, "----------------- SIMULATION FINISHED -----------------");
            $fclose(logfile);
        end
        #10 $finish;
    end
end

// -------------------------------------------------------
// 7. Run sim
// -------------------------------------------------------
initial begin
    // --- GA Parameters ---
    intf.crossover_mode          = 2'b00;
    intf.crossover_single_double = 1'b0;
    intf.crossover_single_point  = 4'd8;
    intf.crossover_double_point1 = 4'd4;
    intf.crossover_double_point2 = 4'd12;
    intf.uniform_crossover_mask  = 16'hAAAA;
    intf.uniform_random_enable   = 1'b0;
    intf.mutation_mode           = 3'b000;
    intf.mutation_rate           = 8'd5;
    intf.target_iteration        = 32'd20;

    // --- Start Simulation ---
    repeat (5) @(posedge CLK);
    run_ga_test; // *** UPDATED: Call the renamed task ***
    $stop;
end

endmodule