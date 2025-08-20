`timescale 1ns / 1ps

// -----------------------------------------------------------
// 1. Interface - bundles DUT I/O signals
// -----------------------------------------------------------
interface crossover_if #(parameter CHROMOSOME_WIDTH = 16, parameter LSFR_WIDTH = 16)(input logic clk, rst);
    // Inputs
    logic start_crossover;
    logic [CHROMOSOME_WIDTH-1:0] parent1;
    logic [CHROMOSOME_WIDTH-1:0] parent2;
    logic [1:0] crossover_mode; // 0=fixed, 1=float, 2=uniform
    logic crossover_single_double;
    logic [$clog2(CHROMOSOME_WIDTH):0] crossover_Single_point;
    logic [$clog2(CHROMOSOME_WIDTH):0] crossover_double_R_FirstPoint;
    logic [$clog2(CHROMOSOME_WIDTH):0] crossover_double_R_SecondPoint;
    logic [CHROMOSOME_WIDTH-1:0] mask_uniform;
    logic uniform_random_enable;
    logic [LSFR_WIDTH-1:0] LSFR_input;
    // Outputs
    logic [CHROMOSOME_WIDTH-1:0] child;
    logic crossover_done;
endinterface

// -----------------------------------------------------------
// 2. Testbench module
// -----------------------------------------------------------
module crossover_tb;
    // Clock
    logic CLK = 0;
    always #1 CLK = ~CLK; // 500 MHz

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

    // -------------------------------------------------------
    // 3. DUT instantiation
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

    // -------------------------------------------------------
    // 3.1 Signals for waveform view (assign style)
    // -------------------------------------------------------
    logic Start, Done;
    logic [15:0] P1, P2, Mask, LfsrInp, ChildOut;
    logic [1:0] Mode;
    assign Start    = DUT.start_crossover;
    assign Mode     = DUT.crossover_mode;
    assign P1       = DUT.parent1;
    assign P2       = DUT.parent2;
    assign Mask     = DUT.mask_uniform;
    assign LfsrInp  = DUT.LSFR_input;
    assign ChildOut = DUT.child;
    assign Done     = DUT.crossover_done;

    // -------------------------------------------------------
    // 4. Golden Models (fixing declaration style)
    // -------------------------------------------------------
    function automatic [15:0] golden_fixed(
        input bit dbl,
        input int point1, point2,
        input [15:0] p1, p2
    );
        logic [15:0] mask1, mask2;
        mask1 = (point1 > 0) ? ((1 << point1) - 1) : 0;
        mask2 = (point2 > point1) ? (((1 << point2) - 1) ^ ((1 << point1) - 1)) : 0;
        if (!dbl)
            return (p2 & ~mask1) | (p1 & mask1);
        else
            return (p1 & mask2) | (p2 & ~mask2);
    endfunction

    function automatic [15:0] golden_uniform(
        input [15:0] mask,
        input [15:0] p1, p2
    );
        for (int i = 0; i < 16; i++)
            golden_uniform[i] = mask[i] ? p1[i] : p2[i];
    endfunction

    // -------------------------------------------------------
    // 5. Driver + Checker
    // -------------------------------------------------------
    logic [15:0] exp, sel_mask;
    int fl_point1, fl_point2; // fixed declaration style

    task drive_and_check(
        input [1:0] mode,
        input bit dbl,
        input int p1_point,
        input int p2_point,
        input [15:0] mask_val,
        input bit rand_mask_en,
        input [15:0] lsfr_val,
        input [15:0] par1,
        input [15:0] par2
    );
        @(posedge CLK);
        intf.crossover_mode = mode;
        intf.crossover_single_double = dbl;
        intf.crossover_Single_point = p1_point;
        intf.crossover_double_R_FirstPoint = p1_point;
        intf.crossover_double_R_SecondPoint = p2_point;
        intf.uniform_random_enable = rand_mask_en;
        intf.mask_uniform = mask_val;
        intf.LSFR_input = lsfr_val;
        intf.parent1 = par1;
        intf.parent2 = par2;
        intf.start_crossover = 1'b1;
        @(posedge CLK);
        intf.start_crossover = 1'b0;
        wait(intf.crossover_done);

        case (mode)
            2'b00: exp = golden_fixed(dbl, p1_point, p2_point, par1, par2);
            2'b01: begin
                fl_point1 = lsfr_val[$clog2(16)-1:0];
                fl_point2 = lsfr_val[$clog2(16)+7:8];
                exp = golden_fixed(dbl, fl_point1, fl_point2, par1, par2);
            end
            2'b10: begin
                sel_mask = rand_mask_en ? lsfr_val : mask_val;
                exp = golden_uniform(sel_mask, par1, par2);
            end
        endcase

        test_count++;
        if (intf.child !== exp) begin
            $display("[%t] ERROR: Mode=%0d Expect=%h Got=%h", $time, mode, exp, intf.child);
            error_count++;
        end
    endtask

    // -------------------------------------------------------
    // 6. Stimulus Generator
    // -------------------------------------------------------
    int p1_point, p2_point;
    int mode;
    int rand_mask_en;
    bit dbl;
    task generator(input int num_tests);
        drive_and_check(2'b00, 0, 8, 0, 0, 0, 0, 16'hAAAA, 16'h5555);
        drive_and_check(2'b00, 1, 4, 12, 0, 0, 0, 16'hF0F0, 16'h0FF0);
        drive_and_check(2'b01, 0, 0, 0, 0, 0, 16'h1234, 16'hAAAA, 16'h5555);
        drive_and_check(2'b10, 0, 0, 0, 16'hF0F0, 0, 0, 16'hAAAA, 16'h5555);
        drive_and_check(2'b10, 0, 0, 0, 0, 1, 16'h0FF0, 16'hAAAA, 16'h5555);

        for (int i = 0; i < num_tests; i++) begin
            dbl = $urandom_range(0,1);
            rand_mask_en = $urandom_range(0,1);
            mode = $urandom_range(0,2);
            p1_point = $urandom_range(0,15);
            p2_point = $urandom_range(0,15);
            drive_and_check(mode, dbl, p1_point, p2_point,
                            $urandom, rand_mask_en, $urandom,
                            $urandom, $urandom);
        end
    endtask

    // -------------------------------------------------------
    // 7. Main Test Flow
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
    end
endmodule
