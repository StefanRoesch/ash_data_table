import Config
config :phx, ash_domains: [Phx.Domain]
config :ash, default_string_length_count: :codepoints
config :phoenix, :json_library, Jason

config :phx, Phx.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4877],
  server: true,
  secret_key_base: String.duplicate("a", 64),
  code_reloader: config_env() == :dev,
  debug_errors: true,
  check_origin: false
