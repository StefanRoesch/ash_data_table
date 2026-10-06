defmodule AshTable.Model.Column do
  @moduledoc false
  # One column of a table model: a field of the resource as the table shows it.
  #
  #   * `name` is the field's name and `kind` says what it is on the resource.
  #   * `label` is the column header.
  #   * `cell_type` is what the table shows the field's values as. Types with no
  #     cell of their own (arrays, maps, embedded resources, keys, …) are
  #     `:other` and shown as read-only text.
  #   * `type` is the field's Ash type with its constraints. What a person
  #     types into the column's filter is checked against it.
  #   * `values` holds, for an `:enum` column, each value with its label in
  #     declared order; `nil` for every other cell type.
  #   * `sortable?` says whether a person can sort by this column: what the
  #     resource allows under the table's pagination strategy, unless the block
  #     switched it off.
  #   * `operators` lists what a person can filter this column by, the default
  #     operator first: those of the cell type that Ash supports for the field.
  #     It is empty for a column without a filter: one the resource does not
  #     allow to be filtered, one of cell type `:other`, or one the block
  #     switched off. See `AshTable.Model.Operator`.
  #   * `editable?` says whether a person can edit the cells of this column in
  #     principle: the column is an attribute, the attribute is writable, an
  #     update action accepts it and its cell type has an editor. In a model
  #     from `AshTable.Model.for_actor/2` it is also `false` when the person can
  #     never run that action. Whether one cell can be edited depends on the
  #     record besides.
  #   * `update_action` is the update action an edit of this column runs, with
  #     the column's attribute as its only input: the column's own, else the
  #     table's. `nil` for a column that is not editable.
  #   * `editor` is what a cell of this column is edited with: `:text`,
  #     `:number`, `:boolean`, `:date`, `:datetime` or `:enum`. `nil` for a
  #     column that is not editable.
  #   * `confirm` is the question asked before an edit of this column is saved,
  #     or `nil` when none is.

  @enforce_keys [:name, :kind, :label, :cell_type, :sortable?, :operators]
  defstruct [
    :name,
    :kind,
    :label,
    :type,
    :cell_type,
    :values,
    :sortable?,
    :operators,
    :update_action,
    :editor,
    :confirm,
    editable?: false
  ]

  @type t :: %__MODULE__{
          name: atom,
          kind: :attribute | :calculation | :aggregate,
          label: String.t(),
          type: {Ash.Type.t() | nil, keyword},
          cell_type: :text | :number | :boolean | :date | :datetime | :enum | :other,
          values: [{atom | String.t(), String.t()}] | nil,
          sortable?: boolean,
          operators: [AshTable.Model.Operator.t()],
          editable?: boolean,
          update_action: atom | nil,
          editor: :text | :number | :boolean | :date | :datetime | :enum | nil,
          confirm: String.t() | nil
        }
end
