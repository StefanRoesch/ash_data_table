defmodule AshDataTable.Parts.Selection do
  @moduledoc false
  # The line above the grid: what is selected and what can be done with it,
  # the notice of changes, "Clear filters" and "Columns" (the kit's
  # `columns/1`). The part `selection_line` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Kit
  alias AshDataTable.Kit.Words
  alias AshDataTable.Model
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
  # The buttons are ordinary tab stops while they are shown, in a nested
  # table too: they are there only while rows are selected, and have to be
  # reached then.
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
        <button type="button" {Attrs.clear_selection(@id)} class="btn btn-sm">
          {@texts.clear_selection}
        </button>
        <%!-- While an action runs the buttons are not to be used, and say so
        without being `disabled`: a button that is disabled drops the focus. --%>
        <button
          :for={action <- @bulk}
          type="button"
          {Attrs.bulk(@id, action, @running?)}
          class={["btn btn-sm", @running? && "btn-disabled"]}
        >
          {action.label}
        </button>
      </div>
    </div>
    """
  end

  attr :bulk, :any, required: true
  attr :choose, :any, required: true
  attr :id, :any, required: true
  attr :kit, :atom, required: true
  attr :model, :any, required: true
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
    it at one end, "Clear filters" and "Columns" at the other. As high as a
    button, so that the table does not move when one of them appears; a nested
    table keeps no room free for it. --%>
    <div class={@kit.class(:selection_line, %{nested?: @nested?})}>
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
        nested?={@nested?}
        notice?={@notice?}
        texts={@texts}
      />
      <%!-- the button goes away with the filters, so focus is sent on to the grid --%>
      <button
        :if={@state.filters != %{}}
        type="button"
        id={"#{@id}-clear-filters"}
        tabindex={@nested? && "-1"}
        class={["btn btn-sm", not @nested? && "ms-auto"]}
        phx-click={
          JS.push(Parts.Common.event(@id, "clear_filters"), target: @myself)
          |> JS.focus(to: "##{@id}-table [tabindex='0']")
        }
      >
        {@texts.clear_filters}
      </button>
      <Kit.part
        :if={length(@model.columns) > 1 and Parts.Grid.hideable(@model) != []}
        part={:columns}
        kit={@kit}
        id={@id}
        columns={Parts.Grid.hideable(@model)}
        keeps_one?={Model.keeps_one?(@model)}
        state={@state}
        class={not @nested? and @state.filters == %{} and "ms-auto"}
        texts={Words.texts(:columns, %{columns: Parts.Grid.hideable(@model), state: @state})}
        messages={Words.messages(:columns, %{columns: Parts.Grid.hideable(@model), state: @state})}
      />
    </div>
    """
  end
end
