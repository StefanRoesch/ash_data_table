defmodule AshTable.Resource.Verifiers.VerifyUploads do
  @moduledoc false
  # The `upload`s of the block: each names an argument that takes a file, and
  # accepts what LiveView takes.
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Uploading
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      for declaration <- AshTable.Resource.Info.uploads(dsl),
          {option, reason} <- Uploading.mistakes(dsl, declaration) do
        DslError.exception(
          module: module,
          path: [:table, :upload, declaration.name] ++ List.wrap(option),
          message: Uploading.message(reason),
          location:
            if(option,
              do: Spark.Dsl.Entity.property_anno(declaration, option),
              else: Spark.Dsl.Entity.anno(declaration)
            )
        )
      end

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
