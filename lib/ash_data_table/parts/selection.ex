defmodule AshDataTable.Parts.Selection do
  @moduledoc false
  # The line above the grid: what is selected and what can be done with it,
  # the notice of changes and "Clear filters". It takes room only while one
  # of them is there. The part `selection_line` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Parts
  alias Phoenix.LiveView.JS

  # What is selected, and what can be done with it: the number of selected
  # rows, the button that selects every record the filters match, the one
  # that clears the selection, and a button per action that runs on the
  # selected rows.
  #
  # Which rows are selected the server holds, and the line is drawn from
  # it: the count, said with its plural form in a live region, which is read
  # out when it changes; the buttons, there while something is selected;
  # "all that match", there once every row of the page is selected and the
  # filters match more records than the page shows. The hook paints the
  # rows and their boxes only.
  #
  # The buttons are ordinary Tab stops while they are shown, in a nested
  # table too.
  #
  # Of more than three actions the first two are buttons of the line and
  # the others are in a menu (`More`, the browser's popover, placed as the
  # list of "Columns" is). An action that destroys has the error colour's
  # outline. "Clear selection" is a quiet button, as "Clear filters" is.
  #
  # The number is said in a live region that is always there, empty while
  # nothing is selected: a region that comes into the page with its text
  # is not read out.
  attr :id, :string, required: true
  attr :page, :any, required: true
  attr :row_count, :integer, required: true
  attr :choose?, :boolean, default: false
  attr :selected, :integer, required: true
  attr :all?, :boolean, required: true
  attr :whole_page?, :boolean, required: true
  attr :bulk, :list, required: true
  attr :running?, :boolean, required: true
  attr :texts, :map, required: true

  defp selection(assigns) do
    # In a table to choose several records from, what is selected is what
    # is chosen: it is kept while the person filters to find a record, and
    # is the rows that were selected one by one, never "all that match",
    # which names no rows.
    more? =
      case assigns.page do
        _any when assigns.choose? -> false
        nil -> false
        %{total: nil} = page -> not is_nil(page.next) or not is_nil(page.previous)
        %{total: total} -> total > assigns.row_count
      end

    any? = assigns.all? or assigns.selected > 0

    assigns =
      assign(assigns,
        any?: any?,
        offered?: any? and not assigns.all? and assigns.whole_page? and more?
      )

    ~H"""
    <div
      {Attrs.selection(@id, @texts)}
      class="flex flex-wrap items-center gap-2"
    >
      <p {Attrs.selected(@id)} class="text-sm">{@texts.selected}</p>
      <div {Attrs.selection_controls(@id, @any?)} class="flex flex-wrap items-center gap-2">
        <button type="button" {Attrs.select_all(@id, @offered?)} class="btn btn-sm">
          {@texts.select_all}
        </button>
        <button type="button" {Attrs.clear_selection(@id)} class="btn btn-ghost btn-sm">
          {@texts.clear_selection}
        </button>
        <%!-- While an action runs the buttons are not to be used, and say so
        without being `disabled`: a button that is disabled drops the focus. --%>
        <button
          :for={action <- inline(@bulk)}
          type="button"
          {Attrs.bulk(@id, action, @running?)}
          class={bulk_class(action, @running?)}
        >
          {action.label}
        </button>
        <button
          :if={menu(@bulk) != []}
          type="button"
          {Attrs.bulk_more_button(@id)}
          style={"anchor-name: --ash-data-table-more-#{@id}"}
          class="btn btn-sm"
        >
          {@texts.more_actions} <span aria-hidden="true">▾</span>
        </button>
        <ul
          :if={menu(@bulk) != []}
          {Attrs.bulk_more(@id)}
          style={"position-anchor: --ash-data-table-more-#{@id}"}
          class="dropdown menu rounded-box bg-base-100 p-2 text-base-content shadow-sm forced-colors:border [position-area:bottom_span-right] [position-try-fallbacks:flip-inline,flip-block] supports-[position-area:bottom]:inset-auto supports-[position-area:bottom]:m-0 supports-[position-area:bottom]:mt-0.5"
        >
          <li :for={action <- menu(@bulk)}>
            <button
              type="button"
              {Attrs.bulk(@id, action, @running?)}
              class={[
                "whitespace-nowrap",
                action.type == :destroy && "text-error",
                @running? && "opacity-50"
              ]}
            >
              {action.label}
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # Of more than three actions, the first two are on the line and the
  # others in the menu. Worked out where they are used, from `bulk`, so that
  # LiveView sends the buttons again only when the actions changed.
  defp inline(bulk) when length(bulk) > 3, do: Enum.take(bulk, 2)
  defp inline(bulk), do: bulk

  defp menu(bulk) when length(bulk) > 3, do: Enum.drop(bulk, 2)
  defp menu(_bulk), do: []

  defp bulk_class(action, running?) do
    [
      "btn btn-sm",
      action.type == :destroy && "btn-outline btn-error",
      running? && "btn-disabled"
    ]
  end

  attr :bulk, :any, required: true
  attr :choose, :any, required: true
  attr :id, :any, required: true
  attr :kit, :atom, required: true
  attr :myself, :any, required: true
  attr :nested?, :any, required: true
  attr :notice?, :any, required: true
  attr :page, :any, required: true
  attr :row_count, :any, required: true
  attr :running, :any, required: true
  attr :selecting, :any, required: true
  attr :selected, :integer, required: true
  attr :all?, :boolean, required: true
  attr :whole_page?, :boolean, required: true
  attr :state, :any, required: true
  attr :texts, :map, required: true

  def selection_line(assigns) do
    ~H"""
    <%!-- The line above the grid: what is selected and what can be done with
    it at one end, "Clear filters" at the other. Only while something is
    selected, a filter is set or a notice shows does it take room: no room
    is kept for it, in a table on the page as in a nested one. --%>
    <div class={
      @kit.class(:selection_line, %{
        nested?: @nested?,
        shown?: shown?(@notice?, @state, @selecting, @all?, @selected)
      })
    }>
      <.selection
        :if={@selecting == :multi}
        id={@id}
        page={@page}
        row_count={@row_count}
        choose?={not is_nil(@choose)}
        selected={@selected}
        all?={@all?}
        whole_page?={@whole_page?}
        bulk={@bulk}
        running?={not is_nil(@running)}
        texts={@texts}
      />
      <Parts.Messages.notice
        id={@id}
        myself={@myself}
        notice?={@notice?}
        texts={@texts}
      />
      <%!-- the button goes away with the filters, so focus is sent on to the
      first control of the filter row --%>
      <button
        :if={@state.filters != %{}}
        type="button"
        id={"#{@id}-clear-filters"}
        class="btn btn-ghost btn-sm ms-auto"
        phx-click={
          JS.push(Attrs.event(@id, "clear_filters"), target: @myself)
          |> JS.focus_first(to: "##{Ids.filter_row(@id)}")
        }
      >
        {@texts.clear_filters}
      </button>
    </div>
    """
  end

  # Whether anything is on the line: rows are selected, a filter is set, or
  # the notice shows.
  defp shown?(notice?, state, selecting, all?, selected),
    do: notice? or state.filters != %{} or (selecting == :multi and (all? or selected > 0))
end
