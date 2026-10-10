defmodule AshTable.Resource.Ask do
  @moduledoc """
  An `ask` declared in a `column` of a resource's `table` block: an argument
  of the column's calculation that the person gives, in the argument line.

  This is the declaration as written, as the `asks` of an
  `AshTable.Resource.Column` hold it: an option that was not given is `nil`.
  """

  defstruct [:name, :default, :label, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom,
          default: term | (map -> term) | mfa | nil,
          label: String.t() | nil
        }

  @schema [
    name: [
      type: :atom,
      required: true,
      doc: "The argument a person gives: an argument of the column's calculation."
    ],
    default: [
      type: {:or, [{:mfa_or_fun, 1}, :literal]},
      doc:
        "What the argument is while the person has chosen nothing: a value, or a function that is given the assigns of the page and returns one (`&MyApp.Defaults.currency/1`, or `{MyApp.Defaults, :currency, []}`, which is called with the assigns before its own arguments). Defaults to the default the argument has in the resource. An argument that cannot be empty has to have one of the two."
    ],
    label: [
      type: :string,
      doc:
        "What the argument's input is called in the argument line. Defaults to the column's label and the humanised argument name (\"Price in: Currency\")."
    ]
  ]

  @doc false
  def schema, do: @schema
end
