defmodule DemoWeb.ReactKit do
  @moduledoc """
  The demo's React kit (`AshDataTable.Kit`, the React kit's design note):
  the parts of the grid drawn with React and shadcn/ui's look, through
  live_react (`LiveReact.react/1`, no server rendering), on the table's
  own hooks, which the islands mount by hand (`mountGrid`,
  `mountPagination`, `liveViewTransport` of the library's JS).

  It draws these parts as islands (`assets/islands/table/`):

    * `grid` - the island `AshGrid`: the header with its sort buttons and
      handles, the filter row, the rows and their cells (every state, the
      columns' components, the actions, the boxes, the expander), the lines
      of an expanded row with the places their nested tables are moved
      into, drawn ahead (the kit's note, C8), the footer with the summaries,
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

  What each island is given is picked here (`DemoWeb.ReactKit.Props`), as
  plain data that goes to JSON: never a record, an Ash type or a struct of
  the table's, and nothing a part is not given. The rows are the table's
  stream, handed to the island as it is.
  """
  use AshDataTable.Kit, contract: 5

  alias AshDataTable.Attrs
  alias DemoWeb.ReactKit.Props

  # The grid's island, and beside it what LiveView draws: the filter row's
  # form (the island's controls name it) and the sender of the grid's
  # events (LiveView mounts its hook and locks it, never the grid). The
  # island draws the templates of the editors and of a failed cell's
  # message, which the hook copies into a cell.
  def grid(assigns) do
    ~H"""
    <form :if={Attrs.filter_row?(@model)} {Attrs.filters(@id, @myself)}></form>
    <div {Attrs.sender(@id)}></div>
    <LiveReact.react
      id={"#{@id}-grid-island"}
      name="AshGrid"
      class="contents"
      rows={@rows}
      texts={@texts}
      skip={Props.skip(@id)}
      scrollbar={Props.scrollbar(@id)}
      grid={Props.grid(@id, @myself, @lead, @selecting, @choose, @texts)}
      table={
        Props.table(
          @id,
          @label,
          @labelledby,
          @model,
          @page,
          @summarised?,
          @lead,
          @acting?,
          @busy?,
          @running
        )
      }
      head={
        Props.head(
          @id,
          @model,
          @state,
          @label_column,
          @lead,
          @selecting,
          @expandable?,
          @acting?,
          @editing?,
          @myself,
          @texts
        )
      }
      filters={
        Props.filters(@id, @model, @filters, @lead, @selecting, @expandable?, @acting?, @myself)
      }
      columns={Props.columns(@model, @texts)}
      row={
        Props.row(
          @id,
          @model,
          @label_column,
          @lead,
          @selecting,
          @expandable?,
          @acting?,
          @open,
          @asks?,
          @nested?
        )
      }
      footer={
        Props.footer(
          @id,
          @model,
          @page,
          @state,
          @lead,
          @selecting,
          @expandable?,
          @acting?,
          @pages?,
          @row_count,
          @label,
          @full_view,
          @summarised?,
          @summary,
          @summing?,
          @time_zone,
          @nested?,
          @myself
        )
      }
      editors={Props.editors(@id, @model, @editors, @asks?)}
      failure={@editing? or @acting?}
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
      heading={
        Props.heading(
          @id,
          @heading,
          @label,
          @label_column,
          @model,
          @offered,
          @page,
          @related,
          @nested?,
          @myself
        )
      }
      columns={Props.heading_columns(@id, @model, @label_column, @state, @label, @nested?)}
      arguments={Props.arguments(@id, @model, @arguments, @nested?, @myself)}
    />
    """
  end

  def selection_line(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-selection-island"}
      name="AshSelectionLine"
      class="contents"
      line={
        Props.selection_line(
          @id,
          @bulk,
          @choose,
          @notice?,
          @page,
          @row_count,
          @running,
          @selecting,
          @selected,
          @all?,
          @whole_page?,
          @state,
          @nested?,
          @myself,
          @texts
        )
      }
    />
    """
  end

  def status(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-status-island"}
      name="AshStatus"
      class="contents"
      status={Props.status(@id, @announcements, @texts)}
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
      related={Props.related(@id, @title, @parent, @clear, @create, @actions, @target, @texts)}
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
      message={Props.message(@id, @kind, @text, @nested?)}
    />
    """
  end

  def pagination(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-pagination-island"}
      name="AshPagination"
      class="contents"
      pagination={Props.pagination(@id, @nested?, @page, @model, @state, @target, @texts, @pages)}
    />
    """
  end

  # The question, drawn once and opened by the grid's hook (`dialog.js`),
  # which writes the question into it: the island's element is LiveView's
  # place left alone (`ID-dialogs`, `-in-panel`, `-in-picker`).
  def confirm(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-dialogs#{Attrs.asked_in(@place)}"}
      name="AshConfirm"
      class="contents"
      confirm={Props.confirm(@id, @model, @bulk, @presentation, @place, @texts)}
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
      panel={Props.panel(@id, @panel, @fields, @target, @presentation, @texts)}
    />
    <.live_file_input
      :for={field <- @fields}
      :if={field.upload}
      upload={field.upload}
      form={"#{@id}-panel-form"}
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
      picker={Props.picker(@id, @picker, @target, @presentation, @takes?, @texts)}
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
end
