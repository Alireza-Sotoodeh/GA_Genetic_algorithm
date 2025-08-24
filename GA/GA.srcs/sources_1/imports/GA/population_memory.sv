module population_memory #(
    parameter CHROMOSOME_WIDTH = 16,
    parameter FITNESS_WIDTH = 14,
    parameter POPULATION_SIZE = 16,
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE)
)(
    clk,
    rst,
    start_write,
    child_in,
    child_fitness_in,
    read_addr1,
    read_addr2,
    request_fitness_values,
    request_total_fitness,
    parent1_out,
    parent2_out,
    fitness_values_out,
    total_fitness_out,
    write_done
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    // Inputs
    input  logic                                clk;
    input  logic                                rst;
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

    // Internal storage arrays
    (* ram_style = "block" *) logic [CHROMOSOME_WIDTH-1:0] population [POPULATION_SIZE-1:0];
    (* ram_style = "block" *) logic [FITNESS_WIDTH-1:0]    fitness_values [POPULATION_SIZE-1:0];
    logic [FITNESS_WIDTH:0]                      internal_total_fitness;

    // Combinational variables for insertion logic
    (* keep = "true" *) logic [ADDR_WIDTH-1:0]   insert_pos;
    (* keep = "true" *) logic                    insert_found;
    (* keep = "true" *) logic [FITNESS_WIDTH-1:0] old_fitness_remove;
    logic                                        writing;

    // Registered copies for outputs to avoid glitch / duplicate values
    logic [FITNESS_WIDTH-1:0]                    fitness_values_reg [POPULATION_SIZE-1:0];
    logic [FITNESS_WIDTH-1:0]                    total_fitness_reg;

    // =========================
    // Combinational preparation
    // =========================
    always_comb begin
        parent1_out = population[read_addr1];
        parent2_out = population[read_addr2];

        // Prepare insertion position
        insert_pos = POPULATION_SIZE - 1;
        insert_found = 1'b0;
        old_fitness_remove = fitness_values[POPULATION_SIZE-1];
        for (int i = 0; i < POPULATION_SIZE; i++) begin
            if (child_fitness_in > fitness_values[i]) begin
                insert_pos = i[ADDR_WIDTH-1:0];
                insert_found = 1'b1;
                break;
            end
        end
    end

    // =========================
    // Sequential logic with pipelined write
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < POPULATION_SIZE; i++) begin
                population[i] <= '0;
                fitness_values[i] <= '0;
                fitness_values_reg[i] <= '0; // registered copy reset
            end
            internal_total_fitness <= '0;
            total_fitness_reg <= '0;
            write_done <= 1'b0;
            writing <= 1'b0;
        end else begin
            write_done <= 1'b0;

            // Handle request outputs synchronously
            if (request_fitness_values) begin
                for (int k = 0; k < POPULATION_SIZE; k++) begin
                    fitness_values_reg[k] <= fitness_values[k];
                end
            end
            if (request_total_fitness) begin
                total_fitness_reg <= internal_total_fitness[FITNESS_WIDTH-1:0];
            end

            // Write pipeline
            if (start_write && !writing) begin
                writing <= 1'b1;
            end else if (writing) begin
                internal_total_fitness <= (internal_total_fitness - old_fitness_remove) + child_fitness_in;
                if (insert_found) begin
                    for (int j = POPULATION_SIZE-1; j > insert_pos; j--) begin
                        population[j] <= population[j-1];
                        fitness_values[j] <= fitness_values[j-1];
                    end
                    population[insert_pos] <= child_in;
                    fitness_values[insert_pos] <= child_fitness_in;
                end else begin
                    population[insert_pos] <= child_in;
                    fitness_values[insert_pos] <= child_fitness_in;
                end
                write_done <= 1'b1;
                writing <= 1'b0;
            end

            // Overflow protection
            if (internal_total_fitness[FITNESS_WIDTH]) begin
                internal_total_fitness <= {1'b0, {FITNESS_WIDTH{1'b1}}};
            end
        end
    end

    // Assign registered outputs
    assign fitness_values_out = fitness_values_reg;
    assign total_fitness_out = total_fitness_reg;

endmodule
