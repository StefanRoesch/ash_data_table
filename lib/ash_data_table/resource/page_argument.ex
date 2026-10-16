defmodule AshDataTable.Resource.PageArgument do
  @moduledoc """
  A `page_argument` declared in an `action` of a resource's `table` block: a
  public argument of the action that the page fills, from its
  `page_arguments`, and that the action panel never asks for.

  This is the declaration as written, as the `page_arguments` of an
  `AshDataTable.Resource.Action` hold it.
  """

  defstruct [:name, :__spark_metadata__]

  @type t :: %__MODULE__{name: atom}

  @schema [
    name: [
      type: :atom,
      required: true,
      doc:
        "The argument: a public argument of the action, other than its `record_argument`. The page gives its value in `page_arguments`; nothing a person types replaces it."
    ]
  ]

  @doc false
  def schema, do: @schema
end
