defmodule AshDataTable.KitCase do
  @moduledoc """
  Checks a kit (`AshDataTable.Kit`) in a host's own tests: it draws a
  table of `AshDataTable.Test.Resource` through the kit in every state, in
  both presentations, and asserts that each state carries the markers the
  table's hooks find their elements by, the element kinds they need, and
  that no state holds the test resource's sensitive value.

      defmodule MyAppWeb.TableKitTest do
        use AshDataTable.KitCase, kit: MyAppWeb.TableKit, endpoint: MyAppWeb.Endpoint
      end

  The states: the rows of a page (`:rows`, with the editors of the cells),
  no records (`:empty`), a read that failed (`:error`), a nested table whose
  first read is on its way (`:loading`) and one that has read (`:nested`),
  a cell whose save failed (`:failed`), a row action's panel with a file
  (`:panel`), a map cell's panel (`:map_panel`), the picker of a reference
  cell (`:picker`), and the result of an action on selected rows
  (`:selected`). Each is drawn with the action panel and the picker opened
  over the page (`:modal`) and in it (`:inline`).

  What a person does with the keyboard and hears from a screen reader is
  not checked here: that needs a browser. The library checks it for
  `AshDataTable.Kit.Default` and for a kit drawn with `div`s in its own
  browser suite.

  It runs with `Phoenix.LiveViewTest` (`live_isolated/3`) on the endpoint
  given, and keeps the test resource's records in memory, in a tenant of
  each test's own: the tests run `async`.
  """

  import ExUnit.Assertions

  # a test dependency of the host's, as for `AshDataTable.Test`
  @compile {:no_warn_undefined, [LazyHTML]}

  alias AshDataTable.Test.Resource

  @table "kit"
  @states [:rows, :empty, :error, :loading, :nested, :failed, :panel, :map_panel, :picker] ++
            [:selected]

  @doc "The states a kit is drawn in."
  def states, do: @states

  defmacro __using__(opts) do
    kit = Keyword.fetch!(opts, :kit)
    endpoint = Keyword.fetch!(opts, :endpoint)

    quote do
      use ExUnit.Case, async: true

      import Phoenix.LiveViewTest

      @endpoint unquote(endpoint)
      @kit unquote(kit)

      for presentation <- [:modal, :inline], state <- AshDataTable.KitCase.states() do
        @presentation presentation
        @state state

        test "#{inspect(@kit)} draws the state #{@state}, what opens #{@presentation}" do
          {tenant, key, session} = AshDataTable.KitCase.given(@kit, @state, @presentation)
          on_exit(fn -> AshDataTable.KitCase.clean(tenant) end)

          {:ok, view, _html} =
            live_isolated(Phoenix.ConnTest.build_conn(), AshDataTable.KitCase.Live,
              session: session
            )

          AshDataTable.KitCase.check(view, key, @state, @presentation)
        end
      end
    end
  end

  # ---- the records -------------------------------------------------------

  @doc false
  # A tenant of the test's own with the records of `state`, the key of the
  # first record, and the session of the LiveView that draws them.
  def given(kit, state, presentation) do
    prefix = if state == :error, do: "broken", else: "kit"
    tenant = "#{prefix}-#{System.unique_integer([:positive])}"
    key = if state not in [:empty, :error], do: seed(tenant)

    {tenant, key,
     %{
       "kit" => kit,
       "tenant" => tenant,
       "presentation" => [panel: presentation, picker: presentation]
     }}
  end

  defp seed(tenant) do
    opts = [tenant: tenant, authorize?: false]
    create = &Ash.create!(&1, &2, opts)
    ann = create.(Resource.Owner, %{name: "Ann"})
    create.(Resource.Owner, %{name: "Bob"})

    first =
      create.(Resource, %{
        name: "Anchor",
        note: "A note long enough to be cut off after two lines of its column",
        secret: Resource.secret(),
        done: true,
        size: 40,
        place: %{city: "Bern", zip: "3000"},
        kind: 7,
        owner_id: ann.id
      })

    create.(Resource, %{name: "Bolt", secret: Resource.secret(), size: 3, kind: "loose"})
    create.(Resource, %{name: "Cog", secret: Resource.secret()})
    create.(Resource.Part, %{title: "Pin", resource_id: first.id})
    create.(Resource.Part, %{title: "Plate", resource_id: first.id})
    first.id
  end

  @doc false
  def clean(tenant) do
    for resource <- [Resource, Resource.Owner, Resource.Part],
        do: Ash.DataLayer.Ets.stop(resource, tenant)
  end

  # ---- the states --------------------------------------------------------

  @doc false
  # Brings the table into `state` and checks every page it draws on the
  # way there.
  def check(view, key, state, presentation) do
    pages = drive(view, state, key)

    for {html, at} <- pages do
      refute html =~ Resource.secret(),
             "the page holds the sensitive value of AshDataTable.Test.Resource (#{at})"

      page = AshDataTable.Test.page(html)
      problems = common(page, at) ++ special(page, at, key, presentation)

      assert problems == [],
             "the kit draws the state #{inspect(at)} without:\n  " <> Enum.join(problems, "\n  ")
    end
  end

  defp event(view, name, payload), do: AshDataTable.Test.send_event(view, @table, name, payload)

  defp drive(view, state, _key) when state in [:rows, :empty, :error],
    do: [{Phoenix.LiveViewTest.render(view), state}]

  defp drive(view, :loading, key) do
    event(view, "expand", %{"row" => key})
    [{event(view, "toggle", %{"row" => key, "relationship" => "parts"}), :loading}]
  end

  defp drive(view, :nested, key) do
    event(view, "expand", %{"row" => key})
    event(view, "toggle", %{"row" => key, "relationship" => "parts"})
    [{Phoenix.LiveViewTest.render_async(view, 5_000), :nested}]
  end

  defp drive(view, :failed, key),
    do: [{event(view, "save", %{"row" => key, "column" => "name", "value" => ""}), :failed}]

  defp drive(view, :panel, key),
    do: [{event(view, "act", %{"row" => key, "action" => "stamp"}), :panel}]

  defp drive(view, :map_panel, key),
    do: [{event(view, "edit", %{"row" => key, "column" => "place"}), :map_panel}]

  defp drive(view, :picker, key) do
    event(view, "pick", %{"row" => key, "column" => "owner"})
    [{Phoenix.LiveViewTest.render_async(view, 5_000), :picker}]
  end

  defp drive(view, :selected, key) do
    event(view, "select", %{"rows" => [key]})
    event(view, "bulk_run", %{"action" => "destroy"})
    [{Phoenix.LiveViewTest.render_async(view, 5_000), :selected}]
  end

  # ---- what every state has ---------------------------------------------

  @columns ~w(name note secret done size place kind owner)

  defp common(page, :error), do: need(page, "[id='kit-error'][role=alert]", "the read's error")

  defp common(page, _state) do
    grid =
      need(
        page,
        "[id='kit-grid'][data-ash-data-table][data-table='kit'][phx-hook]",
        "the grid's hook"
      ) ++
        need(page, "[id='kit-sender'][data-sender][data-table='kit'][phx-hook]", "its sender") ++
        need(page, "[id='kit-table'][role=grid][aria-colcount]", "the grid") ++
        need(page, "[id='kit-table'] [id='kit-head']", "its header in it") ++
        need(page, "[id='kit-head'] [id='kit-head-row'][role=row]", "the row of the headers") ++
        need(page, "[id='kit-head'] [id='kit-filter-row'][role=row]", "the filter row") ++
        need(page, "form[id='kit-filters']", "the filter row's form") ++
        need(page, "[id='kit-whole'][data-whole][popover]", "the whole-text popover") ++
        need(page, "[id='kit-status'][role=status]", "the live region") ++
        need(page, "dialog[id='kit-dialog'][role=dialog]", "the question dialog, a <dialog>") ++
        need(page, "[id='kit-dialog'] [id='kit-dialog-question']", "where it asks") ++
        need(page, "[id='kit-dialog'] button[value='cancel']", "its Cancel") ++
        need(page, "[id='kit-dialog'] button[value='confirm']", "its Confirm") ++
        need(page, "[id='kit-selection'][data-selection]", "the selection line") ++
        need(page, "[id='kit-selected']", "what is selected") ++
        need(page, "[id='kit-selection-controls']", "the selection's buttons") ++
        need(page, "[id='kit-select-all'][data-select-all]", "Select all") ++
        need(page, "[id='kit-clear-selection'][data-clear]", "Clear selection") ++
        need(page, "[data-bulk='destroy']", "the action on the selection") ++
        need(page, "[id='kit-columns-button'][data-columns-button]", "the Columns button") ++
        need(page, "[id='kit-columns'][data-columns-list]", "the Columns list") ++
        need(page, "[id='kit-columns-control']", "its control") ++
        need(page, "[id='kit-columns-status']", "what it says") ++
        need(page, "[id='kit-columns-text']", "its text") ++
        need(page, "[id='kit-scrollbar'][data-scrollbar]", "the scrollbar") ++
        need(page, "template[id='kit-failure']", "the failure template") ++
        need(
          page,
          "[id='kit-select-head'][role=columnheader][data-select-page]",
          "the box of the page"
        )

    columns =
      Enum.flat_map(@columns, fn field ->
        need(
          page,
          "[id='kit-head-#{field}'][role=columnheader][aria-colindex][tabindex='-1']",
          "the header of #{field}"
        ) ++
          need(
            page,
            "[id='kit-head-#{field}'] [id='kit-resize-#{field}'][data-resize]",
            "its handle"
          ) ++
          need(
            page,
            "[id='kit-filter-#{field}'][role=gridcell][aria-colindex][tabindex='-1']",
            "the filter cell of #{field}"
          )
      end)

    editors =
      Enum.flat_map(~w(name note secret done size), &editor(page, &1)) ++
        need(page, "template[id='kit-editor-note'][data-confirm]", "the question of note")

    grid ++ columns ++ editors ++ constants(page)
  end

  # What every cell, header, row and record is, whatever the kit draws it with.
  defp constants(page) do
    none(page, "[role=gridcell]:not([aria-colindex])", "a cell without its place") ++
      none(page, "[role=gridcell]:not([tabindex='-1'])", "a cell that is a tab stop of its own") ++
      none(page, "[role=columnheader]:not([aria-colindex])", "a header without its place") ++
      none(page, "[role=columnheader]:not([tabindex='-1'])", "a header that is a tab stop") ++
      none(page, "[id='kit-table'] [tabindex='0']", "a tab stop in the grid") ++
      Enum.flat_map(LazyHTML.query(page, "[id^='kit-row-'][id$='-r']"), fn row ->
        if LazyHTML.attribute(row, "role") == ["row"] and
             LazyHTML.attribute(row, "aria-rowindex") != [nil],
           do: [],
           else: ["the role and the place of the row #{LazyHTML.attribute(row, "id")}"]
      end)
  end

  # A record's row group, its row, its cells and its actions.
  defp record(page, key) do
    row = "kit-row-#{key}"

    need(page, "[id='#{row}'][role=rowgroup]", "the row group of the record") ++
      need(page, "[id='#{row}'] [id='#{row}-r'][role=row][aria-rowindex]", "its row") ++
      need(page, "[id='#{row}-s'][role=gridcell][data-selector] input", "its box") ++
      need(
        page,
        "[id='#{row}-e'][role=gridcell][data-expander] button[aria-expanded]",
        "its expander"
      ) ++
      need(page, "[id='#{row}-a'][role=gridcell][data-actions]", "its actions cell") ++
      need(
        page,
        "[id='#{row}-a'] [data-action='stamp'][tabindex='-1']",
        "the button of an action"
      ) ++
      need(
        page,
        "[id='#{row}-a'] [data-action='destroy'][data-question][data-destructive]",
        "one that asks"
      ) ++
      Enum.flat_map(@columns, fn field ->
        need(
          page,
          "[id='#{row}-c-#{field}'][role=gridcell][aria-colindex][tabindex='-1']",
          "its cell #{field}"
        )
      end) ++
      need(page, "[id='#{row}-c-note'][data-lines='2']", "the lines of a cell of note") ++
      need(page, "[id='#{row}-c-secret'] [data-mask]", "the mask of the sensitive cell") ++
      need(page, "[id='#{row}-c-secret'] [data-masked]", "what a screen reader hears of it") ++
      need(page, "[id='#{row}-c-secret'] [data-secret]", "where its value goes") ++
      need(page, "[id='#{row}-c-secret'] button[data-reveal]", "its Show")
  end

  # The editor of a column: its template, and one control in it, or one
  # that says it is the control.
  defp editor(page, field) do
    case LazyHTML.query(page, "template[id='kit-editor-#{field}'][data-editor]")
         |> Enum.to_list() do
      [] ->
        ["the editor of #{field} (template[id='kit-editor-#{field}'][data-editor])"]

      [template] ->
        [{"template", _attrs, children}] = LazyHTML.to_tree(template)
        inside = LazyHTML.from_tree(children)
        controls = count(inside, "input,textarea,select")
        marked = count(inside, "[data-control]")

        if controls == 1 or marked == 1,
          do: [],
          else: ["one control in the editor of #{field}"]
    end
  end

  # ---- what each state has besides ---------------------------------------

  defp special(page, :rows, key, _presentation),
    do:
      record(page, key) ++
        need(page, "[id='kit-pagination'][data-table='kit'][phx-hook]", "the pagination") ++
        need(page, "[id='kit-pagination'] [id='kit-next']", "Next")

  defp special(page, :empty, _key, _presentation),
    do: need(page, "[id='kit-empty']", "No records")

  defp special(_page, :error, _key, _presentation), do: []

  defp special(page, :loading, key, _presentation),
    do:
      lines(page, key) ++
        need(page, "[id='kit-row-#{key}-t-parts-loading']", "the nested table's Loading")

  defp special(page, :nested, key, _presentation) do
    nested = "kit-row-#{key}-t-parts"

    lines(page, key) ++
      need(
        page,
        "[id='kit-row-#{key}-n-parts-c'] [id='#{nested}-grid'][data-ash-data-table]",
        "the nested grid in its cell"
      ) ++
      need(page, "[id='#{nested}-table'][role=grid]", "the nested grid") ++
      need(page, "[id='#{nested}-head-title'][role=columnheader]", "its header")
  end

  defp special(page, :failed, key, _presentation) do
    cell = "kit-row-#{key}-c-name"

    need(
      page,
      "[id='#{cell}'][aria-invalid][aria-describedby='#{cell}-error']",
      "the failed cell"
    ) ++
      need(page, "[id='#{cell}'] [id='#{cell}-error'][popover]", "its message")
  end

  defp special(page, :panel, _key, presentation),
    do:
      opened(page, "kit-panel", presentation) ++
        need(page, "[id='kit-panel'] form[id='kit-panel-form']", "the panel's form") ++
        need(page, "[id='kit-panel'] [data-field='file'] input[type=file]", "its file field") ++
        need(page, "[id='kit-panel'] [data-cancel]", "its Cancel") ++
        need(page, "[id='kit-panel'] [id='kit-panel-submit'][type=submit]", "its submit")

  defp special(page, :map_panel, _key, presentation),
    do:
      opened(page, "kit-panel", presentation) ++
        need(page, "[id='kit-panel'][data-ask='changed']", "that it asks once changed") ++
        need(page, "[id='kit-panel'] [data-field='place']", "the field of the map") ++
        need(page, "[id='kit-panel'] [data-field='place.city']", "a field in it")

  defp special(page, :picker, _key, presentation),
    do:
      opened(page, "kit-picker", presentation) ++
        need(page, "[id='kit-picker'] [data-cancel]", "its Cancel") ++
        need(page, "[id='kit-picker'] [data-take]", "its Choose") ++
        need(
          page,
          "[id='kit-picker'] [id='kit-pick-owner-grid'][data-ash-data-table]",
          "its table"
        ) ++
        need(page, "[id='kit-pick-owner-table'][role=grid]", "its grid")

  defp special(page, :selected, _key, _presentation),
    do: need(page, "[id='kit-result']", "what the run came to")

  defp lines(page, key) do
    need(page, "[id='kit-row-#{key}-x'][role=rowgroup][data-detail]", "the detail of the row") ++
      need(page, "[id='kit-row-#{key}-l-parts-c'][role=gridcell][data-line='parts']", "the line") ++
      need(
        page,
        "[id='kit-row-#{key}-l-parts-c'] button[aria-expanded='true']",
        "its button, open"
      ) ++
      need(
        page,
        "[id='kit-row-#{key}-n-parts-c'][role=gridcell][data-nested]",
        "the cell of the nested table"
      )
  end

  # What opens: a `<dialog>` over the page, or a region in it.
  defp opened(page, id, :modal),
    do:
      need(
        page,
        "dialog[id='#{id}'][role=dialog][data-presentation='modal'][data-table='kit']",
        "#{id}, a modal <dialog>"
      )

  defp opened(page, id, :inline),
    do:
      need(
        page,
        "[id='#{id}'][role=region][data-presentation='inline'][data-table='kit'][aria-labelledby]",
        "#{id}, in the page"
      ) ++
        none(page, "dialog[id='#{id}']", "#{id} as a <dialog> while it is inline")

  # ---- reading the page ---------------------------------------------------

  defp count(page, selector), do: page |> LazyHTML.query(selector) |> Enum.count()

  defp need(page, selector, what),
    do: if(count(page, selector) > 0, do: [], else: ["#{what} (#{selector})"])

  defp none(page, selector, what),
    do: if(count(page, selector) == 0, do: [], else: ["no #{what} (#{selector})"])
end

defmodule AshDataTable.KitCase.Live do
  @moduledoc false
  # The LiveView `AshDataTable.KitCase` draws its table in: a table of
  # `AshDataTable.Test.Resource` attached in a tenant of the test's own,
  # with the kit and the presentation of the test.
  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"kit" => kit, "tenant" => tenant, "presentation" => presentation}, socket) do
    {:ok,
     AshDataTable.attach(socket, :table, AshDataTable.Test.Resource,
       id: "kit",
       tenant: tenant,
       kit: kit,
       presentation: presentation
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AshDataTable.attached table={@table} streams={@streams} uploads={assigns[:uploads]} />
    """
  end
end
