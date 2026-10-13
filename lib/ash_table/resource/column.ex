defmodule AshTable.Resource.Column do
  @moduledoc """
  A `column` declared in a resource's `table` block.

  This is the declaration as written, as `AshTable.Resource.Info.table/1`
  returns it: an option that was not given is `nil`. The defaults are filled
  in when the table is rendered.

  `key` is what the column is told apart by: `as` where the block says it,
  else `name`. `asks` holds the `ask`s of the column
  (`AshTable.Resource.Ask`), in the declared order.
  """

  defstruct [
    :name,
    :as,
    :key,
    :label,
    :sortable?,
    :filterable?,
    :update_action,
    :confirm,
    :component,
    :exposes_protected_field?,
    :arguments,
    :summary,
    :__identifier__,
    :__spark_metadata__,
    asks: []
  ]

  @type t :: %__MODULE__{
          name: atom,
          as: atom | nil,
          key: atom,
          label: String.t() | nil,
          sortable?: boolean | nil,
          filterable?: boolean | nil,
          update_action: atom | false | nil,
          confirm: String.t() | nil,
          component: module | nil,
          exposes_protected_field?: boolean | nil,
          arguments: keyword | nil,
          summary: :count | :sum | :avg | :min | :max | nil,
          asks: [AshTable.Resource.Ask.t()]
        }

  # A later slice adds its options here; each needs a struct field above and
  # a key below.
  @schema [
    name: [
      type: :atom,
      required: true,
      doc:
        "What is shown in this column: a public attribute, calculation or aggregate, or a public belongs-to relationship. A relationship makes the column a reference cell: it shows the related record's label, the `label_field` of the destination's table, and is neither sorted nor filtered by. It is edited by choosing another related record from the destination's table, where the column's update action accepts the relationship's foreign key."
    ],
    as: [
      type: :atom,
      doc:
        "Another name for the column, for a calculation that the table shows more than once, with other arguments: the second column of it needs a name of its own, as a calculation that is loaded twice does in Ash (`as:`). The column is sorted, filtered and kept in the URL under this name, and its header defaults to it, humanised. Not the name of a field of the resource, nor of another column."
    ],
    label: [
      type: :string,
      doc:
        "The column header. Defaults to the humanised field name (`:id` becomes \"ID\"), or to the humanised `as`."
    ],
    sortable?: [
      type: :boolean,
      doc:
        "Set to `false` to switch sorting off for this column. Defaults to what the resource allows; it cannot switch sorting on."
    ],
    filterable?: [
      type: :boolean,
      doc:
        "Set to `false` to leave this column without a filter. Defaults to what the resource allows; it cannot switch filtering on."
    ],
    update_action: [
      type: {:or, [{:literal, false}, :atom]},
      doc:
        "The update action an inline edit of this column runs, with the column's attribute as its only input; for a column that names a relationship, the relationship's foreign key. `false` makes the column read-only. Defaults to the table's `update_action`."
    ],
    confirm: [
      type: :string,
      doc: "A question asked before an inline edit of this column is saved."
    ],
    component: [
      type: :module,
      doc:
        "A module that says how the cells of this column look and what they are edited with: one that implements `AshTable.Component`, your own or one of those that are shipped (`AshTable.Components.Badge`, `AshTable.Components.Image`, `AshTable.Components.Progress`, `AshTable.Components.Slider`). It changes the look and the control only: a save still runs the column's `update_action`, and sorting, filtering and authorization are as without it. The same editor is the field of this attribute in the action panel. Not for a column that names a relationship."
    ],
    exposes_protected_field?: [
      type: :boolean,
      doc:
        "Set to `true` on an aggregate or calculation column that is meant to show everyone who reads a row what a field policy protects elsewhere: a field of the related resource that the aggregate is over or filters by, or a field the calculation references. It silences the warning the compiler gives about such a column. Ash applies no field policy of what an aggregate or a calculation is made from; the column is protected by a field policy of its own on this resource."
    ],
    arguments: [
      type: :keyword_list,
      doc:
        "The arguments the column's calculation is computed with, fixed here: `arguments currency: :eur`. For a column that names a calculation; each key an argument of it. An argument that a person is to give is declared with `ask` instead."
    ],
    summary: [
      type: {:one_of, [:count, :sum, :avg, :min, :max]},
      doc:
        "One number under the column, in a footer row of the table: over every record the table matches, not only those of the page. `:count` is the number of records that have a value in this column; `:sum` and `:avg` are for integer, float and decimal attributes; `:min` and `:max` for numbers, dates, datetimes and times. For a column that shows an attribute, not a `sensitive?` one, in a table whose read action is not manual. It counts only values the person may see; where a field policy hides the attribute from them on some records, the footer says \"–\" in place of a number. See the guide \"Footer summaries\"."
    ]
  ]

  @doc false
  def schema, do: @schema

  @doc false
  # What a column is told apart by is known once it is built: `as`, or its name.
  def transform(%__MODULE__{} = column), do: {:ok, %{column | key: column.as || column.name}}
end
