	processor 6502

acr2  equ $c0ab
axr2  equ $c0aa
asr2  equ $c0a9
adr2  equ $c0a8

addr equ $00

	seg program
	org $800

	lda #$16     ; 9600bps, 8n1
	sta acr2     ; Write ACIA 2's control register
	lda #$03     ; TX disabled, IRQ disabled, RX enabled
	sta axr2     ; Write ACIA 2's command register

.w	jsr getc     ; read the command
	bne .l       ; not zero? read the block
	rts
.l	jsr getc     ; read the MSB of the address
	sta addr+1
	jsr getc     ; read the LSB of the address
	sta addr
	jsr getc     ; read the length
	ldy #0
	tax
.d	jsr getc     ; read a data byte
	sta (addr),y ; addr[y] = db
	iny          ; y++
	dex          ; x--
	bne .d       ; loop
	beq .w       ; done; do next block

getc subroutine
	lda #$08     ; set up the receive data, register full flag
.w	bit asr2     ; is there data?
	beq .w       ; no: keep waiting
	lda adr2     ; yes: read the byte and return
	rts
