defmodule AshDataTable.Model.Action do
  @moduledoc false
  # One action a table lets a person run: a row action, run on the record of
  # a row from its button in the actions column; a table action, run on the
  # table as a whole from its button on the line of the table's name; or the
  # table's create action.
  #
  #   * `name` is the action's name on the resource and `type` what it is
  #     there: `:update`, `:destroy`, `:create`, or `:action` for a generic
  #     action.
  #   * `record_argument` is set on a generic action that is a row action:
  #     the argument that takes the primary key of the row. The table fills
  #     it in itself, so it is no input.
  #   * `page_arguments` are the arguments the page fills
  #     (`page_argument`), from its `page_arguments`: no inputs either.
  #   * `returns` is set on a generic action that returns an enum value:
  #     the cell type and the values with their labels, by which the value
  #     it returned is said (`AshDataTable.Format.said/3`).
  #   * `label` is what its button says.
  #   * `confirm` is the question asked before the action runs, or `nil` when
  #     none is.
  #   * `inputs` are what the person can give it, in the action's own order:
  #     the attributes it accepts, then its arguments. See
  #     `AshDataTable.Model.Input`.
  #   * `link` is set on the create action of a nested table: the attribute
  #     of the row the table belongs to and the attribute of the new record
  #     that takes its value (`{source_attribute, destination_attribute}`).
  #     The table fills it in itself, so it is no input.
  #   * `panel?` says whether using the action opens the action panel, where
  #     the person gives the inputs, or runs it straight away.
  #   * `bulk?` says whether a row action is also offered for the rows a
  #     person has selected, to run on all of them at once.

  @enforce_keys [:name, :type, :label]
  defstruct [
    :name,
    :type,
    :label,
    :confirm,
    :link,
    :record_argument,
    :returns,
    page_arguments: [],
    inputs: [],
    panel?: false,
    bulk?: false
  ]

  @type t :: %__MODULE__{
          name: atom,
          type: :update | :destroy | :create | :action,
          label: String.t(),
          confirm: String.t() | nil,
          link: {atom, atom} | nil,
          record_argument: atom | nil,
          page_arguments: [atom],
          returns: %{cell_type: :enum, values: AshDataTable.Resource.CellType.values()} | nil,
          inputs: [AshDataTable.Model.Input.t()],
          panel?: boolean,
          bulk?: boolean
        }
end
