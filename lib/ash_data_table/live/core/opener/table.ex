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
  def ask(table, _intent, _question, _about), do: {:run, table}

  @impl true
  def opened(table, _kind, _value), do: table

  @impl true
  def closed(table, _kind), do: table

  @impl true
  def answer(_table, _ref, _answer), do: :none

  @impl true
  def draws?(_options, _kind), do: true
end
