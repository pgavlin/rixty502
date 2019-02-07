.equ STACK_TOP, 0xc000

.section .text
.globl _start
_start:
		li sp, STACK_TOP
		mv s0, sp
        jal ra, main
       .int 0x00000004 # invalid opcode to halt

.globl syscall
syscall:
		ecall
		ret

.globl setjmp
setjmp:
	sw ra, 0(a0)
	sw s0, 4(a0)
	sw s1, 8(a0)
	sw s2, 12(a0)
	sw s3, 16(a0)
	sw s4, 20(a0)
	sw s5, 24(a0)
	sw s6, 28(a0)
	sw s7, 32(a0)
	sw s8, 36(a0)
	sw s9, 40(a0)
	sw s10, 44(a0)
	sw s11, 48(a0)
	sw sp, 52(a0)
	li a0, 0
	ret

.globl longjmp
longjmp:
	lw ra, 0(a0)
	lw s0, 4(a0)
	lw s1, 8(a0)
	lw s2, 12(a0)
	lw s3, 16(a0)
	lw s4, 20(a0)
	lw s5, 24(a0)
	lw s6, 28(a0)
	lw s7, 32(a0)
	lw s8, 36(a0)
	lw s9, 40(a0)
	lw s10, 44(a0)
	lw s11, 48(a0)
	lw sp, 52(a0)
	seqz a0, a1
	add a0, a0, a1  # a0 = (a1 == 0) ? 1 : a1
	ret
