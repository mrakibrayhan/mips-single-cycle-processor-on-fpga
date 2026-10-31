//====================================================================
// mul_mips.v  (MIPS-compatible single-cycle CPU, step 12)  -  32 x 32 -> 64 multiplier for mult / multu
//   One 33 x 33 signed multiplier serves both: the operands are extended with their sign (mult) or with 0 (multu).
//   Quartus maps it onto the Cyclone IV 9-bit embedded multipliers. Combinational: the product is written into HI/LO
//   at the end of the cycle (HI/LO decouple the multiplier from the register-file write-back path).
//====================================================================
module mul_mips (
    input  [31:0] a, b,
    input         sgn,          // 1 = mult (signed), 0 = multu
    output [63:0] p
);
    wire signed [32:0] a33 = {sgn & a[31], a};
    wire signed [32:0] b33 = {sgn & b[31], b};
    wire signed [65:0] p66 = a33 * b33;
    assign p = p66[63:0];
endmodule
