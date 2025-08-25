`timescale 1ns/1ps

module selection_manual_tb;

    // =========================================================================
    // Parameters: match selection.sv & lfsr_random.sv
    // =========================================================================
    localparam CHROMOSOME_WIDTH = 16;
    localparam FITNESS_WIDTH    = 14;
    localparam POPULATION_SIZE  = 16;
    localparam ADDR_WIDTH       = $clog2(POPULATION_SIZE);
    localparam LFSR_WIDTH       = 16;

    // LFSR config (must match lfsr_random.sv)
    localparam LFSR_WIDTH1      = 16;
    localparam LFSR_WIDTH2      = 15;
    localparam LFSR_WIDTH3      = 14;
    localparam LFSR_WIDTH4      = 13;
    localparam LFSR_SEED_WIDTH  = LFSR_WIDTH1+LFSR_WIDTH2+LFSR_WIDTH3+LFSR_WIDTH4;

    // =========================================================================
    // Testbench Signals
    // =========================================================================
    reg clk, rst;
    reg start_selection;
    reg [FITNESS_WIDTH-1:0] fitness_values [POPULATION_SIZE-1:0];
    reg [FITNESS_WIDTH-1:0] total_fitness;
    wire [LFSR_WIDTH-1:0]   lfsr_input;

    wire [ADDR_WIDTH-1:0]   selected_index1;
    wire [ADDR_WIDTH-1:0]   selected_index2;
    wire selection_done;

    // Internal DUT signals (tapped hierarchically)
    wire [FITNESS_WIDTH+LFSR_WIDTH-1:0] roulette_pos1, roulette_pos2;
    wire [FITNESS_WIDTH-1:0] fitness_sum1, fitness_sum2;
    wire total_fitness_zero;
    wire selecting;
    wire [ADDR_WIDTH-1:0] selected_index1_comb, selected_index2_comb;

    // =========================================================================
    // LFSR instance for random generation
    // =========================================================================
    reg start_lfsr, load_seed;
    reg [LFSR_SEED_WIDTH-1:0] seed_in;
    wire [LFSR_WIDTH1-1:0] random_out;

    lfsr_SudoRandom #(
        .WIDTH1(LFSR_WIDTH1), .WIDTH2(LFSR_WIDTH2),
        .WIDTH3(LFSR_WIDTH3), .WIDTH4(LFSR_WIDTH4)
    ) lfsr_inst (
        .clk(clk),
        .rst(rst),
        .start_lfsr(start_lfsr),
        .seed_in(seed_in),
        .load_seed(load_seed),
        .random_out(random_out)
    );

    assign lfsr_input = random_out;

    // =========================================================================
    // DUT instance
    // =========================================================================
    selection #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE),
        .LFSR_WIDTH(LFSR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start_selection(start_selection),
        .fitness_values(fitness_values),
        .total_fitness(total_fitness),
        .lfsr_input(lfsr_input),
        .selected_index1(selected_index1),
        .selected_index2(selected_index2),
        .selection_done(selection_done)
    );

    // =========================================================================
    // Tap DUT internal signals (like GA_manual_test.sv)
    // =========================================================================
    assign roulette_pos1        = dut.roulette_pos1;
    assign roulette_pos2        = dut.roulette_pos2;
    assign fitness_sum1         = dut.fitness_sum1;
    assign fitness_sum2         = dut.fitness_sum2;
    assign total_fitness_zero   = dut.total_fitness_zero;
    assign selecting            = dut.selecting;
    assign selected_index1_comb = dut.selected_index1_comb;
    assign selected_index2_comb = dut.selected_index2_comb;
    // =========================================================================
    // Clock generation + counter
    // =========================================================================
    initial clk = 0;
    always #50 clk = ~clk;

    integer clk_counter;
    initial clk_counter = 0;
    always @(posedge clk) clk_counter <= clk_counter + 1;

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        // Init
        rst = 1;
        start_selection = 0;
        total_fitness = 0;
        for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = 0;
        start_lfsr = 0;
        load_seed = 0;
        seed_in = {16'hACE1, 15'h3BEE, 14'h2BAD, 13'h1DAD};

        // Reset
        #200 rst = 0;

        // Seed LFSR
        @(posedge clk); load_seed = 1;
        @(posedge clk); load_seed = 0;

        // Warm-up LFSR so numbers aren't correlated
        repeat (5) begin
            start_lfsr = 1;
            @(posedge clk);
            start_lfsr = 0;
            @(posedge clk);
        end

        // ------------------------------
        // Test 1: Zero total_fitness case
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = 0;
        total_fitness = 0;
        pulse_selection();

        // ------------------------------
        // Test 2: Skewed distribution (old GA_top problem pattern)
        // High at index 0, low at last index
        // ------------------------------
        fitness_values[0] = 14'd100;
        for (int i = 1; i < POPULATION_SIZE; i++) fitness_values[i] = 14'd1;
        total_fitness = 14'(100 + (POPULATION_SIZE - 1));
        pulse_selection();

        // ------------------------------
        // Test 3: Uniform distribution
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = 14'd5;
        total_fitness = 14'(5 * POPULATION_SIZE);
        pulse_selection();

        // ------------------------------
        // Multiple random trials
        // ------------------------------
        repeat (10) begin
            // Advance LFSR for new lfsr_input
            start_lfsr = 1; @(posedge clk);
            start_lfsr = 0; @(posedge clk);
            // Fill random-ish fitness pattern
            for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = random_out[i % LFSR_WIDTH] ? 14'd10 : 14'd1;
            total_fitness = sum_fitness();
            pulse_selection();
        end

        #500 $finish;
    end

    task pulse_selection;
    begin
        @(posedge clk);
        start_selection = 1;
        @(posedge clk);
        start_selection = 0;
        @(posedge selection_done);
    end
    endtask

    function automatic [FITNESS_WIDTH-1:0] sum_fitness;
        automatic int s = 0;
        for (int i = 0; i < POPULATION_SIZE; i++) s += fitness_values[i];
        return s;
    endfunction

    // =========================================================================
    // CSV Logging
    // =========================================================================
    integer log_file, j;
    initial begin
        log_file = $fopen("selection_test.csv", "w");
        if (!log_file) begin
            $display("ERROR opening selection_test.csv");
            $finish;
        end

        // Header
        $fwrite(log_file, "clk_counter,clk,rst,start_selection,");
        for (j = 0; j < POPULATION_SIZE; j++)
            $fwrite(log_file, "fitness_values[%0d],", j);
        $fwrite(log_file, "total_fitness,lfsr_input,selected_index1,selected_index2,selection_done,");
        $fwrite(log_file, "roulette_pos1,roulette_pos2,fitness_sum1,fitness_sum2,total_fitness_zero,selecting,selected_index1_comb,selected_index2_comb");
    end

    always @(posedge clk) begin
        // Main row
        $fwrite(log_file, "%0d,%b,%b,%b,", clk_counter, clk, rst, start_selection);
        for (j = 0; j < POPULATION_SIZE; j++)
            $fwrite(log_file, "%0d,", fitness_values[j]);
        $fwrite(log_file, "%0d,%h,%0d,%0d,%b,", total_fitness, lfsr_input, selected_index1, selected_index2, selection_done);
        $fwrite(log_file, "%h,%h,%0d,%0d,%b,%b,%0d,%0d",
                roulette_pos1, roulette_pos2, fitness_sum1, fitness_sum2,
                total_fitness_zero, selecting, selected_index1_comb, selected_index2_comb);
        $fdisplay(log_file, ""); // End of line
    end

    final $fclose(log_file);

endmodule
