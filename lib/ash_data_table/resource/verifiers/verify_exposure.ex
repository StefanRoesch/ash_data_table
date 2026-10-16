defmodule AshDataTable.Resource.Verifiers.VerifyExposure do
  @moduledoc false
  # Warnings about aggregate and calculation columns that show more than
  # their declarations suggest: a column that shows a field which a field
  # policy protects, on the related resource or on this one, while no field
  # policy protects the column itself (see `AshDataTable.Resource.Exposing`).
  # Nothing here is a mistake in the `table` block: the resource may mean it,
  # which is why these are warnings, and why they can be answered on the
  # column.
  #
  # A verifier, not a transformer: both look at other resources.
  use Spark.Dsl.Verifier

  alias Ash.Resource.Info
  alias AshDataTable.Resource.Exposing
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    # of every table of the resource, each by itself
    warnings =
      for table <- AshDataTable.Resource.Info.tables(dsl),
          warning <- warnings(dsl, module, table),
          do: warning

    case warnings do
      [] -> :ok
      warnings -> {:warn, Enum.map(warnings, &located/1)}
    end
  end

  defp warnings(dsl, module, table) do
    for column <- table.columns,
        column.exposes_protected_field? != true,
        field = Info.calculation(dsl, column.name) || Info.aggregate(dsl, column.name),
        exposures = Exposing.exposures(module, field),
        exposures != [],
        do: {exposed(module, field, exposures), Spark.Dsl.Entity.anno(column)}
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
end
