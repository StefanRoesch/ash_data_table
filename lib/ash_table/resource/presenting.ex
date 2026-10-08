defmodule AshTable.Resource.Presenting do
  @moduledoc false
  # What the `component` of a column is: the module, which of the two parts
  # it has and when its editor saves. Shared by the verifier (which reports
  # a mistake) and the table model (which builds on the answer).
  #
  # The module is looked at when it is asked about, never when the resource
  # is compiled: the resource does not depend on it.

  alias AshTable.Component.Column
  alias AshTable.Model.CellType

  @type reason ::
          {:not_found, module}
          | {:not_a_component, module}
          | {:no_part, module}
          | {:unsuitable, module, atom, String.t()}

  @typedoc """
  A column's component: its module, which of the two parts it has, when its
  editor saves, and what it is told about the column.
  """
  @type component :: %{
          module: module,
          cell?: boolean,
          editor?: boolean,
          commit: :enter | :change,
          column: Column.t()
        }

  @doc """
  What a component is told about a column: what the resource knows about
  its field, with the column's label and whether it can ever be edited.
  """
  @spec column(Ash.Resource.t(), struct, String.t(), boolean) :: Column.t()
  def column(resource, field, label, editable?) do
    {type, constraints} = CellType.type(resource, field)
    {cell_type, values} = CellType.classify(type, constraints)

    %Column{
      name: field.name,
      label: label,
      type: type && Ash.Type.get_type(type),
      constraints: constraints,
      cell_type: cell_type,
      values: values,
      editable?: editable?
    }
  end

  @doc """
  The component a column names, for the column it is told about, or what is
  wrong with it: no such module, not a component, or one that says that it
  cannot serve this column (`c:AshTable.Component.verify/1`).
  """
  @spec component(module, Column.t()) :: {:ok, component} | {:error, reason}
  def component(module, %Column{} = column) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, module} ->
        cond do
          not Spark.implements_behaviour?(module, AshTable.Component) ->
            {:error, {:not_a_component, module}}

          not function_exported?(module, :cell, 1) and not function_exported?(module, :editor, 1) ->
            {:error, {:no_part, module}}

          true ->
            with :ok <- suitable(module, column) do
              {:ok,
               %{
                 module: module,
                 cell?: function_exported?(module, :cell, 1),
                 editor?: function_exported?(module, :editor, 1),
                 commit: commit(module),
                 column: column
               }}
            end
        end

      {:error, _reason} ->
        {:error, {:not_found, module}}
    end
  end

  # What the component itself says about the column, if it says anything.
  defp suitable(module, column) do
    if function_exported?(module, :verify, 1) do
      case module.verify(column) do
        :ok ->
          :ok

        {:error, message} when is_binary(message) ->
          {:error, {:unsuitable, module, column.name, message}}
      end
    else
      :ok
    end
  end

  # When the editor saves. A module that implements the behaviour by hand
  # need not say: on Enter or on leaving, as a typed value is.
  defp commit(module) do
    if function_exported?(module, :commit, 0) and module.commit() == :change,
      do: :change,
      else: :enter
  end

  @doc "What is wrong with a column's component, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:not_found, module}),
    do: "The component `#{inspect(module)}` cannot be found: there is no module of that name."

  def message({:not_a_component, module}),
    do:
      "`#{inspect(module)}` is not a component: it does not implement the behaviour " <>
        "`AshTable.Component`. Add `use AshTable.Component` to it and define `cell/1`, " <>
        "`editor/1` or both."

  def message({:no_part, module}),
    do:
      "The component `#{inspect(module)}` defines neither `cell/1` nor `editor/1`, so it " <>
        "changes nothing."

  def message({:unsuitable, module, name, message}),
    do: "The component `#{inspect(module)}` cannot be used on `#{name}`: #{message}"
end
