#include <stddef.h>

void reverse(char* str, int len) {
    int start = 0;
    int end = len - 1;

    while (start < end) {
        char tmp = str[start];
        str[start] = str[end];
        str[end] = tmp;

        start++;
        end--;
    }
}

int strlen(char* str) {
    int count = 0;

    while (str[count] != '\0') count++;

    return count;
}

int streq(char* str, char* cmp, int len) {
    for (int i = 0; i < len; i++) {
        if (str[i] != cmp[i]) return 0;
    }

    return 1;
}

int main(void) {
    char str[] = "Rev";
    int len = strlen(str);
    reverse(str, len);

    char cmp[] = "veR";
    if (streq(str, cmp, len) == 0) return 1;


    return 0;
}
