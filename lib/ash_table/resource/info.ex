defmodule AshTable.Resource.Info do
  @moduledoc """
  Introspection for the `table` block of a resource, as it was written:
  `columns/1` returns the declared columns (`AshTable.Resource.Column`),
  `relationships/1` the declared relationships
  (`AshTable.Resource.Relationship`) and `table/1` both, and there is a
  function per option, such as `table_read_action/1`. An option that was not
  given is `:error` there, unless it has a default; the other defaults are
  filled in when the table is rendered.
  """
  use Spark.InfoGenerator, extension: AshTable.Resource, sections: [:table]

  @doc "The `column`s declared in the `table` block, in the declared order."
  @spec columns(Ash.Resource.t() | Spark.Dsl.t()) :: [AshTable.Resource.Column.t()]
  def columns(resource) do
    for %AshTable.Resource.Column{} = column <- table(resource), do: column
  end

  @doc "The `relationship`s declared in the `table` block, in the declared order."
  @spec relationships(Ash.Resource.t() | Spark.Dsl.t()) :: [AshTable.Resource.Relationship.t()]
  def relationships(resource) do
    for %AshTable.Resource.Relationship{} = relationship <- table(resource), do: relationship
  end
end
