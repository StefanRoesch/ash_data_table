defmodule AshDataTable.Parts.Picker do
  @moduledoc false
  # The picker dialog around the table a record is chosen from.
  use Phoenix.Component

  import AshDataTable.Parts.Common, only: [said: 1]

  alias AshDataTable.Attrs
  alias AshDataTable.Present
  alias AshDataTable.Text

  # The picker: where a person chooses the related record of a reference
  # cell, or of a field of the action panel that holds such a key. A modal
  # dialog at the right edge of the window, as the action panel is, and on
  # top of it when a field of the panel has opened it. It holds the table of
  # the destination resource, told that it is one to choose from, whose rows
  # are selected one at a time; "Choose" takes the selected row.
  #
  # The table is as wide as its columns need, so the dialog is wider than
  # the panel, and the table scrolls sideways in it as it does on a page.
  # It is the slot: the table component draws it.
  attr :id, :string, required: true
  # what `AshDataTable.Present.picker/1` gives of the open picker
  attr :picker, Present.Picker, required: true
  attr :target, :any, required: true
  slot :inner_block, required: true

  def picker(assigns) do
    ~H"""
    <dialog
      {Attrs.picker(@id, said(@picker.question), @picker.several?, @target)}
      class="m-0 ms-auto h-dvh max-h-dvh w-full max-w-3xl overflow-y-auto bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/40 forced-colors:border"
    >
      <h2 id={"#{@id}-picker-title"} class="mb-4 text-lg font-semibold">{said(@picker.title)}</h2>
      <%!-- the row that was chosen names no record this person may read --%>
      <p
        :if={@picker.error}
        id={"#{@id}-picker-error"}
        role="alert"
        class="mb-4 text-sm font-medium"
      >
        {said(@picker.error)}
      </p>
      {render_slot(@inner_block)}
      <div class="mt-6 flex justify-end gap-2">
        <button type="button" {Attrs.cancel("#{@id}-picker-cancel")} class="btn">
          {Text.t(:cancel)}
        </button>
        <button
          :if={@picker.none?}
          type="button"
          {Attrs.none(@id)}
          class="btn"
        >
          {Text.t(:choose_none)}
        </button>
        <%!-- Not to be used while no row is selected, and says so without
        being `disabled`, as the buttons above a grid do. Which rows are
        selected is the hook's, so this is too: a patch leaves it alone.
        Where several records are chosen it is always to be used: no row
        selected is a choice too, of no record. --%>
        <button
          type="button"
          {Attrs.take(@id, @picker.several?)}
          class="btn btn-primary aria-disabled:btn-disabled"
        >
          {Text.t(:choose)}
        </button>
      </div>
    </dialog>
    """
  end
end
