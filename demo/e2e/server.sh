#!/usr/bin/env bash
# Starts one demo for the browser tests and keeps it running, for writing
# tests: `npm run test:server` runs them against it, one at a time. `npm test`
# does not use it: there every worker starts a server of its own
# (support/server.ts).
#
# In the e2e environment (config/e2e.exs): creates and migrates the database
# `demo_e2e`, fills it with the standard seed, builds the assets, and serves
# the demo on E2E_PORT (4479).
set -euo pipefail

cd "$(dirname "$0")/.."

export MIX_ENV=e2e
export PORT="${E2E_PORT:-4479}"

mix do ash.setup --quiet + run priv/repo/seeds.exs + assets.setup + assets.build

exec mix phx.server
