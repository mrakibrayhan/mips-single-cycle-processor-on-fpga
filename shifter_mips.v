//====================================================================
// shifter_mips.v  (MIPS-compatible single-cycle CPU, step 9)  -  barrel shifter used inside the ALU block
//   sh = 00 sll, 01 srl, 10 sra (logical left / logical right / arithmetic right), amount 0..31.
//   Operand = SrcB (= rt), amount = shamt field (sll/srl/sra) or rs[4:0] (sllv/srlv/srav), chosen in the datapath.
//====================================================================
module shifter_mips (
    input  [31:0] b,
    input  [4:0]  shamt,
    input  [1:0]  sh,
    output [31:0] y
);
    wire signed [31:0] bs  = b;
    wire        [31:0] sra = bs >>> shamt;      // separate signed expression (inside ?: it would become unsigned)
    assign y = (sh == 2'b00) ? (b << shamt) :
               (sh == 2'b01) ? (b >> shamt) : sra;
endmodule
