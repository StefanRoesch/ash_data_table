defmodule AshDataTable.Kit.Projection.Heading do
  @moduledoc false
  # The projection of the `heading` part (`AshDataTable.Kit.Projection`):
  # the heading line, with the projections of the parts in it, "Columns"
  # (`columns`) and the argument line (`argument_line`, an `argument` per
  # argument), and its create and table actions.

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Kit.Projection.Count
  alias AshDataTable.Kit.Projection.Related
  alias AshDataTable.Kit.Projection.Said
  alias AshDataTable.Model
  alias AshDataTable.Model.Limits

  @doc false
  def keys,
    do: [:shown?, :nested?, :element, :title, :columns, :argument_line, :acts?, :create, :actions]

  @doc false
  # `heading` is what the page asks of the table's name (a level, true, or
  # false), `lines` what the argument line was sent, `refused` what Ash
  # refused of it.
  def of(%{id: id, model: model, page: page, offered: offered, related: related} = given) do
    nested? = given.nested?
    acts? = !!page and (!!model.create or offered != []) and is_nil(related)
    columns? = length(model.columns) > 1 and hideable(model) != []

    %{
      shown?: nested? or !!given.heading or columns? or model.arguments != [] or acts?,
      nested?: nested?,
      element: %{"id" => "#{id}-header"},
      # the table's name (`title`): not a nested table's, which its line names; a
      # heading of `level` (nil for a plain element)
      title:
        if(given.heading && not nested?,
          do: %{
            element: %{"id" => "#{id}-name"},
            level: if(is_integer(given.heading), do: given.heading),
            text: given.label
          }
        ),
      columns: if(columns?, do: columns(id, model, given.state, given.label, nested?)),
      argument_line:
        if(model.arguments != [],
          do: %{
            form: Attrs.arguments(id, given.myself),
            nested?: nested?,
            arguments: arguments(id, model, given.lines, given.state, given.refused, given.myself)
          }
        ),
      # create and the table actions, at the far end: beside rows only, and
      # not of a table limited to related records, which offers them above
      # its grid
      acts?: acts?,
      create: if(acts?, do: Related.acts(id, model.create, given.myself)),
      actions: if(acts?, do: Related.table_actions(id, offered, given.myself), else: [])
    }
  end

  # The columns a person can hide: every column but the label column.
  defp hideable(%{label_column: nil} = model), do: model.columns

  defp hideable(%{label_column: %{name: name}} = model),
    do: Enum.reject(model.columns, &(&1.name == name))

  # "Columns" and its list: the button and the list, the label column's
  # entry (which cannot be hidden: its name and its width field), a box and
  # a width field per column that can be hidden, with what each says while
  # it is hidden, and "Reset widths".
  #
  # What the button says of the hidden columns is said here for every
  # number the browser can find, from 1 to the number of columns: the
  # browser, which alone knows what is hidden, takes the one it needs.
  # `columns` is what the button shows; `columns_name` what it and its list
  # are called, which names the table where it is nested in another, and
  # `columns_with` that name with what is hidden.
  defp columns(id, model, state, label, nested?) do
    columns = hideable(model)
    label_column = model.label_column
    counts = 1..length(columns)//1
    flags = Enum.map(columns, &flag(state, &1))

    words =
      Said.words(
        columns: Said.t(:columns),
        columns_name: if(nested?, do: Said.t(:columns_of, table: label), else: Said.t(:columns)),
        columns_with:
          if(nested?,
            do: Said.t(:columns_of_with, table: label, details: "{details}"),
            else: Said.t(:columns_with, details: "{details}")
          ),
        columns_hidden: Enum.map(counts, &Said.t(:columns_hidden, count: &1)),
        columns_filtered: Enum.map(counts, &Said.t(:columns_filtered, count: &1)),
        columns_sorted: Enum.map(counts, &Said.t(:columns_sorted, count: &1)),
        column_hidden: Enum.map(columns, &Said.t(:column_hidden, column: &1.label)),
        column_shown: Enum.map(columns, &Said.t(:column_shown, column: &1.label)),
        width_of: Enum.map(columns, &Said.t(:column_width, column: &1.label)),
        label_width: label_column && Said.t(:column_width, column: label_column.label),
        reset_widths: Said.t(:reset_widths),
        flags: flags
      )

    texts = words.texts

    Map.merge(
      %{
        control: %{"id" => "#{id}-columns-control"},
        button: Attrs.columns_button(id, texts),
        # what the hook writes into the button: its name with what is
        # hidden, and how many are
        text: %{"id" => "#{id}-columns-text"},
        count: %{"id" => "#{id}-columns-count"},
        list: Attrs.columns(id, is_nil(label_column), texts),
        # where the hook says that a column was hidden or shown again
        status: %{"id" => "#{id}-columns-status"},
        label:
          if(label_column,
            do: %{
              label: label_column.label,
              width: Attrs.width_field(id, label_column, texts.label_width)
            }
          ),
        entries:
          for {column, flag, hidden, shown, width_of} <-
                Enum.zip([
                  columns,
                  texts.flags,
                  texts.column_hidden,
                  texts.column_shown,
                  texts.width_of
                ]) do
            %{
              name: column.name,
              label: column.label,
              flag: flag,
              entry: %{"id" => "#{id}-column-#{column.name}-entry"},
              box: %{
                "id" => "#{id}-column-#{column.name}",
                "data-head" => Ids.header_cell(id, column.name),
                "data-say-hidden" => hidden,
                "data-say-shown" => shown,
                "data-filtered" => is_map_key(state.filters, column.name),
                "data-sorted" => Attrs.aria_sort(state.sort, column) != "none"
              },
              width: Attrs.width_field(id, column, width_of)
            }
          end,
        reset: Attrs.reset_widths(id),
        # the least and the most a width field takes, in pixels
        least: Attrs.least_width(),
        most: Attrs.most_width()
      },
      words
    )
  end

  # What a column's box in the "Columns" list says of the column besides its
  # name while it is hidden: that the rows are filtered by it, sorted by it,
  # or both.
  defp flag(state, column) do
    case {is_map_key(state.filters, column.name), Attrs.aria_sort(state.sort, column) != "none"} do
      {true, true} -> Said.t(:column_filtered_sorted)
      {true, false} -> Said.t(:column_filtered)
      {false, true} -> Said.t(:column_sorted)
      {false, false} -> nil
    end
  end

  # One per argument of the model, in its order, what its input is drawn
  # with: its ids, the name its control is sent under, what it holds (what
  # its line was sent, else what the state gives it), what Ash said of a
  # value it refused, the limits of a number and the counter of a text, its
  # buttons, and its words.
  defp arguments(id, model, lines, state, refused, target) do
    for argument <- model.arguments do
      named = Model.Argument.argument_id(argument)
      key = Model.Argument.key(argument)
      value = Map.get(lines, key) || Model.Argument.shown(argument, state, refused)
      control = Ids.argument(id, named)
      counted = counted(argument)
      list? = argument.editor == :list and is_list(value)

      errors =
        case refused[key] do
          nil -> []
          %{messages: messages} -> messages
        end

      values = if list?, do: value, else: []

      words =
        Said.words(
          [add_value: Said.t(:add_value), errors: errors] ++ positions(argument.label, values)
        )

      invalid? = errors != []
      error = if invalid?, do: Ids.error(control)
      count = if counted && argument.editor == :text, do: "#{control}-count"

      Map.merge(
        %{
          id: control,
          named: named,
          name: name(argument),
          label: argument.label,
          editor: argument.editor,
          item: item(argument.cell_type),
          required?: argument.required?,
          values: choices(argument.values),
          value: value,
          invalid?: invalid?,
          limits: Limits.of(argument),
          counted: counted,
          element: %{"data-argument" => named},
          # what its control names as its description: its error and its
          # counter
          described: described([error, count]),
          error: if(invalid?, do: %{"id" => Ids.error(control)}),
          count: if(count, do: Count.of(count, counted, value)),
          # an array: a group of controls, which its label names
          group:
            if(argument.editor in [:choices, :list],
              do: %{label: %{"id" => "#{control}-label"}, labelledby: "#{control}-label"}
            ),
          # an array given value by value: a row per value, with the button
          # that takes it away, and the button that adds one
          rows:
            for {held, at} <- Enum.with_index(values) do
              row_count = if counted, do: "#{control}-#{at}-count"

              %{
                value: held,
                id: Ids.argument_value(control, at),
                described: row_count,
                count: if(row_count, do: Count.of(row_count, counted, held)),
                remove:
                  Map.merge(
                    %{"id" => "#{control}-#{at}-remove"},
                    Attrs.argument_remove(id, named, at, target)
                  )
              }
            end,
          add:
            if(argument.editor == :list,
              do:
                Map.merge(
                  %{"id" => Ids.argument_value(control, :add)},
                  Attrs.argument_add(id, named, target)
                )
            )
        },
        words
      )
    end
  end

  # What each value of a list is called, and the button that takes it
  # away, by its place, counted from 1.
  defp positions(label, values) do
    places = 1..length(values)//1

    [
      value_position: Enum.map(places, &Said.t(:value_position, column: label, position: &1)),
      remove_value: Enum.map(places, &Said.t(:remove_value, column: label, position: &1))
    ]
  end

  # What an argument's control is sent under.
  defp name(%{column: nil, name: name}), do: "arguments[a][#{name}]"
  defp name(%{column: column, name: name}), do: "arguments[c][#{column}][#{name}]"

  # the counter of a text that has a most it can be long, as in the panel
  defp counted(%{editor: :text} = argument), do: Limits.counted(argument)

  defp counted(%{editor: :list, cell_type: {:array, :text}} = argument),
    do: Limits.counted(argument)

  defp counted(_argument), do: nil

  @doc false
  # What the values of an array are: `{:array, :text}`'s `:text`; nil of
  # anything else.
  def item({:array, item}), do: item
  def item(_one), do: nil

  @doc false
  # An enum's values, each with its label, as plain data; nil for none.
  def choices(values) when is_list(values),
    do: for({value, label} <- values, do: %{value: to_string(value), label: label})

  def choices(_none), do: nil

  @doc false
  # What a control names as its description: the ids of what says something
  # of it (its error message, its counter), or nil.
  def described(ids) do
    case Enum.filter(ids, &is_binary/1) do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end
end
