defmodule AshDataTable.Kit.ProjectionTest do
  @moduledoc """
  The projections of `AshDataTable.Kit.Projection`, part by part: that
  each goes to JSON as it is, says its texts beside the messages they are
  made of, and its derived facts.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Geometry
  alias AshDataTable.Kit.Projection
  alias AshDataTable.Model
  alias AshDataTable.State
  alias AshDataTable.Test.Resource

  defp model, do: Model.build(Resource)

  defp json!(projection), do: projection |> Jason.encode!() |> Jason.decode!()

  defp page(fields \\ []),
    do: struct(AshDataTable.Query.Page, Keyword.merge([total: 6, pages: 2, offset: 0], fields))

  # Each part's keys, as `AshDataTable.Kit.Projection`'s moduledoc lists
  # them under its heading.
  defp documented do
    {:docs_v1, _anno, _language, _format, %{"en" => doc}, _meta, _docs} =
      Code.fetch_docs(Projection)

    doc
    |> String.split("\n### ")
    |> tl()
    |> Map.new(fn part ->
      [heading | lines] = String.split(part, "\n")
      [_, name] = Regex.run(~r/^`(\w+)`/, heading)

      keys =
        for line <- lines,
            [_, names] <- [Regex.run(~r/^  \* ((?:`[\w?]+`(?:, )?)+)(?: -|$)/, line)],
            [_, key] <- Regex.scan(~r/`([\w?]+)`/, names),
            do: String.to_atom(key)

      {String.to_atom(name), keys}
    end)
  end

  test "every part's projection is documented, key by key, both ways" do
    documented = documented()
    assert Enum.sort(Map.keys(documented)) == Enum.sort(Projection.parts())
    assert Enum.sort(Projection.parts()) == Enum.sort(AshDataTable.Kit.parts())

    for {part, keys} <- documented do
      assert Enum.sort(Enum.uniq(keys)) == Enum.sort(Projection.keys(part)),
             "#{part}: documented but none #{inspect(keys -- Projection.keys(part))}, " <>
               "there but not documented #{inspect(Projection.keys(part) -- keys)}"
    end
  end

  test "status: the live region, the run's result, the no-break space every other time" do
    result = %{summary: {:text, :records, count: 2}, failures: [{:text, :not_available, []}]}
    given = %{id: "t", announcement: {:text, :loading, []}, announcements: 3, result: result}
    projection = Projection.of(:status, given)

    assert projection.again?
    assert projection.region["id"] == "t-status"
    assert projection.result == %{id: "t-result"}

    assert projection.texts == %{
             announcement: "Loading…",
             summary: "2 records",
             failures: ["Not available"]
           }

    assert projection.messages.summary == %{key: :records, values: %{count: 2}}
    refute Projection.of(:status, %{given | announcements: 2, result: nil}).result
    json!(projection)
  end

  test "message: one per message said in place of the rows, in its order" do
    given = %{id: "t", error: nil, fill: nil, loading?: true, row_count: 0, nested?: true}

    assert [%{kind: :loading, element: %{"id" => "t-loading"}, nested?: true} = loading] =
             Projection.of(:message, given)

    assert %{text: "Loading…", message: %{key: :loading, values: %{}}} = loading
    assert [%{kind: :empty}] = Projection.of(:message, %{given | loading?: false})

    assert [%{kind: :error, element: %{"role" => "alert"}}] =
             Projection.of(:message, %{
               given
               | loading?: false,
                 error: {:text, :not_available, []}
             })

    json!(Projection.of(:message, given))
  end

  test "confirm: whether the table asks, and the question's place" do
    given = %{id: "t", model: model(), bulk: [], presentation: :inline, place: :panel}
    projection = Projection.of(:confirm, given)

    assert projection.asks?
    assert projection.holder == %{"id" => "t-dialogs-in-panel", "phx-update" => "ignore"}
    assert projection.question == %{"id" => "t-dialog-question-in-panel"}
    assert projection.texts == %{cancel: "Cancel", confirm: "Confirm"}
    json!(projection)
  end

  test "pagination: the pages offered, their buttons, the page sizes" do
    model = model()
    state = %State{page: 2, per: nil}

    given = %{
      id: "t",
      nested?: false,
      page: page(previous: %State{page: 1}, offset: 5),
      model: model,
      state: state,
      row_count: 1,
      label: "Things",
      target: nil
    }

    projection = Projection.of(:pagination, given)

    assert Enum.map(projection.pages, & &1.number) == [1, 2]

    assert [%{current?: false}, %{current?: true, button: %{"aria-current" => "page"}}] =
             projection.pages

    refute projection.previous["disabled"]
    assert projection.next["disabled"]
    assert projection.next["phx-value-to"] == "next"

    assert projection.texts == %{
             label: "Pagination: Things",
             range: "6–6 of 6",
             previous: "Previous",
             next: "Next",
             rows_per_page: "Rows per page",
             go_to_page: ["Go to page 1", "Go to page 2"]
           }

    assert projection.messages.range == %{
             key: :range_of_total,
             values: %{from: 6, to: 6, total: 6}
           }

    assert Projection.Pagination.pages?(given.page, model)
    refute Projection.Pagination.pages?(nil, model)
    json!(projection)
  end

  test "picker: drawn closed, with its place" do
    given = %{id: "t", picker: nil, presentation: :modal, target: nil, takes?: false}
    projection = Projection.of(:picker, given)

    refute projection.open?
    assert projection.place == %{"id" => "t-picker-place"}
    refute projection.frame || projection.take || projection.none

    assert %{cancel: "Cancel", choose: "Choose", choose_none: "None", title: nil} =
             projection.texts

    json!(projection)
  end

  test "related and the full view: the heading's words around the record" do
    via = %{label: "Parts"}

    given = %{
      id: "t",
      via: via,
      title: "Anchor",
      parent: %{path: "/owners"},
      clear: "/t",
      page: page(),
      create: nil,
      offered: [],
      target: nil
    }

    projection = Projection.of(:related, given)
    assert projection.record == %{id: "t-related-parent", path: "/owners", title: "Anchor"}

    assert projection.texts == %{
             relationship: "Parts",
             heading: "Anchor: Parts",
             heading_before: "",
             heading_after: ": Parts",
             show_all_records: "Show all records"
           }

    assert Projection.of(:related, %{given | title: nil}).record == nil
    json!(projection)

    geometry = Geometry.of(model(), :multi, true, nil)

    view =
      Projection.of(:full_view, %{id: "t", full_view: "/p", label: "Parts", geometry: geometry})

    assert view.link == %{id: "t-full-view", path: "/p"}

    assert view.texts == %{
             full_view: "Open in full view",
             full_view_of: "Open in full view: Parts"
           }

    json!(view)
  end

  test "selection line: what is selected, the buttons, all that match" do
    model = model()
    bulk = Enum.filter(model.actions, & &1.bulk?)

    given = %{
      id: "t",
      bulk: bulk,
      choose: nil,
      notice?: true,
      page: page(),
      row_count: 5,
      running: nil,
      selecting: :multi,
      selected: 5,
      all?: false,
      whole_page?: true,
      state: %State{filters: %{name: {:eq, "x"}}},
      nested?: false,
      myself: nil
    }

    projection = Projection.of(:selection_line, given)
    assert projection.shown?
    refute projection.selection.select_all["hidden"]
    assert projection.notice.read_again["id"] == "t-read-again"
    assert projection.clear_filters["id"] == "t-clear-filters"

    assert %{selected: "5 selected", select_all: "Select all 6 that match"} = projection.texts
    assert projection.messages.selected == %{key: :selected, values: %{count: 5}}

    # in a table to choose from, never "all that match"
    assert Projection.of(:selection_line, %{given | choose: :multi}).selection.select_all[
             "hidden"
           ]

    refute Projection.of(:selection_line, %{given | selecting: nil}).selection
    json!(projection)
  end

  test "heading: the line, Columns, the argument line, create and the table actions" do
    model = model()

    given = %{
      id: "t",
      heading: 2,
      label: "Things",
      model: model,
      offered: model.table_actions,
      page: page(),
      related: nil,
      nested?: false,
      myself: nil,
      state: %State{},
      lines: %{},
      refused: %{}
    }

    projection = Projection.of(:heading, given)
    assert projection.shown?
    assert projection.title == %{element: %{"id" => "t-name"}, level: 2, text: "Things"}
    assert projection.acts?

    assert %{
             columns: "Columns",
             columns_name: "Columns",
             columns_with: "Columns ({details})",
             reset_widths: "Reset widths"
           } = projection.columns.texts

    hideable =
      Enum.reject(model.columns, &(model.label_column && &1.name == model.label_column.name))

    assert length(projection.columns.entries) == length(hideable)
    assert hd(projection.argument_line.arguments).texts.add_value == "Add value"

    assert Projection.of(:heading, %{given | nested?: true}).title == nil
    json!(projection)
  end

  test "heading: an argument's input, what the person chose and what Ash refused of it" do
    model = model()
    [argument] = model.arguments
    key = Model.Argument.key(argument)

    given = %{
      id: "t",
      heading: false,
      label: "T",
      model: model,
      offered: [],
      page: nil,
      related: nil,
      nested?: false,
      myself: nil,
      state: %State{},
      lines: %{},
      refused: %{}
    }

    [input] = Projection.of({:heading, :argument_line}, given).arguments

    assert Map.take(input, [:id, :named, :name, :value, :invalid?, :limits, :counted]) == %{
             id: "t-arg-near",
             named: "near",
             name: "arguments[a][near]",
             value: "",
             invalid?: false,
             limits: %{min: nil, max: nil, step: nil},
             counted: nil
           }

    assert input.texts.add_value == "Add value"

    state = %State{arguments: %{key => "x"}}
    refused = %{key => %{typed: "y", messages: [{:ash, "is required", []}], held: nil}}

    assert [%{value: "x"}] =
             Projection.of({:heading, :argument_line}, %{given | state: state}).arguments

    assert [%{value: "y", invalid?: true, error: %{"id" => "t-arg-near-error"}} = refusal] =
             Projection.of({:heading, :argument_line}, %{given | state: state, refused: refused}).arguments

    assert refusal.texts.errors == ["is required"]
    assert refusal.messages.errors == [%{key: :ash, values: %{message: "is required", vars: %{}}}]
    json!(refusal)
  end

  test "panel: each field's projection, with what a value made of fields holds" do
    model = model()
    inputs = Map.new(model.create.inputs, &{&1.name, &1})

    field = fn name, value ->
      %AshDataTable.Present.Field{
        name: name,
        path: [Atom.to_string(name)],
        form_name: "panel[#{name}]",
        input: inputs[name],
        value: value
      }
    end

    panel = %AshDataTable.Present.Panel{
      title: {:text, :create, []},
      submit: {:text, :create, []},
      ask: nil,
      method: "post",
      fields: [
        field.(:name, "Anchor"),
        field.(:size, "3"),
        field.(:place, %{"_present" => "", "city" => "Bern", "zip" => "3000"}),
        field.(:stops, %{"_present" => "", "0" => %{"_present" => "", "city" => "Thun"}}),
        field.(:kind, %{"_union_type" => "count", "_union_value" => "7"}),
        field.(:tags, ["red"])
      ],
      inside: %{errors: %{}, touched: MapSet.new(), submitted?: false, time_zone: "Etc/UTC"}
    }

    given = %{id: "t", panel: panel, presentation: :modal, target: nil, files: %{}}
    projection = Projection.of(:panel, given)
    assert projection.open?
    assert projection.form["id"] == "t-panel-form"
    fields = Map.new(projection.fields, &{&1.element["data-field"], &1})

    for {_name, field} <- fields,
        do: assert(Enum.sort(Map.keys(field)) == Enum.sort(Projection.keys(:field)))

    assert %{id: "t-panel-f-name", counted: %{max: 40}, count: %{length: 6}} = fields["name"]
    assert fields["size"].limits == %{min: "0", max: "100", step: "1"}
    assert %{control: %{id: "t-panel-f-size", editor: :number}} = fields["size"]

    # a value made of fields: its members, each a field as the panel's,
    # with the hidden entries it sends beside them (named by
    # `AshDataTable.GroupValue`, whose tests say how)
    assert %{hidden: [present], fields: [city, _zip]} = fields["place"].group.members
    assert Map.keys(present) == ["name", "value"]
    assert %{value: "Bern", label: _} = city
    assert fields["place"].group.remove["phx-click"] == "ash_data_table:t:panel_remove"
    refute fields["place"].group.add

    # a list of them: an item per value, under its own number, and its own entry
    assert [%{key: "0", members: stop} = item] = fields["stops"].groups.items
    assert is_binary(item.element["id"]) and is_binary(item.remove["id"])
    assert fields["stops"].groups.add["phx-click"] == "ash_data_table:t:panel_add"
    assert %{fields: [%{value: "Thun"} | _]} = stop
    assert [_own] = fields["stops"].groups.hidden

    # a union: the kind chosen, its one value, what its choice is sent under
    # and the entry that says which kind its value is of
    assert %{kind: "count", single: %{value: "7"}, members: nil} = fields["kind"].union
    assert is_binary(fields["kind"].union.select["name"])
    assert [%{"value" => "count"}] = fields["kind"].union.hidden
    refute fields["tags"].group || fields["tags"].groups || fields["tags"].union
    assert %{rows: [%{value: "red", position: 1}]} = fields["tags"].list

    json!(projection)

    # drawn closed: none while the panel is closed
    closed = Projection.of(:panel, %{given | panel: nil})
    refute closed.open?
    assert closed.fields == [] and closed.frame == nil
    assert closed.place == %{"id" => "t-panel-place"}
  end
end
