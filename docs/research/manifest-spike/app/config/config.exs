import Config

synth = String.to_integer(System.get_env("SYNTH", "0"))
config :spike, synth_count: synth
config :spike, ash_domains: [Spike.Shop, Spike.Accounts] ++ if(synth > 0, do: [Spike.Synth], else: [])
config :ash, :policies, show_policy_breakdowns?: true
config :ash, default_string_length_count: :codepoints
