import Config

# How Ash counts the length of a string: the library's own resources
# (`AshDataTable.Test.Resource`) are compiled here as the project's own.
config :ash, default_string_length_count: :codepoints

if config_env() == :test do
  import_config "test.exs"
end
