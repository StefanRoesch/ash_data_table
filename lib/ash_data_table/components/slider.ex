defmodule AshDataTable.Components.Slider do
  @moduledoc """
  A component that edits a number with a slider: a native
  `<input type="range">` between the attribute's minimum and maximum, with
  the number that is being chosen beside it.

      attribute :progress, :integer do
        constraints min: 0, max: 100
      end

      table do
        update_action :update

        column :progress do
          component AshDataTable.Components.Slider
        end
      end

  It only edits: the cells show the number as the table shows any number.
  To show it another way as well, put the slider's `editor/1` together with
  a `cell/1` in a module of your own, as the guide "Custom components" does
  with `AshDataTable.Components.Progress`.

  ## What it needs

  A column whose field is a number (an integer, a decimal or a float) with
  both `min` and `max` among its constraints. On anything else the compiler
  warns, and the table refuses to be built.

  ## How it behaves

    * It saves when its value changes (`commit: :change`): on letting go of
      the slider, not while it is dragged. It stays open, so the value can
      be changed again; Enter or leaving the cell closes it.
    * From the keyboard it is the native control: the arrow keys, Home, End,
      Page Up and Page Down. A step with a key is saved by Enter or by
      leaving the cell, and given up by Escape.
    * It moves in steps of 1 over a whole number, and of a hundredth of the
      way from the minimum to the maximum over a decimal or a float.
    * It is named after the column for a screen reader, which reads the
      number from the slider itself; the number beside it is for the eye.
    * In a cell it is as high as a line of text, and the cell shows the
      focus, as for every editor. In the action panel it is a field of the
      form and shows the focus itself.

  It is drawn with daisyUI's `range`, in the text colour. The part of the
  track that is not filled is drawn at half that strength, as the edges of
  the table's own inputs are.
  """
  use AshDataTable.Component, commit: :change

  @impl true
  def verify(%{cell_type: :number, constraints: constraints}) do
    if is_nil(constraints[:min]) or is_nil(constraints[:max]),
      do: {:error, needs()},
      else: :ok
  end

  def verify(%{cell_type: cell_type}) do
    {:error,
     "a slider needs a number with a minimum and a maximum, and this field is shown as " <>
       "#{AshDataTable.Components.shown_as(cell_type)}."}
  end

  defp needs do
    "a slider needs a number with a minimum and a maximum. Declare both on the attribute: " <>
      "`constraints min: 0, max: 100`."
  end

  attr :value, :string, required: true, doc: "what the control holds, as text"
  attr :control, :map, required: true, doc: "the attributes the table needs on the control"
  attr :label, :string, required: true, doc: "the column's label"

  attr :column, AshDataTable.Component.Column,
    required: true,
    doc: "what the resource knows about the field"

  attr :place, :atom,
    required: true,
    values: [:grid, :panel],
    doc: "in a cell, or in the action panel"

  @impl true
  def editor(assigns) do
    %{type: type, constraints: constraints} = assigns.column

    assigns =
      assign(assigns,
        min: constraints[:min],
        max: constraints[:max],
        step: step(type, constraints[:min], constraints[:max])
      )

    ~H"""
    <span class="flex items-center gap-2">
      <input
        type="range"
        min={@min}
        max={@max}
        step={@step}
        value={@value}
        class={
          [
            "range",
            # The part of the track that is not filled, at half the strength
            # of the text: daisyUI's is too faint to show how far the slider
            # goes. Forced colours would take the fill away, which is a
            # shadow: there the slider keeps its own drawing, in the
            # system's colours.
            "[--range-bg:color-mix(in_oklab,currentColor_50%,transparent)]",
            "forced-color-adjust-none forced-colors:text-[CanvasText] forced-colors:[--range-thumb:Canvas]",
            # In a cell it stands in the place of the cell's text, and the
            # cell shows the focus. In the panel it is a field of a form and
            # shows the focus itself, in the text colour as a cell does, and
            # whenever it has it: the panel puts the focus on its first
            # field, also for a person who opened it with the pointer.
            if(@place == :grid,
              do: "range-xs w-24 focus-visible:outline-none",
              else: "range-sm focus:outline-2 focus:outline-offset-2 focus:outline-base-content"
            )
          ]
        }
        {@control}
      />
      <span data-value-text aria-hidden="true" class="text-sm tabular-nums">{@value}</span>
    </span>
    """
  end

  # Whole numbers move by one. Any other number moves by a hundredth of the
  # way from the minimum to the maximum.
  defp step(Ash.Type.Integer, _min, _max), do: 1

  defp step(_type, min, max) do
    [min, max] = Enum.map([min, max], &decimal/1)

    max
    |> Decimal.sub(min)
    |> Decimal.div(100)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp decimal(%Decimal{} = number), do: number
  defp decimal(number) when is_integer(number), do: Decimal.new(number)
  defp decimal(number) when is_float(number), do: Decimal.from_float(number)
end
