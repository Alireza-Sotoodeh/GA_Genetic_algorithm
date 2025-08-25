`timescale 1ns/1ps

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

    // Internal signals
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] temp_child;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] flip_mask;
    (* keep = "true" *) logic [3:0]                 swap_pos1, swap_pos2;
    (* keep = "true" *) logic [3:0]                 inv_start, inv_end;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] scramble_mask;
    (* keep = "true" *) logic [3:0]                 sorted_start, sorted_end;

    // =========================
    // Combinational preparation
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
        (* keep = "true" *) logic temp_bit;  // Local to avoid unused reg warning (moved to top of block)
        (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] next_temp_child;  // Combinatorial next-state for temp_child
        (* keep = "true" *) logic [3:0] local_swap_pos1;  // Local copy to avoid driving comb signal (moved to top)
        (* keep = "true" *) logic [3:0] local_swap_pos2;  // Local copy to avoid driving comb signal (moved to top)
        (* keep = "true" *) logic [LSFR_WIDTH-1:0] local_lsfr_input;  // Local copy to avoid multi-drive on input (e.g., bit[7])

        if (rst) begin
            child_out      <= '0;
            mutation_done  <= 1'b0;
            temp_child     <= '0;  // Explicit reset for temp_child
        end else begin
            // Default: reset done (priority over set)
            mutation_done <= 1'b0;

            // Local copy of input to avoid multi-drive warnings
            local_lsfr_input = LSFR_input;

            if (start_mutation) begin
                // Initialize next state
                next_temp_child = child_in;  // start with input
                // Probabilistic check for all modes: mutation occurs only if local_lsfr_input[7:0] < mutation_rate
                // This makes every mode probabilistic with probability ~ (mutation_rate / 256)
                if (local_lsfr_input[7:0] < mutation_rate) begin
                    case (mutation_mode)
                        // Bit-Flip mutation (already per-bit probabilistic, but wrapped in global prob)
                        3'b000: begin
                            for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
                                // Per-bit: use 4-bit slices from flip_mask for finer randomness (adjusted for 16-bit)
                                if (flip_mask[(i % 4)*4 +: 4] < (mutation_rate >> 4)) begin  // Adjusted threshold for intensity
                                    next_temp_child[i] = ~next_temp_child[i];
                                end
                            end
                        end
                        // Bit-Swap Mutation (now probabilistic overall) - MODIFIED for consistency and safety
                        3'b001: begin
                            local_swap_pos1 = swap_pos1;
                            local_swap_pos2 = swap_pos2;
                            // Edge case handler: if swap_pos1 == swap_pos2, regenerate positions using shifted LSFR bits
                            if (local_swap_pos1 == local_swap_pos2) begin
                                local_swap_pos1 = (local_lsfr_input[11:8] % CHROMOSOME_WIDTH);  // Regenerate pos1
                                local_swap_pos2 = (local_lsfr_input[15:12] % CHROMOSOME_WIDTH); // Regenerate pos2
                                // If still equal (rare), skip to avoid no-op
                                if (local_swap_pos1 == local_swap_pos2) begin
                                    // Do nothing (edge case: no swap possible)
                                end else begin
                                    temp_bit = next_temp_child[local_swap_pos1];  // Use temp_bit for safe swap (consistent with temp_child)
                                    next_temp_child[local_swap_pos1] = next_temp_child[local_swap_pos2];
                                    next_temp_child[local_swap_pos2] = temp_bit;
                                end
                            end else begin
                                // Normal swap
                                temp_bit = next_temp_child[local_swap_pos1];  // Use temp_bit
                                next_temp_child[local_swap_pos1] = next_temp_child[local_swap_pos2];
                                next_temp_child[local_swap_pos2] = temp_bit;
                            end
                            // Extra swap if high rate (with edge handler)
                            if (mutation_rate > local_lsfr_input[15:8]) begin
                                local_swap_pos1 = (local_swap_pos1 + 1) % CHROMOSOME_WIDTH;
                                local_swap_pos2 = (local_swap_pos2 + 2) % CHROMOSOME_WIDTH;
                                if (local_swap_pos1 == local_swap_pos2) begin
                                    // Edge handler: shift again to avoid equality
                                    local_swap_pos1 = (local_swap_pos1 + 3) % CHROMOSOME_WIDTH;
                                    local_swap_pos2 = (local_swap_pos2 + 4) % CHROMOSOME_WIDTH;
                                    if (local_swap_pos1 == local_swap_pos2) begin
                                        // Do nothing (edge case handler)
                                    end else begin
                                        temp_bit = next_temp_child[local_swap_pos1];
                                        next_temp_child[local_swap_pos1] = next_temp_child[local_swap_pos2];
                                        next_temp_child[local_swap_pos2] = temp_bit;
                                    end
                                end else begin
                                    // normal
                                    temp_bit = next_temp_child[local_swap_pos1];
                                    next_temp_child[local_swap_pos1] = next_temp_child[local_swap_pos2];
                                    next_temp_child[local_swap_pos2] = temp_bit;
                                end
                            end
                        end
                        // Inversion Mutation (now probabilistic) - MODIFIED with temp_bit for consistency
                        3'b010: begin
                            // Edge case handler: if sorted_start == sorted_end (length 0 or 1), skip inversion
                            if (sorted_start != sorted_end && (sorted_end - sorted_start >= 1)) begin
                                for (int i = 0; i < (sorted_end - sorted_start + 1)/2; i++) begin
                                    temp_bit = next_temp_child[sorted_start + i];
                                    next_temp_child[sorted_start + i] = next_temp_child[sorted_end - i];
                                    next_temp_child[sorted_end - i] = temp_bit;
                                end
                            end else begin
                                // Do nothing for single-bit or zero-length (edge case)
                            end
                        end
                        // Scramble Mutation (now probabilistic) - MODIFIED with temp_bit for swaps
                        3'b011: begin
                            // Simple scramble: XOR with mask
                            next_temp_child = child_in ^ scramble_mask;
                            // Add limited swaps for shuffling (e.g., 2 swaps) if rate high
                            if (mutation_rate > 64) begin
                                for (int i = 0; i < 2; i++) begin
                                    local_swap_pos1 = (local_lsfr_input[(i*4) % 16 +: 4]) % CHROMOSOME_WIDTH;  // Adjusted slicing for 16-bit
                                    local_swap_pos2 = (local_lsfr_input[(i*4 + 4) % 16 +: 4]) % CHROMOSOME_WIDTH;
                                    // Edge case handler: if equal, shift pos2 by 1
                                    if (local_swap_pos1 == local_swap_pos2) begin
                                        local_swap_pos2 = (local_swap_pos2 + 1) % CHROMOSOME_WIDTH;
                                    end
                                    if (local_swap_pos1 != local_swap_pos2) begin
                                        temp_bit = next_temp_child[local_swap_pos1];
                                        next_temp_child[local_swap_pos1] = next_temp_child[local_swap_pos2];
                                        next_temp_child[local_swap_pos2] = temp_bit;
                                    end
                                end
                            end
                        end
                        // Combined: Bit-Flip + Bit-Swap (now probabilistic overall) - MODIFIED with temp_bit
                        3'b100: begin
                            // First apply Bit-Flip with half rate
                            for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
                                if (flip_mask[(i % 4)*4 +: 4] < (mutation_rate >> 5)) begin  // Adjusted for finer control
                                    next_temp_child[i] = ~next_temp_child[i];
                                end
                            end
                            // Then apply Bit-Swap with edge handler
                            local_swap_pos1 = swap_pos1;
                            local_swap_pos2 = swap_pos2;
                            if (local_swap_pos1 == local_swap_pos2) begin
                                local_swap_pos1 = (local_lsfr_input[11:8] % CHROMOSOME_WIDTH);
                                local_swap_pos2 = (local_lsfr_input[15:12] % CHROMOSOME_WIDTH);
                            end
                            if (local_swap_pos1 != local_swap_pos2) begin
                                temp_bit = next_temp_child[local_swap_pos1];
                                next_temp_child[local_swap_pos1] = next_temp_child[local_swap_pos2];
                                next_temp_child[local_swap_pos2] = temp_bit;
                            end
                        end
                        // Default: No mutation
                        default: begin
                            next_temp_child = child_in;
                        end
                    endcase
                end else begin
                    // If probabilistic check fails, no mutation
                    next_temp_child = child_in;
                end
                // Assign next state (non-blocking)
                temp_child    <= next_temp_child;
                child_out     <= next_temp_child;
                mutation_done <= 1'b1;  // Set only on completion (after default reset)
            end
        end
    end

endmodule