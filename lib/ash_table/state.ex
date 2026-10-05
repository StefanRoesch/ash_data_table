defmodule AshTable.State do
  @moduledoc false
  # What a person has chosen in a table: the sort and the position in the
  # pages. It is all the server keeps besides the model, and all that goes
  # into the URL of a mounted table.
  #
  #   * `sort` is `{column_name, :asc | :desc}` or nil; nil leaves the read
  #     action's own sort in charge.
  #   * `page` is the 1-based page number under offset pagination.
  #   * `after` and `before` are keyset cursors; at most one is set.

  alias AshTable.Model

  defstruct sort: nil, page: 1, after: nil, before: nil

  @type sort :: {atom, :asc | :desc} | nil
  @type t :: %__MODULE__{
          sort: sort,
          page: pos_integer,
          after: String.t() | nil,
          before: String.t() | nil
        }

  @doc """
  Reads the state from a table's URL parameters.

  Anything that does not fit the model is dropped: a sort on a column that is
  unknown or not sortable, a page that is not a positive number, a position of
  the wrong pagination strategy.
  """
  @spec from_params(Model.t(), map) :: t
  def from_params(%Model{} = model, params) when is_map(params) do
    %__MODULE__{sort: parse_sort(model, params["sort"])}
    |> put_position(model.pagination.strategy, params)
  end

  def from_params(%Model{}, _params), do: %__MODULE__{}

  @doc "The URL parameters of a state; a default is left out."
  @spec to_params(t) :: %{optional(String.t()) => String.t()}
  def to_params(%__MODULE__{} = state) do
    [
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
  descending, then no sort. Any change of sort returns to the first page.
  """
  @spec cycle_sort(t, Model.t(), String.t()) :: t
  def cycle_sort(%__MODULE__{} = state, %Model{} = model, column_name) do
    case sortable_column(model, column_name) do
      nil -> state
      column -> %__MODULE__{sort: next_sort(state.sort, column.name)}
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
