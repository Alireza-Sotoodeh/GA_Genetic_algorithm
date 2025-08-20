module crossover #(
	parameter CHROMOSOME_WIDTH = 16,
	parameter LSFR_WIDTH = 16
	)(
    //inputs
    input  logic clk,
    input  logic rst_n,
    input  logic start_crossover,
    input  logic [CHROMOSOME_WIDTH-1:0] parent1,
    input  logic [CHROMOSOME_WIDTH-1:0] parent2,
    input  logic [1:0] crossover_mode,             // 0: fixed, 1: float, 2: uniform
    input  logic       crossover_single_double,    // 0: single, 1: double
    input  logic [$clog2(CHROMOSOME_WIDTH):0] crossover_Single_point,
    input  logic [$clog2(CHROMOSOME_WIDTH):0] crossover_double_R_FirstPoint,
    input  logic [$clog2(CHROMOSOME_WIDTH):0] crossover_double_R_SecondPoint,
    input  logic [CHROMOSOME_WIDTH-1:0] mask_uniform, // for uniform crossover
	input  logic [LSFR_WIDTH-1:0] LSFR_input;
    // outputs
    output logic [CHROMOSOME_WIDTH-1:0] child,
    output logic crossover_done
);
///////////////////////////////////////////////////////////////////////////////////////
// due to error crossover_Single_point (and others) is not a constant -> define mask1&2
// mask1: Used for single-point crossover 
// mask2: Used for double-point crossover (middle segment from parent1) 
// parent2 == 0 & parent1 =1
///////////////////////////////////////////////////////////////////////////////////////

	// mask (no flip_flop and need to be updated ASAP) for Fixed crossover
	//
    logic [CHROMOSOME_WIDTH-1:0] mask1, mask2;
	logic [$clog2(CHROMOSOME_WIDTH):0] num_random_1, num_random_2;
    always_comb begin
        mask1 = '0;
        mask2 = '0;
		num_random_1 = LSFR_input[]
        if (crossover_Single_point > 0)
            mask1 = (1 << crossover_Single_point) - 1;
        if (crossover_double_R_SecondPoint > crossover_double_R_FirstPoint)
            mask2 = ((1 << crossover_double_R_SecondPoint) - 1) ^ ((1 << crossover_double_R_FirstPoint) - 1);
    end
	
	// main
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            child <= '0;
            crossover_done <= 1'b0;
        end else begin
            crossover_done <= 1'b0; 
            if (start_crossover) begin
                case (crossover_mode)
                //'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
                    // Fixed 
                    2'b00: begin
                        if (!crossover_single_double) begin //single point
                            child <= (parent2 & ~mask1) | (parent1 & mask1);
                        end else begin // Double-point with mask2 in 
                            child <= (parent1 & mask2) | (parent2 & ~mask2); //mask 1 in middle
                        end
                        crossover_done <= 1'b1;
                    end
				//'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
                    // Float
                    2'b01: begin
                        if (!crossover_single_double) begin //single point
                            child <= (parent2 & ~mask1) | (parent1 & mask1);
                        end else begin // Double-point with mask2 in 
                            child <= (parent1 & mask2) | (parent2 & ~mask2); //mask 1 in middle
                        end
                        crossover_done <= 1'b1;
                    end
			//'''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
                    // Uniform
                    2'b10: begin
                        for (int i = 0; i < CHROMOSOME_WIDTH; i++)
                            child[i] <= mask_uniform[i] ? parent1[i] : parent2[i];
                        crossover_done <= 1'b1;
                    end

                    default: begin
                        child <= '0;
                        crossover_done <= 1'b0;
                    end
                endcase
            end
        end
    end
endmodule
