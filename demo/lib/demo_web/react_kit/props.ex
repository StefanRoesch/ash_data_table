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

  @doc "The link at the start of a table that jumps past it (`Attrs.skip/1`)."
  def skip(id), do: bundle(Attrs.skip(id))

  @doc "The scrollbar at the bottom edge of the window (`Attrs.scrollbar/1`)."
  def scrollbar(id), do: bundle(Attrs.scrollbar(id))

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
            given == nil ->
              nil

            column.editor == :component ->
              bundle(Attrs.component_control(column))

            given.counted && column.editor == :text ->
              bundle(Attrs.counted_control(template, column))

            true ->
              nil
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
  The heading line (the part `heading`): whether it is drawn at all, the
  table's name (a heading of the level the page asks for, else a plain
  element; not of a nested table, whose line names it), and at its far
  end create and the table actions (`Attrs.create/2`,
  `Attrs.table_action/3`), offered beside rows only and not by a table
  limited to related records, which offers them above its grid.
  """
  def heading(id, heading, label, label_column, model, offered, page, related, nested?, myself) do
    acts? = not is_nil(page) and (not is_nil(model.create) or offered != []) and is_nil(related)

    %{
      id: "#{id}-header",
      shown:
        nested? or !!heading or columns?(model, label_column) or model.arguments != [] or acts?,
      nested: nested?,
      name:
        heading && not nested? &&
          %{id: "#{id}-name", level: is_integer(heading) && heading, text: label},
      create:
        acts? && model.create &&
          %{label: model.create.label, attrs: bundle(Attrs.create(id, myself))},
      actions:
        for action <- (acts? && offered) || [] do
          %{
            name: action.name,
            label: action.label,
            attrs: bundle(Attrs.table_action(id, action, myself))
          }
        end
    }
  end

  @doc """
  "Columns" in the heading line, nil where the table has no column a
  person can hide (one column, or only the label column): what
  `columns_list/6` gives of the columns but the label column.
  """
  def heading_columns(id, model, label_column, state, label, nested?) do
    if columns?(model, label_column) do
      hideable = hideable(model, label_column)

      columns_list(
        id,
        hideable,
        label_column,
        is_nil(label_column),
        state,
        Words.texts(:columns, %{
          columns: hideable,
          label_column: label_column,
          state: state,
          label: label,
          nested?: nested?
        })
      )
    end
  end

  defp columns?(model, label_column),
    do: length(model.columns) > 1 and hideable(model, label_column) != []

  defp hideable(model, nil), do: model.columns
  defp hideable(model, label_column), do: List.delete(model.columns, label_column)

  @doc """
  The argument line (the part `argument_line`), nil for a table without
  arguments: its form (`Attrs.arguments/2`) and per argument what the
  table gives its input (`arguments`, `AshDataTable.Kit`): its ids and
  name, what it holds, whether Ash refused it and what it said, the limits
  of a number and the counter of a text (`Attrs.count/2`), with its label,
  control, values and the buttons of a list (`argument_add`,
  `argument_remove`, with `phx-value-at` per value).
  """
  def arguments(id, model, arguments, nested?, myself) do
    if model.arguments != [] do
      target = myself && to_string(myself)

      %{
        form: bundle(Attrs.arguments(id, myself)),
        nested: nested?,
        inputs:
          for {argument, given} <- Enum.zip(model.arguments, arguments) do
            list = %{
              "phx-value-argument" => given.named,
              "phx-target" => target
            }

            %{
              id: given.id,
              named: given.named,
              name: given.name,
              label: argument.label,
              editor: argument.editor,
              item:
                case argument.cell_type do
                  {:array, item} -> item
                  _one -> nil
                end,
              required: argument.required?,
              values: choices(argument.values),
              value: given.value,
              invalid: given.errors != [],
              limits: given.limits,
              counted: given.counted,
              count: given.counted && bundle(Attrs.count(given.counted, false)),
              add:
                argument.editor == :list &&
                  drop_empty(Map.put(list, "phx-click", Attrs.event(id, "argument_add"))),
              remove:
                argument.editor == :list &&
                  drop_empty(Map.put(list, "phx-click", Attrs.event(id, "argument_remove"))),
              texts: given.texts
            }
          end
      }
    end
  end

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
  What a table limited to the records of one record says above its grid
  (the part `related`): its heading, the relationship as the parent's
  table calls it, or its words before and after the record, which is a
  link to the page of the record's own table where the router mounts one;
  create and the table actions (`Attrs.create/2`, `Attrs.table_action/3`),
  and "Show all records", a patch to every record.
  """
  def related(id, title, parent, clear, create, actions, target, texts) do
    %{
      id: "#{id}-related",
      heading: %{
        id: "#{id}-related-heading",
        relationship: texts.relationship,
        record:
          texts.heading_before &&
            %{
              id: "#{id}-related-parent",
              before: texts.heading_before,
              title: title,
              after: texts.heading_after,
              path: parent && parent.path
            }
      },
      create: create && %{label: create.label, attrs: bundle(Attrs.create(id, target))},
      actions:
        for action <- actions do
          %{
            name: action.name,
            label: action.label,
            attrs: bundle(Attrs.table_action(id, action, target))
          }
        end,
      clear: %{id: "#{id}-related-clear", path: clear, text: texts.show_all_records}
    }
  end

  @doc """
  What is said in place of the rows (the part `message`): its element
  `ID-KIND`, an alert where it is the error of a read, and its text.
  """
  def message(id, kind, text, nested?),
    do: %{id: "#{id}-#{kind}", kind: kind, alert: kind == :error, text: text, nested: nested?}

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

  # ---- what opens -----------------------------------------------------------

  @doc """
  The question (the part `confirm`): whether the table asks at all, the
  dialog's bundle (`Attrs.confirm/3`: a `<dialog>` over the page, a region
  in it, hidden until the hook asks), the id of where the hook writes the
  question, and the answers' words.
  """
  def confirm(id, model, bulk, presentation, place, texts) do
    %{
      asks: asks?(model, bulk),
      presentation: presentation,
      dialog: bundle(Attrs.confirm(id, presentation, place)),
      question: "#{Ids.dialog(id)}-question#{Attrs.asked_in(place)}",
      cancel: texts.cancel,
      confirm: texts.confirm
    }
  end

  # Whether anything of the table asks a question before it runs: a column,
  # a row action, a table action, and every action on the selected rows.
  defp asks?(model, bulk),
    do:
      bulk != [] or Enum.any?(model.columns, & &1.confirm) or
        Enum.any?(model.actions ++ model.table_actions, & &1.confirm)

  @doc """
  The action panel (the part `panel`), drawn closed too: whether it is
  open, how it opens, its place (`Ids.panel_place/1`), and while it is open
  its element's bundle (`Attrs.panel/5`), its form, its words and a field
  each (`field/2`).
  """
  def panel(id, panel, fields, target, presentation, texts) do
    %{
      id: id,
      open: panel != nil,
      presentation: presentation,
      place: Ids.panel_place(id),
      frame: panel && bundle(Attrs.panel(id, panel, texts.question, target, presentation)),
      form:
        panel &&
          bundle(%{
            "id" => "#{id}-panel-form",
            "method" => panel.method,
            "phx-change" => Attrs.event(id, "panel_validate"),
            "phx-submit" => Attrs.event(id, "panel_submit"),
            "phx-target" => target,
            "novalidate" => true
          }),
      title: texts.title,
      errors: panel && panel.errors && texts.errors,
      destructive: panel != nil and panel.destructive?,
      cancel: %{attrs: bundle(Attrs.cancel("#{id}-panel-cancel")), text: texts.cancel},
      submit: %{id: "#{id}-panel-submit", text: texts.submit},
      fields: Enum.map(fields, &field(&1, target))
    }
  end

  # One field of the panel, of what its `field` part is given: its ids, name
  # and value, what its control is and says, its buttons' bundles
  # (`Attrs.unpick/4`, `Attrs.clear_field/3`, `Attrs.add_group/3`,
  # `Attrs.remove_group/3`, and the picker's `pick_input`), a file's upload,
  # and what a value made of fields holds, each a field again, with its
  # hidden entries as bundles (`hidden`) and a union's choice of its kind
  # (`kind_name`, `kind_path`).
  defp field(given, target) do
    input = given.input
    editor = input.editor
    group? = editor in [:group, :groups, :union]

    %{
      id: given.id,
      name: given.name,
      path: Enum.join(given.path, "."),
      editor: editor,
      label: input.label,
      required: input.required?,
      sensitive: Map.get(input, :sensitive?) == true,
      item:
        case input.cell_type do
          {:array, item} -> item
          _one -> nil
        end,
      values: choices(input.values),
      value: if(group?, do: nil, else: given.value),
      boxless: boxless(input, given.value),
      invalid: given.errors != [],
      places: given.places != [] && Attrs.held(given.places),
      limits: given.limits,
      counted: given.counted,
      count: given.counted && bundle(Attrs.count(given.counted, false)),
      clear: given.clear,
      clear_button: given.clear && bundle(Attrs.clear_field(given.table, input.name, target)),
      choose:
        editor in [:reference, :references] &&
          bundle(%{
            "phx-click" => Attrs.event(given.table, "pick_input"),
            "phx-value-input" => input.name,
            "phx-target" => target
          }),
      chosen:
        if editor == :references do
          for key <- given.value,
              do: %{key: key, unpick: bundle(Attrs.unpick(given.table, input.name, key, target))}
        end,
      component: editor == :component && inspect(input.component.module),
      upload: given.upload && upload(given.upload),
      add: group? && editor != :union && bundle(Attrs.add_group(given.table, given.path, target)),
      remove:
        editor == :group and not input.required? and
          bundle(Attrs.remove_group(given.table, given.path, target)),
      members: members(given.members, target),
      items:
        for item <- given.items do
          %{
            key: item.key,
            id: item.id,
            remove: bundle(Attrs.remove_group(given.table, item.path, target)),
            members: members(item.members, target)
          }
        end,
      hidden: Enum.map(given.hidden, &bundle/1),
      kind: given.kind,
      kind_name: given.kind_name,
      kind_path: given.kind_path && Enum.join(given.kind_path, "."),
      kinds:
        if editor == :union do
          for member <- input.members,
              do: %{value: Atom.to_string(member.name), label: member.label}
        end,
      single: given.single && field(given.single, target),
      texts: given.texts,
      list:
        editor == :list &&
          Words.texts(:list, %{label: input.label, values: given.value})
    }
  end

  defp members(nil, _target), do: nil

  defp members(members, target),
    do: %{
      hidden: Enum.map(members.hidden, &bundle/1),
      fields: Enum.map(members.fields, &field(&1, target))
    }

  # What a field of multiple choice holds that is none of its values, which
  # it sends back as it came.
  defp boxless(%{editor: :choices, values: values}, held) when is_list(held) do
    choices = Enum.map(values, fn {choice, _label} -> to_string(choice) end)
    Enum.reject(held, &(&1 in choices))
  end

  defp boxless(_input, _held), do: []

  # What LiveView keeps of a file field (`Phoenix.LiveView.UploadConfig`):
  # its name, what it takes, and each file chosen with how far it has come.
  defp upload(upload) do
    %{
      name: to_string(upload.name),
      ref: upload.ref,
      accept: if(is_binary(upload.accept), do: upload.accept),
      multiple: upload.max_entries > 1,
      entries:
        for entry <- upload.entries do
          %{
            ref: entry.ref,
            name: entry.client_name,
            progress: entry.progress,
            done: entry.done?,
            cancelled: entry.cancelled?
          }
        end
    }
  end

  @doc """
  The picker (the part `picker`), drawn closed too: whether it is open, how,
  its place (`Ids.picker_place/1`, which its table is moved into), and
  while it is open its element's bundle (`Attrs.picker/5`), its words, what
  it says when a choice was not taken, and its buttons (`Attrs.cancel/1`,
  `Attrs.none/1`, `Attrs.take/3`).
  """
  def picker(id, picker, target, presentation, takes?, texts) do
    %{
      id: id,
      open: picker != nil,
      presentation: presentation,
      place: Ids.picker_place(id),
      frame:
        picker &&
          bundle(Attrs.picker(id, texts.question, picker.several?, target, presentation)),
      title: texts.title,
      error: picker && picker.error && %{id: Ids.error("#{id}-picker"), text: texts.error},
      cancel: %{attrs: bundle(Attrs.cancel("#{id}-picker-cancel")), text: texts.cancel},
      none:
        picker && picker.allow_none? && %{attrs: bundle(Attrs.none(id)), text: texts.choose_none},
      take:
        picker && %{attrs: bundle(Attrs.take(id, picker.several?, takes?)), text: texts.choose}
    }
  end

  # ---- the bundles ----------------------------------------------------------

  # A bundle as an island's props: without what LiveView reads of an
  # element it draws itself (`phx-hook`, `phx-update`, `phx-mounted`).
  defp bundle(attributes),
    do: attributes |> Map.drop(["phx-hook", "phx-update", "phx-mounted"]) |> Attrs.props()

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
