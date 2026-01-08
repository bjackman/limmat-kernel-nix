#!/bin/bash
set -euo pipefail

# This script verifies the kdump functionality in lk-vm using the pre-packaged kernel.
# Prerequisites:
# - Nix installed and configured

echo "Verifying kdump support using pre-packaged kernel..."

# Create a temporary directory for output
OUTPUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUTPUT_DIR"' EXIT

# Run lk-vm with ktests enabled to trigger a crash
# We use a custom command to trigger a crash
echo "Booting VM and triggering crash..."
# We don't specify --tree or --kernel, relying on the default pre-packaged kernel
nix run .#lk-vm -- --ktests-output "$OUTPUT_DIR" --cmdline "sysrq_always_enabled=1" --qemu-args "-no-reboot" --ktests "bash -c 'echo c > /proc/sysrq-trigger'" || true

# Check if vmcore exists
if [ -f "$OUTPUT_DIR/vmcore" ]; then
    echo "SUCCESS: vmcore generated at $OUTPUT_DIR/vmcore"
    ls -lh "$OUTPUT_DIR/vmcore"
else
    echo "FAILURE: vmcore not found in $OUTPUT_DIR"
    exit 1
fi
