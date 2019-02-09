/*
 * RISC-V Disassembler
 *
 * Copyright (c) 2016-2017 Michael Clark <michaeljclark@mac.com>
 * Copyright (c) 2017-2018 SiFive, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#ifndef RISCV_DISASSEMBLER_H
#define RISCV_DISASSEMBLER_H

#include <inttypes.h>

/* types */

typedef uint32_t rv_inst;
typedef uint8_t rv_opcode;

/* enums */

typedef enum {
    rv_ireg_zero,
    rv_ireg_ra,
    rv_ireg_sp,
    rv_ireg_gp,
    rv_ireg_tp,
    rv_ireg_t0,
    rv_ireg_t1,
    rv_ireg_t2,
    rv_ireg_s0,
    rv_ireg_s1,
    rv_ireg_a0,
    rv_ireg_a1,
    rv_ireg_a2,
    rv_ireg_a3,
    rv_ireg_a4,
    rv_ireg_a5,
    rv_ireg_a6,
    rv_ireg_a7,
    rv_ireg_s2,
    rv_ireg_s3,
    rv_ireg_s4,
    rv_ireg_s5,
    rv_ireg_s6,
    rv_ireg_s7,
    rv_ireg_s8,
    rv_ireg_s9,
    rv_ireg_s10,
    rv_ireg_s11,
    rv_ireg_t3,
    rv_ireg_t4,
    rv_ireg_t5,
    rv_ireg_t6,
} rv_ireg;

typedef enum {
    rv_codec_illegal,
    rv_codec_none,
    rv_codec_u,
    rv_codec_uj,
    rv_codec_i,
    rv_codec_i_sh7,
    rv_codec_s,
    rv_codec_sb,
    rv_codec_r,
    rv_codec_r_f,
} rv_codec;

typedef enum {
	rv_op_illegal = 0,

	rv_op_add = 1,
	rv_op_addi = 2,
	rv_op_and = 3,
	rv_op_andi = 4,
	rv_op_auipc = 5,
	rv_op_beq = 6,
	rv_op_bge = 7,
	rv_op_bgeu = 8,
	rv_op_blt = 9,
	rv_op_bltu = 10,
	rv_op_bne = 11,
	rv_op_ebreak = 12,
	rv_op_ecall = 13,
	rv_op_fence = 14,
	rv_op_fence_i = 15,
	rv_op_jal = 16,
	rv_op_jalr = 17,
	rv_op_lb = 18,
	rv_op_lbu = 19,
	rv_op_lh = 20,
	rv_op_lhu = 21,
	rv_op_lui = 22,
	rv_op_lw = 23,
	rv_op_lwu = 24,
	rv_op_or = 25,
	rv_op_ori = 26,
	rv_op_sb = 27,
	rv_op_sh = 28,
	rv_op_sll = 29,
	rv_op_slli = 30,
	rv_op_slt = 31,
	rv_op_slti = 32,
	rv_op_sltiu = 33,
	rv_op_sltu = 34,
	rv_op_sra = 35,
	rv_op_srai = 36,
	rv_op_srl = 37,
	rv_op_srli = 38,
	rv_op_sub = 39,
	rv_op_sw = 40,
	rv_op_xor = 41,
	rv_op_xori = 42,
} rv_op;

/* structures */

typedef struct {
    uint32_t  pc;
    uint32_t  inst;
    int32_t   imm;
    uint8_t   op;
    uint8_t   rd;
    uint8_t   rs1;
    uint8_t   rs2;
} rv_decode;

/* functions */

//void disasm_inst(uint32_t pc, rv_inst inst);

#endif
