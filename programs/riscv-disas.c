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

#include "riscv-disas.h"

#define NULL 0

uint32_t syscall(uint32_t addr, uint32_t arg);

void cout(char c) {
	const uint32_t couta = 0xfded;
	syscall(couta, (uint32_t)c);
}

char rdkey() {
	const uint32_t rdkeya = 0xfd0c;
	return (char)syscall(rdkeya, 0);
}

char getc() {
	char c = rdkey();
	cout(c);
	return c & 0x7f;
}

void putc(char c) {
	cout(c | 0x80);
}

void puts(const char* s) {
	for (int i = 0; s[i] != '\0'; i++) {
		putc(s[i]);
	}
}

void putint(int n) {
	char buf[10]; // max 32-bit int is 10 decimal digits
	if (n < 0) {
		putc('-');
	}
	int i = 0;
	do {
		int d = n % 10;
		buf[i++] = '0' + (n % 10);
		n = n / 10;
	} while (n > 0);
	while (i > 0) {
		putc(buf[--i]);
	}
}

typedef struct {
    const char * const name;
    const rv_codec codec;
    const char * const format;
} rv_opcode_data;

/* instruction formats */

static const char rv_fmt_none[]                   = "";
static const char rv_fmt_rs1[]                    = "1";
static const char rv_fmt_offset[]                 = "o";
static const char rv_fmt_rs1_rs2[]                = "1,2";
static const char rv_fmt_rd_imm[]                 = "0,i";
static const char rv_fmt_rd_offset[]              = "0,o";
static const char rv_fmt_rd_rs1_rs2[]             = "0,1,2";
static const char rv_fmt_rd_rs1_imm[]             = "0,1,i";
static const char rv_fmt_rd_rs1_offset[]          = "0,1,i";
static const char rv_fmt_rd_offset_rs1[]          = "0,i(1)";
static const char rv_fmt_rs2_offset_rs1[]         = "2,i(1)";
static const char rv_fmt_rs1_rs2_offset[]         = "1,2,o";
static const char rv_fmt_rs2_rs1_offset[]         = "2,1,o";
static const char rv_fmt_rd[]                     = "0";
static const char rv_fmt_rd_rs1[]                 = "0,1";
static const char rv_fmt_rd_rs2[]                 = "0,2";
static const char rv_fmt_rs1_offset[]             = "1,o";
static const char rv_fmt_rs2_offset[]             = "2,o";

/* instruction metadata */

const rv_opcode_data opcode_data[] = {
    { "illegal", rv_codec_illegal, rv_fmt_none },

    { "add", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "addi", rv_codec_i, rv_fmt_rd_rs1_imm },
    { "and", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "andi", rv_codec_i, rv_fmt_rd_rs1_imm },
    { "auipc", rv_codec_u, rv_fmt_rd_offset },
	{ "beq", rv_codec_sb, rv_fmt_rs1_rs2_offset },
    { "bge", rv_codec_sb, rv_fmt_rs1_rs2_offset },
    { "bgeu", rv_codec_sb, rv_fmt_rs1_rs2_offset },
    { "blt", rv_codec_sb, rv_fmt_rs1_rs2_offset },
    { "bltu", rv_codec_sb, rv_fmt_rs1_rs2_offset },
    { "bne", rv_codec_sb, rv_fmt_rs1_rs2_offset },
    { "ebreak", rv_codec_none, rv_fmt_none },
    { "ecall", rv_codec_none, rv_fmt_none },
    { "fence", rv_codec_r_f, rv_fmt_none },
    { "fence.i", rv_codec_none, rv_fmt_none },
    { "jal", rv_codec_uj, rv_fmt_rd_offset },
    { "jalr", rv_codec_i, rv_fmt_rd_rs1_offset },
    { "lb", rv_codec_i, rv_fmt_rd_offset_rs1 },
    { "lbu", rv_codec_i, rv_fmt_rd_offset_rs1 },
    { "lh", rv_codec_i, rv_fmt_rd_offset_rs1 },
    { "lhu", rv_codec_i, rv_fmt_rd_offset_rs1 },
    { "lui", rv_codec_u, rv_fmt_rd_imm },
    { "lw", rv_codec_i, rv_fmt_rd_offset_rs1 },
    { "lwu", rv_codec_i, rv_fmt_rd_offset_rs1 },
    { "or", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "ori", rv_codec_i, rv_fmt_rd_rs1_imm },
    { "sb", rv_codec_s, rv_fmt_rs2_offset_rs1 },
    { "sh", rv_codec_s, rv_fmt_rs2_offset_rs1 },
    { "sll", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "slli", rv_codec_i_sh7, rv_fmt_rd_rs1_imm },
    { "slt", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "slti", rv_codec_i, rv_fmt_rd_rs1_imm },
    { "sltiu", rv_codec_i, rv_fmt_rd_rs1_imm },
    { "sltu", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "sra", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "srai", rv_codec_i_sh7, rv_fmt_rd_rs1_imm },
    { "srl", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "srli", rv_codec_i_sh7, rv_fmt_rd_rs1_imm },
    { "sub", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "sw", rv_codec_s, rv_fmt_rs2_offset_rs1 },
    { "xor", rv_codec_r, rv_fmt_rd_rs1_rs2 },
    { "xori", rv_codec_i, rv_fmt_rd_rs1_imm },
};

/* decode opcode */

static rv_opcode decode_inst_opcode(rv_inst inst)
{
    rv_opcode op = rv_op_illegal;
	if (((inst >> 0) & 0x3) != 3) {
		return op;
	}

	switch (((inst >> 2) & 0x1f)) {
	case 0:
		switch (((inst >> 12) & 0x7)) {
		case 0: op = rv_op_lb; break;
		case 1: op = rv_op_lh; break;
		case 2: op = rv_op_lw; break;
		case 4: op = rv_op_lbu; break;
		case 5: op = rv_op_lhu; break;
		case 6: op = rv_op_lwu; break;
		}
		break;
	case 3:
		switch (((inst >> 12) & 0x7)) {
		case 0: op = rv_op_fence; break;
		case 1: op = rv_op_fence_i; break;
		}
		break;
	case 4:
		switch (((inst >> 12) & 0x7)) {
		case 0: op = rv_op_addi; break;
		case 1:
			switch (((inst >> 27) & 0x1f)) {
			case 0: op = rv_op_slli; break;
			}
			break;
		case 2: op = rv_op_slti; break;
		case 3: op = rv_op_sltiu; break;
		case 4: op = rv_op_xori; break;
		case 5:
			switch (((inst >> 27) & 0x1f)) {
			case 0: op = rv_op_srli; break;
			case 8: op = rv_op_srai; break;
			}
			break;
		case 6: op = rv_op_ori; break;
		case 7: op = rv_op_andi; break;
		}
		break;
	case 5: op = rv_op_auipc; break;
	case 8:
		switch (((inst >> 12) & 0x7)) {
		case 0: op = rv_op_sb; break;
		case 1: op = rv_op_sh; break;
		case 2: op = rv_op_sw; break;
		}
		break;
	case 12:
		switch (((inst >> 22) & 0b1111111000) | ((inst >> 12) & 0b0000000111)) {
		case 0: op = rv_op_add; break;
		case 1: op = rv_op_sll; break;
		case 2: op = rv_op_slt; break;
		case 3: op = rv_op_sltu; break;
		case 4: op = rv_op_xor; break;
		case 5: op = rv_op_srl; break;
		case 6: op = rv_op_or; break;
		case 7: op = rv_op_and; break;
		case 256: op = rv_op_sub; break;
		case 261: op = rv_op_sra; break;
		}
		break;
	case 13: op = rv_op_lui; break;
	case 24:
		switch (((inst >> 12) & 0x7)) {
		case 0: op = rv_op_beq; break;
		case 1: op = rv_op_bne; break;
		case 4: op = rv_op_blt; break;
		case 5: op = rv_op_bge; break;
		case 6: op = rv_op_bltu; break;
		case 7: op = rv_op_bgeu; break;
		}
		break;
	case 25:
		switch (((inst >> 12) & 0x7)) {
		case 0: op = rv_op_jalr; break;
		}
		break;
	case 27: op = rv_op_jal; break;
	case 28:
		switch (((inst >> 12) & 0x7)) {
		case 0:
			switch (((inst >> 20) & 0xfe0) | ((inst >> 7) & 0x1f)) {
			case 0:
				switch (((inst >> 15) & 0x3ff)) {
				case 0: op = rv_op_ecall; break;
				case 32: op = rv_op_ebreak; break;
				}
				break;
			}
			break;
		}
		break;
	}

	return op;
}

/* operand extractors */

static inline uint8_t operand_rd(rv_inst inst) {
    return (uint8_t)((inst << 20) >> 27);
}

static inline uint8_t operand_rs1(rv_inst inst) {
    return (uint8_t)((inst << 12) >> 27);
}

static inline uint8_t operand_rs2(rv_inst inst) {
    return (uint8_t)((inst << 7) >> 27);
}

static uint32_t operand_shamt7(rv_inst inst) {
    return (inst << 5) >> 25;
}

static int32_t operand_imm12(rv_inst inst) {
    return (int32_t)inst >> 20;
}

static int32_t operand_imm20(rv_inst inst) {
	return (int32_t)inst & 0xfffff000;
}

static int32_t operand_jimm20(rv_inst inst) {
    return ((int32_t)inst >> 31) << 20 |
        ((inst << 1) >> 22) << 1 |
        ((inst << 11) >> 31) << 11 |
        ((inst << 12) >> 24) << 12;
}

static int32_t operand_simm12(rv_inst inst) {
    return ((int32_t)inst >> 25) << 5 |
        (inst << 20) >> 27;
}

static int32_t operand_sbimm12(rv_inst inst) {
    return ((int32_t)inst >> 31) << 12 |
        ((inst << 1) >> 26) << 5 |
        ((inst << 20) >> 28) << 1 |
        ((inst << 24) >> 31) << 11;
}

/* decode operands */

static void decode_inst_operands(rv_decode *dec)
{
    rv_inst inst = dec->inst;
	dec->rd = operand_rd(inst);
	dec->rs1 = operand_rs1(inst);
	dec->rs2 = operand_rs2(inst);

    switch (opcode_data[dec->op].codec) {
    case rv_codec_u:
        dec->imm = operand_imm20(inst);
        break;
    case rv_codec_uj:
        dec->imm = operand_jimm20(inst);
        break;
    case rv_codec_i:
        dec->imm = operand_imm12(inst);
        break;
    case rv_codec_i_sh7:
        dec->imm = operand_shamt7(inst);
        break;
    case rv_codec_s:
        dec->imm = operand_simm12(inst);
        break;
    case rv_codec_sb:
        dec->imm = operand_sbimm12(inst);
        break;
    };
}

void puthex8(uint32_t n) {
	static const char *hex = "0123456789abcdef";

	char buf[8];
	int i = 0;
	for (; n != 0; n = n >> 4) {
		buf[i++] = hex[n & 0xf];
	}
	for (int j = 8; j > i; j--) {
		putc('0');
	}
	while (i > 0) {
		putc(buf[--i]);
	}
}

static void print_inst(rv_decode *dec)
{
    const char *fmt;

	puthex8(dec->inst);
	putc(' ');
	puts(opcode_data[dec->op].name);
	putc(' ');

    fmt = opcode_data[dec->op].format;
    while (*fmt) {
        switch (*fmt) {
        case '0':
			putc('x');
			putint(dec->rd);
            break;
        case '1':
			putc('x');
			putint(dec->rs1);
            break;
        case '2':
			putc('x');
			putint(dec->rs2);
            break;
        case 'i':
			putint(dec->imm);
            break;
        case 'o':
			putint(dec->imm);
			puts(" # 0x");
			puthex8(dec->pc + dec->imm);
            break;
        default:
			putc(*fmt);
            break;
        }
        fmt++;
    }
	putc('\r');
}

/* disassemble instruction */

void disasm_inst(uint32_t pc, rv_inst inst)
{
    rv_decode dec = { 0 };
    dec.pc = pc;
    dec.inst = inst;
    dec.op = decode_inst_opcode(inst);
    decode_inst_operands(&dec);
	print_inst(&dec);
}

int main() {
	char buf[33];
	uint16_t addr;

	for (;;) {
	next:
		puts("? ");

		for (int i = 0; ; i++) {
			if (i == sizeof(buf)-1) {
				puts("\rinput too long; try again\r");
				goto next;
			}

			char c = getc();
			if (c == '\r') {
				buf[i] = '\0';
				break;
			}
			buf[i] = c;
		}

		if (buf[0] != '\0') {
			// parse an address
			uint16_t naddr = 0;

			int i = 0;
			for (i = 0; i < 4; i++) {
				uint8_t d;

				char c = buf[i];
				if (c == 'Q') {
					return 0;
				} else if (c >= 'A' && c <= 'F') {
					d = c - 'A' + 10;
				} else if (c >= 'a' && c <= 'f') {
					d = c - 'a' + 10;
				} else if (c >= '0' && c <= '9') {
					d = c - '0';
				} else {
					puts("invalid address\r");
					goto next;
				}

				naddr = (naddr << 4) | d;
			}

			if (buf[i] != '\0') {
				puts("syntax error\r");
				goto next;
			}

			addr = naddr;
		}

		for (int i = 0; i < 24; i++) {
			disasm_inst((uint32_t)addr, *(uint32_t*)(uint32_t)addr);
			addr += 4;
			if (addr == 0) {
				break;
			}
		}
	}
}
