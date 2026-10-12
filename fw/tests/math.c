int main(void) {
    volatile int a = 5;
    volatile int b = 10;
    volatile int c = a + b;

    for (int i = 0; i < 100; i++) {
        c += i;
    }

    return c;
}
