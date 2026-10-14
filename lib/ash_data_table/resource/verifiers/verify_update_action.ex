defmodule AshDataTable.Resource.Verifiers.VerifyUpdateAction do
  @moduledoc false
  # The table-level `update_action`, and what editing asks of the resource as
  # a whole. A column's own `update_action` is checked with the column, in
  # `VerifyColumns`.
  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias AshDataTable.Resource.Editing
  alias AshDataTable.Resource.Table
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      for table <- AshDataTable.Resource.Info.tables(dsl),
          error <- errors(dsl, module, table),
          do: error

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp errors(dsl, module, table) do
    case Editing.table_action(module, table) do
      {:error, reason} ->
        [
          DslError.exception(
            module: module,
            path: Table.path(table) ++ [:update_action],
            message: Editing.message(reason),
            location: Table.option_anno(dsl, table, :update_action)
          )
        ]

      _ ->
        row_refresh_errors(dsl, module, table)
    end
  end

  # After a save the row is shown from the action's result, with the table's
  # calculations, aggregates and reference columns loaded onto it. Ash loads
  # those through the primary read action.
  defp row_refresh_errors(dsl, module, table) do
    columns =
      for column <- table.columns,
          field = field(module, column.name),
          do: {field, column}

    case Editing.unloadable_after_save(module, table, columns) do
      [] ->
        []

      loaded ->
        [
          DslError.exception(
            module: module,
            path: Table.path(table),
            message:
              "The table has editable columns and shows calculations, aggregates or reference columns " <>
                "(#{Enum.map_join(loaded, ", ", &"`#{&1}`")}), but the resource has no primary read action. " <>
                "After a save the row is refreshed with those fields, which Ash loads through the primary read action. " <>
                "Mark a read action `primary? true`.",
            location: Table.anno(dsl, table)
          )
        ]
    end
  end

  defp field(module, name) do
    Info.attribute(module, name) || Info.calculation(module, name) ||
      Info.aggregate(module, name) || Info.relationship(module, name)
  end
end
