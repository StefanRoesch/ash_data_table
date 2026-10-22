defmodule AshDataTable.Parts.Selection do
  @moduledoc false
  # The line above the grid: what is selected and what can be done with it,
  # the notice of changes and "Clear filters". It takes room only while one
  # of them is there. The part `selection_line` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

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
  # list of "Columns" is: the names of its anchor are rules of the grid's
  # hook). An action that destroys has the error colour's outline. "Clear
  # selection" is a quiet button, as "Clear filters" is.
  #
  # The number is said in a live region that is always there, empty while
  # nothing is selected: a region that comes into the page with its text
  # is not read out.
  # the projection's `selection`
  attr :selection, :map, required: true
  attr :texts, :map, required: true

  defp selection(assigns) do
    ~H"""
    <div {@selection.group} class="flex flex-wrap items-center gap-2">
      <p {@selection.selected} class="text-sm">{@texts.selected}</p>
      <div {@selection.controls} class="flex flex-wrap items-center gap-2">
        <button type="button" {@selection.select_all} class="btn btn-sm">
          {@texts.select_all}
        </button>
        <button type="button" {@selection.clear} class="btn btn-ghost btn-sm">
          {@texts.clear_selection}
        </button>
        <%!-- While an action runs the buttons are not to be used, and say so
        without being `disabled`: a button that is disabled drops the focus. --%>
        <button
          :for={action <- @selection.inline}
          type="button"
          {action.button}
          class={bulk_class(action, @selection.running?)}
        >
          {action.label}
        </button>
        <button
          :if={@selection.more}
          type="button"
          {@selection.more.button}
          class="btn btn-sm"
        >
          {@texts.more_actions} <span aria-hidden="true">▾</span>
        </button>
        <ul
          :if={@selection.more}
          {@selection.more.menu}
          class="dropdown menu rounded-box bg-base-100 p-2 text-base-content shadow-sm forced-colors:border [position-area:bottom_span-right] [position-try-fallbacks:flip-inline,flip-block] supports-[position-area:bottom]:inset-auto supports-[position-area:bottom]:m-0 supports-[position-area:bottom]:mt-0.5"
        >
          <li :for={action <- @selection.more.actions}>
            <button
              type="button"
              {action.button}
              class={[
                "whitespace-nowrap",
                action.destroys? && "text-error",
                @selection.running? && "opacity-50"
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

  defp bulk_class(action, running?) do
    [
      "btn btn-sm",
      action.destroys? && "btn-outline btn-error",
      running? && "btn-disabled"
    ]
  end

  # What others have changed that the page does not show: said once
  # through the live region, and here for as long as it holds, with the
  # button that reads the page again. The button goes away with the notice,
  # so focus is sent on to the table's first Tab stop (in its bundle).
  attr :notice, :map, required: true
  attr :texts, :map, required: true

  defp notice(assigns) do
    ~H"""
    <p {@notice.element} class="flex items-center gap-2 text-sm">
      <span>{@texts.changed_records}</span>
      <button type="button" {@notice.read_again} class="btn btn-sm">
        {@texts.read_again}
      </button>
    </p>
    """
  end

  # Its projection (`AshDataTable.Kit.Projection`, `selection_line`).
  attr :id, :string, required: true
  attr :shown?, :boolean, required: true
  attr :nested?, :boolean, required: true
  attr :selection, :map, required: true
  attr :notice, :map, required: true
  attr :clear_filters, :map, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true
  attr :kit, :atom, required: true

  def selection_line(assigns) do
    ~H"""
    <%!-- The line above the grid: what is selected and what can be done with
    it at one end, "Clear filters" at the other. Only while something is
    selected, a filter is set or a notice shows does it take room: no room
    is kept for it, in a table on the page as in a nested one. --%>
    <div class={@kit.class(:selection_line, %{nested?: @nested?, shown?: @shown?})}>
      <.selection :if={@selection} selection={@selection} texts={@texts} />
      <.notice :if={@notice} notice={@notice} texts={@texts} />
      <%!-- the button goes away with the filters, so focus is sent on to the
      first control of the filter row (in its bundle) --%>
      <button :if={@clear_filters} type="button" {@clear_filters} class="btn btn-ghost btn-sm ms-auto">
        {@texts.clear_filters}
      </button>
    </div>
    """
  end
end
