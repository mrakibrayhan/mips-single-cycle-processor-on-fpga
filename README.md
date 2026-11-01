# MIPS-compatible single-cycle processor on FPGA (MIPS-SC)

A MIPS-compatible single-cycle processor implemented in Verilog and tested on the RZ-EasyFPGA A2.2 board (Intel Cyclone IV E EP4CE6E22C8).

> **Status:** complete and tested on hardware. Compiles with Intel Quartus Prime Lite.

## At a glance

| Item | Value |
|---|---|
| ISA | MIPS-compatible (MIPS32 integer subset: ALU, shifts, loads/stores, branches/jumps, MUL and HI/LO multiply; no delay slot; build parameter `HAS_MUL`) |
| Microarchitecture | single-cycle: Single-cycle: one instruction per clock, CPI = 1. |
| Language | Verilog / SystemVerilog |
| Board | RZ-EasyFPGA A2.2 (Intel Cyclone IV E EP4CE6E22C8, 6,272 LEs, 30 M9K) |
| Tool | Intel Quartus Prime Lite (built with 25.1std) |
| Top-level entity | `top_cpu_mips_sc` |
| Board clock | 50 MHz input divided by 4 = 12.5 MHz CPU clock |

## Memory system
Asynchronous-read memories built from logic elements (single-cycle). Board build: 128-word ROM, 32-word RAM. Optional `MEM_M9K` parameter (new file `mem_m9k_mips_sc.sv`) moves ROM and RAM into M9K blocks (ROM read on rising edge, RAM on falling edge) for larger programs; CPI stays 1. To use it, add `mem_m9k_mips_sc.sv` to the Quartus project (Project > Add/Remove Files in Project) and set `MEM_M9K = 1`; it is not in the default file list.

## Repository contents
- `alu_mips.v`
- `controller_mips_sc.v`
- `cpu_core_mips_sc.v`
- `datapath_mips_sc.v`
- `debounce.v`
- `dmem_mips_sc.v`
- `imem_mips_sc.v`
- `mem_m9k_mips_sc.sv`
- `mul_mips.v`
- `regfile_mips_sc.v`
- `seg7_decoder.v`
- `seg7_display.v`
- `shifter_mips.v`
- `snapshot_mips_sc.v`
- `top_cpu_mips_sc.v`
- `timing_constraints.sdc`
- `program.hex`
- `data.hex`
- `MIPS_Single_Cycle_Cpu.qpf`
- `MIPS_Single_Cycle_Cpu.qsf`
- `MIPS_Single_Cycle_Cpu.spf`
- `assembler_mips.py`

- `LICENSE`, `.gitignore`, `README.md`

## Build (Quartus)
1. Install Intel Quartus Prime Lite (the Cyclone IV E family is included).
2. Open `MIPS_Single_Cycle_Cpu.qpf`.
3. Processing > Start Compilation.
4. Programmer: load `output_files/MIPS_Single_Cycle_Cpu.sof` (not stored in the repository; see Releases for a ready-made `.sof`).

The `.qsf` already contains the device (`EP4CE6E22C8`), the pin assignments and the file list.

## Run on the board
- **KEY[3]** = reset (the CPU also stays in reset until KEY[2] is pressed once). **KEY[2]** = run.
- LEDG (active low = lit): [0] fault, [1] started, [2] snapshot done, [3] halted.
- Stop rule: `syscall`, `break`, or `j .` halts; illegal instruction = fault.
- The program is loaded from `program.hex`, the initial RAM from `data.hex`, both when the FPGA is programmed. Reset does not reload the RAM; program the FPGA again to restore it.
- **Snapshot / debug:** when the program halts, or when the ISSP source bit is set, the CPU is frozen and registers and RAM words are copied into small RAMs. Read them in Quartus with *Tools > In-System Memory Content Editor*; read counters and status with *Tools > In-System Sources and Probes Editor*. CPI = cycle counter / instruction counter.

## Writing your own program
`assembler_mips.py` (Python 3, no extra packages) turns an assembly file into the `program.hex` that the CPU loads when the FPGA is programmed:
```
python assembler_mips.py prog.s -o program.hex --core sc
```
Copy the new `program.hex` (and `data.hex` if the assembler wrote one) into the Quartus project folder and compile again. Run `python assembler_mips.py --help` for all options. The cores have no branch delay slot: put a `nop` after every `jal` / `jalr` (or use `--auto-nop`), because the return address is PC + 8.

## Limitations
- Subset ISA, no interrupts, no caches, no MMU, no floating point.
{c['lim']}

## Related repositories
This is one of 9 individual processor projects on FPGA: MIPS-compatible, RISC-V and ARMv4-compatible, each as single-cycle, multi-cycle and pipelined. <!-- add links when ready -->

## License
MIT, see `LICENSE`.

## Trademarks
MIPS is a trademark of MIPS Technologies, Inc.; this project is an independent, educational, MIPS-*compatible* design and is not affiliated with or endorsed by them.

## Author
Md. Rakib Rayhan, Dept. of ECE, North South University. Research Assistant, Microprocessor, Embedded Systems and IoT Lab (MESIL).
