# The demo in dev mode, for `docker compose --profile demo up`.
# Build context: the repository root, because the demo depends on the
# library by path ("..").
FROM elixir:1.19.4-otp-28-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential ca-certificates git inotify-tools \
  && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=dev
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /workspace
COPY . .

WORKDIR /workspace/demo
RUN mix deps.get && mix compile && mix assets.setup && mix assets.build

EXPOSE 4478

# Create and migrate the database, seed it (SEED=standard|large), then serve.
CMD ["sh", "-c", "mix ash.setup && mix run priv/repo/seeds.exs && exec mix phx.server"]
