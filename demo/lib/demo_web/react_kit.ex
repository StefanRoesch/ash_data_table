defmodule DemoWeb.ReactKit do
  @moduledoc """
  The demo's React kit (`AshDataTable.Kit`):
  the parts of the grid drawn with React and shadcn/ui's look, through
  live_react (`LiveReact.react/1`, no server rendering), on the table's
  own hooks, which the islands mount by hand (`mountGrid`,
  `mountPagination`, `liveViewTransport` of the library's JS).

  It draws these parts as islands (`assets/islands/table/`):

    * `grid` - the island `AshGrid`: the header with its sort buttons and
      handles, the filter row, the rows and their cells (every state, the
      columns' components, the actions, the boxes, the expander), the lines
      of an expanded row with the places their nested tables are moved
      into, drawn ahead, the footer with the summaries,
      a nested table's pages and its link to the full view, and the
      templates of the editors (a column's, or its component's by the
      component's module) and of a failed cell's message. Outside the
      island, as markup of the LiveView's: the filter row's form and the
      grid's sender (C9);
    * `heading` - the island `AshHeading`: the table's name, "Columns"
      and its list, the argument line (a form of the island's, which
      LiveView hears from its root), create and the table actions;
    * `selection_line` - the island `AshSelectionLine`;
    * `status` - the island `AshStatus`;
    * `pagination` - the island `AshPagination` (a nested table's is in
      the grid's island);
    * `related` - the island `AshRelated`: what a table limited to the
      records of one record says above its grid, its create and table
      actions, and "Show all records";
    * `message` - the island `AshMessage`, one per message said in place
      of the rows (an error, loading, an argument to fill, "No records").

    * `confirm` - the island `AshConfirm`: the question, a `<dialog>` or a
      region in the page, which the grid's hook opens and writes into;
      once more inside a panel or picker over the page, where the question
      is asked in the page;
    * `panel` - the island `AshPanel`, drawn closed too: a `<dialog>` or a
      region, its form with a field per field (every kind: text, numbers,
      choices, lists, values made of fields and lists of them, unions,
      chosen records, a sensitive field's Clear, a component's editor, a
      file), and its place (`Ids.panel_place/1`), which what opens in it is
      moved into; beside it, LiveView's file input of each file field, out
      of sight, which the island's file control hands the files to
      (`uploadTo`);
    * `picker` - the island `AshPicker`, drawn closed too, with its place
      (`Ids.picker_place/1`), which its table is moved into.

  The panel and the picker mount the table's hooks (`mountPanel`,
  `mountPicker`) as they open, and destroy them as they close.

  The root stays `AshDataTable.Kit.Default`'s: an element with its bundle
  that holds the table's parts and what opens, and draws nothing to be
  seen (LiveView patches what it holds). The parts the islands draw inside
  them (`columns`, `argument_line`, `argument`, `editor`, `field`,
  `control`, `list`, `count`, …) are React components there, each
  replaceable by name (`reactKit({...})`); their `Kit.Default` parts are
  not used by this kit.

  It only draws: each island is given its part's projection
  (`AshDataTable.Kit.Projection`), each key a prop of its own, so that
  LiveView marks a prop changed only when what it is made of changed and
  live_react sends what changed in it. One rule makes props of a
  projection (`props/1` below): its bundles as props, as
  `AshDataTable.Attrs.props/1` makes them. The rows are the table's
  stream, handed to the island as it is.
  """
  use AshDataTable.Kit, contract: 6

  alias AshDataTable.Attrs

  # The grid's island, and beside it what LiveView draws: the filter row's
  # form (the island's controls name it) and the sender of the grid's
  # events (LiveView mounts its hook and locks it, never the grid). The
  # island draws the templates of the editors and of a failed cell's
  # message, which the hook copies into a cell.
  def grid(assigns) do
    ~H"""
    <form :if={@filter_form} {@filter_form}></form>
    <div {@sender}></div>
    <LiveReact.react
      id={"#{@id}-grid-island"}
      name="AshGrid"
      class="contents"
      table_id={@id}
      rows={@rows}
      nested?={@nested?}
      skip={props(@skip)}
      scrollbar={props(@scrollbar)}
      grid={props(@grid)}
      table={props(@table)}
      head={props(@head)}
      filters={props(@filters)}
      row={props(@row)}
      footer={props(@footer)}
      editors={props(@editors)}
      failure={props(@failure)}
      texts={@texts}
      messages={@messages}
    />
    """
  end

  # The heading line, with "Columns" and the argument line in it.
  def heading(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-heading-island"}
      name="AshHeading"
      class="contents"
      shown?={@shown?}
      nested?={@nested?}
      element={props(@element)}
      title={props(@title)}
      columns={props(@columns)}
      argument_line={props(@argument_line)}
      acts?={@acts?}
      create={props(@create)}
      actions={props(@actions)}
    />
    """
  end

  def selection_line(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-selection-island"}
      name="AshSelectionLine"
      class="contents"
      shown?={@shown?}
      nested?={@nested?}
      selection={props(@selection)}
      notice={props(@notice)}
      clear_filters={props(@clear_filters)}
      texts={@texts}
      messages={@messages}
    />
    """
  end

  def status(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-status-island"}
      name="AshStatus"
      class="contents"
      region={props(@region)}
      again?={@again?}
      result={@result}
      texts={@texts}
      messages={@messages}
    />
    """
  end

  # Above a table limited to the records of one record.
  def related(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-related-island"}
      name="AshRelated"
      class="contents"
      element={props(@element)}
      heading={props(@heading)}
      record={@record}
      create={props(@create)}
      actions={props(@actions)}
      clear={@clear}
      texts={@texts}
      messages={@messages}
    />
    """
  end

  # What is said in place of the rows: one island per message, by its kind.
  def message(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-#{@kind}-island"}
      name="AshMessage"
      class="contents"
      kind={@kind}
      element={props(@element)}
      nested?={@nested?}
      text={@text}
      message={@message}
    />
    """
  end

  def pagination(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-pagination-island"}
      name="AshPagination"
      class="contents"
      nested?={@nested?}
      element={props(@element)}
      range={props(@range)}
      previous={props(@previous)}
      next={props(@next)}
      pages={props(@pages)}
      sizes={props(@sizes)}
      texts={@texts}
      messages={@messages}
    />
    """
  end

  # The question, drawn once and opened by the grid's hook (`dialog.js`),
  # which writes the question into it: the island's element is LiveView's
  # place left alone (`ID-dialogs`, `-in-panel`, `-in-picker`).
  def confirm(assigns) do
    ~H"""
    <LiveReact.react
      id={@holder["id"]}
      name="AshConfirm"
      class="contents"
      asks?={@asks?}
      presentation={@presentation}
      holder={props(@holder)}
      dialog={props(@dialog)}
      question={props(@question)}
      texts={@texts}
      messages={@messages}
    />
    """
  end

  # The action panel, drawn closed too, with its place for what opens in it
  # (C8). Beside the island, as markup of the LiveView's: LiveView's own
  # file input of each file field, out of sight and in the island's form
  # (`form=`), which LiveView tracks the files of; the island's control
  # hands it the files a person chooses (`uploadTo`).
  def panel(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-panel-island"}
      name="AshPanel"
      class="contents"
      open?={@open?}
      presentation={@presentation}
      destructive?={@destructive?}
      place={props(@place)}
      frame={props(@frame)}
      form={props(@form)}
      title={props(@title)}
      errors={props(@errors)}
      cancel={props(@cancel)}
      submit={props(@submit)}
      fields={props(@fields)}
      texts={@texts}
      messages={@messages}
    />
    <.live_file_input
      :for={field <- @fields}
      :if={field.file}
      upload={@uploads[field.file.name]}
      form={@form["id"]}
      hidden
    />
    """
  end

  # The picker, drawn closed too, with its place, which its table is moved
  # into (C8).
  def picker(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-picker-island"}
      name="AshPicker"
      class="contents"
      open?={@open?}
      presentation={@presentation}
      place={props(@place)}
      frame={props(@frame)}
      title={props(@title)}
      error={props(@error)}
      cancel={props(@cancel)}
      none={props(@none)}
      take={props(@take)}
      texts={@texts}
      messages={@messages}
    />
    """
  end

  # The root holds the look of every table inside it, nested and pickers'
  # tables too (`assets/css/react_kit.css`, by the tables' markers), and the
  # scope of shadcn's colours (`shadcn`).
  def class(:root, %{nested?: false, look: look}) do
    Enum.join(
      [
        "ash-react-table shadcn",
        "ash-react-#{look.density}",
        look.stripes && "ash-react-stripes",
        look.column_lines && "ash-react-column-lines",
        look.sticky_header && "ash-react-sticky"
      ]
      |> Enum.filter(& &1),
      " "
    )
  end

  def class(:root, %{nested?: true}), do: "ash-react-table-nested"
  def class(:status, _state), do: "sr-only"
  def class(part, state), do: super(part, state)

  # ---- the props rule ---------------------------------------------------

  # A key of a part's projection (`AshDataTable.Kit.Projection`) as an
  # island's prop: every bundle in it (a map of attribute names, string
  # keys) as props (`Attrs.props/1`), without what LiveView reads of an
  # element it draws itself (`phx-hook`, `phx-update`, `phx-mounted`: an
  # island's element is the browser's, and the kit mounts the hooks
  # itself); a module (a column's component) by its name; what a column's
  # component is told of its column (its own contract,
  # `AshDataTable.Component.Column`) as the island draws with it; the rest
  # as it is. One rule for every part: the projection is what the part is
  # given, the islands read the same shapes.
  defp props(%{} = map) when not is_struct(map) and map_size(map) > 0 do
    if bundle?(map),
      do: map |> Map.drop(["phx-hook", "phx-update", "phx-mounted"]) |> Attrs.props(),
      else: Map.new(map, fn {key, value} -> {key, props(value)} end)
  end

  defp props(%AshDataTable.Component.Column{} = column), do: LiveReact.Encoder.encode(column, [])

  defp props(values) when is_list(values), do: Enum.map(values, &props/1)

  defp props(value) when is_atom(value) and not is_boolean(value) and not is_nil(value) do
    case Atom.to_string(value) do
      "Elixir." <> name -> name
      _atom -> value
    end
  end

  defp props(value), do: value

  # a bundle: attribute names, each an attribute's value
  defp bundle?(map),
    do:
      Enum.all?(map, fn {key, value} ->
        is_binary(key) and
          (is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value) or
             is_atom(value) or is_struct(value, Phoenix.LiveView.JS))
      end)

end
