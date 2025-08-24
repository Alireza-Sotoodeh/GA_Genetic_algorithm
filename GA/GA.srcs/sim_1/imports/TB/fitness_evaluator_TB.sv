`timescale 1ns / 1ps
// -----------------------------------------------------------
// 1. Interface - bundles DUT I/O signals
// -----------------------------------------------------------
interface fitness_evaluator_if #(parameter CHROMOSOME_WIDTH = 16, parameter FITNESS_WIDTH = 14)(input logic clk, rst);
    // Inputs
    logic                               start_evaluation;
    logic [CHROMOSOME_WIDTH-1:0]        chromosome;
    // Outputs
    logic [FITNESS_WIDTH-1:0]           fitness;
    logic                               evaluation_done;
endinterface

// -----------------------------------------------------------
// 2. Testbench module
// -----------------------------------------------------------
module fitness_evaluator_tb;
    // Clock
    logic CLK = 0;
    always #1 CLK = ~CLK; // 500 MHz: 2ns for each clk

    // Reset (active-high, matching your latest fitness_evaluator.sv)
    logic RST;
    initial begin
        RST = 1'b1;
        #2 RST = 1'b0;
    end

    // Interface instance
    fitness_evaluator_if intf(.clk(CLK), .rst(RST));

    // Test counters
    int error_count = 0;
    int test_count  = 0;

    // -------------------------------------------------------
    // 3. DUT instantiation
    // -------------------------------------------------------
    fitness_evaluator #(.CHROMOSOME_WIDTH(16), .FITNESS_WIDTH(14)) DUT (
        .clk                (intf.clk),
        .rst                (intf.rst),
        .start_evaluation   (intf.start_evaluation),
        .chromosome         (intf.chromosome),
        .fitness            (intf.fitness),
        .evaluation_done    (intf.evaluation_done)
    );

    // -------------------------------------------------------
    // 3.1 Signals for waveform view (assign style)
    // -------------------------------------------------------
    logic Start, Done;
    logic [15:0] ChromosomeIn;
    logic [13:0] FitnessOut;
    assign Start        = intf.start_evaluation;
    assign ChromosomeIn = intf.chromosome;
    assign FitnessOut   = intf.fitness;
    assign Done         = intf.evaluation_done;

    // -------------------------------------------------------
    // 4. Generator (manual + random)
    // -------------------------------------------------------
    task generator(input int num_tests);
        // Initial setup
        intf.start_evaluation = 1'b0;
        intf.chromosome = 16'b0;
        #10;  // Wait after reset

        // Test 1: Edge case - All zeros (fitness=0)
        $display("Test 1: All zeros chromosome");
        intf.chromosome = 16'b0000000000000000;
        @(posedge CLK);
        intf.start_evaluation = 1'b1;
        @(posedge CLK);
        intf.start_evaluation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 2: Edge case - All ones (fitness=16, no clamp since 16 < 16383)
        $display("Test 2: All ones chromosome");
        intf.chromosome = 16'b1111111111111111;
        @(posedge CLK);
        intf.start_evaluation = 1'b1;
        @(posedge CLK);
        intf.start_evaluation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 3: Single bit set (fitness=1)
        $display("Test 3: Single bit set");
        intf.chromosome = 16'b0000000000000001;
        @(posedge CLK);
        intf.start_evaluation = 1'b1;
        @(posedge CLK);
        intf.start_evaluation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 4: Half ones (8 ones, fitness=8)
        $display("Test 4: Half ones");
        intf.chromosome = 16'b1111111100000000;
        @(posedge CLK);
        intf.start_evaluation = 1'b1;
        @(posedge CLK);
        intf.start_evaluation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 5: Alternating bits (8 ones, fitness=8)
        $display("Test 5: Alternating bits");
        intf.chromosome = 16'b1010101010101010;
        @(posedge CLK);
        intf.start_evaluation = 1'b1;
        @(posedge CLK);
        intf.start_evaluation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 6: Near-max ones (15 ones)
        $display("Test 6: Near-max ones (15 ones)");
        intf.chromosome = 16'b0111111111111111;
        @(posedge CLK);
        intf.start_evaluation = 1'b1;
        @(posedge CLK);
        intf.start_evaluation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 7: Handshaking - Start held high (should not re-trigger until done)
        $display("Test 7: Start held high");
        intf.chromosome = 16'b0000000000000011;  // 2 ones
        @(posedge CLK);
        intf.start_evaluation = 1'b1;  // Hold for 3 cycles
        repeat(3) @(posedge CLK);
        intf.start_evaluation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 8: Back-to-back evaluations (second starts after first done)
        $display("Test 8: Back-to-back evaluations");
        // First eval
        intf.chromosome = 16'b0000000000001111;  // 4 ones
        @(posedge CLK);
        intf.start_evaluation = 1'b1;
        @(posedge CLK);
        intf.start_evaluation = 1'b0;
        check_result();
        // Second eval immediately after
        intf.chromosome = 16'b1111000000000000;  // 4 ones
        @(posedge CLK);
        intf.start_evaluation = 1'b1;
        @(posedge CLK);
        intf.start_evaluation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 9: Reset during evaluation (should abort and reset outputs)
        $display("Test 9: Reset during evaluation");
        intf.chromosome = 16'b1111111111111111;
        @(posedge CLK);
        intf.start_evaluation = 1'b1;
        #1ps;  // Small delay to allow NBA updates after start
        RST = 1'b1;  // Assert reset mid-evaluation (after Cycle 1 updates)
        @(posedge CLK);
        RST = 1'b0;
        #1ps;  // Allow reset deassertion to take effect
        @(posedge CLK);
        #1ps;  // Allow final updates
        if (intf.fitness !== 14'd0 || intf.evaluation_done !== 1'b0) begin
            $display("ERROR: Reset did not clear outputs! Fitness: %0d, Done: %0d", intf.fitness, intf.evaluation_done);
            error_count++;
        end else begin
            $display("PASS: Reset cleared outputs correctly");
        end
        test_count++;
        @(posedge CLK);

        // Test 10: No start (idle, ensure done=0)
        $display("Test 10: Idle (no start)");
        @(posedge CLK);
        #1ps;  // Allow updates
        if (intf.evaluation_done !== 1'b0) begin
            $display("ERROR: evaluation_done high in idle!");
            error_count++;
        end else begin
            $display("PASS: Idle state correct");
        end
        test_count++;
        @(posedge CLK);

        // Randomized tests
        $display("Starting random tests...");
        for (int i = 0; i < num_tests; i++) begin
            // Apply randomized inputs
            intf.chromosome = $urandom();

            @(posedge CLK);
            intf.start_evaluation = 1'b1;
            @(posedge CLK);
            intf.start_evaluation = 1'b0;

            // Occasionally hold start high for handshaking test (every 10th test)
            if (i % 10 == 0) begin
                intf.start_evaluation = 1'b1;  // Hold for extra cycle
                @(posedge CLK);
                intf.start_evaluation = 1'b0;
            end

            check_result();
            @(posedge CLK);

            // Occasionally add a back-to-back random eval (every 20th test)
            if (i % 20 == 0) begin
                $display("Adding back-to-back random eval");
                intf.chromosome = $urandom();
                @(posedge CLK);
                intf.start_evaluation = 1'b1;
                @(posedge CLK);
                intf.start_evaluation = 1'b0;
                check_result();
                @(posedge CLK);
            end
        end
    endtask

    // -------------------------------------------------------
    // 5. check_result
    // -------------------------------------------------------
    logic [13:0] expected_fitness;
    task automatic check_result();
        // Compute expected fitness based on current chromosome (mimic DUT: popcount with clamp)
        int raw_count = $countones(intf.chromosome);
        // Corrected clamp for FITNESS_WIDTH=14 (max value 16383)
        expected_fitness = (raw_count > {14{1'b1}}) ? {14{1'b1}} : raw_count[13:0];
    
        // Small delay to ensure NBA updates have propagated before checking
        #1ps;
    
        // At this point (after second clock NBA), evaluation_done should be high, and fitness should match
        if (intf.evaluation_done !== 1'b1) begin
            $display("ERROR @ time = %0t: Test %0d - evaluation_done not asserted! Actual: %0b | Chromosome: %h | Start_Evaluation: %b | Fitness: %0d | Expected_Fitness: %0d | Reset: %b",
                     $time, test_count + 1, intf.evaluation_done, intf.chromosome, intf.start_evaluation, intf.fitness, expected_fitness, intf.rst);
            error_count++;
        end
        if (intf.fitness !== expected_fitness) begin
            $display("ERROR @ time = %0t: Test %0d - Fitness mismatch! Actual: %0d | Expected: %0d | Chromosome: %h | Start_Evaluation: %b | Evaluation_Done: %0b | Reset: %b",
                     $time, test_count + 1, intf.fitness, expected_fitness, intf.chromosome, intf.start_evaluation, intf.evaluation_done, intf.rst);
            error_count++;
        end
    
        // Advance to next cycle
        @(posedge CLK);
        // Small delay to ensure NBA updates have propagated before checking deassertion
        #1ps;
    
        if (intf.evaluation_done !== 1'b0) begin
            $display("ERROR @ time = %0t: Test %0d - evaluation_done did not deassert after pulse! Actual: %0b | Chromosome: %h | Start_Evaluation: %b | Fitness: %0d | Expected_Fitness: %0d | Reset: %b",
                     $time, test_count + 1, intf.evaluation_done, intf.chromosome, intf.start_evaluation, intf.fitness, expected_fitness, intf.rst);
            error_count++;
        end
    
        test_count++;
    endtask
        // -------------------------------------------------------
    // Main Test Flow
    // -------------------------------------------------------
    initial begin
        intf.start_evaluation = 0;
        intf.chromosome = 0;
        @(negedge RST);
        generator(100);
        $display("Test finished. Ran %0d tests, errors = %0d", test_count, error_count);
        if (error_count == 0) $display("TEST PASSED");
        else $display("TEST FAILED");
        $finish;
        $stop;
    end

endmodule