#include <stdint.h>

uint32_t syscall(uint32_t addr, uint32_t arg);

void cout(char c) {
	const uint32_t couta = 0xfded;
	syscall(couta, (uint32_t)c);
}

char rdkey() {
	const uint32_t rdkeya = 0xfd0c;
	return (char)syscall(rdkeya, 0);
}

void puts(char* s) {
	for (int i = 0; s[i] != '\0'; i++) {
		cout(s[i] | 0x80);
	}
}

void putint(int n) {
	char buf[10]; // max 32-bit int is 10 decimal digits
	if (n < 0) {
		cout('-');
	}
	int i = 0;
	for (; n != 0; n = n / 10) {
		int d = n % 10;
		buf[i++] = '0' + (n % 10);
	}
	while (i > 0) {
		cout(buf[--i]);
	}
}
