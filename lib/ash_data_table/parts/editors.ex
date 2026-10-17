defmodule AshDataTable.Parts.Editors do
  @moduledoc false
  # The built-in editors: the counter of a text and the editor of a list,
  # the parts `count` and `list` of `AshDataTable.Kit.Default`.
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Kit
  alias AshDataTable.Model.Limits

  # How long a text is and the most it can be, beside the control the text
  # is typed into: "12/30". Only for a text whose type says a `max_length`
  # (`AshDataTable.Model.Limits.counted/1`).
  #
  # The server counts what the control holds as it renders it, and the
  # grid's hook counts again whenever something is typed, and after every
  # patch: the same way, from what the counter says of itself (`data-count`:
  # the unit; `data-max`; `data-trim`; `data-casing`). Both count as Ash
  # does, so the counter and Ash's answer never disagree.
  #
  # It describes and stops nothing: a text that is too long is typed, sent
  # and refused by Ash. The counter then says a number greater than the
  # most ("34/30"), and is set in the weight and the colour of the text
  # around it instead of its own muted ones (`data-over`): the numbers say
  # it, and the weight says it again without a colour.
  #
  # The control names it as its description (`aria-describedby`), so a
  # screen reader reads it when the control gets the focus. It is no live
  # region: it is not read out at every key.
  #
  # It stands in the page as text, beside or under its control; in the
  # editor of a cell under the text, and the row grows to it while the
  # editor is open.
  attr :id, :string, required: true
  attr :counted, :map, required: true
  attr :value, :any, required: true
  attr :class, :string, required: true

  def count(assigns) do
    length = Limits.count(assigns.value, assigns.counted)

    assigns =
      assign(assigns,
        length: length,
        over?: length > assigns.counted.max,
        classes:
          Enum.join(
            [
              "shrink-0 text-xs whitespace-nowrap tabular-nums opacity-70 data-[over]:font-semibold data-[over]:opacity-100"
              | List.wrap(assigns.class)
            ],
            " "
          )
      )

    ~H"""
    <span
      id={@id}
      {Attrs.count(@counted, @over?)}
      class={@classes}
    >{@length}/{@counted.max}</span>
    """
  end

  # What a control names as its description: the ids of what says something
  # of it (its error message, its counter), or nothing.
  def described(ids) do
    case Enum.filter(ids, &is_binary/1) do
      [] -> false
      ids -> Enum.join(ids, " ")
    end
  end

  # The field of an array whose values each have a control of their own, in
  # the action panel: one row per value, with the control of the values'
  # cell type and a button that takes the value away, and after the rows a
  # button that adds a value.
  #
  # The server renders the rows the field starts with, and the panel's hook
  # those a person adds, from the row in the `<template>`; each row is sent
  # with the form, under `name`.
  #
  # What a control is called says its place ("Tags 2"), which changes as
  # values are added and taken away: the hook numbers them, from the two
  # texts given here with `{n}` where the number goes. `rest` are further
  # attributes of the list's element.
  attr :label, :string, required: true
  attr :item, :atom, required: true
  attr :limits, :map, required: true
  attr :counted, :any, required: true
  attr :values, :list, required: true
  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :rest, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true

  def list(assigns) do
    ~H"""
    <div
      id={@id}
      data-list
      {Attrs.list(@texts)}
      class="flex flex-col items-stretch gap-1"
      {@rest}
    >
      <template><.list_item
        kit={@kit}
        label={@label}
        item={@item}
        limits={@limits}
        counted={@counted}
        list={@id}
        name={@name}
        value=""
        position={nil}
        value_label={nil}
        remove_label={nil}
      /></template>
      <.list_item
        :for={{value, position} <- Enum.with_index(@values, 1)}
        kit={@kit}
        label={@label}
        item={@item}
        limits={@limits}
        counted={@counted}
        list={@id}
        name={@name}
        value={value}
        position={position}
        value_label={Enum.at(@texts.value_position, position - 1)}
        remove_label={Enum.at(@texts.remove_value, position - 1)}
      />
      <button
        type="button"
        data-add
        class="btn btn-sm self-start"
      >
        {@texts.add_value}
      </button>
    </div>
    """
  end

  # One value of such an array. A box sends nothing while it is not checked,
  # so in the panel what it holds is sent by an input beside it, which the
  # hook keeps at the box's state.
  defp list_item(assigns) do
    assigns =
      assign(assigns,
        # The counter of a value that is text with a most it can be long.
        # Its id says the row's place, as what the row's controls are
        # called does, and the hook numbers it with them.
        count_id:
          assigns.counted && assigns.position && assigns.list &&
            "#{assigns.list}-count-#{assigns.position}"
      )

    ~H"""
    <div data-item class="flex items-center gap-1">
      <input
        :if={@item == :boolean and @name}
        type="hidden"
        name={@name}
        value={to_string(@value == "true")}
      />
      <input
        :if={@item == :boolean}
        type="checkbox"
        checked={@value == "true"}
        aria-label={@value_label}
        class={["checkbox checkbox-sm", box_edge()]}
      />
      <textarea
        :if={@item == :text}
        rows="1"
        name={@name}
        aria-label={@value_label}
        aria-describedby={@count_id}
        class={["textarea min-h-0 flex-1", control_edge()]}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <Kit.part
        :if={@item == :text && @counted}
        part={:count}
        kit={@kit}
        id={@count_id}
        counted={@counted}
        value={@value}
        class={nil}
      />
      <input
        :if={@item in [:number, :date, :datetime]}
        type={input_type(@item)}
        step={@limits.step || input_step(@item)}
        min={@limits.min}
        max={@limits.max}
        name={@name}
        value={@value}
        aria-label={@value_label}
        class={["input flex-1", control_edge()]}
      />
      <button
        type="button"
        data-remove
        aria-label={@remove_label}
        class="btn btn-ghost btn-xs"
      >
        <span aria-hidden="true">✕</span>
      </button>
    </div>
    """
  end

  # The edge of an input or a menu of the table's own, through the variable
  # daisyUI draws it with. At rest daisyUI's edge is too faint to show where
  # an empty input is: here it is the text colour at half strength. With
  # focus it is daisyUI's, which is the text colour. On a control that is
  # `aria-invalid` it is the colour of a failed cell's ring, with focus too;
  # the message under the control is what says so without a colour.
  def control_edge do
    "not-focus:not-aria-invalid:[--input-color:color-mix(in_oklab,var(--color-base-content)_50%,transparent)] aria-invalid:[--input-color:color-mix(in_oklab,var(--color-error)_70%,var(--color-base-content))]"
  end

  # The same for a checkbox, whose variable would also fill it when checked.
  def box_edge do
    "border-base-content/50 aria-invalid:border-[color-mix(in_oklab,var(--color-error)_70%,var(--color-base-content))]"
  end

  # The native input of each cell type that is filtered by a typed value.
  def input_type(:text), do: "text"
  def input_type(:number), do: "number"
  def input_type(:date), do: "date"
  def input_type(:datetime), do: "datetime-local"

  # Any number, not only whole ones; and a datetime to the second, as it is shown.
  def input_step(:number), do: "any"
  def input_step(:datetime), do: "1"
  def input_step(_cell_type), do: nil
end
