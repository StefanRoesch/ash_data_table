# Empties the database and seeds it again; safe to repeat.
#
#     mix run priv/repo/seeds.exs               # the standard profile
#     SEED=large mix run priv/repo/seeds.exs    # about 50,000 tasks
#
# See Demo.Seeds for what each profile contains.

# Thousands of logged inserts are noise.
Logger.configure(level: :info)

Demo.Seeds.run(Demo.Seeds.profile_from_env())
