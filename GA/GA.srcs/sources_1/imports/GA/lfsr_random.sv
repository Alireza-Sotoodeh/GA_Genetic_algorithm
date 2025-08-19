module lfsr_random #(
    parameter WIDTH1 = 16, 
    parameter WIDTH2 = 15, 
    parameter WIDTH3 = 14, 
    parameter WIDTH4 = 13,  
    parameter defualtSeed1 = 16'hACE1,
    parameter defualtSeed2 = 15'h3BEE,
    parameter defualtSeed3 = 14'h2BAD,
    parameter defualtSeed4 = 13'h1DAD
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   start_lfsr,    // step enable
    // Seed inputs for each LFSR
    input  logic [WIDTH1+WIDTH2+WIDTH3+WIDTH4-1:0] seed_in, // single seed input and max = 288230376151711743
    input  logic                   load_seed,     // reseed all LFSRs
    output logic [WIDTH1-1:0]      random_out     // final whitened output
);

    // State registers for each LFSR
    logic [WIDTH1-1:0] lfsr1;
    logic [WIDTH2-1:0] lfsr2;
    logic [WIDTH3-1:0] lfsr3;
    logic [WIDTH4-1:0] lfsr4;
    
    // Feedback wires
    logic fb1, fb2, fb3, fb4;

    // Primitive polynomials for maximum period
    assign fb1 = lfsr1[15] ^ lfsr1[13] ^ lfsr1[12] ^ lfsr1[10];     // x^16 + x^14 + x^13 + x^11 
    assign fb2 = lfsr2[14] ^ lfsr2[13] ^ lfsr2[11] ^ lfsr2[9];      // x^15 + x^14 + x^12 + x^10  
    assign fb3 = lfsr3[13] ^ lfsr3[11] ^ lfsr3[9] ^ lfsr3[8];       // x^14 + x^12 + x^10 + x^9 
    assign fb4 = lfsr4[12] ^ lfsr4[11] ^ lfsr4[9] ^ lfsr4[8];       // x^13 + x^12 + x^10 + x^9 

    // Shift registers update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
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

    // Combine all LFSRs via XOR 
    logic [WIDTH1-1:0] combined;
    assign combined = lfsr1 ^ {{(WIDTH1-WIDTH2){1'b0}}, lfsr2} ^ {{(WIDTH1-WIDTH3){1'b0}}, lfsr3} ^ {{(WIDTH1-WIDTH4){1'b0}}, lfsr4};

    // Whitening: XOR with shifted versions
    assign random_out = combined  ^ (combined >> 7) ^ (combined << 3);

endmodule
