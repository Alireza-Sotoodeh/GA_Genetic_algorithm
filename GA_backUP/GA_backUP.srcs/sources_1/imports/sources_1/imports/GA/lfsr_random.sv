(* keep_hierarchy = "yes" *) //to prevent from begin changed by optimizer
module lfsr_SudoRandom #(
    parameter WIDTH1 = 16, 
    parameter WIDTH2 = 15, 
    parameter WIDTH3 = 14, 
    parameter WIDTH4 = 13,  
    parameter defualtSeed1 = 16'hACE1,
    parameter defualtSeed2 = 15'h3BEE,
    parameter defualtSeed3 = 14'h2BAD,
    parameter defualtSeed4 = 13'h1DAD
)(
    clk,
    rst,
    start_lfsr,
    seed_in,
    load_seed,
    random_out
);

//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
    //inputs
    input  logic                   clk;
    input  logic                   rst;           // high active rst
    input  logic                   start_lfsr;    // step enable
    input  logic [WIDTH1+WIDTH2+WIDTH3+WIDTH4-1:0] seed_in; // single seed input and max = 288230376151711743
    input  logic                   load_seed;     // reseed all LFSRs
    
    //outputs
    output logic [WIDTH1-1:0]      random_out;     // final whitened output
//''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

	//============================================================
	// define logics 
    //============================================================
    // Use SRL16E for efficient shift register implementation
    (* srl_style = "srl" *)          // SRL LUTs for compact implementation
    (* shreg_extract = "yes" *)      // Extract as shift registers
    (* keep = "true" *)              // Prevent optimization
    logic [WIDTH1-1:0] lfsr1;

    (* srl_style = "srl" *)
    (* shreg_extract = "yes" *)
    (* keep = "true" *)
    logic [WIDTH2-1:0] lfsr2;

    (* srl_style = "srl" *)
    (* shreg_extract = "yes" *)
    (* keep = "true" *)
    logic [WIDTH3-1:0] lfsr3;

    (* srl_style = "srl" *)
    (* shreg_extract = "yes" *)
    (* keep = "true" *)
    logic [WIDTH4-1:0] lfsr4;

    // Feedback logic - optimize with LUTs
    (* keep = "true" *)
    (* lut1 = "yes" *)               // Pack into single LUTs
    logic fb1, fb2, fb3, fb4;

    // Combined output logic
    (* use_dsp = "no" *)           // DON'T use DSP
    (* keep = "true" *)
    logic [WIDTH1-1:0] combined;
	//============================================================
	// Primitive polynomials for maximum period (width_independency_space)
    //============================================================
    assign fb1 = lfsr1[WIDTH1-1] ^ lfsr1[WIDTH1-3] ^ lfsr1[WIDTH1-4] ^ lfsr1[WIDTH1-6];       // x^16 + x^14 + x^13 + x^11 
    assign fb2 = lfsr2[WIDTH2-1] ^ lfsr2[WIDTH2-2] ^ lfsr2[WIDTH2-4] ^ lfsr2[WIDTH2-5];       // x^15 + x^14 + x^12 + x^10  
    assign fb3 = lfsr3[WIDTH3-1] ^ lfsr3[WIDTH3-3] ^ lfsr3[WIDTH3-5] ^ lfsr3[WIDTH3-7];       // x^14 + x^12 + x^10 + x^8
    assign fb4 = lfsr4[WIDTH4-1] ^ lfsr4[WIDTH4-2] ^ lfsr4[WIDTH4-4] ^ lfsr4[WIDTH4-5];       // x^13 + x^12 + x^10 + x^9 

    // Shift registers update
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // default non-zero seeds
            lfsr1 <= defualtSeed1;
            lfsr2 <= defualtSeed2;
            lfsr3 <= defualtSeed3;
            lfsr4 <= defualtSeed4;
        end else if (load_seed) begin
            // Slice the single seed 
            lfsr1 <= seed_in[WIDTH1+WIDTH2+WIDTH3+WIDTH4-1 : WIDTH2+WIDTH3+WIDTH4];
            lfsr2 <= seed_in[WIDTH2+WIDTH3+WIDTH4-1 : WIDTH3+WIDTH4];
            lfsr3 <= seed_in[WIDTH3+WIDTH4-1 : WIDTH4];
            lfsr4 <= seed_in[WIDTH4-1:0];
        end else if (start_lfsr) begin
            lfsr1 <= {fb1, lfsr1[WIDTH1-1:1]};
            lfsr2 <= {fb2, lfsr2[WIDTH2-1:1]};
            lfsr3 <= {fb3, lfsr3[WIDTH3-1:1]};
            lfsr4 <= {fb4, lfsr4[WIDTH4-1:1]};
        end
    end

    // Combine all LFSRs via XOR  (by default first num would be A835 hex)
    assign combined = lfsr1 ^ {{(WIDTH1-WIDTH2){1'b0}}, lfsr2} ^ {{(WIDTH1-WIDTH3){1'b0}}, lfsr3} ^ {{(WIDTH1-WIDTH4){1'b0}}, lfsr4};

    // Whitening: XOR with shifted versions
    always_comb begin
        random_out = combined  ^ (combined >> 7) ^ (combined << 3);
    end
endmodule