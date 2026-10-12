#include <stdio.h>

int main(void) {
    char buf[64];

    FILE *f = fopen("test.txt", "w");
    if (!f) {
        perror("create");
        return 1;
    }
    fprintf(f, "written by fprintf %d\n", 42);
    if (fclose(f)) {
        perror("write");
        return 1;
    }

    f = fopen("test.txt", "r");
    if (!f || !fgets(buf, sizeof buf, f)) {
        perror("read");
        return 1;
    }
    fclose(f);
    printf("read back: %s", buf);
    return 0;
}
