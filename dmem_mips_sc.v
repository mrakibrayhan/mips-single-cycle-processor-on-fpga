//====================================================================
// dmem_mips_sc.v  (MIPS-compatible single-cycle CPU, step 3)  -  data RAM, ASYNCHRONOUS read, byte enables
//   Harris & Harris 2nd ed. section 7.6 "dmem": combinational read, write on the rising clock edge.
//   Added for sb / sh: 4 byte-write enables (be[0] = bits 7:0 = byte at address +0, little-endian).
//   2^DMEM_AW words (32 on the board); only a[DMEM_AW+1:2] is decoded, so address 84 (H&H test) and 0x10000054
//   reach the same word. Starting values = DATA_FILE (data.hex, loaded when the FPGA is programmed).
//   Cyclone IV M9K blocks cannot read asynchronously, so Quartus builds this RAM from flip-flops and a read mux.
//====================================================================
module dmem_mips_sc #(
    parameter DMEM_AW   = 5,
    parameter DATA_FILE = "data.hex"
) (
    input         clk,
    input  [3:0]  be,        // byte write enables (all 0 = no write)
    input  [31:0] a,
    input  [31:0] wd,        // write data, already placed in the right byte lanes
    output [31:0] rd
);
    reg [31:0] ram [0:(1 << DMEM_AW) - 1];
    initial $readmemh(DATA_FILE, ram);
    wire [DMEM_AW-1:0] idx = a[DMEM_AW+1:2];
    always @(posedge clk) begin
        if (be[0]) ram[idx][7:0]   <= wd[7:0];
        if (be[1]) ram[idx][15:8]  <= wd[15:8];
        if (be[2]) ram[idx][23:16] <= wd[23:16];
        if (be[3]) ram[idx][31:24] <= wd[31:24];
    end
    assign rd = ram[idx];
endmodule
