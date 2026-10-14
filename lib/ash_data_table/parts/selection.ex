defmodule AshDataTable.Parts.Selection do
  @moduledoc false
  # The line above the grid: what is selected and what can be done with it.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  alias AshDataTable.Model
  alias AshDataTable.Parts
  alias AshDataTable.Text
  alias Phoenix.LiveView.JS

  # What is selected, and what can be done with it: the number of selected
  # rows, the button that selects every record the filters match, the one
  # that clears the selection, and a button per action that runs on the
  # selected rows.
  #
  # Which rows are selected is known to the hook alone, so what depends on
  # it is the hook's to put in: the text of the count, which is a live
  # region and is read out when it changes, and whether the controls and
  # the button for "all that match" are shown. The server renders them
  # hidden and leaves both alone afterwards. What it says for the hook:
  #
  #   * `data-scope` stands for the filters, and for what the table is
  #     limited to: a selection is given up when it changes;
  #   * `data-more` is there when the filters match more records than the
  #     page shows, which is when "all that match" is offered;
  #   * `data-selected` and `data-all` are the two texts of the count, the
  #     first with `{n}` where the number goes.
  #
  # The buttons are ordinary tab stops while they are shown, in a nested
  # table too: they are there only while rows are selected, and have to be
  # reached then.
  attr :id, :string, required: true
  attr :page, :any, required: true
  attr :row_count, :integer, required: true
  attr :scope, :any, required: true
  attr :choose?, :boolean, default: false
  attr :bulk, :list, required: true
  attr :running?, :boolean, required: true

  defp selection(assigns) do
    total = assigns.page && assigns.page.total

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

    assigns =
      assign(assigns,
        total: total,
        more?: more?,
        scope: if(assigns.choose?, do: :choose, else: assigns.scope)
      )

    ~H"""
    <div
      id={"#{@id}-selection"}
      role="group"
      aria-label={Text.t(:selected_rows)}
      data-selection
      data-scope={:erlang.phash2(@scope)}
      data-more={@more?}
      data-selected={Text.t(:selected, count: "{n}")}
      data-all={
        if @total,
          do: Text.t(:all_selected, count: @total),
          else: Text.t(:all_selected_uncounted)
      }
      class="flex flex-wrap items-center gap-2"
    >
      <p id={"#{@id}-selected"} role="status" phx-update="ignore" class="text-sm"></p>
      <div
        id={"#{@id}-selection-controls"}
        hidden
        phx-mounted={JS.ignore_attributes(["hidden"])}
        class="flex flex-wrap items-center gap-2"
      >
        <button
          type="button"
          id={"#{@id}-select-all"}
          hidden
          phx-mounted={JS.ignore_attributes(["hidden"])}
          data-select-all
          class="btn btn-sm"
        >
          {if @total,
            do: Text.t(:select_all, count: @total),
            else: Text.t(:select_all_uncounted)}
        </button>
        <button
          type="button"
          id={"#{@id}-clear-selection"}
          data-clear
          class="btn btn-sm"
        >
          {Text.t(:clear_selection)}
        </button>
        <%!-- While an action runs the buttons are not to be used, and say so
        without being `disabled`: a button that is disabled drops the focus. --%>
        <button
          :for={action <- @bulk}
          type="button"
          id={"#{@id}-bulk-#{action.name}"}
          aria-disabled={@running? && "true"}
          data-bulk={action.name}
          data-destructive={action.type == :destroy}
          class={["btn btn-sm", @running? && "btn-disabled"]}
        >
          {action.label}
        </button>
      </div>
    </div>
    """
  end

  # Part of the component's `render/1` until stage 1 of the refactor. Its
  # markup keeps the indentation it had there, held by `phx-no-format`, so
  # that the text in it, and with it the page, is the same byte for byte.
  attr :bulk, :any, required: true
  attr :choose, :any, required: true
  attr :id, :any, required: true
  attr :model, :any, required: true
  attr :myself, :any, required: true
  attr :nested?, :any, required: true
  attr :notice?, :any, required: true
  attr :page, :any, required: true
  attr :related, :any, required: true
  attr :row_count, :any, required: true
  attr :running, :any, required: true
  attr :selecting, :any, required: true
  attr :state, :any, required: true

  def selection_line(assigns) do
    ~H"""
    <%!-- The line above the grid: what is selected and what can be done with
    it at one end, "Clear filters" and "Columns" at the other. As high as a
    button, so that the table does not move when one of them appears; a nested
    table keeps no room free for it. --%>
    <div
      phx-no-format
      class={[
        "flex flex-wrap items-center gap-2",
        if(@nested?, do: "justify-start", else: "mb-2 min-h-8 justify-between")
      ]}
    >
        <.selection
          :if={@selecting == :multi}
          id={@id}
          page={@page}
          row_count={@row_count}
          scope={{@state.filters, @state.arguments, @related && @related.param}}
          choose?={not is_nil(@choose)}
          bulk={@bulk}
          running?={not is_nil(@running)}
        />
        <Parts.Messages.notice
          id={@id}
          myself={@myself}
          nested?={@nested?}
          notice?={@notice?}
        />
        <%!-- the button goes away with the filters, so focus is sent on to the grid --%>
        <button
          :if={@state.filters != %{}}
          type="button"
          id={"#{@id}-clear-filters"}
          tabindex={@nested? && "-1"}
          class={["btn btn-sm", not @nested? && "ms-auto"]}
          phx-click={
            JS.push("clear_filters", target: @myself)
            |> JS.focus(to: "##{@id}-table [tabindex='0']")
          }
        >
          {Text.t(:clear_filters)}
        </button>
        <Parts.Grid.columns
          :if={length(@model.columns) > 1 and Parts.Grid.hideable(@model) != []}
          id={@id}
          columns={Parts.Grid.hideable(@model)}
          keeps_one?={Model.keeps_one?(@model)}
          state={@state}
          class={not @nested? and @state.filters == %{} and "ms-auto"}
        />
      </div>
    """
  end
end
