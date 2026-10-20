#!/usr/bin/env bash
# Records the three GIFs of the README (docs/images/*.gif) and its screenshot
# (docs/images/tasks.png) against a demo of its own, then stops it.
#
#   scripts/record-gifs.sh
#
# What it does, so that nothing else on the machine is touched:
#
#   1. Exports the committed HEAD into a temporary directory and starts the
#      demo there with `docker compose --profile demo up --build`, the way the
#      README says, as a compose project of its own (`ash_data_table_gifs`),
#      its own Postgres volume, the demo on GIFS_PORT (4490) and Postgres on
#      GIFS_PG_PORT (5490). A fresh standard seed, so the clips always show
#      the same rows.
#   2. Records one Playwright video per clip (demo/e2e/readme-gifs.mjs, not
#      part of `npm test`).
#   3. Turns each video into a GIF with ffmpeg in a container (the image
#      below, pinned), and takes the project down with its volume.
#
# Needs Docker, git, and the browser tests' npm packages (`npm install` in
# demo/e2e, `npm run browsers` there once).
set -euo pipefail

FFMPEG_IMAGE="jrottenberg/ffmpeg:7.1-alpine@sha256:8ec1ee1f6a0fcd37c97725827b6b7832795c9596e3439b8da56d7700d61ae778"
PROJECT="ash_data_table_gifs"
PORT="${GIFS_PORT:-4490}"
PG_PORT="${GIFS_PG_PORT:-5490}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/images"
WORK="$(mktemp -d)"

compose() {
  DEMO_PORT="$PORT" POSTGRES_PORT="$PG_PORT" \
    docker compose -p "$PROJECT" -f "$WORK/src/docker-compose.yml" --profile demo "$@"
}

cleanup() {
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/src" "$WORK/videos" "$OUT"
git -C "$ROOT" archive HEAD | tar -x -C "$WORK/src"

echo "Starting the demo on http://127.0.0.1:$PORT (first build takes minutes)"
compose up --build -d

for _ in $(seq 1 180); do
  curl -fs -o /dev/null "http://127.0.0.1:$PORT/tasks" && break
  sleep 5
done
curl -fsS -o /dev/null "http://127.0.0.1:$PORT/tasks" || {
  compose logs app | tail -50
  echo "The demo did not come up." >&2
  exit 1
}

echo "Recording"
(cd "$ROOT/demo/e2e" && GIFS_URL="http://127.0.0.1:$PORT" VIDEOS_DIR="$WORK/videos" SHOT="$OUT/tasks.png" \
  node readme-gifs.mjs)

echo "Converting"
for video in "$WORK"/videos/*.webm; do
  name="$(basename "$video" .webm)"
  # through stdin and stdout: Docker Desktop mounts no temporary directory
  docker run --rm -i "$FFMPEG_IMAGE" -loglevel error -f webm -i pipe:0 \
    -vf "fps=8,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    -f gif pipe:1 <"$video" >"$OUT/$name.gif"
  ls -l "$OUT/$name.gif"
done
