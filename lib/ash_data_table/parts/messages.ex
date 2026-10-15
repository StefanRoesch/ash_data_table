defmodule AshDataTable.Parts.Messages do
  @moduledoc false
  # What the table says: the live region, the notice of changes, the
  # result of a run, the question dialog, the failure of a cell, the whole
  # text of a cell, and the error, loading, fill and empty messages.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  import AshDataTable.Parts.Common, only: [said: 1]

  alias AshDataTable.Parts
  alias AshDataTable.Text
  alias Phoenix.LiveView.JS

  # Whether anything of the table asks a question before it runs: a column,
  # a row action, a table action, and every action on the selected rows.
  defp asks?(model, bulk),
    do:
      bulk != [] or Enum.any?(model.columns, & &1.confirm) or
        Enum.any?(model.actions ++ model.table_actions, & &1.confirm)

  # Its markup keeps the indentation it had in the table component's
  # `render/1`, held by `phx-no-format`, so that the text in it, and with it
  # the page, is the same byte for byte.
  attr :id, :any, required: true
  attr :myself, :any, required: true
  attr :nested?, :any, required: true
  attr :notice?, :any, required: true

  def notice(assigns) do
    ~H"""
    <%!-- What others have changed that the page does not show: said once
    through the live region below, and here for as long as it holds, with the
    button that reads the page again. The button goes away with the notice,
    so focus is sent on to the grid. --%>
    <p :if={@notice?} phx-no-format id={"#{@id}-notice"} class="flex items-center gap-2 text-sm">
          <span>{Text.t(:changed_records)}</span>
          <button
            type="button"
            id={"#{@id}-read-again"}
            tabindex={@nested? && "-1"}
            class="btn btn-sm"
            phx-click={
              JS.push(Parts.Common.event(@id, "read_again"), target: @myself)
              |> JS.focus(to: "##{@id}-table [tabindex='0']")
            }
          >
            {Text.t(:read_again)}
          </button>
        </p>
    """
  end

  # Its markup keeps the indentation it had in the table component's
  # `render/1`, held by `phx-no-format`, so that the text in it, and with it
  # the page, is the same byte for byte.
  attr :announcement, :any, required: true
  attr :announcements, :any, required: true
  attr :id, :any, required: true
  attr :result, :any, required: true

  def status(assigns) do
    ~H"""
    <%!-- Read out after each filter change, and when a save fails. A live region
    is only read when its content changes, so every other announcement ends in a
    no-break space. --%>
    <p id={"#{@id}-status"} role="status" aria-live="polite" class="sr-only" phx-no-format>{said(@announcement)}{if rem(@announcements, 2) == 1, do: "\u00A0"}</p>
    <%!-- What the last action on the selected rows came to: on how many records
    it ran, on how many it did not, and why not. It is read out through the live
    region above, and stays until the selection changes. In the text colour. --%>
    <p :if={@result} phx-no-format id={"#{@id}-result"} class="mb-2 text-sm">
        <span data-summary>{said(@result.summary)}</span>
        <span :for={failure <- @result.failures} data-failure>{said(failure)}</span>
      </p>
    """
  end

  # Its markup keeps the indentation it had in the table component's
  # `render/1`, held by `phx-no-format`, so that the text in it, and with it
  # the page, is the same byte for byte.
  attr :acting?, :any, required: true
  attr :editing?, :any, required: true
  attr :id, :any, required: true

  def failure(assigns) do
    ~H"""
    <%!-- The message of a cell whose save failed, for the one case in which
    the hook has to mark the cell itself: the record is gone, so there is
    no row to send. --%>
    <template :if={@editing? or @acting?} phx-no-format id={"#{@id}-failure"}>{Parts.Common.failure_message(nil, "")}</template>
    """
  end

  # Its markup keeps the indentation it had in the table component's
  # `render/1`, held by `phx-no-format`, so that the text in it, and with it
  # the page, is the same byte for byte.
  attr :id, :any, required: true

  def whole(assigns) do
    ~H"""
    <%!-- The whole text of a cell whose text is cut off: the hook puts it in,
    from what the cell itself holds, and shows it under the cell while the cell
    has the focus or the pointer (see "the whole text of a cell"). The server
    renders it empty (`phx-no-format`: not even a line break, which the
    popover would show) and never writes to it. For the eye alone: a screen
    reader has the whole text in the cell. With the edge and the ground of the
    table's other popovers; as wide and as high as it may be, it scrolls. --%>
    <div
      phx-no-format
      id={"#{@id}-whole"}
      popover="manual"
      phx-update="ignore"
      aria-hidden="true"
      data-whole
      class="inset-auto m-0 max-h-60 max-w-md overflow-y-auto rounded border border-base-content/40 bg-base-100 px-2 py-1 text-sm break-words whitespace-pre-line text-base-content shadow"
      phx-no-format
    ></div>
    """
  end

  # Its markup keeps the indentation it had in the table component's
  # `render/1`, held by `phx-no-format`, so that the text in it, and with it
  # the page, is the same byte for byte.
  attr :bulk, :any, required: true
  attr :id, :any, required: true
  attr :model, :any, required: true

  def dialog(assigns) do
    ~H"""
    <%!-- The one dialog of the table: it asks the question of a column with
    `confirm` before the cell is saved, that of a row action, and the one that
    comes before every action on the selected rows. The hook opens it and puts
    the question in, so patches leave it alone. --%>
    <div :if={asks?(@model, @bulk)} phx-no-format id={"#{@id}-dialogs"} phx-update="ignore">
        <%!-- Styled here and not with daisyUI's `modal`: that one fades in, and
        a dialog that is not visible yet when it opens cannot take the focus. Its
        edge is its shadow, which forced colours take away: there it has a border. --%>
        <dialog
          id={"#{@id}-dialog"}
          aria-labelledby={"#{@id}-dialog-question"}
          class="m-auto w-full max-w-md rounded-box bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/40 forced-colors:border"
        >
          <form method="dialog">
            <p id={"#{@id}-dialog-question"}></p>
            <div class="mt-6 flex justify-end gap-2">
              <button value="cancel" class="btn">{Text.t(:cancel)}</button>
              <button value="confirm" class="btn btn-primary">{Text.t(:confirm)}</button>
            </div>
          </form>
        </dialog>
      </div>
    """
  end

  # Its markup keeps the indentation it had in the table component's
  # `render/1`, held by `phx-no-format`, so that the text in it, and with it
  # the page, is the same byte for byte.
  attr :error, :any, required: true
  attr :fill, :any, required: true
  attr :id, :any, required: true
  attr :loading?, :any, required: true
  attr :nested?, :any, required: true
  attr :row_count, :any, required: true

  def messages(assigns) do
    ~H"""
    <%!-- in the text colour: the error colour is too faint for small text --%>
    <p
      :if={@error}
      phx-no-format
      id={"#{@id}-error"}
      role="alert"
      class={[if(@nested?, do: "py-4", else: "py-8"), "text-center text-sm font-medium"]}
    >
        {said(@error)}
      </p>
    <%!-- a nested table whose first read is on its way --%>
    <p :if={@loading?} phx-no-format id={"#{@id}-loading"} class="py-4 text-center text-sm opacity-70">
        {Text.t(:loading)}
      </p>
    <%!-- In place of the rows while an argument that the read action requires
    is empty: no read is run, and this is neither an error nor "No records".
    It is read out through the live region above. --%>
    <p
      :if={@fill}
      phx-no-format
      id={"#{@id}-fill"}
      class={[if(@nested?, do: "py-4", else: "py-8"), "text-center text-sm opacity-70"]}
    >
        {said(@fill)}
      </p>
    <p
      :if={is_nil(@error) and is_nil(@fill) and @row_count == 0 and not @loading?}
      phx-no-format
      id={"#{@id}-empty"}
      class={[if(@nested?, do: "py-4", else: "py-8"), "text-center text-sm opacity-70"]}
    >
        {Text.t(:no_records)}
      </p>
    """
  end
end
