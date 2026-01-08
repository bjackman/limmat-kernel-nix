#!/bin/bash
set -euo pipefail

# This script verifies the kdump functionality in lk-vm.
# Prerequisites:
# - A kernel build environment (nix devShell or similar)
# - lk-vm and lk-kconfig tools available in PATH

echo "Verifying kdump support..."

# Create a temporary directory for output
OUTPUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUTPUT_DIR"' EXIT

# Generate a kernel config with kdump support
echo "Generating kernel config..."
lk-kconfig "base vm-boot kdump debug" > "$OUTPUT_DIR/.config"

# Build the kernel (user needs to run this in a kernel tree)
if [ ! -f "Makefile" ]; then
    echo "Error: This script must be run from the root of a kernel tree."
    exit 1
fi

echo "Building kernel (this may take a while)..."
# Using -j$(nproc) for parallel build
make -j"$(nproc)" bzImage > "$OUTPUT_DIR/build.log" 2>&1

# Run lk-vm with ktests enabled to trigger a crash
# We use a custom command to trigger a crash
echo "Booting VM and triggering crash..."
lk-vm --tree . --ktests-output "$OUTPUT_DIR" --cmdline "sysrq_always_enabled=1" --qemu-args "-no-reboot" --ktests "bash -c 'echo c > /proc/sysrq-trigger'" || true

# Check if vmcore exists
if [ -f "$OUTPUT_DIR/vmcore" ]; then
    echo "SUCCESS: vmcore generated at $OUTPUT_DIR/vmcore"
    ls -lh "$OUTPUT_DIR/vmcore"
else
    echo "FAILURE: vmcore not found in $OUTPUT_DIR"
    echo "Check build.log and console output for details."
    exit 1
fi
