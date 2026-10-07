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
          {:error, reason} <- [Relating.declared(dsl, declaration.name)] do
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
end
