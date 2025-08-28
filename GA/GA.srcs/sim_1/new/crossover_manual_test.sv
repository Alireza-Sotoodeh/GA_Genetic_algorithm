`timescale 1ns/1ps

module crossover_manual_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CHROMOSOME_WIDTH = 16;
    localparam LFSR_WIDTH       = 16;

    // LFSR config (match lfsr_random.sv)
    localparam LFSR_WIDTH1      = 16;
    localparam LFSR_WIDTH2      = 15;
    localparam LFSR_WIDTH3      = 14;
    localparam LFSR_WIDTH4      = 13;
    localparam LFSR_SEED_WIDTH  = LFSR_WIDTH1+LFSR_WIDTH2+LFSR_WIDTH3+LFSR_WIDTH4;

    // =========================================================================
    // Testbench Signals
    // =========================================================================
    reg clk, rst;
    reg start_crossover;

    reg  [CHROMOSOME_WIDTH-1:0] parent1, parent2;
    reg  [1:0]  crossover_mode;             // 0: fixed, 1: float, 2: uniform
    reg         crossover_single_double;    // 0: single, 1: double
    reg  [$clog2(CHROMOSOME_WIDTH):0] crossover_single_point;
    reg  [$clog2(CHROMOSOME_WIDTH):0] crossover_double_point1;
    reg  [$clog2(CHROMOSOME_WIDTH):0] crossover_double_point2;
    reg  [CHROMOSOME_WIDTH-1:0] mask_uniform;
    reg                         uniform_random_enable;
    
    wire [CHROMOSOME_WIDTH-1:0] child;
    wire crossover_done;

    // =========================================================================
    // LFSR instance
    // =========================================================================
    reg start_lfsr, load_seed;
    reg [LFSR_SEED_WIDTH-1:0] seed_in;
    wire [LFSR_WIDTH1-1:0] random_out;
    
    lfsr_SudoRandom #(
        .WIDTH1(LFSR_WIDTH1), .WIDTH2(LFSR_WIDTH2),
        .WIDTH3(LFSR_WIDTH3), .WIDTH4(LFSR_WIDTH4)
    ) lfsr_inst (
        .clk(clk),
        .rst(rst),
        .start_lfsr(start_lfsr),
        .seed_in(seed_in),
        .load_seed(load_seed),
        .random_out(random_out)
    );

    // =========================================================================
    // DUT instance
    // =========================================================================
    crossover #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .LFSR_WIDTH(LFSR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start_crossover(start_crossover),
        .parent1(parent1),
        .parent2(parent2),
        .crossover_mode(crossover_mode),
        .crossover_single_double(crossover_single_double),
        .crossover_single_point(crossover_single_point),
        .crossover_double_point1(crossover_double_point1),
        .crossover_double_point2(crossover_double_point2),
        .mask_uniform(mask_uniform),
        .uniform_random_enable(uniform_random_enable),
        .LFSR_input(random_out),
        .child(child),
        .crossover_done(crossover_done)
    );

    // =========================================================================
    // Clock
    // =========================================================================
    initial clk = 0;
    always #50 clk = ~clk;
    
    integer clk_counter;
    initial clk_counter = 0;
    always @(posedge clk) clk_counter <= clk_counter + 1;

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        // Default init
        rst = 1;
        start_crossover = 0;
        parent1 = 16'h0000;
        parent2 = 16'h0000;
        crossover_mode = 0;
        crossover_single_double = 0;
        crossover_single_point = 4;
        crossover_double_point1 = 5;
        crossover_double_point2 = 10;
        mask_uniform = 16'hAAAA;
        uniform_random_enable = 0;
        start_lfsr = 0;
        load_seed  = 0;
        seed_in = {16'hACE1, 15'h3BEE, 14'h2BAD, 13'h1DAD};
        // Reset
        @(negedge clk) rst = 0;

        // Load Seed
        @(posedge clk); load_seed = 1;
        @(posedge clk); load_seed = 0;
        start_lfsr = 1;
        // Warm up LFSR
        repeat (5) @(posedge clk);
        
        start_crossover = 1;
        parent1 = 16'hFFFF;
        parent2 = 16'h0000;
        crossover_mode = 1;
        crossover_single_double = 0;
        crossover_single_point = 8;
        crossover_double_point1 = 5;
        crossover_double_point2 = 10;
        mask_uniform = 16'hAAAA;
        uniform_random_enable = 0;

        
    end
endmodule
