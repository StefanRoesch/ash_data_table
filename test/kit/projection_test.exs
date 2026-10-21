defmodule AshDataTable.Kit.ProjectionTest do
  @moduledoc """
  The projections of `AshDataTable.Kit.Projection`, part by part: that
  each goes to JSON as it is, says what `AshDataTable.Kit.Words` says of
  its part (while the parts still draw from it), and its derived facts.
  """
  use ExUnit.Case, async: true

  alias AshDataTable.Geometry
  alias AshDataTable.Kit.Projection
  alias AshDataTable.Kit.Words
  alias AshDataTable.Model
  alias AshDataTable.State
  alias AshDataTable.Test.Resource

  defp model, do: Model.build(Resource)

  defp json!(projection), do: projection |> Jason.encode!() |> Jason.decode!()

  defp page(fields \\ []),
    do: struct(AshDataTable.Query.Page, Keyword.merge([total: 6, pages: 2, offset: 0], fields))

  test "status: the live region, the run's result, the no-break space every other time" do
    result = %{summary: {:text, :records, count: 2}, failures: [{:text, :not_available, []}]}
    given = %{id: "t", announcement: {:text, :loading, []}, announcements: 3, result: result}
    projection = Projection.of(:status, given)

    assert projection.again?
    assert projection.region["id"] == "t-status"
    assert projection.result == %{id: "t-result"}
    assert projection.texts == Words.texts(:status, given)
    assert projection.messages == Words.messages(:status, given)
    refute Projection.of(:status, %{given | announcements: 2, result: nil}).result
    json!(projection)
  end

  test "message: one per message said in place of the rows, in its order" do
    given = %{id: "t", error: nil, fill: nil, loading?: true, row_count: 0, nested?: true}

    assert [%{kind: :loading, element: %{"id" => "t-loading"}, nested?: true} = loading] =
             Projection.of(:message, given)

    assert loading.text == Words.text(:message, %{message: {:text, :loading, []}})
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
    assert projection.texts == Words.texts(:confirm)
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

    assert Enum.map(projection.pages, & &1.number) ==
             Words.value(:pagination, %{page: given.page, state: state})

    assert [%{current?: false}, %{current?: true, button: %{"aria-current" => "page"}}] =
             projection.pages

    refute projection.previous["disabled"]
    assert projection.next["disabled"]
    assert projection.next["phx-value-to"] == "next"
    assert projection.texts == Words.texts(:pagination, given)
    assert projection.messages == Words.messages(:pagination, given)
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
    assert projection.texts == Words.texts(:picker, given)
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
    assert projection.texts == Words.texts(:related, %{via: via, title: "Anchor"})
    assert Projection.of(:related, %{given | title: nil}).record == nil
    json!(projection)

    geometry = Geometry.of(model(), :multi, true, nil)

    view =
      Projection.of(:full_view, %{id: "t", full_view: "/p", label: "Parts", geometry: geometry})

    assert view.link == %{id: "t-full-view", path: "/p"}
    assert view.texts == Words.texts(:full_view, %{label: "Parts"})
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

    words = %{page: given.page, selected: 5, all?: false}
    assert projection.texts == Words.texts(:selection_line, words)
    assert projection.messages == Words.messages(:selection_line, words)

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
    assert projection.name == %{element: %{"id" => "t-name"}, level: 2, text: "Things"}
    assert projection.acts?

    hideable =
      Enum.reject(model.columns, &(model.label_column && &1.name == model.label_column.name))

    words = %{
      columns: hideable,
      label_column: model.label_column,
      state: given.state,
      label: "Things",
      nested?: false
    }

    assert projection.columns.texts == Words.texts(:columns, words)
    assert length(projection.columns.entries) == length(hideable)

    expected = Words |> apply(:texts, [:argument, argument_words(model)])
    assert hd(projection.argument_line.arguments).texts == expected

    assert Projection.of(:heading, %{given | nested?: true}).name == nil
    json!(projection)
  end

  defp argument_words(model) do
    argument = hd(model.arguments)
    value = Model.Argument.shown(argument, %State{}, %{})
    %{argument: argument, value: value, errors: []}
  end
end
