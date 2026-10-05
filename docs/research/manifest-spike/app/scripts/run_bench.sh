#!/usr/bin/env bash
# Usage: scripts/run_bench.sh <synthetic resource count>
# Recompiles the app with that many synthetic resources, then runs the benchmark
# three times in fresh VMs so each of app/scoped/info gets a cold first call.
set -euo pipefail
cd "$(dirname "$0")/.."
export SYNTH="$1"
start=$(date +%s.%N)
mix compile --force --no-validate-compile-env 2>&1 | tail -2
end=$(date +%s.%N)
echo "mix compile with SYNTH=$SYNTH: $(echo "$end - $start" | bc) s"
for first in app scoped info; do
  mix run scripts/bench.exs "$first" 2>&1 | grep -v '^$'
  echo ---
done
