//====================================================================
// top_cpu_mips_sc.v  (board top-level - RZ-EasyFPGA A2.2 / Cyclone IV EP4CE6)
//
//   MIPS-compatible SINGLE-CYCLE CPU (Harris & Harris 2nd ed. section 7.3) with ASYNCHRONOUS-read memories
//   (instruction ROM in LUT logic, data RAM and register file in flip-flops). Same pins, buttons, LEDs, snapshot RAMs
//   and ISSP style as the ARM / RISC-V boards, so the same board procedure is used.
//
//   Buttons: KEY[3] = reset (the CPU is also held in reset until the first press of KEY[2]); KEY[2] = run.
//   LEDG (active low = lit), led0..led3 left to right = LEDG[0..3]:
//        [0] fault   [1] started   [2] snapshot done   [3] halted
//
//   SNAPSHOT (snapshot_mips_sc.v): on halt / fault, or when the ISSP source bit is 1, the CPU stops and $0..$31 and the
//   32 RAM words are copied into four RAMs read with the In-System Memory Content Editor:
//        R00 = $0..$15   R16 = $16..$31   D00 = RAM 0..15   D16 = RAM 16..31
//   ISSP (altsource_probe, instance "MIPS"): source[0] = manual snapshot request;
//     probe (116 bits, LSB first):
//         [0] started  [1] halted  [2] fault  [3] snapshot done
//         [19:4]    PC (low 16 bits); after a halt: syscall / break -> address + 4, "j ." -> its own address,
//                   after a fault: the illegal instruction's address + 4
//         [51:20]   instruction word at the PC
//         [83:52]   CYCLE COUNTER       CPU clock cycles while running (snapshot stops are not counted)
//         [115:84]  INSTRUCTION COUNTER executed instructions (the stop / faulting instruction included)
//       Single-cycle: cycle counter = instruction counter (CPI = 1) = 'instrs' of mips_iss.py.
//   RAM starting values come from data.hex (32 lines, line 1 = word 0 at 0x10000000), loaded when the FPGA is programmed.
//   The reset (KEY3) does not reload or clear the RAM: program the FPGA again to restore the data.hex values.
//====================================================================
module top_cpu_mips_sc #(
    parameter [7:0] FEATURES  = 8'hFF,
    parameter       IMEM_AW   = 7,              // 128 instruction words
    parameter       DMEM_AW   = 5,              // 32 data words
    parameter       INIT_FILE = "program.hex",
    parameter       DATA_FILE = "data.hex",
    parameter       DEBOUNCE  = 250000          // button filter length in clock cycles (the testbench makes it short)
) (
    input        clk,      // PIN_23
    input  [4:0] KEY,      // PIN_88,89,90,91,25 (only KEY[3], KEY[2] used)
    output [7:0] SEG,      // PIN_128,121,125,129,132,126,124,127
    output [3:0] DIG,      // PIN_133,135,136,137
    output [3:0] LEDG      // PIN_87,86,85,84
);
    //----------------------------------------------------------------
    // Clock divider: 50 MHz / 4 = 12.5 MHz for the CPU core
    //----------------------------------------------------------------
    reg [1:0] clkdiv = 2'b00;
    always @(posedge clk) clkdiv <= clkdiv + 2'b01;
    wire cpu_clk = clkdiv[1];

    //----------------------------------------------------------------
    // Buttons: KEY[3] reset (level), KEY[2] run (one pulse)
    //----------------------------------------------------------------
    wire key3_raw = ~KEY[3];
    wire rst_debounced;
    debounce #(.DEBOUNCE_LIMIT(DEBOUNCE)) db_rst (.clk(clk), .btn_in(key3_raw), .btn_out(rst_debounced));

    wire key2_raw = ~KEY[2];
    wire key2_debounced, step_pulse;
    debounce #(.DEBOUNCE_LIMIT(DEBOUNCE)) db_step (.clk(cpu_clk), .btn_in(key2_raw), .btn_out(key2_debounced));
    edge_detector ed_step (.clk(cpu_clk), .signal_in(key2_debounced), .pulse_out(step_pulse));

    reg started = 1'b0;
    always @(posedge cpu_clk) begin
        if (rst_debounced)   started <= 1'b0;
        else if (step_pulse) started <= 1'b1;
    end

    //----------------------------------------------------------------
    // CPU (held in reset until 'started')
    //----------------------------------------------------------------
    wire        snap_req, frz_req, view_rdy, snap_done, retire, halted, fault;
    wire [5:0]  snap_idx;
    wire [31:0] pc, instr, view_val;
    wire        cpu_rst = rst_debounced | ~started;

    cpu_core_mips_sc #(.FEATURES(FEATURES), .IMEM_AW(IMEM_AW), .DMEM_AW(DMEM_AW), .INIT_FILE(INIT_FILE),
                       .DATA_FILE(DATA_FILE), .DBG_EN(1)) mycpu (
        .clk(cpu_clk), .rst(cpu_rst), .halted(halted), .fault(fault), .retire(retire), .pc(pc), .instr(instr),
        .tr_regw(), .tr_wa(), .tr_wd(), .tr_be(), .tr_adr(), .tr_mdata(), .tr_hiw(), .tr_low(), .tr_hi(), .tr_lo(),
        .freeze(frz_req), .view_rdy(view_rdy), .dbg_idx(snap_idx), .dbg_val(view_val));

    //----------------------------------------------------------------
    // Counters (cpu_clk): count while the CPU runs (not stopped for a snapshot), stop at the halt / fault.
    //----------------------------------------------------------------
    reg [31:0] cycle_count = 32'd0, instr_count = 32'd0;
    wire running = started & ~view_rdy;
    always @(posedge cpu_clk) begin
        if (cpu_rst) begin
            cycle_count <= 32'd0; instr_count <= 32'd0;
        end else if (running) begin
            cycle_count <= cycle_count + 32'd1;
            if (retire) instr_count <= instr_count + 32'd1;
        end
    end

    //----------------------------------------------------------------
    // Snapshot unit
    //----------------------------------------------------------------
    snapshot_mips_sc snap (.clk(cpu_clk), .rst(cpu_rst), .started(started), .trigger_auto(halted | fault),
                           .trigger_src(snap_req), .view_rdy(view_rdy), .view_val(view_val), .freeze(frz_req),
                           .done(snap_done), .idx(snap_idx));

    //----------------------------------------------------------------
    // 7-seg display unused (same as the ARM boards)
    //----------------------------------------------------------------
    assign SEG = 8'hFF;
    assign DIG = 4'hF;

    // LEDs (active low)
    assign LEDG[0] = ~fault;
    assign LEDG[1] = ~started;
    assign LEDG[2] = ~snap_done;
    assign LEDG[3] = ~halted;

    //----------------------------------------------------------------
    // ISSP: source = manual snapshot request, probe = status + PC + instruction + counters
    //----------------------------------------------------------------
    wire [115:0] probe_status = {instr_count, cycle_count, instr, pc[15:0], snap_done, fault, halted, started};
    altsource_probe #(
        .lpm_type                ("altsource_probe"),
        .lpm_hint                ("UNUSED"),
        .sld_auto_instance_index ("YES"),
        .sld_instance_index      (0),
        .SLD_NODE_INFO           (4746752),
        .sld_ir_width            (4),
        .instance_id             ("MIPS"),
        .probe_width             (116),
        .source_width            (1),
        .source_initial_value    ("0"),
        .enable_metastability    ("NO")
    ) inst_issp (
        .probe      (probe_status),
        .source     (snap_req),
        .source_clk (cpu_clk),
        .source_ena (1'b1)
    );
endmodule
