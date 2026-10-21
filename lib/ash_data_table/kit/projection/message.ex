defmodule AshDataTable.Kit.Projection.Message do
  @moduledoc false
  # The projections of the `message` part (`AshDataTable.Kit.Projection`):
  # one per message the table says in place of its rows now, each with its
  # kind, in this order: the error of a read, a nested table's first read on
  # its way, an argument to fill, "No records".

  alias AshDataTable.Kit.Projection.Said

  @doc false
  # the keys of each message's projection
  def keys, do: [:kind, :element, :nested?, :text, :message]

  @doc false
  def of(%{id: id, error: error, fill: fill, loading?: loading?, row_count: row_count} = given) do
    for {kind, message} <- shown(error, fill, loading?, row_count) do
      Map.merge(
        %{
          kind: kind,
          element: %{"id" => "#{id}-#{kind}", "role" => kind == :error && "alert"},
          nested?: given.nested?
        },
        Said.one(message)
      )
    end
  end

  defp shown(error, fill, loading?, row_count) do
    [
      error && {:error, error},
      loading? && {:loading, Said.t(:loading)},
      fill && {:fill, fill},
      (is_nil(error) and is_nil(fill) and row_count == 0 and not loading?) &&
        {:empty, Said.t(:no_records)}
    ]
    |> Enum.filter(& &1)
  end
end
