defmodule AshTable.Model.Column do
  @moduledoc """
  One column of a table model: a field of the resource as the table shows it.

    * `name` is the field's name and `kind` says what it is on the resource.
    * `label` is the column header.
    * `cell_type` is what the table shows the field's values as. Types with no
      cell of their own (arrays, maps, embedded resources, keys, …) are
      `:other` and shown as read-only text.
    * `values` holds, for an `:enum` column, each value with its label in
      declared order; `nil` for every other cell type.
    * `sortable?` says whether a person can sort by this column: what the
      resource allows under the table's pagination strategy, unless the block
      switched it off.
  """

  @enforce_keys [:name, :kind, :label, :cell_type, :sortable?]
  defstruct [:name, :kind, :label, :cell_type, :values, :sortable?]

  @type t :: %__MODULE__{
          name: atom,
          kind: :attribute | :calculation | :aggregate,
          label: String.t(),
          cell_type: :text | :number | :boolean | :date | :datetime | :enum | :other,
          values: [{atom | String.t(), String.t()}] | nil,
          sortable?: boolean
        }
end
