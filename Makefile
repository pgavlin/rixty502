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

all: bin/sim6502 bin/riscv.aiic.bin bin/disas.aiic.bin bin/disas.sim.img

build/riscv.o: core/riscv.s
	$(AS65) -g -o $@ $<

build/riscv.sim.o: core/riscv.s
	$(AS65) -g -o $@ -D simulator=1 $<

build/sim.o: core/sim.s
	$(AS65) -g -o $@ $<

bin/riscv.aiic.bin: build/riscv.o
	$(LD65) -C core/aiic.cfg -o $@ -D program=0x4000 $<

build/init.o: libc/init.s
	$(AS) $(ASFLAGS) -o $@ $<

build/div.o: libc/div.S
	$(AS) $(ASFLAGS) -o $@ $<

build/io.o: libc/io.c
	$(CC) $(CFLAGS) -c -o $@ $<

build/mul.o: libc/mul.S
	$(AS) $(ASFLAGS) -o $@ $<

build/ulisp.o: programs/ulisp.c
	$(CXX) $(CFLAGS) -c -o $@ $<
	
bin/ulisp: build/ulisp.o build/init.o build/div.o
	$(CXX) $(CFLAGS) -T libc/sim.x -o $@ $^

build/ulisp.srec: bin/ulisp
	$(OBJCOPY) -O srec $< $@

build/ulisp.cc65: build/ulisp.srec
	srec-to-cc65 -start 0x4000 <$< >$@

build/ulisp.program.o: build/ulisp.cc65
	$(AS65) -g -o $@ $<

bin/ulisp.sim.img: build/riscv.sim.o build/sim.o core/sim.cfg build/ulisp.program.o
	$(LD65) -C core/sim.cfg --dbgfile bin/ulisp.sim.dbg -o $@ build/riscv.sim.o build/sim.o build/ulisp.program.o

bin/ulisp.aiic.bin: core/aiic.cfg build/ulisp.program.o
	$(LD65) -C core/aiic.cfg --dbgfile bin/ulisp.aiic.dbg -o $@ build/ulisp.program.o

build/hello.o: programs/hello.c
	$(CC) $(CFLAGS) -c -o $@ $<

bin/hello: build/hello.o build/init.o
	$(CC) $(CFLAGS) -T libc/sim.x -o $@ $^

build/hello.srec: bin/hello
	$(OBJCOPY) -O srec $< $@

build/hello.cc65: build/hello.srec
	srec-to-cc65 -start 0x4000 <$< >$@

build/hello.program.o: build/hello.cc65
	$(AS65) -g -o $@ $<

bin/hello.sim.img: build/riscv.sim.o build/sim.o core/sim.cfg build/hello.program.o
	$(LD65) -C core/sim.cfg --dbgfile bin/hello.sim.dbg -o $@ build/riscv.sim.o build/sim.o build/hello.program.o

bin/hello.aiic.bin: core/aiic.cfg build/hello.program.o
	$(LD65) -C core/aiic.cfg --dbgfile bin/hello.aiic.dbg -o $@ build/hello.program.o

build/hlisp.o: programs/hlisp.c
	$(CC) $(CFLAGS) -c -o $@ $<

bin/hlisp: build/hlisp.o build/io.o build/init.o build/div.o build/mul.o
	$(CC) $(CFLAGS) -T libc/sim.x -o $@ $^

build/hlisp.srec: bin/hlisp
	$(OBJCOPY) -O srec $< $@

build/hlisp.cc65: build/hlisp.srec
	srec-to-cc65 -start 0x4000 <$< >$@

build/hlisp.program.o: build/hlisp.cc65
	$(AS65) -g -o $@ $<

bin/hlisp.sim.img: build/riscv.sim.o build/sim.o core/sim.cfg build/hlisp.program.o
	$(LD65) -C core/sim.cfg --dbgfile bin/hlisp.sim.dbg -o $@ build/riscv.sim.o build/sim.o build/hlisp.program.o

bin/hlisp.aiic.bin: core/aiic.cfg build/hlisp.program.o
	$(LD65) -C core/aiic.cfg --dbgfile bin/hlisp.aiic.dbg -o $@ build/hlisp.program.o

build/disas.o: programs/riscv-disas.c
	$(CC) $(CFLAGS) -c -o $@ $<

bin/disas: build/disas.o build/init.o build/div.o build/mul.o
	$(CC) $(CFLAGS) -T libc/sim.x -o $@ $^

build/disas.srec: bin/disas
	$(OBJCOPY) -O srec $< $@

build/disas.cc65: build/disas.srec
	srec-to-cc65 -start 0x4000 <$< >$@

build/disas.program.o: build/disas.cc65
	$(AS65) -g -o $@ $<

bin/disas.sim.img: build/riscv.sim.o build/sim.o core/sim.cfg build/disas.program.o
	$(LD65) -C core/sim.cfg --dbgfile bin/disas.sim.dbg -o $@ build/riscv.sim.o build/sim.o build/disas.program.o

bin/disas.aiic.bin: core/aiic.cfg build/disas.program.o
	$(LD65) -C core/aiic.cfg --dbgfile bin/disas.aiic.dbg -o $@ build/disas.program.o

bin/sim6502: core/sim6502.c
	$(HOSTCC) -o $@ $<

build/miniloader.o: loader/miniloader.s
	$(AS65) -o $@ $<

build/miniloader: build/miniloader.o loader/miniloader.cfg
	$(LD65) -C loader/miniloader.cfg -o $@ build/miniloader.o

bin/miniloader.hex: build/miniloader
	xxd -g 1 -c 8 $< $@

clean:
	rm bin/* build/* 2>/dev/null || true
