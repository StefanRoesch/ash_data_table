defmodule AshTable.Resource.Verifiers.VerifyRelationships do
  @moduledoc false
  # The `relationship`s of the block. A verifier, not a transformer: it looks
  # at the destination resource, which a transformer cannot do when two
  # resources point at each other (the compiler waits for both forever).
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Relating
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      for declaration <- AshTable.Resource.Info.relationships(dsl),
          {:error, reason} <- [offerable(dsl, declaration.name)] do
        DslError.exception(
          module: module,
          path: [:table, :relationship, declaration.name],
          message: Relating.message(reason),
          location: Spark.Dsl.Entity.anno(declaration)
        )
      end

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # A public relationship to a resource with a table, whose nested table
  # runs a public read action. A relationship of the default set is not
  # looked at here: one that cannot be offered is left out of it.
  defp offerable(dsl, name) do
    with {:ok, relationship} <- Relating.declared(dsl, name) do
      Relating.public_read(relationship)
    end
  end
end
