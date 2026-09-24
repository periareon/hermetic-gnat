/* Compiled by the shipped gcc: proves the C front end and the system (or
   bundled mingw-w64) headers are usable from wherever the toolchain lives. */
#include <string.h>

int pa_add(int a, int b) { return a + b; }
const char *pa_greeting(void) { return "hello from C"; }
size_t pa_length(const char *s) { return strlen(s); }
