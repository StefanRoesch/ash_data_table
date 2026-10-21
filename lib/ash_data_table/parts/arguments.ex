defmodule AshDataTable.Parts.Arguments do
  @moduledoc false
  # The argument line: what the read action and the calculations are given.
  # The parts `argument_line` and `argument` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Kit
  alias AshDataTable.Parts

  # One input of the argument line: its label, the control of its type, and
  # under it what Ash says of a value it refuses. The controls are those of
  # a field of the action panel, at the size of the line's buttons, and
  # ordinary tab stops. Text is one line here: the line is no place for a
  # text of several.
  #
  # `named` is what the argument is called in the ids of the page, `name`
  # what its control is sent under, and `value` what it holds: text, or for
  # an array the list of its values; for one that is given value by value,
  # its rows. A typed value is sent when its control is left or Enter is
  # used, as a filter's is; a choice at once.
  #
  # Its projection (`AshDataTable.Kit.Projection`, an argument of the
  # heading's `argument_line`).
  attr :id, :string, required: true
  attr :named, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :editor, :atom, required: true
  attr :item, :atom, required: true
  attr :required?, :boolean, required: true
  attr :values, :list, required: true
  attr :value, :any, required: true
  attr :invalid?, :boolean, required: true
  # the limits of a number, and the counter of a text (nil for none), as
  # for a field of the action panel
  attr :limits, :map, required: true
  attr :counted, :map, required: true
  attr :element, :map, required: true
  attr :described, :string, required: true
  attr :error, :map, required: true
  attr :count, :map, required: true
  attr :group, :map, required: true
  attr :rows, :list, required: true
  attr :add, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true

  def argument(assigns) do
    ~H"""
    <div class="flex flex-col" {@element}>
      <div class="flex min-h-8 flex-wrap items-center gap-2">
        <%!-- an unchecked box sends nothing: this says "false" for it --%>
        <input :if={@editor == :boolean} type="hidden" name={@name} value="false" />
        <label :if={!@group} for={@id} class="label text-sm text-base-content">
          <input
            :if={@editor == :boolean}
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@value == "true"}
            aria-invalid={@invalid? && "true"}
            aria-describedby={@described}
            class={["checkbox checkbox-sm", Parts.Editors.box_edge()]}
          />
          <span data-label>{@label}</span>
          <span :if={@required? and @editor != :boolean} aria-hidden="true">*</span>
        </label>
        <select
          :if={@editor == :enum}
          id={@id}
          name={@name}
          aria-required={@required? && "true"}
          aria-invalid={@invalid? && "true"}
          aria-describedby={@described}
          class={["select select-sm w-auto", Parts.Editors.control_edge()]}
        >
          <option :if={not @required? or @value == ""} value=""></option>
          <option :for={choice <- @values} value={choice.value} selected={choice.value == @value}>
            {choice.label}
          </option>
        </select>
        <input
          :if={@editor in [:text, :number, :date, :datetime, :plain]}
          type={argument_type(@editor)}
          step={@limits.step || Parts.Editors.input_step(@editor)}
          min={@limits.min}
          max={@limits.max}
          id={@id}
          name={@name}
          value={@value}
          phx-debounce="blur"
          aria-required={@required? && "true"}
          aria-invalid={@invalid? && "true"}
          aria-describedby={@described}
          class={["input input-sm w-40", Parts.Editors.control_edge()]}
        />
        <Kit.part :if={@count} part={:count} kit={@kit} class={nil} {@count} />
        <%!-- An array has several controls, and its label is for none of them
        alone: they are a group, which the label names. --%>
        <span :if={@group} {@group.label} class="label text-sm text-base-content">
          <span data-label>{@label}</span>
        </span>
        <div
          :if={@group}
          id={@id}
          role="group"
          aria-labelledby={@group.labelledby}
          aria-describedby={@described}
          class="flex flex-wrap items-center gap-2"
        >
          <%!-- a form sends nothing for a list without values: this entry is
          sent before the values in every case --%>
          <input type="hidden" name={@name <> "[]"} value="" />
          <%!-- multiple choice: one box per value of the enum --%>
          <label
            :for={choice <- (@editor == :choices && @values) || []}
            class="label text-sm text-base-content"
          >
            <input
              type="checkbox"
              name={@name <> "[]"}
              value={choice.value}
              checked={choice.value in @value}
              aria-invalid={@invalid? && "true"}
              class={["checkbox checkbox-sm", Parts.Editors.box_edge()]}
            />
            {choice.label}
          </label>
          <%!-- value by value: a row each, with the button that takes it away,
          and after them the one that adds a row --%>
          <span :for={{row, at} <- Enum.with_index(@rows)} class="flex items-center gap-1">
            <input
              type={argument_type(@item)}
              step={@limits.step || Parts.Editors.input_step(@item)}
              min={@limits.min}
              max={@limits.max}
              id={row.id}
              name={@name <> "[]"}
              value={row.value}
              phx-debounce="blur"
              aria-label={Enum.at(@texts.value_position, at)}
              aria-invalid={@invalid? && "true"}
              aria-describedby={row.described}
              class={["input input-sm w-40", Parts.Editors.control_edge()]}
            />
            <Kit.part :if={row.count} part={:count} kit={@kit} class={nil} {row.count} />
            <button
              type="button"
              {row.remove}
              aria-label={Enum.at(@texts.remove_value, at)}
              class="btn btn-ghost btn-xs"
            >
              <span aria-hidden="true">✕</span>
            </button>
          </span>
          <button :if={@add} type="button" {@add} class="btn btn-sm">
            {@texts.add_value}
          </button>
        </div>
      </div>
      <%!-- in the text colour: the error colour is too faint for small text --%>
      <div :if={@error} {@error} class="mt-1 text-xs">
        <p :for={message <- @texts.errors} data-error>{message}</p>
      </div>
    </div>
    """
  end

  # the native input of an argument that is typed: text for what is written
  # as one line, whatever it is
  defp argument_type(editor) when editor in [:text, :plain], do: "text"
  defp argument_type(editor), do: Parts.Editors.input_type(editor)

  # Its projection (`AshDataTable.Kit.Projection`, the heading's
  # `argument_line`): the form and an `argument` each.
  attr :id, :any, required: true
  attr :kit, :atom, required: true
  attr :form, :map, required: true
  attr :nested?, :boolean, required: true
  attr :arguments, :list, required: true

  def argument_line(assigns) do
    ~H"""
    <%!-- The argument line: what the read action is given, and what the
    columns ask for of their calculations' arguments. A line of its own, which
    is there whenever the table has arguments, so that nothing moves when the
    line under it fills. A table without arguments has none.

    `novalidate` (in its bundle): an input of a number says the least and the
    most the argument takes (`limits`), and the browser is not to hold the
    form back over that. Ash is given what was typed and says what is wrong
    with it. Only what the browser cannot read as a value at all is held back,
    by the hook (`UNREADABLE`). --%>
    <form {@form} class={@kit.class(:argument_line, %{nested?: @nested?})}>
      <Kit.part :for={argument <- @arguments} part={:argument} kit={@kit} {argument} />
    </form>
    """
  end
end
