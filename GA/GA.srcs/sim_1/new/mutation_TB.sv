`timescale 1ns / 1ps
// -----------------------------------------------------------
// 1. Interface - bundles DUT I/O signals
// -----------------------------------------------------------
interface mutation_if #(parameter CHROMOSOME_WIDTH = 16, parameter LSFR_WIDTH = 16)(input logic clk, rst);
    // Inputs
    logic                               start_mutation;
    logic [CHROMOSOME_WIDTH-1:0]        child_in;
    logic [2:0]                         mutation_mode;  // 000: Bit-Flip, 001: Bit-Swap, 010: Inversion, 011: Scramble, 100: Combined (Flip + Swap)
    logic [7:0]                         mutation_rate;  // 0-255, controls probability/intensity
    logic [LSFR_WIDTH-1:0]              LSFR_input;     // Random input from LFSR (now 16-bit)
    // Outputs
    logic [CHROMOSOME_WIDTH-1:0]        child_out;
    logic                               mutation_done;
endinterface

// -----------------------------------------------------------
// 2. Testbench module
// -----------------------------------------------------------
module mutation_tb;
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
    mutation_if intf(.clk(CLK), .rst(RST));

    // Test counters
    int error_count = 0;
    int test_count  = 0;
    // Expected value
    logic [15:0] expected_child;

    // LFSR control signals
    logic start_lfsr = 0;
    logic load_seed = 0;
    logic [15:0] seed_in = 16'hACE1;

    // ADDED: Track current test number for special handling (e.g., reset test)
    int current_test_num = 0;

    // -------------------------------------------------------
    // 3. DUT instantiation + LFSR Instantiation
    // -------------------------------------------------------
    mutation #(.CHROMOSOME_WIDTH(16), .LSFR_WIDTH(16)) DUT (
        .clk             (intf.clk),
        .rst             (intf.rst),
        .start_mutation  (intf.start_mutation),
        .child_in        (intf.child_in),
        .mutation_mode   (intf.mutation_mode),
        .mutation_rate   (intf.mutation_rate),
        .LSFR_input      (intf.LSFR_input),
        .child_out       (intf.child_out),
        .mutation_done   (intf.mutation_done)
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
        .random_out(intf.LSFR_input)
    );

    // -------------------------------------------------------
    // 3.1 Signals for waveform view (assign style)
    // -------------------------------------------------------
    logic Start, Done;
    logic [15:0] ChildIn, ChildOut, LfsrInp;
    logic [2:0] Mode;
    logic [7:0] Rate;
    assign Start     = intf.start_mutation;
    assign ChildIn   = intf.child_in;
    assign Mode      = intf.mutation_mode;
    assign Rate      = intf.mutation_rate;
    assign LfsrInp   = intf.LSFR_input;
    assign ChildOut  = intf.child_out;
    assign Done      = intf.mutation_done;

    // -------------------------------------------------------
    // 4. Generator (manual + random)
    // -------------------------------------------------------
    task generator(input int num_tests);
        // MODE 000: BIT-FLIP MUTATION
        // Test 1: Probabilistic check fails (no mutation)
        current_test_num = 1;
        intf.child_in                    = 16'b0000000000000000;
        intf.mutation_mode               = 3'b000;
        intf.mutation_rate               = 8'd0;  // Rate 0: always fail
        seed_in = 16'hFFFF;  // Any value, but check fails
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK); // Stabilize
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 2: All bits flip (high rate, specific LSFR)
        current_test_num = 2;
        intf.child_in                    = 16'b1010101010101010;
        intf.mutation_mode               = 3'b000;
        intf.mutation_rate               = 8'd255;  // Max rate
        seed_in = 16'h0000;  // LSFR[7:0]=0 <255, and slices < (255>>4)=15 (all <16)
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 3: Partial flips (medium rate)
        current_test_num = 3;
        intf.child_in                    = 16'b1111000011110000;
        intf.mutation_mode               = 3'b000;
        intf.mutation_rate               = 8'd64;  // ~25%
        seed_in = 16'hAC35;  // Specific for known slices
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // MODE 001: BIT-SWAP MUTATION
        // Test 4: Swap positions equal (edge case, regenerate)
        current_test_num = 4;
        intf.child_in                    = 16'b0000111100001111;
        intf.mutation_mode               = 3'b001;
        intf.mutation_rate               = 8'd255;
        seed_in = 16'h0000;  // swap_pos1=0%16=0, swap_pos2=0%16=0 (equal), regenerate to 0 and 0 again? Wait, in code [11:8]=0, [15:12]=0
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 5: Normal swap + extra if high rate
        current_test_num = 5;
        intf.child_in                    = 16'b1010101010101010;
        intf.mutation_mode               = 3'b001;
        intf.mutation_rate               = 8'd200;  // >128 for extra
        seed_in = 16'h1234;  // pos1=4%16=4, pos2=2%16=2 (diff)
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 6: Extra swap with edge handler (positions equal after shift)
        current_test_num = 6;
        intf.child_in                    = 16'b1111111111111111;
        intf.mutation_mode               = 3'b001;
        intf.mutation_rate               = 8'd200;
        seed_in = 16'h0101;  // pos1=1, pos2=0; after +1,+2: pos1=2, pos2=2 (equal), then +3,+4: 5,6
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // MODE 010: INVERSION MUTATION
        // Test 7: Zero length (start==end, skip)
        current_test_num = 7;
        intf.child_in                    = 16'b0000000000000000;
        intf.mutation_mode               = 3'b010;
        intf.mutation_rate               = 8'd255;
        seed_in = 16'hA000;  // inv_start=0%16=0, inv_end=10%16=10? Wait, [11:8]=0, [15:12]=A=10, sorted 0-10
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 8: Normal inversion
        current_test_num = 8;
        intf.child_in                    = 16'b0000111100001111;
        intf.mutation_mode               = 3'b010;
        intf.mutation_rate               = 8'd255;
        seed_in = 16'h4824;  // inv_start=2%16=2, inv_end=4%16=4, sorted 2-4
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 9: Inversion with odd length
        current_test_num = 9;
        intf.child_in                    = 16'b1010101010101010;
        intf.mutation_mode               = 3'b010;
        intf.mutation_rate               = 8'd255;
        seed_in = 16'h5935;  // inv_start=3%16=3, inv_end=5%16=5, sorted 3-5 (length 3)
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // MODE 011: SCRAMBLE MUTATION
        // Test 10: Simple XOR (low rate, no extra swaps)
        current_test_num = 10;
        intf.child_in                    = 16'b1111000011110000;
        intf.mutation_mode               = 3'b011;
        intf.mutation_rate               = 8'd50;  // <64, only XOR
        seed_in = 16'hFFFF;  // scramble_mask=FFFF
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 11: XOR + extra swaps (high rate)
        current_test_num = 11;
        intf.child_in                    = 16'b0000111100001111;
        intf.mutation_mode               = 3'b011;
        intf.mutation_rate               = 8'd100;  // >64, add 2 swaps
        seed_in = 16'h1234;  // For mask and swap positions
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 12: Extra swap with equal positions (edge handler)
        current_test_num = 12;
        intf.child_in                    = 16'b1010101010101010;
        intf.mutation_mode               = 3'b011;
        intf.mutation_rate               = 8'd100;
        seed_in = 16'h0000;  // Positions may equal, shift pos2+1
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // MODE 100: COMBINED (FLIP + SWAP)
        // Test 13: Combined with swap positions equal (edge handler)
        current_test_num = 13;
        intf.child_in                    = 16'b1111111111111111;
        intf.mutation_mode               = 3'b100;
        intf.mutation_rate               = 8'd255;
        seed_in = 16'h0000;  // pos1=0, pos2=0 (equal), regenerate
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 14: Normal combined
        current_test_num = 14;
        intf.child_in                    = 16'b0000000000000000;
        intf.mutation_mode               = 3'b100;
        intf.mutation_rate               = 8'd128;
        seed_in = 16'h1234;  // For flips and swaps
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // BOUNDARY AND ERROR CASES
        // Test 15: Invalid mode (default: no mutation)
        current_test_num = 15;
        intf.child_in                    = 16'b1010101010101010;
        intf.mutation_mode               = 3'b111;  // Invalid
        intf.mutation_rate               = 8'd255;
        seed_in = 16'hFFFF;
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Test 16: Reset during operation
        current_test_num = 16;
        intf.child_in                    = 16'b1111000011110000;
        intf.mutation_mode               = 3'b000;
        intf.mutation_rate               = 8'd255;
        seed_in = 16'h0000;
        load_seed = 1'b1;
        @(posedge CLK);
        load_seed = 1'b0;
        @(posedge CLK);
        intf.start_mutation = 1'b1;
        @(posedge CLK);
        RST = 1'b1;  // Assert reset mid-operation
        @(posedge CLK);
        RST = 1'b0;
        intf.start_mutation = 1'b0;
        check_result();
        @(posedge CLK);

        // Randomized tests
        start_lfsr = 1'b1; // Enable LFSR initially
        for (int i = 0; i < num_tests; i++) begin
            current_test_num = 16 + i + 1;
            // Apply randomized inputs
            intf.child_in                      = $urandom();
            intf.mutation_mode                 = $urandom_range(0, 7);  // Includes invalid
            intf.mutation_rate                 = $urandom_range(0, 255);
            // Advance LFSR to get new value
            @(posedge CLK);
            // Disable LFSR advance for the mutation cycle to avoid race
            start_lfsr = 1'b0;
            // Start mutation
            intf.start_mutation = 1'b1;
            @(posedge CLK);
            intf.start_mutation = 1'b0;
            // Check result (LSFR_input is stable)
            check_result();
            // Advance clock to let done deassert
            @(posedge CLK);
            // Re-enable LFSR for next test
            start_lfsr = 1'b1;
        end
    endtask

    // -------------------------------------------------------
    // 5. check_result
    // -------------------------------------------------------
    task automatic check_result();
        // Local constants for sizing
        localparam int W      = $bits(intf.child_in);
        localparam int PWIDTH = $clog2(W) + 1;  // For positions up to 16

        // Temporaries (replicate DUT internals)
        logic [W-1:0] temp_child;
        logic [W-1:0] flip_mask;
        logic [3:0]   swap_pos1, swap_pos2;
        logic [3:0]   inv_start, inv_end;
        logic [W-1:0] scramble_mask;
        logic [3:0]   sorted_start, sorted_end;

        // Extract from LSFR_input exactly as DUT
        flip_mask     = intf.LSFR_input[15:0];
        swap_pos1     = intf.LSFR_input[3:0] % W;
        swap_pos2     = intf.LSFR_input[7:4] % W;
        inv_start     = intf.LSFR_input[11:8] % W;
        inv_end       = intf.LSFR_input[15:12] % W;
        scramble_mask = intf.LSFR_input[15:0];

        // Sort inversion points
        sorted_start = (inv_start < inv_end) ? inv_start : inv_end;
        sorted_end   = (inv_start < inv_end) ? inv_end : inv_start;

        // Start with input
        temp_child = intf.child_in;

        // Handle special cases like reset test (test 16)
        if (current_test_num == 16) begin  // Reset test: expect done to remain 0 after reset
            // Wait a bit for reset to take effect
            repeat(2) @(posedge intf.clk);  // Wait 2 cycles for stabilization
            if (intf.mutation_done !== 1'b0) begin
                $display("ERROR: In reset test %d, mutation_done should be 0 after reset, but is %b", current_test_num, intf.mutation_done);
                error_count++;
            end else begin
                $display("PASS: Reset test %d handled correctly (done=0)", current_test_num);
            end
            // Check child_out reset to 0 (as per DUT)
            if (intf.child_out !== '0) begin
                $display("ERROR: child_out not reset to 0");
                error_count++;
            end else begin
                $display("PASS: child_out reset correctly");
            end
            test_count++;
            return;  // Skip normal wait and checks
        end

        // Normal wait with timeout to prevent hang
        fork
            begin
                wait(intf.mutation_done == 1'b1);
            end
            begin
                #100ns;  // Timeout after 100ns
                $display("ERROR: Timeout waiting for mutation_done in test %d", current_test_num);
                error_count++;
            end
        join_any
        disable fork;  // Clean up

        // Replicate mutation logic exactly as in DUT
        if (intf.LSFR_input[7:0] < intf.mutation_rate) begin
            case (intf.mutation_mode)
                // Bit-Flip mutation
                3'b000: begin
                    for (int i = 0; i < W; i++) begin
                        // Per-bit: use 4-bit slices from flip_mask
                        if (flip_mask[(i % 4)*4 +: 4] < (intf.mutation_rate >> 4)) begin
                            temp_child[i] = ~temp_child[i];
                        end
                    end
                end
                // Bit-Swap Mutation
                3'b001: begin
                    // Edge case handler: if swap_pos1 == swap_pos2, regenerate
                    if (swap_pos1 == swap_pos2) begin
                        swap_pos1 = (intf.LSFR_input[11:8] % W);  // Regenerate pos1
                        swap_pos2 = (intf.LSFR_input[15:12] % W); // Regenerate pos2
                        // If still equal, skip
                        if (swap_pos1 != swap_pos2) begin
                            temp_child[swap_pos1] = intf.child_in[swap_pos2];
                            temp_child[swap_pos2] = intf.child_in[swap_pos1];
                        end
                    end else begin
                        // Normal swap
                        temp_child[swap_pos1] = intf.child_in[swap_pos2];
                        temp_child[swap_pos2] = intf.child_in[swap_pos1];
                    end
                    // Extra swap if high rate (with edge handler)
                    if (intf.mutation_rate > intf.LSFR_input[15:8]) begin
                        swap_pos1 = (swap_pos1 + 1) % W;
                        swap_pos2 = (swap_pos2 + 2) % W;
                        if (swap_pos1 == swap_pos2) begin
                            // Edge handler: shift again to avoid equality
                            swap_pos1 = (swap_pos1 + 3) % W;
                            swap_pos2 = (swap_pos2 + 4) % W;
                            if (swap_pos1 != swap_pos2) begin
                                temp_child[swap_pos1] = temp_child[swap_pos2];
                                temp_child[swap_pos2] = temp_child[swap_pos1];
                            end
                        end else begin
                            // normal
                            temp_child[swap_pos1] = temp_child[swap_pos2];
                            temp_child[swap_pos2] = temp_child[swap_pos1];
                        end
                    end
                end
                // Inversion Mutation
                3'b010: begin
                    // Edge case handler: if sorted_start == sorted_end or length <1, skip
                    if (sorted_start != sorted_end && (sorted_end - sorted_start >= 1)) begin
                        for (int i = 0; i < (sorted_end - sorted_start + 1)/2; i++) begin
                            temp_child[sorted_start + i] = intf.child_in[sorted_end - i];
                            temp_child[sorted_end - i] = intf.child_in[sorted_start + i];
                        end
                    end
                end
                // Scramble Mutation
                3'b011: begin
                    // Simple scramble: XOR with mask
                    temp_child = intf.child_in ^ scramble_mask;
                    // Add limited swaps for shuffling (e.g., 2 swaps) if rate high
                    if (intf.mutation_rate > 64) begin
                        for (int i = 0; i < 2; i++) begin
                            swap_pos1 = (intf.LSFR_input[(i*4) % 16 +: 4]) % W;  // Adjusted slicing for 16-bit
                            swap_pos2 = (intf.LSFR_input[(i*4 + 4) % 16 +: 4]) % W;
                            // Edge case handler: if equal, shift pos2 by 1
                            if (swap_pos1 == swap_pos2) begin
                                swap_pos2 = (swap_pos2 + 1) % W;
                            end
                            if (swap_pos1 != swap_pos2) begin
                                logic temp_bit = temp_child[swap_pos1];
                                temp_child[swap_pos1] = temp_child[swap_pos2];
                                temp_child[swap_pos2] = temp_bit;
                            end
                        end
                    end
                end
                // Combined: Bit-Flip + Bit-Swap
                3'b100: begin
                    // First apply Bit-Flip with half rate
                    for (int i = 0; i < W; i++) begin
                        if (flip_mask[(i % 4)*4 +: 4] < (intf.mutation_rate >> 5)) begin  // Adjusted for finer control
                            temp_child[i] = ~temp_child[i];
                        end
                    end
                    // Then apply Bit-Swap with edge handler
                    if (swap_pos1 == swap_pos2) begin
                        swap_pos1 = (intf.LSFR_input[11:8] % W);
                        swap_pos2 = (intf.LSFR_input[15:12] % W);
                    end
                    if (swap_pos1 != swap_pos2) begin
                        logic temp_bit = temp_child[swap_pos1];
                        temp_child[swap_pos1] = temp_child[swap_pos2];
                        temp_child[swap_pos2] = temp_bit;
                    end
                end
                // Default: No mutation
                default: begin
                    temp_child = intf.child_in;
                end
            endcase
        end  // else temp_child remains child_in

        // Actual comparison with detailed logging
        if (intf.child_out !== temp_child) begin
            // Detailed ERROR display with all relevant signals
            $display("------------------------------------------------------------");
            $display(">>>ERROR!! test %0d: Mode=%0b, child_in=0x%h, mutation_rate=%0d, LSFR_input=0x%h, mutation_done=%b",
                     current_test_num, intf.mutation_mode, intf.child_in, intf.mutation_rate, intf.LSFR_input, intf.mutation_done);
            $display("Expected child_out=0x%h, but got 0x%h", temp_child, intf.child_out);
            $display("Details: Probabilistic check %s (LSFR[7:0]=%0d %s rate=%0d)",
                     (intf.LSFR_input[7:0] < intf.mutation_rate) ? "passed" : "failed",
                     intf.LSFR_input[7:0],
                     (intf.LSFR_input[7:0] < intf.mutation_rate) ? "<" : ">=",
                     intf.mutation_rate);
            // Add mode-specific details
            case (intf.mutation_mode)
                3'b000: $display("Bit-Flip: flip_mask=0x%h", flip_mask);
                3'b001: $display("Bit-Swap: pos1=%0d, pos2=%0d", swap_pos1, swap_pos2);
                3'b010: $display("Inversion: sorted_start=%0d, sorted_end=%0d", sorted_start, sorted_end);
                3'b011: $display("Scramble: mask=0x%h", scramble_mask);
                3'b100: $display("Combined: flip_mask=0x%h, pos1=%0d, pos2=%0d", flip_mask, swap_pos1, swap_pos2);
                default: $display("Default mode (no mutation)");  
            endcase
            $display("------------------------------------------------------------");
            error_count++;
        end 
        test_count++;
    endtask

    // ADDED: Initial block to run the generator (adjust num_tests as needed)
    initial begin
        // Wait for reset to deassert
        @(negedge RST);
        // Run manual + random tests (e.g., 100 random tests)
        generator(100);
        // Finish simulation
        $display("Tests completed: %d, Errors: %d", test_count, error_count);
        $finish;
        $stop;
    end

endmodule