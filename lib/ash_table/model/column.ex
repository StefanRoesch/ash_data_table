defmodule AshTable.Model.Column do
  @moduledoc false
  # One column of a table model: a field of the resource as the table shows it.
  #
  #   * `name` is the field's name and `kind` says what it is on the resource.
  #     A `:reference` column is named after a belongs-to relationship and
  #     shows the related record's label: `reference` then says which
  #     relationship, to which `destination`, which of its attributes is the
  #     label (`label_field`), and the read action Ash loads the related
  #     record through. `type`, `cell_type` and `values` are those of the
  #     label. Such a column is never sorted or filtered by, and never
  #     edited.
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
  #     `:number`, `:boolean`, `:date`, `:datetime` or `:enum`, or
  #     `:component` for a column whose component has an editor. `nil` for a
  #     column that is not editable.
  #   * `component` is the column's component, nil when the block names
  #     none: its `module`, which of the two parts it has (`cell?`,
  #     `editor?`), when its editor saves (`commit`: `:enter` or `:change`),
  #     and `column`, the `AshTable.Component.Column` it is told about the
  #     column, which is all it is told. A reference column has none. See
  #     `AshTable.Resource.Presenting`.
  #   * `confirm` is the question asked before an edit of this column is saved,
  #     or `nil` when none is.
  #   * `apart?` is `true` for an aggregate that is read in a step of its
  #     own, apart from everything else a row shows, and is then neither
  #     sorted nor filtered by: see `AshTable.Resource.Reading.apart/2`.
  #   * `partly_hidden?` is only ever `true` in a model from
  #     `AshTable.Model.for_actor/2`: the person sees the field on some records
  #     and not on others.

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
    :component,
    :reference,
    editable?: false,
    apart?: false,
    partly_hidden?: false
  ]

  @type t :: %__MODULE__{
          name: atom,
          kind: :attribute | :calculation | :aggregate | :reference,
          label: String.t(),
          type: {Ash.Type.t() | nil, keyword},
          cell_type: :text | :number | :boolean | :date | :datetime | :enum | :other,
          values: [{atom | String.t(), String.t()}] | nil,
          sortable?: boolean,
          operators: [AshTable.Model.Operator.t()],
          editable?: boolean,
          update_action: atom | nil,
          editor: :text | :number | :boolean | :date | :datetime | :enum | :component | nil,
          component: AshTable.Resource.Presenting.component() | nil,
          confirm: String.t() | nil,
          reference:
            %{
              relationship: atom,
              destination: Ash.Resource.t(),
              label_field: atom,
              read_action: atom
            }
            | nil,
          apart?: boolean,
          partly_hidden?: boolean
        }
end
