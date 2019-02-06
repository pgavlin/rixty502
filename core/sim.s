	; Support code for interacting with the 6502 simulator harness.

	stdio = $e000
	trap = $e001

.segment "CLREOL"
	.org $fc9c
.proc clreol
	rts
.endproc

.segment "COUTA"
	.org $fded
.proc couta
	sta stdio
	rts
.endproc

.segment "RDKEYA"
	.org $fd0c
.proc rdkeya
	lda stdio
	rts
.endproc

.segment "RESET"
	.org $fffc
reset:
	.import start
	.word start

.export clreol, couta, rdkeya, reset
