#!/usr/bin/env bash
# Builds the demo image for linux/amd64 and linux/arm64, checks that it
# answers, and, only with --push, publishes it to ghcr.io. The image is a
# throwaway demo snapshot, not a release: it may be overwritten or deleted.
#
#   scripts/publish-demo-image.sh          # build and check, push nothing
#   scripts/publish-demo-image.sh --push   # the same, then push
#
# What it does, so that nothing else on the machine is touched:
#
#   1. Exports the committed HEAD into a temporary directory (uncommitted
#      changes are not in the image), so the tag names exactly what is in it.
#   2. Builds both platforms with `docker buildx` (a builder of its own,
#      `ash_data_table_demo`, docker-container driver), then loads the one of
#      this machine as a local image.
#   3. Starts that image with the repository's docker-compose.yml, as a
#      compose project of its own (`ash_data_table_demo_check`) with its own
#      Postgres volume, the demo on the first free port of 4490-4493 and
#      Postgres on 5490-5493 beside it; waits until /tasks answers, then
#      takes the project down with its volume.
#   4. With --push only: pushes both platforms as
#      ghcr.io/stefanroesch/ash_data_table-demo:<commit SHA> and :latest.
#
# Pushing needs a login the script never does and never stores: run
# `docker login ghcr.io -u stefanroesch --password-stdin` yourself first,
# with a token that may write packages. Building arm64 on an amd64 machine
# (or the other way round) needs QEMU's binfmt handlers, e.g.
# `docker run --privileged --rm tonistiigi/binfmt --install all`.
#
# Needs Docker with buildx, git and curl.
set -euo pipefail

IMAGE="ghcr.io/stefanroesch/ash_data_table-demo"
PLATFORMS="linux/amd64,linux/arm64"
BUILDER="ash_data_table_demo"
PROJECT="ash_data_table_demo_check"
LOCAL_TAG="ash_data_table-demo:check"

push=false
case "${1:-}" in
  "") ;;
  --push) push=true ;;
  *)
    echo "usage: $0 [--push]" >&2
    exit 2
    ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHA="$(git -C "$ROOT" rev-parse HEAD)"
WORK="$(mktemp -d)"

port_free() {
  ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

PORT=""
for n in 0 1 2 3; do
  if port_free "449$n" && port_free "549$n"; then
    PORT="449$n"
    PG_PORT="549$n"
    break
  fi
done
if [ -z "$PORT" ]; then
  echo "No free port pair in 4490-4493 / 5490-5493." >&2
  exit 1
fi

compose() {
  DEMO_IMAGE="$LOCAL_TAG" DEMO_PORT="$PORT" POSTGRES_PORT="$PG_PORT" \
    docker compose -p "$PROJECT" -f "$WORK/src/docker-compose.yml" --profile demo "$@"
}

cleanup() {
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/src"
git -C "$ROOT" archive HEAD | tar -x -C "$WORK/src"
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  echo "Note: uncommitted changes are not in the image (it is built from $SHA)."
fi

docker buildx inspect "$BUILDER" >/dev/null 2>&1 ||
  docker buildx create --name "$BUILDER" --driver docker-container >/dev/null

build() {
  # The source label links the package on ghcr.io to the repository.
  docker buildx build --builder "$BUILDER" -f "$WORK/src/demo/Dockerfile" \
    --label "org.opencontainers.image.source=https://github.com/StefanRoesch/ash_data_table" \
    --label "org.opencontainers.image.revision=$SHA" \
    "$@" "$WORK/src"
}

echo "Building $SHA for $PLATFORMS (the first build takes long)"
build --platform "$PLATFORMS"

echo "Loading the image of this machine"
build --load -t "$LOCAL_TAG"

echo "Checking the demo on http://127.0.0.1:$PORT"
compose up -d --no-build --pull never
for _ in $(seq 1 120); do
  curl -fs -o /dev/null "http://127.0.0.1:$PORT/tasks" && break
  sleep 5
done
curl -fsS -o /dev/null "http://127.0.0.1:$PORT/tasks" || {
  compose logs app | tail -50
  echo "The demo did not come up." >&2
  exit 1
}
echo "The demo answers."
compose down -v --remove-orphans >/dev/null

if [ "$push" = true ]; then
  echo "Pushing $IMAGE:$SHA and $IMAGE:latest"
  build --platform "$PLATFORMS" -t "$IMAGE:$SHA" -t "$IMAGE:latest" --push
else
  echo "Not pushed (run with --push to publish $IMAGE:$SHA and :latest)."
fi
