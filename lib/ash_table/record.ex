defmodule AshTable.Record do
  @moduledoc false
  # One record of a table, read for the person asking. The table does not
  # keep the records it shows, so the record of a row is read again before
  # anything is done with it, by primary key and as that person: the same
  # policies and field policies apply as when the page was read.

  alias AshTable.Model
  alias AshTable.Query

  @doc """
  The record of `model.resource` with the primary key `key`, as `opts` say
  who is asking; `:error` when it is not there, or not theirs to read.
  """
  @spec fetch(Model.t(), map, keyword) :: {:ok, Ash.Resource.record()} | :error
  def fetch(%Model{} = model, key, opts) when is_map(key) do
    case Query.get(model.resource, key, opts) do
      {:ok, %_{} = record} -> {:ok, record}
      _not_found_or_refused -> :error
    end
  end

  @doc """
  The record with what the table's columns show of it besides attributes,
  as an action returned it or as it was read; `:error` when it is no longer
  this person's to read.
  """
  @spec load(Model.t(), Ash.Resource.record(), keyword) :: {:ok, Ash.Resource.record()} | :error
  def load(%Model{} = model, record, opts) do
    case Query.load(record, model, opts) do
      {:ok, %_{} = record} -> {:ok, record}
      _error_or_gone -> :error
    end
  end
end
