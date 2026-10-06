#!/usr/bin/env bash
# Prepares what `npm run measure` measures, in the perf environment
# (config/perf.exs): compiles the demo, builds the assets, and creates,
# migrates and seeds two databases on the Postgres of docker-compose.yml:
#
#   demo_perf           the large seed: 50,000 tasks (about 25 s)
#   demo_perf_standard  the standard seed: 400 tasks
#
# Safe to repeat: seeding empties a database first.
set -euo pipefail

cd "$(dirname "$0")/.."

export MIX_ENV=perf

mix do assets.setup + assets.build

# After a bulk load the planner knows nothing of the tables until autovacuum
# has come by; a database in use has been analysed long ago.
analyse='Demo.Repo.query!("VACUUM ANALYZE", [], timeout: :infinity)'

PERF_DB=demo_perf SEED=large \
  mix do ash.setup --quiet + run priv/repo/seeds.exs + run -e "$analyse"

PERF_DB=demo_perf_standard SEED=standard \
  mix do ash.setup --quiet + run priv/repo/seeds.exs + run -e "$analyse"
