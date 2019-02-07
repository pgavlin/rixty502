#include <stdint.h>

void cout(char c);

void puts(char* s) {
	for (int i = 0; s[i] != '\0'; i++) {
		cout(s[i] | 0x80);
	}
}

int main() {
	puts("HELLO, WORLD!\n");
	return 0;
}
