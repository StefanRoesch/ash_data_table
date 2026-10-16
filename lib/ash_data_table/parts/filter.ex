defmodule AshDataTable.Parts.Filter do
  @moduledoc false
  # The filter row's form and one column's filter control.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Parts
  alias AshDataTable.State
  alias AshDataTable.Text
  alias Phoenix.LiveView.JS

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
  # for several values a button that opens the list of the column's values,
  # a box for each (`choices/1`).
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
        aria-label={Text.t(:filter, column: @column.label)}
        class={["select select-xs w-auto", Parts.Editors.control_edge()]}
      >
        <option value="">{Text.t(:any)}</option>
        <option :for={choice <- @column.operators} value={choice} selected={choice == @operator}>
          {Text.t(choice)}
        </option>
      </select>
      <select
        :if={@column.cell_type != :boolean and match?([_, _ | _], @column.operators)}
        id={"#{@id}-operator"}
        name={"filter[#{@column.name}][o]"}
        form={@form}
        tabindex="-1"
        aria-label={Text.t(:filter_operator, column: @column.label)}
        class={["select select-xs w-auto", Parts.Editors.control_edge()]}
      >
        <option :for={choice <- @column.operators} value={choice} selected={choice == @operator}>
          {operator_text(choice)}
        </option>
      </select>
      <select
        :if={@column.cell_type == :enum and @takes == :one}
        id={"#{@id}-value"}
        name={"filter[#{@column.name}][v]"}
        form={@form}
        tabindex="-1"
        aria-label={Text.t(:filter, column: @column.label)}
        class={["select select-xs w-auto", Parts.Editors.control_edge()]}
      >
        <option value="">{Text.t(:any)}</option>
        <option
          :for={{choice, label} <- @column.values}
          value={choice}
          selected={to_string(choice) == @value}
        >
          {label}
        </option>
      </select>
      <.choices :if={@takes == :many} id={@id} form={@form} column={@column} chosen={@value} />
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
        aria-label={Text.t(:filter, column: @column.label)}
        aria-invalid={@rejected? && "true"}
        aria-describedby={@rejected? && "#{@id}-error"}
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
              {"from", "value", :range_from, :filter_from, elem(@value, 0)},
              {"to", "to", :range_to, :filter_to, elem(@value, 1)}
            ]
          }
          class="flex min-w-0 items-center justify-between gap-1"
        >
          <span aria-hidden="true" class="shrink-0 text-xs font-normal">{Text.t(word)}</span>
          <input
            type={Parts.Editors.input_type(@column.cell_type)}
            step={Parts.Editors.input_step(@column.cell_type)}
            id={"#{@id}-#{suffix}"}
            name={"filter[#{@column.name}][#{end_of}]"}
            form={@form}
            value={typed}
            phx-debounce="blur"
            tabindex="-1"
            aria-label={Text.t(name, column: @column.label)}
            aria-invalid={
              @rejected? && not is_nil(typed) && not State.value?(@column, typed) && "true"
            }
            aria-describedby={@rejected? && "#{@id}-error"}
            class={["input input-xs w-32", Parts.Editors.control_edge()]}
          />
        </div>
      </div>
      <button
        :if={@clears?}
        type="button"
        id={"#{@id}-clear"}
        tabindex="-1"
        aria-label={Text.t(:clear_filter, column: @column.label)}
        class="btn btn-ghost btn-xs"
        phx-click={Parts.Common.event(@table, "clear_filter")}
        phx-value-column={@column.name}
        phx-target={@target}
      >
        <span aria-hidden="true">✕</span>
      </button>
    </div>
    <%!-- in the text colour: the error colour is too faint for small text --%>
    <p :if={@rejected?} id={"#{@id}-error"} class="mt-1 text-xs">
      {Text.t(:invalid_filter)}
    </p>
    """
  end

  # The control of a filter for several of a column's values: a button that
  # says what is chosen, and the list it opens, a box for each value. Built
  # as "Columns" is (`columns/1`): a disclosure, not a menu, and the list a
  # popover, so that nothing around the table cuts it off.
  #
  # The values are the column's own, from its type. Nothing is read for
  # them, so the list says nothing of the records.
  #
  # The boxes belong to the form of the filter row, and are sent with it
  # whether the list is open or not. Ticking one changes no filter: the hook
  # keeps the change from the form, and submits the form when the list is
  # closed (`.Grid`, "several values of a filter"). Until then the button
  # says what applies.
  attr :id, :string, required: true
  attr :form, :string, required: true
  attr :column, :map, required: true
  attr :chosen, :list, required: true

  defp choices(assigns) do
    labels =
      for {value, label} <- assigns.column.values, to_string(value) in assigns.chosen, do: label

    says =
      case labels do
        [] -> Text.t(:any)
        [label] -> label
        labels -> Text.t(:values_chosen, count: length(labels))
      end

    assigns = assign(assigns, says: says, labels: labels)

    ~H"""
    <button
      type="button"
      id={"#{@id}-value"}
      tabindex="-1"
      aria-expanded="false"
      aria-controls={"#{@id}-values"}
      aria-label={"#{Text.t(:filter, column: @column.label)}: #{@says}"}
      title={@labels != [] && Enum.join(@labels, ", ")}
      phx-mounted={JS.ignore_attributes(["aria-expanded"])}
      data-choices-button
      class={[
        "select select-xs w-32 min-w-0 justify-start text-start",
        Parts.Editors.control_edge()
      ]}
    >
      <span class="truncate">{@says}</span>
    </button>
    <div
      id={"#{@id}-values"}
      role="group"
      aria-label={Text.t(:filter, column: @column.label)}
      popover="manual"
      phx-mounted={JS.ignore_attributes(["style"])}
      data-choices
      class="inset-auto m-0 max-h-[60vh] overflow-y-auto rounded border border-base-content/40 bg-base-100 p-2 text-sm font-normal text-base-content shadow"
    >
      <label
        :for={{value, label} <- @column.values}
        class="flex cursor-pointer items-center gap-2 px-1 py-0.5 whitespace-nowrap"
      >
        <input
          type="checkbox"
          id={"#{@id}-value-#{value}"}
          name={"filter[#{@column.name}][in][]"}
          value={value}
          form={@form}
          checked={to_string(value) in @chosen}
          tabindex="-1"
          class={["checkbox checkbox-xs", Parts.Editors.box_edge()]}
        />
        <span>{label}</span>
      </label>
    </div>
    """
  end

  defp operator_text(operator), do: Text.t(String.to_existing_atom("operator_#{operator}"))

  attr :id, :any, required: true
  attr :myself, :any, required: true

  def filter_form(assigns) do
    ~H"""
    <%!-- The form of the filter row. A form cannot sit inside a table around
    its cells, so the controls name it instead. --%>
    <form {Attrs.filters(@id, @myself)}></form>
    """
  end
end
