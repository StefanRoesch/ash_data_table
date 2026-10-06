#!/usr/bin/env bash
# Starts the demo for the browser tests. Playwright runs this (`webServer` in
# playwright.config.ts) and stops it when the tests are done.
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
