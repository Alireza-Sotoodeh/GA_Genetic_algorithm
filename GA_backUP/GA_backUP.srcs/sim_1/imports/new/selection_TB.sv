`timescale 1ns / 1ps
// -----------------------------------------------------------
// 1. Interface - bundles DUT I/O signals
// -----------------------------------------------------------
interface selection_if #(parameter POPULATION_SIZE = 16, parameter ADDR_WIDTH = $clog2(POPULATION_SIZE), parameter FITNESS_WIDTH = 14, parameter LFSR_WIDTH = 16)(input logic clk, rst);
    // Inputs
    logic                               start_selection;
    logic [FITNESS_WIDTH-1:0]           fitness_values [POPULATION_SIZE-1:0];
    logic [FITNESS_WIDTH-1:0]           total_fitness;
    logic [LFSR_WIDTH-1:0]              lfsr_input;
    // Outputs
    logic [ADDR_WIDTH-1:0]              selected_index1;
    logic [ADDR_WIDTH-1:0]              selected_index2;
    logic                               selection_done;
endinterface

// -----------------------------------------------------------
// 2. Testbench module
// -----------------------------------------------------------
module selection_tb;
    // Clock
    logic CLK = 0;
    always #1 CLK = ~CLK; // 500 MHz: 2ns for each clk

    // Reset
    logic RST;
    initial begin
        RST = 1'b1;
        #2 RST = 1'b0;
    end

    // Interface instance
    selection_if intf(.clk(CLK), .rst(RST));

    // Test counters
    int error_count = 0;
    int test_count  = 0;
    // Expected value
    logic [3:0] expected_index1;
    logic [3:0] expected_index2;

    // LFSR control signals
    logic start_lfsr = 0;
    logic load_seed = 0;
    logic [15:0] seed_in = 16'hACE1;

    // -------------------------------------------------------
    // 3. DUT instantiation + LFSR Instantiation
    // -------------------------------------------------------
    selection #(.POPULATION_SIZE(16), .ADDR_WIDTH(4), .FITNESS_WIDTH(14), .LFSR_WIDTH(16)) DUT (
        .clk               (intf.clk),
        .rst               (intf.rst),
        .start_selection   (intf.start_selection),
        .fitness_values    (intf.fitness_values),
        .total_fitness     (intf.total_fitness),
        .lfsr_input        (intf.lfsr_input),
        .selected_index1   (intf.selected_index1),
        .selected_index2   (intf.selected_index2),
        .selection_done    (intf.selection_done)
    );

    // LSFR
    lfsr_SudoRandom #(
        .WIDTH1(16),
        .WIDTH2(15),
        .WIDTH3(14),
        .WIDTH4(13),
        .defualtSeed1(16'hACE1),
        .defualtSeed2(15'h3BEE),
        .defualtSeed3(14'h2BAD),
        .defualtSeed4(13'h1DAD)
    ) lfsr_inst (
        .clk(CLK),
        .rst(RST),
        .start_lfsr(start_lfsr),
        .seed_in(seed_in),
        .load_seed(load_seed),
        .random_out(intf.lfsr_input)
    );

    // -------------------------------------------------------
    // 3.1 Signals for waveform view (assign style)
    // -------------------------------------------------------
    logic Start, Done;
    logic [13:0] TotalFitness;
    logic [15:0] LfsrInp;
    logic [3:0] SelectedIndex1;
    logic [3:0] SelectedIndex2;
    assign Start           = intf.start_selection;
    assign TotalFitness    = intf.total_fitness;
    assign LfsrInp         = intf.lfsr_input;
    assign SelectedIndex1  = intf.selected_index1;
    assign SelectedIndex2  = intf.selected_index2;
    assign Done            = intf.selection_done;

    // -------------------------------------------------------
    // 4. Generator (manual + random)
    // -------------------------------------------------------
    task generator(input int num_tests);

        // Manual tests covering all sensitive and edge cases

        // Test 1: Total fitness = 0 (uniform random selection)
        for (int i = 0; i < 16; i++) intf.fitness_values[i] = 14'h0000;
        intf.total_fitness = 14'h0000;
        intf.lfsr_input = 16'h0005;  // Should select 5 % 16 = 5
        start_lfsr = 1'b0;
        @(posedge CLK);
        intf.start_selection = 1'b1;
        @(posedge CLK);
                intf.start_selection = 1'b0;
        repeat (18) begin  // Max cycles + margin POPULATION_SIZE + 2
            if (intf.selection_done) break;
            @(posedge CLK);
        end
        if (!intf.selection_done) $display("WARNING: Timeout waiting for done in test");
        repeat (18) begin  // Max cycles + margin POPULATION_SIZE + 2
            if (intf.selection_done) break;
            @(posedge CLK);
        end
        if (!intf.selection_done) $display("WARNING: Timeout waiting for done in test");
        check_result();
        @(posedge CLK);

        // Test 2: Total fitness = 0, LSFR max (edge: 65535 % 16 = 15)
        for (int i = 0; i < 16; i++) intf.fitness_values[i] = 14'h0000;
        intf.total_fitness = 14'h0000;
        intf.lfsr_input = 16'hFFFF;
        start_lfsr = 1'b0;
        @(posedge CLK);
        intf.start_selection = 1'b1;
        @(posedge CLK);
        intf.start_selection = 1'b0;
        repeat (18) begin  // Max cycles + margin POPULATION_SIZE + 2
            if (intf.selection_done) break;
            @(posedge CLK);
        end
        if (!intf.selection_done) $display("WARNING: Timeout waiting for done in test");
        check_result();
        @(posedge CLK);

        // Test 3: Total fitness = 0, LSFR=0 (select 0)
        for (int i = 0; i < 16; i++) intf.fitness_values[i] = 14'h0000;
        intf.total_fitness = 14'h0000;
        intf.lfsr_input = 16'h0000;
        start_lfsr = 1'b0;
        @(posedge CLK);
        intf.start_selection = 1'b1;
        @(posedge CLK);
        intf.start_selection = 1'b0;
        repeat (18) begin  // Max cycles + margin POPULATION_SIZE + 2
            if (intf.selection_done) break;
            @(posedge CLK);
        end
        if (!intf.selection_done) $display("WARNING: Timeout waiting for done in test");
        check_result();
        @(posedge CLK);

// Test 11: Max total_fitness, LSFR=0 (select 0)
        for (int i = 0; i < 16; i++) intf.fitness_values[i] = 14'h3FFF;
        intf.total_fitness = 14'h3FF0 * 16 / 16;  // Approx max, but careful with width
        intf.lfsr_input = 16'h0000;
        start_lfsr = 1'b0;
        @(posedge CLK);
        intf.start_selection = 1'b1;
        @(posedge CLK);
        intf.start_selection = 1'b0;
        repeat (18) begin  // Max cycles + margin POPULATION_SIZE + 2
            if (intf.selection_done) break;
            @(posedge CLK);
        end
        if (!intf.selection_done) $display("WARNING: Timeout waiting for done in test");
        check_result();
        @(posedge CLK);

        // Test 12: Invalid uniform (total=0, LSFR >= POPULATION_SIZE, but % handles)
        for (int i = 0; i < 16; i++) intf.fitness_values[i] = 14'h0000;
        intf.total_fitness = 14'h0000;
        intf.lfsr_input = 16'h0010;  // 16 % 16 = 0
        start_lfsr = 1'b0;
        @(posedge CLK);
        intf.start_selection = 1'b1;
        @(posedge CLK);
        intf.start_selection = 1'b0;
        repeat (18) begin  // Max cycles + margin POPULATION_SIZE + 2
            if (intf.selection_done) break;
            @(posedge CLK);
        end
        if (!intf.selection_done) $display("WARNING: Timeout waiting for done in test");
        check_result();
        @(posedge CLK);

        // Test 13: Mixed fitness, LSFR causes break in loop
        intf.fitness_values[0] = 14'h0005;
        intf.fitness_values[1] = 14'h000A;
        for (int i = 2; i < 16; i++) intf.fitness_values[i] = 14'h0000;
        intf.total_fitness = 14'h000F;
        intf.lfsr_input = 16'h0007;  // Scaled to hit index 1
        start_lfsr = 1'b0;
        @(posedge CLK);
        intf.start_selection = 1'b1;
        @(posedge CLK);
        intf.start_selection = 1'b0;
        repeat (18) begin  // Max cycles + margin POPULATION_SIZE + 2
            if (intf.selection_done) break;
            @(posedge CLK);
        end
        if (!intf.selection_done) $display("WARNING: Timeout waiting for done in test");
        check_result();
        @(posedge CLK);

        // Test 14: Total=1, single fitness=1 at random index
        for (int i = 0; i < 16; i++) intf.fitness_values[i] = 14'h0000;
        intf.fitness_values[7] = 14'h0001;
        intf.total_fitness = 14'h0001;
        intf.lfsr_input = 16'hFFFF;  // Should select 7
        start_lfsr = 1'b0;
        @(posedge CLK);
        intf.start_selection = 1'b1;
        @(posedge CLK);
        intf.start_selection = 1'b0;
        repeat (18) begin  // Max cycles + margin POPULATION_SIZE + 2
            if (intf.selection_done) break;
            @(posedge CLK);
        end
        if (!intf.selection_done) $display("WARNING: Timeout waiting for done in test");
        check_result();
        @(posedge CLK);

        // Randomized tests
        start_lfsr = 1'b1; // Enable LFSR for random tests
        for (int i = 0; i < num_tests; i++) begin
            // Apply randomized inputs
            for (int j = 0; j < 16; j++) intf.fitness_values[j] = $urandom % (1 << 14);  // Random fitness 0 to 2^14-1
            intf.total_fitness = 0;
            for (int j = 0; j < 16; j++) intf.total_fitness += intf.fitness_values[j];  // Consistent total
            // Wait for LFSR to stabilize
            @(posedge CLK);
            intf.start_selection = 1'b1;
            @(posedge CLK);
            intf.start_selection = 1'b0;
            // NEW: Wait for DUT to finish
            repeat (18) begin  //POPULATION_SIZE + 2
                if (intf.selection_done) break;
                @(posedge CLK);
            end
            if (!intf.selection_done) begin
                $display("ERROR: Timeout waiting for done in random test %d", i);
                error_count++;  // Optional: count timeout as error
            end
            check_result();
            @(posedge CLK);
        end
    endtask
    // -------------------------------------------------------
    // 7. check_result - Modified version
    // -------------------------------------------------------
    task automatic check_result();
        // Local constants for sizing
        localparam int PSIZE = 16;
        localparam int FW    = 14;
        localparam int LW    = 16;

        // Temporaries
        logic [FW + LW - 1:0] roulette_position1;
        logic [FW + LW - 1:0] roulette_position2;
        logic [FW-1:0] fitness_sum1;
        logic [FW-1:0] fitness_sum2;
        logic total_fitness_zero;
        logic [3:0] calc_index1;
        logic [3:0] calc_index2;
        logic done_expected;

        // Defaults
        fitness_sum1 = '0;
        fitness_sum2 = '0;
        calc_index1 = '0;
        calc_index2 = '0;
        expected_index1 = '0;
        expected_index2 = '0;
        total_fitness_zero = (intf.total_fitness == '0);

        // Calculate roulette_position exactly as DUT
        if (total_fitness_zero) begin
            roulette_position1 = intf.lfsr_input % PSIZE;
            roulette_position2 = (intf.lfsr_input ^ (intf.lfsr_input >> (LW/2))) % PSIZE;
        end else begin
            logic [FW + LW - 1:0] product1;
            logic [FW + LW - 1:0] product2;
            product1 = intf.lfsr_input * intf.total_fitness;
            roulette_position1 = product1 >> LW;
            product2 = (intf.lfsr_input ^ (intf.lfsr_input >> 8)) * intf.total_fitness;  // Modify for second different value
            roulette_position2 = product2 >> LW;
        end

        // Combinational loop for selection exactly as DUT
        for (int i = 0; i < PSIZE; i++) begin
            if (fitness_sum1 + intf.fitness_values[i] > roulette_position1) begin  // Strict > to match DUT
                calc_index1 = i[3:0];
                break;
            end
            fitness_sum1 += intf.fitness_values[i];
        end
        // Force last index if no match (edge case)
        if (fitness_sum1 < roulette_position1) begin
            calc_index1 = PSIZE - 1;
        end

        for (int i = 0; i < PSIZE; i++) begin
            if (fitness_sum2 + intf.fitness_values[i] > roulette_position2) begin  // Strict > to match DUT
                calc_index2 = i[3:0];
                break;
            end
            fitness_sum2 += intf.fitness_values[i];
        end
        // Force last index if no match (edge case)
        if (fitness_sum2 < roulette_position2) begin
            calc_index2 = PSIZE - 1;
        end

        // Ensure different indices (re-assign if same; simple: swap with next if equal)
        if (calc_index1 == calc_index2) begin
            calc_index2 = (calc_index2 + 1) % PSIZE;
        end
        expected_index1 = calc_index1;
        expected_index2 = calc_index2;

        // Expected done signal (always 1 after wait)
        done_expected = 1'b1;  // Based on DUT: pulses after completion

        // Count & check
        test_count++;
        if ((expected_index1 !== intf.selected_index1) || (expected_index2 !== intf.selected_index2) || (intf.selection_done !== done_expected)) begin
            error_count++;
            $display("------------------------------------------------------------");
            $display("ERROR @Time=%0t: Test %0d", $time, test_count);
            $display("  Exp Index1      = %h", expected_index1);
            $display("  DUT Index1      = %h", intf.selected_index1);
            $display("  Exp Index2      = %h", expected_index2);
            $display("  DUT Index2      = %h", intf.selected_index2);
            $display("  Exp Done        = %b", done_expected);
            $display("  DUT Done        = %b", intf.selection_done);
            $display("  Total Fitness   = %h", intf.total_fitness);
            $display("  LSFR_input      = %h", intf.lfsr_input);
            $display("  Roulette Pos1   = %h", roulette_position1);
            $display("  Roulette Pos2   = %h", roulette_position2);
            $display("  Fitness Sum1    = %h", fitness_sum1);
            $display("  Fitness Sum2    = %h", fitness_sum2);
            $display("  Zero Total?     = %b", total_fitness_zero);
            $display("  Fitness Values: ");
            for (int i = 0; i < 16; i++) $display("    [%0d] = %h", i, intf.fitness_values[i]);
            $display("  NOTE: If Done mismatch, check if wait was sufficient");  // NEW: Added debug note
            $display("------------------------------------------------------------");
        end
    endtask
    // -------------------------------------------------------
    // Main Test Flow
    // -------------------------------------------------------
    initial begin
        intf.start_selection = 0;
        for (int i = 0; i < 16; i++) intf.fitness_values[i] = 0;
        intf.total_fitness = 0;
        intf.lfsr_input = 0;
        @(negedge RST);
        generator(100);
        $display("Test finished. Ran %0d tests, errors = %0d", test_count, error_count);
        if (error_count==0) $display("TEST PASSED");
        else $display("TEST FAILED");
        $finish;
        $stop;
    end
endmodule