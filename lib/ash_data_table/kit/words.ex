defmodule AshDataTable.Kit.Words do
  @moduledoc """
  What each part of a kit is given of the texts and values it shows: the
  one place that says it. Whoever draws
  a part passes them as the part's attributes, made here of the part's
  other attributes, so that LiveView sends a text again only when what it
  is made of changed:

      <AshDataTable.Kit.part
        part={:resizer}
        kit={@kit}
        id={@id}
        column={@column}
        texts={AshDataTable.Kit.Words.texts(:resizer, %{column: @column})}
        messages={AshDataTable.Kit.Words.messages(:resizer, %{column: @column})}
      />

  A kit's own part that draws a part of the table through the kit passes
  them the same way. What each part is given, and of which values, is in
  `AshDataTable.Kit`'s moduledoc ("Texts and values"); `names/1` is the
  list of a part's assigns (`AshDataTable.KitCase` checks them):

    * `texts/2` - by name, each text said in the locale of the LiveView's
      process (`AshDataTable.Messages`); a name may hold a list, and nil
      where the part shows nothing there;
    * `messages/2` - the same names, each the message the text is made of;
    * for a part of one text (`message`, `failure`): `text/2` and
      `message/2`;
    * for a part that shows a value: `locale/0`, and for a summary cell
      `value/2` and `text/2`, the value as the default kit shows it; for
      the pagination `value/2`, the page numbers it offers (`pages`).

  The table's core makes keys and values; the words are made here, in the
  LiveView's process.
  """

  alias AshDataTable.Format
  alias AshDataTable.Messages
  alias AshDataTable.Text

  @doc "What `part` shows, by name, in words: of `values`, the part's assigns they are made of."
  @spec texts(atom, map) :: %{atom => String.t() | [String.t()] | nil}
  def texts(part, values \\ %{}),
    do: Map.new(words(part, values), fn {name, message} -> {name, each(message, &say/1)} end)

  @doc "What `part` shows, by name, as the messages `texts/2` says."
  @spec messages(atom, map) :: %{atom => Messages.t() | [Messages.t()] | nil}
  def messages(part, values \\ %{}),
    do:
      Map.new(words(part, values), fn {name, message} ->
        {name, each(message, &Messages.of/1)}
      end)

  @doc """
  The one text of a part: of `:message` and `:failure` their `message`
  (`%{message: …}`), said; of `:summary_cell` the value of its `summary`
  as the default kit shows it (`%{column: …, summary: …, time_zone: …}`).
  Nil for none. A cell's text is in its item (`AshDataTable.Item`).
  """
  @spec text(atom, map) :: String.t() | nil
  def text(part, %{message: message}) when part in [:message, :failure],
    do: Text.say(message || "")

  def text(:summary_cell, %{column: column, summary: {:ok, value}, time_zone: zone}),
    do: Format.summary(column, value, zone)

  def text(:summary_cell, _values), do: nil

  @doc "The one message of `:message` and `:failure`: their `message` as `messages/2` gives it."
  @spec message(atom, map) :: Messages.t() | nil
  def message(part, %{message: message}) when part in [:message, :failure],
    do: Messages.of(message)

  @doc """
  The value a part shows besides its texts: of `:summary_cell` the raw
  value of its `summary` (`%{summary: …}`), nil for none; of `:pagination`
  the numbers of the pages it offers (`%{page: …, state: …}`), as `pages`.
  """
  @spec value(atom, map) :: term
  def value(:summary_cell, %{summary: {:ok, value}}), do: value
  def value(:summary_cell, _values), do: nil

  def value(:pagination, %{page: page, state: state}),
    do: page_numbers(page, state)

  @doc "The locale the texts are said in: Gettext's, of the table's backend."
  @spec locale() :: String.t()
  def locale, do: Text.locale()

  @worded [
    :related,
    :line,
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
  @spec names(atom) :: [atom]
  def names(part) when part in [:message, :failure], do: [:text, :message]
  def names(:cell), do: [:texts, :messages, :locale]
  def names(:summary_cell), do: [:texts, :messages, :locale, :value, :text]
  def names(:field), do: [:texts, :messages, :locale]
  def names(:pagination), do: [:texts, :messages, :pages]
  def names(part) when part in @worded, do: [:texts, :messages]
  def names(_part), do: []

  # ---- the parts ---------------------------------------------------------

  # By part, its messages by name, made of the values it is given.
  defp words(:related, %{via: via, title: title}) do
    label = {:label, via.label}
    {before, behind} = around_record(title, label)

    [
      relationship: label,
      heading: title && t(:related_heading, record: title, relationship: label),
      heading_before: before,
      heading_after: behind,
      show_all_records: t(:show_all_records)
    ]
  end

  # how many records an open nested table has, where it is known
  defp words(:line, %{count: count}),
    do: [count: count && t(:records, count: count)]

  defp words(:full_view, %{label: label}),
    do: [full_view: t(:full_view), full_view_of: t(:full_view_of, table: label)]

  defp words(:argument, %{argument: argument, value: value, errors: errors}) do
    values = if argument.editor == :list and is_list(value), do: value, else: []
    label = argument.label

    [add_value: t(:add_value), errors: errors] ++ positions(label, values)
  end

  defp words(:filter, %{column: column, filter: filter}) do
    label = column.label
    {_operator, value} = filter || {nil, nil}

    [
      filter: t(:filter, column: label),
      filter_operator: t(:filter_operator, column: label),
      any: t(:any),
      operators: Enum.map(column.operators, &operator(column, &1)),
      range_from: t(:range_from),
      range_to: t(:range_to),
      filter_from: t(:filter_from, column: label),
      filter_to: t(:filter_to, column: label),
      clear_filter: t(:clear_filter, column: label),
      invalid_filter: t(:invalid_filter),
      chosen: chosen(column, value)
    ]
  end

  defp words(:selection_line, %{page: page, selected: count, all?: all?}) do
    total = page && page.total

    [
      select_all: if(total, do: t(:select_all, count: total), else: t(:select_all_uncounted)),
      selected_rows: t(:selected_rows),
      # what is selected, said in the live region: nil for nothing
      selected:
        cond do
          all? and total -> t(:all_selected, count: total)
          all? -> t(:all_selected_uncounted)
          count > 0 -> t(:selected, count: count)
          true -> nil
        end,
      clear_selection: t(:clear_selection),
      more_actions: t(:more_actions),
      clear_filters: t(:clear_filters),
      changed_records: t(:changed_records),
      read_again: t(:read_again)
    ]
  end

  # What the button says of the hidden columns is said here for every
  # number the browser can find, from 1 to the number of columns: the
  # browser, which alone knows what is hidden, takes the one it needs.
  #
  # `columns` is what the button shows; `columns_name` what it and its list
  # are called, which names the table where it is nested in another, and
  # `columns_with` that name with what is hidden.
  defp words(:columns, %{columns: columns, state: state, label: label, nested?: nested?}) do
    counts = 1..length(columns)//1

    [
      columns: t(:columns),
      columns_name: if(nested?, do: t(:columns_of, table: label), else: t(:columns)),
      columns_with:
        if(nested?,
          do: t(:columns_of_with, table: label, details: "{details}"),
          else: t(:columns_with, details: "{details}")
        ),
      columns_hidden: Enum.map(counts, &t(:columns_hidden, count: &1)),
      columns_filtered: Enum.map(counts, &t(:columns_filtered, count: &1)),
      columns_sorted: Enum.map(counts, &t(:columns_sorted, count: &1)),
      column_hidden: Enum.map(columns, &t(:column_hidden, column: &1.label)),
      column_shown: Enum.map(columns, &t(:column_shown, column: &1.label)),
      flags: Enum.map(columns, &flag(state, &1))
    ]
  end

  defp words(:status, %{announcement: announcement, result: result}) do
    [
      announcement: announcement,
      summary: result && result.summary,
      failures: (result && result.failures) || []
    ]
  end

  defp words(:grid, _values) do
    [
      select_page: t(:select_page),
      select_row: t(:select_row),
      related_records: t(:related_records),
      actions: t(:actions),
      show_whole: t(:show_whole),
      show_less: t(:show_less)
    ]
  end

  defp words(:row, _values),
    do: [select_row: t(:select_row), related_records: t(:related_records)]

  defp words(:cell, %{column: column, cell: %{state: state, failure: failure}}) do
    label = column.label

    case state do
      :masked ->
        [
          hidden_value: t(:hidden_value),
          show: t(:show),
          hide: t(:hide),
          show_value: t(:show_value, column: label),
          hide_value: t(:hide_value, column: label)
        ]

      :forbidden ->
        [not_available: t(:not_available)]

      # a value a union holds may be one the person may not see
      _value_or_empty when column.cell_type == :union ->
        [not_available: t(:not_available)]

      _value_or_empty ->
        []
    end ++ typed(column, failure)
  end

  defp words(:summary_cell, %{column: column}) do
    [
      kind: column.summary && t(summary_key(column.summary)),
      not_available: t(:not_available)
    ]
  end

  defp words(:resizer, %{column: column}),
    do: [resize_column: t(:resize_column, column: column.label)]

  defp words(:editor, %{column: column}),
    do: [clear: t(:clear), clear_value: t(:clear_value, column: column.label)]

  defp words(:list, %{label: label, values: values}) do
    [
      add_value: t(:add_value),
      value_label: t(:value_position, column: label, position: "{n}"),
      remove_label: t(:remove_value, column: label, position: "{n}")
    ] ++ positions(label, values)
  end

  defp words(:panel, %{panel: panel}) do
    [
      title: panel.title,
      submit: panel.submit,
      question: panel.question,
      errors: panel.errors || [],
      cancel: t(:cancel)
    ]
  end

  defp words(:field, %{input: input, errors: errors} = values) do
    label = input.label
    chosen = chosen_records(values)

    [
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
      errors: errors,
      chosen: Enum.map(chosen, fn {_key, called, _at} -> chosen_said(called) end),
      remove_chosen:
        Enum.map(chosen, fn
          {_key, nil, at} -> t(:remove_value, column: label, position: at)
          {_key, called, _at} -> t(:remove_group, column: called)
        end)
    ] ++ group_items(input, values)
  end

  defp words(:picker, %{picker: picker}) do
    [
      title: picker.title,
      question: picker.question,
      error: picker.error,
      cancel: t(:cancel),
      choose_none: t(:choose_none),
      choose: t(:choose)
    ]
  end

  defp words(:confirm, _values), do: [cancel: t(:cancel), confirm: t(:confirm)]

  defp words(:pagination, %{page: page, row_count: row_count, state: state, label: label}) do
    [
      label: t(:pagination, table: label),
      range: range(page, row_count, state),
      previous: t(:previous),
      next: t(:next),
      rows_per_page: t(:rows_per_page),
      go_to_page:
        Enum.map(
          page_numbers(page, state),
          &t(:go_to_page, page: &1)
        )
    ]
  end

  # ---- the words ---------------------------------------------------------

  defp t(key, bindings \\ []), do: {:text, key, bindings}

  defp each(messages, fun) when is_list(messages), do: Enum.map(messages, &each(&1, fun))
  defp each(message, fun), do: fun.(message)

  defp say(nil), do: nil
  defp say(message), do: Text.say(message)

  # What each value of a list is called, and the button that takes it
  # away, by its place, counted from 1.
  defp positions(label, values) do
    places = 1..length(values)//1

    [
      value_position: Enum.map(places, &t(:value_position, column: label, position: &1)),
      remove_value: Enum.map(places, &t(:remove_value, column: label, position: &1))
    ]
  end

  # Of a field that is a list of groups: what each value of it is called,
  # the button that takes it away, and what is said of it as a whole, by
  # its place (`AshDataTable.Act.items/1`, as the panel draws them).
  defp group_items(%{editor: :groups, label: label}, %{value: held, inside: inside}) do
    items = AshDataTable.Act.items(held)

    positions(label, items) ++
      [
        item_errors:
          for(
            {_item, index} <- Enum.with_index(items),
            do: item_errors(inside, index)
          )
      ]
  end

  defp group_items(_input, _values), do: []

  # The errors about one value of a list of groups as a whole, by its
  # place, once the panel was sent or the list was touched.
  defp item_errors(inside, index) do
    if inside.submitted? or inside.path in inside.touched,
      do: Map.get(inside.errors, inside.place ++ [index], []),
      else: []
  end

  # The page numbers offered: the first, the last and those around the
  # current one, of the pages there are; and the current one, also when the
  # URL asked for a page beyond the last. Without a total only the current
  # page is known.
  defp page_numbers(%{pages: pages}, %{page: current}) when is_integer(pages) do
    [1, pages | Enum.to_list((current - 2)..(current + 2)//1)]
    |> Enum.filter(&((&1 >= 1 and &1 <= pages) or &1 == current))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp page_numbers(_page, %{page: current}), do: [current]

  # What a cell whose save failed shows of what was typed, as the cell
  # would show it had it been saved: a yes or no, an enum's label. Nothing
  # of a sensitive cell, which shows its mask.
  defp typed(%{sensitive?: true}, _failure), do: []
  defp typed(_column, nil), do: []
  defp typed(column, %{typed: typed}), do: [typed: typed_text(typed, column)]

  defp typed_text(typed, %{editor: :boolean}) when typed in ["true", "false"],
    do: t(String.to_existing_atom(if(typed == "true", do: "yes", else: "no")))

  defp typed_text(typed, %{editor: :enum, values: values}),
    do:
      Enum.find_value(values, typed, fn {value, label} -> to_string(value) == typed && label end)

  defp typed_text(typed, _column), do: typed

  # The heading of a table of related records in words, before and after
  # the record it names, where a part draws the record as a link: nil and
  # nil without a title, or where the words do not name the record.
  defp around_record(nil, _relationship), do: {nil, nil}

  defp around_record(_title, relationship) do
    case :related_heading
         |> Text.t(record: "\0", relationship: Text.say(relationship))
         |> String.split("\0", parts: 2) do
      [before, behind] -> {before, behind}
      _not_named -> {nil, nil}
    end
  end

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
