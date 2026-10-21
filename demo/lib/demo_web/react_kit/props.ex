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
  def grid(id, myself, geometry, selecting, choose, texts),
    do: bundle(Attrs.grid(id, myself, geometry, selecting, choose, texts))

  @doc "The `role=table` element (`Attrs.table/6`)."
  def table(id, label, labelledby, geometry, page, busy?, running),
    do: bundle(Attrs.table(id, label, labelledby, geometry, page, busy? or not is_nil(running)))

  @doc """
  The header: its row, the headers of the boxes, the expanders and the
  actions, and per column its header (`Attrs.column_header/3`), its sort
  button (`Attrs.sort/3`, nil where it does not sort), the mark of the sort
  and the lock's name (`texts.read_only`).
  """
  def head(id, model, state, geometry, selecting, expandable?, myself, texts) do
    %{
      row: bundle(Attrs.head_row(id, geometry)),
      select:
        selecting &&
          bundle(
            Attrs.header("#{id}-select-head", "1", %{"data-select-page" => selecting == :multi})
          ),
      select_page: selecting == :multi && texts.select_page,
      select_row: selecting == :single && texts.select_row,
      expander: expandable? && bundle(Attrs.header("#{id}-expander-head", geometry.lead)),
      actions:
        geometry.trail == 1 && bundle(Attrs.header("#{id}-actions-head", geometry.colcount)),
      # where the columns stand: the island counts them (`geometry.colindex`)
      lead: geometry.lead,
      columns:
        for column <- model.columns do
          %{
            id: Ids.header_cell(id, column.name),
            name: column.name,
            label: column.label,
            attrs:
              bundle(
                Attrs.column_header(
                  column,
                  state.sort,
                  model.sticky_label? and label?(model, column)
                )
              ),
            sort: column.sortable? && bundle(Attrs.sort(id, column, myself)),
            mark: mark(state.sort, column),
            resizer: "#{id}-resize-#{column.name}",
            read_only:
              Words.texts(:header_cell, %{column: column, editing?: model.editing?}).read_only
          }
        end
    }
  end

  defp mark({name, :asc}, %{name: name}), do: " ▲"
  defp mark({name, :desc}, %{name: name}), do: " ▼"
  defp mark(_sort, _column), do: ""

  @doc """
  The filter row, nil where the table has none (the geometry's `header_rows` 1):
  its row, its empty cells, and per column its cell and, where the column
  filters, what its filter shows (`filters`, which `AshDataTable.Live.Drawing`
  gives the grid: `filter`, `rejected?`, `applied?`) and says.
  """
  def filters(id, model, filters, geometry, selecting, expandable?, myself) do
    if geometry.header_rows == 2 do
      %{
        row: bundle(Attrs.filter_row(id, geometry)),
        form: Ids.filters(id),
        select: selecting && bundle(Attrs.empty_cell("#{id}-select-filter", "1")),
        expander: expandable? && bundle(Attrs.empty_cell("#{id}-expander-filter", geometry.lead)),
        actions:
          geometry.trail == 1 &&
            bundle(Attrs.empty_cell("#{id}-actions-filter", geometry.colcount)),
        lead: geometry.lead,
        columns:
          for column <- model.columns do
            shown = filters[column.name]

            %{
              id: "#{id}-filter-#{column.name}",
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
  data columns (the geometry's `lead`), whether its rows are selected,
  expanded and have actions, the label column (whose cell is the row's
  header), the row actions with what varies of their buttons
  (`Attrs.action/2`), "Open", the relationships of its lines, how wide a
  line is and where the actions cell stands (the geometry's `colcount`).
  """
  def row(id, model, geometry, selecting, expandable?, open, asks?, nested?) do
    %{
      id: id,
      lead: geometry.lead,
      selecting: selecting,
      expandable: expandable?,
      acting: geometry.trail == 1,
      nested: nested?,
      label: model.label_column && model.label_column.name,
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
      colspan: geometry.colcount,
      actions_colindex: geometry.colcount
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
        geometry,
        selecting,
        expandable?,
        pages?,
        row_count,
        label,
        full_view,
        summary,
        summing?,
        time_zone,
        nested?,
        myself
      ) do
    full_view? = not is_nil(page) and not is_nil(full_view)
    summarised? = geometry.summary?

    %{
      id: "#{id}-foot",
      shown: nested? or summarised?,
      hidden: not (summarised? and not is_nil(page)) and not (nested? and (pages? or full_view?)),
      summaries:
        summarised? && page &&
          %{
            row: bundle(Attrs.summaries(id, geometry, page)),
            select: selecting && %{id: "#{id}-summaries-select", colindex: 1},
            expander: expandable? && %{id: "#{id}-summaries-expander", colindex: geometry.lead},
            actions:
              geometry.trail == 1 &&
                %{id: "#{id}-summaries-actions", colindex: geometry.colcount},
            lead: geometry.lead,
            cells:
              for column <- model.columns do
                held = summary && summary[column.name]
                texts = Words.texts(:summary_cell, %{column: column})

                %{
                  id: "#{id}-summary-#{column.name}",
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
            cell: bundle(Attrs.spanning("#{id}-pager", geometry, %{"data-pager" => true})),
            row: bundle(Attrs.row("#{id}-foot-row")),
            pagination:
              of(
                AshDataTable.Kit.Projection.of(:pagination, %{
                  id: id,
                  nested?: true,
                  page: page,
                  model: model,
                  state: state,
                  row_count: row_count,
                  label: label,
                  target: myself
                })
              )
          },
      full_view:
        nested? && full_view? &&
          %{
            row: bundle(Attrs.row("#{id}-view-row")),
            cell: bundle(Attrs.spanning("#{id}-view", geometry, %{"data-view" => true})),
            id: "#{id}-full-view",
            path: full_view,
            texts: Words.texts(:full_view, %{label: label})
          }
    }
  end

  # ---- what opens -----------------------------------------------------------

  # whether a column is the label column (by name: the model's copy of it
  # is the same column)
  defp label?(%{label_column: nil}, _column), do: false
  defp label?(%{label_column: %{name: name}}, column), do: column.name == name

  # ---- the bundles ----------------------------------------------------------

  @doc """
  A key of a part's projection (`AshDataTable.Kit.Projection`) as an
  island's prop: every bundle in it (a map of attribute names, string keys)
  as props, without what LiveView reads of an element it draws itself;
  the rest as it is.
  """
  def of(%{} = map) when not is_struct(map) and map_size(map) > 0 do
    if Enum.all?(Map.keys(map), &is_binary/1),
      do: bundle(map),
      else: Map.new(map, fn {key, value} -> {key, of(value)} end)
  end

  # what a column's component is told of its column (its own contract,
  # `AshDataTable.Component.Column`): the island is given what it draws with
  def of(%AshDataTable.Component.Column{} = column),
    do: %{
      name: column.name,
      label: column.label,
      cell_type: column.cell_type,
      min: number(column.constraints[:min]),
      max: number(column.constraints[:max])
    }

  def of(values) when is_list(values), do: Enum.map(values, &of/1)
  # a module (a column's component) by its name, as Elixir writes it
  def of(value) when is_atom(value) and not is_boolean(value) and not is_nil(value) do
    case Atom.to_string(value) do
      "Elixir." <> name -> name
      _atom -> value
    end
  end

  def of(value), do: value

  # A bundle as an island's props: without what LiveView reads of an
  # element it draws itself (`phx-hook`, `phx-update`, `phx-mounted`).
  defp bundle(attributes),
    do: attributes |> Map.drop(["phx-hook", "phx-update", "phx-mounted"]) |> Attrs.props()

  # What the cells of a type are, as text: `{:array, :text}` is "array".
  defp cell_type({:array, _item}), do: :array
  defp cell_type(cell_type), do: cell_type

  # An enum's values, each with its label.
  defp choices(values) when is_list(values),
    do: for({value, label} <- values, do: %{value: to_string(value), label: label})

  defp choices(_none), do: nil
end
