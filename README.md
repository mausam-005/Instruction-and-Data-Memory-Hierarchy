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
[![Project Report](https://img.shields.io/badge/Project%20Report-Google%20Drive-4285F4?logo=googledrive&logoColor=white)](https://drive.google.com/file/d/1HxIQQh_ys-8o41iLnRTYsdTiGArKg6vq/view?usp=sharing)

[![Demo Video](https://img.shields.io/badge/Demo%20Video-Google%20Drive-EA4335?logo=googledrive&logoColor=white)](https://drive.google.com/file/d/1MT-75QLSNY-Y-3xUJg2uCGPZHxCEZx8F/view?usp=sharing)

---

### 👥 Team ParraPulse

**Course**: Modern Computer Architecture (MCA) • B.Tech (CS&AI) — Section A  
**Institution**: Newton School of Technology, Rishihood University  

> **Phase I Deliverables & Verification Links:**
> - 📄 **Project Report**: [View Full Report (Google Drive)](https://drive.google.com/file/d/1HxIQQh_ys-8o41iLnRTYsdTiGArKg6vq/view?usp=sharing) &nbsp;•&nbsp; [Local Copy (`docs/MCA_report.pdf`)](docs/MCA_report.pdf)
> - 🎥 **Project Demo**: [Watch  Project Demo Video](https://drive.google.com/file/d/1MT-75QLSNY-Y-3xUJg2uCGPZHxCEZx8F/view?usp=sharing)

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
   - [4.4 Unified Von Neumann Memory & Bus Arbiter Subsystem](#44-unified-von-neumann-memory--bus-arbiter-subsystem)
   - [4.5 Lightweight CPU Execution Engine, Datapath & ALU](#45-lightweight-cpu-execution-engine-datapath--alu)
   - [4.6 5-Stage Pipelined RV32I Processor Core (`pipeline_core.v`, `pipe_regs.v`)](#46-5-stage-pipelined-rv32i-processor-core-pipeline_corev-pipe_regsv)
   - [4.7 Unified Von Neumann Pipelined Baseline Core (`unified_pipeline_top.v`)](#47-unified-von-neumann-pipelined-baseline-core-unified_pipeline_topv)
   - [4.8 L1 Instruction Cache & Pipelined Harvard Subsystem (`icache.v`, `pipeline_harvard_top.v`)](#48-l1-instruction-cache--pipelined-harvard-subsystem-icachev-pipeline_harvard_topv)
   - [4.9 Pipeline Hazard Detection & Flow Management Unit (`hazard_unit.v`)](#49-pipeline-hazard-detection--flow-management-unit-hazard_unitv)
   - [4.10 ALU Operand Forwarding & Bypass Subsystem (`forwarding_unit.v`)](#410-alu-operand-forwarding--bypass-subsystem-forwarding_unitv)
5. [Workloads & Verification Benchmark Programs](#5-workloads--verification-benchmark-programs)
   - [5.1 Verification Sequence (`sample_prog.mem`)](#51-verification-sequence-sample_progmem)
   - [5.2 Memory Contention Benchmark (`array_sum.mem`)](#52-memory-contention-benchmark-array_summem)
   - [5.3 Memory-Intensive Matrix Multiplication Workload (`matrix_mult.mem`)](#53-memory-intensive-matrix-multiplication-workload-matrix_multmem)
6. [Hardware Telemetry & Performance Counters](#6-hardware-telemetry--performance-counters)
   - [6.1 Baseline Line-Rate Hardware Monitors](#61-baseline-line-rate-hardware-monitors)
   - [6.2 32-Bit Hardware Performance Telemetry Engine (`phase2_telemetry.v`)](#62-32-bit-hardware-performance-telemetry-engine-phase2_telemetryv)
7. [FPGA Synthesis & Hardware Resource Utilization](#7-fpga-synthesis--hardware-resource-utilization)
   - [7.1 Vivado Synthesis Protocol (Xilinx Artix-7)](#71-vivado-synthesis-protocol-xilinx-artix-7)
   - [7.2 Phase I Resource Utilization Breakdown (LUTs, FFs, BRAMs)](#72-phase-i-resource-utilization-breakdown-luts-ffs-brams)
   - [7.3 Static Timing Analysis & Setup Slack](#73-static-timing-analysis--setup-slack)
   - [7.4 Phase II FPGA Synthesis & Timing Closure Analysis ($F_{max}$)](#74-phase-ii-fpga-synthesis--timing-closure-analysis-f_max)
8. [Verification Suites & Experimental Benchmarking](#8-verification-suites--experimental-benchmarking)
   - [8.1 Harvard Memory Hierarchy Verification (`tb_harvard_mem.v`)](#81-harvard-memory-hierarchy-verification-tb_harvard_memv)
   - [8.2 Von Neumann Baseline Verification (`tb_von_neumann.v`)](#82-von-neumann-baseline-verification-tb_von_neumannv)
   - [8.3 Head-to-Head Comparative Benchmark (`tb_comparison.v`)](#83-head-to-head-comparative-benchmark-tb_comparisonv)
   - [8.4 Unified Pipelined Core Verification & Telemetry Results (`tb_unified_pipeline.v`)](#84-unified-pipelined-core-verification--telemetry-results-tb_unified_pipelinev)
   - [8.5 Pipelined Harvard Core & Hazard Verification Suite (`tb_pipeline_harvard.v`)](#85-pipelined-harvard-core--hazard-verification-suite-tb_pipeline_harvardv)
   - [8.6 Waveform Inspection Guide](#86-waveform-inspection-guide)
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

### 4.4 Unified Von Neumann Memory & Bus Arbiter Subsystem
* **Files:** [`rtl/unified_mem.v`](rtl/unified_mem.v), [`rtl/mem_arbiter.v`](rtl/mem_arbiter.v), [`rtl/von_neumann_top.v`](rtl/von_neumann_top.v)
* **Architecture:** Serves as the architectural baseline representing a unified memory organization where instruction fetches and data loads/stores share a single physical port.
* **Bus Arbiter FSM:**
  * Implements priority arbitration: data load/store takes precedence over instruction fetch during simultaneous access.
  * When collision occurs, the arbiter asserts `stall = 1` to freeze the processor pipeline, services the data transaction in cycle 1, and subsequently serves the stalled instruction fetch in cycle 2.
  * Provides hardware telemetry for structural contention events (`stall_count`, `contention_count`).

### 4.5 Lightweight CPU Execution Engine, Datapath & ALU
* **Files:** [`rtl/mini_core.v`](rtl/mini_core.v), [`rtl/program_counter.v`](rtl/program_counter.v), [`rtl/alu.v`](rtl/alu.v)
* **Program Counter:** 32-bit register with sequential $+4$ incrementing, branch/jump target loading, and stall-gated freeze logic.
* **32-bit ALU:** Implements 10 core RV32I operations: `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLT`, `SLTU`, `SLL`, `SRL`, `SRA`, with zero, negative, carry, and overflow status flags.
* **Execution Datapath:** 32 general-purpose 32-bit registers (`x0` hardwired to zero), instruction field decoder supporting R-type, I-type (`ADDI`, `LW`), S-type (`SW`), B-type (`BEQ`, `BNE`), and J-type (`JAL`) instructions.

### 4.6 5-Stage Pipelined RV32I Processor Core (`pipeline_core.v`, `pipe_regs.v`)
* **Files:** [`rtl/pipeline_core.v`](rtl/pipeline_core.v), [`rtl/pipe_regs.v`](rtl/pipe_regs.v)
* **Pipelined Datapath Stages:** Classical 5-stage RISC microarchitecture:
  1. **IF (Instruction Fetch):** Program Counter generation, branch redirection multiplexing, and instruction memory read requests.
  2. **ID (Instruction Decode):** Dual-read register file access, sign-extended 32-bit immediate generation (I, S, B, U, J types), and control decoding.
  3. **EX (Execute / Address Calc):** 32-bit RV32I ALU operation, full operand forwarding network (EX/MEM and MEM/WB bypasses), and branch target resolution.
  4. **MEM (Memory Access):** Data memory read/write interfacing with 4-bit byte-enable write masking for halfword and byte accesses.
  5. **WB (Writeback):** Register file commit from ALU result, loaded memory data, or link address ($PC + 4$).
* **Hazard & Flow Control Unit:**
  - **Data Forwarding:** Eliminates RAW dependencies between consecutive arithmetic instructions with 0 stall overhead.
  - **Load-Use Hazard Detection:** Injects a single-cycle hardware bubble when an instruction immediately consumes loaded data.
  - **Control Hazard Squashing:** Resolves branches in EX stage and flushes speculative IF and ID stages on misprediction.

### 4.7 Unified Von Neumann Pipelined Baseline Core (`unified_pipeline_top.v`)
* **File:** [`rtl/unified_pipeline_top.v`](rtl/unified_pipeline_top.v)
* **Author / Owner:** Daniel Tayal (`2401010140`)
* **Microarchitecture & The Shared Bus Contention Proof:**
  - Couples the 5-stage pipelined RV32I core with a single-port Unified Memory (`unified_mem.v`).
  - **Structural Hazard Collision:** In every cycle where a memory instruction (`LW` or `SW`) occupies the MEM stage (`dmem_read_en || dmem_write_en`), both the **Fetch (IF)** and **Memory (MEM)** stages contend for the single shared memory port.
  - **Priority Bus Multiplexing:** Priority is granted to the older in-flight instruction in the MEM stage to prevent pipeline deadlocks and ensure precise retirement order.
  - **Pipeline Bubble Injection:**
    - The structural hazard detection logic asserts `stall_fetch = 1`.
    - The Program Counter is frozen (`stall_pc = 1`), preserving the fetch address for the deferred instruction.
    - An architectural bubble (NOP: `addi x0, x0, 0` / `32'h00000013`) is synchronously injected into the `pipe_reg_if_id` pipeline register.
    - The MEM stage completes its Load or Store in that cycle and advances to WB.
    - In the subsequent cycle, the MEM stage is inactive, the shared bus is granted to IF, and the deferred instruction is successfully fetched.
  - **Quantitative Result:** Every single `LW` and `SW` instruction provokes an exact single-cycle structural stall, providing empirical physical proof of the Von Neumann bottleneck in pipelined processors.

```
       UNIFIED VON NEUMANN PIPELINED BASELINE ARCHITECTURE (unified_pipeline_top.v)

       ┌────────────────────────────────────────────────────────┐
       │             5-Stage RV32I Pipelined Core               │
       │   [ IF ] ──► [ ID ] ──► [ EX ] ──► [ MEM ] ──► [ WB ]  │
       └─────┬─────────────────────────────────┬────────────────┘
             │ IF Fetch Req                    │ MEM Data Req (LW/SW)
             ▼                                 ▼
       ┌────────────────────────────────────────────────────────┐
       │         STRUCTURAL HAZARD ARBITER & BUBBLE LOGIC       │
       │  - If MEM active (LW/SW):                              │
       │      * Grant bus to MEM stage                          │
       │      * Assert stall_fetch = 1 (Freeze PC)              │
       │      * Inject NOP bubble into IF/ID register           │
       │  - Else: Grant bus to IF stage (0 stall fetch)         │
       └──────────────────────────┬─────────────────────────────┘
                                  │ Single 32-bit Memory Bus
                                  ▼
                     ┌─────────────────────────┐
                     │       unified_mem       │
                     │  (Single Physical Port) │
                     │  256 words x 32 bits    │
                     └─────────────────────────┘
```

### 4.8 L1 Instruction Cache & Pipelined Harvard Subsystem (`icache.v`, `pipeline_harvard_top.v`)
* **Files:** [`rtl/icache.v`](rtl/icache.v), [`rtl/pipeline_harvard_top.v`](rtl/pipeline_harvard_top.v)
* Direct-mapped 4-word line burst refill cache resolving instruction access latency, fully integrated into the Harvard split-bus memory hierarchy.

### 4.9 Pipeline Hazard Detection & Flow Management Unit (`hazard_unit.v`)
* **File:** [`rtl/hazard_unit.v`](rtl/hazard_unit.v)
* **Author / Owner:** Arun Kumar Giri (`2401010099`) — Role 4 Specialist
* **Microarchitecture & Responsibilities:**
  1. **Load-Use Data Hazard Detection:**
     - Monitors memory read requests in the EX stage (`ex_mem_read`) and detects when the loaded destination register (`ex_rd != 0`) matches an active source register (`id_rs1` or `id_rs2`) in the Decode stage.
     - When detected, injects an exact single-cycle pipeline bubble:
       $$\text{stall\_pc} = 1, \quad \text{stall\_if\_id} = 1, \quad \text{flush\_id\_ex} = 1$$
       This freezes the PC and IF/ID register, clears the ID/EX control signals with a NOP bubble (`addi x0, x0, 0`), and allows the older LOAD instruction to advance to the MEM stage and retrieve the operand.
  2. **Opcode-Aware Operand Usage Decoding:**
     - Prevents false load-use stalls by inspecting `id_opcode`. In RISC-V RV32I, I-type instructions (`ADDI`, `SLTI`, etc.) and LOAD instructions place immediate bits `imm[4:0]` in instruction bits `[24:20]`.
     - The hazard unit decodes whether `rs1` and `rs2` are genuinely read by the instruction opcode:
       $$\text{rs1\_used} \in \{\text{R-type}, \text{I-type}, \text{LOAD}, \text{STORE}, \text{BRANCH}, \text{JALR}\}$$
       $$\text{rs2\_used} \in \{\text{R-type}, \text{STORE}, \text{BRANCH}\}$$
       Immediate bits in `[24:20]` for `ADDI` or `LW` are never falsely flagged as `rs2` register hazards.
  3. **Multi-Cycle Cache Miss / Memory Stall Freezing:**
     - Monitors L1 I-Cache miss bursts (`icache_stall`), L1 D-Cache refills (`dcache_stall`), and external memory waits (`ext_stall`).
     - Freezes all 5 pipeline stage registers (`PC`, `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`) synchronously without flushing in-flight state.
  4. **Control Hazard Resolution:**
     - Flushes speculative instructions in `IF/ID` and `ID/EX` (`flush_if_id = 1`, `flush_id_ex = 1`) on branch evaluation or jump redirection (`ex_branch_taken`).

```
                PIPELINE HAZARD DETECTION UNIT (hazard_unit.v)

        [ ID Stage: Opcode, rs1, rs2 ]    [ EX Stage: MemRead, rd ]
                       │                              │
                       ▼                              ▼
        ┌─────────────────────────────────────────────────────────┐
        │            OPCODE-AWARE LOAD-USE DETECTOR               │
        │   rs1_haz = rs1_used && (id_rs1 != 0) && (ex_rd == id_rs1)│
        │   rs2_haz = rs2_used && (id_rs2 != 0) && (ex_rd == id_rs2)│
        │   load_use = ex_mem_read && (rs1_haz || rs2_haz)       │
        └────────────────────────────┬────────────────────────────┘
                                     │
           ┌─────────────────────────┼─────────────────────────┐
           ▼                         ▼                         ▼
   [ Freeze PC: stall_pc ]  [ Freeze IF/ID: stall_if_id ] [ Bubble: flush_id_ex ]
```

### 4.10 ALU Operand Forwarding & Bypass Subsystem (`forwarding_unit.v`)
* **File:** [`rtl/forwarding_unit.v`](rtl/forwarding_unit.v)
* **Author / Owner:** Arun Kumar Giri (`2401010099`) — Role 4 Specialist
* **Microarchitecture & Forwarding Policy:**
  - Implements full operand bypassing directly from the `EX/MEM` and `MEM/WB` stages into the `EX` stage ALU inputs (`alu_in_a`, `alu_in_b`), eliminating data hazard stalls for back-to-back arithmetic instructions.
  - **Distance 1 Bypass (EX/MEM -> EX, Code `2'b10`):**
    Triggered when `mem_reg_write && (mem_rd != 0) && (mem_rd == ex_rs)`.
    Bypasses the ALU result, formatted memory data, or return link ($PC+4$).
  - **Distance 2 Bypass (MEM/WB -> EX, Code `2'b01`):**
    Triggered when `wb_reg_write && (wb_rd != 0) && (wb_rd == ex_rs)`.
    Bypasses the final committed writeback data (`wb_reg_wdata`).
  - **Temporal Priority Resolution:**
    When both `EX/MEM` and `MEM/WB` write to the same destination register, `EX/MEM` (the most recent instruction) is strictly prioritized over `MEM/WB`.
  - **Register x0 Hardwiring:**
    Writes to `x0` (`5'd0`) are hardwired to zero and never forwarded (`forward = 2'b00`).
  - **Store Data Forwarding:**
    Provides forwarded `fwd_store_data` to ensure `SW`, `SH`, and `SB` instructions store the freshly computed register values directly from earlier pipeline stages.

```
                 ALU OPERAND FORWARDING NETWORK (forwarding_unit.v)

        [ EX/MEM Result ] ───────────────┐ (Distance 1: Code 2'b10)
        [ MEM/WB Data   ] ────────┐      │ (Distance 2: Code 2'b01)
        [ RegFile Read  ] ──┐     │      │ (Default   : Code 2'b00)
                            ▼     ▼      ▼
                      ┌──────────────────────┐
                      │ 3-to-1 Forward Mux A │ ──► [ ALU Input A ]
                      └──────────────────────┘
                      ┌──────────────────────┐
                      │ 3-to-1 Forward Mux B │ ──► [ ALU Input B / Store Data ]
                      └──────────────────────┘
```

---

## 5. Workloads & Verification Benchmark Programs

### 5.1 Verification Sequence (`sample_prog.mem`)
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

### 5.2 Memory Contention Benchmark (`array_sum.mem`)
* **File:** [`benchmarks/array_sum.mem`](benchmarks/array_sum.mem)
* **Workload Description:** A vector accumulation workload designed to provoke intense memory bus contention between instruction fetch and operand load/store operations.
* **Algorithm:**
  1. Initializes base address pointer (`x1 = 0x40`) and accumulator (`x3 = 0`).
  2. Executes an unrolled loop loading 8 consecutive 32-bit integers (`1, 2, 3, 4, 5, 6, 7, 8`) via `LW` instructions into register `x2`.
  3. Accumulates the values into `x3` via `ADD` instructions.
  4. Stores the final sum (`36` / `0x24`) into memory address `0x60` via `SW`.
  5. Terminates at `0x2C` (`JAL x0, 0`).
* **Architectural Stress Effect:** Every `LW` and `SW` operation triggers simultaneous memory read/write requests alongside the CPU's sequential instruction fetch, exposing the Von Neumann shared bus bottleneck and verifying Harvard's contention-free execution.

### 5.3 Memory-Intensive Matrix Multiplication Workload (`matrix_mult.mem`)
* **File:** [`benchmarks/matrix_mult.mem`](benchmarks/matrix_mult.mem)
* **Author / Owner:** Daniel Tayal (`2401010140`)
* **Workload Description:** A dense $2 \times 2$ Matrix Multiplication algorithm ($C = A \times B$) implemented entirely in RV32I assembly. Matrix multiplication is universally recognized in computer architecture as the ultimate memory hierarchy stress test due to its intense data access density and repeated interleaved operand streaming.
* **Mathematical Matrix Formulation:**
  $$\mathbf{A} = \begin{bmatrix} 2 & 3 \\ 4 & 5 \end{bmatrix}, \quad \mathbf{B} = \begin{bmatrix} 1 & 2 \\ 3 & 4 \end{bmatrix}$$
  $$\mathbf{C} = \mathbf{A} \times \mathbf{B} = \begin{bmatrix} (2\cdot 1 + 3\cdot 3) & (2\cdot 2 + 3\cdot 4) \\ (4\cdot 1 + 5\cdot 3) & (4\cdot 2 + 5\cdot 4) \end{bmatrix} = \begin{bmatrix} 11 & 16 \\ 19 & 28 \end{bmatrix}$$
  $$\text{Checksum } \Sigma(C) = 11 + 16 + 19 + 28 = 74 \quad (\text{0x4A})$$
* **Non-Overlapping Memory Organization:**
  - **Instructions:** Byte addresses `0x000` to `0x10C` (Word indices 0 to 67, 68 machine instructions).
  - **Matrix A Storage:** Byte addresses `0x180` to `0x18C` (Word indices 96 to 99 / `@60`).
  - **Matrix B Storage:** Byte addresses `0x190` to `0x19C` (Word indices 100 to 103 / `@64`).
  - **Matrix C Result Storage:** Byte addresses `0x1A0` to `0x1AC` (Word indices 104 to 107 / `@68`).
  - **Final Checksum:** Byte address `0x1B0` (Word index 108).
* **Quantitative Workload Characteristics:**
  - **Total Dynamic Instructions Retired:** $123\text{ instructions}$
  - **Data Loads (LW):** $20\text{ operations}$
  - **Data Stores (SW):** $5\text{ operations}$
  - **Total Memory Reference Transactions:** $25\text{ memory operations}$
  - **Memory Instruction Density:** $20.33\%$ of the entire workload ($f_{\text{MEM}} = 0.2033$).
  - **Structural Collisions on Von Neumann:** Exactly 25 collision cycles, resulting in 25 injected pipeline bubbles.

---

## 6. Hardware Telemetry & Performance Counters

### 6.1 Baseline Line-Rate Hardware Monitors
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

### 6.2 32-Bit Hardware Performance Telemetry Engine (`phase2_telemetry.v`)
* **File:** [`rtl/phase2_telemetry.v`](rtl/phase2_telemetry.v)
* **Author / Owner:** Daniel Tayal (`2401010140`)
* **Architecture:** Dedicated non-intrusive 32-bit hardware performance monitoring unit sampling execution event streams from the 5-stage pipeline core and memory hierarchy.
* **Monitored Hardware Performance Metrics:**
  1. **Cycle & Retirement Counters:**
     - `cycle_count`: 32-bit hardware accumulator tracking total active clock cycles.
     - `instr_retired_count`: Accurately counts valid instruction commits at the writeback stage, automatically filtering out pipeline bubbles, flush bubbles, and NOPs.
  2. **Real-Time Efficiency Ratios (Fixed-Point Scaled x1000):**
     $$\text{CPI} \times 1000 = \frac{\text{cycle\_count} \times 1000}{\text{instr\_retired\_count}}$$
     $$\text{IPC} \times 1000 = \frac{\text{instr\_retired\_count} \times 1000}{\text{cycle\_count}}$$
     $$\text{Memory Intensity} = \frac{\text{total\_mem\_access} \times 1000}{\text{instr\_retired\_count}}$$
  3. **Hazard & Bubble Telemetry:**
     - `bubble_count`: Tracks every cycle an architectural bubble is inserted due to memory structural stalls.
     - `structural_stall_count`: Monitors shared memory port collisions.
     - `load_use_hazard_count`: Records RAW data hazard stalls.
     - `branch_flush_count`: Accumulates control hazard squash cycles.
  4. **Cache Hierarchy Metrics:**
     - L1 Instruction & Data Cache hits, misses, and dynamic hit rates ($\text{Hit Rate} = \frac{\text{Hits}}{\text{Hits} + \text{Misses}} \times 1000$).
  5. **Analytical Architectural Speedup Factor:**
     $$\mathcal{S}_{\text{Harvard/VN}} = \frac{T_{\text{Von\_Neumann}}}{T_{\text{Von\_Neumann}} - N_{\text{bubbles}}} \times 1000$$

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

### 7.4 Phase II FPGA Synthesis & Timing Closure Analysis ($F_{max}$)
* **Synthesis Script:** [`synth/run_phase2_synth.tcl`](synth/run_phase2_synth.tcl) (Author: Daniel Tayal)
* **Target Device:** AMD/Xilinx Artix-7 `xc7a35tcpg236-1`
* **Timing Constraint:** Target Clock Frequency = $100.0\text{ MHz}$ ($T_{\text{clk}} = 10.000\text{ ns}$).
* **Batch Execution Command:**
  ```bash
  make synth-phase2
  # or directly:
  vivado -mode batch -source synth/run_phase2_synth.tcl
  ```

#### Comparative Hardware Resource Utilization Matrix (Artix-7 xc7a35t):

| Hardware Subsystem / Module | Slice LUTs | Slice Registers (FFs) | Block RAM (RAMB18E1) | DSP48 Slices | Setup Slack (WNS) | Max Frequency ($F_{\text{max}}$) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Unified Von Neumann Core** (`unified_pipeline_top`) | **842** (4.05%) | **1,128** (2.71%) | **1** (1.00%) | **0** (0.00%) | **+2.418 ns** | **131.89 MHz** |
| **Pipelined Harvard Subsystem** (`pipeline_harvard_top`) | **312** (1.50%) | **384** (0.92%) | **0** (Distributed) | **0** (0.00%) | **+4.120 ns** | **170.07 MHz** |
| **Hardware Telemetry Engine** (`phase2_telemetry`) | **248** (1.19%) | **416** (1.00%) | **0** (Logic) | **0** (0.00%) | **+4.685 ns** | **188.15 MHz** |
| **Available FPGA Budget** | 20,800 | 41,600 | 100 | 90 | Target: 100 MHz | — |

#### Microarchitectural Timing Analysis:
- **Unified Von Neumann Critical Path:** The maximum combinational delay path starts from the register file decode / forwarding stage through the 32-bit ALU adder into the unified memory address port multiplexer ($T_{\text{comb}} = 7.158\text{ ns}$).
- **Timing Closure Result:** With a worst negative slack of $\text{WNS} = +2.418\text{ ns}$, the unified pipelined core achieves comfortable timing closure, yielding a maximum operating frequency of:
  $$F_{\text{max}} = \frac{1}{10.000\text{ ns} - 2.418\text{ ns}} = \frac{1}{7.582\text{ ns}} \approx \mathbf{131.89\text{ MHz}}$$
- **Power Dissipation:** Total on-chip power is estimated at $82\text{ mW}$ ($14\text{ mW}$ dynamic, $68\text{ mW}$ device static), operating at a junction temperature of $25.4^\circ\text{C}$.

---

## 8. Verification Suites & Experimental Benchmarking

### 8.1 Harvard Memory Hierarchy Verification (`tb_harvard_mem.v`)
[`sim/tb_harvard_mem.v`](sim/tb_harvard_mem.v) implements a comprehensive self-checking test suite:
* **Test 1:** Preload verification across multiple ROM addresses (`0x00`, `0x04`, `0x0C`).
* **Test 2:** Data memory full word read/write and 4-bit byte-enable write masking (`0xAABBCC55`).
* **Test 3 (Concurrency):** Simultaneously asserts instruction fetch and data store/load on the identical clock edge, verifying that `simultaneous_access == 1` and that no data corruption occurs.

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
  Total Clock Cycles Elapsed : 10
  Total Instruction Fetches  : 3
  Total Data Accesses (R/W)  : 6
  Simultaneous Dual Accesses : 2
==================================================================
 >>> ALL 3 TESTS PASSED SUCCESSFULLY! <<<
 Harvard Dual-Bus Independence Verified: Zero Contention Stalls.
==================================================================
```

### 8.2 Von Neumann Baseline Verification (`tb_von_neumann.v`)
[`sim/tb_von_neumann.v`](sim/tb_von_neumann.v) validates the bus arbitration FSM and verifies that structural hazard stalls are injected whenever instruction fetch and data read/write collide:

```text
==================================================================
   Von Neumann Subsystem Verification & Arbiter Stall Testbench   
==================================================================
[TEST 1] Verifying Conflict-Free Instruction Fetches...
  [PASS] No stall asserted for instruction-only fetch at 0x00
  [PASS] Bus granted to instruction port (grant_instr = 1)
[TEST 2] Verifying Conflict-Free Data Memory Read/Write...
  [PASS] Word Write/Read verified: 0xDEADBEEF
  [PASS] Byte-enable masking verified: 0xDEADAAEF
[TEST 3] Verifying Bus Contention & Single-Cycle Arbiter Stall...
  [PASS] Stall correctly asserted due to simultaneous I/D collision
  [PASS] Arbiter prioritized data write during collision
  [PASS] Instruction fetch deferred (grant_instr = 0)
  [PASS] Stall de-asserted on next cycle (1 stall cycle resolved)
  [PASS] Instruction fetch 0x10 (SW) completed cleanly
[TEST 4] Verifying Back-to-Back Contention Stress Sequence...
  [PASS] Stress Step 1: Contention stall asserted
  [PASS] Stress Step 2: Stall cleared for fetch
[TEST 5] Validating Hardware Telemetry & Performance Counters...
  [PASS] stall_count matches expected arbitration stalls
  [PASS] contention_count matches injected conflict events
==================================================================
 >>> ALL 5 TESTS PASSED SUCCESSFULLY! (0 errors) <<<
 Arbiter Transitions & Von Neumann Stall Penalty Verified.
==================================================================
```

### 8.3 Head-to-Head Comparative Benchmark (`tb_comparison.v`)
[`sim/tb_comparison.v`](sim/tb_comparison.v) instantiates both the **Harvard** and **Von Neumann** architectures executing the vector accumulation program (`array_sum.mem`) in lockstep:

```text
====================================================================================================
                               AUTOMATED PERFORMANCE SCORE TABLE                                    
                             Harvard Dual-Bus vs. Von Neumann Baseline                              
====================================================================================================
 Architectural Metric             | Harvard Architecture     | Von Neumann Baseline     | Delta / Speedup 
----------------------------------------------------------------------------------------------------
 Total Instructions Retired (N)   | 33                       | 33                       | Identical Trace 
 Total Execution Cycles           | 33                       | 42                       | +9 cycles      
 Single-Port Serialization Cycles | 0                        | 9                        | +9 cycles
 Arbiter Stall Cycles             | 0                        | 0                        | 0 cycles
 Arbiter Contention Events        | 0                        | 0                        | 0 events
 Data Memory Operations (LW/SW)   | 9                        | 9                        | 8 LW + 1 SW     
 Concurrent Dual Access Cycles    | 9                        | 0 (Serialized Port)      | +9 Concurrent   
 Cycles Per Instruction (CPI)     | 1.0000                   | 1.2727                   | -0.2727 CPI     
 Execution Wall Time @ 100MHz     | 330.00 ns                | 420.00 ns                | -90.00 ns       
 Relative Execution Speedup       | 1.2727x                  | 1.0000x (Baseline)       | 1.2727x         
 Execution Time Reduction (%)     | 21.43%                   | 0.00%                    | 21.43% faster   
 Result Integrity (Addr 0x60)     | 36 (0x24) [PASS]         | 36 (0x24) [PASS]         | 0 Corruption    
====================================================================================================
```

The comparison harness services the Von Neumann data operation in a separate cycle, so it records nine single-port serialization cycles but no same-cycle arbiter collisions. The independent arbiter collision and stall behavior is verified in `tb_von_neumann.v`.

### 8.4 Unified Pipelined Core Verification & Telemetry Results (`tb_unified_pipeline.v`)
[`sim/tb_unified_pipeline.v`](sim/tb_unified_pipeline.v) (Author: Daniel Tayal) verifies the Unified Von Neumann Pipelined Core executing the complete Matrix Multiplication workload (`matrix_mult.mem`):

```text
==================================================================================
   Unified Von Neumann Pipelined Baseline Core Verification Testbench             
   Workload: RV32I Matrix Multiplication (benchmarks/matrix_mult.mem)            
   Author  : Daniel Tayal (2401010140)                                            
==================================================================================
[INFO] Reset released at t = 30000. Pipelined execution began.

==================================================================================
                   STEP 1: NUMERICAL RESULT VERIFICATION                          
==================================================================================
  [PASS] C[0][0] at 0x1A0 = 11 (Expected: 11)
  [PASS] C[0][1] at 0x1A4 = 16 (Expected: 16)
  [PASS] C[1][0] at 0x1A8 = 19 (Expected: 19)
  [PASS] C[1][1] at 0x1AC = 28 (Expected: 28)
  [PASS] Scalar Checksum at 0x1B0 = 74 (Expected: 74)

==================================================================================
             STEP 2: STRUCTURAL HAZARD & BUBBLE INJECTION PROOF                   
==================================================================================
  Total Data Load (LW) Transactions   : 20 (Expected: 20)
  Total Data Store (SW) Transactions  : 5 (Expected: 5)
  Aggregate Memory Accesses (LW+SW)   : 25 (Expected: 25)
  Total Structural Collisions Detected: 25
  Total Hardware Bubbles Injected     : 25
  [PASS] Proved: Every LW/SW memory access provoked an exact single-cycle bubble!

==================================================================================
                   STEP 3: HARDWARE TELEMETRY SCORE TABLE                         
==================================================================================
  Architectural Metric               | Von Neumann Value  | Harvard Equiv. (Dual-Bus)
 ------------------------------------+--------------------+---------------------------
  Total Retired Instructions (N)     | 123                | 123                      
  Total Execution Cycles             | 178                | 153                      
  Structural Hazard Bubbles          | 25                 | 0 (Zero Contention Stalls)
  Measured Effective CPI             | 1.447              | 1.243                    
  Realized Harvard Speedup Factor    | 1.000x (Baseline)  | 1.163x (14.04% faster)   
==================================================================================

 >>> ALL VERIFICATION CHECKS PASSED SUCCESSFULLY! (0 errors) <<< 
 Unified Pipelined Core & Structural Bubble Telemetry Fully Verified.
==================================================================================
```

### 8.5 Pipelined Harvard Core & Hazard Verification Suite (`tb_pipeline_harvard.v`)
* **File:** [`sim/tb_pipeline_harvard.v`](sim/tb_pipeline_harvard.v)
* **Author / Owner:** Arun Kumar Giri (`2401010099`) — Role 4 Specialist
* **Verification Scope & Test Plan:**
  - Automated self-checking verification suite executing 10 microarchitectural phases:
    1. **Reset & Register Initialization:** Verifies reset PC alignment (`0x00000000`) and de-assertion of stall controls.
    2. **RAW Distance 1 Hazard Forwarding (EX/MEM -> EX):** Validates back-to-back zero-stall ALU result bypassing (`forward_a = 2'b10`).
    3. **RAW Distance 2 Hazard Forwarding (MEM/WB -> EX):** Validates zero-stall bypassing across 1 intervening instruction (`forward_b = 2'b01`).
    4. **Forwarding Priority Resolution & x0 Invariance:** Proves younger `EX/MEM` producer overrides older `MEM/WB` producer; verifies writes to `x0` never cause forwarding.
    5. **Load-Use Data Hazard Detection:** Verifies exact single-cycle bubble injection on LOAD-to-ALU dependencies (`stall_pc = 1`, `stall_if_id = 1`, `flush_id_ex = 1`).
    6. **Opcode-Aware False Hazard Immunity:** Proves I-type immediate bits in `[24:20]` do NOT trigger spurious stalls.
    7. **Multi-Cycle Cache Miss Pipeline Freeze:** Verifies all 5 stage registers hold state synchronously during cache burst line refills.
    8. **Control Hazard Resolution:** Verifies branch taken squashes speculative `IF/ID` and `ID/EX` stages.
    9. **Full Harvard Pipelined Program Execution:** Executes `benchmarks/array_sum.mem` with dual concurrent memory paths, proving final accumulated sum ($36$ / `0x24`) at memory address `0x60`.
    10. **Harvard Concurrency Telemetry:** Verifies `simultaneous_access_count > 0` and 0 structural stalls incurred across the entire run.

```text
==================================================================================
   Pipelined Harvard Memory Subsystem & Hazard/Forwarding Verification Suite      
   Specialist: Arun Kumar Giri (2401010099) — Role 4                             
   Modules   : rtl/hazard_unit.v, rtl/forwarding_unit.v, rtl/pipeline_core.v      
==================================================================================

[TEST 1] Verifying Reset & Architectural Register Initialization...
  [PASS] Reset PC initialized to 0x00000000 : Actual = 0x00000000 (0)
  [PASS] ext_stall initialized low : Actual = 0x00000000 (0)
  [PASS] stall_fetch initialized low (Harvard split bus) : Actual = 0x00000000 (0)

[TEST 2] Verifying RAW Distance 1 Hazard Forwarding (EX/MEM -> EX)...
  [PASS] forward_a code set to 2'b10 (EX/MEM) : Actual = 0x00000002 (2)
  [PASS] fwd_val_a routed from EX/MEM ALU result : Actual = 0xcafe0001 (3405643777)
  [PASS] forward_b code set to 2'b00 (No hazard on rs2) : Actual = 0x00000000 (0)
  [PASS] fwd_val_b retains original rs2 data : Actual = 0x22222222 (572662306)

[TEST 3] Verifying RAW Distance 2 Hazard Forwarding (MEM/WB -> EX)...
  [PASS] forward_a code set to 2'b00 (No hazard on rs1) : Actual = 0x00000000 (0)
  [PASS] forward_b code set to 2'b01 (MEM/WB) : Actual = 0x00000001 (1)
  [PASS] fwd_val_b routed from MEM/WB writeback data : Actual = 0xdeadbeef (3735928559)

[TEST 4] Verifying Forwarding Priority (EX/MEM over MEM/WB) & x0 Invariance...
  [PASS] forward_a prioritized EX/MEM over MEM/WB (2'b10) : Actual = 0x00000002 (2)
  [PASS] fwd_val_a took younger EX/MEM value : Actual = 0x11112222 (286335522)
  [PASS] forward_a is 2'b00: writes to x0 never cause forwarding : Actual = 0x00000000 (0)

[TEST 5] Verifying Load-Use Hazard Detection & 1-Cycle Bubble Injection...
  [PASS] load_use_hazard asserted on dependent R-type read
  [PASS] stall_pc asserted (Freeze PC)
  [PASS] stall_if_id asserted (Freeze IF/ID)
  [PASS] flush_id_ex asserted (Inject bubble into EX)
  [PASS] stall_id_ex not asserted (EX advances to MEM)

[TEST 6] Verifying Opcode-Aware False Hazard Immunity (Immediate Bits Ignored)...
  [PASS] load_use_hazard is 0 (False hazard correctly suppressed)
  [PASS] stall_pc is 0 (Pipeline runs without unnecessary stall)
  [PASS] flush_id_ex is 0 (No bubble injected)

[TEST 7] Verifying Multi-Cycle Cache Miss Pipeline Freeze...
  [PASS] pipeline_freeze asserted during cache burst refill
  [PASS] stall_pc asserted (PC frozen)
  [PASS] stall_if_id asserted (IF/ID frozen)
  [PASS] stall_id_ex asserted (ID/EX frozen)
  [PASS] stall_ex_mem asserted (EX/MEM frozen)
  [PASS] stall_mem_wb asserted (MEM/WB frozen)
  [PASS] flush_id_ex is 0 (No state wiped during cache freeze)

[TEST 8] Verifying Control Hazard Resolution & Speculative Squashing...
  [PASS] control_hazard asserted on branch taken in EX
  [PASS] flush_if_id asserted (Squash speculative IF/ID)
  [PASS] flush_id_ex asserted (Squash speculative ID/EX)

[TEST 9] Executing Pipelined Harvard Benchmark (benchmarks/array_sum.mem)...
         Preloaded: Dedicated Instruction ROM (0x00..0x2C) & Data RAM (0x40..0x5C)
  [INFO] Core reset released at t = 50000 ps. Pipelined Harvard execution active.
  [PASS] Memory at 0x60 contains final array sum 36 (0x24) : Actual = 0x00000024 (36)

[TEST 10] Validating Harvard Concurrency & Architectural Speedup...
  [PASS] simultaneous_access_count > 0 (Dual-bus concurrency verified)
  [PASS] Executed at least 8 LW and 1 SW transactions

==================================================================================
                   AUTOMATED PERFORMANCE TELEMETRY SCORE TABLE                    
                     Harvard Dual-Bus vs. Von Neumann Baseline                    
==================================================================================
  Architectural Metric               | Harvard Architecture | Von Neumann Baseline
 ------------------------------------+----------------------+---------------------
  Total Dynamic Retired Instructions | 28                   | 28                  
  Total Execution Clock Cycles       | 47                   | 56                  
  Structural Arbitration Stalls      | 0                    | 9                   
  Concurrent Dual Access Cycles      | 9                    | 0                   
  RAW Load-Use Hazard Stalls         | 0                    | 0                   
  Branch Control Squashes            | 6                    | 6                   
  Effective Cycles Per Instr (CPI)   | 1.678                | 2.000
  Relative Harvard Speedup Factor    | 1.191x (Faster)      | 1.000x (Baseline)
==================================================================================

 >>> ALL 10 VERIFICATION TESTS PASSED SUCCESSFULLY! (0 ERRORS) <<< 
 Pipeline Hazards, Forwarding & Harvard Dual-Bus Independence Verified.
 Author: Arun Kumar Giri (2401010099) — Role 4 Specialist Signed Off.
==================================================================================
```

### 8.6 Waveform Inspection Guide
Simulation waveform traces (`.vcd` format) are automatically produced in `sim/` and can be inspected in GTKWave or the VS Code WaveTrace extension:

```bash
# View Pipelined Harvard hazard & forwarding waveform (Role 4):
make wave-pipeline-harvard

# View Harvard dual-bus waveform:
make wave

# View Von Neumann arbiter stall waveform:
make wave-vn

# View Head-to-Head comparative waveform:
make wave-comp

# View Unified Von Neumann pipelined bubble waveform:
make wave-unified
```

---

## 9. Repository Layout & Artifact Manifest

```text
mca_proj/
├── frontend/                       # Local browser dashboard for simulations
│   ├── server.py                   # Loopback-only API and fixed Make target runner
│   ├── index.html                  # Dashboard interface
│   ├── app.css                     # Dashboard styling
│   └── app.js                      # Simulation controls and VCD viewer
├── benchmarks/                     # Test programs (RV32I hex format)
│   ├── sample_prog.mem             # Basic instruction test program
│   ├── array_sum.mem               # Phase I memory contention benchmark
│   ├── matrix_mult.mem             # Phase II dense matrix multiplication benchmark
│   └── generate_matrix_mult.py     # RV32I matrix workload assembler & validator
├── docs/                           # Project documentation & reports
│   └── MCA_report.pdf              # MCA Project Evaluation Report (PDF)
├── rtl/                            # Synthesizable Verilog source files
│   ├── instruction_mem.v           # Dedicated Instruction ROM
│   ├── data_mem.v                  # Dedicated Data RAM with byte masking
│   ├── harvard_top.v               # Harvard top-level hierarchy
│   ├── unified_mem.v               # Shared Von Neumann memory array
│   ├── mem_arbiter.v               # Memory bus arbiter & stall FSM
│   ├── von_neumann_top.v           # Phase I Von Neumann baseline top module
│   ├── mini_core.v                 # Single-cycle RV32I execution core
│   ├── alu.v                       # 32-bit Arithmetic Logic Unit
│   ├── program_counter.v           # Program counter logic
│   ├── pipe_regs.v                 # 4 inter-stage pipeline registers
│   ├── hazard_unit.v               # Pipeline hazard detection & freeze unit (Role 4)
│   ├── forwarding_unit.v           # ALU operand forwarding / bypass unit (Role 4)
│   ├── pipeline_core.v             # 5-stage pipelined RV32I datapath
│   ├── dcache.v                    # L1 direct-mapped data cache with byte masking
│   ├── cache_arbiter.v             # Burst-refill cache bus arbiter
│   ├── unified_pipeline_top.v      # Phase II Unified Von Neumann pipelined core
│   ├── icache.v                    # L1 direct-mapped instruction cache
│   ├── pipeline_harvard_top.v      # Phase II Pipelined Harvard memory top
│   └── phase2_telemetry.v          # 32-bit hardware performance telemetry engine
├── sim/                            # Verification testbenches
│   ├── tb_harvard_mem.v            # Harvard self-checking testbench
│   ├── tb_von_neumann.v            # Von Neumann stall testbench
│   ├── tb_mini_core.v              # Core execution unit testbench
│   ├── tb_comparison.v             # Phase I comparative benchmark testbench
│   ├── tb_icache.v                 # L1 I-Cache verification testbench
│   ├── tb_dcache.v                 # L1 D-Cache & arbiter verification testbench
│   ├── tb_unified_pipeline.v       # Phase II Unified pipelined & telemetry testbench
│   └── tb_pipeline_harvard.v       # Phase II Pipelined Harvard & hazard testbench (Role 4)
├── synth/                          # FPGA synthesis scripts & reports
│   ├── run_synth.tcl               # Phase I Vivado batch synthesis script
│   ├── run_phase2_synth.tcl        # Phase II Vivado Artix-7 batch synthesis script
│   └── reports/                    # Post-synthesis utilization & timing reports
│       ├── utilization_unified_pipeline.rpt
│       ├── timing_unified_pipeline.rpt
│       ├── power_unified_pipeline.rpt
│       ├── utilization_pipeline_harvard.rpt
│       ├── timing_pipeline_harvard.rpt
│       ├── power_pipeline_harvard.rpt
│       ├── utilization_telemetry.rpt
│       ├── timing_telemetry.rpt
│       └── power_telemetry.rpt
├── Makefile                        # Build and simulation automation
├── run.sh                          # Unified simulation runner script
├── LICENSE                         # MIT License
├── .gitignore                      # Git ignore rules
└── README.md                       # Project documentation
```

---

## 10. Installation, Reproduction & Simulation Guide

### Step 1: Environment Setup
Ensure simulation tools are installed:
```bash
# On macOS via Homebrew:
brew install icarus-verilog
brew install --cask gtkwave

# On Ubuntu/Debian:
sudo apt-get install iverilog gtkwave
```

### Step 2: Clone the Repository
```bash
git clone https://github.com/mausam-005/Instruction-and-Data-Memory-Hierarchy.git
cd Instruction-and-Data-Memory-Hierarchy
```

### Step 3: Run the Verification Simulations
You can compile and execute simulations using `make` or the `./run.sh` script:

```bash
# 1. Run Unified Von Neumann Pipelined Core & Matrix Multiplication:
make sim-unified-pipe
# or: ./run.sh unified

# 2. Run Harvard Dual-Bus Verification:
make sim-harvard
# or: ./run.sh harvard

# 3. Run Von Neumann Baseline Verification:
make sim-vn
# or: ./run.sh vn

# 4. Run L1 Instruction Cache Verification:
make sim-icache
# or: ./run.sh icache

# 5. Run Head-to-Head Comparative Benchmark:
make sim-comparison
# or: ./run.sh comp
```

### Optional: Local Browser Dashboard
With Python 3, GNU Make, and Icarus Verilog installed, start the local dashboard:
```bash
python3 frontend/server.py
```
Open `http://127.0.0.1:8765`, select a predefined simulation, and click **Run simulation**. The page shows the split Harvard paths, PC/address-decode/read-write roles, and measured array-sum comparison against the shared-memory baseline. The dashboard displays test output and can render or download the generated VCD waveform. It binds to loopback only and accepts only the repository's fixed simulation targets. Press `Ctrl+C` in the terminal to stop it.

### Step 4: Inspect Waveforms
```bash
# View Unified Von Neumann pipelined bubble waveform:
make wave-unified

# View Harvard waveform:
make wave

# View Von Neumann waveform:
make wave-vn

# View Comparative benchmark waveform:
make wave-comp
```

### Step 5: Run FPGA Synthesis via Xilinx Vivado
```bash
# Run Phase II Artix-7 Synthesis (unified_pipeline_top, pipeline_harvard_top, telemetry):
make synth-phase2
# or directly:
vivado -mode batch -source synth/run_phase2_synth.tcl

# Run Phase I Synthesis:
make synth
```
Post-synthesis resource utilization, power, and timing reports ($F_{\text{max}}$) will be written to `synth/reports/`.

---

## 11. Academic Integrity, References & License

### References
1. **D. A. Patterson and J. L. Hennessy**, *Computer Organization and Design: The Hardware/Software Interface (RISC-V Edition)*, Morgan Kaufmann, 2020.
2. **J. L. Hennessy and D. A. Patterson**, *Computer Architecture: A Quantitative Approach*, 6th ed., Morgan Kaufmann, 2017.
3. **RISC-V International**, *The RISC-V Instruction Set Manual, Volume I: User-Level ISA (Document Version 20191213)*, Dec. 2019.
4. **AMD / Xilinx Inc.**, *7 Series FPGAs Memory Resources User Guide (UG473)*, v1.14, 2021.

### License
This project is open-source hardware licensed under the [MIT License](LICENSE).
