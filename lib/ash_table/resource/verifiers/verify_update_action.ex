defmodule AshTable.Resource.Verifiers.VerifyUpdateAction do
  @moduledoc false
  # The table-level `update_action`, and what editing asks of the resource as
  # a whole. A column's own `update_action` is checked with the column, in
  # `VerifyColumns`.
  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias AshTable.Resource.Editing
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    case Editing.table_action(module) do
      {:error, reason} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:table, :update_action],
           message: Editing.message(reason),
           location: Spark.Dsl.Transformer.get_opt_anno(dsl, [:table], :update_action)
         )}

      _ ->
        verify_row_refresh(dsl, module)
    end
  end

  # After a save the row is shown from the action's result, with the table's
  # calculations, aggregates and reference columns loaded onto it. Ash loads
  # those through the primary read action.
  defp verify_row_refresh(dsl, module) do
    columns =
      for column <- AshTable.Resource.Info.columns(dsl),
          field = field(module, column.name),
          do: {field, column}

    case Editing.unloadable_after_save(module, columns) do
      [] ->
        :ok

      loaded ->
        {:error,
         DslError.exception(
           module: module,
           path: [:table],
           message:
             "The table has editable columns and shows calculations, aggregates or reference columns " <>
               "(#{Enum.map_join(loaded, ", ", &"`#{&1}`")}), but the resource has no primary read action. " <>
               "After a save the row is refreshed with those fields, which Ash loads through the primary read action. " <>
               "Mark a read action `primary? true`.",
           location: Spark.Dsl.Transformer.get_section_anno(dsl, [:table])
         )}
    end
  end

  defp field(module, name) do
    Info.attribute(module, name) || Info.calculation(module, name) ||
      Info.aggregate(module, name) || Info.relationship(module, name)
  end
end
