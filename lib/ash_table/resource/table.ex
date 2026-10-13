defmodule AshTable.Resource.Table do
  @moduledoc """
  One table of a resource, as it was written: the default table (the `table`
  block) or a named table (a `table` of the `tables` block).

  This is what `AshTable.Resource.Info.table/2` and
  `AshTable.Resource.Info.tables/1` return, in one shape for both kinds:
  `name` is `:default` for the default table. An option that was not given is
  `nil`, unless it has a default (`on_forbidden`, `max_depth`); the other
  defaults are filled in when the table is rendered. `columns`,
  `relationships`, `actions`, `arguments` and `uploads` are the declarations
  of the table, each in the declared order.

  What a record is called (`label_field`) is not here: it belongs to the
  resource, is written in the default `table` block, and is read with
  `AshTable.Resource.Info.table_label_field/1`. The field `label_field` of
  this struct only holds what a named table wrote there by mistake, which
  is reported when the resource is compiled; it is nil otherwise.
  """

  defstruct [
    :name,
    :read_action,
    :paginate_with,
    :update_action,
    :create_action,
    :label_field,
    :__identifier__,
    :__spark_metadata__,
    on_forbidden: :not_found,
    max_depth: 3,
    columns: [],
    relationships: [],
    actions: [],
    arguments: [],
    uploads: []
  ]

  @type t :: %__MODULE__{
          name: atom,
          read_action: atom | nil,
          paginate_with: :offset | :keyset | nil,
          update_action: atom | nil,
          create_action: atom | nil,
          on_forbidden: :not_found | :message,
          max_depth: non_neg_integer,
          columns: [AshTable.Resource.Column.t()],
          relationships: [AshTable.Resource.Relationship.t()],
          actions: [AshTable.Resource.Action.t()],
          arguments: [AshTable.Resource.Argument.t()],
          uploads: [AshTable.Resource.Upload.t()]
        }

  # The options every table has, the default one and a named one alike.
  @options [
    read_action: [
      type: :atom,
      doc:
        "The read action behind the table: a `public?` read action. Defaults to the resource's primary read action, which then has to be `public?` too."
    ],
    paginate_with: [
      type: {:one_of, [:offset, :keyset]},
      doc:
        "The pagination strategy. Defaults to `:offset` if the read action supports it, else `:keyset`."
    ],
    update_action: [
      type: :atom,
      doc:
        "The update action behind inline editing: every column whose attribute this action accepts becomes editable. Without it, and without an `update_action` on a column, the table is read-only."
    ],
    create_action: [
      type: :atom,
      doc:
        "The create action behind the table's create button: a public create action of the resource. The button opens the action panel with the action's inputs, and the new record is shown as the first row of the page. Without it the table has no create button."
    ],
    on_forbidden: [
      type: {:one_of, [:not_found, :message]},
      default: :not_found,
      doc:
        "What a person is shown whose read the resource refuses outright. `:not_found` answers as if the page did not exist (404); `:message` shows a \"not allowed\" message in place of the rows."
    ],
    max_depth: [
      type: :non_neg_integer,
      default: 3,
      doc:
        "How deep a person can expand rows into nested tables, counted from the table on the page: its own nested tables are at depth 1. The tables at this depth have no expanders. It is the setting of the table on the page that counts for everything beneath it; `0` means the rows of this table never expand, wherever the table is shown."
    ]
  ]

  @name [
    name: [
      type: :atom,
      required: true,
      doc:
        "What the table is called: an atom of lower-case letters, digits and `_` that starts with a letter, and no other table of the resource has. It is what a `relationship` of another table (`table :compact`), the router (`table: :compact`) and `AshTable.table/1` (`table={:compact}`) name the table by, and it is part of the table's default id. `:default` is the name of the default table, and cannot be given to another."
    ]
  ]

  @doc false
  def options, do: @options

  # No option of a named table. It is taken all the same, and not shown in
  # the reference, so that writing it there is answered with where it
  # belongs (`VerifyTables`), and not with "undefined function".
  @misplaced [
    label_field: [
      type: :any,
      hide: true,
      doc: "Not an option of a named table: `label_field` is written in the `table` block."
    ]
  ]

  @doc false
  def schema, do: @name ++ @options ++ @misplaced

  @doc false
  # Where a table is in the DSL, for the path of a diagnostic.
  @spec path(t) :: [atom]
  def path(%__MODULE__{name: :default}), do: [:table]
  def path(%__MODULE__{name: name}), do: [:tables, :table, name]

  @doc false
  # Where the table was written: the `table` block, or the `table` of the
  # `tables` block.
  @spec anno(Spark.Dsl.t(), t) :: :erl_anno.anno() | nil
  def anno(dsl, %__MODULE__{name: :default}),
    do: Spark.Dsl.Transformer.get_section_anno(dsl, [:table])

  def anno(_dsl, %__MODULE__{} = table), do: Spark.Dsl.Entity.anno(table)

  @doc false
  # Where an option of the table was written.
  @spec option_anno(Spark.Dsl.t(), t, atom) :: :erl_anno.anno() | nil
  def option_anno(dsl, %__MODULE__{name: :default}, option),
    do: Spark.Dsl.Transformer.get_opt_anno(dsl, [:table], option)

  def option_anno(_dsl, %__MODULE__{} = table, option),
    do: Spark.Dsl.Entity.property_anno(table, option)

  @doc false
  # The table in words, for a message: "the table" and "the table `:compact`".
  @spec in_words(t | atom) :: String.t()
  def in_words(%__MODULE__{name: name}), do: in_words(name)
  def in_words(:default), do: "the table"
  def in_words(name), do: "the table `#{inspect(name)}`"
end
