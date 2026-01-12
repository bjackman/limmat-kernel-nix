#!/usr/bin/env bash
set -e

# Build the VM runner
echo "Building lk-vm..."
nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#lk-vm

# Create output directory
OUTPUT_DIR=$(mktemp -d)
echo "Output directory: $OUTPUT_DIR"

# Define the command to run inside the VM to trigger the crash
# We wait 30s to ensure the crash kernel is loaded (load-crash-kernel.service)
CRASH_CMD="systemd.run=\"/run/current-system/sw/bin/bash -c 'echo Waiting for crash kernel load...; sleep 30; echo Triggering crash...; echo c > /proc/sysrq-trigger'\""

echo "Running VM with crash trigger..."
# We use --ktests to enable the output directory logic, but we override the command line to run our crash script
./result/bin/lk-vm \
  --golden \
  --ktests \
  --ktests-output "$OUTPUT_DIR" \
  --cmdline "$CRASH_CMD"

echo "VM exited."

if [[ -f "$OUTPUT_DIR/vmcore" ]]; then
  echo "SUCCESS: vmcore found!"
  ls -lh "$OUTPUT_DIR/vmcore"
else
  echo "FAILURE: vmcore not found."
  exit 1
fi
