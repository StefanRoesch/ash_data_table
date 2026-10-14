defmodule AshTable.Resource.Verifiers.VerifyRelationships do
  @moduledoc false
  # The `relationship`s of the block. A verifier, not a transformer: it looks
  # at the destination resource, which a transformer cannot do when two
  # resources point at each other (the compiler waits for both forever).
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Relating
  alias AshTable.Resource.Table
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      for table <- AshTable.Resource.Info.tables(dsl),
          declaration <- table.relationships,
          {:error, reason} <- [offerable(dsl, declaration)] do
        DslError.exception(
          module: module,
          path: Table.path(table) ++ [:relationship, declaration.name],
          message: Relating.message(reason),
          location: Spark.Dsl.Entity.anno(declaration)
        )
      end

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # A public relationship to a resource with a table, and with the table
  # that the declaration names, whose nested table runs a public read
  # action that allows the page sizes that table offers. A relationship of the default set is not looked at here: one
  # that cannot be offered is left out of it.
  defp offerable(dsl, declaration) do
    with {:ok, relationship} <- Relating.declared(dsl, declaration),
         :ok <- Relating.public_read(relationship, Relating.nested(declaration)) do
      Relating.page_sizes(relationship, Relating.nested(declaration))
    end
  end
end
