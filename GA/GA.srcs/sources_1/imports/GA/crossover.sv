module crossover #(
	parameter CHROMOSOME_WIDTH = 16,
	parameter LSFR_WIDTH = 16
)(
    clk,
    rst_n,
    start_crossover,
    parent1,
    parent2,
    crossover_mode,
    crossover_single_double,
    crossover_Single_point,
    crossover_double_R_FirstPoint,
    crossover_double_R_SecondPoint,
    mask_uniform,
    uniform_random_enable,
    LSFR_input,
    child,
    crossover_done
);
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    //inputs
    input  logic 								clk;
    input  logic 								rst_n;
    input  logic 								start_crossover;
    input  logic [CHROMOSOME_WIDTH-1:0] 		parent1;
    input  logic [CHROMOSOME_WIDTH-1:0] 		parent2;
    input  logic [1:0] 							crossover_mode;             	// 0: fixed, 1: float, 2: uniform
    input  logic       							crossover_single_double;    	// 0: single, 1: double
    input  logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_Single_point;
    input  logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_double_R_FirstPoint;
    input  logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_double_R_SecondPoint;
    input  logic [CHROMOSOME_WIDTH-1:0] 		mask_uniform; 					// for uniform crossover
    input  logic                                uniform_random_enable;          // 1 to enable lsfr input
	input  logic [LSFR_WIDTH-1:0] 				LSFR_input;
	
    // outputs
    output logic [CHROMOSOME_WIDTH-1:0] 		child;
    output logic 								crossover_done;
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''


    
    // define logic
    logic [$clog2(CHROMOSOME_WIDTH):0] single_point_rand, double_first_rand, double_second_rand;
    logic [CHROMOSOME_WIDTH-1:0] mask1_fixed, mask2_fixed;
    logic [CHROMOSOME_WIDTH-1:0] mask1_float, mask2_float;
	logic [$clog2(CHROMOSOME_WIDTH):0] num_random_1, num_random_2;
	logic [CHROMOSOME_WIDTH-1:0] mask_uniform_rand; 
	
	//============================================================
    // Fixed masks pre-calculation
    // For fixed mode only
    //============================================================
    always_comb begin
        mask1_fixed = '0;
        mask2_fixed = '0;
        if (crossover_Single_point > 0)
            mask1_fixed = (1 << crossover_Single_point) - 1;
        if (crossover_double_R_SecondPoint > crossover_double_R_FirstPoint)
            mask2_fixed = ((1 << crossover_double_R_SecondPoint) - 1) ^ 
                    ((1 << crossover_double_R_FirstPoint) - 1);
    end
	
	//============================================================
    // Float mode random points
    // Update on each start_crossover in float mode
    //============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            single_point_rand  <= '0;
            double_first_rand  <= '0;
            double_second_rand <= '0;
        end 
        else if (start_crossover && crossover_mode == 2'b01) begin
            single_point_rand  <= LSFR_input[$clog2(CHROMOSOME_WIDTH)-1:0];
            double_first_rand  <= LSFR_input[$clog2(CHROMOSOME_WIDTH)+3:4];
            double_second_rand <= LSFR_input[$clog2(CHROMOSOME_WIDTH)+7:8];
        end
    end
	
	//============================================================
    // Random mask generation for uniform-random mode
    //============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask_uniform_rand <= '0;
        end 
        else if (start_crossover && crossover_mode == 2'b10 && uniform_random_enable) begin
            mask_uniform_rand <= LSFR_input[CHROMOSOME_WIDTH-1:0];
        end
    end
	
	
	//============================================================
    // Main crossover process
    //============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            child          <= '0;
            crossover_done <= 1'b0;
        end 
        else begin
            crossover_done <= 1'b0; // default low
            if (start_crossover) begin
                case (crossover_mode)
                    //------------------------------------------------
                    // 00: FIXED crossover
                    //------------------------------------------------
                    2'b00: begin
                        if (!crossover_single_double) begin
                            // Single-point fixed
                            child <= (parent2 & ~mask1_fixed) | (parent1 & mask1_fixed);
                        end 
                        else begin
                            // Double-point fixed
                            child <= (parent1 & mask2_fixed) | (parent2 & ~mask2_fixed);
                        end
                        crossover_done <= 1'b1;
                    end

                    //------------------------------------------------
                    // 01: FLOAT crossover
                    //------------------------------------------------
                    2'b01: begin
                        if (!crossover_single_double) begin
                            mask1_float = (1 << single_point_rand) - 1;
                            child <= (parent2 & ~mask1_float) | (parent1 & mask1_float);
                        end 
                        else begin
                            mask2_float = ((1 << double_second_rand) - 1) ^ 
                                    ((1 << double_first_rand) - 1);
                            child <= (parent1 & mask2_float) | (parent2 & ~mask2_float);
                        end
                        crossover_done <= 1'b1;
                    end

                    //------------------------------------------------
                    // 10: UNIFORM crossover
                    // Two sub-modes: fixed vs random mask
                    //------------------------------------------------
                    2'b10: begin
                        logic [CHROMOSOME_WIDTH-1:0] active_mask;
                        // Select mask source
                        active_mask = (uniform_random_enable) ? mask_uniform_rand : mask_uniform;
                        for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
                            child[i] <= active_mask[i] ? parent1[i] : parent2[i];
                        end
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