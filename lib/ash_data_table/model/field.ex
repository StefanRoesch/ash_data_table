defmodule AshDataTable.Model.Field do
  @moduledoc false
  # One field of a map cell: a public attribute of an embedded resource, or
  # a field a map declares in its `fields` constraint.
  #
  #   * `name` is the field's name and `label` what it is called: its name
  #     in words, as a column of that name is called.
  #   * `type` is its Ash type with its constraints; `cell_type` and `values`
  #     are what a column of that type has (see `AshDataTable.Model.Column`), and
  #     `fields` the fields of a field that is itself a map cell, or an array
  #     of them: nil for every other field, for a map that declares none,
  #     and for an embedded resource that holds itself. `members` are the
  #     kinds of a field that is a union, or an array of them: each a field
  #     of this kind itself, named as the union names the kind, whose `tag`
  #     is what the union tells the kind by where it does (`{key, value}`:
  #     the key of a map and what it holds for this kind). Nil for every
  #     other field.
  #   * `input?` says whether a person gives the field when the value is
  #     edited: always for a field of a map, and for an attribute of an
  #     embedded resource when the actions Ash casts the value through
  #     accept it. An attribute that is shown and not given keeps what it
  #     holds, or is filled in by the resource.
  #   * `editor` is the control of an input: that of a field of the action
  #     panel (see `AshDataTable.Model.Input`), `:group` for a map cell,
  #     `:groups` for an array of them, and `:union` for a union. Nil for a
  #     field that is no input, and for one a table has no control for.
  #   * `required?` says whether the input can be left empty, and `default`
  #     is the static default a new value starts with.
  #   * `key?` is set for an attribute of an embedded resource's primary key
  #     that is no input. Ash tells by it which value of an array is which,
  #     so it is sent back with the value it came with.
  #   * `sensitive?` is what the attribute says. Such a field is shown as a
  #     mask on the value's one line, and a value with such an input is not
  #     edited in a table (`AshDataTable.Sensitive`).

  @enforce_keys [:name, :label, :type, :cell_type]
  defstruct [
    :name,
    :label,
    :type,
    :cell_type,
    :values,
    :fields,
    :members,
    :tag,
    :editor,
    :default,
    input?: false,
    required?: false,
    key?: false,
    sensitive?: false
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t(),
          type: {Ash.Type.t(), keyword},
          cell_type: AshDataTable.Model.CellType.t(),
          values: AshDataTable.Model.CellType.values() | nil,
          fields: [t] | nil,
          members: [t] | nil,
          tag: {atom | String.t(), term} | nil,
          editor: AshDataTable.Resource.Editing.editor() | :plain | nil,
          default: term,
          input?: boolean,
          required?: boolean,
          key?: boolean,
          sensitive?: boolean
        }
end
