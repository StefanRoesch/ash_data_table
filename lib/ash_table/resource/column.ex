defmodule AshTable.Resource.Column do
  @moduledoc """
  A `column` declared in a resource's `table` block.

  This is the declaration as written, as `AshTable.Resource.Info.table/1`
  returns it: an option that was not given is `nil`. The defaults are filled
  in when the table is rendered.
  """

  defstruct [
    :name,
    :label,
    :sortable?,
    :filterable?,
    :update_action,
    :confirm,
    :exposes_protected_field?,
    :__identifier__,
    :__spark_metadata__
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          sortable?: boolean | nil,
          filterable?: boolean | nil,
          update_action: atom | false | nil,
          confirm: String.t() | nil,
          exposes_protected_field?: boolean | nil
        }

  # Later slices add their options here (`component`); each needs a struct
  # field above and a key below.
  @schema [
    name: [
      type: :atom,
      required: true,
      doc:
        "What is shown in this column: a public attribute, calculation or aggregate, or a public belongs-to relationship. A relationship makes the column a reference cell: it shows the related record's label, the `label_field` of the destination's table, read-only, and is neither sorted nor filtered by."
    ],
    label: [
      type: :string,
      doc: "The column header. Defaults to the humanised field name (`:id` becomes \"ID\")."
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
        "The update action an inline edit of this column runs, with the column's attribute as its only input. `false` makes the column read-only. Defaults to the table's `update_action`."
    ],
    confirm: [
      type: :string,
      doc: "A question asked before an inline edit of this column is saved."
    ],
    exposes_protected_field?: [
      type: :boolean,
      doc:
        "Set to `true` on an aggregate or calculation column that is meant to show everyone who reads a row what a field policy protects elsewhere: a field of the related resource that the aggregate is over or filters by, or a field the calculation references. It silences the warning the compiler gives about such a column. Ash applies no field policy of what an aggregate or a calculation is made from; the column is protected by a field policy of its own on this resource."
    ]
  ]

  @doc false
  def schema, do: @schema
end
