defmodule AshDataTable.TestTest do
  # `AshDataTable.Test` reads a page as the browser shows it and sends what
  # a browser sends, where `Phoenix.LiveViewTest` does not look: inside a
  # `<.portal>`. A small LiveView with a component that draws a form into a
  # portal, as the table component draws a nested table.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :ash_data_table
  end

  defmodule Drawn do
    use Phoenix.LiveComponent

    def mount(socket), do: {:ok, assign(socket, got: [])}

    def handle_event(event, params, socket),
      do: {:noreply, assign(socket, got: socket.assigns.got ++ [{event, params}])}

    def render(assigns) do
      ~H"""
      <div id="t">
        <pre id="got">{Jason.encode!(Enum.map(@got, &Tuple.to_list/1))}</pre>
        <div id="t-row-1-n-comments-c"></div>
        <.portal id="t-row-1-t-comments-portal" target="[id='t-row-1-n-comments-c']">
          <div id="t-row-1-t-comments-grid" phx-target={@myself}>
            <form
              id="t-row-1-t-comments-filter"
              phx-change="ash_data_table:t-row-1-t-comments:filter"
              phx-submit="ash_data_table:t-row-1-t-comments:filter"
              phx-target={@myself}
            >
              <input type="text" name="filter[body]" value="hello" />
              <input type="checkbox" name="filter[open]" value="true" checked />
              <input type="checkbox" name="filter[closed]" value="true" />
              <select name="filter[operator]">
                <option value="eq">is</option>
                <option value="contains" selected>contains</option>
              </select>
              <input type="text" name="filter[off]" value="no" disabled />
            </form>
          </div>
        </.portal>
        <input type="text" name="filter[outside]" value="far" form="t-row-1-t-comments-filter" />
      </div>
      """
    end
  end

  defmodule Page do
    use Phoenix.LiveView

    def render(assigns) do
      ~H"""
      <.live_component module={Drawn} id="t" />
      """
    end
  end

  @endpoint Endpoint

  setup_all do
    Application.put_env(:ash_data_table, Endpoint,
      secret_key_base: String.duplicate("a", 64),
      live_view: [signing_salt: "ash_data_table_test"]
    )

    start_supervised!(Endpoint)
    :ok
  end

  setup do
    {:ok, view, _html} = live_isolated(Phoenix.ConnTest.build_conn(), Page)
    %{view: view}
  end

  defp got(view) do
    view
    |> render()
    |> AshDataTable.Test.page()
    |> LazyHTML.query("#got")
    |> LazyHTML.text()
    |> Jason.decode!()
    |> Enum.map(&List.to_tuple/1)
  end

  test "page/1 puts a portal's content into its target, once and without the wrapper",
       %{view: view} do
    html = render(view)
    assert html =~ "data-phx-portal"
    page = AshDataTable.Test.page(html)

    assert [_grid] = Enum.to_list(LazyHTML.query(page, "[id='t-row-1-t-comments-grid']"))

    assert [_grid] =
             Enum.to_list(
               LazyHTML.query(
                 page,
                 "[id='t-row-1-n-comments-c'] > [id='t-row-1-t-comments-grid']"
               )
             )

    assert Enum.empty?(LazyHTML.query(page, "[id^='_lv_portal_wrap_']"))
  end

  test "send_form/5 sends a form in a portal as the browser does: checked boxes, the selected option, a control outside it that names it, the given values merged in",
       %{view: view} do
    AshDataTable.Test.send_form(view, "[id='t-row-1-t-comments-filter']", :change, %{
      filter: %{body: "typed"}
    })

    AshDataTable.Test.send_form(view, "[id='t-row-1-t-comments-filter']", :submit, %{})

    assert [{"ash_data_table:t-row-1-t-comments:filter", changed}, {_, submitted}] = got(view)

    assert changed == %{
             "filter" => %{
               "body" => "typed",
               "open" => "true",
               "operator" => "contains",
               "outside" => "far"
             }
           }

    assert submitted["filter"]["body"] == "hello"
  end

  test "send_form/5 raises on a name the form lacks, a disabled control's among them",
       %{view: view} do
    for name <- [:nothing, :off] do
      assert_raise ArgumentError, ~r/could not find non-disabled input/, fn ->
        AshDataTable.Test.send_form(view, "[id='t-row-1-t-comments-filter']", :change, %{
          filter: %{name => "x"}
        })
      end
    end

    assert got(view) == []
  end

  test "send_event/5 sends a table in a portal its event by its name", %{view: view} do
    AshDataTable.Test.send_event(view, "t-row-1-t-comments", "sort", %{"column" => "body"})

    assert got(view) == [{"ash_data_table:t-row-1-t-comments:sort", %{"column" => "body"}}]
  end

  test "send_event/5 raises for a table that is on no page", %{view: view} do
    assert_raise ArgumentError, ~r/but got none/, fn ->
      AshDataTable.Test.send_event(view, "elsewhere", "sort", %{"column" => "body"})
    end
  end

  test "table_named/1 is the id between the first and the last colon" do
    assert AshDataTable.Test.table_named("ash_data_table:a:b-row-1-t-c:sort") == "a:b-row-1-t-c"

    assert_raise ArgumentError, ~r/names no table/, fn ->
      AshDataTable.Test.table_named("sort")
    end
  end
end
