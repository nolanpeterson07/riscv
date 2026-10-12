#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int cmp(const void *a, const void *b) {
    return *(const int *)a - *(const int *)b;
}

int main(void) {
    printf("%d %x %s\n", -42, 0xbeef, "ok");

    int *nums = (int*)malloc(4 * sizeof(int));
    if (!nums)
        return -1;
    nums[0] = 30; nums[1] = 10; nums[2] = 40; nums[3] = 20;
    qsort(nums, 4, sizeof(int), cmp);
    printf("sorted: %d %d %d %d\n", nums[0], nums[1], nums[2], nums[3]);

    char buf[16];
    strcpy(buf, "riscv");
    strcat(buf, "32i");
    printf("%s len %d\n", buf, (int)strlen(buf));

    int ret = nums[3] + atoi("2") + (strcmp(buf, "riscv32i") == 0);
    free(nums);

    return ret;
}
