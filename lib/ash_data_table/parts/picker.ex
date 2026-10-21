defmodule AshDataTable.Parts.Picker do
  @moduledoc false
  # The picker dialog around the table a record is chosen from: the part
  # `picker` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  # The picker: where a person chooses the related record of a reference
  # cell, or of a field of the action panel that holds such a key. A modal
  # dialog at the right edge of the window, as the action panel is, and on
  # top of it when a field of the panel has opened it. It holds the table of
  # the destination resource, told that it is one to choose from, whose rows
  # are selected one at a time; "Choose" takes the selected row.
  #
  # The table is as wide as its columns need, so the dialog is wider than
  # the panel, and the table scrolls sideways in it as it does on a page.
  # `AshDataTable.Live.Drawing` draws it, and moves it into the picker's
  # place (`Phoenix.Component.portal/1`).
  #
  # Its projection (`AshDataTable.Kit.Projection`, `picker`): nothing is
  # drawn while it is closed (`open?`).
  attr :id, :string, required: true
  attr :open?, :boolean, required: true
  # `:modal`, a dialog over the page, or `:inline`, a part of it
  attr :presentation, :atom, required: true
  attr :place, :map, required: true
  attr :frame, :map, required: true
  attr :title, :map, required: true
  attr :error, :map, required: true
  attr :cancel, :map, required: true
  attr :none, :map, required: true
  attr :take, :map, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true
  attr :kit, :atom, required: true

  def picker(%{open?: false} = assigns), do: ~H""

  def picker(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={if @presentation == :modal, do: "dialog", else: "section"}
      {@frame}
      class={@kit.class(:picker, %{presentation: @presentation})}
    >
      <h2 {@title} class="mb-4 text-lg font-semibold">{@texts.title}</h2>
      <%!-- the row that was chosen names no record this person may read --%>
      <p :if={@error} {@error} class="mb-4 text-sm font-medium">
        {@texts.error}
      </p>
      <div {@place} class="contents"></div>
      <div class="mt-6 flex justify-end gap-2">
        <button type="button" {@cancel} class="btn">
          {@texts.cancel}
        </button>
        <button :if={@none} type="button" {@none} class="btn">
          {@texts.choose_none}
        </button>
        <%!-- Not to be used while no row is selected, and says so without
        being `disabled`, as the buttons above a grid do. The picker's table
        tells the server what is selected. Where several records are chosen
        it is always to be used: no row selected is a choice too, of no
        record. --%>
        <button type="button" {@take} class="btn btn-primary aria-disabled:btn-disabled">
          {@texts.choose}
        </button>
      </div>
    </.dynamic_tag>
    """
  end
end
