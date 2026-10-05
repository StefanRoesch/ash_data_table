# Postgres intervals are decoded to `Duration`, which `Ash.Type.Duration`
# (the kitchen sink's `a_duration`) expects.
Postgrex.Types.define(
  Demo.PostgrexTypes,
  Ecto.Adapters.Postgres.extensions(),
  interval_decode_type: Duration
)
