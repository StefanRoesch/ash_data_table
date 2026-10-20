defmodule DemoWeb.ReactKit.Props do
  @moduledoc """
  What the React kit's islands are given (`DemoWeb.ReactKit`), picked from
  a part's assigns: plain data only (strings, numbers, booleans, nil,
  lists and maps with atom or string keys), so that it goes to JSON as it
  is. The bundles of `AshDataTable.Attrs` go as props
  (`AshDataTable.Attrs.props/1`: `true` as `""`, nil and false left out,
  the rest as text), without the `phx-hook` and `phx-update` that LiveView
  would read: an island's element is the browser's, and the kit mounts the
  hooks itself.

  Each function takes the assigns it is made of, one argument each, so that
  LiveView marks a prop changed only when one of them changed, and
  live_react sends what changed in it. Nothing here is given a record or a
  sensitive value: a part is given none (`AshDataTable.Present`), and the
  rows are the stream's items as they are. `test/demo_web/react_kit_test.exs`
  encodes every prop of a page to JSON.
  """

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Kit.Words

  # ---- the grid -------------------------------------------------------------

  @doc "The grid's element (`Attrs.grid/6`)."
  def grid(id, myself, lead, selecting, choose, texts),
    do: bundle(Attrs.grid(id, myself, lead, selecting, choose, texts))

  @doc "The `role=table` element (`Attrs.table/8`)."
  def table(id, label, labelledby, model, page, summarised?, lead, acting?, busy?, running) do
    colcount = Attrs.colcount(model, lead, acting?)

    bundle(
      Attrs.table(
        id,
        label,
        labelledby,
        model,
        page,
        summarised?,
        colcount,
        busy? or not is_nil(running)
      )
    )
  end

  @doc """
  The header: its row, the headers of the boxes, the expanders and the
  actions, and per column its header (`Attrs.column_header/3`), its sort
  button (`Attrs.sort/3`, nil where it does not sort), the mark of the sort
  and the lock's name (`texts.read_only`).
  """
  def head(
        id,
        model,
        state,
        label_column,
        lead,
        selecting,
        expandable?,
        acting?,
        editing?,
        myself,
        texts
      ) do
    %{
      row: bundle(Attrs.row(Ids.head_row(id), "1")),
      select:
        selecting &&
          bundle(
            Attrs.header("#{id}-select-head", "1", %{"data-select-page" => selecting == :multi})
          ),
      select_page: selecting == :multi && texts.select_page,
      select_row: selecting == :single && texts.select_row,
      expander: expandable? && bundle(Attrs.header("#{id}-expander-head", lead)),
      actions:
        acting? && bundle(Attrs.header("#{id}-actions-head", length(model.columns) + lead + 1)),
      columns:
        for {column, index} <- Enum.with_index(model.columns) do
          %{
            id: Ids.header_cell(id, column.name),
            name: column.name,
            label: column.label,
            colindex: lead + index + 1,
            attrs:
              bundle(
                Attrs.column_header(
                  column,
                  state.sort,
                  model.sticky_label? and column == label_column
                )
              ),
            sort: column.sortable? && bundle(Attrs.sort(id, column, myself)),
            mark: mark(state.sort, column),
            resizer: "#{id}-resize-#{column.name}",
            read_only: Words.texts(:header_cell, %{column: column, editing?: editing?}).read_only
          }
        end
    }
  end

  defp mark({name, :asc}, %{name: name}), do: " ▲"
  defp mark({name, :desc}, %{name: name}), do: " ▼"
  defp mark(_sort, _column), do: ""

  @doc """
  The filter row, nil where the table has none (`Attrs.filter_row?/1`):
  its row, its empty cells, and per column its cell and, where the column
  filters, what its filter shows (`filters`, which `AshDataTable.Live.Drawing`
  gives the grid: `filter`, `rejected?`, `applied?`) and says.
  """
  def filters(id, model, filters, lead, selecting, expandable?, acting?, myself) do
    if Attrs.filter_row?(model) do
      %{
        row: bundle(Attrs.row(Ids.filter_row(id), "2")),
        form: Ids.filters(id),
        select: selecting && bundle(Attrs.empty_cell("#{id}-select-filter", "1")),
        expander: expandable? && bundle(Attrs.empty_cell("#{id}-expander-filter", lead)),
        actions:
          acting? &&
            bundle(Attrs.empty_cell("#{id}-actions-filter", length(model.columns) + lead + 1)),
        columns:
          for {column, index} <- Enum.with_index(model.columns) do
            shown = filters[column.name]

            %{
              id: "#{id}-filter-#{column.name}",
              colindex: lead + index + 1,
              filter: column.operators != [] && filter(id, column, shown, myself)
            }
          end
      }
    end
  end

  defp filter(id, column, %{filter: filter, rejected?: rejected?, applied?: applied?}, myself) do
    {operator, value} = filter || {nil, nil}
    takes = if operator, do: Map.fetch!(column.takes, operator), else: :one
    texts = Words.texts(:filter, %{column: column, filter: filter})

    %{
      name: column.name,
      cell_type: cell_type(column.cell_type),
      operators:
        for(
          {choice, said} <- Enum.zip(column.operators, texts.operators),
          do: %{value: choice, label: said}
        ),
      several_operators: match?([_, _ | _], column.operators),
      operator: operator,
      takes: takes,
      value: filter_value(value),
      values: choices(column.values),
      rejected: rejected?,
      clears: applied? and not rejected?,
      clear: %{
        "phx-click" => Attrs.event(id, "clear_filter"),
        "phx-value-column" => to_string(column.name),
        "phx-target" => myself && to_string(myself)
      },
      choose: takes == :many && bundle(Attrs.filter_values(id, column, operator, myself)),
      texts: Map.drop(texts, [:operators])
    }
  end

  defp filter_value({from, to}), do: [from, to]
  defp filter_value(value), do: value

  @doc """
  What the cells of a column need, the same on every row: its name and
  label, how it shows its values (`cell_type`, `max_lines`, its enum's
  labels, its `component`), whether it is sensitive, the attributes of its
  cells that are its own (`Attrs.cell/2`'s of the column), and what a
  masked cell says (`texts.show_value`, `texts.hide_value`).
  """
  def columns(model, texts) do
    for {column, show, hide} <- Enum.zip([model.columns, texts.show_value, texts.hide_value]) do
      %{
        name: column.name,
        label: column.label,
        cell_type: cell_type(column.cell_type),
        editor: column.editor,
        max_lines: column.max_lines,
        sensitive: column.sensitive?,
        values: choices(column.values),
        attrs: bundle(Attrs.cell(column, %{attrs: %{}})),
        component: component(column),
        show_value: show,
        hide_value: hide
      }
    end
  end

  # A column whose component draws its cells: the component by its module's
  # name, which the kit maps to a React component of its own, and the
  # bounds of its number, which a bar or a slider shows the value against.
  defp component(%{component: %{cell?: true, module: module, column: column}}) do
    %{
      module: inspect(module),
      min: number(column.constraints[:min]),
      max: number(column.constraints[:max])
    }
  end

  defp component(_column), do: nil

  defp number(%Decimal{} = number), do: Decimal.to_float(number)
  defp number(number) when is_number(number), do: number
  defp number(_none), do: nil

  @doc """
  What every row is drawn with besides its item: the columns before the
  data columns (`lead`), whether its rows are selected, expanded and have
  actions, the label column (whose cell is the row's header), the row
  actions with what varies of their buttons (`Attrs.action/2`), "Open", the
  relationships of its lines and how wide a line is.
  """
  def row(id, model, label_column, lead, selecting, expandable?, acting?, open, asks?, nested?) do
    %{
      id: id,
      lead: lead,
      selecting: selecting,
      expandable: expandable?,
      acting: acting?,
      nested: nested?,
      label: label_column && label_column.name,
      open: open,
      actions:
        for action <- model.actions do
          %{name: action.name, label: action.label, attrs: bundle(Attrs.action(action, asks?))}
        end,
      relationships:
        for(
          relationship <- model.relationships,
          do: %{name: relationship.name, label: relationship.label}
        ),
      colspan: Attrs.colcount(model, lead, acting?),
      actions_colindex: length(model.columns) + lead + 1
    }
  end

  @doc """
  The editors' templates (`Attrs.editor_template/3`), one per editable
  column, and in each what its editor is drawn with: what the `editor`
  part is given of its control (the grid's `editors`: the `limits` of a
  number, the `counted` of a text and the counter's bundle `Attrs.count/2`,
  whether a sensitive cell is `clearable`), the column's label, whether it
  is required, its enum's values, the control's bundle where the table
  gives one (`Attrs.counted_control/2`, `Attrs.component_control/1`), the
  component by its module's name and the texts (`clear`, `clear_value`).
  `editor` is nil where the cell has no editor in it (a reference, an
  array, …: the hook opens the picker or the panel).
  """
  def editors(id, model, editors, asks?) do
    for column <- model.columns, column.editable? do
      given = editors[column.name]
      template = Ids.editor(id, column.name)

      %{
        name: column.name,
        template: bundle(Attrs.editor_template(id, column, asks?)),
        editor: given && column.editor,
        label: column.label,
        required: column.required?,
        sensitive: column.sensitive?,
        values: choices(column.values),
        limits: given && given.limits,
        counted: given && given.counted,
        count: given && given.counted && bundle(Attrs.count(given.counted, false)),
        clearable: given != nil and given.clearable?,
        control:
          cond do
            given == nil -> nil
            column.editor == :component -> bundle(Attrs.component_control(column))
            given.counted && column.editor == :text -> bundle(Attrs.counted_control(template, column))
            true -> nil
          end,
        component: column.editor == :component && inspect(column.component.module),
        texts: given && Words.texts(:editor, %{column: column})
      }
    end
  end

  @doc """
  The footer: the row of the summaries where the table has one, and in a
  nested table its pages and its link to the full view.
  """
  def footer(
        id,
        model,
        page,
        state,
        lead,
        selecting,
        expandable?,
        acting?,
        pages?,
        row_count,
        label,
        full_view,
        summarised?,
        summary,
        summing?,
        time_zone,
        nested?,
        myself
      ) do
    full_view? = not is_nil(page) and not is_nil(full_view)

    %{
      id: "#{id}-foot",
      shown: nested? or summarised?,
      hidden: not (summarised? and not is_nil(page)) and not (nested? and (pages? or full_view?)),
      summaries:
        summarised? && page &&
          %{
            row: bundle(Attrs.summaries(id, model, page)),
            select: selecting && %{id: "#{id}-summaries-select", colindex: 1},
            expander: expandable? && %{id: "#{id}-summaries-expander", colindex: lead},
            actions:
              acting? &&
                %{id: "#{id}-summaries-actions", colindex: length(model.columns) + lead + 1},
            cells:
              for {column, index} <- Enum.with_index(model.columns) do
                held = summary && summary[column.name]
                texts = Words.texts(:summary_cell, %{column: column})

                %{
                  id: "#{id}-summary-#{column.name}",
                  colindex: lead + index + 1,
                  attrs: bundle(Attrs.summary(column, summing?)),
                  kind: column.summary && texts.kind,
                  not_available: texts.not_available,
                  state:
                    case held do
                      {:ok, _value} -> :ok
                      :unavailable -> :unavailable
                      nil -> nil
                    end,
                  text:
                    Words.text(:summary_cell, %{
                      column: column,
                      summary: held,
                      time_zone: time_zone
                    })
                }
              end
          },
      pager:
        nested? && pages? &&
          %{
            cell:
              bundle(
                Attrs.spanning("#{id}-pager", Attrs.colcount(model, lead, acting?), %{
                  "data-pager" => true
                })
              ),
            row: bundle(Attrs.row("#{id}-foot-row")),
            pagination:
              pagination(
                id,
                true,
                page,
                model,
                state,
                myself,
                Words.texts(:pagination, %{
                  page: page,
                  row_count: row_count,
                  state: state,
                  label: label
                }),
                Words.value(:pagination, %{page: page, state: state})
              )
          },
      full_view:
        nested? && full_view? &&
          %{
            row: bundle(Attrs.row("#{id}-view-row")),
            cell:
              bundle(
                Attrs.spanning("#{id}-view", Attrs.colcount(model, lead, acting?), %{
                  "data-view" => true
                })
              ),
            id: "#{id}-full-view",
            path: full_view,
            texts: Words.texts(:full_view, %{label: label})
          }
    }
  end

  # ---- around the grid ------------------------------------------------------

  @doc """
  "Columns" and its list (the part `columns`): the button
  (`Attrs.columns_button/2`) and the list (`Attrs.columns/3`), the label
  column's entry, a box and a width field per column that can be hidden,
  what each says while it is hidden, and "Reset widths".
  """
  def columns_list(id, columns, label_column, keeps_one?, state, texts) do
    %{
      id: id,
      button: bundle(Attrs.columns_button(id, texts)),
      list: bundle(Attrs.columns(id, keeps_one?, texts)),
      label:
        label_column &&
          %{
            label: label_column.label,
            width: bundle(Attrs.width_field(id, label_column, texts.label_width))
          },
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
            id: "#{id}-column-#{column.name}",
            label: column.label,
            flag: flag,
            box:
              %{
                "data-head" => Ids.header_cell(id, column.name),
                "data-say-hidden" => hidden,
                "data-say-shown" => shown,
                "data-filtered" => is_map_key(state.filters, column.name) && "",
                "data-sorted" => Attrs.aria_sort(state.sort, column) != "none" && ""
              }
              |> drop_empty(),
            width: bundle(Attrs.width_field(id, column, width_of))
          }
        end,
      reset: bundle(Attrs.reset_widths(id)),
      least: Attrs.least_width(),
      most: Attrs.most_width(),
      texts: Map.take(texts, [:columns, :columns_name, :reset_widths])
    }
  end

  @doc """
  The line above the grid (the part `selection_line`): what is selected
  and its buttons, the notice of changes with "Read again", and "Clear
  filters", with the events they send.
  """
  def selection_line(
        id,
        bulk,
        choose,
        notice?,
        page,
        row_count,
        running,
        selecting,
        selected,
        all?,
        whole_page?,
        state,
        nested?,
        myself,
        texts
      ) do
    more? =
      case page do
        _any when not is_nil(choose) -> false
        nil -> false
        %{total: nil} = page -> not is_nil(page.next) or not is_nil(page.previous)
        %{total: total} -> total > row_count
      end

    any? = all? or selected > 0
    running? = not is_nil(running)
    filtered? = state.filters != %{}
    target = myself && to_string(myself)
    {inline, menu} = if length(bulk) > 3, do: Enum.split(bulk, 2), else: {bulk, []}

    action = fn action ->
      %{
        label: action.label,
        destroys: action.type == :destroy,
        attrs: bundle(Attrs.bulk(id, action, running?))
      }
    end

    %{
      id: id,
      shown: notice? or filtered? or (selecting == :multi and any?),
      nested: nested?,
      selection:
        selecting == :multi &&
          %{
            group: bundle(Attrs.selection(id, texts)),
            selected: bundle(Attrs.selected(id)),
            controls: bundle(Attrs.selection_controls(id, any?)),
            select_all: bundle(Attrs.select_all(id, any? and not all? and whole_page? and more?)),
            clear: bundle(Attrs.clear_selection(id)),
            inline: Enum.map(inline, action),
            menu: Enum.map(menu, action),
            more_button: menu != [] && bundle(Attrs.bulk_more_button(id)),
            more: menu != [] && bundle(Attrs.bulk_more(id)),
            running: running?
          },
      notice:
        notice? &&
          %{
            id: "#{id}-notice",
            read_again: %{
              "id" => "#{id}-read-again",
              "phx-click" => Attrs.event(id, "read_again"),
              "phx-target" => target
            },
            focus: "#{id}-table"
          },
      clear_filters:
        filtered? &&
          %{
            "id" => "#{id}-clear-filters",
            "phx-click" => Attrs.event(id, "clear_filters"),
            "phx-target" => target
          }
          |> drop_empty(),
      filter_row: Ids.filter_row(id),
      texts: texts
    }
  end

  @doc "The live region and a run's result (the part `status`)."
  def status(id, announcements, texts) do
    %{
      region: bundle(Attrs.status(id)),
      announcement: texts.announcement,
      # a live region is read out when what it holds changes: every other
      # announcement ends in a no-break space
      again: rem(announcements, 2) == 1,
      result:
        texts.summary && %{id: "#{id}-result", summary: texts.summary, failures: texts.failures}
    }
  end

  @doc """
  The pagination (the part `pagination`, and a nested table's in its
  footer): its element (`Attrs.pagination/3`), the range, Previous, the
  page numbers, Next and "Rows per page", with the events they send.
  """
  def pagination(id, nested?, page, model, state, target, texts, pages) do
    target = target && to_string(target)
    sizes = model.pagination.page_sizes

    %{
      id: id,
      nested: nested?,
      element: bundle(Attrs.pagination(id, texts.label, nested?)),
      range: texts.range,
      event: Attrs.event(id, "page"),
      target: target,
      previous: %{text: texts.previous, disabled: is_nil(page.previous)},
      next: %{text: texts.next, disabled: is_nil(page.next)},
      pages:
        if model.pagination.strategy == :offset do
          for(
            {number, label} <- Enum.zip(pages, texts.go_to_page),
            do: %{number: number, label: label, current: number == state.page}
          )
        else
          []
        end,
      sizes:
        sizes != [] &&
          %{
            event: Attrs.event(id, "page_size"),
            sizes: sizes,
            # the size a page holds: the one chosen where it is offered, else the
            # one the table opens with
            chosen: if(state.per in sizes, do: state.per, else: model.pagination.page_size),
            label: texts.rows_per_page
          }
    }
  end

  # ---- the bundles ----------------------------------------------------------

  # A bundle as an island's props: without what LiveView reads of an
  # element it draws itself (`phx-hook`, `phx-update`).
  defp bundle(attributes), do: attributes |> Map.drop(["phx-hook", "phx-update"]) |> Attrs.props()

  defp drop_empty(attributes),
    do: for({name, value} <- attributes, value not in [nil, false], into: %{}, do: {name, value})

  # What the cells of a type are, as text: `{:array, :text}` is "array".
  defp cell_type({:array, _item}), do: :array
  defp cell_type(cell_type), do: cell_type

  # An enum's values, each with its label.
  defp choices(values) when is_list(values),
    do: for({value, label} <- values, do: %{value: to_string(value), label: label})

  defp choices(_none), do: nil
end
