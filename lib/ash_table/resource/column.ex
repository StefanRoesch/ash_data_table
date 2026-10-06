defmodule AshTable.Resource.Column do
  @moduledoc """
  A `column` declared in a resource's `table` block.

  This is the declaration as written. What a table actually shows, with
  defaults filled in, is an `AshTable.Model.Column`.
  """

  defstruct [:name, :label, :sortable?, :filterable?, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          sortable?: boolean | nil,
          filterable?: boolean | nil
        }

  # Later slices add their options here (`update_action`, `confirm`,
  # `component`); each needs a struct field above and a key below.
  @schema [
    name: [
      type: :atom,
      required: true,
      doc: "The field shown in this column: a public attribute, calculation or aggregate."
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
    ]
  ]

  @doc false
  def schema, do: @schema
end
