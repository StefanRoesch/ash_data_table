defmodule DemoWeb.ReactKit do
  @moduledoc """
  The demo's React kit (`AshDataTable.Kit`, the React kit's design note):
  the parts of the grid drawn with React and shadcn/ui's look, through
  live_react (`LiveReact.react/1`, no server rendering), on the table's
  own hooks, which the islands mount by hand (`mountGrid`,
  `mountPagination`, `liveViewTransport` of the library's JS).

  Stage R2 draws these parts as islands (`assets/islands/table/`):

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
    * `columns` - the island `AshColumns`: "Columns" and its list;
    * `selection_line` - the island `AshSelectionLine`;
    * `status` - the island `AshStatus`;
    * `pagination` - the island `AshPagination` (a nested table's is in
      the grid's island).

  The other parts are `AshDataTable.Kit.Default`'s: the root, the heading
  line around "Columns" with the argument line, create and the table
  actions, the messages, the panel, the picker and the question (stage R3).

  What each island is given is picked here (`DemoWeb.ReactKit.Props`), as
  plain data that goes to JSON: never a record, an Ash type or a struct of
  the table's, and nothing a part is not given. The rows are the table's
  stream, handed to the island as it is.
  """
  use AshDataTable.Kit, contract: 3

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

  def columns(assigns) do
    ~H"""
    <LiveReact.react
      id={"#{@id}-columns-island"}
      name="AshColumns"
      class="contents"
      columns={Props.columns_list(@id, @columns, @label_column, @keeps_one?, @state, @texts)}
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
