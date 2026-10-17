defmodule AshDataTable.Parts.Messages do
  @moduledoc false
  # What the table says: the live region and the result of a run (the
  # part `status`), the notice of changes, the question dialog (`confirm`),
  # the whole text of a cell (`whole_text`), and the error, loading, fill
  # and empty messages (`message`), of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  import AshDataTable.Parts.Common, only: [said: 1]

  alias AshDataTable.Attrs
  alias AshDataTable.Parts
  alias AshDataTable.Text
  alias Phoenix.LiveView.JS

  # Whether anything of the table asks a question before it runs: a column,
  # a row action, a table action, and every action on the selected rows.
  defp asks?(model, bulk),
    do:
      bulk != [] or Enum.any?(model.columns, & &1.confirm) or
        Enum.any?(model.actions ++ model.table_actions, & &1.confirm)

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
    <p :if={@notice?} id={"#{@id}-notice"} class="flex items-center gap-2 text-sm">
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

  attr :announcement, :any, required: true
  attr :announcements, :any, required: true
  attr :id, :any, required: true
  attr :result, :any, required: true
  attr :kit, :atom, required: true

  def status(assigns) do
    ~H"""
    <%!-- Read out after each filter change, and when a save fails. A live region
    is only read when its content changes, so every other announcement ends in a
    no-break space. --%>
    <p {Attrs.status(@id)} class={@kit.class(:status, %{})} phx-no-format>{said(@announcement)}{if rem(@announcements, 2) == 1, do: "\u00A0"}</p>
    <%!-- What the last action on the selected rows came to: on how many records
    it ran, on how many it did not, and why not. It is read out through the live
    region above, and stays until the selection changes. In the text colour. --%>
    <p :if={@result} id={"#{@id}-result"} class="mb-2 text-sm">
      <span data-summary>{said(@result.summary)}</span>
      <span :for={failure <- @result.failures} data-failure>{said(failure)}</span>
    </p>
    """
  end

  attr :id, :any, required: true
  attr :kit, :atom, required: true

  def whole_text(assigns) do
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
      {Attrs.whole(@id)}
      class={@kit.class(:whole_text, %{})}
    ></div>
    """
  end

  attr :bulk, :any, required: true
  attr :id, :any, required: true
  attr :model, :any, required: true
  # `:modal`, a dialog over the page, or `:inline`, a part of it
  attr :presentation, :atom, required: true
  attr :kit, :atom, required: true

  def confirm(assigns) do
    ~H"""
    <%!-- The one dialog of the table: it asks the question of a column with
    `confirm` before the cell is saved, that of a row action, and the one that
    comes before every action on the selected rows. The hook opens it and puts
    the question in, so patches leave it alone. --%>
    <div :if={asks?(@model, @bulk)} id={"#{@id}-dialogs"} phx-update="ignore">
      <%!-- Styled here and not with daisyUI's `modal`: that one fades in, and
        a dialog that is not visible yet when it opens cannot take the focus. Its
        edge is its shadow, which forced colours take away: there it has a border. --%>
      <.dynamic_tag
        tag_name={if @presentation == :modal, do: "dialog", else: "section"}
        {Attrs.confirm(@id, @presentation)}
        class={@kit.class(:confirm, %{presentation: @presentation})}
      >
        <form method="dialog">
          <p id={"#{@id}-dialog-question"}></p>
          <div class="mt-6 flex justify-end gap-2">
            <button value="cancel" class="btn">{Text.t(:cancel)}</button>
            <button value="confirm" class="btn btn-primary data-destructive:btn-error">
              {Text.t(:confirm)}
            </button>
          </div>
        </form>
      </.dynamic_tag>
    </div>
    """
  end

  # What is said in place of the rows: the error of a read (`role=alert`),
  # a nested table whose first read is on its way (`:loading`), an argument
  # the read action requires that is empty (`:fill`: no read is run, and it
  # is neither an error nor "No records"; it is read out through the live
  # region), and "No records" (`:empty`). In the text colour: the error
  # colour is too faint for small text.
  attr :id, :string, required: true
  attr :kind, :atom, required: true
  attr :text, :string, required: true
  attr :nested?, :boolean, required: true
  attr :kit, :atom, required: true

  def message(assigns) do
    ~H"""
    <p
      id={"#{@id}-#{@kind}"}
      role={@kind == :error && "alert"}
      class={@kit.class(:message, %{kind: @kind, nested?: @nested?})}
    >
      {@text}
    </p>
    """
  end

  # The messages the table shows now, each with what it says.
  def messages(error, fill, loading?, row_count) do
    [
      error && {:error, said(error)},
      loading? && {:loading, Text.t(:loading)},
      fill && {:fill, said(fill)},
      (is_nil(error) and is_nil(fill) and row_count == 0 and not loading?) &&
        {:empty, Text.t(:no_records)}
    ]
    |> Enum.filter(& &1)
  end
end
