//====================================================================
// controller_mips_sc.v  (MIPS-compatible single-cycle CPU)  -  Harris & Harris 2nd ed. section 7.3.2 / 7.6, extended
//   controller = maindec + aludec + branch-condition logic; PCSrc = Branch & BranchCond.
//   step 6 : H&H rows R-type, lw, sw, beq, addi, j (Tables 7.2, 7.5)
//   step 8 : ALUX: addiu slti sltiu andi ori xori lui (ExtOp, ALUOp = 11 -> by opcode); addu subu xor nor sltu; 4-bit ALUControl
//   step 9 : SHIFT: sll srl sra (amount = shamt), sllv srlv srav (ShVar = 1: amount = rs[4:0])
//   step 10: BR: bne blez bgtz bltz bgez (BrType; Zero of rs - rt, N = SrcA[31]);  JUMP: jal (RegDst = 31, link),
//            jr / jalr (JumpReg: PC = rs; jalr links into rd);  SYS: syscall / break (Stop).
//   step 11: MEMX: lb lbu lh lhu sb sh (MemSize 00 word / 01 half / 10 byte, LoadUns = zero-extend the loaded byte / half)
//   step 12: MUL: mult multu (MulWrite: {HI,LO} = rs x rt, MulSigned), mthi / mtlo (HiWrite / LoWrite = rs),
//            mfhi / mflo (ResultSrc 011 HI / 100 LO).
//   Step E (2026-10-24): MUL (MIPS32 SPECIAL2, funct 000010): rd = (rs x rt)[31:0], ResultSrc 101, MUL group; HI/LO unchanged.
//            H&H MemtoReg becomes ResultSrc (000 ALU, 001 memory, 010 PC + 8 link); RegDst becomes 2 bits (00 rt, 01 rd, 10 $31).
//   FEATURES: an instruction whose group bit is 0 is illegal. For an illegal instruction every control output takes
//   its default value (no write, ALU add, PC + 4), so the hardware of a disabled group is removed by synthesis.
//   Group bits: 0 BASE  1 ALUX  2 SHIFT  3 BR  4 JUMP  5 SYS  6 MEMX  7 MUL
//====================================================================
module controller_mips_sc #(
    parameter [7:0] FEATURES = 8'hFF
) (
    input  [5:0] op, funct,
    input  [4:0] rt,
    input        zero, neg,                // ALU Zero (rs - rt), sign of SrcA (rs)
    output [2:0] resultsrc,
    output       memwrite,
    output [1:0] memsize,
    output       loaduns,
    output       pcsrc, alusrc,
    output [1:0] regdst,
    output       regwrite,
    output       jump, jumpreg,
    output [1:0] extop,
    output [3:0] alucontrol,
    output       shvar,
    output       mulwrite, mulsigned, hiwrite, lowrite,
    output       stop,
    output       illegal
);
    wire [1:0] aluop, extop_r, regdst_r, memsize_r;
    wire [2:0] brtype, resultsrc_r;
    wire [3:0] aluc_r;
    wire [7:0] mgrp, fgrp;
    wire       md_ill, ad_ill, shvar_r, f_nowrite, f_jumpreg, f_stop, f_mulw, f_muls, f_hiw, f_low;
    wire [2:0] f_res;
    wire       memwrite_r, branch_r, alusrc_r, regwrite_r, jump_r, loaduns_r;
    maindec_mips md (.op(op), .rt(rt), .resultsrc(resultsrc_r), .memwrite(memwrite_r), .branch(branch_r),
                     .alusrc(alusrc_r), .regdst(regdst_r), .regwrite(regwrite_r), .jump(jump_r), .aluop(aluop),
                     .extop(extop_r), .brtype(brtype), .memsize(memsize_r), .loaduns(loaduns_r), .grp(mgrp), .illegal(md_ill));
    aludec_mips  ad (.op(op), .funct(funct), .aluop(aluop), .alucontrol(aluc_r), .shvar(shvar_r), .nowrite(f_nowrite),
                     .jumpreg(f_jumpreg), .res(f_res), .stop(f_stop), .mulwrite(f_mulw), .mulsigned(f_muls),
                     .hiwrite(f_hiw), .lowrite(f_low), .grp(fgrp), .illegal(ad_ill));

    assign illegal = md_ill | ad_ill | ~|((mgrp | fgrp) & FEATURES);
    wire   ok      = ~illegal;
    assign resultsrc  = ok ? ((f_res != 3'b000) ? f_res : resultsrc_r) : 3'b000;
    assign memwrite   = memwrite_r & ok;
    assign memsize    = ok ? memsize_r : 2'b00;
    assign loaduns    = loaduns_r & ok;
    assign alusrc     = alusrc_r   & ok;
    assign regdst     = ok ? regdst_r : 2'b00;
    assign regwrite   = regwrite_r & ~f_nowrite & ok;
    assign jump       = jump_r     & ok;
    assign jumpreg    = f_jumpreg  & ok;
    assign stop       = f_stop     & ok;
    assign extop      = ok ? extop_r : 2'b00;
    assign alucontrol = ok ? aluc_r  : 4'b0010;
    assign shvar      = shvar_r & ok;
    assign mulwrite   = f_mulw & ok;
    assign mulsigned  = f_muls & ok;
    assign hiwrite    = f_hiw & ok;
    assign lowrite    = f_low & ok;

    // branch condition (beq / bne use Zero of rs - rt; blez / bgtz have rt = 0 in the encoding)
    reg cond;
    always @(*) begin
        case (brtype)
            3'b000:  cond = zero;              // beq
            3'b001:  cond = ~zero;             // bne
            3'b010:  cond = neg | zero;        // blez
            3'b011:  cond = ~neg & ~zero;      // bgtz
            3'b100:  cond = neg;               // bltz
            default: cond = ~neg;              // bgez
        endcase
    end
    assign pcsrc = branch_r & ok & cond;
endmodule

//--------------------------------------------------------------------
// main decoder (H&H Table 7.5, extended)
//   controls = {regwrite, regdst[1:0], alusrc, branch, memwrite, resultsrc[2:0], jump, aluop[1:0], extop[1:0], brtype[2:0],
//               memsize[1:0], loaduns}
//   aluop: 00 add  01 sub  10 funct  11 opcode (immediate ALU ops)      extop: 00 sign  01 zero  10 upper (lui)
//--------------------------------------------------------------------
module maindec_mips (
    input  [5:0] op,
    input  [4:0] rt,
    output [2:0] resultsrc,
    output       memwrite,
    output       branch, alusrc,
    output [1:0] regdst,
    output       regwrite,
    output       jump,
    output [1:0] aluop,
    output [1:0] extop,
    output [2:0] brtype,
    output [1:0] memsize,
    output       loaduns,
    output reg [7:0] grp,
    output reg   illegal
);
    reg [19:0] c;
    assign {regwrite, regdst, alusrc, branch, memwrite, resultsrc, jump, aluop, extop, brtype, memsize, loaduns} = c;
    always @(*) begin
        illegal = 1'b0;
        grp     = 8'h01;
        //                         rw rd  as br mw res  j  aop ext bt  ms lu
        case (op)
            6'b000000: begin c = 20'b1_01_0_0_0_000_0_10_00_000_00_0; grp = 8'h00; end   // R-type (group from the ALU decoder)
            6'b100011:       c = 20'b1_00_1_0_0_001_0_00_00_000_00_0;                    // lw
            6'b101011:       c = 20'b0_00_1_0_1_000_0_00_00_000_00_0;                    // sw
            6'b000100:       c = 20'b0_00_0_1_0_000_0_01_00_000_00_0;                    // beq
            6'b001000:       c = 20'b1_00_1_0_0_000_0_00_00_000_00_0;                    // addi
            6'b000010:       c = 20'b0_00_0_0_0_000_1_00_00_000_00_0;                    // j
            6'b001001: begin c = 20'b1_00_1_0_0_000_0_00_00_000_00_0; grp = 8'h02; end   // addiu
            6'b001010: begin c = 20'b1_00_1_0_0_000_0_11_00_000_00_0; grp = 8'h02; end   // slti
            6'b001011: begin c = 20'b1_00_1_0_0_000_0_11_00_000_00_0; grp = 8'h02; end   // sltiu (sign-extended, unsigned compare)
            6'b001100: begin c = 20'b1_00_1_0_0_000_0_11_01_000_00_0; grp = 8'h02; end   // andi
            6'b001101: begin c = 20'b1_00_1_0_0_000_0_11_01_000_00_0; grp = 8'h02; end   // ori
            6'b001110: begin c = 20'b1_00_1_0_0_000_0_11_01_000_00_0; grp = 8'h02; end   // xori
            6'b001111: begin c = 20'b1_00_1_0_0_000_0_11_10_000_00_0; grp = 8'h02; end   // lui
            6'b000101: begin c = 20'b0_00_0_1_0_000_0_01_00_001_00_0; grp = 8'h08; end   // bne
            6'b000110: begin c = 20'b0_00_0_1_0_000_0_01_00_010_00_0; grp = 8'h08; end   // blez
            6'b000111: begin c = 20'b0_00_0_1_0_000_0_01_00_011_00_0; grp = 8'h08; end   // bgtz
            6'b000001: begin                                                         // REGIMM
                grp = 8'h08;
                if (rt == 5'b00000)      c = 20'b0_00_0_1_0_000_0_01_00_100_00_0;        // bltz
                else if (rt == 5'b00001) c = 20'b0_00_0_1_0_000_0_01_00_101_00_0;        // bgez
                else begin c = 20'd0; grp = 8'h00; illegal = 1'b1; end
            end
            6'b000011: begin c = 20'b1_10_0_0_0_010_1_00_00_000_00_0; grp = 8'h10; end   // jal ($31 = PC + 8)
            6'b011100: begin c = 20'b1_01_0_0_0_000_0_10_00_000_00_0; grp = 8'h00; end   // SPECIAL2 (MUL; group from the ALU decoder)
            6'b100000: begin c = 20'b1_00_1_0_0_001_0_00_00_000_10_0; grp = 8'h40; end   // lb
            6'b100100: begin c = 20'b1_00_1_0_0_001_0_00_00_000_10_1; grp = 8'h40; end   // lbu
            6'b100001: begin c = 20'b1_00_1_0_0_001_0_00_00_000_01_0; grp = 8'h40; end   // lh
            6'b100101: begin c = 20'b1_00_1_0_0_001_0_00_00_000_01_1; grp = 8'h40; end   // lhu
            6'b101000: begin c = 20'b0_00_1_0_1_000_0_00_00_000_10_0; grp = 8'h40; end   // sb
            6'b101001: begin c = 20'b0_00_1_0_1_000_0_00_00_000_01_0; grp = 8'h40; end   // sh
            default:   begin c = 20'd0; grp = 8'h00; illegal = 1'b1; end
        endcase
    end
endmodule

//--------------------------------------------------------------------
// ALU decoder (H&H Table 7.2, extended) + R-type special controls
//--------------------------------------------------------------------
module aludec_mips (
    input      [5:0] op, funct,
    input      [1:0] aluop,
    output reg [3:0] alucontrol,
    output reg       shvar,
    output reg       nowrite,     // R-type without a register write (jr, syscall, break)
    output reg       jumpreg,     // PC = rs (jr, jalr)
    output reg [2:0] res,         // ResultSrc override: 010 PC + 8 (jalr), 011 HI (mfhi), 100 LO (mflo), 000 none
    output reg       stop,        // syscall, break
    output reg       mulwrite,    // mult / multu
    output reg       mulsigned,
    output reg       hiwrite,     // mthi
    output reg       lowrite,     // mtlo
    output reg [7:0] grp,
    output reg       illegal
);
    always @(*) begin
        illegal = 1'b0; grp = 8'h00; shvar = 1'b0; nowrite = 1'b0; jumpreg = 1'b0; res = 3'b000; stop = 1'b0;
        mulwrite = 1'b0; mulsigned = 1'b0; hiwrite = 1'b0; lowrite = 1'b0;
        case (aluop)
            2'b00: alucontrol = 4'b0010;                 // add (lw / sw / addi / addiu)
            2'b01: alucontrol = 4'b0110;                 // sub (branches)
            2'b11: case (op)                             // immediate ALU ops
                6'b001010: alucontrol = 4'b0111;         // slti
                6'b001011: alucontrol = 4'b1111;         // sltiu
                6'b001100: alucontrol = 4'b0000;         // andi
                6'b001101: alucontrol = 4'b0001;         // ori
                6'b001110: alucontrol = 4'b1000;         // xori
                default:   alucontrol = 4'b1010;         // lui (pass B)
            endcase
            default: if (op == 6'b011100) begin         // SPECIAL2: only MUL rd = (rs x rt)[31:0] (MIPS32, Step E G6)
                alucontrol = 4'b0010;
                if (funct == 6'b000010) begin grp = 8'h80; res = 3'b101; mulsigned = 1'b1; end
                else begin grp = 8'h00; illegal = 1'b1; end
            end else begin                               // R-type
                grp = 8'h02;
                alucontrol = 4'b0010;
                case (funct)
                    6'b100000: begin alucontrol = 4'b0010; grp = 8'h01; end   // add
                    6'b100010: begin alucontrol = 4'b0110; grp = 8'h01; end   // sub
                    6'b100100: begin alucontrol = 4'b0000; grp = 8'h01; end   // and
                    6'b100101: begin alucontrol = 4'b0001; grp = 8'h01; end   // or
                    6'b101010: begin alucontrol = 4'b0111; grp = 8'h01; end   // slt
                    6'b100001: alucontrol = 4'b0010;                          // addu
                    6'b100011: alucontrol = 4'b0110;                          // subu
                    6'b100110: alucontrol = 4'b1000;                          // xor
                    6'b100111: alucontrol = 4'b1001;                          // nor
                    6'b101011: alucontrol = 4'b1111;                          // sltu
                    6'b000000: begin alucontrol = 4'b1100; grp = 8'h04; end   // sll
                    6'b000010: begin alucontrol = 4'b1101; grp = 8'h04; end   // srl
                    6'b000011: begin alucontrol = 4'b1110; grp = 8'h04; end   // sra
                    6'b000100: begin alucontrol = 4'b1100; grp = 8'h04; shvar = 1'b1; end   // sllv
                    6'b000110: begin alucontrol = 4'b1101; grp = 8'h04; shvar = 1'b1; end   // srlv
                    6'b000111: begin alucontrol = 4'b1110; grp = 8'h04; shvar = 1'b1; end   // srav
                    6'b001000: begin grp = 8'h10; jumpreg = 1'b1; nowrite = 1'b1; end      // jr
                    6'b001001: begin grp = 8'h10; jumpreg = 1'b1; res = 3'b010; end        // jalr (rd = PC + 8)
                    6'b001100: begin grp = 8'h20; stop = 1'b1; nowrite = 1'b1; end         // syscall
                    6'b001101: begin grp = 8'h20; stop = 1'b1; nowrite = 1'b1; end         // break
                    6'b011000: begin grp = 8'h80; mulwrite = 1'b1; mulsigned = 1'b1; nowrite = 1'b1; end   // mult
                    6'b011001: begin grp = 8'h80; mulwrite = 1'b1; nowrite = 1'b1; end    // multu
                    6'b010000: begin grp = 8'h80; res = 3'b011; end                       // mfhi
                    6'b010010: begin grp = 8'h80; res = 3'b100; end                       // mflo
                    6'b010001: begin grp = 8'h80; hiwrite = 1'b1; nowrite = 1'b1; end     // mthi
                    6'b010011: begin grp = 8'h80; lowrite = 1'b1; nowrite = 1'b1; end     // mtlo
                    default:   begin grp = 8'h00; illegal = 1'b1; end
                endcase
            end
        endcase
    end
endmodule
