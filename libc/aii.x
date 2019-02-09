SECTIONS
{
  . = 0x00004000;
  .text : { build/init.o(.text); *(.text) }
  .data : { *(.data) }
  .rodata : { *(.rodata) }
  .srodata : { *(.srodata) }
  .bss : { *(.bss) }
  .sbss : { *(.sbss) }
}
