defmodule AshTable.Record do
  @moduledoc false
  # One record of a table, read for the person asking. The table does not
  # keep the records it shows, so the record of a row is read again before
  # anything is done with it, by primary key, as that person and through
  # the read action the table reads its pages through: the same action, the
  # same policies and field policies as when the page was read.

  alias AshTable.Model
  alias AshTable.Query

  @doc """
  The record of `model.resource` with the primary key `key`, as `opts` say
  who is asking; `:error` when it is not there, or not theirs to read.
  """
  @spec fetch(Model.t(), map, keyword) :: {:ok, Ash.Resource.record()} | :error
  def fetch(%Model{} = model, key, opts) when is_map(key) do
    case Query.get(model.resource, model.read_action, key, opts) do
      {:ok, %_{} = record} -> {:ok, record}
      _not_found_or_refused -> :error
    end
  end

  @doc """
  A record of `resource` as the browser names it, as a primary key: the
  value of the key, or the list of its values for a key of several
  attributes, each cast as the attribute's type casts what comes from
  outside. Nil for anything that is no key of the resource.

  It is a claim. Whether there is such a record, and whether it is the
  person's to read, is known once it is read as them.
  """
  @spec key(Ash.Resource.t(), term) :: map | nil
  def key(resource, named) do
    case {Ash.Resource.Info.primary_key(resource), named} do
      {[], _named} -> nil
      {[_field] = fields, value} when not is_list(value) -> key(resource, fields, [value])
      {fields, values} when is_list(values) -> key(resource, fields, values)
      _other -> nil
    end
  end

  defp key(resource, fields, values) when length(values) == length(fields) do
    fields
    |> Enum.zip(values)
    |> Enum.reduce_while(%{}, fn {field, value}, key ->
      %{type: type, constraints: constraints} = Ash.Resource.Info.attribute(resource, field)

      case scalar?(value) && Ash.Type.cast_input(type, value, constraints) do
        {:ok, cast} when not is_nil(cast) -> {:cont, Map.put(key, field, cast)}
        _not_a_value -> {:halt, nil}
      end
    end)
  end

  defp key(_resource, _fields, _values), do: nil

  defp scalar?(value), do: is_binary(value) or is_number(value) or is_boolean(value)

  @doc """
  The record with what the table's columns show of it besides attributes,
  as an action returned it or as it was read; `:error` when it is no longer
  this person's to read.

  Loaded as Ash loads what a create, an update or a destroy action returns:
  through the primary read action. A table that changes records is only
  built over a resource whose primary read action is `public?`
  (`AshTable.Resource.Acting.private_result_read/1`).
  """
  @spec load(Model.t(), Ash.Resource.record(), keyword) :: {:ok, Ash.Resource.record()} | :error
  def load(%Model{} = model, record, opts) do
    case Query.load(record, model, opts) do
      {:ok, %_{} = record} -> {:ok, record}
      _error_or_gone -> :error
    end
  end
end
