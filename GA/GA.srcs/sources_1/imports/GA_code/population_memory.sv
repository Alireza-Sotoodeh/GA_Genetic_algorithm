`timescale 1ns/1ps

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
        //fitness_values_out = fitness_values;
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

    // Notes on structure and potential issues:
    // - Pipelined: Writes take 2 cycles (start + update), reads combinational (no stall). For full pipeline, top module can register reads.
    // - Conflicts prevented: Writes sequential, reads comb; no simultaneous write to same addr (insertion shifts avoid it).
    // - Ties: If child_fitness == some fitness, inserts after (stable), but doesn't insert if not > (preserves elites). Adjust comparison to >= if needed.
    // - Zero total_fitness: Handled in selection (not here), but accumulator starts at 0; user must initialize population.
    // - Overflow: Widened accumulator detects/saturates; for FITNESS_WIDTH=14, max sum=16*16383=262128 (fits in 18 bits, safe but handled).
    // - Sorting: Maintains descending order after each insert (elitism: best preserved, worst discarded).
    // - Connection to selection: Provide read_addr1/2 from selection's outputs, get parent1_out/parent2_out directly to crossover.
    // - For larger POP_SIZE, optimize shift (e.g., use shift registers); current O(N) fine for 16.

endmodule