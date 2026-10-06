spark_locals_without_parens = [
  column: 1,
  column: 2,
  filterable?: 1,
  label: 1,
  paginate_with: 1,
  read_action: 1,
  sortable?: 1
]

[
  import_deps: [:ash, :spark, :phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [ash_table: 2, ash_table: 3] ++ spark_locals_without_parens,
  export: [
    locals_without_parens: [ash_table: 2, ash_table: 3] ++ spark_locals_without_parens
  ]
]
