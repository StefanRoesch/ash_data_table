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
  #     `:choices` or `:list` for an array, `:group` for a map cell and
  #     `:groups` for an array of them, whose `fields` are then those of
  #     the value: see `AshTable.Model.Field`), or
  #     `:plain` for a value that is written as one line of text and has no
  #     editor of its own (a key, a time, an atom), or `:component` for an
  #     attribute whose column in this table has a component with an editor:
  #     `component` is then that column's (see `AshTable.Model.Column`); or
  #     `:reference` for an attribute that is the foreign key of a public
  #     belongs-to relationship whose related record can be chosen: the
  #     field shows what the chosen record is called, and a button opens the
  #     picker. `reference` then says which relationship, to which
  #     `destination`, which attribute of the chosen record is the value
  #     (`destination_attribute`), and through which read action the records
  #     on offer are read (`choose_action`). See
  #     `AshTable.Resource.Referencing.picking/2`.
  #   * `required?` says whether the action takes the input empty: as the
  #     attribute and the action say (`allow_nil?`, `allow_nil_input`,
  #     `require_attributes`), or the argument (`allow_nil?`).
  #   * `default` is the value the field starts with where there is no
  #     record to take it from: the static default of the argument or of the
  #     attribute, nil when it has none or one that is computed.
  #   * `partly_hidden?` is set for the person asking
  #     (`AshTable.Model.for_actor/2`): the input is an attribute they see
  #     on some records only. On one record the table knows whether they
  #     see it there; on several at once it does not, and the input is not
  #     offered.

  @enforce_keys [:name, :kind, :label, :cell_type, :editor]
  defstruct [
    :name,
    :kind,
    :label,
    :type,
    :cell_type,
    :values,
    :fields,
    :editor,
    :component,
    :reference,
    :default,
    required?: false,
    partly_hidden?: false
  ]

  @type t :: %__MODULE__{
          name: atom,
          kind: :attribute | :argument,
          label: String.t(),
          type: {Ash.Type.t(), keyword},
          cell_type: AshTable.Model.CellType.t(),
          values: AshTable.Model.CellType.values() | nil,
          fields: [AshTable.Model.Field.t()] | nil,
          editor: AshTable.Resource.Editing.editor() | :plain | :component | :reference,
          component: map | nil,
          reference:
            %{
              relationship: atom,
              destination: Ash.Resource.t(),
              source_attribute: atom,
              destination_attribute: atom,
              allow_nil?: boolean,
              choose_action: atom
            }
            | nil,
          default: term,
          required?: boolean,
          partly_hidden?: boolean
        }
end
