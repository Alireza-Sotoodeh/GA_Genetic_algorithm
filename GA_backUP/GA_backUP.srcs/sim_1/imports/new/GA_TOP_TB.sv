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
    always #50 CLK = ~CLK; // 100 MHz

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
    // 4. Generator - Load initial population from file
    // -------------------------------------------------------
    logic [15:0] population_mem [0:15];
    task generator_from_file;
        string filename;
        integer i;
        begin
            // Let's use a relative path for portability. Make sure population.txt is in the same directory.
            filename = "population.txt";
            $readmemb(filename, population_mem);
            $display("Population loaded from %s", filename);

            // Start INIT
            intf.start_ga = 1'b1;
            @(posedge CLK);
            intf.start_ga = 1'b0;

            // --- REVISED AND ROBUST SYNCHRONIZATION LOOP ---
            for (i = 0; i < 16; i = i + 1) begin
                // 1. Wait for the DUT to be in the correct state and ready for the 'i'-th chromosome.
                //    This avoids the race condition by not depending on the single-cycle 'pop_write_done' signal.
                wait (DUT.state == DUT.S_INIT && DUT.init_counter == i);

                // 2. Align to the next positive clock edge. This ensures we are in a clean, stable state
                //    before we apply our stimulus signals.
                @(posedge CLK);

                // 3. Now, drive the data and the load pulse for one full clock cycle.
                //    The DUT is guaranteed to be listening for chromosome 'i' at this exact moment.
                intf.data_in <= population_mem[i];
                intf.load_initial_population <= 1'b1;
                @(posedge CLK);
                intf.load_initial_population <= 1'b0;

                // The loop will now naturally pause at the 'wait' statement above until the DUT
                // has finished its entire evaluation/write cycle and incremented init_counter to 'i+1'.
            end

            // Wait for the simulation to complete.
            wait(intf.done);
            $display("Done signal received. Testbench finished.");
        end
    endtask

    // -------------------------------------------------------
    // 5. File logging support
    // -------------------------------------------------------
    integer logfile;

    task dump_iteration(input int iter);
        int i;
        $fdisplay(logfile, "---------------------------------------------------");
        $fdisplay(logfile, "stage%0d done : (iteration %0d)", iter, iter);

        $fdisplay(logfile, "Population memory:");
        for (i = 0; i < 16; i++) begin
            $fdisplay(logfile, " idx %0d: chr=0x%0h fit=%0d", 
                      i, DUT.pop_mem_inst.population[i], DUT.pop_mem_inst.fitness_values[i]);
        end
        $fdisplay(logfile, "Total fitness: %0d", DUT.pop_mem_inst.total_fitness_out);

        $fdisplay(logfile, "load_initial_population = %b", intf.load_initial_population);
        $fdisplay(logfile, "data_in = 0x%0h", intf.data_in);

        $fdisplay(logfile, "selected parent1 idx=%0d chr=0x%0h", DUT.p_selected_idx1, DUT.p_parent1);
        $fdisplay(logfile, "selected parent2 idx=%0d chr=0x%0h", DUT.p_selected_idx2, DUT.p_parent2);
        $fdisplay(logfile, "output crossover = 0x%0h", DUT.p_child_crossed);
        $fdisplay(logfile, "child after mutation = 0x%0h", DUT.p_child_mutated);
        $fdisplay(logfile, "child fitness = %0d", DUT.p_child_fitness);
    endtask

    // Trigger logging at iteration completion
    always @(posedge CLK) begin
        if (DUT.pipeline_state == DUT.P_UPDATE && DUT.pop_write_done) begin
            dump_iteration(intf.iteration_count);
        end
    end

    // -------------------------------------------------------
    // 6. Display monitor
    // -------------------------------------------------------
    initial begin
        logfile  = $fopen("D:/university/studies/FPGA/PJ_FPGA/GA_Genetic_algorithm/GA/GA.srcs/testbench_GA/GA_LOG.txt", "w");
        if (!logfile) begin
            $display("ERROR: cannot open ga_log.txt");
            $finish;
        end

        // Write initial settings
        $fdisplay(logfile, "GA setting initial:");
        $fdisplay(logfile, "crossover_mode          = %b", intf.crossover_mode);
        $fdisplay(logfile, "crossover_single_double = %b", intf.crossover_single_double);
        $fdisplay(logfile, "crossover_single_point  = %0d", intf.crossover_single_point);
        $fdisplay(logfile, "crossover_double_point1 = %0d", intf.crossover_double_point1);
        $fdisplay(logfile, "crossover_double_point2 = %0d", intf.crossover_double_point2);
        $fdisplay(logfile, "uniform_crossover_mask  = 0x%0h", intf.uniform_crossover_mask);
        $fdisplay(logfile, "uniform_random_enable   = %b", intf.uniform_random_enable);
        $fdisplay(logfile, "mutation_mode           = %0d", intf.mutation_mode);
        $fdisplay(logfile, "mutation_rate           = %0d", intf.mutation_rate);
        $fdisplay(logfile, "target_iteration        = %0d", intf.target_iteration);

        // Console header
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
            $fclose(logfile);
            #10 $finish;
        end
    end

    // -------------------------------------------------------
    // 7. Run sim
    // -------------------------------------------------------
    initial begin
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

        repeat (5) @(posedge CLK);
        generator_from_file;
        $stop;
    end

endmodule
