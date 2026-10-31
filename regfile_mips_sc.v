//====================================================================
// regfile_mips_sc.v  (MIPS-compatible single-cycle CPU, step 4)  -  32 x 32 register file
//   Harris & Harris 2nd ed. section 7.6 "regfile": three-ported, two combinational (asynchronous) read ports,
//   one write port written on the rising clock edge; register 0 is hard-wired to 0.
//   Added: synchronous reset clears $1..$31 (the Cyclone IV flip-flop synchronous-clear input, no extra LEs),
//   so every board run starts from the same state. 31 x 32 flip-flops + two 32:1 read multiplexers.
//====================================================================
module regfile_mips_sc (
    input         clk,
    input         rst,
    input         we3,
    input  [4:0]  ra1, ra2, wa3,
    input  [31:0] wd3,
    output [31:0] rd1, rd2
);
    reg [31:0] rf [1:31];
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 1; i < 32; i = i + 1) rf[i] <= 32'd0;
        end else if (we3 && wa3 != 5'd0) begin
            rf[wa3] <= wd3;
        end
    end
    assign rd1 = (ra1 != 5'd0) ? rf[ra1] : 32'd0;
    assign rd2 = (ra2 != 5'd0) ? rf[ra2] : 32'd0;
endmodule
