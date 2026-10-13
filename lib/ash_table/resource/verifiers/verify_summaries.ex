defmodule AshTable.Resource.Verifiers.VerifySummaries do
  @moduledoc false
  # The `summary` of a column: see `AshTable.Resource.Summarising`.
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Reading
  alias AshTable.Resource.Summarising
  alias AshTable.Resource.Table
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      for table <- AshTable.Resource.Info.tables(dsl),
          %{summary: kind} = column when not is_nil(kind) <- table.columns,
          reason <- reasons(dsl, module, table, column) do
        DslError.exception(
          module: module,
          path: Table.path(table) ++ [:column, column.key, :summary],
          message: Summarising.message(reason),
          location: Spark.Dsl.Entity.property_anno(column, :summary)
        )
      end

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # What is wrong with the column itself is said first, and alone: the rest
  # says nothing new about a summary that cannot be.
  defp reasons(dsl, module, table, column) do
    case field(dsl, column.name) do
      # a column that names nothing, or nothing public: `VerifyColumns` says so
      nil ->
        []

      %{public?: false} ->
        []

      field ->
        case Summarising.column(field, column.summary) do
          {:error, reason} -> [reason]
          :ok -> of_action(module, table) ++ of_data_layer(dsl, column.summary)
        end
    end
  end

  # a read action that is not there or not usable: `VerifyReadAction` says so
  defp of_action(module, table) do
    with {:ok, action} <- Reading.read_action(module, table),
         {:error, reason} <- Summarising.action(action) do
      [reason]
    else
      _fine_or_said_elsewhere -> []
    end
  end

  defp of_data_layer(dsl, kind) do
    case Summarising.data_layer(dsl, kind) do
      :ok -> []
      {:error, reason} -> [reason]
    end
  end

  defp field(dsl, name) do
    Ash.Resource.Info.attribute(dsl, name) ||
      Ash.Resource.Info.calculation(dsl, name) ||
      Ash.Resource.Info.aggregate(dsl, name) ||
      Ash.Resource.Info.relationship(dsl, name)
  end
end
