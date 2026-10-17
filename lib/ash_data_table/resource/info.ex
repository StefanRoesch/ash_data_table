defmodule AshDataTable.Resource.Info do
  @moduledoc """
  Introspection for the tables of a resource, as they were written.

  A resource has one default table (its `table` block, or the defaults
  where it has none) and any number of named tables (the `table`s of its
  `tables` block). `tables/1` returns all of them, the default table first,
  and `table/2` the one of a name: each an `AshDataTable.Resource.Table`, in one
  shape for both kinds, with its options and its `columns`,
  `relationships`, `actions`, `arguments` and `uploads`. `:default` names
  the default table.

  The other functions are about the default table alone: `columns/1`
  returns its declared columns (`AshDataTable.Resource.Column`),
  `relationships/1` its declared relationships
  (`AshDataTable.Resource.Relationship`), `actions/1` its declared row actions
  (`AshDataTable.Resource.Action`, each with its `references`:
  `AshDataTable.Resource.Reference`), `arguments/1` the declared arguments of
  its read action (`AshDataTable.Resource.Argument`), `uploads/1` its declared
  uploads (`AshDataTable.Resource.Upload`) and `table/1` all of them, and there
  is a function per option of the `table` block, such as
  `table_read_action/1`. `table_label_field/1` is the one that is about the
  resource whichever table shows it. An option that was not given is
  `:error` there, unless it has a default; the other defaults are filled in
  when the table is rendered.
  """
  use Spark.InfoGenerator, extension: AshDataTable.Resource, sections: [:table]

  @doc "The `column`s declared in the `table` block, in the declared order."
  @spec columns(Ash.Resource.t() | Spark.Dsl.t()) :: [AshDataTable.Resource.Column.t()]
  def columns(resource) do
    for %AshDataTable.Resource.Column{} = column <- table(resource), do: column
  end

  @doc "The `relationship`s declared in the `table` block, in the declared order."
  @spec relationships(Ash.Resource.t() | Spark.Dsl.t()) :: [
          AshDataTable.Resource.Relationship.t()
        ]
  def relationships(resource) do
    for %AshDataTable.Resource.Relationship{} = relationship <- table(resource), do: relationship
  end

  @doc "The `action`s declared in the `table` block, in the declared order: the row actions."
  @spec actions(Ash.Resource.t() | Spark.Dsl.t()) :: [AshDataTable.Resource.Action.t()]
  def actions(resource) do
    for %AshDataTable.Resource.Action{} = action <- table(resource), do: action
  end

  @doc "The `upload`s declared in the `table` block, in the declared order."
  @spec uploads(Ash.Resource.t() | Spark.Dsl.t()) :: [AshDataTable.Resource.Upload.t()]
  def uploads(resource) do
    for %AshDataTable.Resource.Upload{} = upload <- table(resource), do: upload
  end

  @doc "The `argument`s declared in the `table` block, in the declared order."
  @spec arguments(Ash.Resource.t() | Spark.Dsl.t()) :: [AshDataTable.Resource.Argument.t()]
  def arguments(resource) do
    for %AshDataTable.Resource.Argument{} = argument <- table(resource), do: argument
  end

  @doc """
  Every table of the resource: the default table first, then the named
  tables in the declared order.
  """
  @spec tables(Ash.Resource.t() | Spark.Dsl.t()) :: [AshDataTable.Resource.Table.t()]
  def tables(resource) do
    [default(resource) | named(resource)]
  end

  @doc """
  The table of that name: `:default` (or `nil`) for the default table, else
  the name of a named table. `:error` when the resource has no table of the
  name.
  """
  @spec table(Ash.Resource.t() | Spark.Dsl.t(), atom) ::
          {:ok, AshDataTable.Resource.Table.t()} | :error
  def table(resource, name) when name in [nil, :default], do: {:ok, default(resource)}

  def table(resource, name) when is_atom(name) do
    case Enum.find(named(resource), &(&1.name == name)) do
      nil -> :error
      table -> {:ok, table}
    end
  end

  @doc "As `table/2`, raising an `ArgumentError` that lists the resource's tables."
  @spec table!(Ash.Resource.t() | Spark.Dsl.t(), atom) :: AshDataTable.Resource.Table.t()
  def table!(resource, name) do
    case table(resource, name) do
      {:ok, table} -> table
      :error -> raise ArgumentError, no_table(resource, name)
    end
  end

  @doc false
  # What is said of a table that a resource does not have, wherever it is
  # named: by a relationship, in the router, where a table is placed.
  @spec no_table(Ash.Resource.t() | Spark.Dsl.t(), term) :: String.t()
  def no_table(resource, name) do
    module =
      if is_atom(resource),
        do: resource,
        else: Spark.Dsl.Verifier.get_persisted(resource, :module)

    theirs =
      case named(resource) do
        [] ->
          "It has the default table only"

        named ->
          "Its tables: #{Enum.map_join(named, ", ", &"`#{inspect(&1.name)}`")}, and the default table"
      end

    "#{inspect(module)} has no table named `#{inspect(name)}`. #{theirs}."
  end

  defp named(resource), do: Spark.Dsl.Extension.get_entities(resource, [:tables])

  # The `table` block in the shape of a named table.
  defp default(resource) do
    entities = table(resource)

    %AshDataTable.Resource.Table{
      name: :default,
      read_action: option(table_read_action(resource)),
      paginate_with: option(table_paginate_with(resource)),
      page_sizes: option(table_page_sizes(resource)),
      update_action: option(table_update_action(resource)),
      create_action: option(table_create_action(resource)),
      on_forbidden: table_on_forbidden!(resource),
      max_depth: table_max_depth!(resource),
      live?: table_live?(resource),
      sticky_label?: table_sticky_label?(resource),
      columns: for(%AshDataTable.Resource.Column{} = column <- entities, do: column),
      relationships:
        for(%AshDataTable.Resource.Relationship{} = relationship <- entities, do: relationship),
      actions: for(%AshDataTable.Resource.Action{} = action <- entities, do: action),
      arguments: for(%AshDataTable.Resource.Argument{} = argument <- entities, do: argument),
      uploads: for(%AshDataTable.Resource.Upload{} = upload <- entities, do: upload)
    }
  end

  defp option({:ok, value}), do: value
  defp option(:error), do: nil
end
