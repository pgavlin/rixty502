CC=riscv64-unknown-elf-gcc
CXX=riscv64-unknown-elf-g++
CFLAGS=-march=rv32i -mabi=ilp32 -Os -nostdlib -fno-builtin -fno-exceptions
AS=riscv64-unknown-elf-as
ASFLAGS=-march=rv32i -mabi=ilp32
OBJCOPY=riscv64-unknown-elf-objcopy

AS65=ca65
LD65=ld65

HOSTCC=clang

.PHONY: clean

riscv.o: core/riscv.s
	$(AS65) -g -o $@ $<

sim.o: core/sim.s
	$(AS65) -g -o $@ $<

init.o: libc/init.s
	$(AS) $(ASFLAGS) -o $@ $<

div.o: libc/div.S
	$(AS) $(ASFLAGS) -o $@ $<

io.o: libc/io.c
	$(CC) $(CFLAGS) -c -o $@ $<

mul.o: libc/mul.S
	$(AS) $(ASFLAGS) -o $@ $<

ulisp.o: programs/ulisp.c
	$(CXX) $(CFLAGS) -c -o $@ $<
	
ulisp: ulisp.o init.o div.o
	$(CXX) $(CFLAGS) -T libc/sim.x -o $@ $^

ulisp.srec: ulisp
	$(OBJCOPY) -O srec $< $@

ulisp.cc65: ulisp.srec
	srec-to-cc65 <$< >$@

ulisp.program.o: ulisp.cc65
	$(AS65) -g -o $@ $<

ulisp.sim.img: riscv.o sim.o core/sim.cfg ulisp.program.o
	$(LD65) -C core/sim.cfg --dbgfile ulisp.sim.dbg -o $@ riscv.o sim.o ulisp.program.o

ulisp.aiic.img: riscv.o core/aiic.cfg ulisp.program.o
	$(LD65) -C core/aiic.cfg --dbgfile ulisp.aiic.dbg -o $@ riscv.o ulisp.program.o

hello.o: programs/hello.c
	$(CC) $(CFLAGS) -c -o $@ $<

hello: hello.o io.o init.o
	$(CC) $(CFLAGS) -T libc/sim.x -o $@ $^

hello.srec: hello
	$(OBJCOPY) -O srec $< $@

hello.cc65: hello.srec
	srec-to-cc65 <$< >$@

hlisp.o: programs/hlisp.c
	$(CC) $(CFLAGS) -c -o $@ $<

hlisp: hlisp.o io.o init.o div.o mul.o
	$(CC) $(CFLAGS) -T libc/sim.x -o $@ $^

hlisp.srec: hlisp
	$(OBJCOPY) -O srec $< $@

hlisp.cc65: hlisp.srec
	srec-to-cc65 -start 0x4000 <$< >$@

hlisp.program.o: hlisp.cc65
	$(AS65) -g -o $@ $<

hlisp.sim.img: riscv.o sim.o core/sim.cfg hlisp.program.o
	$(LD65) -C core/sim.cfg --dbgfile hlisp.sim.dbg -o $@ riscv.o sim.o hlisp.program.o

hlisp.aiic.img: riscv.o core/aiic.cfg hlisp.program.o
	$(LD65) -C core/aiic.cfg --dbgfile hlisp.aiic.dbg -o $@ riscv.o hlisp.program.o

sim6502: core/sim6502.c
	$(HOSTCC) -o $@ $<

miniloader.o: loader/miniloader.s
	$(AS65) -o $@ $<

miniloader.bin: miniloader.o loader/miniloader.cfg
	$(LD65) -C loader/miniloader.cfg -o $@ miniloader.o

miniloader.hex: miniloader.bin
	xxd -g 1 -c 8 $< $@

clean:
	rm *.o *.srec *.cc65 *.img *.dbg ulisp sim6502 hlisp hello 2>/dev/null || true
