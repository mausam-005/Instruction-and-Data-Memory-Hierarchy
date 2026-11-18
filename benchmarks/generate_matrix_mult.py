#!/usr/bin/env python3
# ==============================================================================
# Script : generate_matrix_mult.py
# Project: Instruction and Data Memory Hierarchy (Phase II)
# Author : Daniel Tayal (2401010140)
# Description:
#   Python-based RV32I assembler and architectural verification simulator for
#   the memory-intensive 2x2 Matrix Multiplication benchmark (matrix_mult.mem).
#
# Workload Overview:
#   - Matrices: A (2x2) and B (2x2), yielding C = A x B (2x2).
#   - Memory Footprint:
#       * Instructions : Byte addresses 0x000 - 0x10C (Word indices 0 to 67)
#       * Matrix A     : Byte addresses 0x180 - 0x18C (Word indices 96 to 99)
#       * Matrix B     : Byte addresses 0x190 - 0x19C (Word indices 100 to 103)
#       * Matrix C     : Byte addresses 0x1A0 - 0x1AC (Word indices 104 to 107)
#       * Checksum     : Byte address   0x1B0         (Word index 108)
#
# Quantitative Workload Profile:
#   - 123 Instructions Retired
#   - 20 Load Word (LW) operations
#   - 5 Store Word (SW) operations
#   - 25 Memory Access Transactions (20.3% memory instruction density)
# ==============================================================================

import sys

def encode_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_i(imm, rs1, funct3, rd, opcode):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def encode_s(imm, rs2, rs1, funct3, opcode):
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_0 << 7) | opcode

def encode_b(imm, rs2, rs1, funct3, opcode):
    imm12 = (imm >> 12) & 0x1
    imm10_5 = (imm >> 5) & 0x3F
    imm4_1 = (imm >> 1) & 0xF
    imm11 = (imm >> 11) & 0x1
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_1 << 8) | (imm11 << 7) | opcode

def encode_j(imm, rd, opcode):
    imm20 = (imm >> 20) & 0x1
    imm10_1 = (imm >> 1) & 0x3FF
    imm11 = (imm >> 11) & 0x1
    imm19_12 = (imm >> 12) & 0xFF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | opcode

def build_benchmark():
    instructions = []
    def add_inst(code, asm):
        pc = len(instructions) * 4
        instructions.append((pc, code, asm))

    # Base pointers setup
    add_inst(encode_i(384, 0, 0, 1, 0x13), 'addi x1, x0, 384    // x1 = 0x180 (Matrix A base pointer)')
    add_inst(encode_i(400, 0, 0, 2, 0x13), 'addi x2, x0, 400    // x2 = 0x190 (Matrix B base pointer)')
    add_inst(encode_i(416, 0, 0, 3, 0x13), 'addi x3, x0, 416    // x3 = 0x1A0 (Matrix C base pointer)')

    # C[0][0] = A[0][0]*B[0][0] + A[0][1]*B[1][0] = 2*1 + 3*3 = 11
    add_inst(encode_i(0, 1, 2, 4, 0x03),   'lw   x4, 0(x1)      // Load A[0][0] = 2')
    add_inst(encode_i(0, 2, 2, 5, 0x03),   'lw   x5, 0(x2)      // Load B[0][0] = 1')
    add_inst(encode_i(0, 0, 0, 7, 0x13),   'addi x7, x0, 0      // C[0][0] acc = 0')
    add_inst(encode_b(16, 5, 0, 0, 0x63),  'beq  x5, x0, 16     // If B_elem == 0 exit mult loop 1')
    add_inst(encode_r(0, 4, 7, 0, 7, 0x33),'add  x7, x7, x4     // acc += A_elem')
    add_inst(encode_i(-1, 5, 0, 5, 0x13),  'addi x5, x5, -1     // B_elem--')
    add_inst(encode_j(-12, 0, 0x6F),       'jal  x0, -12        // Repeat mult loop 1')
    add_inst(encode_i(4, 1, 2, 4, 0x03),   'lw   x4, 4(x1)      // Load A[0][1] = 3')
    add_inst(encode_i(8, 2, 2, 5, 0x03),   'lw   x5, 8(x2)      // Load B[1][0] = 3')
    add_inst(encode_b(16, 5, 0, 0, 0x63),  'beq  x5, x0, 16     // If B_elem == 0 exit mult loop 2')
    add_inst(encode_r(0, 4, 7, 0, 7, 0x33),'add  x7, x7, x4     // acc += A_elem')
    add_inst(encode_i(-1, 5, 0, 5, 0x13),  'addi x5, x5, -1     // B_elem--')
    add_inst(encode_j(-12, 0, 0x6F),       'jal  x0, -12        // Repeat mult loop 2')
    add_inst(encode_s(0, 7, 3, 2, 0x23),   'sw   x7, 0(x3)      // Store C[0][0] = 11 to 0x1A0')

    # C[0][1] = A[0][0]*B[0][1] + A[0][1]*B[1][1] = 2*2 + 3*4 = 16
    add_inst(encode_i(0, 1, 2, 4, 0x03),   'lw   x4, 0(x1)      // Load A[0][0] = 2')
    add_inst(encode_i(4, 2, 2, 5, 0x03),   'lw   x5, 4(x2)      // Load B[0][1] = 2')
    add_inst(encode_i(0, 0, 0, 7, 0x13),   'addi x7, x0, 0      // C[0][1] acc = 0')
    add_inst(encode_b(16, 5, 0, 0, 0x63),  'beq  x5, x0, 16     // If B_elem == 0 exit mult loop 3')
    add_inst(encode_r(0, 4, 7, 0, 7, 0x33),'add  x7, x7, x4     // acc += A_elem')
    add_inst(encode_i(-1, 5, 0, 5, 0x13),  'addi x5, x5, -1     // B_elem--')
    add_inst(encode_j(-12, 0, 0x6F),       'jal  x0, -12        // Repeat mult loop 3')
    add_inst(encode_i(4, 1, 2, 4, 0x03),   'lw   x4, 4(x1)      // Load A[0][1] = 3')
    add_inst(encode_i(12, 2, 2, 5, 0x03),  'lw   x5, 12(x2)     // Load B[1][1] = 4')
    add_inst(encode_b(16, 5, 0, 0, 0x63),  'beq  x5, x0, 16     // If B_elem == 0 exit mult loop 4')
    add_inst(encode_r(0, 4, 7, 0, 7, 0x33),'add  x7, x7, x4     // acc += A_elem')
    add_inst(encode_i(-1, 5, 0, 5, 0x13),  'addi x5, x5, -1     // B_elem--')
    add_inst(encode_j(-12, 0, 0x6F),       'jal  x0, -12        // Repeat mult loop 4')
    add_inst(encode_s(4, 7, 3, 2, 0x23),   'sw   x7, 4(x3)      // Store C[0][1] = 16 to 0x1A4')

    # C[1][0] = A[1][0]*B[0][0] + A[1][1]*B[1][0] = 4*1 + 5*3 = 19
    add_inst(encode_i(8, 1, 2, 4, 0x03),   'lw   x4, 8(x1)      // Load A[1][0] = 4')
    add_inst(encode_i(0, 2, 2, 5, 0x03),   'lw   x5, 0(x2)      // Load B[0][0] = 1')
    add_inst(encode_i(0, 0, 0, 7, 0x13),   'addi x7, x0, 0      // C[1][0] acc = 0')
    add_inst(encode_b(16, 5, 0, 0, 0x63),  'beq  x5, x0, 16     // If B_elem == 0 exit mult loop 5')
    add_inst(encode_r(0, 4, 7, 0, 7, 0x33),'add  x7, x7, x4     // acc += A_elem')
    add_inst(encode_i(-1, 5, 0, 5, 0x13),  'addi x5, x5, -1     // B_elem--')
    add_inst(encode_j(-12, 0, 0x6F),       'jal  x0, -12        // Repeat mult loop 5')
    add_inst(encode_i(12, 1, 2, 4, 0x03),  'lw   x4, 12(x1)     // Load A[1][1] = 5')
    add_inst(encode_i(8, 2, 2, 5, 0x03),   'lw   x5, 8(x2)      // Load B[1][0] = 3')
    add_inst(encode_b(16, 5, 0, 0, 0x63),  'beq  x5, x0, 16     // If B_elem == 0 exit mult loop 6')
    add_inst(encode_r(0, 4, 7, 0, 7, 0x33),'add  x7, x7, x4     // acc += A_elem')
    add_inst(encode_i(-1, 5, 0, 5, 0x13),  'addi x5, x5, -1     // B_elem--')
    add_inst(encode_j(-12, 0, 0x6F),       'jal  x0, -12        // Repeat mult loop 6')
    add_inst(encode_s(8, 7, 3, 2, 0x23),   'sw   x7, 8(x3)      // Store C[1][0] = 19 to 0x1A8')

    # C[1][1] = A[1][0]*B[0][1] + A[1][1]*B[1][1] = 4*2 + 5*4 = 28
    add_inst(encode_i(8, 1, 2, 4, 0x03),   'lw   x4, 8(x1)      // Load A[1][0] = 4')
    add_inst(encode_i(4, 2, 2, 5, 0x03),   'lw   x5, 4(x2)      // Load B[0][1] = 2')
    add_inst(encode_i(0, 0, 0, 7, 0x13),   'addi x7, x0, 0      // C[1][1] acc = 0')
    add_inst(encode_b(16, 5, 0, 0, 0x63),  'beq  x5, x0, 16     // If B_elem == 0 exit mult loop 7')
    add_inst(encode_r(0, 4, 7, 0, 7, 0x33),'add  x7, x7, x4     // acc += A_elem')
    add_inst(encode_i(-1, 5, 0, 5, 0x13),  'addi x5, x5, -1     // B_elem--')
    add_inst(encode_j(-12, 0, 0x6F),       'jal  x0, -12        // Repeat mult loop 7')
    add_inst(encode_i(12, 1, 2, 4, 0x03),  'lw   x4, 12(x1)     // Load A[1][1] = 5')
    add_inst(encode_i(12, 2, 2, 5, 0x03),  'lw   x5, 12(x2)     // Load B[1][1] = 4')
    add_inst(encode_b(16, 5, 0, 0, 0x63),  'beq  x5, x0, 16     // If B_elem == 0 exit mult loop 8')
    add_inst(encode_r(0, 4, 7, 0, 7, 0x33),'add  x7, x7, x4     // acc += A_elem')
    add_inst(encode_i(-1, 5, 0, 5, 0x13),  'addi x5, x5, -1     // B_elem--')
    add_inst(encode_j(-12, 0, 0x6F),       'jal  x0, -12        // Repeat mult loop 8')
    add_inst(encode_s(12, 7, 3, 2, 0x23),  'sw   x7, 12(x3)     // Store C[1][1] = 28 to 0x1AC')

    # Checksum calculation: sum(C) = 11 + 16 + 19 + 28 = 74 (0x4A)
    add_inst(encode_i(0, 3, 2, 4, 0x03),   'lw   x4, 0(x3)      // Read back C[0][0]')
    add_inst(encode_i(4, 3, 2, 5, 0x03),   'lw   x5, 4(x3)      // Read back C[0][1]')
    add_inst(encode_r(0, 5, 4, 0, 11, 0x33),'add x11, x4, x5    // x11 = C[0][0] + C[0][1]')
    add_inst(encode_i(8, 3, 2, 4, 0x03),   'lw   x4, 8(x3)      // Read back C[1][0]')
    add_inst(encode_r(0, 4, 11, 0, 11, 0x33),'add x11, x11, x4  // x11 += C[1][0]')
    add_inst(encode_i(12, 3, 2, 5, 0x03),  'lw   x5, 12(x3)     // Read back C[1][1]')
    add_inst(encode_r(0, 5, 11, 0, 11, 0x33),'add x11, x11, x5  // x11 += C[1][1]')
    add_inst(encode_s(16, 11, 3, 2, 0x23), 'sw   x11, 16(x3)    // Store checksum (74 = 0x4A) to 0x1B0')
    add_inst(encode_j(0, 0, 0x6F),         'jal  x0, 0          // Infinite loop / halt execution')

    return instructions

def simulate(instructions):
    mem = [0] * 256
    # Matrix A at word index 96 (0x60): 2, 3, 4, 5
    mem[96] = 2
    mem[97] = 3
    mem[98] = 4
    mem[99] = 5
    # Matrix B at word index 100 (0x64): 1, 2, 3, 4
    mem[100] = 1
    mem[101] = 2
    mem[102] = 3
    mem[103] = 4

    regs = [0] * 32
    pc = 0
    retired = 0
    lw_count = 0
    sw_count = 0

    halt_pc = instructions[-1][0]
    while pc != halt_pc and retired < 2000:
        inst_idx = pc // 4
        _, code, _ = instructions[inst_idx]
        retired += 1
        regs[0] = 0

        opcode = code & 0x7F
        rd = (code >> 7) & 0x1F
        rs1 = (code >> 15) & 0x1F
        rs2 = (code >> 20) & 0x1F

        if opcode == 0x13:
            imm = (code >> 20)
            if imm & 0x800: imm -= 0x1000
            regs[rd] = (regs[rs1] + imm) & 0xFFFFFFFF
            pc += 4
        elif opcode == 0x33:
            regs[rd] = (regs[rs1] + regs[rs2]) & 0xFFFFFFFF
            pc += 4
        elif opcode == 0x03:
            imm = (code >> 20)
            if imm & 0x800: imm -= 0x1000
            addr = regs[rs1] + imm
            regs[rd] = mem[addr >> 2]
            lw_count += 1
            pc += 4
        elif opcode == 0x23:
            imm = ((code >> 25) << 5) | ((code >> 7) & 0x1F)
            if imm & 0x800: imm -= 0x1000
            addr = regs[rs1] + imm
            mem[addr >> 2] = regs[rs2] & 0xFFFFFFFF
            sw_count += 1
            pc += 4
        elif opcode == 0x63:
            imm = (((code >> 31) & 1) << 12) | (((code >> 7) & 1) << 11) | (((code >> 25) & 0x3F) << 5) | (((code >> 8) & 0xF) << 1)
            if imm & 0x1000: imm -= 0x2000
            if regs[rs1] == regs[rs2]:
                pc += imm
            else:
                pc += 4
        elif opcode == 0x6F:
            imm = (((code >> 31) & 1) << 20) | (((code >> 12) & 0xFF) << 12) | (((code >> 20) & 1) << 11) | (((code >> 21) & 0x3FF) << 1)
            if imm & 0x100000: imm -= 0x200000
            if rd != 0: regs[rd] = pc + 4
            pc += imm

    return {
        'retired': retired,
        'lw_count': lw_count,
        'sw_count': sw_count,
        'mem_ops': lw_count + sw_count,
        'c00': mem[104],
        'c01': mem[105],
        'c10': mem[106],
        'c11': mem[107],
        'checksum': mem[108]
    }

if __name__ == '__main__':
    insts = build_benchmark()
    res = simulate(insts)
    print("=" * 60)
    print(" RV32I Matrix Multiplication Benchmark Architectural Profile")
    print("=" * 60)
    print(f"  Instructions Retired     : {res['retired']}")
    print(f"  Loads (LW)               : {res['lw_count']}")
    print(f"  Stores (SW)              : {res['sw_count']}")
    print(f"  Total Memory Operations  : {res['mem_ops']}")
    print(f"  Memory Instruction Ratio : {res['mem_ops']/res['retired']*100:.2f}%")
    print("-" * 60)
    print(f"  Matrix C[0][0] @ 0x1A0   : {res['c00']} (Expected: 11)")
    print(f"  Matrix C[0][1] @ 0x1A4   : {res['c01']} (Expected: 16)")
    print(f"  Matrix C[1][0] @ 0x1A8   : {res['c10']} (Expected: 19)")
    print(f"  Matrix C[1][1] @ 0x1AC   : {res['c11']} (Expected: 28)")
    print(f"  Final Checksum @ 0x1B0   : {res['checksum']} (Expected: 74)")
    print("=" * 60)
