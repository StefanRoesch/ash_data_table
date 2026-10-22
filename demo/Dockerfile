# The demo in dev mode, for `docker compose --profile demo up` (the ready
# image on ghcr.io, scripts/publish-demo-image.sh) and `... up --build`.
# Build context: the repository root, because the demo depends on the
# library by path ("..").
#
# No secret goes into the image: the database settings come from the
# environment at start (compose), and the dev config's secret_key_base is
# the one committed in demo/config/dev.exs.
FROM elixir:1.19.4-otp-28-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential ca-certificates git inotify-tools nodejs npm \
  && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=dev
RUN mix local.hex --force && mix local.rebar --force

# The dependencies first, in layers of their own, so a rebuild after a code
# change skips them: the Hex and git deps (the library's path dep is only
# read for its mix.exs here and compiled with the source below), then the
# npm packages of the React islands (`ash_data_table` among them is
# `file:../..`, the root's package.json).
WORKDIR /workspace
COPY mix.exs mix.lock package.json ./
COPY demo/mix.exs demo/mix.lock demo/
COPY demo/config demo/config

WORKDIR /workspace/demo
RUN mix deps.get && mix deps.compile --skip-local-deps

COPY demo/assets/package.json demo/assets/package-lock.json assets/
# --install-links=false: Debian's npm 9 would copy the library (only its
# package.json is here yet); a symlink is filled by `COPY . .` below.
RUN cd assets && npm install --no-audit --no-fund --install-links=false

# The source. .dockerignore keeps _build, deps and node_modules out of the
# context, so the layers above stay.
WORKDIR /workspace
COPY . .

WORKDIR /workspace/demo
RUN mix compile && mix assets.setup && mix assets.build

EXPOSE 4478

# Create and migrate the database, seed it (SEED=standard|large), then serve.
CMD ["sh", "-c", "mix ash.setup && mix run priv/repo/seeds.exs && exec mix phx.server"]
