defmodule AshTable.Resource.Verifiers.VerifyComponents do
  @moduledoc false
  # The `component` of a column. A verifier runs once every module of the
  # application is compiled, so the component's module is looked at here
  # without the resource depending on it.
  use Spark.Dsl.Verifier

  alias AshTable.Resource.Editing
  alias AshTable.Resource.Presenting
  alias AshTable.Resource.Referencing
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl) do
    module = Verifier.get_persisted(dsl, :module)

    errors =
      for %{component: component} = column when not is_nil(component) <-
            AshTable.Resource.Info.columns(dsl),
          message <- messages(column, field(dsl, column.name), module) do
        DslError.exception(
          module: module,
          path: [:table, :column, column.name, :component],
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
  defp messages(_column, nil, _module), do: []
  defp messages(_column, %{public?: false}, _module), do: []

  defp messages(column, field, module) do
    if Referencing.relationship?(field) do
      [
        "`#{column.name}` shows the label of a related record. A reference cell has no " <>
          "component: remove `component` from this column."
      ]
    else
      editable? = Editing.update_action(module, field, column) != :none
      label = column.label || AshTable.Model.humanize(column.name)

      case Presenting.component(
             column.component,
             Presenting.column(module, field, label, editable?)
           ) do
        {:ok, component} -> never_used(component, column, field, module)
        {:error, reason} -> [Presenting.message(reason)]
      end
    end
  end

  # A component with both parts is at home on a column nobody edits: its
  # editor is not used there, and its cell is. One that only edits does
  # nothing at all on such a column.
  defp never_used(%{cell?: false} = component, column, field, module) do
    case Editing.update_action(module, field, column) do
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

  defp never_used(_component, _column, _field, _module), do: []

  defp field(dsl, name) do
    Ash.Resource.Info.attribute(dsl, name) ||
      Ash.Resource.Info.calculation(dsl, name) ||
      Ash.Resource.Info.aggregate(dsl, name) ||
      Ash.Resource.Info.relationship(dsl, name)
  end
end
