defmodule AshTable.Model.Action do
  @moduledoc false
  # One action a table lets a person run: a row action, run on the record of
  # a row from its button in the actions column, or the table's create action.
  #
  #   * `name` is the action's name on the resource and `type` what it is
  #     there: `:update`, `:destroy` or `:create`.
  #   * `label` is what its button says.
  #   * `confirm` is the question asked before the action runs, or `nil` when
  #     none is.
  #   * `inputs` are what the person can give it, in the action's own order:
  #     the attributes it accepts, then its arguments. See
  #     `AshTable.Model.Input`.
  #   * `link` is set on the create action of a nested table: the attribute
  #     of the row the table belongs to and the attribute of the new record
  #     that takes its value (`{source_attribute, destination_attribute}`).
  #     The table fills it in itself, so it is no input.
  #   * `panel?` says whether using the action opens the action panel, where
  #     the person gives the inputs, or runs it straight away.

  @enforce_keys [:name, :type, :label]
  defstruct [:name, :type, :label, :confirm, :link, inputs: [], panel?: false]

  @type t :: %__MODULE__{
          name: atom,
          type: :update | :destroy | :create,
          label: String.t(),
          confirm: String.t() | nil,
          link: {atom, atom} | nil,
          inputs: [AshTable.Model.Input.t()],
          panel?: boolean
        }
end
