defmodule AshDataTable.Components.Badge do
  @moduledoc """
  A component that shows a choice as a badge: the label of an enum's value,
  in an outlined pill.

      column :status do
        component AshDataTable.Components.Badge
      end

  It only shows: an editable column keeps the table's own menu.

  ## What it needs

  A column whose field is a choice: an `Ash.Type.Enum`, or an `:atom` with
  `constraints one_of: [...]`. On anything else the compiler warns, and the
  table refuses to be built.

  ## How it looks

  daisyUI's `badge`, without a fill, with an edge at half the strength of
  the text colour and the label in the text colour, at the size of the
  table's text. The row is as high as a row without it.

  Every value has the same badge. There is no colour per value: in a theme
  whose semantic colours are made for fills and not for text (those of the
  Phoenix generator, for one), a badge in `success` or `warning` does not
  have the contrast that text needs. The label says the value.
  """
  use AshDataTable.Component

  @impl true
  def verify(%{cell_type: :enum}), do: :ok

  def verify(%{cell_type: cell_type}) do
    {:error,
     "a badge shows the label of a choice, and this field is shown as " <>
       "#{AshDataTable.Components.shown_as(cell_type)}. It needs an `Ash.Type.Enum`, or an " <>
       "`:atom` with `constraints one_of: [...]`."}
  end

  attr :value, :any, required: true, doc: "the value as the record holds it"
  attr :text, :string, required: true, doc: "what the table itself would show for it"

  attr :column, AshDataTable.Component.Column,
    required: true,
    doc: "what the resource knows about the field"

  @impl true
  def cell(assigns) do
    ~H"""
    <span class="badge border-base-content/50 bg-transparent align-top">{@text}</span>
    """
  end
end
