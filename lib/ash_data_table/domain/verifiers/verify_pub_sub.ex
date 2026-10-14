defmodule AshDataTable.Domain.Verifiers.VerifyPubSub do
  @moduledoc false
  # A resource that says `live? true` announces its changes through the
  # `pub_sub` its domain names: a domain with such a resource has to name
  # one.
  #
  # It is the domain that is looked at, and not the resource: a resource is
  # compiled before its domain, and cannot read the domain's block. The rule
  # and its sentence are `AshDataTable.Resource.Listening`'s, which the table
  # asks again when it is built, for a domain that does not list this
  # extension.
  use Spark.Dsl.Verifier

  alias AshDataTable.Resource.Listening
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    domain = Verifier.get_persisted(dsl, :module)

    case Verifier.get_option(dsl, [:table], :pub_sub) do
      nil ->
        errors =
          for resource <- Ash.Domain.Info.resources(dsl), Listening.announces?(resource) do
            DslError.exception(
              module: domain,
              path: [:table, :pub_sub],
              message: Listening.message({:no_pub_sub, resource, domain}),
              location: Spark.Dsl.Transformer.get_section_anno(dsl, [:table])
            )
          end

        if errors == [], do: :ok, else: {:error, errors}

      _named ->
        :ok
    end
  end
end
