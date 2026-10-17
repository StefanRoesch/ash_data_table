defmodule AshDataTable.KitCase do
  @moduledoc """
  Checks a kit (`AshDataTable.Kit`) in a host's own tests: it draws a
  table of `AshDataTable.Test.Resource` through the kit in every state, with
  what opens over the page and in it, and asserts that every page on the
  way carries the markers, ids and `data-*` values the table's hooks find
  their elements by and read, the element kinds they need, and that no page
  holds the test resource's sensitive value.

      defmodule MyAppWeb.TableKitTest do
        use AshDataTable.KitCase, kit: MyAppWeb.TableKit, endpoint: MyAppWeb.Endpoint
      end

  The states (`states/0`): the rows of a page (`:rows`, with the argument
  line, the footer of the summaries and the editors of the cells), sorted
  and filtered by several values (`:filtered`), no records (`:empty`), a
  read that failed (`:error`), a nested table whose first read is on its
  way (`:loading`) and one that has read (`:nested`), a cell whose save
  failed (`:failed`), and one of the sensitive column (`:secret_failed`),
  the panels of a row action with a file (`:panel`), of one with the
  sensitive field (`:rekey`), of the create action (`:create`) and its
  failed submit (`:create_failed`), of a map cell (`:map_panel`) and of a
  list of maps (`:groups_panel`), of records chosen in the picker
  (`:staff`) and that picker (`:staff_picker`), the picker of a reference
  cell (`:picker`), the result of an action on selected rows
  (`:selected`), and the parts a table draws only where the router mounts
  the related table (`:links`: what a table limited to the records of one
  record says above its grid, and a nested table's link to its full view,
  drawn with `Phoenix.LiveViewTest.render_component/2`).

  Each is drawn in every presentation (`presentations/0`): what opens all
  over the page (`:modal`), all in it (`:inline`), the panel and the
  picker over it with the question in it (`:mixed`), and the panel over it
  with the picker and the question in it (`:inside`: a picker a field of
  the panel opens is drawn inside the panel).

  What a person does with the keyboard and hears from a screen reader is
  not checked here: that needs a browser. The library checks it for
  `AshDataTable.Kit.Default` and for a kit drawn with `div`s in its own
  browser suite.

  It runs with `Phoenix.LiveViewTest` (`live_isolated/3`) on the endpoint
  given, and keeps the test resource's records in memory, in a tenant of
  each test's own: the tests run `async`.
  """

  import ExUnit.Assertions

  require Phoenix.LiveViewTest

  # a test dependency of the host's, as for `AshDataTable.Test`
  @compile {:no_warn_undefined, [LazyHTML]}

  alias AshDataTable.Test.Resource

  @table "kit"
  @states [:rows, :filtered, :empty, :error, :loading, :nested, :failed, :secret_failed] ++
            [:panel, :rekey, :create, :create_failed, :map_panel, :groups_panel, :staff] ++
            [:staff_picker, :picker, :selected, :links]

  @presentations [
    modal: [panel: :modal, picker: :modal, confirm: :modal],
    inline: [panel: :inline, picker: :inline, confirm: :inline],
    mixed: [panel: :modal, picker: :modal, confirm: :inline],
    inside: [panel: :modal, picker: :inline, confirm: :inline]
  ]

  @doc "The states a kit is drawn in."
  def states, do: @states

  @doc """
  How what opens is drawn: all over the page (`:modal`), all in it
  (`:inline`), the panel and the picker over the page with the question in
  it (`:mixed`), and the panel over the page with the picker and the
  question in it (`:inside`).
  """
  def presentations, do: Keyword.keys(@presentations)

  defmacro __using__(opts) do
    kit = Keyword.fetch!(opts, :kit)
    endpoint = Keyword.fetch!(opts, :endpoint)

    quote do
      use ExUnit.Case, async: true

      import Phoenix.LiveViewTest

      # a state draws a read that fails, which the table logs
      @moduletag :capture_log

      @endpoint unquote(endpoint)
      @kit unquote(kit)

      for presentation <- AshDataTable.KitCase.presentations(),
          state <- AshDataTable.KitCase.states() do
        @presentation presentation
        @state state

        test "#{inspect(@kit)} draws the state #{@state}, what opens #{@presentation}" do
          {tenant, key, session} = AshDataTable.KitCase.given(@kit, @state, @presentation)
          on_exit(fn -> AshDataTable.KitCase.clean(tenant) end)

          {:ok, view, html} =
            live_isolated(Phoenix.ConnTest.build_conn(), AshDataTable.KitCase.Live,
              session: session
            )

          AshDataTable.KitCase.check(@kit, view, html, key, @state, @presentation)
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
       "presentation" => Keyword.fetch!(@presentations, presentation)
     }}
  end

  # Six records, more than a page holds, read by name: `Anchor` first, with
  # a value in every column, an owner, a helper and two parts.
  defp seed(tenant) do
    opts = [tenant: tenant, authorize?: false]
    create = &Ash.create!(&1, &2, opts)
    secret = Resource.secret()
    create.(Resource.Owner, %{name: "Ann Lee", pin: secret})

    first =
      create.(Resource, %{
        name: "Anchor",
        note: "A note long enough to be cut off after two lines of its column",
        secret: secret,
        done: true,
        size: 40,
        tier: :high,
        tags: ["red", "blue"],
        place: %{city: "Bern", zip: "3000"},
        stops: [%{city: "Thun"}, %{city: "Biel"}],
        kind: 7,
        owner_id: "Ann Lee"
      })

    create.(Resource.Owner, %{name: "Bob Ray", pin: secret, holder_id: first.id})
    create.(Resource, %{name: "Bolt", secret: secret, size: 3, tier: :low, kind: "loose"})

    for name <- ~w(Cog Dial Edge Fuse),
        do: create.(Resource, %{name: name, secret: secret, tier: :low})

    create.(Resource.Part, %{title: "Pin", secret: secret, resource_id: first.id})
    create.(Resource.Part, %{title: "Plate", secret: secret, resource_id: first.id})
    first.id
  end

  @doc false
  def clean(tenant) do
    for resource <- [Resource, Resource.Owner, Resource.Part],
        do: Ash.DataLayer.Ets.stop(resource, tenant)
  end

  # ---- the states --------------------------------------------------------

  @doc false
  # Brings the table into `state` and checks every page it draws on the way
  # there, the first one (`html`, as it was mounted) among them.
  def check(kit, view, html, key, state, presentation) do
    pages = [{html, {:way, state}} | drive(kit, view, state, key)]

    for {html, at} <- pages do
      refute html =~ Resource.secret(),
             "the page holds the sensitive value of AshDataTable.Test.Resource (#{inspect(at)})"

      page = AshDataTable.Test.page(html)
      problems = common(page, at, presentation) ++ special(page, at, key, presentation)

      assert problems == [],
             "the kit draws the state #{inspect(at)} without:\n  " <> Enum.join(problems, "\n  ")
    end
  end

  defp event(view, name, payload, opts \\ []),
    do: AshDataTable.Test.send_event(view, @table, name, payload, opts)

  defp async(view), do: Phoenix.LiveViewTest.render_async(view, 5_000)

  # The pages on the way to `state`, each with what it is: the page of the
  # state last, the others `{:way, state}`.
  defp drive(_kit, view, state, _key) when state in [:rows, :empty, :error],
    do: [{Phoenix.LiveViewTest.render(view), state}]

  defp drive(_kit, view, :filtered, _key) do
    sorted = event(view, "sort", %{"column" => "size"})
    chosen = event(view, "filter", %{"filter" => %{"tier" => %{"o" => "any_of"}}})
    event(view, "filter", %{"filter" => %{"tier" => %{"o" => "any_of", "in" => ["low"]}}})
    [{sorted, {:way, :filtered}}, {chosen, {:way, :filtered}}, {async(view), :filtered}]
  end

  defp drive(_kit, view, :loading, key) do
    expanded = event(view, "expand", %{"row" => key})
    [{expanded, {:way, :loading}}, {toggled(view, key), :loading}]
  end

  defp drive(_kit, view, :nested, key) do
    expanded = event(view, "expand", %{"row" => key})
    loading = toggled(view, key)
    [{expanded, {:way, :nested}}, {loading, {:way, :nested}}, {async(view), :nested}]
  end

  defp drive(_kit, view, :failed, key),
    do: [{event(view, "save", %{"row" => key, "column" => "name", "value" => ""}), :failed}]

  # longer than the column takes, with the sensitive value in it
  defp drive(_kit, view, :secret_failed, key) do
    typed = Resource.secret() <> String.duplicate("x", 20)

    [
      {event(view, "save", %{"row" => key, "column" => "secret", "value" => typed}),
       :secret_failed}
    ]
  end

  defp drive(_kit, view, :panel, key),
    do: [{event(view, "act", %{"row" => key, "action" => "stamp"}), :panel}]

  defp drive(_kit, view, :rekey, key),
    do: [{event(view, "act", %{"row" => key, "action" => "rekey"}), :rekey}]

  defp drive(_kit, view, :create, _key), do: [{event(view, "create", %{}), :create}]

  # what the action refuses (a value too long in the list) is said at its
  # place, with the sensitive value typed into the panel
  defp drive(_kit, view, :create_failed, _key) do
    opened = event(view, "create", %{})

    failed =
      AshDataTable.Test.send_form(
        view,
        "[id='kit-panel-form']",
        :submit,
        %{
          "panel" => %{
            "name" => "New",
            "secret" => Resource.secret(),
            "tags" => ["ok", "much-too-long"]
          }
        },
        check: false
      )

    [{opened, {:way, :create_failed}}, {failed, :create_failed}]
  end

  defp drive(_kit, view, :map_panel, key),
    do: [{event(view, "edit", %{"row" => key, "column" => "place"}), :map_panel}]

  defp drive(_kit, view, :groups_panel, key),
    do: [{event(view, "edit", %{"row" => key, "column" => "stops"}), :groups_panel}]

  defp drive(_kit, view, :staff, key),
    do: [{event(view, "act", %{"row" => key, "action" => "staff"}), :staff}]

  defp drive(_kit, view, :staff_picker, key) do
    opened = event(view, "act", %{"row" => key, "action" => "staff"})
    event(view, "pick_input", %{"input" => "helpers"}, from: :panel)
    [{opened, {:way, :staff_picker}}, {async(view), :staff_picker}]
  end

  defp drive(_kit, view, :picker, key) do
    event(view, "pick", %{"row" => key, "column" => "owner"})
    [{async(view), :picker}]
  end

  defp drive(_kit, view, :selected, key) do
    selected = event(view, "select", %{"rows" => [key]})
    asked = event(view, "bulk", %{"action" => "destroy"})
    Phoenix.LiveViewTest.assert_reply(view, %{selection: token})
    event(view, "bulk_run", %{"action" => "destroy", "selection" => token})

    [
      {selected, {:way, :selected}},
      {asked, {:way, :selected}},
      {async(view), :selected}
    ]
  end

  defp drive(kit, _view, :links, key) do
    model = AshDataTable.Model.build(Resource, [])
    parts = Enum.find(model.relationships, &(&1.name == :parts))
    nested = "kit-row-#{key}-t-parts"

    related =
      Phoenix.LiveViewTest.render_component(&kit.related/1, %{
        kit: kit,
        id: @table,
        via: parts,
        title: "Anchor",
        parent: %{path: "/kit", id: @table},
        clear: "/kit",
        create: nil,
        actions: [],
        target: nil
      })

    # a row of the grid: parsed inside one
    full_view =
      Phoenix.LiveViewTest.render_component(&kit.full_view/1, %{
        kit: kit,
        acting?: false,
        full_view: "/parts?of=Anchor",
        id: nested,
        label: "Parts",
        lead: 0,
        model: AshDataTable.Model.build(Resource.Part, [])
      })

    [{related, :related}, {"<table>#{full_view}</table>", :full_view}]
  end

  # the nested table's line, opened: its first read is on its way
  defp toggled(view, key),
    do: event(view, "toggle", %{"row" => key, "relationship" => "parts"})

  # ---- what every page has ----------------------------------------------

  @columns ~w(name note secret done size tier tags place stops kind owner)

  defp common(page, at, presentation) do
    case state_of(at) do
      :error -> need(page, "[id='kit-error'][role=alert]", "the read's error")
      state when state in [:related, :full_view] -> []
      _state -> grid(page) ++ question(page, presentation)
    end
  end

  defp state_of({_way, state}), do: state
  defp state_of(state), do: state

  # The question: a `<dialog>` over the page, or a region in it named by
  # its question, hidden until the hook asks.
  defp question(page, presentation) do
    case Keyword.fetch!(@presentations, presentation)[:confirm] do
      :modal ->
        need(
          page,
          "dialog[id='kit-dialog'][role=dialog][data-presentation='modal'][aria-labelledby='kit-dialog-question']",
          "the question, a modal <dialog>"
        )

      :inline ->
        need(
          page,
          "[id='kit-dialog'][role=region][data-presentation='inline'][aria-labelledby='kit-dialog-question'][hidden]",
          "the question, in the page and hidden"
        ) ++
          none(page, "dialog[id='kit-dialog']", "the question as a <dialog> while it is inline")
    end
  end

  defp grid(page) do
    grid =
      need(
        page,
        "[id='kit-grid'][data-ash-data-table][data-table='kit'][phx-hook][data-lead][data-select='multi']",
        "the grid's hook, with where the arrow keys start and how rows are selected"
      ) ++
        need(page, "[id='kit-sender'][data-sender][data-table='kit'][phx-hook]", "its sender") ++
        need(page, "[id='kit-table'][role=grid][aria-colcount][data-first-row]", "the grid") ++
        need(page, "[id='kit-table'] [id='kit-head']", "its header in it") ++
        need(page, "[id='kit-head'] [id='kit-head-row'][role=row]", "the row of the headers") ++
        need(page, "[id='kit-head'] [id='kit-filter-row'][role=row]", "the filter row") ++
        need(page, "form[id='kit-filters']", "the filter row's form") ++
        need(page, "[id='kit-table'] [id='kit-foot']", "the footer in the grid") ++
        need(
          page,
          "[id='kit-foot'] [id='kit-summaries'][role=row][data-summaries]",
          "the row of the summaries"
        ) ++
        need(page, "[id='kit-summary-size'][role=gridcell]", "the summary of size") ++
        need(page, "[id='kit-arguments'][data-arguments]", "the argument line") ++
        need(page, "[id='kit-arguments'] [data-argument='near']", "the argument near") ++
        need(page, "[id='kit-do-greet'][data-table-action='greet']", "the table action") ++
        need(page, "[id='kit-create']", "the create button") ++
        need(page, "[id='kit-whole'][data-whole][popover]", "the whole-text popover") ++
        need(page, "[id='kit-status'][role=status]", "the live region") ++
        need(page, "[id='kit-dialog'] [id='kit-dialog-question']", "where it asks") ++
        need(page, "[id='kit-dialog'] button[value='cancel']", "its Cancel, the safe answer") ++
        need(page, "[id='kit-dialog'] button[value='confirm']", "its Confirm") ++
        need(
          page,
          "[id='kit-selection'][data-selection][data-all][data-selected]",
          "the selection line, with what it says"
        ) ++
        need(page, "[id='kit-selected']", "what is selected") ++
        need(page, "[id='kit-selection-controls']", "the selection's buttons") ++
        need(page, "[id='kit-select-all'][data-select-all]", "Select all") ++
        need(page, "[id='kit-clear-selection'][data-clear]", "Clear selection") ++
        need(page, "[data-bulk='destroy']", "the action on the selection") ++
        need(
          page,
          "[id='kit-columns-button'][data-columns-button][data-say-hidden][data-say-shown]",
          "the Columns button"
        ) ++
        need(page, "[id='kit-columns'][data-columns-list]", "the Columns list") ++
        need(
          page,
          "[id='kit-columns'] input[data-head][data-label]",
          "a box of the Columns list"
        ) ++
        need(page, "[id='kit-columns-control']", "its control") ++
        need(page, "[id='kit-columns-status']", "what it says") ++
        need(page, "[id='kit-columns-text']", "its text") ++
        need(page, "[id='kit-scrollbar'][data-scrollbar]", "the scrollbar") ++
        need(page, "template[id='kit-failure']", "the failure template") ++
        need(
          page,
          "[id='kit-select-head'][role=columnheader][data-select-page]",
          "the box of the page"
        ) ++
        need(page, "[id='kit-head-name'][data-label]", "the label column, kept in view") ++
        need(page, "[id='kit-head-name'][data-sort]", "a header that sorts")

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
      Enum.flat_map(
        ~w(name note secret done size tier),
        &editor(page, &1, "input,textarea,select")
      ) ++
        editor(page, "tags", "[data-list]") ++
        need(page, "template[id='kit-editor-note'][data-confirm]", "the question of note") ++
        need(page, "template[id='kit-editor-secret'][data-editor='secret']", "a secret editor") ++
        in_template(
          page,
          "kit-editor-name",
          "[data-count][data-max]",
          "the counter of name in its editor"
        ) ++
        in_template(
          page,
          "kit-editor-tags",
          "[data-list][data-value-label][data-remove-label]",
          "the list editor of tags, with what its rows are called"
        )

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
      need(page, "[id='#{row}-c-tags'][data-value]", "what a cell of a list holds") ++
      need(page, "[id='#{row}-c-secret'] [data-mask]", "the mask of the sensitive cell") ++
      need(page, "[id='#{row}-c-secret'] [data-masked]", "what a screen reader hears of it") ++
      need(page, "[id='#{row}-c-secret'] [data-secret]", "where its value goes") ++
      need(
        page,
        "[id='#{row}-c-secret'] button[data-reveal][data-show][data-hide][data-show-label][data-hide-label]",
        "its Show, with what it says either way"
      )
  end

  # The editor of a column: its template, and in it one control, or one
  # that says it is the control (`controls` finds them).
  defp editor(page, field, controls) do
    case LazyHTML.query(page, "template[id='kit-editor-#{field}'][data-editor]")
         |> Enum.to_list() do
      [] ->
        ["the editor of #{field} (template[id='kit-editor-#{field}'][data-editor])"]

      [template] ->
        inside = inside(template)
        found = count(inside, controls)
        marked = count(inside, "[data-control]")

        if found == 1 or marked == 1,
          do: [],
          else: ["one control in the editor of #{field}"]
    end
  end

  # What a template holds, which LazyHTML does not look into.
  defp inside(template) do
    [{"template", _attrs, children}] = LazyHTML.to_tree(template)
    LazyHTML.from_tree(children)
  end

  defp in_template(page, id, selector, what) do
    case Enum.to_list(LazyHTML.query(page, "template[id='#{id}']")) do
      [template] -> need(inside(template), selector, what)
      _none -> ["#{what} (template[id='#{id}'])"]
    end
  end

  # ---- what each state has besides ---------------------------------------

  defp special(_page, {_way, _state}, _key, _presentation), do: []

  defp special(page, :rows, key, _presentation),
    do:
      record(page, key) ++
        need(page, "[id='kit-selection'][data-more]", "that more records match than are shown") ++
        need(page, "[id='kit-pagination'][data-table='kit'][phx-hook]", "the pagination") ++
        need(page, "[id='kit-pagination'] [id='kit-next']", "Next")

  defp special(page, :filtered, _key, _presentation),
    do:
      need(page, "[id='kit-filter-tier'] [data-choices-button]", "the button of its values") ++
        need(page, "[id='kit-filter-tier'] [data-choices]", "the list of its values") ++
        need(page, "[id='kit-columns'] input[data-filtered]", "the column that filters") ++
        need(page, "[id='kit-columns'] input[data-sorted]", "the column that sorts")

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
      need(page, "[id='#{nested}-head-title'][role=columnheader]", "its header") ++
      need(page, "[id='#{nested}-head-secret'][role=columnheader]", "its sensitive column") ++
      need(
        page,
        "[id='#{nested}-columns'][data-keeps-one]",
        "the Columns list of a table without a label column"
      )
  end

  defp special(page, :failed, key, _presentation) do
    cell = "kit-row-#{key}-c-name"

    need(
      page,
      "[id='#{cell}'][aria-invalid][aria-describedby='#{cell}-error'][data-value][data-saved]",
      "the failed cell, with what was typed and what is saved"
    ) ++
      need(page, "[id='#{cell}'] [id='#{cell}-error'][popover]", "its message")
  end

  defp special(page, :secret_failed, key, _presentation) do
    cell = "kit-row-#{key}-c-secret"

    need(
      page,
      "[id='#{cell}'][aria-invalid][aria-describedby='#{cell}-error']",
      "the failed cell"
    ) ++
      need(page, "[id='#{cell}'] [id='#{cell}-error'][popover]", "its message")
  end

  defp special(page, :panel, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-field='file'] input[type=file]", "its file field")

  defp special(page, :rekey, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-field='secret']", "the sensitive field") ++
        need(page, "[id='kit-panel'] [data-clear-field='secret']", "its button that empties it") ++
        need(
          page,
          "[id='kit-panel'] [data-field='tags'] [id$='-count-2'][data-count]",
          "the counter of the second tag"
        )

  defp special(page, :create, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-field='secret']", "the sensitive field") ++
        need(page, "[id='kit-panel'] [data-field='tags'] [data-list]", "the list of tags") ++
        need(page, "[id='kit-panel'] [data-add-group]", "the button that adds a stop")

  defp special(page, :create_failed, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-invalid]", "the places of the values refused")

  defp special(page, :map_panel, _key, presentation),
    do:
      panel(page, presentation) ++
        need(
          page,
          "[id='kit-panel'][data-ask='changed'][data-question]",
          "that it asks once changed, and what"
        ) ++
        need(page, "[id='kit-panel'] [data-field='place']", "the field of the map") ++
        need(page, "[id='kit-panel'] [data-field='place.city']", "a field in it")

  defp special(page, :groups_panel, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-add-group]", "the button that adds a stop") ++
        need(page, "[id='kit-panel'] [data-remove-group]", "the button that takes one away")

  defp special(page, :staff, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-field='helpers']", "the field of the helpers") ++
        need(page, "[id='kit-panel'] [data-unpick]", "the button that takes a helper out")

  defp special(page, :staff_picker, _key, presentation) do
    picker = picker(page, presentation)

    inside =
      if Keyword.fetch!(@presentations, presentation)[:picker] == :inline and
           Keyword.fetch!(@presentations, presentation)[:panel] == :modal,
         do: need(page, "[id='kit-panel'] [id='kit-picker']", "the picker inside the panel"),
         else: []

    picker ++
      inside ++
      need(page, "[id='kit-picker'][data-several]", "that several are chosen") ++
      need(page, "[id='kit-picker'] [data-chosen-rows]", "the rows chosen as it opens")
  end

  defp special(page, :picker, _key, presentation),
    do:
      picker(page, presentation) ++
        need(
          page,
          "[id='kit-picker'] [data-ash-data-table][data-choose]",
          "its table, to choose from"
        ) ++
        need(
          page,
          "[id='kit-picker'] [role=columnheader][id$='-head-pin']",
          "its sensitive column"
        ) ++
        need(
          page,
          "[id='kit-picker'] [role=rowgroup][data-key]",
          "what a row names its record by"
        )

  defp special(page, :selected, _key, _presentation),
    do: need(page, "[id='kit-result']", "what the run came to")

  defp special(page, :related, _key, _presentation),
    do:
      need(page, "[id='kit-related']", "what a table limited to related records says") ++
        need(page, "[id='kit-related'] [id='kit-related-clear']", "its way back to every record")

  defp special(page, :full_view, key, _presentation),
    do:
      need(
        page,
        "[id='kit-row-#{key}-t-parts-view'][role=gridcell][data-view] a[id='kit-row-#{key}-t-parts-full-view']",
        "the link to the full view"
      )

  defp lines(page, key) do
    need(
      page,
      "[id='kit-row-#{key}-x'][role=rowgroup][data-detail][data-row]",
      "the detail of the row"
    ) ++
      need(page, "[id='kit-row-#{key}-l-parts-c'][role=gridcell][data-line='parts']", "the line") ++
      need(
        page,
        "[id='kit-row-#{key}-l-parts-c'] button[aria-expanded='true']",
        "its button, open"
      ) ++
      need(
        page,
        "[id='kit-row-#{key}-n-parts-c'][role=gridcell][data-nested][data-line-cell][data-expander-cell]",
        "the cell of the nested table, with the cells it is reached from"
      )
  end

  defp panel(page, presentation),
    do:
      opened(page, "kit-panel", Keyword.fetch!(@presentations, presentation)[:panel]) ++
        need(page, "[id='kit-panel'] form[id='kit-panel-form']", "the panel's form") ++
        need(page, "[id='kit-panel'] [data-cancel]", "its Cancel") ++
        need(page, "[id='kit-panel'] [id='kit-panel-submit'][type=submit]", "its submit")

  defp picker(page, presentation),
    do:
      opened(page, "kit-picker", Keyword.fetch!(@presentations, presentation)[:picker]) ++
        need(page, "[id='kit-picker'] [data-cancel]", "its Cancel") ++
        need(page, "[id='kit-picker'] [data-take]", "its Choose") ++
        need(
          page,
          "[id='kit-picker'] [id^='kit-pick-'][id$='-grid'][data-ash-data-table]",
          "its table"
        )

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
