defmodule AshDataTable.Resource.Transformers.Announce do
  @moduledoc false
  # A resource whose `table` block says `live? true` gets the table's
  # notifier, as a resource with GraphQL subscriptions gets ash_graphql's
  # (`AshGraphql.Resource.Transformers.Subscription`): among its simple
  # notifiers, which is where `Ash.Resource.Info.notifiers/1` finds it. The
  # host's own notifiers, and its `pub_sub` block, are left as they are.
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  # Named as an atom, not as a module, so that the transformer does not
  # depend on it (a resource's compile cycle would take it in). It is the
  # facade of `AshDataTable.Resource.Notifier` for now: what
  # `Ash.Resource.Info.notifiers/1` lists stays as it was.
  @notifier :"Elixir.AshDataTable.Notifier"

  @impl true
  def transform(dsl) do
    if Transformer.get_option(dsl, [:table], :live?, false) do
      notifiers = Transformer.get_persisted(dsl, :simple_notifiers, [])

      {:ok, Transformer.persist(dsl, :simple_notifiers, Enum.uniq([@notifier | notifiers]))}
    else
      {:ok, dsl}
    end
  end

  # Ash notes, per action, what an action selects of its record afterwards:
  # the primary key alone where the resource has no notifier. The notifier
  # reads the tenant of an attribute-multitenant record off the record, so
  # it has to be there by then.
  @impl true
  def before?(Ash.Resource.Transformers.CacheActionInputs), do: true
  def before?(_other), do: false
end
