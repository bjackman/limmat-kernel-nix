#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>

#ifndef __NR_memfd_secret
#define __NR_memfd_secret 447
#endif

#ifndef O_CLOEXEC
#define O_CLOEXEC 02000000
#endif

long long parse_size(const char *str) {
    char *endptr;
    long long val = strtoll(str, &endptr, 10);
    if (endptr == str) {
        return -1;
    }
    if (*endptr == '\0') {
        return val;
    }
    if (endptr[1] != '\0') {
        return -1;
    }
    switch (*endptr) {
        case 'k':
        case 'K':
            return val * 1024;
        case 'm':
        case 'M':
            return val * 1024LL * 1024LL;
        case 'g':
        case 'G':
            return val * 1024LL * 1024LL * 1024LL;
        default:
            return -1;
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <size>[K|M|G]\n", argv[0]);
        fprintf(stderr, "Example: %s 2M\n", argv[0]);
        return 1;
    }

    long long size = parse_size(argv[1]);
    if (size <= 0) {
        fprintf(stderr, "Invalid size: %s\n", argv[1]);
        return 1;
    }

    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size < 0) {
        perror("sysconf");
        return 1;
    }

    // Round up to page size
    long long aligned_size = ((size + page_size - 1) / page_size) * page_size;
    if (aligned_size != size) {
        printf("Rounding size up to page multiple: %lld -> %lld\n", size, aligned_size);
    }

    printf("Attempting to allocate %lld bytes from memfd_secret...\n", aligned_size);

    // Note: memfd_secret might require secretmem.enable=1 (or secretmem.size=...) on boot.
    int fd = syscall(__NR_memfd_secret, O_CLOEXEC);
    if (fd < 0) {
        perror("memfd_secret");
        if (errno == ENOSYS) {
            fprintf(stderr, "Note: memfd_secret might not be supported by your kernel, or it is disabled.\n");
            fprintf(stderr, "Check if CONFIG_SECRETMEM is enabled and 'secretmem.size' boot parameter is set.\n");
        }
        return 1;
    }

    if (ftruncate(fd, aligned_size) < 0) {
        perror("ftruncate");
        close(fd);
        return 1;
    }

    // memfd_secret MUST be mapped with MAP_SHARED. MAP_PRIVATE is not allowed.
    void *ptr = mmap(NULL, aligned_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (ptr == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return 1;
    }

    printf("Successfully allocated and mapped %lld bytes at %p\n", aligned_size, ptr);

    // Write to the memory to populate pages
    printf("Populating memory...\n");
    long long chunk_size = aligned_size / 10;
    if (chunk_size < page_size) {
        chunk_size = page_size;
    }
    // Align chunk_size to page_size
    chunk_size = (chunk_size / page_size) * page_size;

    unsigned char *uptr = (unsigned char *)ptr;
    long long populated = 0;
    while (populated < aligned_size) {
        long long to_populate = aligned_size - populated;
        if (to_populate > chunk_size) {
            to_populate = chunk_size;
        }
        memset(uptr + populated, 0x5A, to_populate);
        populated += to_populate;
        printf("Populated %lld/%lld bytes (%.0f%%)...\n",
               populated, aligned_size, (double)populated / aligned_size * 100);
    }
    printf("Memory populated. First byte: 0x%02X\n", uptr[0]);

    if (munmap(ptr, aligned_size) < 0) {
        perror("munmap");
    }
    close(fd);

    return 0;
}
