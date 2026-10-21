defmodule AshDataTable.Live.Core.Notify do
  @moduledoc false
  # Events to the host (`AshDataTable.Event`): sent to the
  # LiveView's own process as `{:ash_data_table, id, {event, details}}`,
  # `id` the id of the table on the page, for the events the page asked for
  # with `notify` (`true` for all). A component runs in its LiveView's
  # process, so the tag's host hears them as an attached table's does. The
  # table's own hooks never halt them. A picker's table, and every table
  # inside one, sends none.
  #
  # Over the table (stage 9g): what is told is an effect of a step,
  # `{:tell, top, {event, details}}`, which `Live.Core.effects/2` sends;
  # the socket's way of a topic tells with `Live.Core.notify/3`.

  @doc """
  What the host is told of `event` of `table` (the table the callback
  works on), where the page asked for it: the effects, `[]` or one
  `{:tell, top, {name, details}}`. Nil is no event. `always?` is told
  whatever `notify` says: `:row_opened`, which the page asked for with
  `open`.
  """
  def told(table, event, always? \\ false)

  def told(_table, nil, _always?), do: []

  def told(%{caller: %{notify: notify}, entry: entry} = table, {name, details}, always?) do
    if (always? or wanted?(notify, name)) and not picking?(table) do
      [top | _] = entry.path

      details =
        details
        |> Map.put(:table, entry.id)
        |> Map.put(:resource, entry.resource)
        |> then(&if(length(entry.path) > 1, do: Map.put(&1, :path, entry.path), else: &1))

      [{:tell, top, {name, details}}]
    else
      []
    end
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
