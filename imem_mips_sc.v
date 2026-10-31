//====================================================================
// imem_mips_sc.v  (MIPS-compatible single-cycle CPU, step 3)  -  instruction ROM, ASYNCHRONOUS read
//   Harris & Harris 2nd ed. section 7.6 "imem": RAM[a[7:2]] read combinationally. Here 2^IMEM_AW words (128 on the board),
//   index = a[IMEM_AW+1:2] (the fetch wraps around), contents = INIT_FILE (program.hex, one 32-bit word per line).
//   Cyclone IV M9K blocks have registered (synchronous) reads only, so Quartus builds this ROM from LUT logic
//   (the LE count depends on the program contents).
//====================================================================
module imem_mips_sc #(
    parameter IMEM_AW   = 7,
    parameter INIT_FILE = "program.hex"
) (
    input  [31:0] a,
    output [31:0] rd
);
    reg [31:0] rom [0:(1 << IMEM_AW) - 1];
    initial $readmemh(INIT_FILE, rom);
    assign rd = rom[a[IMEM_AW+1:2]];
endmodule
