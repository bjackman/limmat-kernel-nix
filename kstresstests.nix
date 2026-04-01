# TODO:
# - Do we want to integrate this into ktests? I think no we want stress tests
#   to have a different interface from ktests since they will never "pass"
# - Do we want a flexible configurable set of stressors?
# - Do we need some higher-level scripts for comparing kernels? Are stresstests
#   actually benchmarks that should be analysed by Falba?
{ pkgs }:
pkgs.writeShellApplication {
  name = "kstresstests";

  runtimeInputs = with pkgs; [
    stress-ng
    util-linux
  ];

  text = ''
    cleanup() {
        echo "Terminating stress-ng..."
        kill "$STRESS_PID" 2>/dev/null
        exit 0
    }

    trap cleanup SIGINT SIGTERM

    stress-ng --secretmem 1 --timeout 0 &
    STRESS_PID=$!

    while true; do
        echo "[$(date +%T)] Disabling 16G of memory..."
        if chmem -d 16G; then
            sleep 2
            echo "[$(date +%T)] Enabling 16G of memory..."
            chmem -e 16G
        else
            echo "Error: chmem -d 16G failed. Check system memory availability."
        fi
        sleep 2
    done
  '';
}
