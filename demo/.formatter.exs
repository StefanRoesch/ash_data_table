[
  import_deps: [
    :ash_data_table,
    :ash_phoenix,
    :ash_postgres,
    :ash,
    :ash_csv_interchange,
    :reactor,
    :ecto,
    :ecto_sql,
    :phoenix
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "{e2e,perf}/server/**/*.{ex,exs}",
    "priv/*/seeds.exs"
  ]
]
