//====================================================================
// alu_mips.v  (MIPS-compatible single-cycle CPU)  -  Harris & Harris 2nd ed. ALU, extended
//   step 5: H&H codes  010 add  110 sub  000 and  001 or  111 slt   (kept as 0xxx: bit 3 = 0)
//   step 8: 1000 xor   1001 nor   1111 sltu   1010 pass B (lui: B = imm << 16)
//   step 9: 1100 sll   1101 srl   1110 sra   (shifter_mips: operand b, amount shamt)
//   slt uses the overflow-corrected sign (true signed compare); sltu = borrow of a - b.
//====================================================================
module alu_mips (
    input      [31:0] a, b,
    input      [3:0]  alucontrol,
    input      [4:0]  shamt,
    output reg [31:0] result,
    output            zero
);
    wire [31:0] condinvb = alucontrol[2] ? ~b : b;
    wire [32:0] sum33    = {1'b0, a} + {1'b0, condinvb} + {32'd0, alucontrol[2]};
    wire [31:0] sum      = sum33[31:0];
    wire        lt       = (a[31] != b[31]) ? a[31] : sum[31];      // signed a < b
    wire        ltu      = ~sum33[32];                              // unsigned a < b (no carry out of a + ~b + 1)
    wire [31:0] shifted;
    shifter_mips shf (.b(b), .shamt(shamt), .sh(alucontrol[1:0]), .y(shifted));
    always @(*) begin
        case (alucontrol)
            4'b0000: result = a & b;
            4'b0001: result = a | b;
            4'b0111: result = {31'd0, lt};
            4'b1111: result = {31'd0, ltu};
            4'b1000: result = a ^ b;
            4'b1001: result = ~(a | b);
            4'b1010: result = b;
            4'b1100, 4'b1101, 4'b1110: result = shifted;
            default: result = sum;                                  // 0010 add, 0110 sub
        endcase
    end
    assign zero = (result == 32'd0);
endmodule
