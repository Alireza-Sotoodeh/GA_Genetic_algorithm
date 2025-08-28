`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module crossover #(
	parameter CHROMOSOME_WIDTH = 16,
	parameter LFSR_WIDTH = 16
)(
    clk,
    rst,
    start_crossover,
    parent1,
    parent2,
    crossover_mode,
    crossover_single_double,
    crossover_single_point,
    crossover_double_point1,
    crossover_double_point2,
    mask_uniform,
    uniform_random_enable,
    LFSR_input,
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
    input  logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_single_point;
    input  logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_double_point1;
    input  logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_double_point2;
    input  logic [CHROMOSOME_WIDTH-1:0] 		mask_uniform; 					// for uniform crossover
    input  logic                                uniform_random_enable;          // 1 to enable lsfr input
	input  logic [LFSR_WIDTH-1:0] 				LFSR_input;
	
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
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] parent2_shifted_fixed; 
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] parent2_shifted_double_p1, parent2_shifted_double_p2;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] parent2_shifted_float;
    (* keep = "true" *) logic [CHROMOSOME_WIDTH-1:0] parent2_shifted_double_p1_float, parent2_shifted_double_p2_float;

    // =========================
    // Combinational preparation
    // =========================
    always_comb begin
        // Slice LSFR for random points (float mode)
        localparam PWIDTH = $clog2(CHROMOSOME_WIDTH);
        sp_rand  = LFSR_input[PWIDTH-1:0];
        dp1_rand = LFSR_input[(2*PWIDTH)-1:PWIDTH];
        dp2_rand = LFSR_input[(3*PWIDTH)-1:(2*PWIDTH)];

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
        mask_single_fixed = (crossover_single_point == 0) ? '0 :
                            (crossover_single_point >= CHROMOSOME_WIDTH) ? 
                              {CHROMOSOME_WIDTH{1'b1}} :
                              ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - crossover_single_point));
        parent2_shifted_fixed = (parent2<<crossover_single_point);
        
        // Fixed: double
        if (crossover_double_point1 == crossover_double_point2) begin
            mask_double_fixed = mask_single_fixed; // same as single if identical
        end else begin
            mask_double_fixed = ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - p2_fixed-1))
                              ^ ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - p1_fixed));
            parent2_shifted_double_p2 = (parent2<< (p2_fixed+1));
            parent2_shifted_double_p1 = (parent2>>  (CHROMOSOME_WIDTH-p1_fixed-1));                  
        end

        // Float: single
        mask_single_float = (sp_rand == 0) ? '0 :
                            (sp_rand >= CHROMOSOME_WIDTH) ? 
                              {CHROMOSOME_WIDTH{1'b1}} :
                              ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - sp_rand));
        parent2_shifted_float = (parent2 << sp_rand);
        // Float: double
        if (dp1_rand == dp2_rand) begin
            mask_double_float = mask_single_float;
        end else begin
            mask_double_float = ({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - p2_float))
                               ^({CHROMOSOME_WIDTH{1'b1}} >> (CHROMOSOME_WIDTH - p1_float));
           parent2_shifted_double_p2_float = (parent2 << (p2_float+1));
           parent2_shifted_double_p1_float = (parent2 >> (CHROMOSOME_WIDTH-p1_float-1));

        end

        // Uniform mask selection
        active_uniform_mask = uniform_random_enable ? LFSR_input[CHROMOSOME_WIDTH-1:0]
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
                            child <= (parent2_shifted_fixed & ~mask_single_fixed) |
                                     (parent1 & mask_single_fixed);
                        end else begin
                            child <= (parent1 & mask_double_fixed) |
                                     (parent2_shifted_double_p2)|
                                     (parent2_shifted_double_p1);
                        end
                        crossover_done <= 1'b1;
                    end
                    // Float
                    2'b01: begin
                        if (!crossover_single_double) begin
                            child <= (parent2_shifted_float  & ~mask_single_float) |
                                     (parent1 & mask_single_float);
                        end else begin
                            child <= (parent1 & mask_double_float) | 
                                     (parent2_shifted_double_p2_float) | 
                                     (parent2_shifted_double_p1_float);
                        end
                        crossover_done <= 1'b1;
                    end
                    // Uniform
                    2'b10: begin
                        child <= (parent1 & active_uniform_mask) |
                                 (parent2 & ~active_uniform_mask);
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