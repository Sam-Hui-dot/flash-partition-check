__attribute__((noreturn)) void reset(void) {
  for (;;) __asm__ volatile("wfi");
}

__attribute__((section(".vectors"), used))
const unsigned long vectors[] = { 0x20040000UL, (unsigned long)reset };
