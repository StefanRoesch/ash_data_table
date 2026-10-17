defmodule AshDataTable.Kit.Words do
  @moduledoc false
  # What each part of a kit is given of the texts and values it shows (the
  # design note of stage 7, D23): the one place that says it. `Kit.part/1`,
  # through which every part is drawn, puts it into the part's assigns:
  #
  #   * `messages` - by name, the message each text is made of, as
  #     `AshDataTable.Messages` documents it (a name may hold a list, and a
  #     message may be nil where the part shows nothing there);
  #   * `texts` - the same names, each message said in the locale of the
  #     LiveView's process (`AshDataTable.Text`);
  #   * for a part of one text (`message`, `failure`): `message` and `text`;
  #   * for a part that shows a value (`cell`, `summary_cell`, `field`):
  #     `locale`, and the value's `text` beside its `value`.
  #
  # The core makes keys and values; the words are made here, as the part is
  # drawn. They are given as changed only when an assign they are made of
  # changed (`Phoenix.Component.changed?/2`), so that a part sends a text
  # again only with what it is made of; else they are there all the same,
  # for what a part draws anew.

  alias AshDataTable.Format
  alias AshDataTable.Messages
  alias AshDataTable.Parts
  alias AshDataTable.Text

  @doc """
  The assigns of `part` with what it is given of its texts and values.
  """
  def given(part, assigns) do
    case words(part, assigns) do
      nil ->
        assigns

      {inputs, words} ->
        if Enum.any?(inputs, &Phoenix.Component.changed?(assigns, &1)),
          do: Phoenix.Component.assign(assigns, words),
          else: Map.merge(assigns, words)
    end
  end

  @worded [
    :related,
    :full_view,
    :argument,
    :filter,
    :selection_line,
    :columns,
    :status,
    :grid,
    :row,
    :resizer,
    :editor,
    :list,
    :panel,
    :picker,
    :confirm,
    :pagination
  ]

  @doc """
  What `part` is given of its words, by assign: the names a kit can rely on
  (`AshDataTable.KitCase` checks them).
  """
  def names(part) when part in [:message, :failure], do: [:text, :message]
  def names(part) when part in [:cell, :summary_cell], do: [:texts, :messages, :locale]
  def names(:field), do: [:texts, :messages, :locale]
  def names(part) when part in @worded, do: [:texts, :messages]
  def names(_part), do: []

  # ---- the parts ---------------------------------------------------------

  defp words(:related, a) do
    label = {:label, a.via.label}

    {[:via, :title],
     said(
       relationship: label,
       heading: a.title && t(:related_heading, record: a.title, relationship: label),
       show_all_records: t(:show_all_records)
     )}
  end

  defp words(:full_view, a),
    do: {[:label], said(full_view: t(:full_view), full_view_of: t(:full_view_of, table: a.label))}

  defp words(:argument, a) do
    values = if a.argument.editor == :list and is_list(a.value), do: a.value, else: []
    label = a.argument.label

    {[:argument, :value, :errors],
     said(
       add_value: t(:add_value),
       errors: a.errors,
       value_position:
         for(
           {_value, at} <- Enum.with_index(values, 1),
           do: t(:value_position, column: label, position: at)
         ),
       remove_value:
         for(
           {_value, at} <- Enum.with_index(values, 1),
           do: t(:remove_value, column: label, position: at)
         )
     )}
  end

  defp words(:filter, a) do
    column = a.column.label
    {_operator, value} = a.filter || {nil, nil}

    {[:column, :filter],
     said(
       filter: t(:filter, column: column),
       filter_operator: t(:filter_operator, column: column),
       any: t(:any),
       operators: Enum.map(a.column.operators, &operator(a.column, &1)),
       range_from: t(:range_from),
       range_to: t(:range_to),
       filter_from: t(:filter_from, column: column),
       filter_to: t(:filter_to, column: column),
       clear_filter: t(:clear_filter, column: column),
       invalid_filter: t(:invalid_filter),
       chosen: chosen(a.column, value)
     )}
  end

  defp words(:selection_line, a) do
    total = a.page && a.page.total

    {[:page, :row_count],
     said(
       select_all: if(total, do: t(:select_all, count: total), else: t(:select_all_uncounted)),
       selected_rows: t(:selected_rows),
       selected: t(:selected, count: "{n}"),
       all_selected:
         if(total, do: t(:all_selected, count: total), else: t(:all_selected_uncounted)),
       clear_selection: t(:clear_selection),
       clear_filters: t(:clear_filters),
       changed_records: t(:changed_records),
       read_again: t(:read_again)
     )}
  end

  defp words(:columns, a) do
    {[:columns, :state],
     said(
       columns: t(:columns),
       columns_with: t(:columns_with, details: "{details}"),
       columns_hidden: t(:columns_hidden, count: "{n}"),
       columns_filtered: t(:columns_filtered, count: "{n}"),
       columns_sorted: t(:columns_sorted, count: "{n}"),
       column_hidden: t(:column_hidden, column: "{column}"),
       column_shown: t(:column_shown, column: "{column}"),
       flags: Enum.map(a.columns, &flag(a.state, &1))
     )}
  end

  defp words(:status, a) do
    {[:announcement, :result],
     said(
       announcement: a.announcement,
       summary: a.result && a.result.summary,
       failures: (a.result && a.result.failures) || []
     )}
  end

  defp words(:grid, _a) do
    {[:kit],
     said(
       select_page: t(:select_page),
       select_row: t(:select_row),
       related_records: t(:related_records),
       actions: t(:actions)
     )}
  end

  defp words(:row, _a),
    do: {[:kit], said(select_row: t(:select_row), related_records: t(:related_records))}

  defp words(:cell, a) do
    column = a.column.label

    messages =
      case a.state do
        :masked ->
          [
            hidden_value: t(:hidden_value),
            show: t(:show),
            hide: t(:hide),
            show_value: t(:show_value, column: column),
            hide_value: t(:hide_value, column: column)
          ]

        :forbidden ->
          [not_available: t(:not_available)]

        _value_or_empty ->
          []
      end

    {[:state, :column, :value], Map.put(said(messages), :locale, Text.locale())}
  end

  defp words(:summary_cell, a) do
    {value, text} =
      case a.summary do
        {:ok, value} -> {value, Format.summary(a.column, value, a.time_zone)}
        _none -> {nil, nil}
      end

    words =
      said(
        kind: a.column.summary && t(summary_key(a.column.summary)),
        not_available: t(:not_available)
      )

    {[:column, :summary], Map.merge(words, %{value: value, text: text, locale: Text.locale()})}
  end

  defp words(:resizer, a),
    do: {[:column], said(resize_column: t(:resize_column, column: a.column.label))}

  defp words(:editor, a) do
    {[:column],
     said(
       clear: t(:clear),
       clear_value: t(:clear_value, column: a.column.label)
     )}
  end

  defp words(:list, a) do
    positions = Enum.with_index(a.values, 1)

    {[:label, :values],
     said(
       add_value: t(:add_value),
       value_label: t(:value_position, column: a.label, position: "{n}"),
       remove_label: t(:remove_value, column: a.label, position: "{n}"),
       value_position:
         for({_v, at} <- positions, do: t(:value_position, column: a.label, position: at)),
       remove_value:
         for({_v, at} <- positions, do: t(:remove_value, column: a.label, position: at))
     )}
  end

  defp words(:panel, a) do
    panel = a.panel

    {[:panel],
     said(
       title: panel.title,
       submit: panel.submit,
       question: panel.question,
       errors: panel.errors || [],
       cancel: t(:cancel)
     )}
  end

  defp words(:field, a) do
    label = a.input.label
    chosen = chosen_records(a)

    words =
      said(
        required: t(:required),
        choose: t(:choose),
        add_value: t(:add_value),
        kind: t(:kind),
        remove_group: t(:remove_group, column: label),
        will_be_cleared: t(:will_be_cleared),
        keep: t(:keep),
        clear: t(:clear),
        keep_value: t(:keep_value, column: label),
        clear_value: t(:clear_value, column: label),
        errors: a.errors,
        chosen: Enum.map(chosen, fn {_key, called, _at} -> chosen_said(called) end),
        remove_chosen:
          Enum.map(chosen, fn
            {_key, nil, at} -> t(:remove_value, column: label, position: at)
            {_key, called, _at} -> t(:remove_group, column: called)
          end)
      )

    {[:input, :value, :errors, :chosen, :clear], Map.put(words, :locale, Text.locale())}
  end

  defp words(:picker, a) do
    picker = a.picker

    {[:picker],
     said(
       title: picker.title,
       question: picker.question,
       error: picker.error,
       cancel: t(:cancel),
       choose_none: t(:choose_none),
       choose: t(:choose)
     )}
  end

  defp words(:confirm, _a), do: {[:kit], said(cancel: t(:cancel), confirm: t(:confirm))}

  defp words(part, a) when part in [:message, :failure] do
    {[:message], %{message: Messages.of(a.message), text: Text.say(a.message || "")}}
  end

  defp words(:pagination, a) do
    numbers = Parts.Pagination.page_numbers(a.page, a.state)

    words =
      said(
        label: t(:pagination, table: a.label),
        range: range(a.page, a.row_count, a.state),
        previous: t(:previous),
        next: t(:next),
        rows_per_page: t(:rows_per_page),
        go_to_page: Enum.map(numbers, &t(:go_to_page, page: &1))
      )

    {[:page, :row_count, :state, :label], Map.put(words, :pages, numbers)}
  end

  defp words(_part, _assigns), do: nil

  # ---- the words ---------------------------------------------------------

  defp t(key, bindings \\ []), do: {:text, key, bindings}

  # `texts` and `messages` of the messages by name: each said, a list each
  # one, and nil where nothing is shown.
  defp said(named) do
    named = Map.new(named)

    %{
      messages: Map.new(named, fn {name, message} -> {name, each(message, &Messages.of/1)} end),
      texts: Map.new(named, fn {name, message} -> {name, each(message, &say/1)} end)
    }
  end

  defp each(messages, fun) when is_list(messages), do: Enum.map(messages, &each(&1, fun))
  defp each(message, fun), do: fun.(message)

  defp say(nil), do: nil
  defp say(message), do: Text.say(message)

  # What an operator of a column's filter is called: a boolean's are its
  # two values.
  defp operator(%{cell_type: :boolean}, choice), do: t(choice)
  defp operator(_column, operator), do: t(String.to_existing_atom("operator_#{operator}"))

  defp summary_key(:count), do: :summary_count
  defp summary_key(:sum), do: :summary_sum
  defp summary_key(:avg), do: :summary_avg
  defp summary_key(:min), do: :summary_min
  defp summary_key(:max), do: :summary_max

  # What the button of a filter for several values says of what is chosen.
  defp chosen(%{values: values}, chosen) when is_list(values) and is_list(chosen) do
    case for {value, label} <- values, to_string(value) in chosen, do: label do
      [] -> t(:any)
      [label] -> label
      labels -> t(:values_chosen, count: length(labels))
    end
  end

  defp chosen(%{values: values} = column, nil) when is_list(values), do: chosen(column, [])
  defp chosen(_column, _value), do: nil

  # What a column's box in the "Columns" list says of the column besides its
  # name while it is hidden: that the rows are filtered by it, sorted by it,
  # or both.
  defp flag(state, column) do
    case {is_map_key(state.filters, column.name),
          AshDataTable.Attrs.aria_sort(state.sort, column) != "none"} do
      {true, true} -> t(:column_filtered_sorted)
      {true, false} -> t(:column_filtered)
      {false, true} -> t(:column_sorted)
      {false, false} -> nil
    end
  end

  # What the range of the page says.
  defp range(%{offset: offset, total: total}, row_count, _state)
       when is_integer(offset) and row_count > 0 do
    bindings = [from: offset + 1, to: offset + row_count, total: total]
    if total, do: t(:range_of_total, bindings), else: t(:range, Keyword.delete(bindings, :total))
  end

  defp range(%{offset: offset}, _row_count, state) when is_integer(offset),
    do: t(:page, page: state.page)

  defp range(%{total: total}, _row_count, _state) when is_integer(total),
    do: t(:records, count: total)

  defp range(_page, _row_count, _state), do: nil

  # The records a field holds that is given by choosing: each with its key,
  # what it is called (a value and its column, which is formatted here), and
  # its place, counted from 1.
  defp chosen_records(%{input: %{editor: :reference}, value: value, chosen: chosen}) do
    case chosen do
      %{^value => %{label: label}} -> [{value, called(label), 1}]
      _other -> []
    end
  end

  defp chosen_records(%{input: %{editor: :references}, value: values, chosen: chosen})
       when is_list(values) do
    for {key, position} <- Enum.with_index(values, 1) do
      {key, with(%{label: label} <- (chosen || %{})[key], do: called(label)), position}
    end
  end

  defp chosen_records(_field), do: []

  defp called({column, value, zone}), do: Format.format(column, value, zone)
  defp called(_nothing), do: nil

  defp chosen_said(nil), do: t(:not_available)
  defp chosen_said(called), do: called
end
