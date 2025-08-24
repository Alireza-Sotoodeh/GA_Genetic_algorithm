(* keep_hierarchy = "yes" *)
module crossover #(
	parameter CHROMOSOME_WIDTH = 16,
	parameter LSFR_WIDTH = 16
)(
    clk,
    rst,
    start_crossover,
    parent1,
    parent2,
    crossover_mode,
    crossover_single_double,
    crossover_Single_point,
    crossover_double_point1,
    crossover_double_point2,
    mask_uniform,
    uniform_random_enable,
    LSFR_input,
    child,
    crossover_done
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    //inputs
    input  logic 								clk;
    input  logic 								rst;
    input  logic 								start_crossover;
    input  logic [CHROMOSOME_WIDTH-1:0] 		parent1;
    input  logic [CHROMOSOME_WIDTH-1:0] 		parent2;
    input  logic [1:0] 							crossover_mode;             	// 0: fixed, 1: float, 2: uniform
    input  logic       							crossover_single_double;    	// 0: single, 1: double
    input  logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_Single_point;
    input  logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_double_point1;
    input  logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_double_point2;
    input  logic [CHROMOSOME_WIDTH-1:0] 		mask_uniform; 					// for uniform crossover
    input  logic                                uniform_random_enable;          // 1 to enable lsfr input
	input  logic [LSFR_WIDTH-1:0] 				LSFR_input;
	
    // outputs
    (* use_dsp = "no" *)
    output logic [CHROMOSOME_WIDTH-1:0] 		child;
    output logic 								crossover_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

    
    // Internal signals
    (* keep = "true" *) logic [$clog2(CHROMOSOME_WIDTH):0] sp_rand, dp1_rand, dp2_rand;
    (* keep = "true" *) logic [$clog2(CHROMOSOME_WIDTH):0] p1_fixed, p2_fixed;
    (* keep = "true" *) logic [$clog2(CHROMOSOME_WIDTH):0] p1_float, p2_float;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] mask_single_fixed, mask_double_fixed;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] mask_single_float, mask_double_float;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] active_uniform_mask;

    // =========================
    // Combinational preparation
    // =========================
    always_comb begin
        // Slice LSFR for random points (float mode)
        localparam PWIDTH = $clog2(CHROMOSOME_WIDTH);
        sp_rand  = LSFR_input[PWIDTH-1:0];
        dp1_rand = LSFR_input[(2*PWIDTH)-1:PWIDTH];
        dp2_rand = LSFR_input[(3*PWIDTH)-1:(2*PWIDTH)];

        // ---- Sort double points ----
		(* keep = "true", lut1 = "yes" *)
        p1_fixed = (crossover_double_point1 < crossover_double_point2) 
                   ? crossover_double_point1 : crossover_double_point2;
		(* keep = "true", lut1 = "yes" *)		   
        p2_fixed = (crossover_double_point1 < crossover_double_point2) 
                   ? crossover_double_point2 : crossover_double_point1;
        // Float
		(* keep = "true", lut1 = "yes" *)
        p1_float = (dp1_rand < dp2_rand) ? dp1_rand : dp2_rand;
		(* keep = "true", lut1 = "yes" *)
        p2_float = (dp1_rand < dp2_rand) ? dp2_rand : dp1_rand;

        // Generate masks 
        // Fixed: single
        mask_single_fixed = (crossover_Single_point == 0) ? '0 :
                            (crossover_Single_point >= CHROMOSOME_WIDTH) ? 
                              {CHROMOSOME_WIDTH{1'b1}} :
                              ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - crossover_Single_point));

        // Fixed: double
        if (crossover_double_point1 == crossover_double_point2) begin
            mask_double_fixed = mask_single_fixed; // same as single if identical
        end else begin
            mask_double_fixed = ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - p2_fixed))
                              ^ ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - p1_fixed));
        end

        // Float: single
        mask_single_float = (sp_rand == 0) ? '0 :
                            (sp_rand >= CHROMOSOME_WIDTH) ? 
                              {CHROMOSOME_WIDTH{1'b1}} :
                              ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - sp_rand));

        // Float: double
        if (dp1_rand == dp2_rand) begin
            mask_double_float = mask_single_float;
        end else begin
            mask_double_float = ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - p2_float))
                               ^({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - p1_float));
        end

        // Uniform mask selection
        active_uniform_mask = uniform_random_enable ? LSFR_input[CHROMOSOME_WIDTH-1:0]
                                                    : mask_uniform;
    end

    // =========================
    // Main crossover process
    // =========================
    (* use_dsp = "no" *)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            child          <= '0;
            crossover_done <= 1'b0;
        end else begin
            crossover_done <= 1'b0;
            if (start_crossover) begin
                case (crossover_mode)
                    // Fixed
                    2'b00: begin
                        if (!crossover_single_double) begin
                            child <= (parent2 & ~mask_single_fixed) | (parent1 & mask_single_fixed);
                        end else begin
                            child <= (parent1 & mask_double_fixed) | (parent2 & ~mask_double_fixed);
                        end
                        crossover_done <= 1'b1;
                    end
                    // Float
                    2'b01: begin
                        if (!crossover_single_double) begin
                            child <= (parent2 & ~mask_single_float) | (parent1 & mask_single_float);
                        end else begin
                            child <= (parent1 & mask_double_float) | (parent2 & ~mask_double_float);
                        end
                        crossover_done <= 1'b1;
                    end
                    // Uniform
                    2'b10: begin
                        child <= (parent1 & active_uniform_mask) | (parent2 & ~active_uniform_mask);
                        crossover_done <= 1'b1;
                    end
                    // Default
                    default: begin
                        child <= '0;
                        crossover_done <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule

module fitness_evaluator #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14
)(
    clk,
    rst,
    start_evaluation,
    chromosome,
    fitness,
    evaluation_done
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    input logic clk;
    input logic rst;
    input logic start_evaluation;
    input logic [CHROMOSOME_WIDTH-1:0] chromosome;
    output logic [FITNESS_WIDTH-1:0] fitness;
    output logic evaluation_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

    logic [FITNESS_WIDTH-1:0] raw_fitness;  // Combinational result
    logic evaluating;  // New: Internal flag for two-cycle

    // Combinational fitness calculation (synthesizable popcount using loop)
    always_comb begin
        raw_fitness = {FITNESS_WIDTH{1'b0}};  // Initialize to 0
        for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
            raw_fitness += { {(FITNESS_WIDTH-1){1'b0}}, chromosome[i] };  // Add 1 if bit is set (zero-extend to avoid overflow)
        end
        // Clamp to max value to avoid overflow in GA summation (optional for small CHROMOSOME_WIDTH)
        if (raw_fitness > {FITNESS_WIDTH{1'b1}}) begin
            raw_fitness = {FITNESS_WIDTH{1'b1}};
        end
    end

    // Sequential registration and handshaking (unchanged)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fitness <= '0;
            evaluation_done <= 1'b0;
            evaluating <= 1'b0;  // Reset the new flag
        end else begin
            // Default: Deassert done to ensure one-cycle pulse
            evaluation_done <= 1'b0;

            if (start_evaluation && !evaluating) begin
                // Cycle 1: Start evaluation, register fitness, set flag
                fitness <= raw_fitness;
                evaluating <= 1'b1;
            end else if (evaluating) begin
                // Cycle 2: Pulse done and clear flag
                evaluation_done <= 1'b1;
                evaluating <= 1'b0;
            end
            // Note: If start_evaluation is held high, it won't re-trigger until evaluating clears
        end
    end
    
endmodule

(* keep_hierarchy = "yes" *) //to prevent from begin changed by optimizer
module lfsr_SudoRandom #(
    parameter WIDTH1 = 16, 
    parameter WIDTH2 = 15, 
    parameter WIDTH3 = 14, 
    parameter WIDTH4 = 13,  
    parameter defualtSeed1 = 16'hACE1,
    parameter defualtSeed2 = 15'h3BEE,
    parameter defualtSeed3 = 14'h2BAD,
    parameter defualtSeed4 = 13'h1DAD
)(
    clk,
    rst,
    start_lfsr,
    seed_in,
    load_seed,
    random_out
);

//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    //inputs
    input  logic                   clk;
    input  logic                   rst;           // high active rst
    input  logic                   start_lfsr;    // step enable
    input  logic [WIDTH1+WIDTH2+WIDTH3+WIDTH4-1:0] seed_in; // single seed input and max = 288230376151711743
    input  logic                   load_seed;     // reseed all LFSRs
    
    //outputs
    output logic [WIDTH1-1:0]      random_out;     // final whitened output
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

	//============================================================
	// define logics 
    //============================================================
    // Use SRL16E for efficient shift register implementation
    (* srl_style = "srl" *)          // SRL LUTs for compact implementation
    (* shreg_extract = "yes" *)      // Extract as shift registers
    (* keep = "true" *)              // Prevent optimization
    logic [WIDTH1-1:0] lfsr1;

    (* srl_style = "srl" *)
    (* shreg_extract = "yes" *)
    (* keep = "true" *)
    logic [WIDTH2-1:0] lfsr2;

    (* srl_style = "srl" *)
    (* shreg_extract = "yes" *)
    (* keep = "true" *)
    logic [WIDTH3-1:0] lfsr3;

    (* srl_style = "srl" *)
    (* shreg_extract = "yes" *)
    (* keep = "true" *)
    logic [WIDTH4-1:0] lfsr4;

    // Feedback logic - optimize with LUTs
    (* keep = "true" *)
    (* lut1 = "yes" *)               // Pack into single LUTs
    logic fb1, fb2, fb3, fb4;

    // Combined output logic
    (* use_dsp = "no" *)           // DON'T use DSP
    (* keep = "true" *)
    logic [WIDTH1-1:0] combined;
	//============================================================
	// Primitive polynomials for maximum period (width_independency_space)
    //============================================================
    assign fb1 = lfsr1[WIDTH1-1] ^ lfsr1[WIDTH1-3] ^ lfsr1[WIDTH1-4] ^ lfsr1[WIDTH1-6];       // x^16 + x^14 + x^13 + x^11 
    assign fb2 = lfsr2[WIDTH2-1] ^ lfsr2[WIDTH2-2] ^ lfsr2[WIDTH2-4] ^ lfsr2[WIDTH2-5];       // x^15 + x^14 + x^12 + x^10  
    assign fb3 = lfsr3[WIDTH3-1] ^ lfsr3[WIDTH3-3] ^ lfsr3[WIDTH3-5] ^ lfsr3[WIDTH3-7];       // x^14 + x^12 + x^10 + x^8
    assign fb4 = lfsr4[WIDTH4-1] ^ lfsr4[WIDTH4-2] ^ lfsr4[WIDTH4-4] ^ lfsr4[WIDTH4-5];       // x^13 + x^12 + x^10 + x^9 

    // Shift registers update
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // default non-zero seeds
            lfsr1 <= defualtSeed1;
            lfsr2 <= defualtSeed2;
            lfsr3 <= defualtSeed3;
            lfsr4 <= defualtSeed4;
        end else if (load_seed) begin
            // Slice the single seed 
            lfsr1 <= seed_in[WIDTH1+WIDTH2+WIDTH3+WIDTH4-1 : WIDTH2+WIDTH3+WIDTH4];
            lfsr2 <= seed_in[WIDTH2+WIDTH3+WIDTH4-1 : WIDTH3+WIDTH4];
            lfsr3 <= seed_in[WIDTH3+WIDTH4-1 : WIDTH4];
            lfsr4 <= seed_in[WIDTH4-1:0];
        end else if (start_lfsr) begin
            lfsr1 <= {fb1, lfsr1[WIDTH1-1:1]};
            lfsr2 <= {fb2, lfsr2[WIDTH2-1:1]};
            lfsr3 <= {fb3, lfsr3[WIDTH3-1:1]};
            lfsr4 <= {fb4, lfsr4[WIDTH4-1:1]};
        end
    end

    // Combine all LFSRs via XOR  (by default first num would be A835 hex)
    assign combined = lfsr1 ^ {{(WIDTH1-WIDTH2){1'b0}}, lfsr2} ^ {{(WIDTH1-WIDTH3){1'b0}}, lfsr3} ^ {{(WIDTH1-WIDTH4){1'b0}}, lfsr4};

    // Whitening: XOR with shifted versions
    always_comb begin
        random_out = combined  ^ (combined >> 7) ^ (combined << 3);
    end
endmodule

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

module population_memory #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14,
    parameter POPULATION_SIZE = 16,
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE)
)(
    clk,
    rst,
    start_write,
    child_in,                   // Child after mutation
    child_fitness_in,           // Fitness from fitness_evaluator
    read_addr1,                 // For reading parent1 (from selection's output index1)
    read_addr2,                 // For reading parent2 (from selection's output index2)
    request_fitness_values,     // Signal to request all fitness values (for selection)
    request_total_fitness,      // Signal to request total_fitness (for selection)
    parent1_out,                // Direct output to crossover (chromosome for parent1)
    parent2_out,                // Direct output to crossover (chromosome for parent2)
    fitness_values_out,         // Array of all fitness values (pipelined output for selection)
    total_fitness_out,          // Accumulated total fitness (pipelined output for selection)
    write_done                  // Handshake done for write/insertion
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Inputs
    input  logic                                clk;
    input  logic                                rst;  // Active-high like crossover
    input  logic                                start_write;
    input  logic [CHROMOSOME_WIDTH-1:0]         child_in;
    input  logic [FITNESS_WIDTH-1:0]            child_fitness_in;
    input  logic [ADDR_WIDTH-1:0]               read_addr1;
    input  logic [ADDR_WIDTH-1:0]               read_addr2;
    input  logic                                request_fitness_values;
    input  logic                                request_total_fitness;

    // Outputs
    output logic [CHROMOSOME_WIDTH-1:0]         parent1_out;
    output logic [CHROMOSOME_WIDTH-1:0]         parent2_out;
    output logic [FITNESS_WIDTH-1:0]            fitness_values_out [POPULATION_SIZE-1:0];
    output logic [FITNESS_WIDTH-1:0]            total_fitness_out;
    output logic                                write_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

    // Internal storage: arrays for chromosomes and fitness (kept sorted descending by fitness)
    (* ram_style = "block" *) logic [CHROMOSOME_WIDTH-1:0] population [POPULATION_SIZE-1:0];
    (* ram_style = "block" *) logic [FITNESS_WIDTH-1:0]    fitness_values [POPULATION_SIZE-1:0];
    logic [FITNESS_WIDTH:0]                      internal_total_fitness;  // Accumulator (widened by 1 bit to handle overflow detection)

    // Pipeline internals (to prevent read/write conflicts, enable simultaneous operations)
    (* keep = "true" *) logic [ADDR_WIDTH-1:0] insert_pos;          // Comb: Position to insert new child
    (* keep = "true" *) logic                  insert_found;         // Comb: Flag if better position found
    (* keep = "true" *) logic [FITNESS_WIDTH-1:0] old_fitness_remove; // Comb: Fitness of worst to remove
    logic                  writing;                // Internal flag like crossover (for two-cycle handshake)

    // =========================
    // Combinational preparation (like crossover: prepare reads, insertion logic, and requests)
    // =========================
    always_comb begin
        // Combinational reads for dual-port emulation (no conflict with writes since writes are sequential)
        // Outputs directly to crossover (pipelined by registering in top if needed)
        parent1_out = population[read_addr1];
        parent2_out = population[read_addr2];

        // Handle requests (combinational, but can be pipelined if latency mismatch)
        if (request_fitness_values) begin
            fitness_values_out = fitness_values;
        end else begin
            fitness_values_out = '{default: '0};
        end
        if (request_total_fitness) begin
            total_fitness_out = internal_total_fitness[FITNESS_WIDTH-1:0];  // Truncate if overflowed
        end else begin
            total_fitness_out = '0;
        end

        // Prepare insertion (linear search for insert_pos, assuming small POPULATION_SIZE=16, O(N) ok)
        // Assume sorted descending: fitness_values[0] highest, [POPULATION_SIZE-1] lowest
        insert_pos = POPULATION_SIZE - 1;  // Default: replace worst
        insert_found = 1'b0;
        old_fitness_remove = fitness_values[POPULATION_SIZE-1];  // Worst by default
        for (int i = 0; i < POPULATION_SIZE; i++) begin
            if (child_fitness_in > fitness_values[i]) begin
                insert_pos = i[ADDR_WIDTH-1:0];
                insert_found = 1'b1;
                break;  // Insert here, will shift rest down
            end
        end
    end

    // =========================
    // Main process (like crossover: sequential with start/done handshake, pipelined for write)
    // =========================
    (* use_dsp = "no" *)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < POPULATION_SIZE; i++) begin
                population[i] <= '0;
                fitness_values[i] <= '0;
            end
            internal_total_fitness <= '0;
            write_done <= 1'b0;
            writing <= 1'b0;
        end else begin
            // Default: Deassert done for one-cycle pulse
            write_done <= 1'b0;

            if (start_write && !writing) begin
                // Cycle 1: Start write, set flag (prep done in comb)
                writing <= 1'b1;
            end else if (writing) begin
                // Cycle 2: Perform insertion, update total_fitness incrementally, pulse done
                // Incremental update: subtract removed (worst), add new (handles overflow by widening)
                internal_total_fitness <= (internal_total_fitness - old_fitness_remove) + child_fitness_in;

                // Insertion: shift down from insert_pos to end, insert new, effectively remove worst
                if (insert_found) begin
                    for (int j = POPULATION_SIZE-1; j > insert_pos; j--) begin
                        population[j] <= population[j-1];
                        fitness_values[j] <= fitness_values[j-1];
                    end
                    population[insert_pos] <= child_in;
                    fitness_values[insert_pos] <= child_fitness_in;
                end else begin
                    // Not better than any: replace worst
                    population[insert_pos] <= child_in;
                    fitness_values[insert_pos] <= child_fitness_in;
                end

                write_done <= 1'b1;
                writing <= 1'b0;
            end

            // Handle potential issues (e.g., overflow): if widened bit set, saturate (optional, can assert error)
            if (internal_total_fitness[FITNESS_WIDTH]) begin
                internal_total_fitness <= {1'b0, {FITNESS_WIDTH{1'b1}}};  // Saturate to max
            end
        end
    end

endmodule

module selection #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14,
    parameter POPULATION_SIZE = 16,
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE),
    parameter LFSR_WIDTH = 16      // For random input, matches crossover
)(
    clk,
    rst,
    start_selection,
    fitness_values,             // From population_memory (array)
    total_fitness,              // From population_memory (accumulator)
    lfsr_input,                 // External random like crossover
    selected_index1,            // Output index1 for parent1 (to population_memory read_addr1)
    selected_index2,            // Output index2 for parent2 (to population_memory read_addr2)
    selection_done
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Inputs (similar to crossover style)
    input  logic                                clk;
    input  logic                                rst;  // Active-high like crossover
    input  logic                                start_selection;
    input  logic [FITNESS_WIDTH-1:0]            fitness_values [POPULATION_SIZE-1:0];
    input  logic [FITNESS_WIDTH-1:0]            total_fitness;
    input  logic [LFSR_WIDTH-1:0]               lfsr_input;  // External random

    // Outputs
    output logic [ADDR_WIDTH-1:0]               selected_index1;
    output logic [ADDR_WIDTH-1:0]               selected_index2;
    output logic                                selection_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

    // Internal signals (like crossover masks/prep)
    (* keep = "true" *) logic [FITNESS_WIDTH + LFSR_WIDTH - 1:0] roulette_pos1, roulette_pos2;  // Wide for scaling, two different positions
    (* keep = "true" *) logic [FITNESS_WIDTH-1:0] fitness_sum1, fitness_sum2;
    (* keep = "true" *) logic                  total_fitness_zero;
    (* keep = "true" *) logic                  selecting;  // Internal flag like crossover (for two-cycle)
    (* keep = "true" *) logic [ADDR_WIDTH-1:0] selected_index1_comb, selected_index2_comb;  // Comb results

    // =========================
    // Combinational preparation (like crossover: prepare two different roulette positions and comb selection)
    // =========================
    always_comb begin
        // Detect zero total fitness
        total_fitness_zero = (total_fitness == '0);

        // Generate two different positions (use lfsr_input split/modified for difference)
        if (total_fitness_zero) begin
            roulette_pos1 = lfsr_input % POPULATION_SIZE;  // Uniform random index
            roulette_pos2 = (lfsr_input ^ (lfsr_input >> (LFSR_WIDTH/2))) % POPULATION_SIZE;  // XOR for difference (ensure != pos1)
        end else begin
            // Wide multiplication for scaling (avoid overflow)
            logic [FITNESS_WIDTH + LFSR_WIDTH - 1:0] product1, product2;
            product1 = lfsr_input * total_fitness;
            roulette_pos1 = product1 >> LFSR_WIDTH;  // Scale down
            product2 = (lfsr_input ^ (lfsr_input >> 8)) * total_fitness;  // Modify for second different value
            roulette_pos2 = product2 >> LFSR_WIDTH;
        end

        // Comb loop for selection1 (unrollable, single-cycle)
        fitness_sum1 = '0;
        selected_index1_comb = '0;
        for (int i = 0; i < POPULATION_SIZE; i++) begin
            if (fitness_sum1 + fitness_values[i] > roulette_pos1) begin  // Strict > for ties handling
                selected_index1_comb = i[ADDR_WIDTH-1:0];
                break;
            end
            fitness_sum1 += fitness_values[i];
        end
        if (fitness_sum1 < roulette_pos1) selected_index1_comb = POPULATION_SIZE - 1;  // Edge: last

        // Comb loop for selection2 (parallel)
        fitness_sum2 = '0;
        selected_index2_comb = '0;
        for (int i = 0; i < POPULATION_SIZE; i++) begin
            if (fitness_sum2 + fitness_values[i] > roulette_pos2) begin
                selected_index2_comb = i[ADDR_WIDTH-1:0];
                break;
            end
            fitness_sum2 += fitness_values[i];
        end
        if (fitness_sum2 < roulette_pos2) selected_index2_comb = POPULATION_SIZE - 1;

        // Ensure different indices (re-assign if same; simple: swap with next if equal)
        if (selected_index1_comb == selected_index2_comb) begin
            selected_index2_comb = (selected_index2_comb + 1) % POPULATION_SIZE;
        end
    end

    // =========================
    // Sequential process (like crossover: register comb results, handshake)
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            selected_index1 <= '0;
            selected_index2 <= '0;
            selection_done <= 1'b0;
            selecting <= 1'b0;
        end else begin
            // Default: Deassert done for one-cycle pulse
            selection_done <= 1'b0;

            if (start_selection && !selecting) begin
                // Cycle 1: Sample comb, set flag
                selected_index1 <= selected_index1_comb;
                selected_index2 <= selected_index2_comb;
                selecting <= 1'b1;
            end else if (selecting) begin
                // Cycle 2: Pulse done, clear flag
                selection_done <= 1'b1;
                selecting <= 1'b0;
            end
        end
    end

endmodule

module ga_top #(
    // General GA Parameters
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14,
    parameter POPULATION_SIZE = 16,

    // Derived Parameters
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE),
    parameter LFSR_WIDTH = 16
)(
    //''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Control & Clocking
    input  logic                                clk,
    input  logic                                rst,
    input  logic                                start_ga,
    // Initial Population Seeding (Optional)
    input  logic                                load_initial_population, // Pulse to load one seed chromosome
    input  logic [CHROMOSOME_WIDTH-1:0]         data_in,                 // The seed chromosome to load

    // Crossover Parameters
    input  logic [1:0]                          crossover_mode,
    input  logic                                crossover_single_double,
    input  logic [ADDR_WIDTH-1:0]               crossover_single_point,
    input  logic [ADDR_WIDTH-1:0]               crossover_double_point1,
    input  logic [ADDR_WIDTH-1:0]               crossover_double_point2,
    input  logic [CHROMOSOME_WIDTH-1:0]         uniform_crossover_mask,
    input  logic                                uniform_random_enable,

    // Mutation Parameters
    input  logic [2:0]                          mutation_mode,
    input  logic [7:0]                          mutation_rate,

    // Termination Condition
    input  logic [31:0]                         target_iteration, // How many generations to run

    //''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Status & Results Outputs
    output logic                                busy,                   // GA is currently running
    output logic                                done,                   // GA has finished
    output logic                                perfect_found,          // Flag for when the perfect chromosome is found
    output logic [CHROMOSOME_WIDTH-1:0]         best_chromosome,        // The best chromosome from the population
    output logic [FITNESS_WIDTH-1:0]            best_fitness,           // Fitness of the best chromosome
    output logic [31:0]                         iteration_count,        // Current generation number
    output logic [31:0]                         crossovers_to_perfect,  // Generations it took to find the perfect solution
    // Legacy outputs from original request
    output logic [CHROMOSOME_WIDTH-1:0]         data_out,
    output logic [ADDR_WIDTH-1:0]               number_of_chromosomes
);

//======================================================================
// State Machine Definitions
//======================================================================
    // Main FSM States
    localparam [1:0] S_IDLE = 2'b00,
                     S_INIT = 2'b01,
                     S_RUNNING = 2'b10,
                     S_DONE = 2'b11;
    logic [1:0] state, next_state;

    // Pipeline FSM States (controls the main GA loop)
    localparam [2:0] P_IDLE = 3'b000,
                     P_SELECT = 3'b001,
                     P_CROSSOVER = 3'b010,
                     P_MUTATION = 3'b011,
                     P_EVALUATE = 3'b100,
                     P_UPDATE = 3'b101;
    logic [2:0] pipeline_state, next_pipeline_state;

//======================================================================
// Internal Wires & Registers
//======================================================================
    // Handshake signals for all modules
    logic start_select, select_done;
    logic start_cross, cross_done;
    logic start_mutate, mutate_done;
    logic start_eval_init, start_eval_pipe, eval_done;
    logic start_pop_write, pop_write_done;
    logic req_fitness, req_total_fitness;

    // Data paths between pipeline stages
    logic [ADDR_WIDTH-1:0]      p_selected_idx1, p_selected_idx2;
    logic [CHROMOSOME_WIDTH-1:0] p_parent1, p_parent2;
    logic [CHROMOSOME_WIDTH-1:0] p_child_crossed, p_child_mutated;
    logic [FITNESS_WIDTH-1:0]    p_child_fitness;
    logic [CHROMOSOME_WIDTH-1:0] init_chromosome_in;
    logic [FITNESS_WIDTH-1:0]    init_fitness_in; // needs proper assignment

    // Population Memory connections - Fixed signal widths
    logic [CHROMOSOME_WIDTH-1:0] pop_mem_parent1_out, pop_mem_parent2_out;
    logic [FITNESS_WIDTH-1:0]    pop_mem_fitness_values_out [POPULATION_SIZE-1:0];
    logic [FITNESS_WIDTH-1:0]    pop_mem_total_fitness_out; // Corrected width to FITNESS_WIDTH

    // LFSR connections
    logic start_lfsrs;
    logic [LFSR_WIDTH-1:0] rand_sel, rand_cross, rand_mut;

    // Counters and control flags
    logic [ADDR_WIDTH-1:0] init_counter;
    logic [31:0]           perfect_counter_reg;
    logic                  perfect_found_latch;

    // Pipeline control registers - Added for proper synchronization
    logic                  eval_init_pending, eval_pipe_pending;
    logic                  selection_valid, crossover_valid, mutation_valid;

//======================================================================
// Module Instantiations
//======================================================================
    // Three independent LFSRs for Selection, Crossover, and Mutation
    lfsr_SudoRandom #(
        .WIDTH1(LFSR_WIDTH), .defualtSeed1(16'hACE1)
    ) lfsr_sel_inst (
        .clk(clk), .rst(rst), .start_lfsr(start_lfsrs),
        .load_seed(1'b0), .seed_in('0), .random_out(rand_sel)
    );

    lfsr_SudoRandom #(
        .WIDTH1(LFSR_WIDTH), .defualtSeed1(16'hBEEF)
    ) lfsr_cross_inst (
        .clk(clk), .rst(rst), .start_lfsr(start_lfsrs),
        .load_seed(1'b0), .seed_in('0), .random_out(rand_cross)
    );

    lfsr_SudoRandom #(
        .WIDTH1(LFSR_WIDTH), .defualtSeed1(16'hDEAD)
    ) lfsr_mut_inst (
        .clk(clk), .rst(rst), .start_lfsr(start_lfsrs),
        .load_seed(1'b0), .seed_in('0), .random_out(rand_mut)
    );

    // --- GA Core Modules ---
    selection #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE),
        .LFSR_WIDTH(LFSR_WIDTH)
    ) sel_inst (
        .clk(clk),
        .rst(rst),
        .start_selection(start_select),
        .fitness_values(pop_mem_fitness_values_out),
        .total_fitness(pop_mem_total_fitness_out), // Correct width now
        .lfsr_input(rand_sel),
        .selected_index1(p_selected_idx1),
        .selected_index2(p_selected_idx2),
        .selection_done(select_done)
    );

    crossover #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .LSFR_WIDTH(LFSR_WIDTH)
    ) cross_inst (
        .clk(clk),
        .rst(rst),
        .start_crossover(start_cross),
        .parent1(p_parent1),
        .parent2(p_parent2),
        .crossover_mode(crossover_mode),
        .crossover_single_double(crossover_single_double),
        .crossover_Single_point(crossover_single_point),
        .crossover_double_point1(crossover_double_point1),
        .crossover_double_point2(crossover_double_point2),
        .LSFR_input(rand_cross),
        .mask_uniform(uniform_crossover_mask),
        .uniform_random_enable(uniform_random_enable),
        .child(p_child_crossed),
        .crossover_done(cross_done)
    );

    mutation #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .LSFR_WIDTH(LFSR_WIDTH)
    ) mut_inst (
        .clk(clk),
        .rst(rst),
        .start_mutation(start_mutate),
        .child_in(p_child_crossed),
        .mutation_mode(mutation_mode),
        .mutation_rate(mutation_rate),
        .LSFR_input(rand_mut),
        .child_out(p_child_mutated),
        .mutation_done(mutate_done)
    );

    fitness_evaluator #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH)
    ) fit_eval_inst (
        .clk(clk),
        .rst(rst),
        .start_evaluation(start_eval_init || start_eval_pipe),
        .chromosome(start_eval_init ? init_chromosome_in : p_child_mutated),
        .fitness(p_child_fitness),
        .evaluation_done(eval_done)
    );

    population_memory #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE)
    ) pop_mem_inst (
        .clk(clk),
        .rst(rst),
        .start_write(start_pop_write),
        .child_in(start_eval_init ? init_chromosome_in : p_child_mutated),
        .child_fitness_in(start_eval_init ? init_fitness_in : p_child_fitness), // use proper fitness for init
        .read_addr1(p_selected_idx1),
        .read_addr2(p_selected_idx2),
        .request_fitness_values(req_fitness),
        .request_total_fitness(req_total_fitness),
        .parent1_out(pop_mem_parent1_out),
        .parent2_out(pop_mem_parent2_out),
        .fitness_values_out(pop_mem_fitness_values_out),
        .total_fitness_out(pop_mem_total_fitness_out),
        .write_done(pop_write_done)
    );

//======================================================================
// Main State Machine - Sequential Logic
//======================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

//======================================================================
// Pipeline & Counter State Machine - Sequential Logic
//======================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pipeline_state <= P_IDLE;
            init_counter <= '0;
            iteration_count <= '0;
            perfect_counter_reg <= '0;
            perfect_found_latch <= 1'b0;
            p_parent1 <= '0;
            p_parent2 <= '0;
            eval_init_pending <= 1'b0;
            eval_pipe_pending <= 1'b0;
            selection_valid <= 1'b0;
            crossover_valid <= 1'b0;
            mutation_valid <= 1'b0;
            init_fitness_in <= '0; // reset init fitness
        end else begin
            pipeline_state <= next_pipeline_state;

            if (state == S_INIT && pop_write_done && init_counter < POPULATION_SIZE) begin
                init_counter <= init_counter + 1;
            end
            if (pipeline_state == P_UPDATE && pop_write_done) begin
                iteration_count <= iteration_count + 1;
            end

            if (select_done && !selection_valid) begin
                p_parent1 <= pop_mem_parent1_out;
                p_parent2 <= pop_mem_parent2_out;
                selection_valid <= 1'b1;
            end else if (pipeline_state != P_SELECT && pipeline_state != P_CROSSOVER) begin
                selection_valid <= 1'b0;
            end

            if (cross_done) crossover_valid <= 1'b1;
            else if (pipeline_state != P_CROSSOVER && pipeline_state != P_MUTATION) crossover_valid <= 1'b0;

            if (mutate_done) mutation_valid <= 1'b1;
            else if (pipeline_state != P_MUTATION && pipeline_state != P_EVALUATE) mutation_valid <= 1'b0;

            if (start_eval_init) eval_init_pending <= 1'b1;
            else if (eval_done && eval_init_pending) eval_init_pending <= 1'b0;

            if (start_eval_pipe) eval_pipe_pending <= 1'b1;
            else if (eval_done && eval_pipe_pending) eval_pipe_pending <= 1'b0;

            // assign fitness after evaluation done in init phase
            if (eval_done && eval_init_pending) begin
                init_fitness_in <= p_child_fitness;
            end

            if (perfect_found && !perfect_found_latch) begin
                perfect_found_latch <= 1'b1;
                perfect_counter_reg <= iteration_count + 1;
            end
        end
    end

//======================================================================
// State Machines & Control - Combinational Logic
//======================================================================
    always_comb begin
        next_state = state;
        next_pipeline_state = pipeline_state;
        start_select = 1'b0;
        start_cross = 1'b0;
        start_mutate = 1'b0;
        start_eval_init = 1'b0;
        start_eval_pipe = 1'b0;
        start_pop_write = 1'b0;
        start_lfsrs = 1'b0;
        req_fitness = 1'b0;
        req_total_fitness = 1'b0;

        // Proper initialization chromosome assignment
        if (load_initial_population && state == S_INIT) begin
            init_chromosome_in = data_in;
        end else begin
            init_chromosome_in = rand_mut;
        end

        case(state)
            S_IDLE: if (start_ga) begin
                next_state = S_INIT;
                start_lfsrs = 1'b1;
            end

            S_INIT: begin
                start_lfsrs = 1'b1;
                if (!eval_init_pending && !eval_done) begin
                    start_eval_init = 1'b1;
                end else if (eval_done && !pop_write_done) begin
                    start_pop_write = 1'b1;
                end
                if (init_counter >= POPULATION_SIZE - 1 && pop_write_done) begin
                    next_state = S_RUNNING;
                    next_pipeline_state = P_SELECT;
                end
            end

            S_RUNNING: begin
                start_lfsrs = 1'b1;
                req_fitness = 1'b1;
                req_total_fitness = 1'b1;

                case(pipeline_state)
                    P_SELECT: if (!select_done) start_select = 1'b1;
                              else if (select_done && selection_valid) next_pipeline_state = P_CROSSOVER;
                    P_CROSSOVER: if (!cross_done && selection_valid) start_cross = 1'b1;
                                 else if (cross_done && crossover_valid) next_pipeline_state = P_MUTATION;
                    P_MUTATION: if (!mutate_done && crossover_valid) start_mutate = 1'b1;
                                else if (mutate_done && mutation_valid) next_pipeline_state = P_EVALUATE;
                    P_EVALUATE: if (!eval_pipe_pending && !eval_done && mutation_valid) start_eval_pipe = 1'b1;
                                 else if (eval_done && eval_pipe_pending) next_pipeline_state = P_UPDATE;
                    P_UPDATE: if (!pop_write_done) start_pop_write = 1'b1;
                              else if (pop_write_done) begin
                                  if (iteration_count >= target_iteration - 1 || perfect_found) begin
                                      next_state = S_DONE;
                                      next_pipeline_state = P_IDLE;
                                  end else begin
                                      next_pipeline_state = P_SELECT;
                                  end
                              end
                    default: next_pipeline_state = P_IDLE;
                endcase
            end
            S_DONE: next_pipeline_state = P_IDLE;
        endcase
    end

//======================================================================
// Output Assignments
//======================================================================
    assign best_chromosome = pop_mem_inst.population[0];
    assign best_fitness = pop_mem_inst.fitness_values[0];
    assign busy = (state == S_INIT || state == S_RUNNING);
    assign done = (state == S_DONE);
    assign perfect_found = (best_fitness == CHROMOSOME_WIDTH);
    assign crossovers_to_perfect = perfect_found_latch ? perfect_counter_reg : 0;
    assign data_out = best_chromosome;
    assign number_of_chromosomes = POPULATION_SIZE[ADDR_WIDTH-1:0];

endmodule

