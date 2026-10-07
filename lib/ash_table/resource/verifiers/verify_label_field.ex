defmodule AshTable.Resource.Verifiers.VerifyLabelField do
  @moduledoc false
  # The `label_field` of the block: a public attribute of the resource.
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Referencing
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    case Referencing.label_field(dsl) do
      {:error, reason} ->
        {:error,
         DslError.exception(
           module: Verifier.get_persisted(dsl, :module),
           path: [:table, :label_field],
           message: Referencing.message(reason),
           location: Spark.Dsl.Transformer.get_opt_anno(dsl, [:table], :label_field)
         )}

      _ok_or_none ->
        :ok
    end
  end
end
