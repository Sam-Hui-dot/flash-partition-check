ENTRY(reset)
MEMORY {
  FLASH (rx) : ORIGIN = 0x26000, LENGTH = 0xED000 - 0x26000
}
SECTIONS {
  .text : { KEEP(*(.vectors)) *(.text*) } > FLASH
}
