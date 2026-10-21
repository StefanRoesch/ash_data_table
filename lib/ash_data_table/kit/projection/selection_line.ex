defmodule AshDataTable.Kit.Projection.SelectionLine do
  @moduledoc false
  # The projection of the `selection_line` part
  # (`AshDataTable.Kit.Projection`): what is selected and what can be done
  # with it, the notice of changes, and "Clear filters".

  alias AshDataTable.Attrs
  alias AshDataTable.Kit.Projection.Said

  @doc false
  def keys, do: [:shown?, :nested?, :selection, :notice, :clear_filters, :texts, :messages]

  # Each key of its own inputs (`key/2`): `selected` how many rows are
  # selected, `total` the page's total, `filtered?` whether a filter is set,
  @doc false
  # whether anything is on the line: rows are selected, a filter is set, or
  # the notice shows
  def key(:shown?, %{notice?: notice?, filtered?: filtered?, selecting: selecting} = given),
    do: notice? or filtered? or (selecting == :multi and any?(given))

  def key(:nested?, %{nested?: nested?}), do: nested?

  def key(:selection, %{id: id, selecting: selecting} = given) do
    if selecting == :multi, do: selection(id, given, any?(given), words(given).texts)
  end

  def key(:notice, %{id: id, notice?: notice?, myself: myself}) do
    if notice? do
      %{element: %{"id" => "#{id}-notice"}, read_again: Attrs.read_again(id, myself)}
    end
  end

  def key(:clear_filters, %{id: id, filtered?: filtered?, myself: myself}),
    do: if(filtered?, do: Attrs.clear_filters(id, myself))

  def key(words, given) when words in [:texts, :messages], do: Map.fetch!(words(given), words)

  defp any?(%{all?: all?, selected: count}), do: all? or count > 0

  defp words(%{total: total, selected: count, all?: all?}) do
    Said.words(
      select_all:
        if(total, do: Said.t(:select_all, count: total), else: Said.t(:select_all_uncounted)),
      selected_rows: Said.t(:selected_rows),
      # what is selected, said in the live region: nil for nothing
      selected:
        cond do
          all? and total -> Said.t(:all_selected, count: total)
          all? -> Said.t(:all_selected_uncounted)
          count > 0 -> Said.t(:selected, count: count)
          true -> nil
        end,
      clear_selection: Said.t(:clear_selection),
      more_actions: Said.t(:more_actions),
      clear_filters: Said.t(:clear_filters),
      changed_records: Said.t(:changed_records),
      read_again: Said.t(:read_again)
    )
  end

  # What is selected and its buttons: the actions on the selection, of more
  # than three the first two on the line (`inline`) and the others in the
  # menu "More" (`more`, nil for none); "all that match", there once every
  # row of the page is selected and the filters match more records than
  # the page shows.
  defp selection(id, given, any?, texts) do
    running? = not is_nil(given.running)

    {inline, menu} =
      if length(given.bulk) > 3, do: Enum.split(given.bulk, 2), else: {given.bulk, []}

    action = fn action ->
      %{
        name: action.name,
        label: action.label,
        destroys?: action.type == :destroy,
        button: Attrs.bulk(id, action, running?)
      }
    end

    %{
      group: Attrs.selection(id, texts),
      selected: Attrs.selected(id),
      controls: Attrs.selection_controls(id, any?),
      select_all:
        Attrs.select_all(id, any? and not given.all? and given.whole_page? and more?(given)),
      clear: Attrs.clear_selection(id),
      inline: Enum.map(inline, action),
      more:
        if(menu != [],
          do: %{
            button: Attrs.bulk_more_button(id),
            menu: Attrs.bulk_more(id),
            actions: Enum.map(menu, action)
          }
        ),
      running?: running?
    }
  end

  # Whether the filters match more records than the page shows. In a table
  # to choose several records from, what is selected is what is chosen: it
  # is the rows that were selected one by one, never "all that match".
  defp more?(%{choose: choose}) when not is_nil(choose), do: false
  defp more?(%{page: nil}), do: false

  defp more?(%{page: %{total: nil} = page}),
    do: not is_nil(page.next) or not is_nil(page.previous)

  defp more?(%{page: %{total: total}, row_count: row_count}), do: total > row_count
end
