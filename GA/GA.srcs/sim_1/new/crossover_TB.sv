`timescale 1ns / 1ps
// -----------------------------------------------------------
// 1. Interface - bundles DUT I/O signals
// -----------------------------------------------------------
interface crossover_if #(parameter CHROMOSOME_WIDTH = 16, parameter LSFR_WIDTH = 16)(input logic clk, rst);
    // Inputs
    logic 								start_crossover;
    logic [CHROMOSOME_WIDTH-1:0] 		parent1;
    logic [CHROMOSOME_WIDTH-1:0] 		parent2;
    logic [1:0] 						crossover_mode;				// 0=fixed, 1=float, 2=uniform
    logic 								crossover_single_double;	// 0: single, 1: double
    logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_Single_point;
    logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_double_R_FirstPoint;
    logic [$clog2(CHROMOSOME_WIDTH):0] 	crossover_double_R_SecondPoint;
    logic [CHROMOSOME_WIDTH-1:0] 		mask_uniform;
    logic								uniform_random_enable;		// 1 to enable
    logic [LSFR_WIDTH-1:0] 				LSFR_input;
    // Outputs
    logic [CHROMOSOME_WIDTH-1:0] 		child;
    logic 								crossover_done;
endinterface

// -----------------------------------------------------------
// 2. Testbench module
// -----------------------------------------------------------
module crossover_tb;
    // Clock
    logic CLK = 0;
    always #1 CLK = ~CLK; // 500 MHz: 2ns for each clk

    // Reset
    logic RST;
    initial begin
        RST = 1'b1;
        #2 RST = 1'b0;
    end

    // Interface instance
    crossover_if intf(.clk(CLK), .rst(RST));

    // Test counters
    int error_count = 0;
    int test_count  = 0;
	// Expected value 
	logic [15:0] expected_child;


    // -------------------------------------------------------
    // 3. DUT instantiation + LFSR Instantiation
    // -------------------------------------------------------
    crossover #(.CHROMOSOME_WIDTH(16), .LSFR_WIDTH(16)) DUT (
        .clk       (intf.clk),
        .rst_n     (~intf.rst),
        .start_crossover(intf.start_crossover),
        .parent1   (intf.parent1),
        .parent2   (intf.parent2),
        .crossover_mode(intf.crossover_mode),
        .crossover_single_double(intf.crossover_single_double),
        .crossover_Single_point(intf.crossover_Single_point),
        .crossover_double_R_FirstPoint(intf.crossover_double_R_FirstPoint),
        .crossover_double_R_SecondPoint(intf.crossover_double_R_SecondPoint),
        .mask_uniform(intf.mask_uniform),
        .uniform_random_enable(intf.uniform_random_enable),
        .LSFR_input(intf.LSFR_input),
        .child(intf.child),
        .crossover_done(intf.crossover_done)
    );
	
	// LSFR
	    lfsr_SudoRandom #(
        .WIDTH1(16),
        .WIDTH2(15),
        .WIDTH3(14),
        .WIDTH4(13),
        .defualtSeed1(16'hACE1),
        .defualtSeed2(15'h3BEE),
        .defualtSeed3(14'h2BAD),
        .defualtSeed4(13'h1DAD)
    ) lfsr_inst (
        .clk(CLK),
        .rst(RST),
        .start_lfsr(1),
        .seed_in(0),
        .load_seed(0),
        .random_out(intf.LSFR_input)
    );
	
    // -------------------------------------------------------
    // 3.1 Signals for waveform view (assign style)
    // -------------------------------------------------------
    logic Start, Done, crossover_single_double, MaskRandom, Single0_Double1;
    logic [15:0] P1, P2, Mask, LfsrInp, ChildOut;
	logic [3:0] SinglePoint, DoublePoint1R, DoublePoint2R;
    logic [1:0] Mode;
    assign Start    		= intf.start_crossover;
    assign P1       		= intf.parent1;
    assign P2       		= intf.parent2;
	assign Mode     		= intf.crossover_mode;
	assign Single0_Double1 	= intf.crossover_single_double;
	assign SinglePoint		= intf.crossover_Single_point;
	assign DoublePoint1R	= intf.crossover_double_R_FirstPoint;
	assign DoublePoint2R	= intf.crossover_double_R_SecondPoint;
    assign Mask     		= intf.mask_uniform;
	assign MaskRandom		= intf.uniform_random_enable;
    assign LfsrInp  		= intf.LSFR_input;
    assign ChildOut 		= intf.child;
    assign Done     		= intf.crossover_done;

    // -------------------------------------------------------
    // 4. Generator (manual + random)
    // -------------------------------------------------------
    task generator(input int num_tests);
	

    // MODE 0: FIXED CROSSOVER - SINGLE POINT
		// Test 1: Single point at 0 (edge case)
		intf.parent1                     = 16'b0000000000000000;
		intf.parent2                     = 16'b1111111111111111;
		intf.crossover_mode              = 2'b00;
		intf.crossover_single_double     = 1'b0;
		intf.crossover_Single_point      = 4'b0000;  // Point 0 - should take all from parent2
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);


		// Test 2: Single point at 16 (edge case - max)
		intf.parent1                     = 16'b1010101010101010;
		intf.parent2                     = 16'b0101010101010101;
		intf.crossover_mode              = 2'b00;
		intf.crossover_single_double     = 1'b0;
		intf.crossover_Single_point      = 4'b1111;  // Point 15 - should take all from parent1
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);


		// Test 3: Single point at middle
		intf.parent1                     = 16'b1111000011110000;
		intf.parent2                     = 16'b0000111100001111;
		intf.crossover_mode              = 2'b00;
		intf.crossover_single_double     = 1'b0;
		intf.crossover_Single_point      = 4'b1000;  // Point 8
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);

    // MODE 0: FIXED CROSSOVER - DOUBLE POINT
		// Test 4: Double point with points 0 and 16
		intf.parent1                     = 16'b1010101010101010;
		intf.parent2                     = 16'b0101010101010101;
		intf.crossover_mode              = 2'b00;
		intf.crossover_single_double     = 1'b1;
		intf.crossover_double_R_FirstPoint  = 4'b0000;  // Point 0
		intf.crossover_double_R_SecondPoint = 4'b1111;  // Point 15
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);


		// Test 5: Double point with adjacent points
		intf.parent1                     = 16'b1111111111111111;
		intf.parent2                     = 16'b0000000000000000;
		intf.crossover_mode              = 2'b00;
		intf.crossover_single_double     = 1'b1;
		intf.crossover_double_R_FirstPoint  = 4'b0111;  // Point 7
		intf.crossover_double_R_SecondPoint = 4'b1000;  // Point 8
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);
	 

		// Test 6: Double point with invalid order (second < first)
		intf.parent1                     = 16'b1111000011110000;
		intf.parent2                     = 16'b0000111100001111;
		intf.crossover_mode              = 2'b00;
		intf.crossover_single_double     = 1'b1;
		intf.crossover_double_R_FirstPoint  = 4'b1000;  // Point 8
		intf.crossover_double_R_SecondPoint = 4'b0100;  // Point 4 (invalid: 4 < 8)
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);


    // MODE 1: FLOAT CROSSOVER (using LFSR input)
		// Test 7: Float single point with LFSR = 0
		intf.parent1                     = 16'b0000000000000000;
		intf.parent2                     = 16'b1111111111111111;
		intf.crossover_mode              = 2'b01;
		intf.crossover_single_double     = 1'b0;
		intf.LSFR_input                  = 16'h0000;  // Point 0
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);


		// Test 8: Float double point with LFSR values
		intf.parent1                     = 16'b1111000011110000;
		intf.parent2                     = 16'b0000111100001111;
		intf.crossover_mode              = 2'b01;
		intf.crossover_single_double     = 1'b1;
		intf.LSFR_input                  = 16'h3478;  // Points: 8 (0x8) and 7 (0x7) - invalid order
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);



    // MODE 2: UNIFORM CROSSOVER
		// Test 9: Uniform with all 1s mask
		intf.parent1                     = 16'b1010101010101010;
		intf.parent2                     = 16'b0101010101010101;
		intf.crossover_mode              = 2'b10;
		intf.mask_uniform                = 16'b1111111111111111;  // All from parent1
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);


		// Test 10: Uniform with all 0s mask;
		intf.parent1                     = 16'b1010101010101010;
		intf.parent2                     = 16'b0101010101010101;
		intf.crossover_mode              = 2'b10;
		intf.mask_uniform                = 16'b0000000000000000;  // All from parent2
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);


		// Test 11: Uniform with alternating mask
		intf.parent1                     = 16'b1111000011110000;
		intf.parent2                     = 16'b0000111100001111;
		intf.crossover_mode              = 2'b10;
		intf.mask_uniform                = 16'b1010101010101010;  // Alternating
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);


		// Test 12: Uniform with random enable (using LFSR)
		intf.parent1                     = 16'b1111111111111111;
		intf.parent2                     = 16'b0000000000000000;
		intf.crossover_mode              = 2'b10;
		intf.mask_uniform                = 16'b0000000000000000;  // Ignored when random enabled
		intf.uniform_random_enable       = 1'b1;
		intf.LSFR_input                  = 16'b1010101010101010;  // Will be used as mask
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);

    // BOUNDARY AND ERROR CASES
		// Test 13: Invalid mode (should default)
		intf.parent1                     = 16'b1111111111111111;
		intf.parent2                     = 16'b0000000000000000;
		intf.crossover_mode              = 2'b11;  // Invalid mode
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);
		// Should be 0 (default)

		// Test 14: Same parents
		intf.parent1                     = 16'b1100110011001100;
		intf.parent2                     = 16'b1100110011001100;
		intf.crossover_mode              = 2'b00;
		intf.crossover_single_double     = 1'b0;
		intf.crossover_Single_point      = 4'b1000;
		intf.mask_uniform                = 16'b0000000000000000;
		intf.uniform_random_enable       = 1'b0;
		@(posedge CLK);
		intf.start_crossover = 1'b1;
		@(posedge CLK);
		intf.start_crossover = 1'b0;
		check_result();
		@(posedge CLK);
		// Should be same as parents
		
		intf.start_crossover 				= 1'b1;
	//randomized
		for (int i = 0; i < num_tests; i++) begin
			// Apply randomized inputs
			intf.parent1                       = $urandom();                
			intf.parent2                       = $urandom();                
			intf.crossover_mode                = $urandom_range(0, 3);
			intf.crossover_single_double       = $urandom_range(0, 1);
			intf.crossover_Single_point        = $urandom_range(0, 15);
			intf.crossover_double_R_FirstPoint = $urandom_range(0, 15);
			intf.crossover_double_R_SecondPoint= $urandom_range(0, 15);
			intf.mask_uniform                  = $urandom();
			intf.uniform_random_enable         = $urandom_range(0, 1);
			// Wait until crossover completes
			check_result();
		@(posedge CLK);
		end

    endtask
    // -------------------------------------------------------
    // 5. Driver 
    // -------------------------------------------------------
    /*task drive();
		@(posedge CLK);
		#1;
		monitor();
    endtask
    */
    // -------------------------------------------------------
    // 6. monitor
    // -------------------------------------------------------
	/*task monitor();
		//check_result();
	endtask*/
	// -------------------------------------------------------
    // 7. check_result (this part is done by AI)
    // -------------------------------------------------------
task automatic check_result();
    logic [15:0] mask_calc;
    logic [3:0] single_pt, first_pt, second_pt; // from LFSR
    int sp_int, fp_int, sp2_int;

    // Match DUT's extraction for CHROMOSOME_WIDTH=16
    single_pt = intf.LSFR_input[3:0];
    first_pt  = intf.LSFR_input[7:4];
    second_pt = intf.LSFR_input[11:8];

    sp_int  = single_pt;
    fp_int  = first_pt;
    sp2_int = second_pt;

    case (intf.crossover_mode)
       
        // 00: FIXED CROSSOVER
        
        2'b00: begin
            if (!intf.crossover_single_double) begin
                // Single point
                if (intf.crossover_Single_point >= 16)
                    mask_calc = 16'hFFFF;
                else if (intf.crossover_Single_point > 0)
                    mask_calc = (16'(1) << intf.crossover_Single_point) - 1;
                else
                    mask_calc = '0;
                expected_child = (intf.parent2 & ~mask_calc) | (intf.parent1 & mask_calc);
            end
            else begin
                // Double point
                if (intf.crossover_double_R_SecondPoint > intf.crossover_double_R_FirstPoint &&
                    intf.crossover_double_R_SecondPoint <= 16) begin
                    mask_calc = ((16'(1) << intf.crossover_double_R_SecondPoint) - 1) ^
                                 ((16'(1) << intf.crossover_double_R_FirstPoint) - 1);
                end
                else begin
                    // Invalid order → treat as single point at first point
                    if (intf.crossover_double_R_FirstPoint >= 16)
                        mask_calc = 16'hFFFF;
                    else if (intf.crossover_double_R_FirstPoint > 0)
                        mask_calc = (16'(1) << intf.crossover_double_R_FirstPoint) - 1;
                    else
                        mask_calc = '0;
                end
                expected_child = (intf.parent1 & mask_calc) | (intf.parent2 & ~mask_calc);
            end
        end

        
        // 01: FLOAT CROSSOVER
        
        2'b01: begin
            if (!intf.crossover_single_double) begin
                // Single point from LFSR
                if (sp_int >= 16)
                    mask_calc = 16'hFFFF;
                else if (sp_int > 0)
                    mask_calc = (16'(1) << sp_int) - 1;
                else
                    mask_calc = '0;
                expected_child = (intf.parent2 & ~mask_calc) | (intf.parent1 & mask_calc);
            end
            else begin
                // Double point from LFSR
                if (sp2_int > fp_int && sp2_int <= 16) begin
                    mask_calc = ((16'(1) << sp2_int) - 1) ^ ((16'(1) << fp_int) - 1);
                end
                else begin
                    // Invalid order → treat as single point at first_pt
                    if (fp_int >= 16)
                        mask_calc = 16'hFFFF;
                    else if (fp_int > 0)
                        mask_calc = (16'(1) << fp_int) - 1;
                    else
                        mask_calc = '0;
                end
                expected_child = (intf.parent1 & mask_calc) | (intf.parent2 & ~mask_calc);
            end
        end

        
        // 10: UNIFORM CROSSOVER
        
        2'b10: begin
            logic [15:0] active_mask;
            active_mask = (intf.uniform_random_enable) ? intf.LSFR_input[15:0] : intf.mask_uniform;
            for (int i = 0; i < 16; i++)
                expected_child[i] = active_mask[i] ? intf.parent1[i] : intf.parent2[i];
        end

        
        // Default: invalid mode
        
        default: expected_child = '0;
    endcase

    // Compare with DUT output
    test_count++;
	if (expected_child !== intf.child) begin
		error_count++;
		$display("------------------------------------------------------------");
		$display("ERROR @Time=%0t: Test %0d", $time, test_count);
		$display("  Mode                    = %b", intf.crossover_mode);
		$display("  Expected Child          = %h", expected_child);
		$display("  DUT Child               = %h", intf.child);
		$display("  Parent1                 = %h", intf.parent1);
		$display("  Parent2                 = %h", intf.parent2);
		$display("  crossover_Single_point  = %h", intf.crossover_Single_point);
		$display("  crossover_double_R_FirstPoint  = %h", intf.crossover_double_R_FirstPoint);
		$display("  crossover_double_R_SecondPoint = %h", intf.crossover_double_R_SecondPoint);
		$display("  LSFR_input              = %h", intf.LSFR_input);

		// Extra per‑mode context
		if (intf.crossover_mode <= 2'b01) begin
			$display("  crossover_single_double = %b", intf.crossover_single_double);
			$display("  mask_calc               = %h", mask_calc);
		end
		if (intf.crossover_mode == 2'b10) begin
			$display("  UniformRandomEnable     = %b", intf.uniform_random_enable);
			$display("  mask_uniform            = %h", intf.mask_uniform);
		end
		$display("------------------------------------------------------------");
	end
endtask
    // -------------------------------------------------------
    // . Main Test Flow
    // -------------------------------------------------------
    initial begin
        intf.start_crossover = 0;
        intf.parent1 = 0;
        intf.parent2 = 0;
        intf.mask_uniform = 0;
        intf.uniform_random_enable = 0;
        intf.LSFR_input = 0;
        @(negedge RST);
        generator(100);
        $display("Test finished. Ran %0d tests, errors = %0d", test_count, error_count);
        if (error_count==0) $display("TEST PASSED");
        else $display("TEST FAILED");
        $finish;
        $stop;
    end
endmodule
