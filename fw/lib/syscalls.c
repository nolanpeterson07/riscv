#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include "ff.h"
#include "uart.h"

#undef errno
extern int errno;

// keep this much room between the heap and the current stack pointer
#define STACK_GUARD 512

extern char _heap_start[];

// fds 0-2 are the uart, files on the sd card start at 3
#define NFILES 2

static FATFS fs;
static FIL files[NFILES];
static char used[NFILES];
static char mounted;

static FIL *file(int fd) {
    if (fd < 3 || fd >= 3 + NFILES || !used[fd - 3]) {
        errno = EBADF;
        return 0;
    }
    return &files[fd - 3];
}

static int fail(FRESULT r) {
    switch (r) {
    case FR_OK: return 0;
    case FR_NO_FILE: case FR_NO_PATH: errno = ENOENT; break;
    case FR_EXIST: errno = EEXIST; break;
    case FR_DENIED: case FR_WRITE_PROTECTED: errno = EACCES; break;
    default: errno = EIO;
    }
    return -1;
}

static int mount(void) {
    if (!mounted && fail(f_mount(&fs, "", 1)))
        return -1;
    mounted = 1;
    return 0;
}

void _exit(int code) {
    uart_puts("\r\nProgram exited with status code ");
    uart_putdec(code);
    uart_puts("\r\n");

    register int a0 __asm__("a0") = code;
    __asm__ volatile("ebreak" : : "r"(a0));
    for (;;)
        ;
}

int _open(const char *path, int flags, int mode) {
    (void)mode;
    if (mount())
        return -1;

    // translate posix open flags to a fatfs mode byte
    //   fopen  flags                 fatfs
    //   "r"    -                     (open existing)
    //   "w"    O_CREAT | O_TRUNC     FA_CREATE_ALWAYS  create or wipe
    //   "a"    O_CREAT | O_APPEND    FA_OPEN_APPEND    create, start at end
    //   "wx"   O_CREAT | O_EXCL      FA_CREATE_NEW     fail if it exists
    //          O_CREAT               FA_OPEN_ALWAYS    create, keep contents
    BYTE m = (flags & O_ACCMODE) == O_RDONLY ? FA_READ
           : (flags & O_ACCMODE) == O_WRONLY ? FA_WRITE : FA_READ | FA_WRITE;
    if ((flags & (O_CREAT | O_EXCL)) == (O_CREAT | O_EXCL))
        m |= FA_CREATE_NEW;
    else if ((flags & (O_CREAT | O_TRUNC)) == (O_CREAT | O_TRUNC))
        m |= FA_CREATE_ALWAYS;
    else if (flags & O_APPEND)
        m |= FA_OPEN_APPEND;
    else if (flags & O_CREAT)
        m |= FA_OPEN_ALWAYS;

    for (int i = 0; i < NFILES; i++) {
        if (used[i])
            continue;
        if (fail(f_open(&files[i], path, m)))
            return -1;
        used[i] = 1;
        return i + 3;
    }
    errno = EMFILE;
    return -1;
}

int _write(int fd, const char *buf, int len) {
    if (fd > 2) {
        FIL *f = file(fd);
        UINT n;
        return !f || fail(f_write(f, buf, len, &n)) ? -1 : (int)n;
    }
    for (int i = 0; i < len; i++) {
        if (buf[i] == '\n')
            uart_putc('\r');
        uart_putc(buf[i]);
    }
    return len;
}

int _read(int fd, char *buf, int len) {
    if (fd > 2) {
        FIL *f = file(fd);
        UINT n;
        return !f || fail(f_read(f, buf, len, &n)) ? -1 : (int)n;
    }
    int i = 0;
    while (i < len) {
        char c = uart_getc();
        buf[i++] = c;
        if (c == '\n' || c == '\r')
            break;
    }
    return i;
}

void *_sbrk(int incr) {
    static char *brk = _heap_start;
    char *sp;
    __asm__ volatile("mv %0, sp" : "=r"(sp));
    if (brk + incr > sp - STACK_GUARD) {
        errno = ENOMEM;
        return (void *)-1;
    }
    char *prev = brk;
    brk += incr;
    return prev;
}

int _close(int fd) {
    FIL *f = file(fd);
    if (!f)
        return -1;
    used[fd - 3] = 0;
    return fail(f_close(f));
}

int _fstat(int fd, struct stat *st) {
    if (fd > 2) {
        FIL *f = file(fd);
        if (!f)
            return -1;
        st->st_mode = S_IFREG;
        st->st_size = f_size(f);
        return 0;
    }
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int fd) { return fd <= 2; }

int _lseek(int fd, int off, int whence) {
    if (fd <= 2)
        return 0;
    FIL *f = file(fd);
    if (!f)
        return -1;
    if (whence == SEEK_CUR)
        off += f_tell(f);
    else if (whence == SEEK_END)
        off += f_size(f);
    if (off < 0) {
        errno = EINVAL;
        return -1;
    }
    return fail(f_lseek(f, off)) ? -1 : (int)f_tell(f);
}

int _unlink(const char *path) {
    return mount() ? -1 : fail(f_unlink(path));
}

int _kill(int pid, int sig) { (void)pid; (void)sig; errno = EINVAL; return -1; }

int _getpid(void) { return 1; }
