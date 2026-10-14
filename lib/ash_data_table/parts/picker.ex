defmodule AshDataTable.Parts.Picker do
  @moduledoc false
  # The picker dialog around the table a record is chosen from.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  alias AshDataTable.Model
  alias AshDataTable.Text
  alias Phoenix.LiveView.JS

  # The picker: where a person chooses the related record of a reference
  # cell, or of a field of the action panel that holds such a key. A modal
  # dialog at the right edge of the window, as the action panel is, and on
  # top of it when a field of the panel has opened it. It holds the table of
  # the destination resource, told that it is one to choose from, whose rows
  # are selected one at a time; "Choose" takes the selected row.
  #
  # The table is as wide as its columns need, so the dialog is wider than
  # the panel, and the table scrolls sideways in it as it does on a page.
  attr :id, :string, required: true
  attr :picker, :map, required: true
  attr :reader, :map, required: true
  attr :component, :atom, required: true
  attr :target, :any, required: true

  def picker(assigns) do
    ~H"""
    <dialog
      id={"#{@id}-picker"}
      phx-hook="AshDataTable.Live.TableComponent.Picker"
      phx-mounted={JS.ignore_attributes(["open"])}
      phx-target={@target}
      data-question={@picker.question}
      data-several={@picker.several?}
      aria-labelledby={"#{@id}-picker-title"}
      class="m-0 ms-auto h-dvh max-h-dvh w-full max-w-3xl overflow-y-auto bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/40 forced-colors:border"
    >
      <h2 id={"#{@id}-picker-title"} class="mb-4 text-lg font-semibold">{@picker.title}</h2>
      <%!-- the row that was chosen names no record this person may read --%>
      <p
        :if={@picker.error}
        id={"#{@id}-picker-error"}
        role="alert"
        class="mb-4 text-sm font-medium"
      >
        {@picker.error}
      </p>
      <.live_component
        module={@component}
        id={"#{@id}-pick-#{@picker.name}"}
        resource={@picker.reference.destination}
        table={:default}
        select={if @picker.several?, do: :multi, else: :single}
        choose={
          %{
            read_action: @picker.reference.choose_action,
            current: {@picker.reference.destination_attribute, @picker.current},
            chosen: @picker.chosen
          }
        }
        label={Text.label(Model.label(@picker.reference.destination))}
        heading={false}
        url={nil}
        mounted?={false}
        {@reader}
      />
      <div class="mt-6 flex justify-end gap-2">
        <button type="button" id={"#{@id}-picker-cancel"} class="btn" data-cancel>
          {Text.t(:cancel)}
        </button>
        <button
          :if={@picker.none?}
          type="button"
          id={"#{@id}-picker-none"}
          class="btn"
          data-none
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
          id={"#{@id}-picker-choose"}
          class={["btn btn-primary", not @picker.several? && "btn-disabled"]}
          aria-disabled={to_string(not @picker.several?)}
          phx-mounted={JS.ignore_attributes(["aria-disabled", "class"])}
          data-take
        >
          {Text.t(:choose)}
        </button>
      </div>
    </dialog>
    """
  end
end
