#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>
#include <linux/kvm.h>

#ifndef GUEST_MEMFD_FLAG_MMAP
#define GUEST_MEMFD_FLAG_MMAP (1ULL << 0)
#endif

#ifndef GUEST_MEMFD_FLAG_INIT_SHARED
#define GUEST_MEMFD_FLAG_INIT_SHARED (1ULL << 1)
#endif

#ifndef GUEST_MEMFD_FLAG_NO_DIRECT_MAP
#define GUEST_MEMFD_FLAG_NO_DIRECT_MAP (1ULL << 2)
#endif

#ifndef KVM_CREATE_GUEST_MEMFD
struct kvm_create_guest_memfd {
	__u64 size;
	__u64 flags;
	__u64 reserved[6];
};
#define KVM_CREATE_GUEST_MEMFD _IOWR(KVMIO, 0xd4, struct kvm_create_guest_memfd)
#endif

#define NUM_ITERATIONS 5000
#define MAX_PAGES 512 // Max 2MB per allocation
#define PAGE_SIZE 4096

typedef enum {
    MODE_MIXED,
    MODE_ANON,
    MODE_GUEST
} TestMode;

void touch_memory(volatile unsigned char *addr, size_t size, const char *type) {
    // Write pattern
    for (size_t i = 0; i < size; i += PAGE_SIZE) {
        addr[i] = (unsigned char)(i % 255);
    }
    // Read/Verify pattern
    for (size_t i = 0; i < size; i += PAGE_SIZE) {
        unsigned char val = addr[i];
        if (val != (unsigned char)(i % 255)) {
            fprintf(stderr, "[%s] Data verification failed at offset %zu. Expected: %u, Got: %u\n",
                    type, i, (unsigned char)(i % 255), val);
            exit(1);
        }
    }
}

void test_anon(size_t size) {
    void *addr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (addr == MAP_FAILED) {
        perror("mmap anon");
        exit(1);
    }

    touch_memory((volatile unsigned char *)addr, size, "Anonymous");

    if (munmap(addr, size) < 0) {
        perror("munmap anon");
        exit(1);
    }
}

void test_guest_memfd(int vm_fd, size_t size, int use_no_direct_map) {
    __u64 flags = GUEST_MEMFD_FLAG_MMAP | GUEST_MEMFD_FLAG_INIT_SHARED;
    if (use_no_direct_map) {
        flags |= GUEST_MEMFD_FLAG_NO_DIRECT_MAP;
    }

    struct kvm_create_guest_memfd guest_memfd_args = {
        .size = size,
        .flags = flags,
    };

    int memfd = ioctl(vm_fd, KVM_CREATE_GUEST_MEMFD, &guest_memfd_args);
    if (memfd < 0) {
        perror("KVM_CREATE_GUEST_MEMFD");
        exit(1);
    }

    void *addr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, memfd, 0);
    if (addr == MAP_FAILED) {
        perror("mmap guest_memfd");
        close(memfd);
        exit(1);
    }

    touch_memory((volatile unsigned char *)addr, size, "GuestMemfd");

    if (munmap(addr, size) < 0) {
        perror("munmap guest_memfd");
        close(memfd);
        exit(1);
    }

    close(memfd);
}

int main(int argc, char *argv[]) {
    int use_no_direct_map = 1;
    TestMode mode = MODE_MIXED;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--skip-no-direct-map") == 0) {
            use_no_direct_map = 0;
            printf("Skipping GUEST_MEMFD_FLAG_NO_DIRECT_MAP\n");
        } else if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
            if (strcmp(argv[i+1], "anon") == 0) {
                mode = MODE_ANON;
            } else if (strcmp(argv[i+1], "guest") == 0) {
                mode = MODE_GUEST;
            } else if (strcmp(argv[i+1], "mixed") == 0) {
                mode = MODE_MIXED;
            } else {
                fprintf(stderr, "Unknown mode: %s\n", argv[i+1]);
                return 1;
            }
            i++;
        }
    }

    srand(time(NULL));

    int kvm_fd = open("/dev/kvm", O_RDWR);
    if (kvm_fd < 0) {
        perror("open /dev/kvm");
        return 1;
    }

    int vm_fd = ioctl(kvm_fd, KVM_CREATE_VM, 0);
    if (vm_fd < 0) {
        perror("KVM_CREATE_VM");
        close(kvm_fd);
        return 1;
    }

    printf("Starting stress test in %s mode with %d iterations...\n",
           mode == MODE_ANON ? "anon" : (mode == MODE_GUEST ? "guest" : "mixed"),
           NUM_ITERATIONS);

    for (int i = 0; i < NUM_ITERATIONS; i++) {
        size_t size = ((rand() % MAX_PAGES) + 1) * PAGE_SIZE;

        if (i % 100 == 0) {
            printf("Iteration %d\r", i);
            fflush(stdout);
        }

        int do_anon;
        if (mode == MODE_ANON) {
            do_anon = 1;
        } else if (mode == MODE_GUEST) {
            do_anon = 0;
        } else {
            do_anon = rand() % 2;
        }

        if (do_anon) {
            test_anon(size);
        } else {
            test_guest_memfd(vm_fd, size, use_no_direct_map);
        }
    }

    printf("\nTest completed successfully.\n");

    close(vm_fd);
    close(kvm_fd);
    return 0;
}
