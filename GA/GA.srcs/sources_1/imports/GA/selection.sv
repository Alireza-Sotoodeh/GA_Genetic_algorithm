`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:
// Design Name: 
// Module Name: selection
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module selection #(
    parameter CHROMOSOME_WIDTH = 8,
    parameter POPULATION_SIZE = 16,
    parameter ADDR_WIDTH = $clog2(POPULATION_SIZE),
    parameter FITNESS_WIDTH = 10  // Wider to accommodate sum of fitness values
)(
    input logic clk,
    input logic rst_n,
    input logic start_selection,
    input logic [FITNESS_WIDTH-1:0] fitness_values [POPULATION_SIZE-1:0],
    input logic [FITNESS_WIDTH-1:0] total_fitness,
    output logic [ADDR_WIDTH-1:0] selected_parent,
    output logic selection_done
);
    // States for selection FSM
    typedef enum logic [1:0] {
        IDLE,
        SPINNING,
        DONE
    } state_t;
    
    state_t state, next_state;
    logic [FITNESS_WIDTH-1:0] roulette_position;
    logic [FITNESS_WIDTH-1:0] fitness_sum;
    logic [ADDR_WIDTH-1:0] current_idx;
    
    // LFSR for random number generation
    logic lfsr_enable;
    logic [CHROMOSOME_WIDTH-1:0] random_value;
    
    lfsr_random #(
        .WIDTH(CHROMOSOME_WIDTH)
    ) lfsr_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(lfsr_enable),
        .random_out(random_value)
    );
    
    // Scale random value to total fitness range
    always_comb begin
        // Scale random number to be between 0 and total_fitness
        roulette_position = (random_value * total_fitness) >> CHROMOSOME_WIDTH;
    end
    
    // Selection FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fitness_sum <= '0;
            current_idx <= '0;
            selected_parent <= '0;
            selection_done <= 1'b0;
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    fitness_sum <= '0;
                    current_idx <= '0;
                    selection_done <= 1'b0;
                end
                
                SPINNING: begin
                    if (fitness_sum + fitness_values[current_idx] >= roulette_position) begin
                        selected_parent <= current_idx;
                        selection_done <= 1'b1;
                    end else begin
                        fitness_sum <= fitness_sum + fitness_values[current_idx];
                        current_idx <= current_idx + 1'b1;
                    end
                end
                
                DONE: begin
                    selection_done <= 1'b1;
                end
            endcase
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = state;
        lfsr_enable = 1'b0;
        
        case (state)
            IDLE: begin
                if (start_selection) begin
                    next_state = SPINNING;
                    lfsr_enable = 1'b1;
                end
            end
            
            SPINNING: begin
                if (fitness_sum + fitness_values[current_idx] >= roulette_position || 
                    current_idx == POPULATION_SIZE-1) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end
endmodule