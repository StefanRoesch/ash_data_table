defmodule AshDataTable.Resource.Verifiers.VerifyLabelField do
  @moduledoc false
  # The `label_field` of the block: a public attribute of the resource. And
  # `sticky_label?` of every table: there is a label column to keep in view.
  use Spark.Dsl.Verifier

  alias AshDataTable.Resource.Info
  alias AshDataTable.Resource.Referencing
  alias AshDataTable.Resource.Table
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    case Referencing.label_field(dsl) do
      {:error, reason} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:table, :label_field],
           message: Referencing.message(reason),
           location: Spark.Dsl.Transformer.get_opt_anno(dsl, [:table], :label_field)
         )}

      _ok_or_none ->
        sticky(dsl, module)
    end
  end

  defp sticky(dsl, module) do
    errors =
      for table <- Info.tables(dsl),
          {:error, reason} <- [Referencing.sticky_label(dsl, table)] do
        DslError.exception(
          module: module,
          path: Table.path(table) ++ [:sticky_label?],
          message: Referencing.message(reason),
          location: Table.option_anno(dsl, table, :sticky_label?)
        )
      end

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
