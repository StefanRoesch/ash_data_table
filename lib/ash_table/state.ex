defmodule AshTable.State do
  @moduledoc false
  # What a person has chosen in a table: the sort, the filters, the
  # arguments and the position in the pages. It is all the server keeps
  # besides the model, and all that goes into the URL of a mounted table.
  #
  #   * `sort` is `{column_name, :asc | :desc}` or nil; nil leaves the read
  #     action's own sort in charge.
  #   * `filters` holds, by column name, the operator a person chose and the
  #     value as it was typed; nil for an operator that takes none. All of
  #     them apply at once.
  #   * `arguments` holds, by the key of an argument of the argument line
  #     (`AshTable.Model.Argument.key/1`), what a person typed or picked for
  #     it: text, or for an array the texts of its values. An argument that
  #     is as its input shows it with nothing chosen is not in here: it is
  #     then left to its default.
  #   * `page` is the 1-based page number under offset pagination.
  #   * `after` and `before` are keyset cursors; at most one is set.

  alias AshTable.Model
  alias AshTable.Model.Argument
  alias AshTable.Model.Operator

  defstruct sort: nil, filters: %{}, arguments: %{}, page: 1, after: nil, before: nil

  @type sort :: {atom, :asc | :desc} | nil
  @type filter :: {Operator.t(), String.t() | nil}
  @type t :: %__MODULE__{
          sort: sort,
          filters: %{optional(atom) => filter},
          arguments: %{optional(Argument.key()) => Argument.typed()},
          page: pos_integer,
          after: String.t() | nil,
          before: String.t() | nil
        }

  @doc """
  Reads the state from a table's URL parameters.

  Anything that does not fit the model is dropped: a sort on a column that is
  unknown or not sortable, a filter on a column that has none or with an
  operator the column does not offer, an argument the table's line does not
  have, a page that is not a positive number, a position of the wrong
  pagination strategy.

  An argument's value is not looked at here: whether it is one the action
  takes is Ash's to say, when it is given to the action.
  """
  @spec from_params(Model.t(), map) :: t
  def from_params(%Model{} = model, params) when is_map(params) do
    %__MODULE__{
      sort: parse_sort(model, params["sort"]),
      filters: filters_from_params(model, params["f"]),
      arguments: arguments_from_params(model, params)
    }
    |> put_position(model.pagination.strategy, params)
  end

  def from_params(%Model{}, _params), do: %__MODULE__{}

  @doc """
  The state as far as it fits the model: without a sort by a column the
  table does not have or does not sort by, and without a filter on a column
  the table does not have, or with an operator the column does not offer,
  and without an argument the table's line does not have. A state that loses
  something starts at the first page again.

  A table that keeps its state itself holds it across a change of who is
  asking, and what one person could sort and filter by is not what the next
  one can.
  """
  @spec fit(t, Model.t()) :: t
  def fit(%__MODULE__{} = state, %Model{} = model) do
    sort =
      case state.sort do
        {name, _direction} = sort ->
          if Enum.any?(model.columns, &(&1.name == name and &1.sortable?)), do: sort

        nil ->
          nil
      end

    filters =
      Map.filter(state.filters, fn {name, {operator, _value}} ->
        Enum.any?(model.columns, &(&1.name == name and operator in &1.operators))
      end)

    arguments =
      Map.filter(state.arguments, fn {key, _typed} -> not is_nil(Model.argument(model, key)) end)

    if sort == state.sort and filters == state.filters and arguments == state.arguments do
      state
    else
      %{
        state
        | sort: sort,
          filters: filters,
          arguments: arguments,
          page: 1,
          after: nil,
          before: nil
      }
    end
  end

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

  The arguments of the read action are under `"a"`, by name, and those a
  column asks for under `"c"`, by column and name, each as it was typed. An
  array is the list of its values, and the empty text when it has none:

      %{"a" => %{"search" => "report"}, "c" => %{"price_in" => %{"currency" => "usd"}}}
  """
  @spec to_params(t, Model.t()) :: %{optional(String.t()) => String.t() | map}
  def to_params(%__MODULE__{} = state, %Model{} = model) do
    [
      {"f", encode_filters(model, state.filters)},
      {"a", encode_arguments(model, state.arguments, &is_nil(&1.column))},
      {"c", encode_arguments(model, state.arguments, &(not is_nil(&1.column)))},
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
  @spec cycle_sort(t, Model.t(), term) :: t
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

  @doc """
  The state after a person changed the argument line. `form` is what the
  line's form sends: the arguments of the read action under `"a"`, by name,
  and those a column asks for under `"c"`, by column and name.

  The arguments are exactly those of the form, each as it was typed. One
  that is as its input shows it with nothing chosen is left out: it is not
  a choice, and the argument keeps its default. Any change returns to the
  first page; the sort and the filters stay.
  """
  @spec argue(t, Model.t(), map) :: t
  def argue(%__MODULE__{} = state, %Model{} = model, form) when is_map(form) do
    arguments =
      for argument <- model.arguments,
          typed = sent(argument, form),
          typed != Argument.rest(argument),
          into: %{},
          do: {Argument.key(argument), typed}

    put_arguments(state, arguments)
  end

  @doc """
  The state with `typed` as what a person chose for the argument `key`
  names. As in `argue/3`, what the input shows with nothing chosen is no
  choice.
  """
  @spec put_argument(t, Model.t(), Argument.key(), Argument.typed()) :: t
  def put_argument(%__MODULE__{} = state, %Model{} = model, key, typed) do
    case Model.argument(model, key) do
      nil ->
        state

      argument ->
        typed = normal(argument, typed)

        put_arguments(
          state,
          if(typed == Argument.rest(argument),
            do: Map.delete(state.arguments, key),
            else: Map.put(state.arguments, key, typed)
          )
        )
    end
  end

  @doc """
  The state with what `previous` held for the arguments `keys` name, in
  place of what it holds for them itself: for a choice that was not taken.
  """
  @spec restore(t, t, [Argument.key()]) :: t
  def restore(%__MODULE__{} = state, %__MODULE__{} = previous, keys) do
    put_arguments(
      state,
      state.arguments |> Map.drop(keys) |> Map.merge(Map.take(previous.arguments, keys))
    )
  end

  @doc """
  The rows of an argument that is given value by value, as the argument
  line's form sends them: every one of them as it was typed, the empty ones
  too, without the entry the field sends of its own before them. Nil when
  the form holds nothing for the argument.
  """
  @spec rows(Argument.t(), map) :: [String.t()] | nil
  def rows(%Argument{cell_type: {:array, _item}} = argument, form) when is_map(form) do
    case held(argument, form) do
      [_own | rows] -> Enum.filter(rows, &is_binary/1)
      _nothing -> nil
    end
  end

  @doc "The state without what a person chose for the arguments `keys` name."
  @spec withdraw(t, [Argument.key()]) :: t
  def withdraw(%__MODULE__{} = state, keys),
    do: put_arguments(state, Map.drop(state.arguments, keys))

  defp put_arguments(%__MODULE__{arguments: arguments} = state, arguments), do: state

  defp put_arguments(%__MODULE__{} = state, arguments),
    do: %{state | arguments: arguments, page: 1, after: nil, before: nil}

  # What a form, or a URL, holds for an argument, as the state keeps it. An
  # argument that is not in it is as its input shows it with nothing chosen.
  defp sent(argument, params) do
    case held(argument, params) do
      nil -> Argument.rest(argument)
      held -> normal(argument, held)
    end
  end

  defp held(%{column: nil, name: name}, params), do: within(params, ["a", name])
  defp held(%{column: column, name: name}, params), do: within(params, ["c", column, name])

  # Looked up by names as text, so that text from the outside is never
  # turned into an atom.
  defp within(held, []), do: held
  defp within(%{} = params, [name | rest]), do: within(params[to_string(name)], rest)
  defp within(_not_a_map, _names), do: nil

  # An array is the list of its values, without those that are empty: a row
  # that nothing was typed into holds no value yet. One value is text.
  # Anything else is nothing a person can have sent through the table.
  defp normal(%{cell_type: {:array, _item}}, held) when is_list(held),
    do: for(value <- held, is_binary(value), value != "", do: value)

  defp normal(%{cell_type: {:array, _item}}, _empty_or_other), do: []
  defp normal(_argument, held) when is_binary(held), do: held
  defp normal(argument, _other), do: Argument.rest(argument)

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

  # The arguments a URL names, as far as the table's line has them.
  defp arguments_from_params(model, params) do
    for argument <- model.arguments,
        typed = sent(argument, params),
        typed != Argument.rest(argument),
        into: %{},
        do: {Argument.key(argument), typed}
  end

  # Those of `arguments` that `which` picks: by name for the read action's,
  # by column and name for the asked ones. Nil when there are none.
  defp encode_arguments(model, arguments, which) do
    encoded =
      for argument <- model.arguments,
          which.(argument),
          {:ok, typed} <- [Map.fetch(arguments, Argument.key(argument))],
          reduce: %{} do
        encoded ->
          typed = if typed == [], do: "", else: typed
          name = Atom.to_string(argument.name)

          case argument.column do
            nil ->
              Map.put(encoded, name, typed)

            column ->
              Map.update(
                encoded,
                Atom.to_string(column),
                %{name => typed},
                &Map.put(&1, name, typed)
              )
          end
      end

    if encoded != %{}, do: encoded
  end

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

  # anything else that an event may hold in place of a name
  defp sortable_column(_model, _other), do: nil

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
