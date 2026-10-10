defmodule AshTable.Component.Column do
  @moduledoc """
  What a component is told about the column it is used on: what the resource
  knows about the field, and what the table calls it. It is the `column`
  assign of `c:AshTable.Component.cell/1` and `c:AshTable.Component.editor/1`,
  and what `c:AshTable.Component.verify/1` is asked about.

    * `name` - the name of the field: an attribute, a calculation or an
      aggregate of the resource.
    * `label` - the column's header, in the language of the person reading.
    * `type` - the field's Ash type, as a module: `Ash.Type.Integer`, or the
      resource's own `Ash.Type.Enum`. An array is `{:array, module}`.
    * `constraints` - the constraints of that type, as the resource declares
      them: `[min: 0, max: 100]` for a bounded number, `[max_length: 40]`
      for a string, `[one_of: [...]]` for an atom. Empty for an aggregate.
    * `cell_type` - what the table shows the field as: `:text`, `:number`,
      `:boolean`, `:date`, `:datetime`, `:enum`; `:map` for a value made of
      fields (an embedded resource, a map); `:union` for a union, whose
      value is then an `Ash.Union`; `{:array, item}` for an array
      of values of one of those, as `{:array, :text}`; or `:other`
      for everything a table has no cell of its own for.
    * `values` - for an `:enum` and for an array of enum values, each value
      with its label, in declared order and in the language of the person
      reading; `nil` otherwise.
    * `editable?` - whether this person can edit cells of the column at all.
      Whether one cell can be edited depends on its record besides.
  """

  @enforce_keys [:name, :label, :type, :cell_type]
  defstruct [:name, :label, :type, :cell_type, :values, constraints: [], editable?: false]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t(),
          type: Ash.Type.t() | nil,
          constraints: keyword,
          cell_type:
            :text
            | :number
            | :boolean
            | :date
            | :datetime
            | :enum
            | :map
            | :union
            | {:array, :text | :number | :boolean | :date | :datetime | :enum | :map | :union}
            | :other,
          values: [{atom | String.t(), String.t()}] | nil,
          editable?: boolean
        }
end
