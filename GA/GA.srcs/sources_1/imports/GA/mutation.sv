(* keep_hierarchy = "yes" *)
module mutation #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter LSFR_WIDTH = 16  // Adjusted to 16-bit as per user specification (sufficient for slicing random values)
)(
    clk,
    rst,
    start_mutation,
    child_in,
    mutation_mode,
    mutation_rate,
    LSFR_input,
    child_out,
    mutation_done
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Inputs
    input  logic                               clk;
    input  logic                               rst;  // Active-high reset
    input  logic                               start_mutation;
    input  logic [CHROMOSOME_WIDTH-1:0]        child_in;
    input  logic [2:0]                         mutation_mode;  // 000: Bit-Flip, 001: Bit-Swap, 010: Inversion, 011: Scramble, 100: Combined (Flip + Swap)
    input  logic [7:0]                         mutation_rate;  // 0-255, controls probability/intensity
    input  logic [LSFR_WIDTH-1:0]              LSFR_input;     // Random input from LFSR (now 16-bit)

    // Outputs
    (* use_dsp = "no" *)
    output logic [CHROMOSOME_WIDTH-1:0]        child_out;
    output logic                               mutation_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

    // Internal signals (original)
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] temp_child;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] flip_mask;
    (* keep = "true" *) logic [3:0]                 swap_pos1, swap_pos2;
    (* keep = "true" *) logic [3:0]                 inv_start, inv_end;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] scramble_mask;
    (* keep = "true" *) logic [3:0]                 sorted_start, sorted_end;

    // ADDED: New logic signals at module level for edge-case handling (instead of local variables)
    // These are driven only in always_ff to avoid multiple drivers
    (* keep = "true" *) logic [3:0]                 effective_swap_pos1;
    (* keep = "true" *) logic [3:0]                 effective_swap_pos2;
    (* keep = "true" *) logic [3:0]                 effective_extra_pos1;  // For extra swap in Bit-Swap
    (* keep = "true" *) logic [3:0]                 effective_extra_pos2;  // For extra swap in Bit-Swap
    (* keep = "true" *) logic [3:0]                 scramble_pos1 [1:0];   // Array for 2 swaps in Scramble
    (* keep = "true" *) logic [3:0]                 scramble_pos2 [1:0];   // Array for 2 swaps in Scramble

    // =========================
    // Combinational preparation (unchanged)
    // =========================
    always_comb begin
        // Slice LSFR for random values (adjusted for 16-bit LSFR; reuse/overlap bits to fit all needs)
        flip_mask     = LSFR_input[15:0];  // Full 16 bits for flip decisions (per-bit will slice further)
        swap_pos1     = LSFR_input[3:0] % CHROMOSOME_WIDTH;
        swap_pos2     = LSFR_input[7:4] % CHROMOSOME_WIDTH;
        inv_start     = LSFR_input[11:8] % CHROMOSOME_WIDTH;
        inv_end       = LSFR_input[15:12] % CHROMOSOME_WIDTH;
        scramble_mask = LSFR_input[15:0];  // Reuse full 16 bits for scramble (fits CHROMOSOME_WIDTH=16)

        // Sort inversion points
        (* keep = "true", lut1 = "yes" *)
        sorted_start = (inv_start < inv_end) ? inv_start : inv_end;
        (* keep = "true", lut1 = "yes" *)
        sorted_end   = (inv_start < inv_end) ? inv_end : inv_start;
    end

    // =========================
    // Main mutation process
    // =========================
    (* use_dsp = "no" *)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            child_out            <= '0;
            mutation_done        <= 1'b0;
            effective_swap_pos1  <= '0;  // ADDED: Reset new signals
            effective_swap_pos2  <= '0;
            effective_extra_pos1 <= '0;
            effective_extra_pos2 <= '0;
            scramble_pos1[0]     <= '0;
            scramble_pos1[1]     <= '0;
            scramble_pos2[0]     <= '0;
            scramble_pos2[1]     <= '0;
        end else begin
            mutation_done <= 1'b0;  // default
            if (start_mutation) begin
                temp_child = child_in;  // start with input
                // Probabilistic check for all modes: mutation occurs only if LSFR_input[7:0] < mutation_rate
                // This makes every mode probabilistic with probability ~ (mutation_rate / 256)
                if (LSFR_input[7:0] < mutation_rate) begin
                    case (mutation_mode)
                        // Bit-Flip mutation (unchanged)
                        3'b000: begin
                            for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
                                // Per-bit: use 4-bit slices from flip_mask for finer randomness (adjusted for 16-bit)
                                if (flip_mask[(i % 4)*4 +: 4] < (mutation_rate >> 4)) begin  // Adjusted threshold for intensity
                                    temp_child[i] = ~temp_child[i];
                                end
                            end
                        end
                        // Bit-Swap Mutation (now using effective_pos at module level)
                        3'b001: begin
                            // CHANGED: Initialize effective positions from combinational values
                            effective_swap_pos1 = swap_pos1;
                            effective_swap_pos2 = swap_pos2;

                            // Edge case handler: if equal, regenerate using shifted LSFR bits
                            if (effective_swap_pos1 == effective_swap_pos2) begin
                                effective_swap_pos1 = (LSFR_input[11:8] % CHROMOSOME_WIDTH);  // Regenerate pos1
                                effective_swap_pos2 = (LSFR_input[15:12] % CHROMOSOME_WIDTH); // Regenerate pos2
                                // If still equal (rare), skip to avoid no-op
                                if (effective_swap_pos1 == effective_swap_pos2) begin
                                    // Do nothing (edge case: no swap possible)
                                end else begin
                                    temp_child[effective_swap_pos1] <= child_in[effective_swap_pos2];
                                    temp_child[effective_swap_pos2] <= child_in[effective_swap_pos1];
                                end
                            end else begin
                                // Normal swap
                                temp_child[effective_swap_pos1] <= child_in[effective_swap_pos2];
                                temp_child[effective_swap_pos2] <= child_in[effective_swap_pos1];
                            end
                            // Extra swap if high rate (with edge handler, using effective_extra_pos)
                            if (mutation_rate > LSFR_input[15:8]) begin
                                effective_extra_pos1 = (effective_swap_pos1 + 1) % CHROMOSOME_WIDTH;
                                effective_extra_pos2 = (effective_swap_pos2 + 2) % CHROMOSOME_WIDTH;
                                if (effective_extra_pos1 == effective_extra_pos2) begin
                                    // Edge handler: shift again to avoid equality
                                    effective_extra_pos1 = (effective_extra_pos1 + 3) % CHROMOSOME_WIDTH;
                                    effective_extra_pos2 = (effective_extra_pos2 + 4) % CHROMOSOME_WIDTH;
                                    if (effective_extra_pos1 == effective_extra_pos2) begin
                                        // Do nothing (edge case handler)
                                    end else begin
                                        temp_child[effective_extra_pos1] <= temp_child[effective_extra_pos2];
                                        temp_child[effective_extra_pos2] <= temp_child[effective_extra_pos1];
                                    end
                                end else begin
                                    // normal
                                    temp_child[effective_extra_pos1] <= temp_child[effective_extra_pos2];
                                    temp_child[effective_extra_pos2] <= temp_child[effective_extra_pos1];
                                end
                            end
                        end
                        // Inversion Mutation (unchanged)
                        3'b010: begin
                            // Edge case handler: if sorted_start == sorted_end (length 0 or 1), skip inversion
                            if (sorted_start != sorted_end && (sorted_end - sorted_start >= 1)) begin
                                for (int i = 0; i < (sorted_end - sorted_start + 1)/2; i++) begin
                                    temp_child[sorted_start + i]       <= child_in[sorted_end - i];
                                    temp_child[sorted_end - i]         <= child_in[sorted_start + i];
                                end
                            end else begin
                                // Do nothing for single-bit or zero-length (edge case)
                            end
                        end
                        // Scramble Mutation (now using scramble_pos arrays at module level)
                        3'b011: begin
                            // Simple scramble: XOR with mask
                            temp_child = child_in ^ scramble_mask;
                            // Add limited swaps for shuffling (e.g., 2 swaps) if rate high
                            if (mutation_rate > 64) begin
                                for (int i = 0; i < 2; i++) begin
                                    // CHANGED: Initialize and handle edge cases using module-level arrays
                                    scramble_pos1[i] = (LSFR_input[(i*4) % 16 +: 4]) % CHROMOSOME_WIDTH;
                                    scramble_pos2[i] = (LSFR_input[(i*4 + 4) % 16 +: 4]) % CHROMOSOME_WIDTH;
                                    // Edge case handler: if equal, shift pos2 by 1
                                    if (scramble_pos1[i] == scramble_pos2[i]) begin
                                        scramble_pos2[i] = (scramble_pos2[i] + 1) % CHROMOSOME_WIDTH;
                                    end
                                    if (scramble_pos1[i] != scramble_pos2[i]) begin
                                        temp_child[scramble_pos1[i]] <= temp_child[scramble_pos2[i]];
                                        temp_child[scramble_pos2[i]] <= temp_child[scramble_pos1[i]];
                                    end
                                end
                            end
                        end
                        // Combined: Bit-Flip + Bit-Swap (now using effective_pos at module level)
                        3'b100: begin
                            // First apply Bit-Flip with half rate (unchanged)
                            for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
                                if (flip_mask[(i % 4)*4 +: 4] < (mutation_rate >> 5)) begin  // Adjusted for finer control
                                    temp_child[i] = ~temp_child[i];
                                end
                            end
                            // Then apply Bit-Swap with edge handler
                            // CHANGED: Initialize effective positions from combinational values
                            effective_swap_pos1 = swap_pos1;
                            effective_swap_pos2 = swap_pos2;
                            if (effective_swap_pos1 == effective_swap_pos2) begin
                                effective_swap_pos1 = (LSFR_input[11:8] % CHROMOSOME_WIDTH);
                                effective_swap_pos2 = (LSFR_input[15:12] % CHROMOSOME_WIDTH);
                            end
                            if (effective_swap_pos1 != effective_swap_pos2) begin
                                temp_child[effective_swap_pos1] <= temp_child[effective_swap_pos2];
                                temp_child[effective_swap_pos2] <= temp_child[effective_swap_pos1];
                            end
                        end
                        // Default: No mutation
                        default: begin
                            temp_child = child_in;
                        end
                    endcase
                end else begin
                    // If probabilistic check fails, no mutation
                    temp_child = child_in;
                end
                child_out     <= temp_child;
                mutation_done <= 1'b1;
            end
        end
    end

endmodule
