defmodule AshDataTable.Parts.Filter do
  @moduledoc false
  # One column's filter control, in the filter row: the part `filter` of
  # `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Parts

  # The controls of one column's filter, showing the filter that applies.
  # Each is a Tab stop of its own.
  #
  # What the value is given with follows from the operator, as the column
  # says (`takes`): one control for one value; for a range two inputs,
  # one above the other, so that the column needs no more room than for one;
  # for several values a button that opens the side panel with a box for
  # each of the column's values. Its projection (`AshDataTable.Kit.Projection`,
  # a filter cell's `filter`): each control's bundle, nil where the filter
  # has none of it.
  attr :cell_type, :any, required: true
  attr :takes, :atom, required: true
  attr :yes_no, :map, required: true
  attr :operators, :map, required: true
  attr :choice, :map, required: true
  attr :input, :map, required: true
  attr :range, :list, required: true
  attr :several, :map, required: true
  attr :clear, :map, required: true
  attr :error, :map, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true
  attr :kit, :atom, required: true

  def filter(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <select
        :if={@yes_no}
        {@yes_no.select}
        class={["select select-xs w-auto", Parts.Editors.control_edge()]}
      >
        <option value="">{@texts.any}</option>
        <option
          :for={option <- @yes_no.options}
          value={option.value}
          selected={option.chosen?}
        >
          {option.label}
        </option>
      </select>
      <select
        :if={@operators}
        {@operators.select}
        class={["select select-xs w-auto", Parts.Editors.control_edge()]}
      >
        <option
          :for={option <- @operators.options}
          value={option.value}
          selected={option.chosen?}
        >
          {option.label}
        </option>
      </select>
      <select
        :if={@choice}
        {@choice.select}
        class={["select select-xs w-auto", Parts.Editors.control_edge()]}
      >
        <option value="">{@texts.any}</option>
        <option
          :for={option <- @choice.options}
          value={option.value}
          selected={option.chosen?}
        >
          {option.label}
        </option>
      </select>
      <.several :if={@several} several={@several} />
      <%!-- an operator such as "is empty" is complete without a value --%>
      <input
        :if={@input}
        type={Parts.Editors.input_type(@cell_type)}
        step={Parts.Editors.input_step(@cell_type)}
        {@input}
        phx-debounce="blur"
        class={["input input-xs w-32", Parts.Editors.control_edge()]}
      />
      <%!-- The two ends of a range, one above the other, each with the word
      that says which it is. They are applied as one input is: on Enter and
      when one is left. Rows that shrink, as an input beside a menu does once
      a person has made the column narrower. --%>
      <div :if={@range} class="flex min-w-0 flex-col gap-0.5">
        <div
          :for={end_of <- @range}
          class="flex min-w-0 items-center justify-between gap-1"
        >
          <span aria-hidden="true" class="shrink-0 text-xs font-normal">{end_of.word}</span>
          <input
            type={Parts.Editors.input_type(@cell_type)}
            step={Parts.Editors.input_step(@cell_type)}
            {end_of.input}
            phx-debounce="blur"
            class={["input input-xs w-32", Parts.Editors.control_edge()]}
          />
        </div>
      </div>
      <button
        :if={@clear}
        type="button"
        {@clear}
        class="btn btn-ghost btn-xs"
      >
        <span aria-hidden="true">✕</span>
      </button>
    </div>
    <%!-- in the text colour: the error colour is too faint for small text --%>
    <p :if={@error} {@error} class="mt-1 text-xs">
      {@texts.invalid_filter}
    </p>
    """
  end

  # The control of a filter for several of a column's values: a button that
  # says what is chosen and opens the table's side panel, with a box per
  # value, as a form of its own (`filter_values`): a choice of several
  # values is made where every value of several is edited. Nothing is
  # filtered until the panel is sent.
  #
  # The values are the column's own, from its type. Nothing is read for
  # them, so the panel says nothing of the records.
  #
  # The values that apply belong to the filter row's form, as inputs that
  # are not shown, so that a change of another filter sends them with it.
  attr :several, :map, required: true

  defp several(assigns) do
    ~H"""
    <button
      type="button"
      {@several.button}
      class={[
        "select select-xs w-32 min-w-0 justify-start text-start",
        Parts.Editors.control_edge()
      ]}
    >
      <span class="truncate">{@several.says}</span>
    </button>
    <input
      :for={value <- @several.hidden}
      type="hidden"
      {value}
    />
    """
  end
end
