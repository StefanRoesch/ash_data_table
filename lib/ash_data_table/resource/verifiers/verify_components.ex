defmodule AshDataTable.Resource.Verifiers.VerifyComponents do
  @moduledoc false
  # The `component` of a column. A verifier runs once every module of the
  # application is compiled, so the component's module is looked at here
  # without the resource depending on it.
  use Spark.Dsl.Verifier

  alias AshDataTable.Resource.Editing
  alias AshDataTable.Resource.Presenting
  alias AshDataTable.Resource.Referencing
  alias AshDataTable.Resource.Table
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      for table <- AshDataTable.Resource.Info.tables(dsl),
          %{component: component} = column when not is_nil(component) <- table.columns,
          message <- messages(column, field(dsl, column.name), module, table) do
        DslError.exception(
          module: module,
          path: Table.path(table) ++ [:column, column.key, :component],
          message: message,
          location: Spark.Dsl.Entity.property_anno(column, :component)
        )
      end

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # a column that names nothing, or nothing public: `VerifyColumns` says so
  defp messages(_column, nil, _module, _table), do: []
  defp messages(_column, %{public?: false}, _module, _table), do: []

  defp messages(column, field, module, table) do
    cond do
      Referencing.relationship?(field) ->
        [
          "`#{column.name}` shows the label of a related record. A reference cell has no " <>
            "component: remove `component` from this column."
        ]

      AshDataTable.Resource.Exposing.sensitive?(field) ->
        [Presenting.message({:sensitive, column.name})]

      true ->
        editable? = Editing.update_action(module, table, field, column) != :none
        label = column.label || AshDataTable.Resource.Words.humanize(column.name)

        case Presenting.component(
               column.component,
               Presenting.column(module, field, label, editable?)
             ) do
          {:ok, component} -> never_used(component, column, field, module, table)
          {:error, reason} -> [Presenting.message(reason)]
        end
    end
  end

  # A component with both parts is at home on a column nobody edits: its
  # editor is not used there, and its cell is. One that only edits does
  # nothing at all on such a column.
  defp never_used(%{cell?: false} = component, column, field, module, table) do
    case Editing.update_action(module, table, field, column) do
      {:ok, _action} ->
        []

      :none ->
        [
          "The component `#{inspect(component.module)}` only edits (it has no `cell/1`), and " <>
            "`#{column.name}` can never be edited, so the component is never used. " <>
            Editing.never_edited(Editing.obstacle(module, field))
        ]
    end
  end

  defp never_used(_component, _column, _field, _module, _table), do: []

  defp field(dsl, name) do
    Ash.Resource.Info.attribute(dsl, name) ||
      Ash.Resource.Info.calculation(dsl, name) ||
      Ash.Resource.Info.aggregate(dsl, name) ||
      Ash.Resource.Info.relationship(dsl, name)
  end
end
