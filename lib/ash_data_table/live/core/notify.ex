defmodule AshDataTable.Live.Core.Notify do
  @moduledoc false
  # Events to the host (`AshDataTable.Event`): sent to the
  # LiveView's own process as `{:ash_data_table, id, {event, details}}`,
  # `id` the id of the table on the page, for the events the page asked for
  # with `notify` (`true` for all). A component runs in its LiveView's
  # process, so the tag's host hears them as an attached table's does. The
  # table's own hooks never halt them. A picker's table, and every table
  # inside one, sends none.

  alias AshDataTable.Live.Core

  @doc """
  Tells the host `event` of the table the callback works on, where the page
  asked for it. Nil is no event. Returns the socket.
  """
  def told(socket, nil), do: socket

  def told(socket, event), do: told(socket, event, false)

  @doc """
  The same, `always?` sent whatever `notify` says: `:row_opened`, which
  the page asked for with `open`.
  """
  def told(socket, {name, details}, always?) do
    %{caller: %{notify: notify}, entry: entry} = table = Core.table(socket)

    if (always? or wanted?(notify, name)) and not picking?(table) do
      [top | _] = entry.path

      details =
        details
        |> Map.put(:table, entry.id)
        |> Map.put(:resource, entry.resource)
        |> then(&if(length(entry.path) > 1, do: Map.put(&1, :path, entry.path), else: &1))

      send(self(), {:ash_data_table, top, {name, details}})
    end

    socket
  end

  defp wanted?(true, _name), do: true
  defp wanted?(names, name) when is_list(names), do: name in names
  defp wanted?(_none, _name), do: false

  # Whether the table is a picker's, or inside one: what is chosen there is
  # told as what it becomes, a saved row or a panel's value.
  defp picking?(%{entry: entry, entries: entries}) do
    not is_nil(entry.choose) or
      Enum.any?(entry.path, fn id ->
        match?(%{choose: choose} when not is_nil(choose), Map.get(entries, id))
      end)
  end
end
