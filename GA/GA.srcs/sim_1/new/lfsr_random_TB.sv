`timescale 1ns / 1ps // set time scale
// -----------------------------------------------------------
// 1. Interface - bundles DUT I/O signals
// -----------------------------------------------------------
interface lsfr_random_if(input logic clk, rst); 
    //inputs 
    logic          start_lfsr;
    logic  [57:0]  seed_in;    //16+15+14+13 = 58 bit
    logic          load_seed;
    //outputs
    logic  [15:0]  random_out;
endinterface

// -----------------------------------------------------------
// 2. Testbench module
// -----------------------------------------------------------
module lsfr_SudoRandom_TB;

    //clk
    logic CLK = 0;
    always #1 CLK = ~CLK; // clk period 2ns (500MHz)
    
    //rst
    logic RST;  // active-high reset
    initial begin
         RST = 1'b1;  
        #2 RST = 1'b0; //rst for one clk
    end
    
    // interface instance
    lsfr_random_if intf(.clk(CLK), .rst(RST));
    
    // test counters
    int error_count = 0;
    int test_count  = 0;

    // -------------------------------------------------------
    // 3. DUT instantiation (matching your latest lfsr_random.sv)
    // -------------------------------------------------------
    lfsr_SudoRandom DUT (
    .clk       (intf.clk),
    .rst       (intf.rst),
    .start_lfsr(intf.start_lfsr),
    .seed_in   (intf.seed_in),
    .load_seed (intf.load_seed),
    .random_out(intf.random_out)
    );
    
     // using assign to see wave in output
    logic Start, LoadSeed;
    logic [57:0] SeedIn;
    logic [16:0] Output_lsfr;
    assign Start       = DUT.start_lfsr;
    assign SeedIn      = DUT.seed_in;
    assign LoadSeed    = DUT.load_seed;
    assign Output_lsfr = DUT.random_out;
    // -------------------------------------------------------
    // 4. Generator Task (manual + random)
    // -------------------------------------------------------
    task generator(input int num_tests);
        // ***** Phase 1: Manual fixed inputs *****
        // Reset signals
        intf.start_lfsr = 1'b0;
        intf.seed_in    = 58'd0;
        intf.load_seed  = 1'b0;
        repeat (2) @(posedge intf.clk); // wait 2 cycles
        
        // defualt seeds 
        intf.start_lfsr = 1'b1;
        intf.seed_in    = 58'd0;
        intf.load_seed  = 1'b0;
        repeat (10) @(posedge intf.clk); // wait 10 cycles
        
        // Load a known seed
        intf.seed_in   = 58'h0A55_AA55_3C; // example seed
        intf.load_seed = 1'b1;
        @(posedge intf.clk);
        intf.load_seed = 1'b0;
        repeat (10) @(posedge intf.clk); // wait 10 cycles
        
        //reset to deufalt seed
        RST  = 1'b1;
        repeat (2)@(negedge intf.clk);
        RST  = 1'b0;
        
        // Step the LFSR manually a few times
        repeat (4) begin
            intf.start_lfsr = 1'b0;
            @(posedge intf.clk);
            intf.start_lfsr = 1'b1;
            @(posedge intf.clk);
        end
        intf.start_lfsr = 1'b1; //make sure the lsfr is working 
        // ***** Phase 2: Random seeds and run *****
        for (int i = 0; i < num_tests; i++) begin
            // Randomly reseed occasionally
            if ($urandom_range(0,4) == 0) begin
                intf.seed_in   = $urandom;
                intf.load_seed = 1'b1;
                @(posedge intf.clk);
                intf.load_seed = 1'b0;
            end
            
            // Enable LFSR shifting
            intf.start_lfsr = 1'b1;
            @(posedge intf.clk);
            intf.start_lfsr = 1'b0;
            @(posedge intf.clk);
            
            test_count++;
            // Optional check: could compare intf.random_out to a golden model here
            $display("[%0t] LFSR output = 0x%h", $time, intf.random_out);
        end
    endtask

    // -------------------------------------------------------
    // 5. Main Test Flow
    // -------------------------------------------------------
    initial begin
    @(negedge RST); //wait for reset to be done! (active high reset)
    generator(50);
        
        $display("Test finished. Ran %0d cycles, errors = %0d", test_count, error_count);
        $finish;
        $stop;
    end
endmodule

