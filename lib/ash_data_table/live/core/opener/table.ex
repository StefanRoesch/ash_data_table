defmodule AshDataTable.Live.Core.Opener.Table do
  @moduledoc false
  # The table draws what it opens (`AshDataTable.Live.Core.Opener`, the
  # default): nothing is held for anyone. A question was asked by the hook
  # before its event came (`confirmed` of `picked`, the `table_run`,
  # `bulk_run` the hook's Confirm sends), or the topic has the hook ask it
  # (`ash_data_table:ask`, a reply's `ask`); the panel and the picker are
  # drawn, and the picker's table is read.

  @behaviour AshDataTable.Live.Core.Opener

  @impl true
  def ask(socket, _intent, _question, _about), do: {:run, socket}

  @impl true
  def opened(socket, _kind, _value), do: socket

  @impl true
  def closed(socket, _kind), do: socket

  @impl true
  def answer(_socket, _ref, _answer), do: :none

  @impl true
  def draws?(_options, _kind), do: true
end
