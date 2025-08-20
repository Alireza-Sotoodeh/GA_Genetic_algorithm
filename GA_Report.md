# GA (genetic algorithm) Projet Report

**Name:** Alirzea Sotoodeh

**Date:** 1404/05/28

**master:** Phd. Ali Mahani

**define:** a search heuristic that mimics the process of natural selection to find optimal or near-optimal solutions to optimization and search problems.

-------------------

# Goals

- **inputs:** CLK,  Data_in `16 bit`, population, start, iteration, 1 or 2 point cross over, mutation rate

- **Output:** Data_out `16 bit`, Done, number of chromosome

- **Optional input:** 

- **Optional output:** best chromosome, Data_out_stage

- it shuld include a nice **test bench** (like what we have done in class)

-------------

# Per‑file analysis (raw code):

## crossover

**Purpose:** Performs single‑point crossover between two parents to create one child chromosome.

**Parameters:**

- `CHROMOSOME_WIDTH` (default = **8 bits**) — length of chromosome.

**Key Signals:**

- **Inputs:**
  - `parent1` & `parent2` → each 8 bits
  - `crossover_point` → 3 bits (can specify 0–7)
  -  `start_crossover` 
  - `rst_n` & `clk`
- **Outputs:**
  - `child` → 8 bits
  - `crossover_done` → 1 bit

**behavior:**

- on `!rst_n` it would be reset and  `child <= '0;` and `crossover_done <= 1'b0;`
- On `start_crossover` high, `child` is formed by **<u>manually</u>** taking upper 6 bits from `parent1` and lower 3 bits from `parent2` (manual crossover! )

**Types of cross over:**

- **Fixed-Point (Single-Point) Crossover**
  
  > **Description**: A single crossover point is chosen at a fixed bit position (e.g., bit 4). The child is formed by taking bits from Parent1 before the crossover point and bits from Parent2 after (and including) the crossover point.
  > 
  > **Diagram**:
  > 
  > ```tsx
  > Parent1:  1 0 1 0 | 1 0 1 0
  > Parent2:  0 0 1 1 | 0 0 1 1
  >           |       ^ Crossover point (bit 4)
  > Child:    1 0 1 0 | 0 0 1 1
  > Result:   Child = 10100011
  > ```

- **Fixed-Point (Two-Point) Crossover**
  
  > **Description**: Two fixed crossover points are chosen (e.g., bits 2 and 6). The child is formed by taking bits from Parent1 before the first point, bits from Parent2 between the points, and bits from Parent1 after the second point.
  > 
  > **Diagram**:
  > 
  > ```tsx
  > Parent1:  1 0 | 1 0 1 0 | 1 0
  > Parent2:  0 0 | 1 1 0 0 | 1 1
  >               ^ bit2    ^ bit6
  > Child:    1 0 | 1 1 0 0 | 1 0
  > Result:   Child = 10110010
  > ```

- Floating-Point (Single-Point) Crossover
  
  > **Description**: A single crossover point is determined as a fraction of the chromosome length (e.g., 0.5, corresponding to bit 4 for an 8-bit chromosome). The child is formed similarly to fixed-point single-point crossover, but the point is conceptually based on a floating-point ratio. For simplicity, we assume the crossover point maps to bit 4.
  > 
  > **Diagram**:
  > 
  > ```tsx
  > Parent1:  1 0 1 0 | 1 0 1 0
  > Parent2:  0 0 1 1 | 0 0 1 1
  >           |       ^ Crossover point (0.5 * 8 = bit 4)
  > Child:    1 0 1 0 | 0 0 1 1
  > Result:   Child = 10100011
  > ```

- Floating-Point (Two-Point) Crossover
  
  > **Description**: Two crossover points are chosen as fractions of the chromosome length (e.g., 0.25 and 0.75, mapping to bits 2 and 6). The child is formed by taking bits from Parent1 before the first point, bits from Parent2 between the points, and bits from Parent1 after the second point.
  > 
  > **Diagram**:
  > 
  > ```tsx
  > Parent1:  1 0 | 1 0 1 0 | 1 0
  > Parent2:  0 0 | 1 1 0 0 | 1 1
  >               ^         ^ (0.25 * 8 = bit 2)(0.75 * 8 = bit 6)
  > Child:    1 0 | 1 1 0 0 | 1 0
  > Result:   Child = 10110010
  > ```

**Issues to fix:**

- The **crossover_point** input is unused → crossover is manual (fix it by making the user choose the crossover point as mentioned) so it should be dynamic
  
  ```v
  child <= {parent1[CHROMOSOME_WIDTH-1:crossover_point], parent2[crossover_point-1:0]};
  ```

- inccreas the cross over methodes (single‑point, two‑point, uniform crossover)

- if `crossover_point = CHROMOSOME_WIDTH` or `crossover_point = 0` then we have error

- cross over can be improve by making it undependet from CHROMOSOME_WIDTH `input logic [$clog2(CHROMOSOME_WIDTH):0] crossover_point`

## fitness_evaluator

**Purpose:** Computes the fitness score of a chromosome.

- `CHROMOSOME_WIDTH` → 8 bits
- `FITNESS_WIDTH` → 10 bits (can represent values from 0–1023)

**Key Signals:**

- **Inputs:**
  - `rst_n`&`clk`
  - `start_evaluation`
  - `chromosome` (8 bits)
- **Outputs:**
  - `fitness` (10 bits)
  - `evaluation_done` (1 bit)

**behavior:**

- Fitness function = **count number of '1’s in chromosome**
- Uses simple `for` loop inside a sequential always_ff
- Resets: Synchronous to clk with async rst_n → `fitness` cleared, `evaluation_done` low.

**Issues to fix:**

- [ ] The `for` loop updates `fitness <= fitness + 1'b1;` inside same always_ff → in synthesis on FPGAs, this cumulative assignment inside loop generally works because it’s rolled combinatorially by synthesis, but it’s cleaner to store count in a temp variable.
- [ ] Fitness max possible = 8, FIT_WIDTH=10 → fine, but over-allocates bits a bit.

## lfsr_random

**Purpose:** Random Number Generator by using LSFR **(Linear Feedback Shift Register)** and Produces pseudo‑random sequences. act like **<u>Wheel of Fortune</u>** fof choosing from  population!

**Parameters:**

- `WIDTH` (e.g., 8 for GA usage)

**Key Signals:**

- **Inputs:**
  - `rst_n` & `clk`
  - `enable`
- **Outputs:**
  - `random_out`

**behavior:**

- Standard LFSR feedback — on enable, shifts right, MSB fed by XOR of certain taps.

- For better undrstanding here is an example:
  
  1. (e.g.)`lfsr_reg` = `1111 1111`
  
  2. `feedback` = `1 (bit7)` XOR `1 (bit5)` XOR `1 (bit4)` XOR `1 (bit3)` = 0  or we can simply say `XOR 1 XOR 1 XOR 1 XOR 1= 0`
  
  3. insert and shift: {feedback, lfsr_reg[WIDTH-1:1]}; = {0, 1111 111} →  `random_out = 0111 1111`
  
  4. the cycle start ove and over again.
  
  <img src="file:///C:/Users/Alireza/AppData/Roaming/marktext/images/2025-08-19-19-30-36-deepseek_mermaid_20250819_06e147.png" title="" alt="" width="646">

**Issues to fix:**

- Taps are not parameterized or visible in code snippet → need correct polynomial per WIDTH for maximal length.

- choose th right primitive polynomial
  
  `x^16 + x^14 + x^13 + x^11 ` 65535 states before repetition
  
  formula to calculate: $extPeriod=2^n−1$

- No seed input → always starts at ‘1’ : `load_seed`

- how can i make it more randomized ?
  
  - 2 LSFR and XOR the output : About 2 billion states before iteration
  
  - 4 LSFR and XOR the output : 2.88*10^17 states before iteration
  
  - Change Seed Periodically
  
  - ignore the output Periodically and jump 
  
  - Whitening
  
  ```v
  logic [15:0] whitened;
  assign whitened = random_out ^ (random_out >> 7) ^ (random_out << 3);
  ```

## mutation

**Purpose:** Applies bit‑flip mutation.

**Parameters:**

- `Chromosome width` = 8 bits

**Key Signals:**

- **Inputs:**
  - `rst_n` & `clk`
  - `start_mutation`
  - `child_in (8bit)`
  - `mutation_mask (8bit)` Random bits to determine mutation
  - `mutation_rate (8 bit)` range 0-255, higher means more likely to mutate
- **Outputs:**
  - `child_out (8bit)`
  - `mutation_done`

**Behavior:**

- For each bit: If corresponding mutation_mask[i] < mutation_rate, bit is flipped.
- Uses `mutation_mask` from `lfsr_random`.

**Potential Issue:**

- [ ] Logic is incorrect and needs to be fixed (For each bit, apply mutation if random value < mutation_rate) refer to `how???`

## selection

**Purpose:** Roulette‑wheel selection for parent index. (higher fitness == higher chance to be chosen as parent!)

**Parameters:**

- `CHROMOSOME_WIDTH `= 8
  
  `ADDR_WIDTH` = $clog2(POPULATION_SIZE)→ `clog2 == Ceiling Logarithm base 2` used for **"Calculate the minimum number of bits needed to uniquely address every member of the population."**
  
  `POPULATION_SIZE` = 16, addresses → 4 bits

- `FITNESS_WIDTH` = 10 bits

**Key Signals:**

- **Inputs:**
  - `rst_n` & `clk`
  - `start_selection`
  - `fitness_values`
  - `total_fitness` Random bits to determine mutation
- **Outputs:**
  - `selected_parent`
  - `selection_done`

**Flow:**

- Generates random position (scaled) via LFSR × total fitness → chooses first chromosome where cumulative >= random position.

**Potential Issue:**

- [ ] Random scaling:
  
  `roulette_position = (random_value * total_fitness) >> CHROMOSOME_WIDTH;`
  
  For 8‑bit chromosomes, this divides by 256 → might cause bias for small total_fitness values.

- [ ] Doesn’t protect against total_fitness=0 → division trivial, selection may pick index 0 always.

## population_memory

**Purpose:** Stores chromosomes in block RAM (distributed reg array).

**Spec:**

- Depth = 16, width = 8 bits

**Potential Issues:**

- [ ] No initialization from file → initial state undefined until explicitly written.
- [ ] Read is combinational, write is synchronous — fine for Vivado inference.

## genetic_algorithm (Top)

**Purpose:** Top‑level GA controller (FSM).

**Parameters:**

- `CHROMOSOME_WIDTH` = 8 bits
- `POPULATION_SIZE` = 16 (needs 4‑bit address because `$clog2(16)=4`)
- `MAX_GENERATIONS` = 100
- `FITNESS_WIDTH` = 10 bits
- `MUTATION_RATE` = 8’h10 (16/256 ≈ 6.25%)

**Key Components Instantiated:**

- `lfsr_random` → generates random bits (for mutation and crossover point)
- `population_memory` → 8-bit × 16 entry storage
- `selection` → roulette wheel selection
- `crossover`, `mutation`, `fitness_evaluator` → the main GA operators

**FSM States (12 total)** in proper GA order:

`IDLE → INIT_POPULATION → EVALUATE_FITNESS → CALC_TOTAL_FITNESS → SELECT_PARENT1 → SELECT_PARENT2 → CROSSOVER → MUTATION → EVALUATE_CHILD → REPLACE_WORST → CHECK_TERMINATION → DONE`

**Data widths:**

- Chromosomes: 8 bits
- Fitness: 10 bits each, plus total_fitness (could be up to 16×8 = 128 → needs 8 bits, but has 10 bits, fine)
- LFSR output: 8 bits

**Potential Issues:**

- [ ] `total_fitness` accumulation in `CALC_TOTAL_FITNESS` doesn’t clear per generation before summing unless state machine ensures it at start → risk of carry‑over.
- [ ] `worst_fitness` reset works, but tracking best/worst might break if fitness values tie and replacement logic only triggers `>` not `>=`.
- [ ] Crossover module currently fixed‑point.
- [ ] No random seed control for LFSR → repeatability limited.

## Main Observed Weaknesses & Suggestions

1. **Unused `crossover_point`** in `crossover.sv` — fix to allow true variable splitting.
2. **`mutation_mask` indexing** — ensure it provides enough random range per gene before comparing to mutation_rate.
3. **Seed control** in LFSRs — add a seed input or vary initial value for reproducibility.
4. **`total_fitness` reset** — guarantee clear before accumulating each generation.
5. **Selection scaling edge cases** — handle `total_fitness == 0`.
6. Possible **performance bottleneck** — fitness evaluation done serially, could be optimized in parallel for small populations.

-----------------------------------

# Standard test becnch style

```v
`timescale 1ns / 1ps
// -----------------------------------------------------------
// 1. Interface — bundles DUT I/O signals
// -----------------------------------------------------------
interface dut_if(input logic clk, rst);
    // DUT inputs
    logic [7:0] a;
    logic [7:0] b;
    logic       carry_in;
    logic [1:0] op_sel;

    // DUT outputs
    logic [7:0] result;
    logic       carry_out;
endinterface

// -----------------------------------------------------------
// 2. Testbench module
// -----------------------------------------------------------
module tb_top;

    // Clock generation (100 MHz with timescale 1ns/1ps)
    logic clk = 0;
    always #5 clk = ~clk;

    // Reset generation
    logic rst;
    initial begin
        rst = 1;
        #20 rst = 0;
    end

    // Interface instance
    dut_if intf(clk, rst);

    // Expected values (based on reference / golden model)
    logic [7:0] expected_result;
    logic       expected_carry;

    int error_count = 0;
    int test_count  = 0;

    // -------------------------------------------------------
    // 3. DUT instantiation
    // -------------------------------------------------------
    // Replace 'my_dut' and port connections as per your DUT
    my_dut DUT (
        .a(intf.a),
        .b(intf.b),
        .carry_in(intf.carry_in),
        .op_sel(intf.op_sel),
        .result(intf.result),
        .carry_out(intf.carry_out)
    );

    // -------------------------------------------------------
    // 4. Generator — produces random + edge case stimuli
    // -------------------------------------------------------
    task generator(int num_tests);
        for (int i = 0; i < num_tests; i++) begin
            // Default randomization
            intf.a        = $urandom();
            intf.b        = $urandom();
            intf.carry_in = $urandom_range(0, 1);
            intf.op_sel   = $urandom_range(0, 3);

            // Inject example edge cases at fixed intervals
            if (i % 100 == 0) begin
                intf.a = 8'h00;
                intf.b = 8'hFF;
            end

            // Compute expected values based on your DUT function
            // (Replace this block with your golden model logic)
            case (intf.op_sel)
                2'b00: {expected_carry, expected_result} = intf.a + intf.b;
                2'b01: {expected_carry, expected_result} = {1'b0, intf.a} - {1'b0, intf.b};
                2'b10: begin expected_result = intf.a & intf.b; expected_carry = 0; end
                2'b11: begin expected_result = intf.a | intf.b; expected_carry = 0; end
            endcase

            // Send to DUT via driver
            driver();
        end
    endtask

    // -------------------------------------------------------
    // 5. Driver — applies data to DUT synchronised to clock
    // -------------------------------------------------------
    task driver();
        @(posedge clk);
        #1; // allow small time for signals to settle
        monitor();
        test_count++;
    endtask

    // -------------------------------------------------------
    // 6. Monitor — captures DUT outputs and calls checker
    // -------------------------------------------------------
    task monitor();
        check_result();
    endtask

    // -------------------------------------------------------
    // 7. Checker — compares DUT output with expected values
    // -------------------------------------------------------
    task check_result();
        if (intf.result !== expected_result) begin
            $display("ERROR @ %0t: op_sel=%b, a=%h, b=%h | expected result=%h, got=%h",
                     $time, intf.op_sel, intf.a, intf.b,
                     expected_result, intf.result);
            error_count++;
        end
        if (intf.carry_out !== expected_carry) begin
            $display("ERROR @ %0t: op_sel=%b, a=%h, b=%h | expected carry=%b, got=%b",
                     $time, intf.op_sel, intf.a, intf.b,
                     expected_carry, intf.carry_out);
            error_count++;
        end
    endtask

    // -------------------------------------------------------
    // 8. Main sequence — controls simulation flow
    // -------------------------------------------------------
    initial begin
        wait(!rst); // Wait until reset is released
        $display("Starting tests...");
        generator(1000); // Number of tests
        $display("Tests completed: %0d total, %0d errors", test_count, error_count);

        if (error_count == 0)
            $display("TEST PASSED");
        else
            $display("TEST FAILED");

        $finish;
    end

    // Optional waveform dump
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
```

![TB.png](D:\university\studies\FPGA\PJ_FPGA\GA_Genetic_algorithm\PNG\TB.png)

-----

# fixing the parts

![diagram.png](D:\university\studies\FPGA\PJ_FPGA\GA_Genetic_algorithm\PNG\diagram.png)

## crossover

### v1

![v1.png](D:\university\studies\FPGA\PJ_FPGA\GA_Genetic_algorithm\PNG\crossover\v1.png)

- **error:** crossover_Single_point is not a constant

- **solution:** use mask

### Issues to fix:

- [ ] The **crossover_point** input is unused → crossover is manual (fix it by making the user choose the crossover point as mentioned) so it should be dynamic
  
  ```v
  child <= {parent1[CHROMOSOME_WIDTH-1:crossover_point], parent2[crossover_point-1:0]};
  ```

- [ ] inccreas the cross over methodes (single‑point, two‑point, uniform crossover)

- [ ] if `crossover_point = CHROMOSOME_WIDTH` or `crossover_point = 0` then we have error

- [ ] cross over can be improve by making it undependet from CHROMOSOME_WIDTH `input logic [$clog2(CHROMOSOME_WIDTH):0] crossover_point`

- [ ] Add fixed 
  
  - [ ] single
  
  - [ ] double

- [ ] Add float
  
  - [ ] fix LSFR before it for random float point
  
  - [ ] single
  
  - [ ] double

- [ ] add uniform crossover
  
  - [ ] mask using input 
  
  - [ ] mask using random input (using LSFR)

## LSFR

### v1

![](C:\Users\Alireza\AppData\Roaming\marktext\images\2025-08-20-22-55-08-image.png)

:warning:the defualt value is `A835` and not `0` its good or bad? (43061 unsined decimal)

this happend becuse of 

```v
    // Combine all LFSRs via XOR 
    logic [WIDTH1-1:0] combined;
    assign combined = lfsr1 ^ {{(WIDTH1-WIDTH2){1'b0}}, lfsr2} ^ {{(WIDTH1-WIDTH3){1'b0}}, lfsr3} ^ {{(WIDTH1-WIDTH4){1'b0}}, lfsr4};

    // Whitening: XOR with shifted versions
    assign random_out = combined  ^ (combined >> 7) ^ (combined << 3);
```

as you see no 0 output and rst is active low

```v
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
```

### Issues to fix:

- [x] Taps are not parameterized or visible in code snippet → need correct polynomial per WIDTH for maximal length. (making it independent from WIDTH)

- [x] choose th right primitive polynomial
  
  `x^16 + x^14 + x^13 + x^11` 65535 states before repetition

- [x] No seed input → always starts at ‘1’ : `load_seed`

- [x] how can i make it more randomized ?
  
  - [x] 4 LSFR and XOR the output : 2.88*10^17 states before iteration
  
  - [x] Whitening

- [x] rst_n sould be rst and turn to active high because its confiusing for me!!

- [x] output should be 0 when its rst !

- [x] Test bench (**f<u>inal step</u>**)
