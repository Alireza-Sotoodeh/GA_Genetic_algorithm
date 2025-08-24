`timescale 1ns / 1ps
// -----------------------------------------------------------
// 1. Interface - bundles DUT I/O signals
// -----------------------------------------------------------
interface population_memory_if #(parameter CHROMOSOME_WIDTH = 16, parameter FITNESS_WIDTH = 14, parameter POPULATION_SIZE = 16, parameter ADDR_WIDTH = $clog2(POPULATION_SIZE))(input logic clk, rst);
    // Inputs
    logic                               start_write;
    logic [CHROMOSOME_WIDTH-1:0]        child_in;
    logic [FITNESS_WIDTH-1:0]           child_fitness_in;
    logic [ADDR_WIDTH-1:0]              read_addr1;
    logic [ADDR_WIDTH-1:0]              read_addr2;
    logic                               request_fitness_values;
    logic                               request_total_fitness;
    // Outputs
    logic [CHROMOSOME_WIDTH-1:0]        parent1_out;
    logic [CHROMOSOME_WIDTH-1:0]        parent2_out;
    logic [FITNESS_WIDTH-1:0]           fitness_values_out [POPULATION_SIZE-1:0];
    logic [FITNESS_WIDTH-1:0]           total_fitness_out;
    logic                               write_done;
endinterface

// -----------------------------------------------------------
// 2. Testbench module
// -----------------------------------------------------------
module population_memory_tb;
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
    population_memory_if intf(.clk(CLK), .rst(RST));

    // Test counters
    int error_count = 0;
    int test_count  = 0;

    // LFSR control signals (kept for structure, used for random generation in tests)
    logic start_lfsr = 0;
    logic load_seed = 0;
    logic [15:0] seed_in = 16'hACE1;
    logic [15:0] lfsr_output;  // Output from LFSR for random values

    // -------------------------------------------------------
    // 3. DUT instantiation + LFSR Instantiation (LFSR kept for random tests, even if not directly connected to DUT)
    // -------------------------------------------------------
    population_memory #(.CHROMOSOME_WIDTH(16), .FITNESS_WIDTH(14), .POPULATION_SIZE(16), .ADDR_WIDTH(4)) DUT (
        .clk                     (intf.clk),
        .rst                     (intf.rst),
        .start_write             (intf.start_write),
        .child_in                (intf.child_in),
        .child_fitness_in        (intf.child_fitness_in),
        .read_addr1              (intf.read_addr1),
        .read_addr2              (intf.read_addr2),
        .request_fitness_values  (intf.request_fitness_values),
        .request_total_fitness   (intf.request_total_fitness),
        .parent1_out             (intf.parent1_out),
        .parent2_out             (intf.parent2_out),
        .fitness_values_out      (intf.fitness_values_out),
        .total_fitness_out       (intf.total_fitness_out),
        .write_done              (intf.write_done)
    );

    // LSFR (kept for structure and used in random tests to generate child_in and fitness)
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
        .random_out(lfsr_output)
    );

    // -------------------------------------------------------
    // 3.1 Signals for waveform view (assign style)
    // -------------------------------------------------------
    logic StartWrite, WriteDone;
    logic [15:0] ChildIn;
    logic [13:0] ChildFitnessIn;
    logic [3:0] ReadAddr1;
    logic [3:0] ReadAddr2;
    logic ReqFitnessValues;
    logic ReqTotalFitness;
    logic [15:0] Parent1Out;
    logic [15:0] Parent2Out;
    logic [13:0] TotalFitnessOut;
    assign StartWrite        = intf.start_write;
    assign WriteDone         = intf.write_done;
    assign ChildIn           = intf.child_in;
    assign ChildFitnessIn    = intf.child_fitness_in;
    assign ReadAddr1         = intf.read_addr1;
    assign ReadAddr2         = intf.read_addr2;
    assign ReqFitnessValues  = intf.request_fitness_values;
    assign ReqTotalFitness   = intf.request_total_fitness;
    assign Parent1Out        = intf.parent1_out;
    assign Parent2Out        = intf.parent2_out;
    assign TotalFitnessOut   = intf.total_fitness_out;

    // -------------------------------------------------------
    // 3.2 Shadow Model Declarations (module-level)
    // -------------------------------------------------------
    logic [15:0] shadow_population [16];
    logic [13:0] shadow_fitness [16];
    logic [14:0] shadow_total_fitness;  // Widened for overflow detection

    // Initialize shadow model on reset
    always @(posedge RST) begin
        shadow_population = '{default: '0};
        shadow_fitness = '{default: '0};
        shadow_total_fitness = '0;
    end

    // -------------------------------------------------------
    // 3.3 update_shadow_memory Task
    // -------------------------------------------------------
    task automatic update_shadow_memory(input [15:0] child, input [13:0] fitness);
        // Local variables (automatic: reset each call)
        logic [3:0] insert_pos = 15;  // Default: worst
        logic found = 0;
        logic [13:0] old_fitness = shadow_fitness[15];
        
        // Find insertion position (mirrors DUT comb logic)
        for (int i = 0; i < 16; i++) begin
            if (fitness > shadow_fitness[i]) begin
                insert_pos = i;
                found = 1;
                break;
            end
        end
        
        // Update total fitness with saturation (mirrors DUT ff logic, using widened bit)
        shadow_total_fitness = (shadow_total_fitness - old_fitness) + fitness;
        if (shadow_total_fitness[14]) begin
            shadow_total_fitness = {1'b0, {14{1'b1}}};  // Saturate to 14'h3FFF
        end
        
        // Update arrays (mirrors DUT insertion/shift)
        if (found) begin
            // Shift elements down
            for (int j = 15; j > insert_pos; j--) begin
                shadow_population[j] = shadow_population[j-1];
                shadow_fitness[j] = shadow_fitness[j-1];
            end
            shadow_population[insert_pos] = child;
            shadow_fitness[insert_pos] = fitness;
        end else begin
            // Replace worst
            shadow_population[15] = child;
            shadow_fitness[15] = fitness;
        end
    endtask

    // -------------------------------------------------------
    // 4. Generator (manual + random) - Updated to call update_shadow_memory after each write
    // -------------------------------------------------------
    task generator(input int num_tests);

        // Manual tests covering all sensitive and edge cases

        // Test 1: Reset state - all zeros, requests return zeros
        @(posedge CLK);
        intf.request_fitness_values = 1'b1;
        intf.request_total_fitness = 1'b1;
        @(posedge CLK);
        check_result();  // Expect all fitness_out=0, total=0
        intf.request_fitness_values = 1'b0;
        intf.request_total_fitness = 1'b0;
        @(posedge CLK);

        // Test 2: Write first child (insert at pos 0 since empty)
        intf.child_in = 16'hAAAA;
        intf.child_fitness_in = 14'h1000;
        start_lfsr = 1'b0;
        @(posedge CLK);
        intf.start_write = 1'b1;
        @(posedge CLK);
        intf.start_write = 1'b0;
        repeat (18) begin  // Max cycles + margin
            if (intf.write_done) break;
            @(posedge CLK);
        end
        if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
        else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        check_result();  // Expect population[0]=AAAA, fitness[0]=1000, total=1000
        @(posedge CLK);

        // Test 3: Write second child better than first (insert at 0, shift)
        intf.child_in = 16'hBBBB;
        intf.child_fitness_in = 14'h2000;
        @(posedge CLK);
        intf.start_write = 1'b1;
        @(posedge CLK);
        intf.start_write = 1'b0;
        repeat (18) begin
            if (intf.write_done) break;
            @(posedge CLK);
        end
        if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
        else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        check_result();  // Expect [0]=BBBB:2000, [1]=AAAA:1000, total=3000
        @(posedge CLK);

        // Test 4: Initialize a full population with descending fitness
        for (int i = 2; i < 16; i++) begin
            intf.child_in = 16'h0000 + i;
            intf.child_fitness_in = 14'h3FFF - i;
            @(posedge CLK);
            intf.start_write = 1'b1;
            @(posedge CLK);
            intf.start_write = 1'b0;
            repeat (18) begin
                if (intf.write_done) break;
                @(posedge CLK);
            end
            if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
            else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        end
        check_result();  // After filling, check sorted and total
        @(posedge CLK);

        // Test 5: Write child better than some (insert in middle, shift)
        intf.child_in = 16'hCCCC;
        intf.child_fitness_in = 14'h3FFA;  // Better than some
        @(posedge CLK);
        intf.start_write = 1'b1;
        @(posedge CLK);
        intf.start_write = 1'b0;
        repeat (18) begin
            if (intf.write_done) break;
            @(posedge CLK);
        end
        if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
        else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        check_result();
        @(posedge CLK);

        // Test 6: Write child worse than all (replace worst)
        intf.child_in = 16'hDDDD;
        intf.child_fitness_in = 14'h0001;
        @(posedge CLK);
        intf.start_write = 1'b1;
        @(posedge CLK);
        intf.start_write = 1'b0;
        repeat (18) begin
            if (intf.write_done) break;
            @(posedge CLK);
        end
        if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
        else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        check_result();
        @(posedge CLK);

        // Test 7: Read parents from specific addresses
        intf.read_addr1 = 4'h0;
        intf.read_addr2 = 4'h1;
        @(posedge CLK);
        check_result();  // Check parent1_out and parent2_out match internal
        @(posedge CLK);

        // Test 8: Request fitness_values and total_fitness
        intf.request_fitness_values = 1'b1;
        intf.request_total_fitness = 1'b1;
        @(posedge CLK);
        check_result();
        intf.request_fitness_values = 1'b0;
        intf.request_total_fitness = 1'b0;
        @(posedge CLK);

        // Test 9: Overflow in total_fitness (all max fitness, add another max)
        for (int i = 0; i < 16; i++) begin
            intf.child_in = 16'hFFFF;
            intf.child_fitness_in = 14'h3FFF;
            @(posedge CLK);
            intf.start_write = 1'b1;
            @(posedge CLK);
            intf.start_write = 1'b0;
            repeat (18) begin
                if (intf.write_done) break;
                @(posedge CLK);
            end
            if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
            else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        end
        // Add one more to trigger saturation
        intf.child_in = 16'hFFFF;
        intf.child_fitness_in = 14'h3FFF;
        @(posedge CLK);
        intf.start_write = 1'b1;
        @(posedge CLK);
        intf.start_write = 1'b0;
        repeat (18) begin
            if (intf.write_done) break;
            @(posedge CLK);
        end
        if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
        else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        check_result();  // Expect saturated total
        @(posedge CLK);

        // Test 10: Tie in fitness (insert after equal)
        // Set all to same fitness, write equal
        for (int i = 0; i < 16; i++) begin
            intf.child_in = 16'h1111 + i;
            intf.child_fitness_in = 14'h1000;
            @(posedge CLK);
            intf.start_write = 1'b1;
            @(posedge CLK);
            intf.start_write = 1'b0;
            repeat (18) begin
                if (intf.write_done) break;
                @(posedge CLK);
            end
            if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
            else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        end
        intf.child_in = 16'h2222;
        intf.child_fitness_in = 14'h1000;  // Equal, should not insert (since > not >=)
        @(posedge CLK);
        intf.start_write = 1'b1;
        @(posedge CLK);
        intf.start_write = 1'b0;
        repeat (18) begin
            if (intf.write_done) break;
            @(posedge CLK);
        end
        if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
        else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        check_result();  // Expect replace worst
        @(posedge CLK);

        // Test 11: Write with fitness=0
        intf.child_in = 16'h0000;
        intf.child_fitness_in = 14'h0000;
        @(posedge CLK);
        intf.start_write = 1'b1;
        @(posedge CLK);
        intf.start_write = 1'b0;
        repeat (18) begin
            if (intf.write_done) break;
            @(posedge CLK);
        end
        if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
        else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        check_result();
        @(posedge CLK);

        // Test 12: Simultaneous read and write (check no conflict)
        intf.read_addr1 = 4'h5;
        intf.read_addr2 = 4'h6;
        intf.child_in = 16'hEEEE;
        intf.child_fitness_in = 14'h3000;
        @(posedge CLK);
        intf.start_write = 1'b1;
        @(posedge CLK);
        intf.start_write = 1'b0;
        repeat (18) begin
            if (intf.write_done) break;
            @(posedge CLK);
        end
        if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
        else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        check_result();
        @(posedge CLK);

        // Test 13: Request while writing
        intf.request_fitness_values = 1'b1;
        intf.request_total_fitness = 1'b1;
        intf.child_in = 16'hFFFF;
        intf.child_fitness_in = 14'h3FFF;
        @(posedge CLK);
        intf.start_write = 1'b1;
        @(posedge CLK);
        intf.start_write = 1'b0;
        repeat (18) begin
            if (intf.write_done) break;
            @(posedge CLK);
        end
        if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
        else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        check_result();
        intf.request_fitness_values = 1'b0;
        intf.request_total_fitness = 1'b0;
        @(posedge CLK);

        // Test 14: Multiple writes in sequence
        for (int i = 0; i < 5; i++) begin
            intf.child_in = 16'hABCD + i;
            intf.child_fitness_in = 14'h2000 + i;
            @(posedge CLK);
            intf.start_write = 1'b1;
            @(posedge CLK);
            intf.start_write = 1'b0;
            repeat (18) begin
                if (intf.write_done) break;
                @(posedge CLK);
            end
            if (!intf.write_done) $display("WARNING: Timeout waiting for done in test");
            else update_shadow_memory(intf.child_in, intf.child_fitness_in);
        end
        check_result();
        @(posedge CLK);

        // Randomized tests
        start_lfsr = 1'b1; // Enable LFSR for random tests
        for (int i = 0; i < num_tests; i++) begin
            // Apply randomized inputs
            intf.child_in = lfsr_output;  // Use LFSR for child_in
            intf.child_fitness_in = lfsr_output[13:0];  // Random fitness
            @(posedge CLK);
            intf.start_write = 1'b1;
            @(posedge CLK);
            intf.start_write = 1'b0;
            // Wait for DUT to finish
            repeat (18) begin  // POPULATION_SIZE + 2
                if (intf.write_done) break;
                @(posedge CLK);
            end
            if (!intf.write_done) begin
                $display("ERROR: Timeout waiting for done in random test %d", i);
                error_count++;  // Optional: count timeout as error
            end else begin
                update_shadow_memory(intf.child_in, intf.child_fitness_in);
            end
            // Random read addrs
            intf.read_addr1 = $urandom % 16;
            intf.read_addr2 = $urandom % 16;
            // Random requests
            intf.request_fitness_values = $urandom % 2;
            intf.request_total_fitness = $urandom % 2;
            @(posedge CLK);
            check_result();
            @(posedge CLK);
            // Deassert requests
            intf.request_fitness_values = 1'b0;
            intf.request_total_fitness = 1'b0;
        end
    endtask

    // -------------------------------------------------------
    // 7. check_result - Updated to use shadow model
    // -------------------------------------------------------
    task automatic check_result();
        // Local constants for sizing
        localparam int PSIZE = 16;
        localparam int CW    = 16;
        localparam int FW    = 14;

        // Expected values derived from shadow model
        logic [FW-1:0] exp_total_out;
        logic [CW-1:0] exp_parent1;
        logic [CW-1:0] exp_parent2;
        logic [FW-1:0] exp_fitness_out [PSIZE-1:0];
        logic exp_done = 1'b0;  // Expect 0 post-pulse (checks happen after write_done deasserts)

        // Compute expected outputs based on current requests and shadow state
        exp_parent1 = shadow_population[intf.read_addr1];
        exp_parent2 = shadow_population[intf.read_addr2];
        if (intf.request_fitness_values) begin
            exp_fitness_out = shadow_fitness;
        end else begin
            exp_fitness_out = '{default: '0};
        end
        if (intf.request_total_fitness) begin
            exp_total_out = shadow_total_fitness[FW-1:0];  // Truncate widened bit
        end else begin
            exp_total_out = '0;
        end

        // Count & check
        test_count++;
        if ((exp_parent1 !== intf.parent1_out) || (exp_parent2 !== intf.parent2_out) ||
            (exp_fitness_out !== intf.fitness_values_out) || (exp_total_out !== intf.total_fitness_out) ||
            (intf.write_done !== exp_done)) begin
            error_count++;
            $display("------------------------------------------------------------");
            $display("ERROR @Time=%0t: Test %0d", $time, test_count);
            $display("  Exp Parent1     = %h", exp_parent1);
            $display("  DUT Parent1     = %h", intf.parent1_out);
            $display("  Exp Parent2     = %h", exp_parent2);
            $display("  DUT Parent2     = %h", intf.parent2_out);
            $display("  Exp Total       = %h", exp_total_out);
            $display("  DUT Total       = %h", intf.total_fitness_out);
            $display("  Exp Done        = %b", exp_done);
            $display("  DUT Done        = %b", intf.write_done);
            $display("  Child In        = %h", intf.child_in);
            $display("  Child Fitness   = %h", intf.child_fitness_in);
            $display("  Read Addr1      = %h", intf.read_addr1);
            $display("  Read Addr2      = %h", intf.read_addr2);
            $display("  Req Fitness     = %b", intf.request_fitness_values);
            $display("  Req Total       = %b", intf.request_total_fitness);
            $display("  Fitness Out: ");
            for (int i = 0; i < 16; i++) $display("    [%0d] = %h (Exp: %h)", i, intf.fitness_values_out[i], exp_fitness_out[i]);
            $display("  NOTE: If Done mismatch, check if wait was sufficient");  // Retained debug note
            $display("------------------------------------------------------------");
        end
    endtask

    // -------------------------------------------------------
    // Main Test Flow
    // -------------------------------------------------------
    initial begin
        intf.start_write = 0;
        intf.child_in = 0;
        intf.child_fitness_in = 0;
        intf.read_addr1 = 0;
        intf.read_addr2 = 0;
        intf.request_fitness_values = 0;
        intf.request_total_fitness = 0;
        @(negedge RST);
        generator(100);
        $display("Test finished. Ran %0d tests, errors = %0d", test_count, error_count);
        if (error_count==0) $display("TEST PASSED");
        else $display("TEST FAILED");
        $finish;
        $stop;
    end
endmodule