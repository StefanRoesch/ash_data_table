defmodule AshDataTable.Live.Current do
  @moduledoc false
  # Guards over the table a callback works on (stage 4): the
  # `AshDataTable.Table` under the assign whose name the socket's private
  # data holds (`AshDataTable.Live.Core.table/1`). A function head of the
  # live core says what it is for with them:
  #
  #     def follow(socket) when Current.entry(socket, :page) == nil
  #
  # Macros only, with no dependency, so that the modules that require it
  # are compiled against nothing of the core.

  @doc "The table the callback works on."
  defguard table(socket)
           when :erlang.map_get(
                  :erlang.map_get(
                    :current,
                    :erlang.map_get(:ash_data_table, :erlang.map_get(:private, socket))
                  ),
                  :erlang.map_get(:assigns, socket)
                )

  @doc "A field of the entry the callback works on."
  defguard entry(socket, field)
           when :erlang.map_get(field, :erlang.map_get(:entry, table(socket)))

  @doc "An option of the table the callback works on."
  defguard option(socket, field)
           when :erlang.map_get(field, :erlang.map_get(:options, table(socket)))
end
