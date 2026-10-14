defmodule AshDataTable.Model.Input do
  @moduledoc false
  # One input of an action as the action panel offers it: an attribute the
  # action accepts, or one of its arguments.
  #
  #   * `name` is the input's name and `kind` what it is on the action:
  #     `:attribute` or `:argument`.
  #   * `label` is what its field is called: the label of the table's column
  #     for an attribute that has one, else the humanised name.
  #   * `type` is the Ash type with its constraints; `cell_type` and `values`
  #     are what a column of that type has (see `AshDataTable.Model.Column`), and
  #     what the field's value is written with (`AshDataTable.Format.input/2`).
  #   * `editor` is the control of the field: that of a cell of its type
  #     (`:text`, `:number`, `:boolean`, `:date`, `:datetime`, `:enum`, and
  #     `:choices` or `:list` for an array, `:group` for a map cell and
  #     `:groups` for an array of them, whose `fields` are then those of
  #     the value: see `AshDataTable.Model.Field`), `:union` for a union,
  #     whose `members` are then its kinds, or
  #     `:file` for an argument that takes a file (`Ash.Type.File`), which
  #     is given by uploading one: `upload` then says what the upload is
  #     limited to (`accept`, `max_file_size`); or
  #     `:plain` for a value that is written as one line of text and has no
  #     editor of its own (a key, a time, an atom), or `:component` for an
  #     attribute whose column in this table has a component with an editor:
  #     `component` is then that column's (see `AshDataTable.Model.Column`); or
  #     `:reference` for an attribute that is the foreign key of a public
  #     belongs-to relationship whose related record can be chosen: the
  #     field shows what the chosen record is called, and a button opens the
  #     picker. `reference` then says which relationship, to which
  #     `destination`, which attribute of the chosen record is the value
  #     (`destination_attribute`), and through which read action the records
  #     on offer are read (`choose_action`). See
  #     `AshDataTable.Resource.Referencing.picking/2`.
  #
  #     An argument that a `manage_relationship` change of the action hands
  #     to a relationship as the key of a related record is a `:reference`
  #     too, and one that holds a list of such keys is `:references`: its
  #     field lists what the chosen records are called, and the picker
  #     selects any number of rows. `reference` is then as above, without a
  #     `source_attribute`: the `destination_attribute` is the attribute the
  #     argument names a record by, `several?` says which of the two it is,
  #     and `related?` whether the argument is everything the relationship
  #     is to hold, so that its field starts with the records that are
  #     related now. See `AshDataTable.Resource.Referencing.managing/1`.
  #
  #     So is an argument whose resource the `action` of the block names
  #     (`reference`): `reference` then has no `relationship` (nil), its
  #     `destination` is the named resource, and its
  #     `destination_attribute` that resource's primary key. See
  #     `AshDataTable.Resource.Referencing.declared/4`.
  #   * `required?` says whether the action takes the input empty: as the
  #     attribute and the action say (`allow_nil?`, `allow_nil_input`,
  #     `require_attributes`), or the argument (`allow_nil?`).
  #   * `default` is the value the field starts with where there is no
  #     record to take it from: the static default of the argument or of the
  #     attribute, nil when it has none or one that is computed.
  #   * `sensitive?` is what the attribute or the argument says
  #     (`AshDataTable.Sensitive`): what is typed into its field is hidden, the
  #     field starts empty whatever the record holds, and left empty it
  #     gives the action nothing. Only an input that is typed as text or as
  #     a number is ever one: a sensitive input of any other type is no
  #     input of the panel.
  #   * `partly_hidden?` is set for the person asking
  #     (`AshDataTable.Model.for_actor/2`): the input is an attribute they see
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
    :members,
    :upload,
    :editor,
    :component,
    :reference,
    :default,
    required?: false,
    partly_hidden?: false,
    sensitive?: false
  ]

  @type t :: %__MODULE__{
          name: atom,
          kind: :attribute | :argument,
          label: String.t(),
          type: {Ash.Type.t(), keyword},
          cell_type: AshDataTable.Model.CellType.t(),
          values: AshDataTable.Model.CellType.values() | nil,
          fields: [AshDataTable.Model.Field.t()] | nil,
          members: [AshDataTable.Model.Field.t()] | nil,
          upload: %{accept: :any | [String.t()], max_file_size: pos_integer} | nil,
          editor:
            AshDataTable.Resource.Editing.editor()
            | :plain
            | :file
            | :component
            | :reference
            | :references,
          component: map | nil,
          reference:
            %{
              relationship: atom | nil,
              destination: Ash.Resource.t(),
              source_attribute: atom | nil,
              destination_attribute: atom,
              allow_nil?: boolean,
              choose_action: atom,
              several?: boolean,
              related?: boolean
            }
            | nil,
          default: term,
          required?: boolean,
          partly_hidden?: boolean,
          sensitive?: boolean
        }
end
