defmodule AshDataTable.Kit.Projection.Grid do
  @moduledoc false
  # The projection of the `grid` part (`AshDataTable.Kit.Projection`): its
  # elements' bundles, the header (`head`, a `header_cell` each), the filter
  # row (`filters`, a `filter_cell` and its `filter` each), what every row
  # is drawn with (`row`: its columns, each what a `cell` of it is drawn
  # with, its actions, its lines), the footer (`footer`: the summaries, a
  # nested table's pages and full view), the editors' templates (`editors`,
  # an `editor` each) and the failure template. The rows are the table's
  # stream, which the part is given beside its projection. Each key of its
  # own inputs (`key/2`), so that LiveView sends a key again only when
  # what it is made of changed.

  alias AshDataTable.Attrs
  alias AshDataTable.Edit
  alias AshDataTable.Format
  alias AshDataTable.Geometry
  alias AshDataTable.Ids
  alias AshDataTable.Kit.Projection.Count
  alias AshDataTable.Kit.Projection.FullView
  alias AshDataTable.Kit.Projection.Pagination
  alias AshDataTable.Kit.Projection.Said
  alias AshDataTable.Model.Limits
  alias AshDataTable.State

  @doc false
  def keys,
    do: [
      :nested?,
      :sender,
      :skip,
      :scrollbar,
      :filter_form,
      :grid,
      :table,
      :head,
      :filters,
      :row,
      :footer,
      :editors,
      :failure,
      :texts,
      :messages
    ]

  @doc false
  def key(:nested?, %{nested?: nested?}), do: nested?
  def key(:sender, %{id: id}), do: Attrs.sender(id)
  def key(:skip, %{id: id}), do: Attrs.skip(id)
  def key(:scrollbar, %{id: id}), do: Attrs.scrollbar(id)

  # the form of the filter row, where there is one (the controls name it)
  def key(:filter_form, %{id: id, geometry: geometry, myself: myself}),
    do: if(geometry.header_rows == 2, do: Attrs.filters(id, myself))

  def key(:grid, %{
        id: id,
        myself: myself,
        geometry: geometry,
        selecting: selecting,
        choose: choose
      }) do
    texts =
      Said.words(
        show_whole: Said.t(:show_whole),
        show_less: Said.t(:show_less),
        show_whole_of: Said.t(:show_whole_of, column: "{column}"),
        show_less_of: Said.t(:show_less_of, column: "{column}")
      ).texts

    Attrs.grid(id, myself, geometry, selecting, choose, texts)
  end

  # the `role=table` element: busy while it reads or runs on the selection
  def key(:table, %{id: id, label: label, labelledby: labelledby, geometry: geometry} = given),
    do:
      Attrs.table(
        id,
        label,
        labelledby,
        geometry,
        given.page,
        given.busy? or not is_nil(given.running)
      )

  def key(:head, %{id: id, model: model, state: state, geometry: geometry} = given),
    do: head(id, model, state, geometry, given.selecting, given.expandable?, given.myself)

  def key(:filters, %{id: id, model: model, geometry: geometry} = given) do
    if geometry.header_rows == 2,
      do: filters(id, model, geometry, given)
  end

  def key(:row, %{id: id, model: model, geometry: geometry} = given),
    do: row(id, model, geometry, given.selecting, given.expandable?, given.open, given.asks?)

  def key(:footer, %{id: id, geometry: geometry, nested?: nested?} = given) do
    if nested? or geometry.summary?, do: footer(id, geometry, given)
  end

  def key(:editors, %{id: id, model: model, asks?: asks?}), do: editors(id, model, asks?)

  # the template of a cell's message, which the hook copies where the record
  # is gone: where a cell can be edited or a row acted on
  def key(:failure, %{id: id, model: model, geometry: geometry}) do
    if model.editing? or geometry.trail == 1,
      do: Map.merge(%{template: %{"id" => "#{id}-failure"}}, Said.one(""))
  end

  def key(words, given) when words in [:texts, :messages], do: Map.fetch!(words(given), words)

  # Besides its own, the texts the cells of its rows show that are the same
  # on every row (a stream item holds only what varies, ADR 0002): what a
  # masked cell says (`show_value`, `hide_value`, one per column of the
  # model, nil where the column is not sensitive; `hidden_value`, `show`,
  # `hide`), what a cell the person may not see says (`not_available`), and
  # what a failed boolean cell shows of what was typed (`yes`, `no`). Each
  # column's are in its projection too (`row`'s `columns`).
  defp words(%{label: label, model: model}) do
    masked = fn key ->
      Enum.map(model.columns, fn column ->
        if column.sensitive?, do: Said.t(key, column: column.label)
      end)
    end

    Said.words(
      skip_table: Said.t(:skip_table, name: label),
      select_page: Said.t(:select_page),
      select_row: Said.t(:select_row),
      related_records: Said.t(:related_records),
      actions: Said.t(:actions),
      show_whole: Said.t(:show_whole),
      show_less: Said.t(:show_less),
      show_whole_of: Said.t(:show_whole_of, column: "{column}"),
      show_less_of: Said.t(:show_less_of, column: "{column}"),
      hidden_value: Said.t(:hidden_value),
      show: Said.t(:show),
      hide: Said.t(:hide),
      show_value: masked.(:show_value),
      hide_value: masked.(:hide_value),
      not_available: Said.t(:not_available),
      yes: Said.t(:yes),
      no: Said.t(:no)
    )
  end

  # ---- the header -------------------------------------------------------

  # The header row: its bundle, the headers of the boxes (where one stands
  # for the rows of the page, its box's name), of the expanders and of the
  # actions, and a `header_cell` per column.
  defp head(id, model, state, geometry, selecting, expandable?, myself) do
    %{
      row: Attrs.head_row(id, geometry),
      select:
        if(selecting,
          do: %{
            element:
              Attrs.header("#{id}-select-head", "1", %{
                "data-select-page" => selecting == :multi
              }),
            page?: selecting == :multi
          }
        ),
      expander: if(expandable?, do: Attrs.header("#{id}-expander-head", geometry.lead)),
      actions: if(geometry.trail == 1, do: Attrs.header("#{id}-actions-head", geometry.colcount)),
      cells:
        for {column, index} <- Enum.with_index(model.columns) do
          words =
            Said.words(
              # the lock after the heading of a column that no row may be
              # edited in, where the table offers editing at all
              read_only: (model.editing? and not column.editable? and Said.t(:read_only)) || nil
            )

          Map.merge(
            %{
              element:
                Map.merge(
                  %{
                    "id" => Ids.header_cell(id, column.name),
                    "aria-colindex" => Geometry.colindex(geometry, index),
                    "aria-label" => column.label
                  },
                  Attrs.column_header(column, state.sort, label?(model, column))
                ),
              label: column.label,
              button: if(column.sortable?, do: Attrs.sort(id, column, myself)),
              mark: mark(state.sort, column),
              resizer: %{element: %{"id" => "#{id}-resize-#{column.name}"}}
            },
            words
          )
        end
    }
    |> Map.merge(Said.words(select_page: Said.t(:select_page), select_row: Said.t(:select_row)))
  end

  # Whether a column is the label column kept in view (`data-label`).
  defp label?(%{sticky_label?: true, label_column: %{name: name}}, %{name: name}), do: true
  defp label?(_model, _column), do: false

  # The mark of the sort beside a sortable column's label.
  defp mark({name, :asc}, %{name: name}), do: " ▲"
  defp mark({name, :desc}, %{name: name}), do: " ▼"
  defp mark(_sort, _column), do: ""

  # ---- the filter row ---------------------------------------------------

  # The filter row: its bundle, its empty cells, and a `filter_cell` per
  # column, with its `filter` where the column filters.
  defp filters(id, model, geometry, given) do
    form = Ids.filters(id)

    %{
      row: Attrs.filter_row(id, geometry),
      select: if(given.selecting, do: Attrs.empty_cell("#{id}-select-filter", "1")),
      expander:
        if(given.expandable?, do: Attrs.empty_cell("#{id}-expander-filter", geometry.lead)),
      actions:
        if(geometry.trail == 1,
          do: Attrs.empty_cell("#{id}-actions-filter", geometry.colcount)
        ),
      cells:
        for {column, index} <- Enum.with_index(model.columns) do
          cell = "#{id}-filter-#{column.name}"
          filters? = column.operators != []

          %{
            element: %{
              "id" => cell,
              "aria-colindex" => Geometry.colindex(geometry, index),
              "data-filter" => filters?
            },
            filter: if(filters?, do: filter(id, cell, form, column, given))
          }
        end
    }
  end

  # What a column's filter shows: what was typed and rejected; else what
  # the row was last sent, an operator without its value among it, while the
  # table is filtered by what it was sent among (the filters before it, and
  # after: a change of the filters goes through the URL, and is not in the
  # state at once); else the filter that applies.
  defp shown(rejected, pending, state, name) do
    rejected[name] || (state.filters in pending.among && pending.controls[name]) ||
      state.filters[name]
  end

  # One column's filter: the controls it has by what its operator takes
  # (one value, a range, several: a button that opens the side panel, with
  # the values that apply as hidden inputs of the filter row's form), each
  # control's bundle, its clear button.
  defp filter(table, cell, form, column, given) do
    name = column.name
    filter = shown(given.rejected, given.pending, given.state, name)
    rejected? = is_map_key(given.rejected, name)
    applied? = is_map_key(given.state.filters, name)
    {operator, value} = filter || {nil, nil}
    takes = if operator, do: Map.fetch!(column.takes, operator), else: :one
    words = filter_words(column, value)
    texts = words.texts
    error = if rejected?, do: Ids.error(cell)

    control = fn suffix, field, label ->
      %{
        "id" => "#{cell}-#{suffix}",
        "name" => "filter[#{name}][#{field}]",
        "form" => form,
        "aria-label" => label
      }
    end

    typed = fn suffix, field, label, value, invalid? ->
      Map.merge(control.(suffix, field, label), %{
        "value" => value,
        "aria-invalid" => invalid? && "true",
        "aria-describedby" => error
      })
    end

    Map.merge(
      %{
        cell_type: plain(column.cell_type),
        takes: takes,
        # a boolean: one menu of its two values and "Any"
        yes_no:
          if(column.cell_type == :boolean,
            do: %{
              select: control.("value", "o", texts.filter),
              options: options(column.operators, texts.operators, operator)
            }
          ),
        # the operator, where the column has several
        operators:
          if(column.cell_type != :boolean and match?([_, _ | _], column.operators),
            do: %{
              select: control.("operator", "o", texts.filter_operator),
              options: options(column.operators, texts.operators, operator)
            }
          ),
        # an enum's one value
        choice:
          if(column.cell_type == :enum and takes == :one,
            do: %{
              select: control.("value", "v", texts.filter),
              options: values(column.values, &(&1 == value))
            }
          ),
        # a typed value
        input:
          if(column.cell_type not in [:boolean, :enum] and takes == :one,
            do: typed.("value", "v", texts.filter, value, rejected?)
          ),
        # the two ends of a range, each with the word that says which
        range:
          if(takes == :range,
            do:
              for {end_of, suffix, word, label, held} <- [
                    {"from", "value", texts.range_from, texts.filter_from, elem(value, 0)},
                    {"to", "to", texts.range_to, texts.filter_to, elem(value, 1)}
                  ] do
                %{
                  word: word,
                  input:
                    typed.(
                      suffix,
                      end_of,
                      label,
                      held,
                      rejected? and not is_nil(held) and not State.value?(column, held)
                    )
                }
              end
          ),
        # several values: the button that opens the side panel, which says
        # what is chosen, and the values that apply, sent with the row's form
        several:
          if(takes == :many,
            do: several(table, cell, form, column, operator, value || [], texts, given.myself)
          ),
        clear:
          if(applied? and not rejected?,
            do:
              Map.merge(
                %{"id" => "#{cell}-clear", "aria-label" => texts.clear_filter},
                Attrs.clear_filter(table, column, given.myself)
              )
          ),
        error: if(error, do: %{"id" => error})
      },
      words
    )
  end

  defp several(table, cell, form, column, operator, chosen, texts, myself) do
    labels = for {value, label} <- column.values, to_string(value) in chosen, do: label

    %{
      button:
        Map.merge(
          %{
            "id" => "#{cell}-value",
            "aria-haspopup" => "dialog",
            "aria-label" => "#{texts.filter}: #{texts.chosen}",
            "title" => labels != [] && Enum.join(labels, ", ")
          },
          Attrs.filter_values(table, column, operator, myself)
        ),
      # what it says is chosen
      says: texts.chosen,
      hidden:
        for(
          value <- chosen,
          do: %{"name" => "filter[#{column.name}][in][]", "value" => value, "form" => form}
        )
    }
  end

  # The options of an operator's menu: each its value, its words, whether
  # it is chosen.
  defp options(operators, said, operator) do
    for {choice, label} <- Enum.zip(operators, said),
        do: %{value: choice, label: label, chosen?: choice == operator}
  end

  # An enum's values as options: each its value as text, its label, whether
  # it is chosen.
  defp values(values, chosen?) do
    for {value, label} <- values do
      value = to_string(value)
      %{value: value, label: label, chosen?: chosen?.(value)}
    end
  end

  defp filter_words(column, value) do
    label = column.label

    Said.words(
      filter: Said.t(:filter, column: label),
      filter_operator: Said.t(:filter_operator, column: label),
      any: Said.t(:any),
      operators: Enum.map(column.operators, &operator(column, &1)),
      range_from: Said.t(:range_from),
      range_to: Said.t(:range_to),
      filter_from: Said.t(:filter_from, column: label),
      filter_to: Said.t(:filter_to, column: label),
      clear_filter: Said.t(:clear_filter, column: label),
      invalid_filter: Said.t(:invalid_filter),
      chosen: chosen(column, value)
    )
  end

  # What an operator of a column's filter is called: a boolean's are its
  # two values.
  defp operator(%{cell_type: :boolean}, choice), do: Said.t(choice)
  defp operator(_column, operator), do: Said.t(String.to_existing_atom("operator_#{operator}"))

  # What the button of a filter for several values says of what is chosen.
  defp chosen(%{values: values}, chosen) when is_list(values) and is_list(chosen) do
    case for {value, label} <- values, to_string(value) in chosen, do: label do
      [] -> Said.t(:any)
      [label] -> label
      labels -> Said.t(:values_chosen, count: length(labels))
    end
  end

  defp chosen(%{values: values} = column, nil) when is_list(values), do: chosen(column, [])
  defp chosen(_column, _value), do: nil

  # ---- the rows ---------------------------------------------------------

  # What every row is drawn with besides its item: whether it is selected
  # and expanded (and the box's name where one row at a time is), its
  # columns (each what a `cell` of it is drawn with), the row actions with
  # what varies of their buttons, "Open", the relationships of its lines,
  # how wide a line is, and where the actions cell stands (nil for none).
  defp row(id, model, geometry, selecting, expandable?, open, asks?) do
    label = model.label_column && model.label_column.name

    Map.merge(
      %{
        selecting: selecting,
        radio: if(selecting == :single, do: "#{id}-select"),
        expandable?: expandable?,
        lead: geometry.lead,
        columns:
          for(
            {column, index} <- Enum.with_index(model.columns),
            do: column(column, Geometry.colindex(geometry, index), column.name == label)
          ),
        actions:
          if(geometry.trail == 1,
            do: %{
              colindex: geometry.colcount,
              open: open,
              buttons:
                for(
                  action <- model.actions,
                  do: %{
                    name: action.name,
                    label: action.label,
                    attrs: Attrs.action(action, asks?)
                  }
                )
            }
          ),
        relationships:
          for(
            relationship <- model.relationships,
            do: %{
              name: relationship.name,
              label: relationship.label,
              cell: Attrs.line(relationship)
            }
          ),
        colspan: geometry.colcount
      },
      Said.words(select_row: Said.t(:select_row), related_records: Said.t(:related_records))
    )
  end

  # What a cell of a column is drawn with, the same on every row (the
  # projection of the `cell` part, beside the item's cell): its name and
  # label, where it stands and whether it is the row's header, how it shows
  # its values (`cell_type`, `max_lines`, an enum's values, its component),
  # whether it is sensitive, its cells' attributes that are the column's
  # (`Attrs.cell/2` of the column), what a failed cell shows of what was
  # typed (`typed`: by what was typed, its words; nil where it shows it as
  # it is), and its words.
  defp column(column, colindex, header?) do
    label = column.label

    words =
      Said.words(
        hidden_value: Said.t(:hidden_value),
        show: Said.t(:show),
        hide: Said.t(:hide),
        show_value: if(column.sensitive?, do: Said.t(:show_value, column: label)),
        hide_value: if(column.sensitive?, do: Said.t(:hide_value, column: label)),
        not_available: Said.t(:not_available)
      )

    Map.merge(
      %{
        name: column.name,
        label: label,
        colindex: colindex,
        header?: header?,
        cell_type: plain(column.cell_type),
        editor: column.editor,
        max_lines: column.max_lines,
        sensitive?: column.sensitive?,
        values: column.values && values(column.values, fn _value -> false end),
        attrs: Attrs.cell(column, %{attrs: %{}}),
        component:
          if(match?(%{cell?: true}, column.component),
            do: %{module: column.component.module, column: column.component.column}
          ),
        typed: typed(column)
      },
      words
    )
    |> Map.put(:locale, Said.locale())
  end

  # What a cell whose save failed shows of what was typed, as the cell
  # would show it had it been saved: of a boolean its yes or no, of an enum
  # its value's label; nil where what was typed is shown as it is (and of a
  # sensitive cell, which shows its mask).
  defp typed(%{sensitive?: true}), do: nil

  defp typed(%{editor: :boolean}),
    do: %{"true" => Said.say(Said.t(:yes)), "false" => Said.say(Said.t(:no))}

  defp typed(%{editor: :enum, values: values}) when is_list(values),
    do: Map.new(values, fn {value, label} -> {to_string(value), label} end)

  defp typed(_column), do: nil

  # A cell type as plain data: an array's is `%{array: item}`.
  defp plain({:array, item}), do: %{array: plain(item)}
  defp plain(cell_type), do: cell_type

  # ---- the footer -------------------------------------------------------

  # The footer: its element (hidden while it has nothing to show), the row
  # of the summaries where the table has one, and in a nested table its
  # pages and its link to the full view.
  defp footer(id, geometry, given) do
    page = given.page
    nested? = given.nested?
    pages? = Pagination.pages?(page, given.model)
    full_view? = not is_nil(page) and not is_nil(given.full_view)

    %{
      element: %{
        "id" => "#{id}-foot",
        "hidden" =>
          not (geometry.summary? and not is_nil(page)) and
            not (nested? and (pages? or full_view?))
      },
      summaries: if(geometry.summary? and page, do: summaries(id, geometry, given)),
      pager:
        if(nested? and pages?,
          do: %{
            row: Attrs.row("#{id}-foot-row"),
            cell: Attrs.spanning("#{id}-pager", geometry, %{"data-pager" => true}),
            pagination:
              AshDataTable.Kit.Projection.of(:pagination, %{
                id: id,
                nested?: true,
                page: page,
                model: given.model,
                state: given.state,
                row_count: given.row_count,
                label: given.label,
                target: given.myself
              })
          }
        ),
      full_view:
        if(nested? and full_view?,
          do:
            FullView.of(%{
              id: id,
              full_view: given.full_view,
              label: given.label,
              geometry: geometry
            })
        )
    }
  end

  # The row of the summaries: its bundle, its empty cells, and a
  # `summary_cell` per column.
  defp summaries(id, geometry, given) do
    %{
      row: Attrs.summaries(id, geometry, given.page),
      select:
        if(given.selecting,
          do: %{"id" => "#{id}-summaries-select", "role" => "cell", "aria-colindex" => "1"}
        ),
      expander:
        if(given.expandable?,
          do: %{
            "id" => "#{id}-summaries-expander",
            "role" => "cell",
            "aria-colindex" => geometry.lead
          }
        ),
      actions:
        if(geometry.trail == 1,
          do: %{
            "id" => "#{id}-summaries-actions",
            "role" => "cell",
            "aria-colindex" => geometry.colcount
          }
        ),
      cells:
        for {column, index} <- Enum.with_index(given.model.columns) do
          held = given.summary && given.summary[column.name]

          Map.merge(
            %{
              element:
                Map.merge(
                  %{
                    "id" => "#{id}-summary-#{column.name}",
                    "aria-colindex" => Geometry.colindex(geometry, index)
                  },
                  Attrs.summary(column, given.summing?)
                ),
              summary?: not is_nil(column.summary),
              # what the summary is: `:ok` with its `value` and `text`,
              # `:unavailable`, or nil while there is no answer yet
              state:
                case held do
                  {:ok, _value} -> :ok
                  :unavailable -> :unavailable
                  nil -> nil
                end,
              value:
                case held do
                  {:ok, value} -> value
                  _other -> nil
                end,
              text:
                case held do
                  {:ok, value} -> Format.summary(column, value, given.time_zone)
                  _other -> nil
                end
            },
            Said.words(
              kind: column.summary && Said.t(summary_key(column.summary)),
              not_available: Said.t(:not_available)
            )
          )
          |> Map.put(:locale, Said.locale())
        end
    }
  end

  defp summary_key(:count), do: :summary_count
  defp summary_key(:sum), do: :summary_sum
  defp summary_key(:avg), do: :summary_avg
  defp summary_key(:min), do: :summary_min
  defp summary_key(:max), do: :summary_max

  # ---- the editors ------------------------------------------------------

  # The editors' templates, one per editable column, which the hook copies
  # into a cell it opens: each its template's bundle, and the projection of
  # its `editor` (nil where the cell has no editor in it: the picker or the
  # panel edits it), or its column's component's editor.
  @built_in [:text, :number, :boolean, :date, :datetime, :enum]

  defp editors(id, model, asks?) do
    for column <- model.columns, column.editable? do
      template = Ids.editor(id, column.name)

      %{
        name: column.name,
        template: Attrs.editor_template(id, column, asks?),
        editor: if(column.editor in @built_in, do: editor(template, column)),
        component:
          if(column.editor == :component,
            do: %{
              module: column.component.module,
              column: column.component.column,
              label: column.label,
              limits: Limits.of(column),
              control: Attrs.component_control(column)
            }
          )
      }
    end
  end

  # What the `editor` part is given of its control: the limits of a number,
  # the counter of a text with a most it can be long (and its control's
  # bundle), whether a sensitive cell can be emptied, its words.
  defp editor(template, column) do
    counted = Limits.counted(column)

    Map.merge(
      %{
        id: template,
        label: column.label,
        editor: column.editor,
        required?: column.required?,
        sensitive?: column.sensitive?,
        values: column.values && values(column.values, fn _value -> false end),
        limits: Limits.of(column),
        counted: counted,
        count:
          if(counted && column.editor == :text, do: Count.of("#{template}-count", counted, "")),
        control:
          if(counted && column.editor == :text, do: Attrs.counted_control(template, column)),
        clearable?: Edit.clearable?(column)
      },
      Said.words(clear: Said.t(:clear), clear_value: Said.t(:clear_value, column: column.label))
    )
  end
end
