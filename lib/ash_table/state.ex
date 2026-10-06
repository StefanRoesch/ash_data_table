defmodule AshTable.State do
  @moduledoc false
  # What a person has chosen in a table: the sort, the filters and the
  # position in the pages. It is all the server keeps besides the model, and
  # all that goes into the URL of a mounted table.
  #
  #   * `sort` is `{column_name, :asc | :desc}` or nil; nil leaves the read
  #     action's own sort in charge.
  #   * `filters` holds, by column name, the operator a person chose and the
  #     value as it was typed; nil for an operator that takes none. All of
  #     them apply at once.
  #   * `page` is the 1-based page number under offset pagination.
  #   * `after` and `before` are keyset cursors; at most one is set.

  alias AshTable.Model
  alias AshTable.Model.Operator

  defstruct sort: nil, filters: %{}, page: 1, after: nil, before: nil

  @type sort :: {atom, :asc | :desc} | nil
  @type filter :: {Operator.t(), String.t() | nil}
  @type t :: %__MODULE__{
          sort: sort,
          filters: %{optional(atom) => filter},
          page: pos_integer,
          after: String.t() | nil,
          before: String.t() | nil
        }

  @doc """
  Reads the state from a table's URL parameters.

  Anything that does not fit the model is dropped: a sort on a column that is
  unknown or not sortable, a filter on a column that has none or with an
  operator the column does not offer, a page that is not a positive number, a
  position of the wrong pagination strategy.
  """
  @spec from_params(Model.t(), map) :: t
  def from_params(%Model{} = model, params) when is_map(params) do
    %__MODULE__{
      sort: parse_sort(model, params["sort"]),
      filters: filters_from_params(model, params["f"])
    }
    |> put_position(model.pagination.strategy, params)
  end

  def from_params(%Model{}, _params), do: %__MODULE__{}

  @doc """
  The URL parameters of a state; a default is left out.

  The filters are under `"f"`, by column name. A filter with its column's
  default operator is the value alone, another one is the operator with its
  value, and a choice between operators without a value is the operator
  alone:

      %{"f" => %{
        "title" => "report",
        "progress" => %{"at_least" => "50"},
        "due_on" => %{"is_empty" => ""},
        "billable?" => "yes"
      }}
  """
  @spec to_params(t, Model.t()) :: %{optional(String.t()) => String.t() | map}
  def to_params(%__MODULE__{} = state, %Model{} = model) do
    [
      {"f", encode_filters(model, state.filters)},
      {"sort", encode_sort(state.sort)},
      {"page", if(state.page > 1, do: Integer.to_string(state.page))},
      {"after", state.after},
      {"before", state.before}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @doc """
  The state after a person asks to sort by `column_name`: ascending, then
  descending, then no sort. Any change of sort returns to the first page; the
  filters stay.
  """
  @spec cycle_sort(t, Model.t(), String.t()) :: t
  def cycle_sort(%__MODULE__{} = state, %Model{} = model, column_name) do
    case sortable_column(model, column_name) do
      nil ->
        state

      column ->
        %{state | sort: next_sort(state.sort, column.name), page: 1, after: nil, before: nil}
    end
  end

  @doc """
  The state after a person changed the filter row. `form` is what the row's
  form sends: by column name, the operator under `"o"` and the value under
  `"v"`, either of which a column's filter may lack.

  The filters are exactly those of the form. Any change of them returns to
  the first page; the sort stays.

  A value that is not one of the column's type is not applied. It is returned
  beside the state, by column name, for the table to show as rejected.
  """
  @spec filter(t, Model.t(), map) :: {t, %{optional(atom) => filter}}
  def filter(%__MODULE__{} = state, %Model{} = model, form) when is_map(form) do
    parsed =
      for %{operators: [_ | _]} = column <- model.columns,
          %{} = entry <- [form[Atom.to_string(column.name)]],
          {outcome, filter} <- [parse_filter(column, entry["o"], entry["v"])],
          do: {outcome, {column.name, filter}}

    {put_filters(state, Map.new(Keyword.get_values(parsed, :ok))),
     Map.new(Keyword.get_values(parsed, :rejected))}
  end

  @doc "The state without the filter of the column named `column_name`."
  @spec clear_filter(t, String.t()) :: t
  def clear_filter(%__MODULE__{} = state, column_name) when is_binary(column_name) do
    put_filters(
      state,
      Map.reject(state.filters, fn {name, _filter} -> Atom.to_string(name) == column_name end)
    )
  end

  @doc "The state without any filter."
  @spec clear_filters(t) :: t
  def clear_filters(%__MODULE__{} = state), do: put_filters(state, %{})

  defp put_filters(%__MODULE__{filters: filters} = state, filters), do: state

  defp put_filters(%__MODULE__{} = state, filters),
    do: %{state | filters: filters, page: 1, after: nil, before: nil}

  # A filter from the outside, where both the operator and the value are
  # text. No operator named means the column's default one, when that is one
  # which takes a value.
  defp parse_filter(column, operator, value) do
    operator = operator(column, operator)

    cond do
      is_nil(operator) -> {:none, nil}
      not Operator.takes_value?(operator) -> {:ok, {operator, nil}}
      not is_binary(value) or value == "" -> {:none, nil}
      value?(column, value) -> {:ok, {operator, value}}
      true -> {:rejected, {operator, value}}
    end
  end

  # Whether the text is a value of the column's type. Text is; a choice has
  # to be one of the values; a number, date or datetime is whatever Ash casts
  # to the type. Nothing is changed: the text itself goes into the filter.
  defp value?(%{cell_type: :text}, _text), do: true

  defp value?(%{cell_type: :enum, values: values}, text),
    do: Enum.any?(values, fn {value, _label} -> to_string(value) == text end)

  defp value?(%{type: {type, constraints}}, text),
    do: match?({:ok, _value}, Ash.Type.cast_input(type, text, constraints))

  defp operator(%{operators: [default | _]}, blank) when blank in [nil, ""],
    do: if(Operator.takes_value?(default), do: default)

  # Looked up as text, so that text from the outside is never turned into an atom.
  defp operator(%{operators: operators}, name) when is_binary(name),
    do: Enum.find(operators, &(Atom.to_string(&1) == name))

  defp operator(_column, _other), do: nil

  defp filters_from_params(model, params) when is_map(params) do
    for %{operators: [default | _]} = column <- model.columns,
        entry = params[Atom.to_string(column.name)],
        {:ok, filter} <- [parse_param(column, default, entry)],
        into: %{},
        do: {column.name, filter}
  end

  defp filters_from_params(_model, _params), do: %{}

  defp parse_param(column, default, text) when is_binary(text) do
    if Operator.takes_value?(default),
      do: parse_filter(column, nil, text),
      else: parse_filter(column, text, nil)
  end

  defp parse_param(column, _default, entry) when is_map(entry) do
    case Map.to_list(entry) do
      [{operator, value}] when operator != "" -> parse_filter(column, operator, value)
      _ -> {:none, nil}
    end
  end

  defp parse_param(_column, _default, _entry), do: {:none, nil}

  defp encode_filters(_model, filters) when filters == %{}, do: nil

  defp encode_filters(model, filters) do
    for %{operators: [default | _]} = column <- model.columns,
        {operator, value} <- [filters[column.name]],
        into: %{} do
      param =
        cond do
          operator == default -> value || Atom.to_string(operator)
          Operator.takes_value?(default) -> %{Atom.to_string(operator) => value || ""}
          true -> Atom.to_string(operator)
        end

      {Atom.to_string(column.name), param}
    end
  end

  @doc "The state on another page of an offset-paginated table."
  @spec to_page(t, pos_integer) :: t
  def to_page(%__MODULE__{} = state, page) when is_integer(page) and page > 0,
    do: %{state | page: page, after: nil, before: nil}

  defp next_sort({name, :asc}, name), do: {name, :desc}
  defp next_sort({name, :desc}, name), do: nil
  defp next_sort(_other, name), do: {name, :asc}

  defp parse_sort(model, "-" <> name), do: parse_sort(model, name, :desc)
  defp parse_sort(model, name) when is_binary(name), do: parse_sort(model, name, :asc)
  defp parse_sort(_model, _other), do: nil

  defp parse_sort(model, name, direction) do
    case sortable_column(model, name) do
      nil -> nil
      column -> {column.name, direction}
    end
  end

  defp encode_sort(nil), do: nil
  defp encode_sort({name, :asc}), do: Atom.to_string(name)
  defp encode_sort({name, :desc}), do: "-" <> Atom.to_string(name)

  # Looks the column up by its name as text, so that text from the outside is
  # never turned into an atom.
  defp sortable_column(model, name) when is_binary(name) do
    Enum.find(model.columns, &(&1.sortable? and Atom.to_string(&1.name) == name))
  end

  defp put_position(state, :offset, params) do
    case params["page"] do
      text when is_binary(text) ->
        case Integer.parse(text) do
          {page, ""} when page > 0 -> %{state | page: page}
          _ -> state
        end

      _ ->
        state
    end
  end

  defp put_position(state, :keyset, params) do
    case params do
      %{"after" => cursor} when is_binary(cursor) and cursor != "" -> %{state | after: cursor}
      %{"before" => cursor} when is_binary(cursor) and cursor != "" -> %{state | before: cursor}
      _ -> state
    end
  end

  defp put_position(state, :none, _params), do: state
end
