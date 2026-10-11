defmodule AshTable.Resource.Reference do
  @moduledoc """
  A `reference` declared in an `action` of a resource's `table` block: the
  resource whose records an argument of the action names by their key.

  This is the declaration as written, as the `references` of an
  `AshTable.Resource.Action` hold it.
  """

  defstruct [:name, :destination, :__spark_metadata__]

  @type t :: %__MODULE__{name: atom, destination: module}

  @schema [
    name: [
      type: :atom,
      required: true,
      doc:
        "The argument: a public argument of the action that holds the primary key of a record of `destination`, or a list of such keys."
    ],
    destination: [
      type: {:spark, Ash.Resource},
      required: true,
      doc:
        "The resource the argument's keys belong to. It has to have a table (list `AshTable.Resource`), read through a public read action, and a primary key of one attribute, of the argument's type."
    ]
  ]

  @doc false
  def schema, do: @schema
end
