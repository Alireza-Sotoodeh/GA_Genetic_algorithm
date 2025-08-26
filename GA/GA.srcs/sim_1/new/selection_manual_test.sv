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
    reg [FITNESS_WIDTH + ADDR_WIDTH -1:0] total_fitness;  // Increased width to match sum
    wire [LFSR_WIDTH-1:0]   lfsr_input;

    wire [ADDR_WIDTH-1:0]   selected_index1;
    wire [ADDR_WIDTH-1:0]   selected_index2;
    wire selection_done;

    // Internal DUT signals (tapped hierarchically, corrected to match actual DUT signals)
    wire [FITNESS_WIDTH + LFSR_WIDTH -1:0] roulette_pos1, roulette_pos2;  // Match increased width
    wire total_fitness_zero;
    wire [ADDR_WIDTH-1:0] selected_index1_comb, selected_index2_comb;
    wire selecting; // To tap internal selecting flag for debugging

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
        .total_fitness(total_fitness[FITNESS_WIDTH-1:0]),  // Truncate to match DUT input width
        .lfsr_input(lfsr_input),
        .selected_index1(selected_index1),
        .selected_index2(selected_index2),
        .selection_done(selection_done)
    );

    // =========================================================================
    // Tap DUT internal signals (corrected to existing signals only)
    // =========================================================================
    assign roulette_pos1        = dut.roulette_pos1;
    assign roulette_pos2        = dut.roulette_pos2;
    assign total_fitness_zero   = dut.total_fitness_zero;
    assign selected_index1_comb = dut.selected_index1_comb;
    assign selected_index2_comb = dut.selected_index2_comb;
    assign selecting            = dut.selecting; // Tap internal selecting for debugging

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
        // New Test 4: Single high fitness at end
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE - 1; i++) fitness_values[i] = 14'd1;
        fitness_values[POPULATION_SIZE - 1] = 14'd100;
        total_fitness = 14'(100 + (POPULATION_SIZE - 1));
        pulse_selection();

        // ------------------------------
        // New Test 5: Two high fitness values
        // ------------------------------
        fitness_values[0] = 14'd50;
        fitness_values[1] = 14'd50;
        for (int i = 2; i < POPULATION_SIZE; i++) fitness_values[i] = 14'd1;
        total_fitness = 14'(50 + 50 + (POPULATION_SIZE - 2));
        pulse_selection();

        // ------------------------------
        // New Test 6: All fitness zero except one
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = 0;
        fitness_values[5] = 14'd10;
        total_fitness = 14'd10;
        pulse_selection();

        // ------------------------------
        // New Test 7: Maximum fitness values (near overflow)
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = {FITNESS_WIDTH{1'b1}}; // Max value
        total_fitness = sum_fitness(); // Use function to handle potential overflow
        pulse_selection();

        // ------------------------------
        // New Test 8: Alternating high and low fitness
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE; i++) begin
            fitness_values[i] = (i % 2 == 0) ? 14'd20 : 14'd1;
        end
        total_fitness = sum_fitness();
        pulse_selection();

        // ------------------------------
        // New Test 9: Increasing fitness gradient
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = 14'(i + 1);
        total_fitness = sum_fitness();
        pulse_selection();

        // ------------------------------
        // New Test 10: Decreasing fitness gradient
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = 14'(POPULATION_SIZE - i);
        total_fitness = sum_fitness();
        pulse_selection();

        // ------------------------------
        // Multiple random trials (reduced to 20 for faster simulation during debug)
        // ------------------------------
        repeat (20) begin
            // Advance LFSR for new lfsr_input
            start_lfsr = 1; @(posedge clk);
            start_lfsr = 0; @(posedge clk);
            // Fill random-ish fitness pattern with more variety
            for (int i = 0; i < POPULATION_SIZE; i++) begin
                // Generate more varied fitness: 0 to 100 based on random_out bits
                fitness_values[i] = (random_out[i % LFSR_WIDTH] ? 14'(random_out[7:0] % 100) : 14'd0);
            end
            total_fitness = sum_fitness();
            pulse_selection();
        end

        // ------------------------------
        // Additional edge case: lfsr_input = 0 (force low value)
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = 14'd1;
        total_fitness = 14'(POPULATION_SIZE);
        // Advance minimally to get potentially low lfsr_input
        start_lfsr = 1; @(posedge clk);
        start_lfsr = 0; @(posedge clk);
        pulse_selection();

        // ------------------------------
        // Additional edge case: lfsr_input max value
        // ------------------------------
        for (int i = 0; i < POPULATION_SIZE; i++) fitness_values[i] = 14'd1;
        total_fitness = 14'(POPULATION_SIZE);
        // Advance LFSR multiple times to get high values
        repeat (10) begin
            start_lfsr = 1; @(posedge clk);
            start_lfsr = 0; @(posedge clk);
        end
        pulse_selection();

        #500 $finish;
    end

    task pulse_selection;
    begin
        @(posedge clk);
        start_selection = 1;
        @(posedge clk);
        start_selection = 0;
        // Wait for selection_done or timeout to prevent hangs
        fork
            begin
                while (!selection_done) @(posedge clk);  // Poll every cycle to catch short pulses
            end
            begin
                #20000; // Increased timeout to 20us (200 * 100ns = 20000ns)
                $display("WARNING: Selection timeout! Current selecting: %b, total_fitness: %0d", selecting, total_fitness);
            end
        join_any
    end
    endtask

    function automatic [FITNESS_WIDTH + ADDR_WIDTH -1:0] sum_fitness;  // Increased return width, no truncate
        automatic logic [31:0] s = 0;  // Use 32-bit for safe sum
        for (int i = 0; i < POPULATION_SIZE; i++) s += fitness_values[i];
        return s[FITNESS_WIDTH + ADDR_WIDTH -1:0];
    endfunction

    // =========================================================================
    // CSV Logging (enhanced with test labels, removed non-existing signals)
    // =========================================================================
    integer log_file, j;
    integer test_num = 0;
    initial begin
        log_file = $fopen("selection_test.csv", "w");
        if (!log_file) begin
            $display("ERROR opening selection_test.csv");
            $finish;
        end

        // Header (updated to remove fitness_sum1/2, added selecting)
        $fwrite(log_file, "test_num,clk_counter,clk,rst,start_selection,");
        for (j = 0; j < POPULATION_SIZE; j++)
            $fwrite(log_file, "fitness_values[%0d],", j);
        $fwrite(log_file, "total_fitness,lfsr_input,selected_index1,selected_index2,selection_done,");
        $fwrite(log_file, "roulette_pos1,roulette_pos2,total_fitness_zero,selected_index1_comb,selected_index2_comb,selecting");
        $fdisplay(log_file, ""); // End of line
    end

    always @(posedge clk) begin
        // Main row (updated to match header)
        $fwrite(log_file, "%0d,%0d,%b,%b,%b,", test_num, clk_counter, clk, rst, start_selection);
        for (j = 0; j < POPULATION_SIZE; j++)
            $fwrite(log_file, "%0d,", fitness_values[j]);
        $fwrite(log_file, "%h,%h,%0d,%0d,%b,", total_fitness, lfsr_input, selected_index1, selected_index2, selection_done); // total_fitness as %h for wider value
        $fwrite(log_file, "%h,%h,%b,%0d,%0d,%b",
                roulette_pos1, roulette_pos2, total_fitness_zero, selected_index1_comb, selected_index2_comb, selecting);
        $fdisplay(log_file, ""); // End of line
    end

    // Increment test_num after each pulse_selection
    always @(posedge selection_done) begin  // Changed to posedge to catch rising edge
        test_num <= test_num + 1;
    end

    final $fclose(log_file);

endmodule