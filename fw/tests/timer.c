#include "timer.h"
#include <stdio.h>

int main(void) {
    printf("Begin of main: %lu\n", (unsigned long)timer_ms_since_boot());

    for (size_t i = 0; i < 100000; i++) {}

    printf("After loop %lu\n", (unsigned long)timer_ms_since_boot());

    return 0;
}
