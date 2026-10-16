defmodule AshDataTable.Parts.Related do
  @moduledoc false
  # Relationship lines under an expanded row, the nested tables in them,
  # what a table limited to related records says above its grid, and the
  # link to the full view: the parts `detail`, `line`, `related` and
  # `full_view` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Kit
  alias AshDataTable.Parts
  alias AshDataTable.Parts.Common
  alias AshDataTable.Text

  # What is under an expanded row: one line per relationship the person is
  # offered, and under an open line the row whose one cell holds the nested
  # table. A line is a cell that spans the table, with a button that says
  # whether it is open; so is the cell of a nested table, which the hook lets
  # a person go into and come back out of.
  #
  # The nested table is named by its line and by the first cell of the row
  # it belongs to ("Comments" and "Write the report"): both are on the page,
  # so the name follows the row when it is edited, and the server keeps
  # nothing for it.
  #
  # The detail draws a line per relationship (the kit's `line/1`).
  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :model, :map, required: true
  attr :colspan, :integer, required: true
  attr :creates, :map, required: true
  attr :myself, :any, required: true
  attr :kit, :atom, required: true

  def detail(assigns) do
    ~H"""
    <Kit.part
      :for={relationship <- @model.relationships}
      part={:line}
      kit={@kit}
      id={"#{@id}-row-#{@row.key}"}
      relationship={relationship}
      open?={relationship.name in @row.lines}
      colspan={@colspan}
      create={@creates[relationship.name][:create]}
      actions={@creates[relationship.name][:actions] || []}
      table={"#{@id}-row-#{@row.key}-t-#{relationship.name}"}
      myself={@myself}
    />
    """
  end

  # One relationship's line under an expanded row, and under it, while it
  # is open, the row whose one cell the nested table is moved into. `id` is
  # the row's (`ID-row-KEY`), `table` the nested table's, whose events the
  # line's buttons send.
  attr :id, :string, required: true
  attr :relationship, :map, required: true
  attr :open?, :boolean, required: true
  attr :colspan, :integer, required: true
  attr :create, :any, required: true
  attr :actions, :list, required: true
  attr :table, :string, required: true
  attr :myself, :any, required: true

  def line(assigns) do
    ~H"""
    <tr id={"#{@id}-l-#{@relationship.name}"} role="row">
      <td
        id={"#{@id}-l-#{@relationship.name}-c"}
        role="gridcell"
        colspan={@colspan}
        aria-colindex="1"
        tabindex="-1"
        {Attrs.line(@relationship)}
        class="px-0 py-1"
      >
        <%!-- What the line holds stays at the left edge of the table's
        scroll area while the table scrolls sideways under it, as the nested
        table under it does: the padding of the cell is this element's, so
        that it stands in the same place stuck and not. --%>
        <div class="sticky left-0 w-fit px-4">
          <button
            type="button"
            id={"#{@id}-l-#{@relationship.name}-b"}
            tabindex="-1"
            aria-expanded={to_string(@open?)}
            class="font-medium"
          >
            {@relationship.label}
          </button>
          <%!-- The create button of the nested table, on the line that names
          it: after the label, since the line is as wide as the table around it
          and its far end is usually out of sight. It is shown once the nested
          table has read (the rule is with the table's classes), and as high as
          the line's text, so the line is as high with it as without. --%>
          <button
            :if={@open? and @create}
            type="button"
            id={"#{@id}-l-#{@relationship.name}-create"}
            tabindex="-1"
            data-create
            phx-click={Common.event(@table, "create")}
            phx-target={@myself}
            class="btn btn-xs ms-2 hidden h-5 align-top"
          >
            {@create}
          </button>
          <%!-- The table actions of the nested table, after it and looking as
          it does: shown with it, and used on the nested table. --%>
          <button
            :for={action <- (@open? && @actions) || []}
            type="button"
            id={"#{@id}-l-#{@relationship.name}-do-#{action.name}"}
            tabindex="-1"
            {Attrs.line_action(action)}
            phx-click={Common.event(@table, "table_act")}
            phx-value-action={action.name}
            phx-target={@myself}
            class="btn btn-xs ms-2 hidden h-5 align-top"
          >
            {action.label}
          </button>
        </div>
      </td>
    </tr>
    <tr :if={@open?} id={"#{@id}-n-#{@relationship.name}"} role="row">
      <td
        id={"#{@id}-n-#{@relationship.name}-c"}
        role="gridcell"
        colspan={@colspan}
        aria-colindex="1"
        tabindex="-1"
        data-nested
        data-line-cell={"#{@id}-l-#{@relationship.name}-c"}
        data-expander-cell={"#{@id}-e"}
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
  # message, so that a translation can put its parts in another order.
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
    # in the host's words, as the line of the relationship is
    label = Text.label(assigns.via.label)

    # the message with a mark where the record goes
    parts =
      :related_heading
      |> Text.t(record: "\0", relationship: label)
      |> String.split("\0", parts: 2)

    assigns =
      assign(assigns,
        label: label,
        parts: parts,
        titled?: assigns.title && match?([_, _], parts)
      )

    ~H"""
    <div id={"#{@id}-related"} class={@kit.class(:related, %{})}>
      <h2 id={"#{@id}-related-heading"} class="font-semibold" phx-no-format><%= if @titled? do %>{hd(@parts)}<.link
            :if={@parent}
            id={"#{@id}-related-parent"}
            navigate={@parent.path}
            class="link"
          >{@title}</.link><span :if={!@parent} id={"#{@id}-related-parent"}>{@title}</span>{List.last(@parts)}<% else %>{@label}<% end %></h2>
      <div class="flex items-center gap-2">
        <Parts.Heading.create :if={@create} id={@id} action={@create} target={@target} />
        <Parts.Heading.table_actions id={@id} actions={@actions} target={@target} />
        <.link id={"#{@id}-related-clear"} patch={@clear} class="btn btn-sm">
          {Text.t(:show_all_records)}
        </.link>
      </div>
    </div>
    """
  end

  # Whether a nested table has its link to the full view: the router mounts
  # the destination's table, and the nested table has been read.
  def full_view?(page, full_view), do: not is_nil(page) and not is_nil(full_view)

  # The link to the full view is the last row of a nested table's grid,
  # for the same reason as its pages: reached with the arrow keys and
  # followed with Enter.
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
          tabindex="-1"
          aria-label={Text.t(:full_view_of, table: @label)}
          class="link sticky left-4 text-sm"
        >
          {Text.t(:full_view)}
        </.link>
      </td>
    </tr>
    """
  end
end
