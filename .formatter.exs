spark_locals_without_parens = [
  actor_assign: 1,
  authorize?: 1,
  column: 1,
  column: 2,
  confirm: 1,
  filterable?: 1,
  label: 1,
  on_forbidden: 1,
  paginate_with: 1,
  read_action: 1,
  scope_assign: 1,
  sortable?: 1,
  tenant_assign: 1,
  update_action: 1
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
