//====================================================================
// mem_m9k_mips_sc.sv - Step G3 ABLATION ONLY (cpu_core_mips_sc MEM_M9K = 1; the default MEM_M9K = 0 never uses this file).
//   The single-cycle core keeps CPI = 1 with synchronous M9K memories:
//   ROM: clocked on the RISING edge with the PC register's next value (pc_d), so the M9K address register holds
//        exactly what the PC register holds and rd = ROM[PC] during the whole cycle (as the asynchronous ROM).
//   RAM: clocked on the FALLING edge: the data address is ready after half a cycle, the word is read (or written)
//        at mid-cycle and is valid for the second half, before the register write at the next rising edge.
//   Cost: the data-memory path gets half a clock period (this is what the ablation measures).
//====================================================================
module imem_m9k_mips_sc #(
    parameter IMEM_AW   = 7,
    parameter INIT_FILE = "program.hex"
) (
    input             clk,
    input      [31:0] a_next,        // = the PC register's D input
    output reg [31:0] rd
);
    (* ramstyle = "M9K" *) reg [31:0] rom [0:(1 << IMEM_AW) - 1];
    initial $readmemh(INIT_FILE, rom);
    always @(posedge clk) rd <= rom[a_next[IMEM_AW+1:2]];
endmodule

module dmem_m9k_mips_sc #(
    parameter DMEM_AW   = 5,
    parameter DATA_FILE = "data.hex"
) (
    input             clk,
    input      [3:0]  be,
    input      [31:0] a,
    input      [31:0] wd,
    output reg [31:0] rd
);
    (* ramstyle = "M9K" *) logic [3:0][7:0] ram [0:(1 << DMEM_AW) - 1];
    initial $readmemh(DATA_FILE, ram);
    wire [DMEM_AW-1:0] idx = a[DMEM_AW+1:2];
    always @(negedge clk) begin
        if (be[0]) ram[idx][0] <= wd[7:0];
        if (be[1]) ram[idx][1] <= wd[15:8];
        if (be[2]) ram[idx][2] <= wd[23:16];
        if (be[3]) ram[idx][3] <= wd[31:24];
        rd <= ram[idx];
    end
endmodule
