defmodule AshTable.Resource.Verifiers.VerifyExposure do
  @moduledoc false
  # Warnings about aggregate and calculation columns that show more than
  # their declarations suggest. Nothing here is a mistake in the `table`
  # block: the resource may mean it, which is why these are warnings, and
  # why the first kind can be answered on the column.
  #
  #   * A column that shows a field which a field policy protects, on the
  #     related resource or on this one, while no field policy protects the
  #     column itself: see `AshTable.Resource.Exposing`.
  #   * A `first` aggregate column that the table has to read apart from the
  #     row, and so cannot sort or filter by: see
  #     `AshTable.Resource.Reading.apart/2`. A column that switches both off
  #     itself has nothing to be told.
  #
  # A verifier, not a transformer: both look at other resources.
  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias AshTable.Resource.Exposing
  alias AshTable.Resource.Reading
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    # of every table of the resource, each by itself
    warnings =
      for table <- AshTable.Resource.Info.tables(dsl),
          warning <- warnings(dsl, module, table),
          do: warning

    case warnings do
      [] -> :ok
      warnings -> {:warn, Enum.map(warnings, &located/1)}
    end
  end

  defp warnings(dsl, module, table) do
    columns =
      for column <- table.columns,
          field = Info.calculation(dsl, column.name) || Info.aggregate(dsl, column.name),
          do: {column, field}

    exposed =
      for {column, field} <- columns,
          column.exposes_protected_field? != true,
          exposures = Exposing.exposures(module, field),
          exposures != [],
          do: {exposed(module, field, exposures), Spark.Dsl.Entity.anno(column)}

    apart =
      for {aggregate, calculation} <- Reading.apart(module, Enum.map(columns, &elem(&1, 1))),
          {column, field} <- columns,
          column.name == aggregate,
          # a column that says it is neither sorted nor filtered by loses nothing
          not (column.sortable? == false and column.filterable? == false),
          do: {apart(field, calculation), Spark.Dsl.Entity.anno(column)}

    exposed ++ apart
  end

  # A warning without a place in the source is the text alone.
  defp located({message, nil}), do: message
  defp located(warning), do: warning

  defp exposed(module, %Ash.Resource.Aggregate{name: name}, exposures) do
    "The aggregate column `#{name}` #{Enum.map_join(exposures, ", and ", &shown/1)}, " <>
      "and #{inspect(module)} has no field policy for `#{name}`. " <>
      "Ash applies the read policy of the related resource to an aggregate, and not its field policies: " <>
      "everyone who can read a row sees this column, and can sort and filter by it. " <>
      remedy(module, name)
  end

  defp exposed(module, %Ash.Resource.Calculation{name: name}, exposures) do
    "The calculation column `#{name}` #{Enum.map_join(exposures, ", and ", &shown/1)}, " <>
      "and #{inspect(module)} has no field policy for `#{name}`. " <>
      "Ash applies no policy to what a calculation references: " <>
      "everyone who can read a row sees this column, and can sort and filter by it. " <>
      remedy(module, name)
  end

  defp shown(%{through: :field, resource: resource, field: field}),
    do: "shows `#{field}` of #{inspect(resource)}, which a field policy protects there"

  defp shown(%{through: :filter, resource: resource, field: field}),
    do:
      "counts by `#{field}` of #{inspect(resource)} in its `filter`, which a field policy protects there"

  defp shown(%{through: [], field: field}),
    do: "references `#{field}`, which a field policy protects on this resource"

  defp shown(%{through: path, resource: resource, field: field}),
    do:
      "references `#{field}` of #{inspect(resource)} (through `#{Enum.join(path, ".")}`), which a field policy protects there"

  defp remedy(module, name) do
    "Protect it with a field policy for `#{name}` on #{inspect(module)}, which needs " <>
      "`Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, " <>
      "one that authorizes everything. If the column is meant to show this to everyone who reads " <>
      "a row, say so with `exposes_protected_field? true` on the column."
  end

  defp apart(%{name: name, relationship_path: path}, calculation) do
    "The aggregate column `#{name}` is a `first` aggregate over the one record of " <>
      "`#{Enum.join(path, ".")}`, and the calculation column `#{calculation}` reaches through the " <>
      "same relationship. Read together through a SQL data layer, such an aggregate returns the " <>
      "value of a related record that the reader may not read (ash_table issue #32). The table " <>
      "therefore reads `#{name}` apart from the rest of the row, and does not sort or filter by it. " <>
      "To have it read with the row again, and sorted and filtered by, take the aggregate out of " <>
      "the join the two share: give it a `join_filter` or a `read_action` of its own. To leave it " <>
      "at that, say `sortable? false` and `filterable? false` on the column."
  end
end
