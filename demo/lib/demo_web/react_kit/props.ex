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
  # (`Attrs.unpick/4`, `Attrs.clear_field/3`, `Attrs.add_group/4`,
  # `Attrs.remove_group/4`, with the buttons' ids, and the picker's `pick_input`), a file's upload,
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
      add:
        group? && editor != :union &&
          bundle(Attrs.add_group(given.add_id, given.table, given.path, target)),
      remove:
        editor == :group and not input.required? and
          bundle(Attrs.remove_group(given.remove_id, given.table, given.path, target)),
      members: members(given.members, target),
      items:
        for item <- given.items do
          %{
            key: item.key,
            id: item.id,
            remove: bundle(Attrs.remove_group(item.remove_id, given.table, item.path, target)),
            members: members(item.members, target)
          }
        end,
      hidden: Enum.map(given.hidden, &bundle/1),
      kind: given.kind,
      kind_id: given.kind_id,
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

  def of(values) when is_list(values), do: Enum.map(values, &of/1)
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
