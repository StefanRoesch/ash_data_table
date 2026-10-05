defmodule AshTable.Resource.Verifiers.VerifyColumns do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Reading
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      dsl
      |> Verifier.get_entities([:table])
      |> Enum.flat_map(&column_errors(&1, dsl, module))

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp column_errors(column, dsl, module) do
    case field(dsl, column.name) do
      nil ->
        [
          error(
            column,
            module,
            "The resource has no attribute, calculation or aggregate named `#{column.name}`."
          )
        ]

      %{public?: false} ->
        [
          error(
            column,
            module,
            "`#{column.name}` is not public. Only `public?` fields can be columns of a table."
          )
        ]

      field ->
        required_argument_errors(column, field, module) ++ sortable_errors(column, module)
    end
  end

  # A mistake in `read_action` or `paginate_with` is reported by
  # `VerifyReadAction`; without a valid one there is nothing to check here.
  defp sortable_errors(%{sortable?: true} = column, module) do
    with {:ok, action} <- Reading.read_action(module),
         {:ok, strategy} <- Reading.strategy(module, action),
         false <- Reading.sortable?(module, column.name, strategy) do
      [
        DslError.exception(
          module: module,
          path: [:table, :column, column.name, :sortable?],
          message:
            "`#{column.name}` cannot be sorted#{strategy_note(strategy)}, so `sortable? true` has no effect. `sortable?` can only switch sorting off; remove it or set it to `false`.",
          location: Spark.Dsl.Entity.property_anno(column, :sortable?)
        )
      ]
    else
      _ -> []
    end
  end

  defp sortable_errors(_column, _module), do: []

  defp strategy_note(:keyset), do: " with keyset pagination"
  defp strategy_note(_strategy), do: ""

  defp required_argument_errors(column, %Ash.Resource.Calculation{arguments: arguments}, module) do
    for %{allow_nil?: false, default: nil, name: name} <- arguments do
      error(
        column,
        module,
        "The calculation `#{column.name}` requires the argument `#{name}`. A table cannot supply arguments, so a column can only show a calculation whose arguments are optional or have defaults."
      )
    end
  end

  defp required_argument_errors(_column, _field, _module), do: []

  defp field(dsl, name) do
    Ash.Resource.Info.attribute(dsl, name) ||
      Ash.Resource.Info.calculation(dsl, name) ||
      Ash.Resource.Info.aggregate(dsl, name)
  end

  defp error(column, module, message) do
    DslError.exception(
      module: module,
      path: [:table, :column, column.name],
      message: message,
      location: Spark.Dsl.Entity.anno(column)
    )
  end
end
