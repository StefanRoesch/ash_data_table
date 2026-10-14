defmodule AshDataTable.Parts.Related do
  @moduledoc false
  # Relationship lines under an expanded row, the nested tables in them,
  # what a table limited to related records says above its grid, and the
  # link to the full view.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  alias AshDataTable.Parts
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
  attr :id, :string, required: true
  attr :row, :map, required: true
  attr :model, :map, required: true
  attr :colspan, :integer, required: true
  attr :creates, :map, required: true
  attr :reader, :map, required: true
  attr :component, :atom, required: true

  def lines(assigns) do
    assigns =
      assign(assigns,
        row_id: "#{assigns.id}-row-#{assigns.row.key}",
        first: List.first(assigns.model.columns)
      )

    ~H"""
    <%= for relationship <- @model.relationships do %>
      <tr id={"#{@row_id}-l-#{relationship.name}"} role="row">
        <td
          id={"#{@row_id}-l-#{relationship.name}-c"}
          role="gridcell"
          colspan={@colspan}
          aria-colindex="1"
          tabindex="-1"
          data-line={relationship.name}
          class="px-0 py-1"
        >
          <%!-- What the line holds stays at the left edge of the table's
          scroll area while the table scrolls sideways under it, as the nested
          table under it does: the padding of the cell is this element's, so
          that it stands in the same place stuck and not. --%>
          <div class="sticky left-0 w-fit px-4">
            <button
              type="button"
              id={"#{@row_id}-l-#{relationship.name}-b"}
              tabindex="-1"
              aria-expanded={to_string(relationship.name in @row.lines)}
              class="font-medium"
            >
              {relationship.label}
            </button>
            <%!-- The create button of the nested table, on the line that names
            it: after the label, since the line is as wide as the table around it
            and its far end is usually out of sight. It is shown once the nested
            table has read (the rule is with the table's classes), and as high as
            the line's text, so the line is as high with it as without. --%>
            <button
              :if={relationship.name in @row.lines and @creates[relationship.name][:create]}
              type="button"
              id={"#{@row_id}-l-#{relationship.name}-create"}
              tabindex="-1"
              data-create
              class="btn btn-xs ms-2 hidden h-5 align-top"
              phx-click="create"
              phx-target={"##{@row_id}-t-#{relationship.name}"}
            >
              {@creates[relationship.name].create}
            </button>
            <%!-- The table actions of the nested table, after it and looking as
            it does: shown with it, and used on the nested table. --%>
            <button
              :for={
                action <-
                  (relationship.name in @row.lines && @creates[relationship.name][:actions]) || []
              }
              type="button"
              id={"#{@row_id}-l-#{relationship.name}-do-#{action.name}"}
              tabindex="-1"
              data-table-action={action.name}
              class="btn btn-xs ms-2 hidden h-5 align-top"
              phx-click="table_act"
              phx-value-action={action.name}
              phx-target={"##{@row_id}-t-#{relationship.name}"}
            >
              {action.label}
            </button>
          </div>
        </td>
      </tr>
      <tr
        :if={relationship.name in @row.lines}
        id={"#{@row_id}-n-#{relationship.name}"}
        role="row"
      >
        <td
          id={"#{@row_id}-n-#{relationship.name}-c"}
          role="gridcell"
          colspan={@colspan}
          aria-colindex="1"
          tabindex="-1"
          data-nested
          data-line-cell={"#{@row_id}-l-#{relationship.name}-c"}
          data-expander-cell={"#{@row_id}-e"}
          class="p-0"
        >
          <%!-- A nested table is as wide as what is seen of the table around
          it, and stays there while that table scrolls sideways under it: it
          scrolls sideways in its own area (its grid), under its own rows. The
          outer element takes no width, so the columns around stay as they are,
          and holds its place at the left edge of the scroll area around it; the
          inner one is as wide as that area, which its hook says
          (`--ash-data-table-view`, see "scrolling sideways" in the hook). --%>
          <div class="sticky left-0 w-0" data-pin>
            <div class="w-[var(--ash-data-table-view)]">
              <.live_component
                module={@component}
                id={"#{@row_id}-t-#{relationship.name}"}
                resource={relationship.destination}
                table={relationship.table}
                via={relationship}
                parent_key={@row.pk}
                label={relationship.label}
                labelledby={
                  Enum.join(
                    ["#{@row_id}-l-#{relationship.name}-b"] ++
                      if(@first, do: ["#{@row_id}-c-#{@first.name}"], else: []),
                    " "
                  )
                }
                url={nil}
                mounted?={false}
                {@reader}
              />
            </div>
          </div>
        </td>
      </tr>
    <% end %>
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
    <div id={"#{@id}-related"} class="mb-2 flex flex-wrap items-center justify-between gap-2">
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

  # Part of the component's `render/1` until stage 1 of the refactor. Its
  # markup keeps the indentation it had there, held by `phx-no-format`, so
  # that the text in it, and with it the page, is the same byte for byte.
  attr :acting?, :any, required: true
  attr :full_view, :any, required: true
  attr :id, :any, required: true
  attr :label, :any, required: true
  attr :lead, :any, required: true
  attr :model, :any, required: true
  attr :nested?, :any, required: true
  attr :page, :any, required: true

  def full_view(assigns) do
    ~H"""
    <%!-- The link to the full view is the last row of a nested table's grid,
    for the same reason: reached with the arrow keys and followed with Enter. --%>
    <tr
      :if={@nested? and full_view?(@page, @full_view)}
      phx-no-format
      id={"#{@id}-view-row"}
      role="row"
    >
              <td
                id={"#{@id}-view"}
                role="gridcell"
                colspan={length(@model.columns) + @lead + Parts.Common.trail(@acting?)}
                aria-colindex="1"
                tabindex="-1"
                data-view
              >
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
