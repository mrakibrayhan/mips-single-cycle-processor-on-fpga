//====================================================================
// cpu_core_mips_sc.v  (MIPS-compatible single-cycle CPU, step 6)  -  H&H 'top' = mips (controller + datapath) + imem + dmem
//   Added around the H&H processor (no change to the datapath / control):
//     halted : set after syscall / break (step 10; PC + 4) or after a taken branch / jump to its own address ("j ." = stop);
//              the stop instruction completes, then the PC and all writes freeze.
//     fault  : set by an illegal instruction (not in the enabled subset): no writes, PC + 4, then freeze.
//     retire : 1 in every cycle that executes an instruction (CPI = 1); trace outputs for the testbench.
//     step 14 board view (DBG_EN = 1): 'freeze' stops the CPU after the current instruction (no PC update, no writes);
//              while stopped (freeze / halted / fault: view_rdy = 1) dbg_idx 0..31 reads register $idx through read
//              port 1 and dbg_idx 32..63 reads RAM word idx-32 through the RAM read port (both asynchronous, so dbg_val
//              belongs to dbg_idx of the same cycle). With DBG_EN = 0 the view muxes are removed.
//====================================================================
module cpu_core_mips_sc #(
    parameter [7:0] FEATURES  = 8'hFF,
    parameter       IMEM_AW   = 7,
    parameter       DMEM_AW   = 5,
    parameter       INIT_FILE = "program.hex",
    parameter       DATA_FILE = "data.hex",
    parameter       DBG_EN    = 0,
    parameter       MEM_M9K   = 0       // Step G3 ablation: 1 = ROM/RAM in M9K (ROM on the rising edge addressed by the PC's next value, RAM on the falling edge; CPI stays 1). 0 = textbook asynchronous memories (default, all paper / board builds)
) (
    input         clk, rst,
    output reg    halted, fault,
    output        retire,
    output [31:0] pc, instr,
    // trace (simulation / debug)
    output        tr_regw,
    output [4:0]  tr_wa,
    output [31:0] tr_wd,
    output [3:0]  tr_be,
    output [31:0] tr_adr, tr_mdata,
    output        tr_hiw, tr_low,
    output [31:0] tr_hi, tr_lo,
    // board view
    input         freeze,
    output        view_rdy,
    input  [5:0]  dbg_idx,
    output [31:0] dbg_val
);
    wire        memwrite, pcsrc, alusrc, regwrite, jump, jumpreg, zero, neg, stop, illegal;
    wire [2:0]  resultsrc;
    wire [1:0]  regdst, memsize;
    wire        loaduns;
    wire [31:0] memwdata;
    wire [3:0]  membe;
    wire [31:0] hiwd, lowd;
    wire [3:0]  alucontrol;
    wire [1:0]  extop;
    wire        shvar, mulwrite, mulsigned, hiwrite, lowrite;
    wire [31:0] aluout, writedata, readdata, pcnext, result;
    wire [4:0]  writereg;

    wire stopped = halted | fault | (DBG_EN != 0 && freeze);
    wire run     = ~stopped;
    wire dbg_en  = (DBG_EN != 0) && stopped;
    wire [31:0] dbg_rd1;
    wire wr_ok = run & ~illegal;

    controller_mips_sc #(.FEATURES(FEATURES)) c (
        .op(instr[31:26]), .funct(instr[5:0]), .rt(instr[20:16]), .zero(zero), .neg(neg), .resultsrc(resultsrc),
        .memwrite(memwrite), .memsize(memsize), .loaduns(loaduns), .pcsrc(pcsrc), .alusrc(alusrc), .regdst(regdst), .regwrite(regwrite), .jump(jump), .jumpreg(jumpreg), .stop(stop), .extop(extop), .alucontrol(alucontrol), .shvar(shvar),
        .mulwrite(mulwrite), .mulsigned(mulsigned), .hiwrite(hiwrite), .lowrite(lowrite), .illegal(illegal));

    datapath_mips_sc #(.HAS_MUL(FEATURES[7])) dp (
        .clk(clk), .rst(rst), .pcen(run), .resultsrc(resultsrc), .memsize(memsize), .loaduns(loaduns), .pcsrc(pcsrc), .alusrc(alusrc), .regdst(regdst), .jumpreg(jumpreg),
        .regwrite(regwrite & wr_ok), .jump(jump), .extop(extop), .alucontrol(alucontrol), .shvar(shvar),
        .mulwrite(mulwrite & wr_ok), .mulsigned(mulsigned), .hiwrite(hiwrite & wr_ok), .lowrite(lowrite & wr_ok), .zero(zero), .neg(neg), .pc(pc), .pcnext(pcnext),
        .instr(instr), .aluout(aluout), .writedata(writedata), .memwdata(memwdata), .membe(membe), .readdata(readdata), .writereg(writereg), .result(result), .hiwd(hiwd), .lowd(lowd),
        .dbg_en(dbg_en), .dbg_ra(dbg_idx[4:0]), .dbg_rd1(dbg_rd1));

    // PC register's next value (same as datapath_mips_sc: rst -> 0, pcen = run -> pcnext): address of the M9K ROM (MEM_M9K = 1)
    wire [31:0] pc_d = rst ? 32'd0 : (run ? pcnext : pc);
    generate if (MEM_M9K) begin : g_m9k_rom
        imem_m9k_mips_sc #(.IMEM_AW(IMEM_AW), .INIT_FILE(INIT_FILE)) imem (.clk(clk), .a_next(pc_d), .rd(instr));
    end else begin : g_rom
        imem_mips_sc #(.IMEM_AW(IMEM_AW), .INIT_FILE(INIT_FILE)) imem (.a(pc), .rd(instr));
    end endgenerate

    wire [3:0]  be     = (memwrite & wr_ok) ? membe : 4'b0000;
    wire [31:0] dmem_a = dbg_en ? {25'd0, dbg_idx[4:0], 2'b00} : aluout;
    generate if (MEM_M9K) begin : g_m9k_ram
        dmem_m9k_mips_sc #(.DMEM_AW(DMEM_AW), .DATA_FILE(DATA_FILE)) dmem (.clk(clk), .be(be), .a(dmem_a), .wd(memwdata), .rd(readdata));
    end else begin : g_ram
        dmem_mips_sc #(.DMEM_AW(DMEM_AW), .DATA_FILE(DATA_FILE)) dmem (.clk(clk), .be(be), .a(dmem_a), .wd(memwdata), .rd(readdata));
    end endgenerate

    // stop logic
    wire selfloop = (jump | jumpreg | pcsrc) & (pcnext == pc);
    always @(posedge clk) begin
        if (rst) begin
            halted <= 1'b0;
            fault  <= 1'b0;
        end else if (run) begin
            if (illegal)       fault  <= 1'b1;
            else if (stop | selfloop) halted <= 1'b1;
        end
    end
    assign retire   = run;
    assign view_rdy = stopped;
    assign dbg_val  = dbg_idx[5] ? readdata : dbg_rd1;

    assign tr_regw  = regwrite & wr_ok & (writereg != 5'd0);
    assign tr_wa    = writereg;
    assign tr_wd    = result;
    assign tr_be    = be;
    assign tr_adr   = aluout;
    assign tr_mdata = memwdata;
    assign tr_hiw   = (mulwrite | hiwrite) & wr_ok;
    assign tr_low   = (mulwrite | lowrite) & wr_ok;
    assign tr_hi    = hiwd;
    assign tr_lo    = lowd;
endmodule
