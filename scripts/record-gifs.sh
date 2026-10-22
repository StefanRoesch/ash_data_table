#!/usr/bin/env bash
# Records the GIFs of the README (docs/images/*.gif) and its screenshot
# (docs/images/tasks.png) against a demo of its own, then stops it.
#
#   scripts/record-gifs.sh                # every clip
#   scripts/record-gifs.sh picker         # only the clips named, no picture
#
# What it does, so that nothing else on the machine is touched:
#
#   1. Exports the committed HEAD into a temporary directory and starts a
#      Postgres container of its own there (`ash_data_table_gifs_pg`, an
#      anonymous volume) on GIFS_PG_PORT (5490).
#   2. Runs `mix setup` and `mix phx.server` in the exported demo/, on
#      GIFS_PORT (4490): a fresh standard seed, so the clips always show the
#      same rows. The Hex deps are copied from this checkout's demo/deps, so
#      nothing is fetched that is already here.
#   3. Records one Playwright video per clip (demo/e2e/readme-gifs.mjs, not
#      part of `npm test`).
#   4. Turns each video into a GIF with ffmpeg in a container (the image
#      below, pinned), then stops the server and removes the container with
#      its volume.
#
# Needs Docker, git, Elixir 1.18+, Node 20+, and the browser tests' npm
# packages (`npm install` in demo/e2e, `npm run browsers` there once).
set -euo pipefail

FFMPEG_IMAGE="jrottenberg/ffmpeg:7.1-alpine@sha256:8ec1ee1f6a0fcd37c97725827b6b7832795c9596e3439b8da56d7700d61ae778"
POSTGRES_IMAGE="postgres:18.6-alpine"
PG_CONTAINER="ash_data_table_gifs_pg"
PORT="${GIFS_PORT:-4490}"
PG_PORT="${GIFS_PG_PORT:-5490}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/images"
WORK="$(mktemp -d)"
SERVER=""

cleanup() {
  # the server runs in a session of its own: its watchers go with it
  [ -n "$SERVER" ] && kill -TERM -- "-$SERVER" 2>/dev/null || true
  docker rm -f -v "$PG_CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/src" "$WORK/videos" "$OUT"
git -C "$ROOT" archive HEAD | tar -x -C "$WORK/src"
cp -a "$ROOT/demo/deps/." "$WORK/src/demo/deps/" 2>/dev/null || true

echo "Starting Postgres on 127.0.0.1:$PG_PORT"
docker rm -f -v "$PG_CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$PG_CONTAINER" -p "127.0.0.1:$PG_PORT:5432" \
  -e POSTGRES_USER=ash_table -e POSTGRES_PASSWORD=ash_table -e POSTGRES_DB=demo_dev \
  "$POSTGRES_IMAGE" >/dev/null

for _ in $(seq 1 60); do
  docker exec "$PG_CONTAINER" pg_isready -U ash_table -d demo_dev >/dev/null 2>&1 && break
  sleep 1
done

export MIX_ENV=dev PORT POSTGRES_PORT="$PG_PORT" POSTGRES_HOST=localhost \
  POSTGRES_USER=ash_table POSTGRES_PASSWORD=ash_table POSTGRES_DB=demo_dev SEED=standard

echo "Setting up the demo (the first compile takes minutes)"
(cd "$WORK/src/demo" && mix setup) >"$WORK/setup.log" 2>&1 || {
  tail -50 "$WORK/setup.log"
  echo "mix setup failed." >&2
  exit 1
}

echo "Starting the demo on http://127.0.0.1:$PORT"
(cd "$WORK/src/demo" && exec setsid mix phx.server) >"$WORK/server.log" 2>&1 &
SERVER=$!

for _ in $(seq 1 120); do
  curl -fs -o /dev/null "http://127.0.0.1:$PORT/tasks" && break
  sleep 2
done
curl -fsS -o /dev/null "http://127.0.0.1:$PORT/tasks" || {
  tail -50 "$WORK/server.log"
  echo "The demo did not come up." >&2
  exit 1
}

echo "Recording"
# a clip that fails leaves the others: they are converted, and the run fails at the end
status=0
# the picture only with every clip
shot="$OUT/tasks.png"
[ $# -gt 0 ] && shot=""
(cd "$ROOT/demo/e2e" && GIFS_URL="http://127.0.0.1:$PORT" VIDEOS_DIR="$WORK/videos" SHOT="$shot" \
  CLIPS="$*" node readme-gifs.mjs) || status=$?

# GIFS_KEEP_VIDEOS=dir keeps the videos, to try other ffmpeg settings on them
[ -n "${GIFS_KEEP_VIDEOS:-}" ] && mkdir -p "$GIFS_KEEP_VIDEOS" && cp "$WORK"/videos/*.webm "$GIFS_KEEP_VIDEOS"/

echo "Converting"
for video in "$WORK"/videos/*.webm; do
  name="$(basename "$video" .webm)"
  # through stdin and stdout: Docker Desktop mounts no temporary directory.
  # hqdn3d smooths the video's flicker over time, so that what stands still
  # stays the same in the GIF: about half the size.
  docker run --rm -i "$FFMPEG_IMAGE" -loglevel error -f webm -i pipe:0 \
    -vf "fps=6,scale=800:-1:flags=lanczos,hqdn3d=0:0:20:20,split[a][b];[a]palettegen=max_colors=48:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
    -f gif pipe:1 <"$video" >"$OUT/$name.gif"
  ls -l "$OUT/$name.gif"
done
exit "$status"
