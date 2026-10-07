defmodule AshTable.Resource.Action do
  @moduledoc """
  An `action` declared in a resource's `table` block: a row action.

  This is the declaration as written, as `AshTable.Resource.Info.actions/1`
  returns it: an option that was not given is `nil`. The defaults are filled
  in when the table is rendered.
  """

  defstruct [:name, :label, :confirm, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom,
          label: String.t() | nil,
          confirm: String.t() | false | nil
        }

  @schema [
    name: [
      type: :atom,
      required: true,
      doc:
        "The action a person runs on the record of a row: a public update or destroy action of the resource."
    ],
    label: [
      type: :string,
      doc: "What the action's button says. Defaults to the humanised action name."
    ],
    confirm: [
      type: {:or, [{:literal, false}, :string]},
      doc:
        "A question asked before the action runs. `false` says that the action runs without one on purpose, which silences the warning the compiler gives about a destroy action without `confirm`."
    ]
  ]

  @doc false
  def schema, do: @schema
end
