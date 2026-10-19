defmodule AshDataTable.Parts.Related do
  @moduledoc false
  # Relationship lines under an expanded row, the nested tables in them,
  # what a table limited to related records says above its grid, and the
  # link to the full view: the parts `detail`, `line`, `related` and
  # `full_view` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Kit
  alias AshDataTable.Parts

  # What is under an expanded row: one line per relationship the person is
  # offered, and under an open line the row whose one cell holds the nested
  # table. A line is a cell that spans the table, with a button that says
  # whether it is open, the line's Tab stop; the cell of a nested table spans
  # it too, and the nested table's controls in it are stops in their turn.
  #
  # The nested table is named by its line and by the first cell of the row
  # it belongs to ("Comments" and "Write the report"): both are on the page,
  # so the name follows the row when it is edited, and the server keeps
  # nothing for it.
  #
  # The detail draws a line per relationship (the kit's `line/1`), from the
  # detail's item (`AshDataTable.Item`): its `lines`, in the model's order.
  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :model, :map, required: true
  attr :colspan, :integer, required: true
  attr :myself, :any, required: true
  attr :kit, :atom, required: true

  def detail(assigns) do
    ~H"""
    <Kit.part
      :for={{relationship, line} <- Enum.zip(@model.relationships, @row.lines)}
      part={:line}
      kit={@kit}
      id={Ids.row(@id, @row.key)}
      relationship={relationship}
      open?={line.open}
      count={line.count}
      colspan={@colspan}
      table={Ids.nested_table(Ids.row(@id, @row.key), relationship.name)}
      myself={@myself}
      texts={%{count: line.text}}
      messages={%{count: line.message}}
    />
    """
  end

  # One relationship's line under an expanded row, and under it, while it
  # is open, the row whose one cell the nested table is moved into. `id` is
  # the row's (`ID-row-KEY`), `table` the nested table's, whose events the
  # line's buttons send.
  #
  # The line is the heading line of its nested table: the arrow that opens
  # and closes it, the relationship's name and, once the nested table has
  # read, how many records it has (`count`); after them, while it is open,
  # the place the nested table's own heading line is moved into
  # (`Ids.line_heading/2`: its "Columns", its argument line, its create
  # button and table actions, the kit's `heading/1` drawn by the nested
  # table, see `AshDataTable.Live.Drawing`). Its element that stays in
  # view, as wide as what is seen of the table (`--ash-data-table-view`),
  # draws the line of the nested area down its left (see `Parts.Look`) and
  # the one inset after it.
  attr :id, :string, required: true
  attr :relationship, :map, required: true
  attr :open?, :boolean, required: true
  attr :count, :any, required: true
  attr :colspan, :integer, required: true
  attr :table, :string, required: true
  attr :myself, :any, required: true
  attr :texts, :map, required: true

  def line(assigns) do
    ~H"""
    <tr id={"#{@id}-l-#{@relationship.name}"} role="row">
      <td
        id={Ids.line_cell(@id, @relationship.name)}
        role="cell"
        colspan={@colspan}
        aria-colindex="1"
        {Attrs.line(@relationship)}
        class="p-0"
      >
        <%!-- What the line holds stays at the left edge of the table's
        scroll area while the table scrolls sideways under it, as the nested
        table under it does, and is as wide as what is seen of it, so that
        the far end of the heading line is in view: the padding of the cell
        is this element's, so that it stands in the same place stuck and not.
        One line, which wraps only where it does not fit. --%>
        <div class="sticky left-0 flex w-[var(--ash-data-table-view,100%)] flex-wrap items-center gap-x-3 gap-y-2 border-s-[3px] border-s-primary/45 py-1 ps-5">
          <button
            type="button"
            id={Ids.line_button(@id, @relationship.name)}
            aria-expanded={to_string(@open?)}
            class="text-sm font-semibold"
          >
            {@relationship.label}
          </button>
          <%!-- How many records the nested table has, once it has read: beside
          the button, not in it, as the button names the nested grid, which
          says its number of rows itself. --%>
          <span :if={@open? and @texts.count} class="-ms-1 text-sm text-base-content/70">
            {@texts.count}
          </span>
          <%!-- The nested table's heading line, put here by the browser (a
          portal): it takes the rest of the line, and goes under the name as a
          whole where it does not fit beside it. --%>
          <div
            :if={@open?}
            id={Ids.line_heading(@id, @relationship.name)}
            class="min-w-0 grow basis-auto"
          >
          </div>
        </div>
      </td>
    </tr>
    <tr :if={@open?} id={Ids.nested_row(@id, @relationship.name)} role="row">
      <td
        id={Ids.nested_cell(@id, @relationship.name)}
        role="cell"
        colspan={@colspan}
        aria-colindex="1"
        data-nested
        data-line-cell={Ids.line_cell(@id, @relationship.name)}
        data-expander-cell={Ids.expander(@id)}
        class="p-0"
      >
        <%!-- The nested table is drawn by the table on the page, and the
        browser puts it here (a portal, see `AshDataTable.Live.Drawing`), as
        wide as what is seen of the table around it: it scrolls sideways in
        its own area (its grid), under its own rows. --%>
      </td>
    </tr>
    """
  end

  # What is above the grid of a table that a URL limits to the records
  # related to one record: what it shows, and the way back to all records.
  #
  # The heading names the relationship, as the parent's table labels it, and
  # the record once it has been read for this person: as a link to the page
  # of the record's own table where the router mounts one. The text is one
  # message, so that a translation can put its parts in another order: the
  # part is given its words before and after the record.
  attr :id, :string, required: true
  attr :via, :map, required: true
  attr :title, :string, default: nil
  attr :parent, :map, default: nil
  attr :clear, :string, required: true
  attr :create, :map, default: nil
  attr :actions, :list, default: []
  attr :target, :any, default: nil
  attr :kit, :atom, required: true

  def related(assigns) do
    ~H"""
    <div id={"#{@id}-related"} class={@kit.class(:related, %{})}>
      <h2 id={"#{@id}-related-heading"} class="font-semibold" phx-no-format><%= if @texts.heading_before do %>{@texts.heading_before}<.link
            :if={@parent}
            id={"#{@id}-related-parent"}
            navigate={@parent.path}
            class="link"
          >{@title}</.link><span :if={!@parent} id={"#{@id}-related-parent"}>{@title}</span>{@texts.heading_after}<% else %>{@texts.relationship}<% end %></h2>
      <div class="flex items-center gap-2">
        <Parts.Heading.create :if={@create} id={@id} action={@create} target={@target} />
        <Parts.Heading.table_actions id={@id} actions={@actions} target={@target} />
        <.link id={"#{@id}-related-clear"} patch={@clear} class="btn btn-sm">
          {@texts.show_all_records}
        </.link>
      </div>
    </div>
    """
  end

  # Whether a nested table has its link to the full view: the router mounts
  # the destination's table, and the nested table has been read.
  def full_view?(page, full_view), do: not is_nil(page) and not is_nil(full_view)

  # The link to the full view is the last row of a nested table's grid,
  # after its pages: a Tab stop, followed with Enter.
  attr :acting?, :any, required: true
  attr :full_view, :any, required: true
  attr :id, :any, required: true
  attr :label, :any, required: true
  attr :lead, :any, required: true
  attr :model, :any, required: true

  def full_view(assigns) do
    ~H"""
    <tr {Attrs.row("#{@id}-view-row")}>
      <td {Attrs.spanning("#{@id}-view", Attrs.colcount(@model, @lead, @acting?), %{"data-view" => true})}>
        <.link
          id={"#{@id}-full-view"}
          navigate={@full_view}
          aria-label={@texts.full_view_of}
          class="link sticky left-4 text-sm"
        >
          {@texts.full_view}
        </.link>
      </td>
    </tr>
    """
  end
end
