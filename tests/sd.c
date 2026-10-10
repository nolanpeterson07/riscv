#include "sdspi.h"
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    if (sdspi_init(SDSPI) != 0) {
        printf("SD failed to init\n");
        exit(1);
    }

    return 0;
}
