defmodule AshTable.Resource.Info do
  @moduledoc """
  Introspection for the `table` block of a resource, as it was written:
  `columns/1` returns the declared columns (`AshTable.Resource.Column`),
  `relationships/1` the declared relationships
  (`AshTable.Resource.Relationship`), `actions/1` the declared row actions
  (`AshTable.Resource.Action`), `arguments/1` the declared arguments of the
  read action (`AshTable.Resource.Argument`), `uploads/1` the declared
  uploads (`AshTable.Resource.Upload`) and `table/1` all of them, and there is a
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

  @doc "The `action`s declared in the `table` block, in the declared order: the row actions."
  @spec actions(Ash.Resource.t() | Spark.Dsl.t()) :: [AshTable.Resource.Action.t()]
  def actions(resource) do
    for %AshTable.Resource.Action{} = action <- table(resource), do: action
  end

  @doc "The `upload`s declared in the `table` block, in the declared order."
  @spec uploads(Ash.Resource.t() | Spark.Dsl.t()) :: [AshTable.Resource.Upload.t()]
  def uploads(resource) do
    for %AshTable.Resource.Upload{} = upload <- table(resource), do: upload
  end

  @doc "The `argument`s declared in the `table` block, in the declared order."
  @spec arguments(Ash.Resource.t() | Spark.Dsl.t()) :: [AshTable.Resource.Argument.t()]
  def arguments(resource) do
    for %AshTable.Resource.Argument{} = argument <- table(resource), do: argument
  end
end
