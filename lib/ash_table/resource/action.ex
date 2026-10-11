defmodule AshTable.Resource.Action do
  @moduledoc """
  An `action` declared in a resource's `table` block: a row action, or a
  table action.

  This is the declaration as written, as `AshTable.Resource.Info.actions/1`
  returns it: an option that was not given is `nil`. The defaults are filled
  in when the table is rendered.

  `references` holds the `reference`s of the action
  (`AshTable.Resource.Reference`), in the declared order.
  """

  defstruct [
    :name,
    :label,
    :confirm,
    :bulk?,
    :record_argument,
    :__identifier__,
    :__spark_metadata__,
    references: []
  ]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          confirm: String.t() | false | nil,
          bulk?: boolean | nil,
          record_argument: atom | nil,
          references: [AshTable.Resource.Reference.t()]
        }

  @schema [
    name: [
      type: :atom,
      required: true,
      doc:
        "The action a person runs: a public update or destroy action of the resource, which runs on the record of a row, or a public generic action, which runs on the table as a whole."
    ],
    label: [
      type: :string,
      doc: "What the action's button says. Defaults to the humanised action name."
    ],
    confirm: [
      type: {:or, [{:literal, false}, :string]},
      doc:
        "A question asked before the action runs. `false` says that the action runs without one on purpose, which silences the warning the compiler gives about a destroy action without `confirm`."
    ],
    bulk?: [
      type: :boolean,
      doc:
        "Whether the action is also offered for the rows a person has selected, to run on all of them at once. Defaults to `true` for every action that can: one that accepts no attribute of which two records cannot hold the same value. `false` leaves it an action of one row; it can only switch off. A generic action without `record_argument` runs on no row, and has nothing to switch off."
    ],
    record_argument: [
      type: :atom,
      doc:
        "For a generic action: the argument that is given the primary key of a row. The action is then a row action: its button stands in every row, the argument is filled in by the table and not asked for, and the action's other arguments are asked for in the action panel. The argument has to be public and of the type of the resource's primary key, which has to be one attribute."
    ]
  ]

  @doc false
  def schema, do: @schema
end
