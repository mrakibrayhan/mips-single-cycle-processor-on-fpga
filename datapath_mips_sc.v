//====================================================================
// datapath_mips_sc.v  (MIPS-compatible single-cycle CPU, step 5)  -  Harris & Harris 2nd ed. section 7.3 / 7.6
//   The H&H single-cycle datapath with the addi and j extensions (Figure "complete single-cycle MIPS processor"):
//     PC register, PCPlus4 adder, sign extend, shift-left-2, PCBranch adder, PCSrc mux, jump mux,
//     register file (A1 = rs, A2 = rt, A3 = RegDst ? rd : rt), ALUSrc mux, ALU, MemtoReg mux.
//   Added for the board: pcen (the PC holds after a halt / fault).
//   step 14: board view port: while the CPU is stopped (dbg_en = 1) register-file read port 1 reads register dbg_ra
//            (the snapshot unit sweeps $0..$31 through it, so no third read port is needed).
//   step 12: HI / LO registers (hilo) + mul_mips: mult/multu write {HI,LO}, mthi/mtlo write rs, mfhi/mflo read
//            through ResultSrc 011 / 100.
//   step 11: load aligner (lb/lbu/lh/lhu: byte / half selected by ALUResult[1:0], sign / zero extended) and store
//            lanes (sb / sh data replicated into every lane, byte enables from MemSize and ALUResult[1:0], little-endian).
//   step 10: PCNext = JumpReg ? SrcA : Jump ? PCJump : PCSrc ? PCBranch : PCPlus4;  PCPlus8 = link value;
//            RegDst 00 rt / 01 rd / 10 $31;  ResultSrc 000 ALU / 001 memory / 010 PC + 8 / 011 HI / 100 LO / 101 product (MUL);  neg = SrcA[31] to the branch logic.
//   step 9: shift amount = ShVar ? SrcA[4:0] (sllv/srlv/srav) : instr[10:6] (shamt) -> ALU shifter.
//   step 8: Extend unit (ExtOp 00 sign / 01 zero / 10 upper = imm << 16) feeds the ALUSrc mux; ALUControl 4 bits.
//   Instruction memory and data memory are outside (cpu_core_mips_sc.v), as the H&H 'imem' / 'dmem'.
//====================================================================
module datapath_mips_sc #(
    parameter HAS_MUL = 1               // 0 = no multiplier and no HI/LO hardware (BASE build, Step E gap G19)
) (
    input         clk, rst,
    input         pcen,                 // 0 = PC holds (halted / fault)
    input  [2:0]  resultsrc,
    input  [1:0]  memsize,
    input         loaduns,
    input  [1:0]  regdst,
    input         pcsrc, alusrc, regwrite, jump, jumpreg,
    input  [1:0]  extop,
    input  [3:0]  alucontrol,
    input         shvar,
    input         mulwrite, mulsigned, hiwrite, lowrite,
    output        zero, neg,
    output [31:0] pc,
    output [31:0] pcnext,
    input  [31:0] instr,
    output [31:0] aluout, writedata,
    output [31:0] memwdata,             // store data placed in the byte lanes
    output [3:0]  membe,                // byte enables of a store (the core gates them with MemWrite)
    input  [31:0] readdata,
    output [4:0]  writereg,
    output [31:0] result,
    output [31:0] hiwd, lowd,            // values written into HI / LO (trace)
    input         dbg_en,                // board view: read port 1 address = dbg_ra
    input  [4:0]  dbg_ra,
    output [31:0] dbg_rd1
);
    // next PC logic
    reg  [31:0] pcreg;
    wire [31:0] pcplus4  = pcreg + 32'd4;
    wire [31:0] signimm  = {{16{instr[15]}}, instr[15:0]};
    wire [31:0] signimmsh = {signimm[29:0], 2'b00};
    wire [31:0] pcbranch = pcplus4 + signimmsh;
    wire [31:0] pcnextbr = pcsrc ? pcbranch : pcplus4;
    wire [31:0] pcjump   = {pcplus4[31:28], instr[25:0], 2'b00};
    wire [31:0] srca;
    wire [31:0] pcplus8  = pcreg + 32'd8;
    assign pcnext = jumpreg ? srca : jump ? pcjump : pcnextbr;
    always @(posedge clk) begin
        if (rst)       pcreg <= 32'd0;
        else if (pcen) pcreg <= pcnext;
    end
    assign pc = pcreg;

    // register file logic
    assign writereg = (regdst == 2'b10) ? 5'd31 : regdst[0] ? instr[15:11] : instr[20:16];
    regfile_mips_sc rfile (.clk(clk), .rst(rst), .we3(regwrite), .ra1(dbg_en ? dbg_ra : instr[25:21]), .ra2(instr[20:16]), .wa3(writereg),
                        .wd3(result), .rd1(srca), .rd2(writedata));
    // load aligner / store lanes (little-endian)
    wire [1:0]  bo   = aluout[1:0];
    wire [15:0] half = aluout[1] ? readdata[31:16] : readdata[15:0];
    wire [7:0]  byte_ = (bo == 2'd0) ? readdata[7:0] : (bo == 2'd1) ? readdata[15:8] :
                        (bo == 2'd2) ? readdata[23:16] : readdata[31:24];
    wire [31:0] loaddata = (memsize == 2'b01) ? {{16{half[15] & ~loaduns}}, half} :
                           (memsize == 2'b10) ? {{24{byte_[7] & ~loaduns}}, byte_} : readdata;
    assign memwdata = (memsize == 2'b01) ? {2{writedata[15:0]}} :
                      (memsize == 2'b10) ? {4{writedata[7:0]}} : writedata;
    assign membe    = (memsize == 2'b01) ? (aluout[1] ? 4'b1100 : 4'b0011) :
                      (memsize == 2'b10) ? (4'b0001 << bo) : 4'b1111;
    // HI / LO (hilo) and the multiplier
    reg  [31:0] hi, lo;
    wire [63:0] product_raw, product;
    mul_mips mul (.a(srca), .b(writedata), .sgn(mulsigned), .p(product_raw));
    assign product = HAS_MUL ? product_raw : 64'd0;      // HAS_MUL = 0: multiplier removed by synthesis
    always @(posedge clk) begin
        if (rst | ~HAS_MUL) begin                        // HAS_MUL = 0: HI / LO stay 0 and are removed
            hi <= 32'd0; lo <= 32'd0;
        end else begin
            if (mulwrite)     begin hi <= product[63:32]; lo <= product[31:0]; end
            else begin
                if (hiwrite)  hi <= srca;
                if (lowrite)  lo <= srca;
            end
        end
    end

    assign hiwd = mulwrite ? product[63:32] : srca;
    assign lowd = mulwrite ? product[31:0]  : srca;

    assign result = (resultsrc == 3'b001) ? loaddata :
                    (resultsrc == 3'b010) ? pcplus8  :
                    (resultsrc == 3'b011) ? hi       :
                    (resultsrc == 3'b100) ? lo       :
                    (resultsrc == 3'b101) ? product[31:0] : aluout;   // 101: MUL rd = (rs x rt)[31:0] (MIPS32 SPECIAL2, Step E G6)
    assign neg    = srca[31];
    assign dbg_rd1 = srca;

    // ALU logic
    wire [31:0] extimm = (extop == 2'b01) ? {16'd0, instr[15:0]} :
                         (extop == 2'b10) ? {instr[15:0], 16'd0} : signimm;
    wire [31:0] srcb = alusrc ? extimm : writedata;
    wire [4:0]  shamt = shvar ? srca[4:0] : instr[10:6];
    alu_mips alu (.a(srca), .b(srcb), .alucontrol(alucontrol), .shamt(shamt), .result(aluout), .zero(zero));
endmodule
