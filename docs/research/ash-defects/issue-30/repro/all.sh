#!/bin/sh
# Runs the matrix: {pg, ets} x {Ash defaults, colleague's flags}. Separate build dirs because config :ash is compile-time.
cd "$(dirname "$0")"
mix run --no-start setup_db.exs || exit 1
for flags in 0 1; do for dl in pg ets; do
  ASHBUG_FLAGS=$flags MIX_BUILD_PATH=_build/flags$flags DL=$dl SQL=1 mix run run.exs > out_${dl}_flags${flags}.txt 2>&1
  echo "$dl flags=$flags exit=$?"
done; done
