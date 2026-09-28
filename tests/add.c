int main(void) {
    volatile int *out = (int *)0x100;
    int sum = 0;
    for (int i = 1; i <= 5; i++)
        sum += i;
    *out = sum;
    return sum;
}
