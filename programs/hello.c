#include <stdint.h>

uint32_t syscall(uint32_t addr, uint32_t arg);

void cout(char c) {
	const uint32_t couta = 0xfded;
	syscall(couta, (uint32_t)c);
}

void puts(char* s) {
	for (int i = 0; s[i] != '\0'; i++) {
		cout(s[i] | 0x80);
	}
}

int main() {
	puts("HELLO, WORLD!\n");
	return 0;
}
