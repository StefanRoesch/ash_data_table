defmodule AshTable.Model.Input do
  @moduledoc false
  # One input of an action as the action panel offers it: an attribute the
  # action accepts, or one of its arguments.
  #
  #   * `name` is the input's name and `kind` what it is on the action:
  #     `:attribute` or `:argument`.
  #   * `label` is what its field is called: the label of the table's column
  #     for an attribute that has one, else the humanised name.
  #   * `type` is the Ash type with its constraints; `cell_type` and `values`
  #     are what a column of that type has (see `AshTable.Model.Column`), and
  #     what the field's value is written with (`AshTable.Format.input/2`).
  #   * `editor` is the control of the field: that of a cell of its type
  #     (`:text`, `:number`, `:boolean`, `:date`, `:datetime`, `:enum`, and
  #     `:choices` or `:list` for an array), or
  #     `:plain` for a value that is written as one line of text and has no
  #     editor of its own (a key, a time, an atom), or `:component` for an
  #     attribute whose column in this table has a component with an editor:
  #     `component` is then that column's (see `AshTable.Model.Column`).
  #   * `required?` says whether the action takes the input empty: as the
  #     attribute and the action say (`allow_nil?`, `allow_nil_input`,
  #     `require_attributes`), or the argument (`allow_nil?`).
  #   * `default` is the value the field starts with where there is no
  #     record to take it from: the static default of the argument or of the
  #     attribute, nil when it has none or one that is computed.

  @enforce_keys [:name, :kind, :label, :cell_type, :editor]
  defstruct [
    :name,
    :kind,
    :label,
    :type,
    :cell_type,
    :values,
    :editor,
    :component,
    :default,
    required?: false
  ]

  @type t :: %__MODULE__{
          name: atom,
          kind: :attribute | :argument,
          label: String.t(),
          type: {Ash.Type.t(), keyword},
          cell_type: AshTable.Model.CellType.t(),
          values: AshTable.Model.CellType.values() | nil,
          editor: AshTable.Resource.Editing.editor() | :plain | :component,
          component: map | nil,
          default: term,
          required?: boolean
        }
end
