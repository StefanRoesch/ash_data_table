defmodule AshDataTable.Parts.Filter do
  @moduledoc false
  # The filter row's form and one column's filter control.
  # It draws from the assigns of the table's component.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Parts
  alias AshDataTable.State

  # What a column's filter shows: what was typed and rejected; else what
  # the row was last sent, an operator without its value among it, while the
  # table is filtered by what it was sent among (the filters before it, and
  # after: a change of the filters goes through the URL, and is not in the
  # state at once); else the filter that applies.
  def shown_filter(rejected, pending, state, name) do
    rejected[name] || (state.filters in pending.among && pending.controls[name]) ||
      state.filters[name]
  end

  # The controls of one column's filter, showing the filter that applies.
  # They are out of the tab order: the grid is one tab stop, and the hook
  # moves focus into a filter cell.
  #
  # What the value is given with follows from the operator, as the column
  # says (`takes`): one control for one value; for a range two inputs,
  # one above the other, so that the column needs no more room than for one;
  # for several values a button that opens the side panel with a box for
  # each of the column's values (`choices/1`).
  def filter(assigns) do
    {operator, value} = assigns.filter || {nil, nil}
    takes = if(operator, do: Map.fetch!(assigns.column.takes, operator), else: :one)

    assigns =
      assign(assigns,
        operator: operator,
        value: value,
        takes: takes,
        clears?: assigns.applied? and not assigns.rejected?
      )

    ~H"""
    <div class="flex items-center gap-1">
      <select
        :if={@column.cell_type == :boolean}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][o]"}
        form={@form}
        tabindex="-1"
        aria-label={@texts.filter}
        class={["select select-xs w-auto", Parts.Editors.control_edge()]}
      >
        <option value="">{@texts.any}</option>
        <option
          :for={{choice, said} <- Enum.zip(@column.operators, @texts.operators)}
          value={choice}
          selected={choice == @operator}
        >
          {said}
        </option>
      </select>
      <select
        :if={@column.cell_type != :boolean and match?([_, _ | _], @column.operators)}
        id={"#{@id}-operator"}
        name={"filter[#{@column.name}][o]"}
        form={@form}
        tabindex="-1"
        aria-label={@texts.filter_operator}
        class={["select select-xs w-auto", Parts.Editors.control_edge()]}
      >
        <option
          :for={{choice, said} <- Enum.zip(@column.operators, @texts.operators)}
          value={choice}
          selected={choice == @operator}
        >
          {said}
        </option>
      </select>
      <select
        :if={@column.cell_type == :enum and @takes == :one}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][v]"}
        form={@form}
        tabindex="-1"
        aria-label={@texts.filter}
        class={["select select-xs w-auto", Parts.Editors.control_edge()]}
      >
        <option value="">{@texts.any}</option>
        <option
          :for={{choice, label} <- @column.values}
          value={choice}
          selected={to_string(choice) == @value}
        >
          {label}
        </option>
      </select>
      <.choices
        :if={@takes == :many}
        id={@id}
        form={@form}
        table={@table}
        column={@column}
        operator={@operator}
        chosen={@value || []}
        target={@target}
        texts={@texts}
      />
      <%!-- an operator such as "is empty" is complete without a value --%>
      <input
        :if={@column.cell_type not in [:boolean, :enum] and @takes == :one}
        type={Parts.Editors.input_type(@column.cell_type)}
        step={Parts.Editors.input_step(@column.cell_type)}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][v]"}
        form={@form}
        value={@value}
        phx-debounce="blur"
        tabindex="-1"
        aria-label={@texts.filter}
        aria-invalid={@rejected? && "true"}
        aria-describedby={@rejected? && Ids.error(@id)}
        class={["input input-xs w-32", Parts.Editors.control_edge()]}
      />
      <%!-- The two ends of a range, one above the other, each with the word
      that says which it is. They are applied as one input is: on Enter and
      when one is left. Rows that shrink, as an input beside a menu does once
      a person has made the column narrower. --%>
      <div :if={@takes == :range} class="flex min-w-0 flex-col gap-0.5">
        <div
          :for={
            {end_of, suffix, word, name, typed} <- [
              {"from", "value", @texts.range_from, @texts.filter_from, elem(@value, 0)},
              {"to", "to", @texts.range_to, @texts.filter_to, elem(@value, 1)}
            ]
          }
          class="flex min-w-0 items-center justify-between gap-1"
        >
          <span aria-hidden="true" class="shrink-0 text-xs font-normal">{word}</span>
          <input
            type={Parts.Editors.input_type(@column.cell_type)}
            step={Parts.Editors.input_step(@column.cell_type)}
            id={"#{@id}-#{suffix}"}
            name={"filter[#{@column.name}][#{end_of}]"}
            form={@form}
            value={typed}
            phx-debounce="blur"
            tabindex="-1"
            aria-label={name}
            aria-invalid={
              @rejected? && not is_nil(typed) && not State.value?(@column, typed) && "true"
            }
            aria-describedby={@rejected? && Ids.error(@id)}
            class={["input input-xs w-32", Parts.Editors.control_edge()]}
          />
        </div>
      </div>
      <button
        :if={@clears?}
        type="button"
        id={"#{@id}-clear"}
        tabindex="-1"
        aria-label={@texts.clear_filter}
        class="btn btn-ghost btn-xs"
        phx-click={Attrs.event(@table, "clear_filter")}
        phx-value-column={@column.name}
        phx-target={@target}
      >
        <span aria-hidden="true">✕</span>
      </button>
    </div>
    <%!-- in the text colour: the error colour is too faint for small text --%>
    <p :if={@rejected?} id={Ids.error(@id)} class="mt-1 text-xs">
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
  attr :id, :string, required: true
  attr :form, :string, required: true
  attr :table, :string, required: true
  attr :column, :map, required: true
  attr :operator, :atom, required: true
  attr :chosen, :list, required: true
  attr :target, :any, required: true
  attr :texts, :map, required: true

  defp choices(assigns) do
    labels =
      for {value, label} <- assigns.column.values, to_string(value) in assigns.chosen, do: label

    assigns = assign(assigns, says: assigns.texts.chosen, labels: labels)

    ~H"""
    <button
      type="button"
      id={"#{@id}-value"}
      tabindex="-1"
      aria-haspopup="dialog"
      aria-label={"#{@texts.filter}: #{@says}"}
      title={@labels != [] && Enum.join(@labels, ", ")}
      {Attrs.filter_values(@table, @column, @operator, @target)}
      class={[
        "select select-xs w-32 min-w-0 justify-start text-start",
        Parts.Editors.control_edge()
      ]}
    >
      <span class="truncate">{@says}</span>
    </button>
    <input
      :for={value <- @chosen}
      type="hidden"
      name={"filter[#{@column.name}][in][]"}
      value={value}
      form={@form}
    />
    """
  end
end
