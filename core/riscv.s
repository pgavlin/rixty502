	; rixty502: a RISCV interpreter for the 65C02
	;
	; Currently operates at roughly 200 6502 cycles per RISCV instruction. This works out to ~5000 instructions per
	; second on an Apple //c.
	;
	; Reference will be made throughout to the RISC-V Instruction Set Manual Volume I, Version 2.2.

	; The virtual processor's private state and temporary registers are stored in the low 20 bytes of the zero page.
	; This includes the virtual program counter, instruction decoding registers, ALU registers, and control registers.
	; The user-accessible registers are stored in the upper 128 bytes of the zero page. All multi-byte values are
	; stored in little-endian format. The virtual processor shares an address space with the actual processor.

	vpc = $00 ; The virtual program counter holds the address of the currently executing RISCV instruction.
	vin = $04 ; The virtual instruction register holds the currently executing RISCV instruction.
	vf3 = $08 ; vf3 corresponds to the `funct3` field of the RISCV R-, I-, and S-type instruction formats.
	vs1 = $0c ; vs1 operates as the first operand and 4-byte accumulator for many internal ALU operations.
	vs2 = $10 ; vs2 operates as the second operand for many internal ALU operations.

	; vx0-vx31 correspond to the user-visible RISCV registers x0-x1. The simulator initializes x0 to 0 upon startup
	; and ensures that simulated instructions never write to it.
	;
	; The virtual register file is organized into four planes. Each plane contains the nth byte of every virtual
	; register: plane 0 contains each register's first byte, plane 1 the second, and so on. This allows the register
	; file to be indexed without extra shifting. For example, if we are accessing register x5, we need to access the
	; bytes at addresses $80+5, $a0+5, $c0+5, and $e0+5. If the register file was organized as an array of four-byte
	; values, accessing the same register would require accessing the bytes at $80+5*4+0, $80+5*4+1, $80+5*4+2, and
	; $80+5*4+3. This requires two more shifts when calculating the base address than the plane-oriented approach.
	vx0 = $80
	vx1 = $81
	vx2 = $82
	vx3 = $83
	vx4 = $84
	vx5 = $85
	vx6 = $86
	vx7 = $87
	vx8 = $88
	vx9 = $89
	vx10 = $8a
	vx11 = $8b
	vx12 = $8c
	vx13 = $8d
	vx14 = $8e
	vx15 = $8f
	vx16 = $90
	vx17 = $91
	vx18 = $92
	vx19 = $93
	vx20 = $94
	vx21 = $95
	vx22 = $96
	vx23 = $97
	vx24 = $98
	vx25 = $99
	vx26 = $9a
	vx27 = $9b
	vx28 = $9c
	vx29 = $9d
	vx30 = $9e
	vx31 = $9f

	; ldard loads the value of the rd field of the R-, I-, and U-type instruction formats into A. It expects the
	; instruction to decode in vin. The result is suitable for indexing into the virtual registers starting at vx0.
	; The Z flag is set if rd refers to x0.
	;
	; rd occupies bits 7-11 of an R-, I-, or U-type instruction. Bits 0-7 and 8-15 of the instruction to decode are
	; stored at vin and vin+1, respectively. Visually:
	; 
	;     | 15 14 13 12 11 10  9  8 |  7  6  5  4  3  2  1  0 |
	;     +-------------------------+-------------------------+
	;     |  x  x  x  x [      rd      ]  x  x  x  x  x  x  x |
	;     +-------------------------+-------------------------|
	;     | [        vin+1        ] | [         vin         ] |
	;
	; It is clear from this diagram that we want bit 7 of vin in bit 0 of the result and the low nibble of vin+1 in
	; bits 1-4 of the result. We can achieve this by shifting vin left 1 bit to put its MSb into C, rotating vin+1 left
	; by one, and masking the result. We will then multiply the result by four in order to make the result suitable for
	; indexing into the virtual register set.
.macro ldard
	lda vin
	asl
	lda vin+1
	and #$0f
	rol
.endmacro

	; ldars1 loads the value of the rs1 field of the R-, I-, and U-type instruction formats into A. It expects the
	; instruction to decode in vin. The result is suitable for indexing into the virtual registers starting at vx0.
	;
	; This macro uses the same technique as ldard, but on bytes 2 and 1 of vin: like rd, the rs1 field occupies the
	; high bit and low four bits of two adjacent bytes.
.macro ldars1
	lda vin+1 
	asl
	lda vin+2
	and #$0f
	rol
.endmacro

	; ldars2 loads the value of the rs2 field of the R-, I-, and U-type instruction formats into A. It expects the
	; instruction to decode in vin. The result is suitable for indexing into the virtual registers starting at vx0.
	;
	; rs2 occupies bits 20-24 of an R-, I-, or U-type instruction. Bits 15-23 and 24-31 of the instruction to decode
	; are stored at vin+2 and vin+3, repsectively. Visually:
	;
	;     | 31 30 29 28 27 26 25 24 | 23 22 21 20 19 18 17 16 |
	;     +-------------------------+-------------------------+
	;     |  x  x  x  x  x  x  x [      rs2     ]  x  x  x  x |
	;     +-------------------------+-------------------------|
	;     | [        vin+3        ] | [        vin+2        ] |
	;
	; It is clear from the diagram that the raw value of rs2 would put bit 0 of vin+3 in bit 4 of the result and the
	; high nibble of vin+2 in the low nibble of the result. However, we are computing rs2*4 so that the result can be
	; used to index into the virtual registers. What we actually want is this:
	;
	;     |  7  6  5  4  3  2  1  0 |
	;     +-------------------------+
	;     |  0 [     rs2    ]  0  0 |
	;
	; Fortunately, it is faster to compute this value than it is the raw value of rs2. This value requires bit 0 of
	; vin+3 in bit 6 of the result and bits 4-7 of vin+2 in bits 2-5 of the result. We can achieve this by shifting
	; vin+3 right one to put its LSb into C, masking off the low nibble of vin+2, and rotating the result right twice.
.macro ldars2
	lda vin+3
	lsr
	lda vin+2
	ror
	lsr
	lsr
	lsr
.endmacro

	; aluop performs a four-byte ALU operation using the given ALU opcode. Source 1 for the ALU operation is the
	; virtual register at the offset in Y. source 2 is the internal register vs2, and the destination is the virtual
	; register at the offset in X. In C pseudocode, the operation is
	;
	;     *((uint32_t*)&vx0[X]) = *((uint32_t*)&vx0[Y]) opc vs2
	;
	; The offsets in X and Y are byte offsets, so the virtual register number must be prescaled by four. The results of
	; ldard, ldars1, and ldars2 are suitable for use as inputs to this macro.
.macro aluop opc
	lda vx0,y
	opc vs2
	sta vx0,x
	lda vx0+32,y
	opc vs2+1
	sta vx0+32,x
	lda vx0+64,y
	opc vs2+2
	sta vx0+64,x
	lda vx0+96,y
	opc vs2+3
	sta vx0+96,x
.endmacro

.segment "CODE"
	; start is the entrypoint for the simulator. It is responsible for initializing the simulator's state and running
	; to the target program.
.proc start
	; Initialize the two 256-byte shift tables, lsr4 and asr4. The former shifts its index right by four bits; the
	; latter shifts its index left by four bits.
	ldx #0
tl:	txa
	lsr
	lsr
	lsr
	lsr
	sta lsr4,x
	txa
	asl
	asl
	asl
	asl
	sta asl4,x
	dex
	bne tl

	; Set vx0 to 0. RISC-V requires that the x0 register is always 0; the simulator implements this by initializing its
	; virtual registers to 0 and ensuring that it is never written.
	lda #0
	sta vx0
	sta vx0+32
	sta vx0+64
	sta vx0+96

	; Load the reset vector into the PC and go.
	.import program
	lda #<program
	sta vpc
	lda #>program
	sta vpc+1
	jsr run
	brk
.endproc
.export start

	; The following section contains the implementation of the various ALU operations required by the RISC-V
	; specification. These operations expect the offset of their first operand in Y, the value of their second operand
	; in vs2, and the offset of their destination register in X. The first operand may be a virtual register or vs1.
	; The ALU operations themselves are preceded by two helpers, shift and cltkernel, that are used in the implementation
	; of various instructions.

	; shift implements the shift loop. It expects the offset from the shiftzero symbol to the shift kernel in A, the
	; offset of the register that contains the value to shift in Y, the shift amount in vs2, and the offset of the
	; destination register in X.
.proc shift
	; Store the offset into the target.
	sta tg

	; Copy the value to be shifted into vs1. We do this first to free up the Y register.
	lda vx0,y
	sta vs1
	lda vx0+32,y
	sta vs1+1
	lda vx0+64,y
	sta vs1+2
	lda vx0+96,y
	sta vs1+3

	; Load the shift amount from vs2 and mask off its upper 27 bits. If the result is zero, simply copy vs1 to the
	; destination.
	lda vs2
	and #$1f
	beq zero

	; Load the shift amount into Y, decrement it by 1, and branch to the shift kernel.
	tay
	dey

	; These two bytes are "bpl tg". The target is overwritten at the beginning of this procedure to save on code size.
	.byte $10
tg:	.byte $00

	; For a zero-width shift, simply copy the input to the output.
zero:
	lda vs1
	sta vx0,x
	lda vs1+1
	sta vx0+32,x
	lda vs1+2
	sta vx0+64,x
	lda vs1+3
	sta vx0+96,x
	jmp addpc4

	; sll is the shift kernel for an sll instruction. On entry to the kernel, vs1 contains the value to be
	; shifted, Y contains the shift amount minus 1, and X contains the offset of the destination register.
	; The shift count is predecremented so that the value to shift can be shifted left one as it is copied into the
	; destination, which is slightly faster than the RMW operators used by the shift loop.
sll:
	beq slldone
sllloop:
	asl vs1
	rol vs1+1
	rol vs1+2
	rol vs1+3
	dey
	bne sllloop
slldone:
	lda vs1
	asl
	sta vx0,x
	lda vs1+1
	rol
	sta vx0+32,x
	lda vs1+2
	rol
	sta vx0+64,x
	lda vs1+3
	rol
	sta vx0+96,x
	jmp addpc4

	; sra is the shift kernel for an sra instruction. The contract is the same as that of the other kernels; see
	; the documentation of sll for more information.
sra:
	beq sradone
	lda vs1+3
sraloop:
	cmp #$80 ; Put the high-order bit of vs1 into C.
	ror vs1+3
	ror vs1+2
	ror vs1+1
	ror vs1
	dey
	bne sraloop
sradone:
	lda vs1+3
	cmp #$80
	ror
	sta vx0+96,x
	lda vs1+2
	ror
	sta vx0+64,x
	lda vs1+1
	ror
	sta vx0+32,x
	lda vs1
	ror
	sta vx0,x
	jmp addpc4

	; srl is the shift kernel for an srl instruction. The contract is the same as that of the other kernels; see
	; the documentation of sll for more information.
srl:
	beq srldone
srlloop:
	lsr vs1+3
	ror vs1+2
	ror vs1+1
	ror vs1
	dey
	bne srlloop
srldone:
	lda vs1+3
	lsr
	sta vx0+96,x
	lda vs1+2
	ror
	sta vx0+64,x
	lda vs1+1
	ror
	sta vx0+32,x
	lda vs1
	ror
	sta vx0,x
	jmp addpc4
.endproc

	; cltkernel is a shared kernel that computes vx[Y] - vs2 and sets the status flags accordingly. This is used by the
	; implementation of the slt and sltu instructions.
.proc cltkernel
	sec
	lda vx0,y
	sbc vs2
	lda vx0+32,y
	sbc vs2+1
	lda vx0+64,y
	sbc vs2+2
	lda vx0+96,y
	sbc vs2+3
	rts
.endproc

	; aluaddsub implements the addi, add, and sub instructions. The operation performed is indicated by the values of
	; bits 5 and 30 of the executing instruction. If the bit 5 is clear, the instruction is an addi. If bit 5 is set
	; and bit 30 is clear, the instruction is an add. Otherwise, it is a sub.
.proc aluaddsub
	tax
	lda #$60
	bit vin
	bne cksub
	aluop adc  ; carry is clear from the ALU dispatcher
	jmp addpc4
cksub:
	bit vin+3
	bne sub
	aluop adc  ; carry is clear from the ALU dispatcher
	jmp addpc4
sub:
	sec
	aluop sbc
	jmp addpc4
.endproc

	; alusll implements the sll instruction. Essentially all of the work is done by the shift helper.
.proc alusll
	tax
	lda #shift::sll-shift::zero
	jmp shift
.endproc

	; alusltu implements the sltu and sltui instructions. The result is computed by subtracting the second operand
	; (vs2) from the first (vx[Y]) and comparing the value of overflow flag against that of the sign flag. If the two
	; match, then the first operand is greater than or equal to the second. Otherwise, the first operand is less than
	; the second.
.proc alusltu
	tax
	jsr cltkernel
	lda #0
	rol
	eor #1
setrd:
	sta vx0,x
	lsr
	sta vx0+32,x
	sta vx0+64,x
	sta vx0+96,x
	jmp addpc4
.endproc

	; aluslt implements the slt and slti instructions. The result is computed by subtracting the second operand (vs2)
	; from the first (vx[Y]) and comparing the value of overflow flag against that of the sign flag. If the two match,
	; then the first operand is greater than or equal to the second. Otherwise, the first operand is less than the
	; second.
.proc aluslt
	tax
	jsr cltkernel
	bmi @m
	bvs @s
@c:	lda #0
	jmp alusltu::setrd
@m:	bvs @c
@s:	lda #1
	jmp alusltu::setrd
.endproc

	; aluxor implements the xor and xori instructions.
.proc aluxor
	tax
	aluop eor
	jmp addpc4
.endproc

	; alusrlsra implements the srl, srli, sra, and srai instructions. The first operand is shifted by the amount
	; specified by the lower five bits of the second operand. If bit 30 of the executing instruction is set, an
	; arithmetic shift is performed; otherwise, a logical shift is performed.
.proc alusrlsra
	tax
	lda vin+3
	and #$fe
	bne sra

	; Both shifts special-case a shift by 31 bits. Such a shift is commonly used to check for negative numbers.

srl:
	lda vs2
	and #$1f
	cmp #$1f
	beq srl31
	lda #shift::srl-shift::zero
	jmp shift
srl31:
	lda vx0+96,y
	asl          ; Put the high bit of the source register into C
	lda #0       ; Zero out the high 3 bytes of the destination register
	sta vx0+96,x
	sta vx0+64,x
	sta vx0+32,x
	rol          ; Put the high bit of the source register into the low bit of the accumulator
	sta vx0,x    ; Store the accumulator into the low byte of the destination register
	jmp addpc4

sra:
	lda vs2
	and #$1f
	cmp #$1f
	beq sra31
	lda #shift::sra-shift::zero
	jmp shift
sra31:
	; The result of a 31-bit arithmetic right shift is either zero (if the value in the source register is positive)
	; or (1<<32)-1 (if the value is negative). In both cases, all of the bytes of the destination register will hold
	; the same value--either 0 or 0xff. We use the high bit of the source register (i.e its sign bit) to determine
	; which value to use for the fill. In C, the algorithm is:
	;
	;     uint32_t fill = 0;
	;     if (fill <= vx[Y]) {
	;         fill = 0xffffffff;
	;     }
	;     vx[X] = fill;
	;
	lda #0
	cmp vx0+96,y
	bmi @s
	beq @s
	lda #$ff
@s:	sta vx0+96,x
	sta vx0+64,x
	sta vx0+32,x
	sta vx0,x
	jmp addpc4
.endproc

	; aluor implements the or and ori instructions.
.proc aluor
	tax
	aluop ora
	jmp addpc4
.endproc

	; aluand implements the and and andi instructions.
.proc aluand
	tax
	aluop and
	jmp addpc4
.endproc

	; run is the main loop of the simulator. It is responsible for fetching the next instruction to execute, decoding
	; its opcode field, and dispatching exeucution to the correct handler.
	;
	; The speed of the simulator depends on this loop being as tight as possible.
.proc run
	; If we're targeting the simulator, let it know we've begun an instruction.
.if .defined(simulator)
	lda $e002
.endif

	; Otherwise. copy the next instruction to execute into the instruction register (vin). This copy is done from most-
	; to least-significant byte so that the last load leaves the byte that contains the opcode in A.
	ldy #3
	lda (vpc),y
	sta vin+3
	dey
	lda (vpc),y
	sta vin+2
	dey
	lda (vpc),y
	sta vin+1
	dey
	lda (vpc),y
	sta vin

	; Mask off all but the opcode bits. For RV32I, the low two bits will always be set, so we take the liberty of
	; ignoring them. Conveniently, the result of the mask is suitable as a branch offset into the instruction dispatch
	; table.
	and #$7c
	tax
	jmp (optab,x)
.endproc

	; addpc4 increments the virtual program counter by 4 bytes. In order to save cycles, each byte of the add is only
	; executed if necessary (i.e. if there is a carry out from the previous byte).
.proc addpc4
	; Add four to the least significant byte of the VPC. If there is no carry out, fall through and jump back to the
	; top of run. If there is a carry out, repeat for the next three bytes of the VPC. Note that this code requires
	; that the value in the VPC is always four-byte aligned: it makes the assumption that if the carry is set, then
	; the accumulator must be set to 0, which may not be true if the VPC is not properly aligned.
	clc
	lda vpc
	adc #4
	sta vpc
	bcc run
	adc vpc+1 ; A must be 0, assuming that the value in the VPC is 4-byte aligned.
	sta vpc+1
	bcc run
	adc vpc+2
	sta vpc+2
	bcc run
	lda vpc+3
	adc #0
	sta vpc+3
	jmp run
.endproc

	; Below here is where things really start to get interesting. The code that follows implements most of the
	; instruction-format-specific decoding as well as most of the operand-specific behaviors.

	; opinv is the implementation of an invalid opcode. An invalid opcode will halt the simulator.
.proc opinv
	rts
.endproc

	; oplx implements the LOAD group. This includes the lw, lh, lhu, lb, and lbu instructions. As per the RISC-V spec,
	; LOAD instructions are encoded using the I-type instruction format. The funct3 field indicates the width and
	; sign-extension behavior of the load. This field is extracted and used as the index into a jump table to transfer
	; control to the appropriate load kernel. Each kernel is implemented as an unrolled loop. Loads that target x0 are
	; special-cased: though the load must execute, it must not write to the vx0 virtual register. These loads do not
	; use the jump table, and instead use a load width table and a loop.
	;
	; The first part of this procedure is concerned with calculating the effective address for the load. This address
	; is obtained by adding the value in the base address register (rs1) and the sign-extended 12-bit immediate present
	; in the instruction. Because the 65C02 has a 16-bit address space, only the low 16 bits of the effective address
	; are computed. The effective address is stored in vs1.
	;
	; Obtaining the sign-extended immediate requires some bit shifting. These shifts are accelerated using the
	; lsr4/asr4 tables. The result of indexing these tables with a byte value returns the value shifted right or left
	; by 4 bits, respectively.
.proc oplx
	ldars1
	tax          ; Put the offset of the source register in X.
	ldy vin+2    ; Bits 0-3 of the offset are in the upper 4 bits of the instruction's 3rd byte.
	lda lsr4,y   ; Shift the instruction's 3rd byte right by 4, moving bits 0-3 of the offset into place.
	ldy vin+3    ; Bits 4-7 of the offset are in the lower 4 bits of the instruction's 4th byte.
	ora asl4,y   ; Shift the instruction's 4th byte left by 4 and OR it with A to form the low byte of the offset.
	adc vx0,x    ; Add the low byte of the offset with the low byte of the base register. ldars1 leaves the carry clear.
	sta vs1      ; Store the low byte of the effective address into the low byte of vs1.
	lda lsr4,y   ; Shift the fourth byte of the instruction right by 4, moving bits 8-11 of the offset into place in A.
	bit vin+3    ; Put the offset's sign bit into N.
	bpl s0       ; If the sign bit is zero, skip sign extension: bits 12-15 of the offset are already zero.
	ora #$f0     ; If the sign bit is one, sign extend the offset by setting bits 12-15 to 1.
s0:	adc vx0+32,x ; Add the second byte of the offset with the second byte of the base register.
	sta vs1+1    ; Store the second byte of the effective address into the second byte of vs1.
	lda vin+1    ; Put funct3 into A, then shift and mask it to form the jump/width table index.
	lsr
	lsr
	lsr
	and #$0e
	tax              ; Put the table index into X.
	ldard            ; Load the offset of the destination register into A.
	beq nw           ; If the destination register is x0, branch to the load-only loop.
	jmp (jlxtable,x) ; Otherwise, jump to the appropriate load kernel.

nw:
	; We still need to perform the load when the destination register is x0, as the load may have side effects.
	; This is rare enough in practice that it's not worth using load kernels: instead, we use a table that maps the
	; width field to the number of bytes we need to load and loop.
	lda jnwtable,x
	tax
	ldy #0
rl:	lda (vs1),y
	iny
	dex
	bne rl
	jmp addpc4

lxw:
	tax
	ldy #3
	lda (vs1),y
	sta vx0+96,x
	dey
	lda (vs1),y
	sta vx0+64,x
	dey
	lda (vs1),y
	sta vx0+32,x
	dey
	lda (vs1),y
	sta vx0,x
	jmp addpc4

lxh:
	tax
	ldy #1
	lda (vs1),y
	sta vx0+32,x
	cmp #$80
	dey
	lda (vs1),y
	sta vx0,x
	bcc s1
	dey
s1:	sty vx0+64,x
	sty vx0+96,x
	jmp addpc4

lxb:
	tax
	ldy #0
	lda (vs1),y
	sta vx0,x
	bpl s2
	dey
s2:	sty vx0+32,x
	sty vx0+64,x
	sty vx0+96,x
	jmp addpc4

lxhu:
	tax
	ldy #1
	lda (vs1),y
	sta vx0+32,x
	dey
	lda (vs1),y
	sta vx0,x
	sty vx0+64,x
	sty vx0+96,x
	jmp addpc4

lxbu:
	tax
	ldy #0
	lda (vs1),y
	sta vx0,x
	sty vx0+32,x
	sty vx0+64,x
	sty vx0+96,x
	jmp addpc4

jlxtable:
	.word lxb, lxh, lxw, lxw, lxbu, lxhu
jnwtable:
	.byte 1, 2, 4, 4, 2, 1
.endproc

	; opfence implements the MISC-MEM group.
.proc opfence
	jmp addpc4
.endproc

	; opimm implementds the OP-IMM group.
.proc opimm
	lda #0
	ldx vin+3
	bpl bz    ; if inst[b31] == 0, skip
	lda #$ff  ; if inst[b31] == 1, fill = 0xff
bz:	sta vs2+3 ; imm[3] = fill
	sta vs2+2 ; imm[2] = fill
	and #$f0
	ora lsr4,x
	sta vs2+1 ; imm[1] = fill & 0xf0
	lda asl4,x
	ldx vin+2
	ora lsr4,x
	sta vs2
.endproc

	; alu is the common code shared by instructions in the OP-IMM and OP groups.
.proc alu
	ldars1
	tay

	lda vin+1 ; extract funct3
	lsr
	lsr
	and #$1c
	tax

	; Load rd into A. If rd refers to x0, do nothing: an ALU operator is side-effect-free aside from writing the
	; destiation register, and rd is never written.
	ldard
	beq skip
	jmp (alutab,x)

skip:
	jmp addpc4
.endproc

	; opauipc implements the auipc instruction.
.proc opauipc
	ldard
	beq skip
	tax
	lda vpc
	sta vx0,x
	lda vin+1
	and #$f0
	adc vpc+1   ; ldard leaves the carry clear
	sta vx0+32,x
	lda vin+2
	adc vpc+2
	sta vx0+64,x
	lda vin+3
	adc vpc+3
	sta vx0+96,x
skip:
	jmp addpc4
.endproc

	; opsx implements the STORE group.
.proc opsx
	ldars1
	tax
	lda vin+3
	and #$fe
	tay
	lda vin ; extract the store immediate
	asl
	lda vin+1
	and #$0f  ; mask off upper four bits
	rol
	ora asl4,y
	adc vx0,x ; carry is clear from the rol above
	sta vs1
	lda lsr4,y
	bit vin+3
	bpl s0
	ora #$f0
s0:	adc vx0+32,x
	sta vs1+1
	lda vin+1 ; extract funct3
	lsr
	lsr
	lsr
	and #$0e
	tax
	ldy #0
	ldars2
	jmp (jsxtable,x)
sxw:
	tax
	lda vx0,x
	sta (vs1),y
	iny
	lda vx0+32,x
	sta (vs1),y
	iny
	lda vx0+64,x
	sta (vs1),y
	iny
	lda vx0+96,x
	sta (vs1),y
	jmp addpc4
sxh:
	tax
	lda vx0,x
	sta (vs1),y
	iny
	lda vx0+32,x
	sta (vs1),y
	jmp addpc4
sxb:
	tax
	lda vx0,x
	sta (vs1),y
	jmp addpc4

jsxtable:
	.word sxb, sxh, sxw
.endproc

	; opop implements the OP group.
.proc opop
	ldars2
	tax
	lda vx0,x
	sta vs2
	lda vx0+32,x
	sta vs2+1
	lda vx0+64,x
	sta vs2+2
	lda vx0+96,x
	sta vs2+3
	jmp alu
.endproc

	; oplui implements the lui instruction
.proc oplui
	ldard
	beq skip
	tax
	lda #0
	sta vx0,x
	lda vin+1
	and #$f0
	sta vx0+32,x
	lda vin+2
	sta vx0+64,x
	lda vin+3
	sta vx0+96,x
skip:
	jmp addpc4
.endproc

	; opbxx implements the BRANCH group.
.proc opbxx
	ldars1
	tay
	ldars2
	tax
	lda vin+1 ; check funct3
	and #$70
	sta vf3
	cmp #$30
	bpl ne
	lda vx0,y
	cmp vx0,x
	bne t0
	lda vx0+32,y
	cmp vx0+32,x
	bne t0
	lda vx0+64,y
	cmp vx0+64,x
	bne t0
	lda vx0+96,y
	cmp vx0+96,x
	bne t0
t1:	lda #$10
	bne t2
t0:	lda #0
	beq t2
ne:	cmp #$60
	bpl s0
	sec
	lda vx0,y
	sbc vx0,x
	lda vx0+32,y
	sbc vx0+32,x
	lda vx0+64,y
	sbc vx0+64,x
	lda vx0+96,y
	sbc vx0+96,x
	bmi m0
	bvs t1
	lda #0
	bvc t2
m0:	bvc t1
	lda #0
	bvs t2
s0:	sec
	lda vx0,y
	sbc vx0,x
	lda vx0+32,y
	sbc vx0+32,x
	lda vx0+64,y
	sbc vx0+64,x
	lda vx0+96,y
	sbc vx0+96,x
	bcc t1
	lda #0
t2:	eor vf3
	and #$10
	bne b0
	jmp addpc4
b0:	lda vin+3
	and #$7e
	bit vin
	bpl s2
	ora #$80
s2:	tax
	lda vin+1 ; extract the branch immediate
	asl
	and #$1f  ; mask off upper three bits
	ora asl4,x
	clc
	adc vpc
	sta vpc
	lda lsr4,x
	bit vin+3
	bmi sx
	adc vpc+1
	sta vpc+1
	lda #0
	adc vpc+2
	sta vpc+2
	lda #0
	adc vpc+3
	sta vpc+3
	jmp run
sx:	ora #$f0
	adc vpc+1
	sta vpc+1
	lda #$ff
	adc vpc+2
	sta vpc+2
	lda #$ff
	adc vpc+3
	sta vpc+3
	jmp run
.endproc

	; jalrd is a helper that writes the address of the next instruction into rd (unless rd referes to x0)
.proc jalrd
	ldard
	beq skip
	tax
	lda vpc
	adc #4      ; ldard leaves the carry clear
	sta vx0,x
	lda vpc+1
	adc #0
	sta vx0+32,x
	lda vpc+2
	adc #0
	sta vx0+64,x
	lda vpc+3
	adc #0
	sta vx0+96,x
skip:	
	rts
.endproc

.proc opjalr
	jsr jalrd
	ldars1
	tax
	ldy vin+2
	lda lsr4,y
	ldy vin+3
	ora asl4,y ; immediate byte 1 in a
	adc vx0,x
	sta vpc
	lda lsr4,y
	bit vin+3
	bmi s0     ; immediate byte 2 in a
	adc vx0+32,x
	sta vpc+1
	lda #0     ; immediate byte 3 in a
	adc vx0+64,x
	sta vpc+2
	lda #0     ; immediate byte 4 in a
	adc vx0+96,x
	sta vpc+3
	jmp run
s0:	ora #$f0   ; immediate byte 2 in a
	adc vx0+32,x
	sta vpc+1
	lda #$ff   ; immediate byte 3 in a
	adc vx0+64,x
	sta vpc+2
	lda #$ff   ; immediate byte 4 in a
	adc vx0+96,x
	sta vpc+3
	jmp run
.endproc

.proc opjal
	jsr jalrd ; pc+4 -> rd
	lda vin+2
	tax
	and #$10
	lsr
	sta vs2
	lda vin+3
	and #$7f
	tay
	lda lsr4,x
	ora asl4,y
	and #$fe   ; immediate byte 1 in a
	adc vpc    ; carry cleared by earlier lsr
	sta vpc
	lda vin+1
	and #$f0
	ora vs2
	ora lsr4,y ; immediate byte 2 in a
	adc vpc+1
	sta vpc+1
	lda vin+2
	and #$0f
	bit vin+3
	bmi s0     ; immediate byte 3 in a
	adc vpc+2
	sta vpc+2
	lda #0     ; immediate byte 4 in a
	adc vpc+3
	sta vpc+3
	jmp run
s0:	ora #$f0   ; immediate byte 3 in a
	adc vpc+2
	sta vpc+2
	lda #$ff   ; immediate byte 4 in a
	adc vpc+3
	sta vpc+3
	jmp run
.endproc

.proc opsystem
	lda vx10
	sta tg
	lda vx10+32
	sta tg+1
	lda vx11+96
	pha
	lda vx11
	ldx vx11+32
	ldy vx11+64
	plp
	.byte $20
tg:	.byte $00,$00
	sta vx10
	stx vx10+32
	sty vx10+64
	php
	pla
	sta vx10+96
	jmp addpc4
.endproc

.segment "BSS"
	.align 256
lsr4:
	.res 256
asl4:
	.res 256

.segment "DATA"
	.align 256
optab:
	.word oplx
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opfence
	.word 0
	.word opimm
	.word 0
	.word opauipc
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opsx
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opop
	.word 0
	.word oplui
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opbxx
	.word 0
	.word opjalr
	.word 0
	.word opinv
	.word 0
	.word opjal
	.word 0
	.word opsystem
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
	.word opinv
	.word 0
alutab:
	.word aluaddsub
	.word 0
	.word alusll
	.word 0
	.word aluslt
	.word 0
	.word alusltu
	.word 0
	.word aluxor
	.word 0
	.word alusrlsra
	.word 0
	.word aluor
	.word 0
	.word aluand
	.word 0
