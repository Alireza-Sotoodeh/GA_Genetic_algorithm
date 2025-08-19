module population_memory #(
    parameter CHROMOSOME_WIDTH = 8,
    parameter POPULATION_SIZE = 16,
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE)
)(
    input logic clk,
    input logic rst_n,
    input logic write_enable,
    input logic [ADDR_WIDTH-1:0] write_addr,
    input logic [ADDR_WIDTH-1:0] read_addr,
    input logic [CHROMOSOME_WIDTH-1:0] write_data,
    output logic [CHROMOSOME_WIDTH-1:0] read_data
);
    // Register to store population
   logic [CHROMOSOME_WIDTH-1:0] population [POPULATION_SIZE-1:0];
    
    always_ff @(posedge clk) begin
        if (write_enable) begin
            population[write_addr] <= write_data;
        end
    end
    
    assign read_data = population[read_addr];
endmodule