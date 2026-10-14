defmodule AshDataTable.Parts.Arguments do
  @moduledoc false
  # The argument line: what the read action and the calculations are given.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  alias AshDataTable.Model
  alias AshDataTable.Model.Limits
  alias AshDataTable.Parts
  alias AshDataTable.Text

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
  attr :id, :string, required: true
  attr :named, :string, required: true
  attr :name, :string, required: true
  attr :argument, :map, required: true
  attr :value, :any, required: true
  attr :errors, :list, required: true
  attr :target, :any, required: true

  defp argument(assigns) do
    assigns =
      assign(assigns,
        described: assigns.errors != [] && "#{assigns.id}-error",
        array?: assigns.argument.editor in [:choices, :list],
        # as for a field of the action panel
        limits: Limits.of(assigns.argument)
      )

    # the counter of a text that has a most it can be long, as in the panel
    counted =
      case assigns.argument do
        %{editor: :text} = argument -> Limits.counted(argument)
        %{editor: :list, cell_type: {:array, :text}} = argument -> Limits.counted(argument)
        _another_control -> nil
      end

    assigns =
      assign(assigns,
        counted: counted,
        described:
          Parts.Editors.described([
            assigns.described,
            counted && assigns.argument.editor == :text && "#{assigns.id}-count"
          ])
      )

    ~H"""
    <div class="flex flex-col" data-argument={@named}>
      <div class="flex min-h-8 flex-wrap items-center gap-2">
        <%!-- an unchecked box sends nothing: this says "false" for it --%>
        <input :if={@argument.editor == :boolean} type="hidden" name={@name} value="false" />
        <label :if={not @array?} for={@id} class="label text-sm text-base-content">
          <input
            :if={@argument.editor == :boolean}
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@value == "true"}
            aria-invalid={@errors != [] && "true"}
            aria-describedby={@described}
            class={["checkbox checkbox-sm", Parts.Editors.box_edge()]}
          />
          <span data-label>{@argument.label}</span>
          <span :if={@argument.required? and @argument.editor != :boolean} aria-hidden="true">*</span>
        </label>
        <select
          :if={@argument.editor == :enum}
          id={@id}
          name={@name}
          aria-required={@argument.required? && "true"}
          aria-invalid={@errors != [] && "true"}
          aria-describedby={@described}
          class={["select select-sm w-auto", Parts.Editors.control_edge()]}
        >
          <option :if={not @argument.required? or @value == ""} value=""></option>
          <option
            :for={{choice, label} <- @argument.values}
            value={choice}
            selected={to_string(choice) == @value}
          >
            {label}
          </option>
        </select>
        <input
          :if={@argument.editor in [:text, :number, :date, :datetime, :plain]}
          type={argument_type(@argument.editor)}
          step={@limits.step || Parts.Editors.input_step(@argument.editor)}
          min={@limits.min}
          max={@limits.max}
          id={@id}
          name={@name}
          value={@value}
          phx-debounce="blur"
          aria-required={@argument.required? && "true"}
          aria-invalid={@errors != [] && "true"}
          aria-describedby={@described}
          class={["input input-sm w-40", Parts.Editors.control_edge()]}
        />
        <Parts.Editors.count
          :if={@counted && @argument.editor == :text}
          id={"#{@id}-count"}
          counted={@counted}
          value={@value}
        />
        <%!-- An array has several controls, and its label is for none of them
        alone: they are a group, which the label names. --%>
        <span :if={@array?} id={"#{@id}-label"} class="label text-sm text-base-content">
          <span data-label>{@argument.label}</span>
        </span>
        <div
          :if={@array?}
          id={@id}
          role="group"
          aria-labelledby={"#{@id}-label"}
          aria-describedby={@described}
          class="flex flex-wrap items-center gap-2"
        >
          <%!-- a form sends nothing for a list without values: this entry is
          sent before the values in every case --%>
          <input type="hidden" name={@name <> "[]"} value="" />
          <%!-- multiple choice: one box per value of the enum --%>
          <label
            :for={{choice, label} <- (@argument.editor == :choices && @argument.values) || []}
            class="label text-sm text-base-content"
          >
            <input
              type="checkbox"
              name={@name <> "[]"}
              value={choice}
              checked={to_string(choice) in @value}
              aria-invalid={@errors != [] && "true"}
              class={["checkbox checkbox-sm", Parts.Editors.box_edge()]}
            />
            {label}
          </label>
          <%!-- value by value: a row each, with the button that takes it away,
          and after them the one that adds a row --%>
          <span
            :for={{value, at} <- (@argument.editor == :list && Enum.with_index(@value)) || []}
            class="flex items-center gap-1"
          >
            <input
              type={argument_type(elem(@argument.cell_type, 1))}
              step={@limits.step || Parts.Editors.input_step(elem(@argument.cell_type, 1))}
              min={@limits.min}
              max={@limits.max}
              id={"#{@id}-#{at}"}
              name={@name <> "[]"}
              value={value}
              phx-debounce="blur"
              aria-label={Text.t(:value_position, column: @argument.label, position: at + 1)}
              aria-invalid={@errors != [] && "true"}
              aria-describedby={@counted && "#{@id}-#{at}-count"}
              class={["input input-sm w-40", Parts.Editors.control_edge()]}
            />
            <Parts.Editors.count
              :if={@counted}
              id={"#{@id}-#{at}-count"}
              counted={@counted}
              value={value}
            />
            <button
              type="button"
              id={"#{@id}-#{at}-remove"}
              aria-label={Text.t(:remove_value, column: @argument.label, position: at + 1)}
              class="btn btn-ghost btn-xs"
              phx-click="argument_remove"
              phx-value-argument={@named}
              phx-value-at={at}
              phx-target={@target}
            >
              <span aria-hidden="true">✕</span>
            </button>
          </span>
          <button
            :if={@argument.editor == :list}
            type="button"
            id={"#{@id}-add"}
            class="btn btn-sm"
            phx-click="argument_add"
            phx-value-argument={@named}
            phx-target={@target}
          >
            {Text.t(:add_value)}
          </button>
        </div>
      </div>
      <%!-- in the text colour: the error colour is too faint for small text --%>
      <div :if={@errors != []} id={"#{@id}-error"} class="mt-1 text-xs">
        <p :for={message <- @errors} data-error>{message}</p>
      </div>
    </div>
    """
  end

  # the native input of an argument that is typed: text for what is written
  # as one line, whatever it is
  defp argument_type(editor) when editor in [:text, :plain], do: "text"
  defp argument_type(editor), do: Parts.Editors.input_type(editor)

  # Part of the component's `render/1` until stage 1 of the refactor. Its
  # markup keeps the indentation it had there, held by `phx-no-format`, so
  # that the text in it, and with it the page, is the same byte for byte.
  attr :id, :any, required: true
  attr :lines, :any, required: true
  attr :model, :any, required: true
  attr :myself, :any, required: true
  attr :nested?, :any, required: true
  attr :refused, :any, required: true
  attr :state, :any, required: true

  def argument_line(assigns) do
    ~H"""
    <%!-- The argument line: what the read action is given, and what the
    columns ask for of their calculations' arguments. A line of its own, which
    is there whenever the table has arguments, so that nothing moves when the
    line under it fills. A table without arguments has none.

    `novalidate`: an input of a number says the least and the most the
    argument takes (`AshDataTable.Model.Limits`), and the browser is not to hold
    the form back over that. Ash is given what was typed and says what is
    wrong with it. Only what the browser cannot read as a value at all is
    held back, by the hook (`UNREADABLE`). --%>
    <form
      :if={@model.arguments != []}
      phx-no-format
      id={"#{@id}-arguments"}
      phx-change="arguments"
      phx-submit="arguments"
      phx-target={@myself}
      novalidate
      data-arguments
      class={[
        "flex flex-wrap items-start gap-x-4 gap-y-2",
        if(@nested?, do: "px-4 py-2", else: "mb-2")
      ]}
    >
        <.argument
          :for={argument <- @model.arguments}
          id={"#{@id}-arg-#{argument_id(argument)}"}
          named={argument_id(argument)}
          name={argument_name(argument)}
          argument={argument}
          value={Map.get(@lines, Model.Argument.key(argument)) || shown(argument, @state, @refused)}
          errors={
            case @refused[Model.Argument.key(argument)] do
              nil -> []
              %{messages: messages} -> messages
            end
          }
          target={@myself}
        />
      </form>
    """
  end

  # What an argument is called in the ids of the page, and what its control
  # is sent under.
  def argument_id(%{column: nil, name: name}), do: Atom.to_string(name)
  def argument_id(%{column: column, name: name}), do: "#{column}-#{name}"

  defp argument_name(%{column: nil, name: name}), do: "arguments[a][#{name}]"
  defp argument_name(%{column: column, name: name}), do: "arguments[c][#{column}][#{name}]"

  # What an argument's input shows: what was typed and refused, else what
  # the person chose, else what it holds with nothing chosen.
  def shown(argument, state, refused) do
    key = Model.Argument.key(argument)

    case refused do
      %{^key => %{typed: typed}} -> typed
      _not_refused -> Map.get(state.arguments, key, Model.Argument.rest(argument))
    end
  end
end
