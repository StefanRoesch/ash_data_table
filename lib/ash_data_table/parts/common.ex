defmodule AshDataTable.Parts.Common do
  @moduledoc false
  # The small helpers that several parts draw with: the place of a column
  # and of a row in the grid, and the popover of a failure. A leaf: it calls
  # no other part, so that the parts do not call each other in a circle
  # (stage 1 drift check F8). A seed of `AshDataTable.Attrs` (stage 7).

  alias AshDataTable.Present
  alias AshDataTable.Text

  # A function of a column's component (`AshDataTable.Component`), which
  # is known at runtime only: called as LiveView's `Phoenix.Component` docs
  # say under "Dynamic Component Rendering", by a function component that
  # hands its assigns on with `apply/3`, so that LiveView tracks what
  # changes in them.
  def dynamic_component(assigns) do
    {module, assigns} = Map.pop(assigns, :module)
    {function, assigns} = Map.pop(assigns, :function)

    apply(module, function, [assigns])
  end

  # The columns after the last data column: the actions, when the rows have
  # them.
  def trail(true), do: 1
  def trail(false), do: 0

  # 1-based position of a data column among all columns of the grid.
  def colindex(index, lead), do: lead + index + 1

  # The footer row of the summaries is the last row of all: after the
  # records of every page. Where their number is not known it says nothing.
  def summary_rowindex(%{total: total}) when is_integer(total),
    do: total + Present.header_rows() + 1

  def summary_rowindex(_page), do: nil

  @doc """
  The name of the event `name` of the table `id`, as the browser sends it
  (target.md Q4): `ash_data_table:ID:NAME`. The live core takes only the
  events of its own table.
  """
  def event(id, name), do: "ash_data_table:" <> id <> ":" <> name

  @doc """
  What a message says (`AshDataTable.Text.say/1`): a part makes the words of
  the messages it is given as it draws them. Nil for no message.
  """
  def said(nil), do: nil
  def said(message), do: Text.say(message)

  def failure_message(id, message) do
    {:safe,
     [
       "<span",
       if(id, do: [~s( id="), escape(id), ~s(")], else: []),
       ~s| popover="manual" class="inset-auto m-0 max-w-xs rounded border border-[color-mix(in_oklab,var(--color-error)_70%,var(--color-base-content))] bg-base-100 px-2 py-1 text-xs whitespace-normal text-base-content shadow">|,
       escape(Text.say(message)),
       "</span>"
     ]}
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
