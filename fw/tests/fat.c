#include "ff.h"
#include <stdio.h>

static FATFS fs;

int main(void) {
    printf("init\n");

    FIL f;
    char buf[64];
    UINT n;
    FRESULT r;

    if ((r = f_mount(&fs, "", 1)) || (r = f_open(&f, "hello.txt", FA_READ))
        || (r = f_read(&f, buf, sizeof buf - 1, &n))) {
        printf("fatfs error %d\n", r);
        return 1;
    }

    buf[n] = 0;
    printf("%s\n", buf);
    return 0;
}
