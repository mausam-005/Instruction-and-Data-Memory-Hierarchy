# Instruction and Data Memory Hierarchy
# Microarchitectural Design, Memory Organization, and Verification of a Dual-Bus Harvard Memory Subsystem

[![Verilog-2012](https://img.shields.io/badge/HDL-Verilog--2012-blue.svg)](https://en.wikipedia.org/wiki/Verilog)
[![FPGA: Artix-7](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7%20(xc7a35t)-orange.svg)](https://www.xilinx.com/)
[![Simulation: Icarus](https://img.shields.io/badge/Simulation-Icarus%20Verilog%20%2B%20GTKWave-brightgreen.svg)](http://iverilog.icarus.com/)
[![Synthesis: Vivado](https://img.shields.io/badge/Synthesis-Xilinx%20Vivado%202020.1%2B-red.svg)](https://www.xilinx.com/products/design-tools/vivado.html)
[![Architecture: Dual-Bus](https://img.shields.io/badge/Architecture-Harvard%20Memory%20Hierarchy-purple.svg)](#2-architectural-overview--the-von-neumann-bottleneck)
[![ISA: RV32I-Subset](https://img.shields.io/badge/ISA-RISC--V%20RV32I%20Subset-yellow.svg)](https://riscv.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Team](https://img.shields.io/badge/Team-ParraPulse-purple.svg)](#-team-parrapulse)

---

### 👥 Team ParraPulse

**Course**: Modern Computer Architecture (MCA) • B.Tech (CS&AI) — Section A  
**Institution**: Newton School of Technology, Rishihood University 



---

### 📋 Team Members

| Student Name | Enrollment Number | Institutional Email |
| :--- | :---: | :--- |
| **Mausam Kumar Dwivedi** | `2401010266` | [mausam.dwivedi2024@nst.rishihood.edu.in](mailto:mausam.dwivedi2024@nst.rishihood.edu.in) |
| **Krish Dabas** | `2401010233` | [krish.dabas2024@nst.rishihood.edu.in](mailto:krish.dabas2024@nst.rishihood.edu.in) |
| **Arun Kumar Giri** | `2401010099` | [arun.giri2024@nst.rishihood.edu.in](mailto:arun.giri2024@nst.rishihood.edu.in) |
| **Ritik Atri** | `2401010386` | [ritik.attri2024@nst.rishihood.edu.in](mailto:ritik.attri2024@nst.rishihood.edu.in) |
| **Daniel Tayal** | `2401010140` | [daniel.tayal2024@nst.rishihood.edu.in](mailto:daniel.tayal2024@nst.rishihood.edu.in) |

---

## Table of Contents

1. [Executive Summary & Abstract](#1-executive-summary--abstract)
2. [Architectural Overview & The Von Neumann Bottleneck](#2-architectural-overview--the-von-neumann-bottleneck)
   - [2.1 The Shared Memory Contention Problem](#21-the-shared-memory-contention-problem)
   - [2.2 Harvard Split-Bus Concurrency Resolution](#22-harvard-split-bus-concurrency-resolution)
3. [Theoretical & Mathematical Formulations](#3-theoretical--mathematical-formulations)
   - [3.1 Structural Stall Probability Model](#31-structural-stall-probability-model)
   - [3.2 Analytical Cycles Per Instruction (CPI) Formulation](#32-analytical-cycles-per-instruction-cpi-formulation)
   - [3.3 Memory Bus Bandwidth Utilization](#33-memory-bus-bandwidth-utilization)
   - [3.4 Timing Closure & Maximum Operating Frequency ($F_{max}$)](#34-timing-closure--maximum-operating-frequency-f_max)
4. [RTL Hardware Subsystems & Microarchitecture](#4-rtl-hardware-subsystems--microarchitecture)
   - [4.1 Dedicated Instruction Memory (ROM / Read-Only Path)](#41-dedicated-instruction-memory-rom--read-only-path)
   - [4.2 Dedicated Data Memory with Byte-Enable Masking (RAM / R-W Path)](#42-dedicated-data-memory-with-byte-enable-masking-ram--r-w-path)
   - [4.3 Top-Level Harvard Subsystem & Concurrency Detector](#43-top-level-harvard-subsystem--concurrency-detector)
5. [Workloads & Verification Benchmark Program](#5-workloads--verification-benchmark-program)
6. [Hardware Telemetry & Performance Counters](#6-hardware-telemetry--performance-counters)
7. [FPGA Synthesis & Hardware Resource Utilization](#7-fpga-synthesis--hardware-resource-utilization)
   - [7.1 Vivado Synthesis Protocol (Xilinx Artix-7)](#71-vivado-synthesis-protocol-xilinx-artix-7)
   - [7.2 Resource Utilization Breakdown (LUTs, FFs, BRAMs)](#72-resource-utilization-breakdown-luts-ffs-brams)
   - [7.3 Static Timing Analysis & Setup Slack](#73-static-timing-analysis--setup-slack)
8. [Verification Suite & Waveform Verification](#8-verification-suite--waveform-verification)
   - [8.1 Self-Checking Assertions (`tb_harvard_mem.v`)](#81-self-checking-assertions-tb_harvard_memv)
   - [8.2 GTKWave Waveform Inspection Guide](#82-gtkwave-waveform-inspection-guide)
9. [Repository Layout & Artifact Manifest](#9-repository-layout--artifact-manifest)
10. [Installation, Reproduction & Simulation Guide](#10-installation-reproduction--simulation-guide)
11. [Academic Integrity, References & License](#11-academic-integrity-references--license)

---

## 1. Executive Summary & Abstract

In modern computer architecture, memory bandwidth is often the primary bottleneck restricting processor performance—a phenomenon historically identified as the **Von Neumann Bottleneck**. When instruction fetches ($\text{IF}$) and operand loads/stores ($\text{MEM}$) share a single unified bus, the processor cannot simultaneously fetch a subsequent instruction while accessing memory for data, forcing the processor pipeline to **stall**.

This repository presents a synthesizable **Harvard-Style Memory Hierarchy** in Verilog-2012, featuring completely independent, non-interfering instruction and data memory paths. The architecture is verified using directed self-checking testbenches and synthesized on a Xilinx Artix-7 FPGA target.

```
   ┌────────────────────────────────────────────────────────────────────────┐
   │                 HARVARD MEMORY HIERARCHY ARCHITECTURE                  │
   └────────────────────────────────────────────────────────────────────────┘
                                      │
               ┌──────────────────────┴──────────────────────┐
               ▼                                             ▼
     [ Instruction Memory (ROM) ]                  [ Data Memory (RAM) ]
     256 words x 32 bits (1 KB)                    256 words x 32 bits (1 KB)
     Word-aligned addressing [9:2]                 4-bit byte-enable write masking
     $readmemh preload support                     Synchronous write, async/sync read
               │                                             │
               └──────────────────────┬──────────────────────┘
                                      ▼
                        [ harvard_top Subsystem ]
                        Independent 32-bit Fetch & Data Buses
                        Dual-access Concurrency Detector
                        Hardware Performance Telemetry Meters
                                      │
               ┌──────────────────────┴──────────────────────┐
               ▼                                             ▼
     [ Verification Suite ]                       [ FPGA Synthesis (Artix-7) ]
     Self-checking testbench                      Vivado 2020.1+ Out-of-Context
     Preload, byte-mask & concurrency             Target: xc7a35tcpg236-1
     GTKWave VCD dump analysis                    Fmax > 160 MHz, 2 BRAM primitives
```

### Key Quantitative Findings
* **Elimination of Structural Stalls:** The Harvard dual-bus architecture executes simultaneous instruction fetch and data read/write transactions with **0 stall cycles**, validating complete spatial decoupling between instruction and data paths.
* **Effective Single-Cycle CPI:** By providing dedicated memory paths, the memory subsystem allows execution cores to sustain an ideal $\text{CPI} = 1.00$ without memory structural bubbles.
* **FPGA Synthesis Feasibility:** Synthesized on a Xilinx Artix-7 FPGA (`xc7a35tcpg236-1`), the hierarchy cleanly infers 2 Block RAM primitives with 0 Slice LUT memory logic overhead, achieving a post-synthesis maximum operating frequency exceeding **$160\text{ MHz}$**.

---

## 2. Architectural Overview & The Von Neumann Bottleneck

```
┌────────────────────────────────────────────────────────────────────────┐
│                        HARVARD ARCHITECTURE                            │
│                                                                        │
│               ┌─────────────────────────────────────┐                  │
│               │              CPU Core               │                  │
│               │     (Fetch / Decode / Execute)      │                  │
│               └──────────┬───────────────┬──────────┘                  │
│           Instr Bus      │               │     Data Bus                │
│    (Addr, ReadEn, Instr) │               │ (Addr, WData, RData, WEn)   │
│                          ▼               ▼                             │
│                  ┌──────────────┐ ┌──────────────┐                     │
│                  │ Instruction  │ │  Data Memory │                     │
│                  │ Memory (ROM) │ │  (RAM, R/W)  │                     │
│                  └──────────────┘ └──────────────┘                     │
│           [RESULT: 0 Stalls during Load/Store instructions]            │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.1 The Shared Memory Contention Problem
In a single-port unified memory system, both instruction opcodes and runtime data share the same physical bus. When the CPU executes a memory-reference instruction (`LW` or `SW`), it requires data memory access at the exact same cycle it must fetch the next instruction at $\text{PC} + 4$. This causes a **structural hazard**, requiring one of the operations to be deferred by injecting a pipeline stall.

### 2.2 Harvard Split-Bus Concurrency Resolution
The Harvard architecture decouples instruction storage from data storage into physically distinct memory arrays:
1. **Instruction Fetch Bus:** Dedicated exclusively to the Program Counter read path (`instr_addr[31:0]`, `instr_read_en`, `instr_data[31:0]`).
2. **Data Access Bus:** Dedicated exclusively to the execution unit load/store path (`data_addr[31:0]`, `data_wdata[31:0]`, `data_rdata[31:0]`, `data_byte_enable[3:0]`, `data_write_en`, `data_read_en`).

Because neither transaction contends for shared routing resources, both execute in parallel without structural delay.

---

## 3. Theoretical & Mathematical Formulations

### 3.1 Structural Stall Probability Model
Let a program execution trace consist of $N$ retired instructions, with memory-reference instructions $N_{\text{MEM}}$:

$$f_{\text{MEM}} = \frac{N_{\text{MEM}}}{N} = \frac{N_{\text{LW}} + N_{\text{SW}}}{N}$$

In a unified single-bus memory organization, each memory instruction creates an arbitration collision requiring 1 stall cycle ($S_{\text{penalty}} = 1\text{ cycle}$):

$$N_{\text{stalls, Unified}} = N \cdot f_{\text{MEM}}$$

In the Harvard architecture with separate buses, structural stalls are eliminated:

$$N_{\text{stalls, Harvard}} = 0$$

### 3.2 Analytical Cycles Per Instruction (CPI) Formulation
The total execution cycles required to complete a workload is:

$$T_{\text{Harvard}} = N \times \text{CPI}_{\text{base}} = N \times 1.00$$

$$T_{\text{Unified}} = N \cdot (1.00 + f_{\text{MEM}})$$

Consequently:

$$\text{CPI}_{\text{Harvard}} = 1.00$$

$$\text{CPI}_{\text{Unified}} = 1.00 + f_{\text{MEM}}$$

For a typical application where memory instructions account for $33.3\%$ of the workload ($f_{\text{MEM}} = 0.333$):

$$\text{CPI}_{\text{Unified}} = 1.33 \implies \text{Speedup } \mathcal{S} = \frac{1.33}{1.00} = 1.333\times \quad (25.0\% \text{ reduction in total execution time})$$

### 3.3 Memory Bus Bandwidth Utilization
$$\mathcal{U}_{\text{I-Bus, Harvard}} = \frac{N_{\text{Fetch}}}{T_{\text{Harvard}}} = \frac{N}{N} = 100.0\%$$

$$\mathcal{U}_{\text{D-Bus, Harvard}} = \frac{N_{\text{MEM}}}{T_{\text{Harvard}}} = f_{\text{MEM}}$$

### 3.4 Timing Closure & Maximum Operating Frequency ($F_{max}$)
$$T_{\text{clk}} \ge T_{\text{cq}} + T_{\text{comb, max}} + T_{\text{setup}} + T_{\text{skew}}$$

$$F_{\text{max}} = \frac{1}{T_{\text{clk, min}}}$$

In the Harvard architecture, address lines directly feed independent memory address decoders without passing through bus arbitration multiplexers, reducing $T_{\text{comb, max}}$ and enabling higher clock frequencies.

---

## 4. RTL Hardware Subsystems & Microarchitecture

```
                        HARVARD HARDWARE SUBSYSTEM (harvard_top.v)
                        
   ┌───────────────────────┐                    ┌───────────────────────┐
   │    instruction_mem    │                    │       data_mem        │
   │  (256 x 32-bit Words) │                    │  (256 x 32-bit Words) │
   │                       │                    │                       │
   │  addr[9:2] ──► Decode │                    │  addr[9:2] ──► Decode │
   │  read_en   ──► Output │                    │  byte_en[3:0]─► Mask  │
   │  instr     ◄── 32-bit │                    │  write_data ──► Synch │
   └───────────┬───────────┘                    └───────────┬───────────┘
               │                                            │
               │ Fetch Bus                                  │ Data Bus
               ▼                                            ▼
   ┌────────────────────────────────────────────────────────────────────┐
   │                      CONCURRENCY DETECTOR                          │
   │   simultaneous_access = instr_read_en && (data_re || data_we)      │
   └────────────────────────────────────────────────────────────────────┘
```

### 4.1 Dedicated Instruction Memory (ROM / Read-Only Path)
* **File:** [`rtl/instruction_mem.v`](rtl/instruction_mem.v)
* **Organization:** 256 words $\times$ 32 bits ($1,024\text{ Bytes}$ / $1\text{ KB}$ capacity).
* **Word-Aligned Addressing:** Computes internal word indices by discarding the lower 2 byte-offset bits:
  ```verilog
  wire [ADDR_BITS-1:0] word_idx = addr[ADDR_BITS+1:2];
  ```
* **Preload Mechanism:** Initializes simulation and FPGA block RAM contents directly from hexadecimal `.mem` files using synthesizable `$readmemh`:
  ```verilog
  if (MEM_INIT_FILE != "") begin
      $readmemh(MEM_INIT_FILE, memory);
  end
  ```
* **Read Latency Flexibility:** Configurable for both single-cycle asynchronous combinational lookup (`SYNC_READ = 0`) and registered synchronous BRAM output (`SYNC_READ = 1`).

### 4.2 Dedicated Data Memory with Byte-Enable Masking (RAM / R-W Path)
* **File:** [`rtl/data_mem.v`](rtl/data_mem.v)
* **Organization:** 256 words $\times$ 32 bits ($1\text{ KB}$ capacity).
* **Byte-Enable Masking:** Features a 4-bit write-mask (`byte_enable[3:0]`) enabling full compatibility with standard memory access granularities:
  * `4'b0001`: Store Byte (`SB`) — writes byte lane 0 (`memory[word_idx][7:0]`).
  * `4'b0011`: Store Halfword (`SH`) — writes byte lanes 0 and 1 (`memory[word_idx][15:0]`).
  * `4'b1111`: Store Word (`SW`) — writes all 32 bits simultaneously.
* **FPGA Synthesis Compliance:** Synthesizable template that infers Xilinx Block RAM (`RAMB18E1`/`RAMB36E1`) with byte-write enables.

### 4.3 Top-Level Harvard Subsystem & Concurrency Detector
* **File:** [`rtl/harvard_top.v`](rtl/harvard_top.v)
* Wires the independent instruction and data memory instances into a unified dual-port hierarchy.
* Includes hardware telemetry counters:
  * `simultaneous_access`: Dynamically asserts high when an instruction fetch and data transaction coincide on the exact same clock edge.
  * `simultaneous_access_count`: 32-bit hardware accumulator recording total conflict-free concurrent transfers.
  * `total_fetch_count` and `total_data_access_count`.

---

## 5. Workloads & Verification Benchmark Program

The verification benchmark is assembled in 32-bit hexadecimal format formatted for `$readmemh` ingestion:

* **File:** [`benchmarks/sample_prog.mem`](benchmarks/sample_prog.mem)
* **Instruction Stream:**
  ```text
  00000013 // 0x00: NOP (addi x0, x0, 0)
  00500113 // 0x04: addi x2, x0, 5      (x2 = 5)
  00a00193 // 0x08: addi x3, x0, 10     (x3 = 10)
  00310233 // 0x0C: add  x4, x2, x3     (x4 = 15)
  00412023 // 0x10: sw   x4, 0(x2)      (Store 15 at Mem[5])
  00012283 // 0x14: lw   x5, 0(x2)      (Load from Mem[5] into x5)
  005202b3 // 0x18: add  x5, x4, x5     (x5 = 15 + 15 = 30)
  0000006f // 0x1C: jal  x0, 0          (Infinite loop / halt)
  ```
* **Purpose:** Validates sequential arithmetic execution followed by back-to-back store and load operations, demonstrating zero-interference instruction fetching.

---

## 6. Hardware Telemetry & Performance Counters

To provide zero-overhead architectural visibility, `harvard_top.v` integrates line-rate hardware performance monitors:

```verilog
always @(posedge clk or posedge rst) begin
    if (rst) begin
        cycle_count               <= 32'd0;
        simultaneous_access_count <= 32'd0;
        total_fetch_count         <= 32'd0;
        total_data_access_count   <= 32'd0;
    end else begin
        cycle_count <= cycle_count + 1'b1;
        if (instr_read_en)
            total_fetch_count <= total_fetch_count + 1'b1;
        if (data_read_en || data_write_en)
            total_data_access_count <= total_data_access_count + 1'b1;
        if (simultaneous_access)
            simultaneous_access_count <= simultaneous_access_count + 1'b1;
    end
end
```

---

## 7. FPGA Synthesis & Hardware Resource Utilization

### 7.1 Vivado Synthesis Protocol (Xilinx Artix-7)
The complete Harvard hierarchy was synthesized using **Xilinx Vivado (v2020.1+)** in out-of-context batch mode:
* **Target Device:** AMD/Xilinx Artix-7 `xc7a35tcpg236-1` (Basys 3 / Nexys A7).
* **Synthesis Script:** [`synth/run_synth.tcl`](synth/run_synth.tcl)
* **Constraints:** Clock period specified at $10.000\text{ ns}$ ($100.0\text{ MHz}$).

```bash
vivado -mode batch -source synth/run_synth.tcl
```

### 7.2 Resource Utilization Breakdown (LUTs, FFs, BRAMs)

| FPGA Resource | Available on Artix-7 | Harvard Hierarchy Used | Utilization (%) |
| :--- | :---: | :---: | :---: |
| **Slice LUTs** | 20,800 | **64** | **0.31%** |
| **Slice Registers (FFs)** | 41,600 | **132** | **0.32%** |
| **Block RAM (RAMB18E1)** | 100 | **2 blocks** (1 I-Mem, 1 D-Mem) | **2.00%** |
| **DSP48 Slices** | 90 | **0** | **0.00%** |
| **Global Clock Buffers (BUFG)**| 32 | **1** | **3.13%** |

### 7.3 Static Timing Analysis & Setup Slack
* **Clock Period Target:** $10.000\text{ ns}$ ($100\text{ MHz}$)
* **Worst Negative Slack (WNS):** $+3.842\text{ ns}$ (Timing met with positive margin)
* **Worst Hold Slack (WHS):** $+0.214\text{ ns}$ (Met)
* **Computed Maximum Frequency ($F_{max}$):**
  $$F_{\text{max}} = \frac{1}{T_{\text{target}} - \text{WNS}} = \frac{1}{10.000\text{ ns} - 3.842\text{ ns}} = \frac{1}{6.158\text{ ns}} \approx \mathbf{162.39\text{ MHz}}$$

---

## 8. Verification Suite & Waveform Verification

### 8.1 Self-Checking Assertions (`tb_harvard_mem.v`)
[`sim/tb_harvard_mem.v`](sim/tb_harvard_mem.v) implements a comprehensive self-checking test suite:
* **Test 1:** Preload verification across multiple ROM addresses (`0x00`, `0x04`, `0x0C`).
* **Test 2:** Data memory full word read/write and 4-bit byte-enable write masking (`0xAABBCC55`).
* **Test 3 (Concurrency):** Simultaneously asserts instruction fetch and data store/load on the identical clock edge, verifying that `simultaneous_access == 1` and that no data corruption occurs.

#### Simulation Output:
```text
==================================================================
   Harvard Memory Hierarchy Verification Testbench    
==================================================================
[instruction_mem] Loading instruction hex from benchmarks/sample_prog.mem

[TEST 1] Verifying Instruction Memory Preload...
  [PASS] Addr 0x00 Fetched: 0x00000013 (NOP)
  [PASS] Addr 0x04 Fetched: 0x00500113 (ADDI)
  [PASS] Addr 0x0C Fetched: 0x00310233 (ADD)

[TEST 2] Verifying Data Memory Read/Write & Byte Enables...
  [PASS] Word Write/Read Matched: 0xaabbccdd
  [PASS] Byte-Enable Masking Verified: 0xaabbcc55

[TEST 3] Verifying CONCURRENT Fetch + Data Access (Harvard Principle)...
  [PASS] simultaneous_access flag successfully asserted.
  [PASS] Instruction fetched without interference: 0x00412023
  [PASS] Dual Concurrent Read Succeeded: Instr=0x00012283, Data=0xcafe1234

==================================================================
                      HARDWARE TELEMETRY REPORT                   
==================================================================
  Total Clock Cycles Elapsed : 8
  Total Instruction Fetches  : 5
  Total Data Accesses (R/W)  : 3
  Simultaneous Dual Accesses : 2
==================================================================
 >>> ALL 3 TESTS PASSED SUCCESSFULLY! <<<
 Harvard Dual-Bus Independence Verified: Zero Contention Stalls.
==================================================================
```

### 8.2 GTKWave Waveform Inspection Guide
Launch the waveform viewer:
```bash
make wave
# or:
gtkwave sim/harvard_mem.vcd
```
Verify that `simultaneous_access` pulses high while `instr_data` and `data_rdata` are valid simultaneously without any clock stall.

---

## 9. Repository Layout & Artifact Manifest

```text
mca_proj/
├── benchmarks/                 # Test programs (RV32I hex format)
│   ├── sample_prog.mem         # Basic instruction test program
│   └── array_sum.mem           # Memory contention benchmark
├── docs/                       # Project documentation & reports
├── rtl/                        # Synthesizable Verilog source files
│   ├── instruction_mem.v       # Dedicated Instruction ROM
│   ├── data_mem.v              # Dedicated Data RAM with byte masking
│   ├── harvard_top.v           # Harvard top-level hierarchy
│   ├── unified_mem.v           # Shared Von Neumann memory
│   ├── mem_arbiter.v           # Memory bus arbiter & stall FSM
│   ├── von_neumann_top.v       # Von Neumann baseline top module
│   ├── mini_core.v             # RV32I execution core
│   ├── alu.v                   # 32-bit Arithmetic Logic Unit
│   └── program_counter.v       # Program counter logic
├── sim/                        # Verification testbenches
│   ├── tb_harvard_mem.v        # Harvard self-checking testbench
│   ├── tb_von_neumann.v        # Von Neumann stall testbench
│   └── tb_comparison.v         # Dual-system comparison testbench
├── synth/                      # FPGA synthesis scripts
│   └── run_synth.tcl           # Vivado batch synthesis script
├── Makefile                    # Build and simulation automation
├── run.sh                      # Test runner script
├── LICENSE                     # MIT License
├── .gitignore                  # Git ignore rules
└── README.md                   # Project documentation
```

---

## 10. Installation, Reproduction & Simulation Guide

### Step 1: Environment Setup
Ensure simulation tools are installed:
```bash
# On macOS via Homebrew:
brew install icarus-verilog gtkwave

# On Ubuntu/Debian:
sudo apt-get install iverilog gtkwave
```

### Step 2: Clone the Repository
```bash
git clone https://github.com/mausam-005/Instruction-and-Data-Memory-Hierarchy.git
cd Instruction-and-Data-Memory-Hierarchy
```

### Step 3: Run the Verification Simulation
Using `make`:
```bash
make sim-harvard
```
Or using the executable shell script:
```bash
./run.sh
```

### Step 4: Inspect Waveforms in GTKWave
```bash
make wave
# or directly:
gtkwave sim/harvard_mem.vcd
```

### Step 5: Run FPGA Synthesis via Xilinx Vivado
```bash
make synth
# or directly:
vivado -mode batch -source synth/run_synth.tcl
```
Reports will be written to `synth/reports/`.

---

## 11. Academic Integrity, References & License

### References
1. **D. A. Patterson and J. L. Hennessy**, *Computer Organization and Design: The Hardware/Software Interface (RISC-V Edition)*, Morgan Kaufmann, 2020.
2. **J. L. Hennessy and D. A. Patterson**, *Computer Architecture: A Quantitative Approach*, 6th ed., Morgan Kaufmann, 2017.
3. **RISC-V International**, *The RISC-V Instruction Set Manual, Volume I: User-Level ISA (Document Version 20191213)*, Dec. 2019.
4. **AMD / Xilinx Inc.**, *7 Series FPGAs Memory Resources User Guide (UG473)*, v1.14, 2021.

### License
This project is open-source hardware licensed under the [MIT License](LICENSE).
