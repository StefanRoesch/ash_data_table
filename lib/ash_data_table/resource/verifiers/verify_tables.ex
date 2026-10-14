defmodule AshDataTable.Resource.Verifiers.VerifyTables do
  @moduledoc false
  # The named tables of the `tables` block: what each is called, and that
  # none declares a column, relationship, action, argument or upload twice.
  #
  # That no two tables have one name is reported by Spark, as it reports a
  # declaration made twice in the `table` block. Inside a named table it
  # reports neither (2.7.6: see the note at the entity in
  # `AshDataTable.Resource`), so that is looked at here.
  use Spark.Dsl.Verifier

  alias AshDataTable.Resource.Table
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  # a name becomes part of the table's id, and so of ids in the page and of
  # the parameters of its URL
  @name ~r/\A[a-z][a-z0-9_]*\z/

  @declarations [
    columns: {:column, :key},
    relationships: {:relationship, :name},
    actions: {:action, :name},
    arguments: {:argument, :name},
    uploads: {:upload, :name}
  ]

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    # the tables of the `tables` block alone, by whatever name
    errors =
      for %Table{} = table <- Spark.Dsl.Extension.get_entities(dsl, [:tables]),
          error <-
            name_errors(module, table) ++
              label_errors(module, table) ++ twice_errors(module, table),
          do: error

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc "Whether an atom can be the name of a named table."
  @spec name?(term) :: boolean
  def name?(name) when is_atom(name) and name not in [nil, :default, true, false],
    do: Regex.match?(@name, Atom.to_string(name))

  def name?(_other), do: false

  defp name_errors(module, %Table{name: name} = table) do
    if name?(name) do
      []
    else
      [
        DslError.exception(
          module: module,
          path: [:tables, :table, name],
          message: name_message(name),
          location: Spark.Dsl.Entity.anno(table)
        )
      ]
    end
  end

  # The path of this one says `:default`: there the name stands for the
  # default table, which a named table cannot be.
  defp name_message(:default),
    do:
      "`:default` is the name of the default table, the one of the `table` block, and no named " <>
        "table can have it. Write this table in the `table` block, or give it another name."

  defp name_message(name),
    do:
      "`#{inspect(name)}` cannot be the name of a table. A table's name is part of its id and of " <>
        "the parameters of its URL: an atom of lower-case letters, digits and `_` that starts " <>
        "with a letter, such as `:compact`."

  # `label_field` belongs to the resource: it is written in the `table`
  # block, and names the record whichever table shows it.
  defp label_errors(_module, %Table{label_field: nil}), do: []

  defp label_errors(module, %Table{label_field: field} = table) do
    [
      DslError.exception(
        module: module,
        path: [:tables, :table, table.name, :label_field],
        message:
          "`label_field` says what a record of the resource is called, whichever of its tables " <>
            "shows it, so it is no option of a named table. Write `label_field " <>
            "#{inspect(field)}` in the `table` block of the resource.",
        location: Spark.Dsl.Entity.property_anno(table, :label_field)
      )
    ]
  end

  defp twice_errors(module, table) do
    for {key, {entity, identifier}} <- @declarations,
        declared = Map.fetch!(table, key),
        names = Enum.map(declared, &Map.fetch!(&1, identifier)),
        name <- Enum.uniq(names -- Enum.uniq(names)) do
      # at the second of them
      [_first, second | _] = Enum.filter(declared, &(Map.fetch!(&1, identifier) == name))

      DslError.exception(
        module: module,
        path: [:tables, :table, table.name, entity, name],
        message:
          "The #{entity} `#{name}` is declared more than once in the table `#{inspect(table.name)}`.",
        location: Spark.Dsl.Entity.anno(second)
      )
    end
  end
end
