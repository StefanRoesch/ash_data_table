defmodule AshDataTable.Model.Column do
  @moduledoc false
  # One column of a table model: a field of the resource as the table shows it.
  #
  #   * `name` is what the column is told apart by, and `field` the name of
  #     the resource's field it shows. They are the same but for a column
  #     with `as`: the second column of a calculation, whose values Ash puts
  #     under that name among the record's `calculations`.
  #   * `fixed` holds the arguments the block fixes for a calculation
  #     column, and `arguments` everything the calculation is computed with:
  #     those, and the asked ones once `AshDataTable.Model.supply/2` has put
  #     them in. The column is loaded, sorted and filtered with them.
  #   * `kind` says what the field is on the resource.
  #     A `:reference` column is named after a belongs-to relationship and
  #     shows the related record's label: `reference` then says which
  #     relationship, to which `destination`, which of its attributes is the
  #     label (`label_field`), and the read action Ash loads the related
  #     record through. `type`, `cell_type` and `values` are those of the
  #     label. Such a column is never sorted or filtered by. It is edited by
  #     choosing another record of the destination's table: `reference`
  #     then also says which attribute an edit changes (`source_attribute`,
  #     the foreign key), which attribute of the related record is its value
  #     (`destination_attribute`), whether "none" can be chosen
  #     (`allow_nil?`), and through which read action the records on offer
  #     are read (`choose_action`; nil for a column nobody edits). What the
  #     column's action is given is the foreign key, unless `argument` names
  #     an argument of the action that hands the chosen record to the
  #     relationship; either way its value is the chosen record's
  #     `value_attribute`.
  #   * `label` is the column header.
  #   * `cell_type` is what the table shows the field's values as. An array
  #     of values that have a cell type is `{:array, item}`. A value of
  #     named fields (an embedded resource, a map) is `:map`, and a value
  #     that is one of several kinds `:union`. Types with no cell of their
  #     own (keys, …, and the arrays of those) are `:other` and shown as
  #     read-only text.
  #   * `fields` holds, for a map cell and for an array of them, the fields
  #     of the value (`AshDataTable.Model.Field`): the public attributes of an
  #     embedded resource, or the fields a map declares. Nil for a map that
  #     declares none, which shows whatever it holds, and for every other
  #     cell type.
  #   * `members` holds, for a union and for an array of them, the kinds of
  #     the value (`AshDataTable.Model.Field`, one per kind). Nil for every
  #     other cell type.
  #   * `type` is the field's Ash type with its constraints. What a person
  #     types into the column's filter is checked against it.
  #   * `values` holds, for an `:enum` column and for an array of enum
  #     values, each value with its label in declared order; `nil` for every
  #     other cell type.
  #   * `sortable?` says whether a person can sort by this column: what the
  #     resource allows under the table's pagination strategy, unless the block
  #     switched it off.
  #   * `operators` lists what a person can filter this column by, the default
  #     operator first: those of the cell type that Ash supports for the field.
  #     It is empty for a column without a filter: one the resource does not
  #     allow to be filtered, one of cell type `:other`, an array, a map
  #     cell, a union, or one the block switched off. See `AshDataTable.Resource.Operator`.
  #   * `takes` says, by each of `operators`, what a person gives it: `:none`,
  #     `:one` value, `:many` of the column's values, or the two ends of a
  #     `:range` (`AshDataTable.Resource.Operator.takes/1`). The controls of the
  #     column's filter follow from it.
  #   * `editable?` says whether a person can edit the cells of this column in
  #     principle: the column is an attribute, the attribute is writable, an
  #     update action accepts it and its cell type has an editor; or it is a
  #     reference column whose related record can be chosen, and an update
  #     action accepts the foreign key or takes the record through an
  #     argument. In a model
  #     from `AshDataTable.Model.for_actor/2` it is also `false` when the person can
  #     never run that action. Whether one cell can be edited depends on the
  #     record besides.
  #   * `update_action` is the update action an edit of this column runs, with
  #     the column's attribute as its only input (for a reference column,
  #     the foreign key, or the argument that takes the related record): the
  #     column's own, else the table's. `nil` for a column that is not
  #     editable.
  #   * `editor` is what a cell of this column is edited with: `:text`,
  #     `:number`, `:boolean`, `:date`, `:datetime` or `:enum`, in the cell;
  #     for an array `:choices` (one checkbox per value of an enum) or
  #     `:list` (one control per value), which are edited in the side panel;
  #     `:group` for a map cell and `:groups` for an array of them, edited
  #     there field by field; `:union` for a union, edited there too, kind
  #     first (`AshDataTable.Model.in_panel?/1`);
  #     `:component` for a column whose component has
  #     an editor; or `:reference` for a reference column, which is edited
  #     in the picker. `nil` for a column that is not editable.
  #   * `required?` says whether an edit can leave the cell empty: as the
  #     attribute and the column's update action say (`allow_nil?`,
  #     `require_attributes`), which is how an input of the action panel is
  #     told. `false` for a column that is not editable, and for a reference
  #     column, whose `reference` says whether "none" can be chosen.
  #   * `component`, `max_lines` and `sticky_label?` (the table's, on the
  #     model) are presentation hints: what the parts draw with, which the
  #     core passes on and never reads (target.md 6, F3; the design note of
  #     stage 7, D14; `test/architecture_test.exs`), but `Live.Core.in_words/1`,
  #     which puts the words of a component's column into it. `editor` is no
  #     hint: it says how a value is given and written.
  #   * `component` is the column's component, nil when the block names
  #     none: its `module`, which of the two parts it has (`cell?`,
  #     `editor?`), when its editor saves (`commit`: `:enter` or `:change`),
  #     and `column`, the `AshDataTable.Component.Column` it is told about the
  #     column, which is all it is told. A reference column has none. See
  #     `AshDataTable.Resource.Presenting`.
  #   * `confirm` is the question asked before an edit of this column is saved,
  #     or `nil` when none is.
  #   * `sensitive?` is `true` for a column of a field the resource declares
  #     `sensitive?`: an attribute, a calculation or an aggregate. Its cells
  #     show a mask, the same for every value, and the value of one cell
  #     when a person asks for it; it is neither sorted nor filtered by,
  #     has no component, and its editor hides what is typed. See
  #     `AshDataTable.Sensitive`.
  #   * `summary` is the kind of the column's summary, the number under the
  #     column in the table's footer row (`:count`, `:sum`, `:avg`, `:min` or
  #     `:max`), or nil for a column without one. Only ever on a column of
  #     an attribute that is not `sensitive?`: see
  #     `AshDataTable.Resource.Summarising`. The number is asked for with
  #     `AshDataTable.Query.summaries/4`.
  #   * `max_lines` is how many lines a cell of this column shows at most:
  #     1 unless the block says more (`max_lines`), which it can for a
  #     column that is shown as text. See `AshDataTable.Resource.Presenting`.
  #   * `partly_hidden?` is only ever `true` in a model from
  #     `AshDataTable.Model.for_actor/2`: the person sees the field on some records
  #     and not on others.

  @enforce_keys [:name, :kind, :label, :cell_type, :sortable?, :operators]
  defstruct [
    :name,
    :field,
    :kind,
    :label,
    :type,
    :cell_type,
    :values,
    :fields,
    :members,
    :sortable?,
    :operators,
    :update_action,
    :editor,
    :confirm,
    :component,
    :reference,
    :summary,
    editable?: false,
    required?: false,
    partly_hidden?: false,
    sensitive?: false,
    max_lines: 1,
    fixed: %{},
    arguments: %{},
    takes: %{}
  ]

  @type t :: %__MODULE__{
          name: atom,
          field: atom,
          fixed: %{optional(atom) => term},
          arguments: %{optional(atom) => term},
          kind: :attribute | :calculation | :aggregate | :reference,
          label: String.t(),
          type: {Ash.Type.t() | nil, keyword},
          cell_type: AshDataTable.Resource.CellType.t(),
          values: [{atom | String.t(), String.t()}] | nil,
          fields: [AshDataTable.Model.Field.t()] | nil,
          members: [AshDataTable.Model.Field.t()] | nil,
          sortable?: boolean,
          operators: [AshDataTable.Resource.Operator.t()],
          takes: %{optional(AshDataTable.Resource.Operator.t()) => :none | :one | :many | :range},
          editable?: boolean,
          required?: boolean,
          update_action: atom | nil,
          editor: AshDataTable.Resource.Editing.editor() | :component | :reference | nil,
          component: AshDataTable.Resource.Presenting.component() | nil,
          confirm: String.t() | nil,
          reference:
            %{
              relationship: atom,
              destination: Ash.Resource.t(),
              label_field: atom,
              read_action: atom,
              source_attribute: atom,
              destination_attribute: atom,
              allow_nil?: boolean,
              choose_action: atom | nil,
              argument: atom | nil,
              value_attribute: atom
            }
            | nil,
          summary: AshDataTable.Resource.Summarising.kind() | nil,
          partly_hidden?: boolean,
          sensitive?: boolean,
          max_lines: pos_integer
        }

  # What a record holds for a column. For a reference column that is the
  # label of the related record, as Ash loaded it for this person:
  #
  #   * nil where there is no related record, and where there is one that is
  #     not theirs to read. Ash gives nil for both, so the cell is empty for
  #     both, and nothing in it tells the two apart;
  #   * an `Ash.ForbiddenField` where they may read the related record and
  #     not its label, or where the read of the destination was refused as a
  #     whole: the cell of a hidden field.
  @doc false
  def value(%{kind: :reference, name: name, reference: %{label_field: label}}, record) do
    case Map.get(record, name) do
      %Ash.ForbiddenField{} = hidden -> hidden
      %Ash.NotLoaded{} = not_loaded -> not_loaded
      %_{} = related -> Map.get(related, label)
      nil -> nil
    end
  end

  # The second column of a calculation is loaded under its own name, and
  # Ash puts what is loaded so among the record's `calculations`: the value,
  # or what stands for one the person may not see.
  def value(%{kind: :calculation, name: name, field: field}, record) when name != field,
    do: Map.get(record.calculations, name, %Ash.NotLoaded{field: field, type: :calculation})

  def value(column, record), do: Map.get(record, column.name)
end
