defmodule AshDataTable.Resource.Argument do
  @moduledoc """
  An `argument` declared in a resource's `table` block: what an argument of
  the table's read action is called in the argument line.

  This is the declaration as written, as
  `AshDataTable.Resource.Info.arguments/1` returns it: an option that was not
  given is `nil`.
  """

  defstruct [:name, :label, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{name: atom, label: String.t() | nil}

  @schema [
    name: [
      type: :atom,
      required: true,
      doc: "The argument: a public argument of the read action behind the table."
    ],
    label: [
      type: :string,
      doc:
        "What the argument's input is called in the argument line. Defaults to the humanised argument name."
    ]
  ]

  @doc false
  def schema, do: @schema
end
