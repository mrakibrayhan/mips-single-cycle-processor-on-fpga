//====================================================================
// snapshot_mips_sc.v  (MIPS-compatible single-cycle CPU, board view, step 14)  -  register / RAM snapshot for the
//                                                                              In-System Memory Content Editor
//   Same unit, same four 16-word RAMs and same declaration order (R00, R16, D00, D16) as the ARM / RISC-V boards:
//        R00 = $0  .. $15          R16 = $16 .. $31
//        D00 = RAM word  0 .. 15   (0x10000000 .. 0x1000003C)      D16 = RAM word 16 .. 31   (0x10000040 .. 0x1000007C)
//   (MIPS has 32 registers, so both R RAMs hold registers; PC, instruction and counters are in the ISSP probes.)
//   WHEN: the program halts or faults (trigger_auto) or the ISSP source bit is 1 (trigger_src, works at any time).
//   The core reads asynchronously, so the value of index i comes in the same cycle: the sweep presents idx 0..63 and
//   writes word idx in the same cycle (64 cycles).  idx 0..31 = $idx, 32..63 = RAM word idx-32.
//   IDLE (CPU runs) -> WAIT (freeze, until view_rdy) -> SNAP (64 cycles) -> DONE (frozen while the trigger stays 1) -> IDLE.
//   RESET CLEAR: while rst = 1 (KEY3 held, or the CPU not started yet) the four RAMs are written with 0 word by word
//   (16 cycles; the button filter keeps rst high for milliseconds), so after KEY3 the Memory Content Editor shows zeros.
//====================================================================
module snapshot_mips_sc (
    input         clk,           // cpu_clk
    input         rst,           // debounced reset (level)
    input         started,
    input         trigger_auto,  // halted | fault
    input         trigger_src,   // ISSP source bit (JTAG clock domain)
    input         view_rdy,      // the core is stopped and its view port is free
    input  [31:0] view_val,      // core dbg_val (belongs to idx of this cycle)
    output        freeze,
    output        done,
    output [5:0]  idx            // view index presented to the core
);
    reg s1 = 1'b0, s2 = 1'b0;
    always @(posedge clk) begin
        s1 <= trigger_src;
        s2 <= s1;
    end
    wire trigger = trigger_auto | s2;

    localparam IDLE = 2'd0, WAIT = 2'd1, SNAP = 2'd2, DONE = 2'd3;
    reg [1:0] state = IDLE;
    reg [5:0] cnt   = 6'd0;
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            cnt   <= 6'd0;
        end else begin
            case (state)
                IDLE: if (started && trigger) state <= WAIT;
                WAIT: if (view_rdy) begin state <= SNAP; cnt <= 6'd0; end
                SNAP: if (cnt == 6'd63) state <= DONE; else cnt <= cnt + 6'd1;
                DONE: if (!trigger) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
    assign freeze = (state != IDLE);
    assign done   = (state == DONE);
    assign idx    = cnt;
    wire   wr     = (state == SNAP);

    // reset clear: a 4-bit word counter that runs while rst = 1
    reg  [3:0]  clr = 4'd0;
    always @(posedge clk) clr <= rst ? clr + 4'd1 : 4'd0;

    wire [3:0]  word_in   = rst ? clr : cnt[3:0];
    wire [31:0] snap_data = rst ? 32'd0 : view_val;
    wire [31:0] q_R00_unused, q_R16_unused, q_D00_unused, q_D16_unused;

    altsyncram #(
        .operation_mode ("SINGLE_PORT"), .width_a (32), .widthad_a (4), .numwords_a (16),
        .outdata_reg_a ("UNREGISTERED"), .clock_enable_input_a ("BYPASS"), .clock_enable_output_a ("BYPASS"),
        .power_up_uninitialized ("FALSE"), .read_during_write_mode_port_a ("NEW_DATA_NO_NBE_READ"),
        .ram_block_type ("M9K"), .intended_device_family ("Cyclone IV E"),
        .lpm_hint ("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=R00"), .lpm_type ("altsyncram")
    ) snap_ram_R00 (.address_a (word_in), .clock0 (clk), .data_a (snap_data), .wren_a (rst | (wr && cnt[5:4] == 2'd0)), .q_a (q_R00_unused));

    altsyncram #(
        .operation_mode ("SINGLE_PORT"), .width_a (32), .widthad_a (4), .numwords_a (16),
        .outdata_reg_a ("UNREGISTERED"), .clock_enable_input_a ("BYPASS"), .clock_enable_output_a ("BYPASS"),
        .power_up_uninitialized ("FALSE"), .read_during_write_mode_port_a ("NEW_DATA_NO_NBE_READ"),
        .ram_block_type ("M9K"), .intended_device_family ("Cyclone IV E"),
        .lpm_hint ("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=R16"), .lpm_type ("altsyncram")
    ) snap_ram_R16 (.address_a (word_in), .clock0 (clk), .data_a (snap_data), .wren_a (rst | (wr && cnt[5:4] == 2'd1)), .q_a (q_R16_unused));

    altsyncram #(
        .operation_mode ("SINGLE_PORT"), .width_a (32), .widthad_a (4), .numwords_a (16),
        .outdata_reg_a ("UNREGISTERED"), .clock_enable_input_a ("BYPASS"), .clock_enable_output_a ("BYPASS"),
        .power_up_uninitialized ("FALSE"), .read_during_write_mode_port_a ("NEW_DATA_NO_NBE_READ"),
        .ram_block_type ("M9K"), .intended_device_family ("Cyclone IV E"),
        .lpm_hint ("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=D00"), .lpm_type ("altsyncram")
    ) snap_ram_D00 (.address_a (word_in), .clock0 (clk), .data_a (snap_data), .wren_a (rst | (wr && cnt[5:4] == 2'd2)), .q_a (q_D00_unused));

    altsyncram #(
        .operation_mode ("SINGLE_PORT"), .width_a (32), .widthad_a (4), .numwords_a (16),
        .outdata_reg_a ("UNREGISTERED"), .clock_enable_input_a ("BYPASS"), .clock_enable_output_a ("BYPASS"),
        .power_up_uninitialized ("FALSE"), .read_during_write_mode_port_a ("NEW_DATA_NO_NBE_READ"),
        .ram_block_type ("M9K"), .intended_device_family ("Cyclone IV E"),
        .lpm_hint ("ENABLE_RUNTIME_MOD=YES,INSTANCE_NAME=D16"), .lpm_type ("altsyncram")
    ) snap_ram_D16 (.address_a (word_in), .clock0 (clk), .data_a (snap_data), .wren_a (rst | (wr && cnt[5:4] == 2'd3)), .q_a (q_D16_unused));
endmodule
