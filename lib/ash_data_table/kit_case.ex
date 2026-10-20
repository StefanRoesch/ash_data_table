defmodule AshDataTable.KitCase do
  @moduledoc """
  Checks a kit (`AshDataTable.Kit`) in a host's own tests: it draws a
  table of `AshDataTable.Test.Resource` through the kit in every state, with
  what opens over the page and in it, and asserts that every page on the
  way carries the markers, ids and `data-*` values the table's hooks find
  their elements by and read, the element kinds they need, a table's Tab
  stops (`AshDataTable.Kit`, "Tab stops": its controls and its
  editable cells, no read-only cell, no header that does not sort, no cell
  that holds controls; the skip link and its target; no `aria-readonly`,
  `aria-selected`, `aria-multiselectable` and no `aria-invalid` on a cell),
  and that no page holds the test resource's sensitive value.

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
  failed submit (`:create_failed`), of a cell of a list (`:list_panel`),
  of a map cell (`:map_panel`) and of a list of maps (`:groups_panel`), of records chosen in the picker
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

  Every part is drawn through a kit of its own that first checks what the
  part is given: its `texts`, `messages` and `locale`, or its `text` and
  `message`, where `AshDataTable.Kit` says it has them.

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

  alias AshDataTable.Ids
  alias AshDataTable.Test.Resource

  @table "kit"
  @states [:rows, :filtered, :empty, :error, :loading, :nested, :failed, :secret_failed] ++
            [:panel, :rekey, :create, :create_failed, :list_panel, :map_panel, :groups_panel] ++
            [:staff] ++
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

    # The kit, drawn through a kit that first checks what each part is given
    # (`given!/2`): every part the kit draws is called through it.
    probed =
      for part <- AshDataTable.Kit.parts() do
        quote do
          def unquote(part)(assigns) do
            AshDataTable.KitCase.given!(unquote(part), assigns)
            unquote(kit).unquote(part)(%{assigns | kit: __MODULE__})
          end
        end
      end

    quote do
      use ExUnit.Case, async: true

      import Phoenix.LiveViewTest

      # a state draws a read that fails, which the table logs
      @moduletag :capture_log

      @endpoint unquote(endpoint)
      @kit unquote(kit)

      defmodule Probe do
        @moduledoc false
        use AshDataTable.Kit, contract: 5

        unquote_splicing(probed)

        def class(part, state), do: unquote(kit).class(part, state)
        def presentation(thing), do: unquote(kit).presentation(thing)
        def look(option), do: unquote(kit).look(option)
      end

      for presentation <- AshDataTable.KitCase.presentations(),
          state <- AshDataTable.KitCase.states() do
        @presentation presentation
        @state state

        test "#{inspect(@kit)} draws the state #{@state}, what opens #{@presentation}" do
          {tenant, key, session} =
            AshDataTable.KitCase.given(__MODULE__.Probe, @state, @presentation)

          on_exit(fn -> AshDataTable.KitCase.clean(tenant) end)

          {:ok, view, html} =
            live_isolated(Phoenix.ConnTest.build_conn(), AshDataTable.KitCase.Live,
              session: session
            )

          AshDataTable.KitCase.check(__MODULE__.Probe, view, html, key, @state, @presentation)
        end
      end
    end
  end

  @doc false
  # What a part is given of its texts and values (`AshDataTable.Kit`, "Texts
  # and values"): raises, and fails the state, where the part lacks one.
  def given!(part, assigns) do
    missing =
      for name <- AshDataTable.Kit.Words.names(part), not is_map_key(assigns, name), do: name

    if missing != [] do
      raise ArgumentError, "the part #{inspect(part)} is given no #{inspect(missing)}"
    end

    with %{texts: texts, messages: messages} <- assigns,
         false <- Map.keys(texts) == Map.keys(messages) do
      raise ArgumentError,
            "the part #{inspect(part)} is given `texts` and `messages` of other names"
    end

    for {name, message} <- Map.get(assigns, :messages, %{}) do
      shape!(part, name, message, Map.get(assigns.texts, name))
    end

    if part in [:message, :failure], do: shape!(part, :message, assigns.message, assigns.text)

    :ok
  end

  # A message as `AshDataTable.Messages` documents it, and its text beside
  # it: a key of the list with exactly the values it names (a value may be
  # a message), an action's message with its variables, or nil; a list of
  # them where the text is a list.
  defp shape!(_part, _name, nil, text) when is_nil(text) or is_binary(text), do: :ok

  defp shape!(part, name, messages, texts) when is_list(messages) do
    if not is_list(texts) or length(texts) != length(messages) do
      raise ArgumentError,
            "the part #{inspect(part)} is given the messages `#{name}` as a list, " <>
              "and its texts not as a list of as many: #{inspect(texts, limit: 5)}"
    end

    Enum.zip_with(messages, texts, &shape!(part, name, &1, &2))
  end

  defp shape!(part, name, %{key: :ash, values: values} = message, text) do
    if not (is_map(values) and Enum.sort(Map.keys(values)) == [:message, :vars] and
              is_binary(values.message) and is_map(values.vars)) do
      raise ArgumentError,
            "the part #{inspect(part)} is given an action's message `#{name}` " <>
              "#{inspect(message, limit: 5)}, which is not `%{key: :ash, values: " <>
              "%{message: String.t(), vars: map}}`"
    end

    text!(part, name, text)
  end

  defp shape!(part, name, %{key: key, values: values} = message, text)
       when is_atom(key) and is_map(values) and map_size(message) == 2 do
    case AshDataTable.Messages.all() do
      %{^key => %{values: names}} ->
        if Enum.sort(Map.keys(values)) != Enum.sort(names) do
          raise ArgumentError,
                "the part #{inspect(part)} is given the message `#{name}` " <>
                  "#{inspect(message, limit: 5)}, whose values are not the ones " <>
                  "AshDataTable.Messages names for #{inspect(key)}: #{inspect(names)}"
        end

        for {_value, value} <- values,
            inner <- if(is_list(value), do: value, else: [value]),
            inner_message?(inner),
            do: shape!(part, name, inner, nil)

      _unknown ->
        raise ArgumentError,
              "the part #{inspect(part)} is given the message `#{name}` of the key " <>
                "#{inspect(key)}, which is no key of AshDataTable.Messages"
    end

    text!(part, name, text)
  end

  defp shape!(part, name, other, _text) do
    raise ArgumentError,
          "the part #{inspect(part)} is given `#{name}` as #{inspect(other, limit: 5)}, " <>
            "which is no message of AshDataTable.Messages"
  end

  # a message inside another: a value of it, or one of those it joins
  defp inner_message?(%{key: key, values: values} = message)
       when is_atom(key) and is_map(values) and map_size(message) == 2,
       do: true

  defp inner_message?(_value), do: false

  defp text!(_part, _name, text) when is_nil(text) or is_binary(text), do: :ok

  defp text!(part, name, text) do
    raise ArgumentError,
          "the part #{inspect(part)} is given the text `#{name}` as #{inspect(text, limit: 5)}, " <>
            "not as words"
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

    create.(Resource.Part, %{
      title: "Pin",
      secret: secret,
      resource_id: first.id,
      owner_id: "Ann Lee"
    })

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
    opened = event(view, "filter_values", %{"column" => "tier", "operator" => "any_of"})

    AshDataTable.Test.send_form(
      view,
      "[id='kit-panel-form']",
      :submit,
      %{"panel" => %{"tier" => ["", "low"]}},
      check: false
    )

    [
      {sorted, {:way, :filtered}},
      {chosen, {:way, :filtered}},
      {opened, :filter_panel},
      {async(view), :filtered}
    ]
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

  defp drive(_kit, view, :list_panel, key),
    do: [{event(view, "edit", %{"row" => key, "column" => "tags"}), :list_panel}]

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
      {selected, {:row_selected, :selected}},
      {asked, {:way, :selected}},
      {async(view), :selected}
    ]
  end

  defp drive(kit, _view, :links, key) do
    model = AshDataTable.Model.build(Resource, [])
    parts = Enum.find(model.relationships, &(&1.name == :parts))
    nested = Ids.nested_table(Ids.row("kit", key), :parts)

    related =
      Phoenix.LiveViewTest.render_component(&AshDataTable.Kit.part/1, %{
        part: :related,
        kit: kit,
        id: @table,
        via: parts,
        title: "Anchor",
        parent: %{path: "/kit", id: @table},
        clear: "/kit",
        create: nil,
        actions: [],
        target: nil,
        texts: AshDataTable.Kit.Words.texts(:related, %{via: parts, title: "Anchor"}),
        messages: AshDataTable.Kit.Words.messages(:related, %{via: parts, title: "Anchor"})
      })

    # a row of the grid: parsed inside one
    full_view =
      Phoenix.LiveViewTest.render_component(&AshDataTable.Kit.part/1, %{
        part: :full_view,
        kit: kit,
        acting?: false,
        full_view: "/parts?of=Anchor",
        id: nested,
        label: "Parts",
        lead: 0,
        model: AshDataTable.Model.build(Resource.Part, []),
        texts: AshDataTable.Kit.Words.texts(:full_view, %{label: "Parts"}),
        messages: AshDataTable.Kit.Words.messages(:full_view, %{label: "Parts"})
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
      :error -> need(page, "[id='#{Ids.error("kit")}'][role=alert]", "the read's error")
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
          "dialog[id='#{Ids.dialog("kit")}'][role=dialog][data-presentation='modal'][aria-labelledby='#{Ids.dialog("kit")}-question']",
          "the question, a modal <dialog>"
        )

      :inline ->
        need(
          page,
          "[id='#{Ids.dialog("kit")}'][role=region][data-presentation='inline'][aria-labelledby='#{Ids.dialog("kit")}-question'][hidden]",
          "the question, in the page and hidden"
        ) ++
          none(
            page,
            "dialog[id='#{Ids.dialog("kit")}']",
            "the question as a <dialog> while it is inline"
          )
    end
  end

  defp grid(page) do
    grid =
      need(
        page,
        "[id='kit-grid'][data-ash-data-table][data-table='kit'][phx-hook][data-lead][data-select='multi'][tabindex='-1']",
        "the grid's hook, with how many columns lead and how rows are selected, no Tab stop"
      ) ++
        need(page, "[id='kit-sender'][data-sender][data-table='kit'][phx-hook]", "its sender") ++
        need(page, "[id='kit-table'][role=table][aria-colcount][data-first-row]", "the table") ++
        need(
          page,
          "a[id='#{Ids.skip("kit")}'][href='##{Ids.skip_target("kit")}']",
          "the link that skips the table (`Attrs.skip/1`)"
        ) ++
        need(
          page,
          "[id='kit'] [id='#{Ids.skip_target("kit")}'][tabindex='-1']",
          "where it jumps to, in the table's root (`Attrs.skip_target/1`)"
        ) ++
        skip_order(page, "kit") ++
        need(page, "[id='kit-table'] [id='#{Ids.head("kit")}']", "its header in it") ++
        need(
          page,
          "[id='#{Ids.head("kit")}'] [id='#{Ids.head_row("kit")}'][role=row]",
          "the row of the headers"
        ) ++
        need(
          page,
          "[id='#{Ids.head("kit")}'] [id='#{Ids.filter_row("kit")}'][role=row]",
          "the filter row"
        ) ++
        need(page, "form[id='#{Ids.filters("kit")}']", "the filter row's form") ++
        need(page, "[id='kit-table'] [id='kit-foot']", "the footer in the grid") ++
        need(
          page,
          "[id='kit-foot'] [id='kit-summaries'][role=row][data-summaries]",
          "the row of the summaries"
        ) ++
        need(page, "[id='kit-summary-size'][role=cell]", "the summary of size") ++
        need(page, "[id='kit-arguments'][data-arguments]", "the argument line") ++
        need(page, "[id='kit-arguments'] [data-argument='near']", "the argument near") ++
        need(page, "[id='kit-do-greet'][data-table-action='greet']", "the table action") ++
        need(page, "[id='kit-create']", "the create button") ++
        need(
          page,
          "[id='kit-grid'][data-show-whole][data-show-less][data-show-whole-of*='{column}'][data-show-less-of*='{column}']",
          "what the button says that shows a cell's whole text"
        ) ++
        need(page, "[id='kit-status'][role=status]", "the live region") ++
        need(
          page,
          "[id='#{Ids.dialog("kit")}'] [id='#{Ids.dialog("kit")}-question']",
          "where it asks"
        ) ++
        need(
          page,
          "[id='#{Ids.dialog("kit")}'] button[value='cancel']",
          "its Cancel, the safe answer"
        ) ++
        need(page, "[id='#{Ids.dialog("kit")}'] button[value='confirm']", "its Confirm") ++
        need(
          page,
          "[id='kit-selection'][data-selection]",
          "the selection line"
        ) ++
        need(page, "[id='kit-selected']", "what is selected") ++
        need(page, "[id='kit-selection-controls']", "the selection's buttons") ++
        need(page, "[id='kit-select-all'][data-select-all]", "Select all") ++
        need(page, "[id='kit-clear-selection'][data-clear]", "Clear selection") ++
        need(page, "[data-bulk='destroy']", "the action on the selection") ++
        need(
          page,
          "[id='kit-columns-button'][data-columns-button][data-text-hidden][data-text-filtered][data-text-sorted]",
          "the Columns button, with what it says of the hidden columns"
        ) ++
        need(page, "[id='kit-columns'][data-columns-list]", "the Columns list") ++
        need(
          page,
          "[id='kit-columns'] input[data-head][data-say-hidden][data-say-shown]",
          "a box of the Columns list, with what is read out"
        ) ++
        need(
          page,
          "[id='kit-columns'] input[type=number][data-width^='kit-head-'][min][max][aria-label]",
          "a column's width field (`Attrs.width_field/3`), named"
        ) ++
        need(
          page,
          "[id='kit-columns'] input[type=number][data-width='#{Ids.header_cell("kit", :name)}'][aria-label]",
          "the label column's width field"
        ) ++
        none(
          page,
          "[id='kit-columns'] input[type=checkbox][data-head='#{Ids.header_cell("kit", :name)}']",
          "a box of the label column, which cannot be hidden"
        ) ++
        need(page, "[id='kit-columns'] button[data-reset-widths]", "Reset widths") ++
        need(page, "[id='kit-columns-control']", "its control") ++
        need(page, "[id='kit-columns-status']", "what it says") ++
        need(page, "[id='kit-columns-text']", "its text") ++
        need(page, "[id='kit-columns-count']", "its number of hidden columns") ++
        need(page, "[id='kit-scrollbar'][data-scrollbar]", "the scrollbar") ++
        need(page, "template[id='kit-failure']", "the failure template") ++
        need(
          page,
          "[id='kit-select-head'][role=columnheader][data-select-page]",
          "the box of the page"
        ) ++
        need(
          page,
          "[id='#{Ids.header_cell("kit", :name)}'][data-label]",
          "the label column, kept in view"
        ) ++
        need(
          page,
          "[id='#{Ids.header_cell("kit", :name)}'][data-sort][aria-sort] > button[id='#{Ids.sort("kit", :name)}'][phx-click='ash_data_table:kit:sort']",
          "a header that sorts, with its sort button (`Attrs.sort/3`)"
        ) ++
        sort_buttons(page)

    columns =
      Enum.flat_map(@columns, fn field ->
        need(
          page,
          "[id='#{Ids.header_cell("kit", field)}'][role=columnheader][aria-colindex][aria-label]",
          "the header of #{field}"
        ) ++
          need(
            page,
            "[id='#{Ids.header_cell("kit", field)}'] [id='kit-resize-#{field}'][data-resize][aria-hidden=true]:not([role],[tabindex])",
            "its handle, for the pointer alone"
          ) ++
          need(
            page,
            "[id='kit-filter-#{field}'][role=cell][aria-colindex]",
            "the filter cell of #{field}"
          )
      end)

    editors =
      Enum.flat_map(
        ~w(name note secret done size tier),
        &editor(page, &1, "input,textarea,select")
      ) ++
        in_panel(page, "tags", "list") ++
        need(
          page,
          "template[id='#{Ids.editor("kit", :note)}'][data-confirm]",
          "the question of note"
        ) ++
        need(
          page,
          "template[id='#{Ids.editor("kit", :secret)}'][data-editor='secret']",
          "a secret editor"
        ) ++
        in_template(
          page,
          Ids.editor("kit", :name),
          "[data-count][data-max]",
          "the counter of name in its editor"
        )

    grid ++ columns ++ editors ++ constants(page)
  end

  # What every cell, header, row and record is, whatever the kit draws it
  # with, and its Tab stops: controls, and an editable cell; nothing else.
  defp constants(page) do
    none(
      page,
      ":is([role=cell],[role=rowheader]):not([aria-colindex])",
      "a cell without its place"
    ) ++
      none(page, "[role=columnheader]:not([aria-colindex])", "a header without its place") ++
      none(page, "[role=grid],[role=gridcell]", "an ARIA grid: a table is a table") ++
      none(
        page,
        ":is([role=cell],[role=rowheader])[tabindex]:not([tabindex='0'])",
        "a cell with another tabindex than an editable cell's"
      ) ++
      none(
        page,
        ":is([role=cell],[role=rowheader])[tabindex='0']:is([data-selector],[data-expander],[data-actions],[data-line],[data-nested],[data-pager],[data-view],[data-filter],[colspan])",
        "a cell that holds controls and is a Tab stop besides them"
      ) ++
      none(page, "[id='kit-foot'] [tabindex]", "a Tab stop among the summaries") ++
      none(
        page,
        "[role=columnheader][tabindex]",
        "a header that is a Tab stop (its sort button is)"
      ) ++
      none(
        page,
        "[id^='kit'] :is(input,select,textarea,button,a)[tabindex]",
        "a control taken out of the Tab order, or put into it by hand"
      ) ++
      none(page, "[id^='kit-pick-'] [tabindex='0']", "an editable cell in a table to choose from") ++
      none(page, "[aria-readonly]", "aria-readonly, which no table cell takes") ++
      none(page, "[aria-selected]", "aria-selected, which no table row takes") ++
      none(page, "[aria-multiselectable]", "aria-multiselectable, which no table takes") ++
      none(
        page,
        ":is([role=cell],[role=rowheader])[aria-invalid]",
        "aria-invalid on a cell (`data-failed`)"
      ) ++
      Enum.flat_map(LazyHTML.query(page, "[id^='#{Ids.row("kit", "")}'][id$='-r']"), fn row ->
        if LazyHTML.attribute(row, "role") == ["row"] and
             LazyHTML.attribute(row, "aria-rowindex") != [nil],
           do: [],
           else: ["the role and the place of the row #{LazyHTML.attribute(row, "id")}"]
      end)
  end

  # A record's row group, its row, its cells and its actions.
  defp record(page, key) do
    row = Ids.row("kit", key)

    need(page, "[id='#{row}'][role=rowgroup]", "the row group of the record") ++
      need(page, "[id='#{row}'] [id='#{row}-r'][role=row][aria-rowindex]", "its row") ++
      need(page, "[id='#{Ids.selector(row)}'][role=cell][data-selector] input", "its box") ++
      need(
        page,
        "[id='#{Ids.expander(row)}'][role=cell][data-expander] button[aria-expanded]",
        "its expander"
      ) ++
      need(
        page,
        "[id='#{Ids.actions_cell(row)}'][role=cell][data-actions]",
        "its actions cell"
      ) ++
      need(
        page,
        "[id='#{Ids.actions_cell(row)}'] button[data-action='stamp']",
        "the button of an action"
      ) ++
      need(
        page,
        "[id='#{Ids.cell(row, :name)}'][role=rowheader][tabindex='0']",
        "the cell of the label column, the row's header, editable"
      ) ++
      need(
        page,
        "[id='#{Ids.actions_cell(row)}'] [data-action='destroy'][data-question][data-destructive]",
        "one that asks"
      ) ++
      Enum.flat_map(@columns, fn field ->
        need(
          page,
          "[id='#{Ids.cell(row, field)}']:is([role=cell],[role=rowheader])[aria-colindex][tabindex='0']",
          "its cell #{field}, editable: a Tab stop"
        )
      end) ++
      need(page, "[id='#{Ids.cell(row, :note)}'][data-lines='2']", "the lines of a cell of note") ++
      none(
        page,
        "[id='#{Ids.cell(row, :tags)}'][data-value]",
        "editor's value on a cell of a list, which is edited in the panel"
      ) ++
      need(page, "[id='#{Ids.cell(row, :secret)}'] [data-mask]", "the mask of the sensitive cell") ++
      need(
        page,
        "[id='#{Ids.cell(row, :secret)}'] [data-masked]",
        "what a screen reader hears of it"
      ) ++
      need(page, "[id='#{Ids.cell(row, :secret)}'] [data-secret]", "where its value goes") ++
      need(
        page,
        "[id='#{Ids.cell(row, :secret)}'] button[data-reveal][data-show][data-hide][data-show-label][data-hide-label]",
        "its Show, with what it says either way"
      )
  end

  # The editor of a column: its template, and in it one control, or one
  # that says it is the control (`controls` finds them).
  defp editor(page, field, controls) do
    case LazyHTML.query(page, "template[id='#{Ids.editor("kit", field)}'][data-editor]")
         |> Enum.to_list() do
      [] ->
        ["the editor of #{field} (template[id='#{Ids.editor("kit", field)}'][data-editor])"]

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

  # The template of a column edited in the side panel: its kind, and no
  # control, as nothing is edited in the cell.
  defp in_panel(page, field, kind) do
    case Enum.to_list(LazyHTML.query(page, "template[id='#{Ids.editor("kit", field)}']")) do
      [template] ->
        if LazyHTML.attribute(template, "data-editor") == [kind] and
             count(inside(template), "input,select,textarea,button,[data-control]") == 0,
           do: [],
           else: ["the editor of #{field}, of the kind #{kind} and without a control"]

      _none ->
        ["the editor of #{field} (template[id='#{Ids.editor("kit", field)}'])"]
    end
  end

  defp in_template(page, id, selector, what) do
    case Enum.to_list(LazyHTML.query(page, "template[id='#{id}']")) do
      [template] -> need(inside(template), selector, what)
      _none -> ["#{what} (template[id='#{id}'])"]
    end
  end

  # ---- what each state has besides ---------------------------------------

  # one row selected: the line says so, with its buttons, and offers
  # nothing for every record while the page is not all selected
  defp special(page, {:row_selected, _state}, _key, _presentation) do
    said = page |> LazyHTML.query("[id='kit-selected']") |> LazyHTML.text() |> String.trim()

    if(said == "1 selected", do: [], else: ["what is selected, \"1 selected\" (#{said})"]) ++
      need(page, "[id='kit-selection-controls']:not([hidden])", "the selection's buttons, shown") ++
      need(page, "[id='kit-select-all'][hidden]", "Select all, hidden while the page is not")
  end

  defp special(_page, {_way, _state}, _key, _presentation), do: []

  defp special(page, :rows, key, _presentation),
    do:
      record(page, key) ++
        need(page, "[id='kit-pagination'][data-table='kit'][phx-hook]", "the pagination") ++
        need(page, "[id='kit-pagination'] [id='kit-next']", "Next")

  defp special(page, :filtered, _key, _presentation),
    do:
      need(
        page,
        "[id='kit-filter-tier'] [id='kit-filter-tier-value'][phx-click][phx-value-column='tier'][phx-value-operator='any_of']",
        "the button that opens the panel of its values"
      ) ++
        need(
          page,
          "[id='kit-filter-tier'] input[type=hidden][name='filter[tier][in][]'][value='low'][form='#{Ids.filters("kit")}']",
          "the value that applies, in the filter row's form"
        ) ++
        need(page, "[id='kit-columns'] input[data-filtered]", "the column that filters") ++
        need(page, "[id='kit-columns'] input[data-sorted]", "the column that sorts")

  defp special(page, :empty, _key, _presentation),
    do: need(page, "[id='kit-empty']", "No records")

  defp special(_page, :error, _key, _presentation), do: []

  defp special(page, :loading, key, _presentation),
    do:
      lines(page, key) ++
        need(
          page,
          "[id='#{Ids.nested_table(Ids.row("kit", key), :parts)}-loading']",
          "the nested table's Loading"
        )

  defp special(page, :nested, key, _presentation) do
    nested = Ids.nested_table(Ids.row("kit", key), :parts)

    lines(page, key) ++
      need(
        page,
        "[id='#{Ids.nested_cell(Ids.row("kit", key), :parts)}'] [id='#{nested}-grid'][data-ash-data-table]",
        "the nested grid in its cell"
      ) ++
      need(page, "[id='#{nested}-table'][role=table]", "the nested table") ++
      need(
        page,
        "a[id='#{Ids.skip(nested)}'][href='##{Ids.skip_target(nested)}']",
        "the nested table's own skip link"
      ) ++
      need(page, "[id='#{Ids.skip_target(nested)}'][tabindex='-1']", "where it jumps to") ++
      skip_order(page, nested) ++
      need(
        page,
        "[id='#{nested}-table'][aria-labelledby~='#{Ids.line_button(Ids.row("kit", key), :parts)}']",
        "the nested grid named by its line's button, which is on the page"
      ) ++
      need(page, "[id='#{Ids.header_cell(nested, :title)}'][role=columnheader]", "its header") ++
      need(
        page,
        "[id='#{nested}-table'] [id$='-c-title'][role=cell][tabindex='0']",
        "an editable cell of the nested table, a Tab stop"
      ) ++
      need(
        page,
        "[id='#{nested}-table'] [id$='-c-secret'][role=cell]:not([tabindex])",
        "a read-only cell of the nested table, no Tab stop"
      ) ++
      need(
        page,
        "[id='#{Ids.header_cell(nested, :secret)}'][role=columnheader]",
        "its sensitive column"
      ) ++
      need(
        page,
        "[id='#{nested}-columns'][data-keeps-one]",
        "the Columns list of a table without a label column"
      ) ++
      need(
        page,
        "[id='#{Ids.line_cell(Ids.row("kit", key), :parts)}'] [id='#{Ids.line_heading(Ids.row("kit", key), :parts)}'] [id='#{nested}-columns-button']",
        "the nested table's heading line on its line (`Ids.line_heading/2`)"
      )
  end

  defp special(page, :failed, key, _presentation) do
    cell = Ids.cell(Ids.row("kit", key), :name)

    need(
      page,
      "[id='#{cell}'][data-failed][aria-describedby='#{Ids.error(cell)}'][data-value][data-saved]",
      "the failed cell, described by its message, with what was typed and what is saved"
    ) ++
      need(page, "[id='#{cell}'] [id='#{Ids.error(cell)}']", "its message, in the cell")
  end

  defp special(page, :secret_failed, key, _presentation) do
    cell = Ids.cell(Ids.row("kit", key), :secret)

    need(
      page,
      "[id='#{cell}'][data-failed][aria-describedby='#{Ids.error(cell)}']",
      "the failed cell, described by its message"
    ) ++
      need(page, "[id='#{cell}'] [id='#{Ids.error(cell)}']", "its message, in the cell")
  end

  defp special(page, :panel, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-field='file'] input[type=file]", "its file field")

  defp special(page, :rekey, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-field='secret']", "the sensitive field") ++
        need(
          page,
          "[id='kit-panel'] button[phx-click='ash_data_table:kit:panel_clear'][phx-value-input='secret']",
          "its button that empties it"
        ) ++
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
        need(
          page,
          "[id='kit-panel'] button[id$='-add'][phx-click*='panel_add']",
          "the button that adds a stop"
        )

  defp special(page, :create_failed, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-invalid]", "the places of the values refused")

  # the panel of a filter for several values, over the filter row: a box
  # per value, as a form of its own
  defp special(page, :filter_panel, _key, presentation),
    do:
      panel(page, presentation) ++
        need(
          page,
          "[id='kit-panel'] [data-field='tier'] input[type=checkbox][name='panel[tier][]']",
          "a box per value of the filter"
        )

  defp special(page, :list_panel, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-field='tags'] [data-list]", "the field of the list") ++
        need(page, "[id='kit-panel'] [data-field='tags'] [data-list] [data-add]", "its Add")

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
        need(
          page,
          "[id='kit-panel'] button[id$='-add'][phx-click*='panel_add']",
          "the button that adds a stop"
        ) ++
        need(page, "[id='kit-panel'] [data-remove-group]", "the button that takes one away")

  defp special(page, :staff, _key, presentation),
    do:
      panel(page, presentation) ++
        need(page, "[id='kit-panel'] [data-field='helpers']", "the field of the helpers") ++
        need(
          page,
          "[id='kit-panel'] button[phx-click='ash_data_table:kit:panel_unpick'][phx-value-input='helpers'][phx-value-key]",
          "the button that takes a helper out"
        )

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
        "[id='#{Ids.nested_table(Ids.row("kit", key), :parts)}-view'][role=cell][data-view] a[id='#{Ids.nested_table(Ids.row("kit", key), :parts)}-full-view']",
        "the link to the full view"
      )

  defp lines(page, key) do
    need(
      page,
      "[id='#{Ids.detail(Ids.row("kit", key))}'][role=rowgroup][data-detail][data-row]",
      "the detail of the row"
    ) ++
      need(
        page,
        "[id='#{Ids.line_cell(Ids.row("kit", key), :parts)}'][role=cell][data-line='parts']",
        "the line"
      ) ++
      need(
        page,
        "[id='#{Ids.line_cell(Ids.row("kit", key), :parts)}'] button[id='#{Ids.line_button(Ids.row("kit", key), :parts)}'][aria-expanded='true']",
        "its button (`Ids.line_button/2`), open"
      ) ++
      need(
        page,
        "[id='#{Ids.nested_cell(Ids.row("kit", key), :parts)}'][role=cell][data-nested][data-line-cell][data-expander-cell]",
        "the cell of the nested table, with the cells it is reached from"
      )
  end

  defp panel(page, presentation),
    do:
      opened(page, "kit-panel", Keyword.fetch!(@presentations, presentation)[:panel]) ++
        need(page, "[id='kit-panel'] form[id='kit-panel-form']", "the panel's form") ++
        need(page, "[id='kit-panel'] [data-cancel]", "its Cancel") ++
        need(page, "[id='kit-panel'] [id='kit-panel-submit'][type=submit]", "its submit") ++
        asked_in(page, "kit-panel", presentation, :panel)

  defp picker(page, presentation),
    do:
      opened(page, "kit-picker", Keyword.fetch!(@presentations, presentation)[:picker]) ++
        need(page, "[id='kit-picker'] [data-cancel]", "its Cancel") ++
        need(page, "[id='kit-picker'] [data-take]", "its Choose") ++
        need(
          page,
          "[id='kit-picker'] [id^='kit-pick-'][id$='-grid'][data-ash-data-table]",
          "its table"
        ) ++
        picker_skip(page) ++
        asked_in(page, "kit-picker", presentation, :picker)

  # The picker's table has its own skip link and target, as every table.
  defp picker_skip(page) do
    grids = LazyHTML.query(page, "[id='kit-picker'] [id^='kit-pick-'][id$='-grid'][data-table]")

    case LazyHTML.attribute(grids, "data-table") do
      [id] ->
        need(
          page,
          "[id='kit-picker'] a[id='#{Ids.skip(id)}'][href='##{Ids.skip_target(id)}']",
          "the picker's table's own skip link"
        ) ++
          need(
            page,
            "[id='kit-picker'] [id='#{Ids.skip_target(id)}'][tabindex='-1']",
            "where it jumps to"
          ) ++ skip_order(page, id)

      _none ->
        []
    end
  end

  # The question once more inside what opens over the page, where it is
  # asked in the page: hidden, with the ids of its place, and left alone by
  # patches.
  defp asked_in(page, id, presentation, thing) do
    presentations = Keyword.fetch!(@presentations, presentation)
    suffix = AshDataTable.Attrs.asked_in(thing)

    if presentations[thing] == :modal and presentations[:confirm] == :inline,
      do:
        need(
          page,
          "[id='#{id}'] [id='kit-dialogs#{suffix}'][phx-update='ignore']",
          "the question's place in #{id}"
        ) ++
          need(
            page,
            "[id='#{id}'] [id='#{Ids.dialog("kit")}#{suffix}'][role=region][data-presentation='inline'][aria-labelledby='#{Ids.dialog("kit")}-question#{suffix}'][hidden]",
            "the question in #{id}, hidden"
          ) ++
          need(
            page,
            "[id='#{Ids.dialog("kit")}#{suffix}'] [id='#{Ids.dialog("kit")}-question#{suffix}']",
            "where it asks"
          ) ++
          need(
            page,
            "[id='#{Ids.dialog("kit")}#{suffix}'] button[value='confirm']",
            "its Confirm"
          ),
      else:
        none(
          page,
          "[id='#{id}'] [id^='#{Ids.dialog("kit")}-in']",
          "copy of the question in #{id}, which is not over the page"
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

  # The skip link of the table `id` stands before its header row, and where
  # it jumps to after its table and its pagination, in the page's order.
  defp skip_order(page, id) do
    html = LazyHTML.to_html(page)
    at = fn element -> :binary.match(html, ~s(id="#{element}")) end

    case Enum.map([Ids.skip(id), Ids.head_row(id), "#{id}-table", Ids.skip_target(id)], at) do
      [{skip, _}, {head, _}, {table, _}, {target, _}] when skip < head and table < target ->
        case at.("#{id}-pagination") do
          {pages, _} when pages > target -> ["#{id}'s skip target after its pagination"]
          _none_or_before -> []
        end

      _otherwise ->
        ["#{id}'s skip link before its header row, and its target after the table"]
    end
  end

  # Each header that sorts holds its sort button; one that does not, none.
  defp sort_buttons(page) do
    for header <- LazyHTML.query(page, "[id='#{Ids.head_row("kit")}'] > [role=columnheader]"),
        [id] = LazyHTML.attribute(header, "id"),
        String.starts_with?(id, Ids.header_cell("kit", "")),
        name = String.replace_prefix(id, Ids.header_cell("kit", ""), ""),
        sorts? = LazyHTML.attribute(header, "data-sort") != [],
        button? = Enum.count(LazyHTML.query(header, "button[id='#{Ids.sort("kit", name)}']")) == 1,
        sorts? != button? do
      if sorts?,
        do: "the sort button of #{name} (#{Ids.sort("kit", name)})",
        else: "no sort button in the header of #{name}, which does not sort"
    end
  end

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
