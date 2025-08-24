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

    // Internal signals (module-level for comb and reg separation)
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] temp_child;  // Retained as reg (if needed; appears unused but kept for compatibility)
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] comb_child;  // New: combinatorial next-state for child_out/temp_child
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] flip_mask;
    (* keep = "true" *) logic [3:0]                 swap_pos1, swap_pos2;
    (* keep = "true" *) logic [3:0]                 inv_start, inv_end;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] scramble_mask;
    (* keep = "true" *) logic [3:0]                 sorted_start, sorted_end;

    // =========================
    // Combinational preparation (existing always_comb retained)
    // =========================
    
    always_comb begin
        // --- FIX START ---
        // Use a temporary variable to build the mutated result
        logic [CHROMOSOME_WIDTH-1:0] next_child;
        // --- FIX END ---

        // Local variables for comb block (no inference of regs here)
        logic temp_bit;  // Local temp for swaps
        logic [3:0] local_swap_pos1;  // Local copy for modifications
        logic [3:0] local_swap_pos2;  // Local copy for modifications

        // Default: no mutation (pass through child_in)
        comb_child = child_in;
        // --- FIX START ---
        next_child = child_in; // Initialize temp variable
        // --- FIX END ---

        // Only compute mutation if start_mutation is active (gate the entire comb logic)
        if (start_mutation) begin
            // Probabilistic check: mutation occurs only if LSFR_input[7:0] < mutation_rate
            if (LSFR_input[7:0] < mutation_rate) begin
                case (mutation_mode)
                    // Bit-Flip mutation
                    3'b000: begin
                        for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
                            if (flip_mask[(i % 4)*4 +: 4] < (mutation_rate >> 4)) begin
                                // --- FIX: Operate on next_child ---
                                next_child[i] = ~next_child[i];
                            end
                        end
                    end
                    // Bit-Swap Mutation
                    3'b001: begin
                        local_swap_pos1 = swap_pos1;
                        local_swap_pos2 = swap_pos2;
                        if (local_swap_pos1 == local_swap_pos2) begin
                            local_swap_pos1 = (LSFR_input[11:8] % CHROMOSOME_WIDTH);
                            local_swap_pos2 = (LSFR_input[15:12] % CHROMOSOME_WIDTH);
                            if (local_swap_pos1 != local_swap_pos2) begin
                                temp_bit = next_child[local_swap_pos1];
                                next_child[local_swap_pos1] = next_child[local_swap_pos2];
                                next_child[local_swap_pos2] = temp_bit;
                            end
                        end else begin
                            temp_bit = next_child[local_swap_pos1];
                            next_child[local_swap_pos1] = next_child[local_swap_pos2];
                            next_child[local_swap_pos2] = temp_bit;
                        end
                        // Extra swap if high rate
                        if (mutation_rate > LSFR_input[15:8]) begin
                           local_swap_pos1 = (local_swap_pos1 + 1) % CHROMOSOME_WIDTH;
                           local_swap_pos2 = (local_swap_pos2 + 2) % CHROMOSOME_WIDTH;
                           if (local_swap_pos1 == local_swap_pos2) begin
                                local_swap_pos1 = (local_swap_pos1 + 3) % CHROMOSOME_WIDTH;
                                local_swap_pos2 = (local_swap_pos2 + 4) % CHROMOSOME_WIDTH;
                                if (local_swap_pos1 != local_swap_pos2) begin
                                    temp_bit = next_child[local_swap_pos1];
                                    next_child[local_swap_pos1] = next_child[local_swap_pos2];
                                    next_child[local_swap_pos2] = temp_bit;
                                end
                           end else begin
                                temp_bit = next_child[local_swap_pos1];
                                next_child[local_swap_pos1] = next_child[local_swap_pos2];
                                next_child[local_swap_pos2] = temp_bit;
                           end
                        end
                    end
                    // Inversion Mutation
                    3'b010: begin
                        if (sorted_start != sorted_end && (sorted_end - sorted_start >= 1)) begin
                            for (int i = 0; i < (sorted_end - sorted_start + 1)/2; i++) begin
                                temp_bit = next_child[sorted_start + i];
                                next_child[sorted_start + i] = next_child[sorted_end - i];
                                next_child[sorted_end - i] = temp_bit;
                            end
                        end
                    end
                    // Scramble Mutation
                    3'b011: begin
                        // --- FIX: Operate on next_child ---
                        next_child = child_in ^ scramble_mask;
                        if (mutation_rate > 64) begin
                            for (int i = 0; i < 2; i++) begin
                                local_swap_pos1 = (LSFR_input[(i*4) % 16 +: 4]) % CHROMOSOME_WIDTH;
                                local_swap_pos2 = (LSFR_input[(i*4 + 4) % 16 +: 4]) % CHROMOSOME_WIDTH;
                                if (local_swap_pos1 == local_swap_pos2) begin
                                    local_swap_pos2 = (local_swap_pos2 + 1) % CHROMOSOME_WIDTH;
                                end
                                if (local_swap_pos1 != local_swap_pos2) begin
                                    temp_bit = next_child[local_swap_pos1];
                                    next_child[local_swap_pos1] = next_child[local_swap_pos2];
                                    next_child[local_swap_pos2] = temp_bit;
                                end
                            end
                        end
                    end
                    // Combined: Bit-Flip + Bit-Swap
                    3'b100: begin
                        for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
                            if (flip_mask[(i % 4)*4 +: 4] < (mutation_rate >> 5)) begin
                                // --- FIX: Operate on next_child ---
                                next_child[i] = ~next_child[i];
                            end
                        end
                        local_swap_pos1 = swap_pos1;
                        local_swap_pos2 = swap_pos2;
                        if (local_swap_pos1 == local_swap_pos2) begin
                            local_swap_pos1 = (LSFR_input[11:8] % CHROMOSOME_WIDTH);
                            local_swap_pos2 = (LSFR_input[15:12] % CHROMOSOME_WIDTH);
                        end
                        if (local_swap_pos1 != local_swap_pos2) begin
                            temp_bit = next_child[local_swap_pos1];
                            next_child[local_swap_pos1] = next_child[local_swap_pos2];
                            next_child[local_swap_pos2] = temp_bit;
                        end
                    end
                    // Default: No mutation
                    default: begin
                        next_child = child_in;
                    end
                endcase
                // --- FIX START ---
                // Final assignment to the comb block output
                comb_child = next_child;
                // --- FIX END ---
            end else begin
                comb_child = child_in;
            end
        end
    end
endmodule
