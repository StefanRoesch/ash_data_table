defmodule AshDataTable.Resource.Presenting do
  @moduledoc false
  # What the `component` of a column is: the module, which of the two parts
  # it has and when its editor saves. Shared by the verifier (which reports
  # a mistake) and the table model (which builds on the answer).
  #
  # The module is looked at when it is asked about, never when the resource
  # is compiled: the resource does not depend on it.

  alias AshDataTable.Component.Column
  alias AshDataTable.Resource.CellType

  @type reason ::
          {:sensitive, atom}
          | {:not_found, module}
          | {:not_a_component, module}
          | {:no_part, module}
          | {:unsuitable, module, atom, String.t()}
          | {:one_line, atom, :reference | :sensitive | {:component, module} | CellType.t()}

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
  cannot serve this column (`c:AshDataTable.Component.verify/1`).
  """
  @spec component(module, Column.t()) :: {:ok, component} | {:error, reason}
  def component(module, %Column{} = column) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, module} ->
        cond do
          not Spark.implements_behaviour?(module, AshDataTable.Component) ->
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

  # The cell types whose cells are never more than a few characters on one
  # line, and take no `max_lines`.
  @short [:number, :boolean, :date, :datetime, :enum]

  @doc """
  How many lines a cell of a column shows at most: what the column's
  `max_lines` says, where its cells are shown as text that can be long, and
  1 where the block says nothing. `declared` is the column as written, or
  nil for a column of the default set.

  More than one line is refused where it can never have an effect: on a
  reference cell, on a sensitive column, on a column whose component shows
  the cell, and on a number, a date, a datetime, a boolean and an enum.
  """
  @spec max_lines(Ash.Resource.t(), struct, struct | nil) ::
          {:ok, pos_integer} | {:error, reason}
  def max_lines(resource, field, %{max_lines: lines} = declared)
      when is_integer(lines) and lines > 1 do
    cond do
      is_struct(field, Ash.Resource.Relationships.BelongsTo) ->
        {:error, {:one_line, declared.name, :reference}}

      AshDataTable.Resource.Exposing.sensitive?(field) ->
        {:error, {:one_line, declared.name, :sensitive}}

      shows?(declared.component) ->
        {:error, {:one_line, declared.name, {:component, declared.component}}}

      true ->
        case CellType.of(resource, field) do
          {cell_type, _values} when cell_type in @short ->
            {:error, {:one_line, declared.name, cell_type}}

          _text ->
            {:ok, lines}
        end
    end
  end

  def max_lines(_resource, _field, _declared), do: {:ok, 1}

  # Whether a column's component shows the cell. One that cannot be found
  # shows nothing, and is reported for that.
  defp shows?(nil), do: false

  defp shows?(module),
    do:
      match?({:module, _module}, Code.ensure_compiled(module)) and
        function_exported?(module, :cell, 1)

  @doc "What is wrong with a column's component or its `max_lines`, for a diagnostic."
  @spec message(reason) :: String.t()
  def message({:sensitive, name}),
    do:
      "`#{name}` is declared `sensitive?: true`. A table masks the cells of a sensitive column and hides what is typed into them itself; a component would be given the value to show. Remove `component` from this column."

  def message({:not_found, module}),
    do: "The component `#{inspect(module)}` cannot be found: there is no module of that name."

  def message({:not_a_component, module}),
    do:
      "`#{inspect(module)}` is not a component: it does not implement the behaviour " <>
        "`AshDataTable.Component`. Add `use AshDataTable.Component` to it and define `cell/1`, " <>
        "`editor/1` or both."

  def message({:no_part, module}),
    do:
      "The component `#{inspect(module)}` defines neither `cell/1` nor `editor/1`, so it " <>
        "changes nothing."

  def message({:unsuitable, module, name, message}),
    do: "The component `#{inspect(module)}` cannot be used on `#{name}`: #{message}"

  def message({:one_line, name, why}),
    do:
      "`max_lines` has no effect on `#{name}`: #{one_line(name, why)} " <>
        "`max_lines` is for a column that is shown as text: a string, an array, a map, an " <>
        "embedded resource, a union, or a type shown as read-only text. Remove `max_lines` " <>
        "from this column."

  defp one_line(_name, :reference),
    do: "it shows the label of a related record, which is always one line."

  defp one_line(_name, :sensitive),
    do: "it is declared `sensitive?: true`, and its cells show a mask and a button on one line."

  defp one_line(_name, {:component, module}),
    do: "its cells are shown by the component `#{inspect(module)}`, which decides how they look."

  defp one_line(_name, cell_type),
    do: "it is shown as #{article(cell_type)}, which is always one line."

  defp article(:number), do: "a number"
  defp article(:boolean), do: "a boolean"
  defp article(:date), do: "a date"
  defp article(:datetime), do: "a datetime"
  defp article(:enum), do: "an enum"

  @doc false
  # What a field of a cell type is shown as, in a sentence: what the shipped
  # components (`AshDataTable.Components.Badge`, `.Image`, `.Progress`,
  # `.Slider`) say when a column is not of a type they show.
  def shown_as(:text), do: "text"
  def shown_as(:number), do: "a number"
  def shown_as(:boolean), do: "a boolean"
  def shown_as(:date), do: "a date"
  def shown_as(:datetime), do: "a date and time"
  def shown_as(:enum), do: "a choice"
  def shown_as({:array, _item}), do: "a list of values"
  def shown_as(:map), do: "a value made of fields"
  def shown_as(:union), do: "a value of one of several kinds"
  def shown_as(:other), do: "read-only text"
end
