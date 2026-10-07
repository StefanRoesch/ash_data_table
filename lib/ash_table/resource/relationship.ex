defmodule AshTable.Resource.Relationship do
  @moduledoc """
  A `relationship` declared in a resource's `table` block.

  This is the declaration as written, as
  `AshTable.Resource.Info.relationships/1` returns it: an option that was not
  given is `nil`. The defaults are filled in when the table is rendered.
  """

  defstruct [:name, :label, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{name: atom, label: String.t() | nil}

  # The later parts of nested tables add their options here; each needs a
  # struct field above and a key below.
  @schema [
    name: [
      type: :atom,
      required: true,
      doc:
        "The relationship a row offers: a public relationship of the resource whose destination resource has a table."
    ],
    label: [
      type: :string,
      doc:
        "What the relationship is called on its line under a row. Defaults to the humanised relationship name."
    ]
  ]

  @doc false
  def schema, do: @schema
end
