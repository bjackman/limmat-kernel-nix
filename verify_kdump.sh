#!/usr/bin/env bash
set -e

# Build the VM runner
echo "Building lk-vm..."
# Using flags to ensure it works in restricted environments if needed
nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#lk-vm

# Create output directory
OUTPUT_DIR=$(mktemp -d)
LOG_FILE="$OUTPUT_DIR/vm.log"
echo "Output directory: $OUTPUT_DIR"
echo "VM Log file: $LOG_FILE"

# Define the command to run inside the VM to trigger the crash
# We poll for the crash kernel to be loaded before triggering.
CRASH_CMD="systemd.run=\"/run/current-system/sw/bin/bash -c '
  echo \\\"Checking for crash kernel...\\\";
  for i in {1..60}; do
    if [[ -f /sys/kernel/kexec_crash_loaded ]]; then
      loaded=\$(cat /sys/kernel/kexec_crash_loaded);
      if [[ \\\"\$loaded\\\" == \\\"1\\\" ]]; then
        echo \\\"Crash kernel loaded! Triggering crash in 2s...\\\";
        sleep 2;
        echo c > /proc/sysrq-trigger;
        exit 0;
      fi
    fi
    echo \\\"Waiting for crash kernel load... \$i\\\";
    sleep 1;
  done;
  echo \\\"Timed out waiting for crash kernel.\\\";
  exit 1
'\""

echo "Running VM with crash trigger..."
# We use --ktests to enable the output directory logic, but we override the command line to run our crash script
# We capture stdout/stderr to analyze if things go wrong.
./result/bin/lk-vm \
  --golden \
  --ktests \
  --ktests-output "$OUTPUT_DIR" \
  --cmdline "$CRASH_CMD" > "$LOG_FILE" 2>&1 || true

echo "VM exited."

if [[ -f "$OUTPUT_DIR/vmcore" ]]; then
  echo "SUCCESS: vmcore found!"
  ls -lh "$OUTPUT_DIR/vmcore"
  exit 0
else
  echo "FAILURE: vmcore not found."
  echo "Dump of VM log:"
  cat "$LOG_FILE"
  exit 1
fi
