defmodule AshDataTable.Components.Progress do
  @moduledoc """
  A component that shows a number as a bar, with the number beside it: how
  far the value is from the attribute's minimum to its maximum.

      attribute :progress, :integer do
        constraints min: 0, max: 100
      end

      table do
        column :progress do
          component AshDataTable.Components.Progress
        end
      end

  It only shows: an editable column keeps the table's own number editor. To
  edit with a slider as well, put its `cell/1` together with the `editor/1`
  of `AshDataTable.Components.Slider` in a module of your own, as the guide
  "Custom components" does.

  ## What it needs

  A column whose field is a number (an integer, a decimal or a float) with
  both `min` and `max` among its constraints. On anything else the compiler
  warns, and the table refuses to be built.

  ## How it looks

  A native `<progress>` element, drawn with daisyUI's `progress` in the text
  colour, a fixed width, and the number as the table writes it. The number
  is what says the value: the bar is hidden from screen readers, so the
  value is read once, and nobody has to judge a length. The row is as high
  as a row without it.
  """
  use AshDataTable.Component

  @impl true
  def verify(%{cell_type: :number, constraints: constraints}) do
    if is_nil(constraints[:min]) or is_nil(constraints[:max]) do
      {:error,
       "a progress bar needs a number with a minimum and a maximum. Declare both on the " <>
         "attribute: `constraints min: 0, max: 100`."}
    else
      :ok
    end
  end

  def verify(%{cell_type: cell_type}) do
    {:error,
     "a progress bar needs a number with a minimum and a maximum, and this field is shown " <>
       "as #{AshDataTable.Components.shown_as(cell_type)}."}
  end

  attr :value, :any, required: true, doc: "the value as the record holds it"
  attr :text, :string, required: true, doc: "what the table itself would show for it"

  attr :column, AshDataTable.Component.Column,
    required: true,
    doc: "what the resource knows about the field"

  @impl true
  def cell(assigns) do
    %{value: value, column: %{constraints: constraints}} = assigns
    min = number(constraints[:min])

    assigns =
      assign(assigns, done: number(value) - min, of: number(constraints[:max]) - min)

    ~H"""
    <span class="flex items-center gap-2" phx-no-format><progress class="progress w-16 forced-color-adjust-none forced-colors:text-[CanvasText]" value={@done} max={@of} aria-hidden="true"></progress>{@text}</span>
    """
  end

  defp number(%Decimal{} = number), do: Decimal.to_float(number)
  defp number(number) when is_number(number), do: number
end
