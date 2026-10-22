defmodule AshDataTable.Parts.Panel do
  @moduledoc false
  # The action panel and its fields: groups, unions and chosen records.
  # The parts `panel`, `field` and `control` of `AshDataTable.Kit.Default`;
  # what a part draws inside it, it draws through the kit
  # (`Parts.Common.part/1`).
  use Phoenix.Component

  alias AshDataTable.Kit
  alias AshDataTable.Parts

  # The action panel: where a person gives the inputs of a row action, or of
  # the create action, before it runs. A modal dialog at the right edge of
  # the window, which its hook opens when it is put into the page and which
  # goes when the server takes it out again. Its form is the form of an
  # `AshPhoenix.Form` of the action, which the table keeps while the panel
  # is open: what is typed is given to the action as it is typed, and the
  # action's errors are shown at their fields. Its projection
  # (`AshDataTable.Kit.Projection`, `panel`): nothing is drawn while it is
  # closed (`open?`). `uploads` are LiveView's uploads of its file fields,
  # by name, which it hands to its fields.
  attr :id, :string, required: true
  attr :open?, :boolean, required: true
  # `:modal`, a dialog over the page, or `:inline`, a part of it
  attr :presentation, :atom, required: true
  attr :destructive?, :boolean, required: true
  attr :place, :map, required: true
  attr :frame, :map, required: true
  attr :form, :map, required: true
  attr :title, :map, required: true
  attr :errors, :map, required: true
  attr :cancel, :map, required: true
  attr :submit, :map, required: true
  attr :fields, :list, required: true
  attr :uploads, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true

  def panel(%{open?: false} = assigns), do: ~H""

  def panel(assigns) do
    ~H"""
    <%!-- `open` is the hook's: a patch leaves it alone. Not daisyUI's `modal`,
    for the reason given at the other dialog. --%>
    <.dynamic_tag
      tag_name={if @presentation == :modal, do: "dialog", else: "section"}
      {@frame}
      class={@kit.class(:panel, %{destructive?: @destructive?, presentation: @presentation})}
    >
      <%!-- `novalidate` (in its bundle), for the reason given at the argument
      line: the limits on a field describe, and the action judges. --%>
      <form {@form}>
        <h2 {@title} class="mb-4 text-lg font-semibold">{@texts.title}</h2>
        <%!-- what the action says that is about none of the fields --%>
        <div :if={@errors} {@errors} class="mb-4 text-sm font-medium">
          <p :for={message <- @texts.errors}>{message}</p>
        </div>
        <Kit.part :for={field <- @fields} part={:field} kit={@kit} uploads={@uploads} {field} />
        <div class="mt-6 flex justify-end gap-2">
          <button type="button" {@cancel} class="btn">
            {@texts.cancel}
          </button>
          <button
            type="submit"
            {@submit}
            class={["btn", if(@destructive?, do: "btn-error", else: "btn-primary")]}
          >
            {@texts.submit}
          </button>
        </div>
      </form>
      <%!-- what opens inside it is moved in here (`Phoenix.Component.portal/1`) --%>
      <div {@place} class="contents"></div>
    </.dynamic_tag>
    """
  end

  # One field of the action panel: its label, the control of its type, and
  # the action's errors about it. The controls are those of the cell
  # editors, at the size of a form's.
  #
  # `name` is what the field is sent under and `value` what it holds, as its
  # control holds it. A field inside a group is one of these too. Its
  # `element` says what the field is (`data-field`): its name, and for a
  # field inside a group the names on the way to it, with a dot between.
  # What a value made of fields holds is in it (`group`, `groups`, `union`),
  # with the bundles of its buttons and its hidden entries. Its projection
  # (`AshDataTable.Kit.Projection`, a field of `panel`); `uploads` LiveView's
  # uploads of the panel's file fields, by name.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :element, :map, required: true
  attr :editor, :atom, required: true
  attr :label, :string, required: true
  attr :required?, :boolean, required: true
  attr :secret?, :boolean, required: true
  attr :item, :atom, required: true
  attr :values, :list, required: true
  attr :value, :any, required: true
  attr :boxless, :list, required: true
  attr :invalid?, :boolean, required: true
  attr :places, :string, required: true
  attr :limits, :map, required: true
  attr :counted, :map, required: true
  attr :described, :string, required: true
  attr :labelled?, :boolean, required: true
  attr :group_label, :map, required: true
  attr :labelledby, :string, required: true
  attr :error, :map, required: true
  attr :reference, :map, required: true
  attr :references, :map, required: true
  attr :list, :map, required: true
  attr :file, :map, required: true
  attr :component, :map, required: true
  attr :control, :map, required: true
  attr :clear, :map, required: true
  attr :count, :map, required: true
  attr :group, :map, required: true
  attr :groups, :map, required: true
  attr :union, :map, required: true
  attr :uploads, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :messages, :map, required: true
  attr :locale, :string, required: true

  def field(assigns) do
    ~H"""
    <div class="fieldset mb-2" {@element}>
      <%!-- an unchecked box sends nothing: this says "false" for it --%>
      <input :if={@editor == :boolean} type="hidden" name={@name} value="false" />
      <label :if={@labelled?} for={@id} class="label mb-1 text-base-content">
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
      <%!-- An array has several controls, and its label is for none of them
      alone: they are a group, which the label names. It has no mark of a
      required field: the field always gives a list, with or without values,
      and how many it has to have is the action's to say. --%>
      <span
        :if={@group_label && @editor != :reference}
        {@group_label}
        class="label mb-1 text-base-content"
      >
        <span data-label>{@label}</span>
      </span>
      <%!-- The key of a related record is not typed: the field says what the
      record is called, as plain text, and its button opens the picker. The
      two are a group, which the label names; the key itself is sent by an
      input that is not shown. (Not of the type `hidden`, for the reason given
      at the field of an array.) A group cannot say that it is required, so
      the label says it. --%>
      <span :if={@reference} {@group_label} class="label mb-1 text-base-content">
        <span data-label>{@label}</span>
        <span :if={@required?} aria-hidden="true">*</span>
        <span :if={@required?} class="sr-only">{@texts.required}</span>
      </span>
      <div
        :if={@reference}
        id={@id}
        role="group"
        aria-labelledby={@labelledby}
        aria-describedby={@described}
        class="flex items-center gap-2"
      >
        <input type="text" name={@name} value={@value} hidden data-key />
        <span :if={@reference.chosen} {@reference.chosen.element} class="text-sm" data-chosen>{@reference.chosen.text}</span>
        <button type="button" class="btn btn-sm" {@reference.choose}>
          {@texts.choose}
        </button>
      </div>
      <%!-- The keys of several related records are not typed either: the
      field lists what the chosen records are called, as plain text, each
      with a button that takes it out again, and its button opens the picker,
      in which any number of rows is selected. All of it is the server's to
      render: the panel keeps which records the field holds. Each key is
      sent by an input that is not shown, after an entry of the field's own,
      as the values of an array are. A record this person may not read is
      held all the same, and called "Not available". --%>
      <div
        :if={@references}
        id={@id}
        role="group"
        aria-labelledby={@labelledby}
        aria-describedby={@described}
        data-references
        class="flex flex-col gap-1"
      >
        <input type="text" name={@name <> "[]"} value="" hidden data-own />
        <div
          :for={entry <- @references.entries}
          class="flex items-center gap-1"
          data-chosen-item
        >
          <input type="text" name={@name <> "[]"} value={entry.key} hidden data-key />
          <span {entry.element} class="text-sm" data-chosen>
            {entry.text}
          </span>
          <button type="button" {entry.unpick} class="btn btn-ghost btn-xs">
            <span aria-hidden="true">✕</span>
          </button>
        </div>
        <button type="button" class="btn btn-sm self-start" {@references.choose}>
          {@texts.choose}
        </button>
      </div>
      <div
        :if={@editor in [:choices, :list]}
        id={@id}
        role="group"
        aria-labelledby={@labelledby}
        aria-describedby={@described}
        data-invalid={@places}
        class="flex flex-col gap-1"
      >
        <%!-- A form sends nothing for a list without values. This entry is
        sent before the values in every case, and is left out where they are
        taken (`AshDataTable.Act`). It is not of the type `hidden`: LiveView then
        says of the field whether a person has used it, as of any other. --%>
        <input type="text" name={@name <> "[]"} value="" hidden data-own />
        <%!-- multiple choice: one box per value of the enum --%>
        <label
          :for={choice <- (@editor == :choices && @values) || []}
          class="label text-base-content"
        >
          <input
            type="checkbox"
            name={@name <> "[]"}
            value={choice.value}
            checked={choice.chosen?}
            aria-invalid={@invalid? && "true"}
            class={["checkbox checkbox-sm", Parts.Editors.box_edge()]}
          />
          {choice.label}
        </label>
        <%!-- What the field holds that is none of the enum's values, and so
        has no box: sent with the ticked ones, after them, so that the
        action is given back what a person could not see or change. --%>
        <input
          :for={value <- @boxless}
          type="hidden"
          name={@name <> "[]"}
          value={value}
        />
        <%!-- The rows are the hook's from here on: a patch leaves them alone,
        so that a value a person has added is not taken away by the answer
        to an earlier change. Which of them the action refuses is said on the
        group around them (`data-invalid`: their places, counted from 0, as
        JSON), and the hook marks their controls. --%>
        <Kit.part :if={@list} part={:list} kit={@kit} {@list} />
      </div>

      <%!-- a value made of fields, and an array of them --%>
      <.group
        :if={@group}
        id={@id}
        label={@label}
        labelledby={@labelledby}
        required?={@required?}
        error={@error}
        group={@group}
        uploads={@uploads}
        kit={@kit}
        texts={@texts}
      />
      <.groups
        :if={@groups}
        id={@id}
        label={@label}
        labelledby={@labelledby}
        error={@error}
        groups={@groups}
        uploads={@uploads}
        kit={@kit}
        texts={@texts}
      />
      <%!-- a union: the choice of its kind, and under it that kind's value --%>
      <.union
        :if={@union}
        id={@id}
        label={@label}
        labelledby={@labelledby}
        required?={@required?}
        error={@error}
        union={@union}
        uploads={@uploads}
        kit={@kit}
        texts={@texts}
      />
      <%!-- An argument that takes a file: LiveView's own file input, which
      shows the name of the file that was chosen, as a browser does. Its id
      is LiveView's to say, so the label is pointed at that. The file is sent
      when the panel's button is used, and a bar says how far it has come
      while that takes time. --%>
      <label :if={@file} {@file.label} class="label mb-1 text-base-content">
        <span data-label>{@label}</span>
        <span :if={@required?} aria-hidden="true">*</span>
      </label>
      <.live_file_input
        :if={@file}
        upload={@uploads[@file.name]}
        aria-required={@required? && "true"}
        aria-invalid={@invalid? && "true"}
        aria-describedby={@described}
        class={["file-input w-full", Parts.Editors.control_edge()]}
      />
      <progress
        :for={entry <- (@file && @file.entries) || []}
        :if={entry.sending?}
        value={entry.progress}
        max="100"
        aria-label={entry.name}
        class="progress mt-1 w-full"
      >
        {entry.progress}%
      </progress>
      <%!-- an attribute whose column has a component that edits: its editor --%>
      {if @component, do: field_editor(assigns)}
      <%!-- A sensitive input, which is text or a number: typed hidden. It
      starts empty whatever the record holds, and left empty it gives the
      action nothing (`AshDataTable.Act`). What it holds here is what was typed
      into it, which a patch has to bring back as it does for any field. --%>
      <Kit.part :if={@control} part={:control} kit={@kit} {@control} />
      <%!-- A sensitive field that is left empty changes nothing, so it cannot
      say "no value". Where the record has a value and the action takes none,
      a button says it: "Clear". The value is emptied when the action runs.
      Until then the field says so in place of its input, and the button
      takes it back: "Keep". Nothing of this is in the form: the panel
      keeps it, and the server gives the action the field without a value.
      The panel's hook sends it (`panel_clear`), and puts the focus back on
      the button, which a patch that changes what stands before it takes off. --%>
      <p :if={@clear && @clear.asked?} {@clear.cleared} class="text-sm" data-cleared>
        {@texts.will_be_cleared}
      </p>
      <button
        :if={@clear}
        type="button"
        class="btn btn-sm justify-self-start"
        {@clear.button}
      >
        {if @clear.asked?, do: @texts.keep, else: @texts.clear}
      </button>
      <%!-- how long the text is, and the most it can be: under its control,
      at the end, where the eye is when the text gets long --%>
      <Kit.part :if={@count} part={:count} kit={@kit} class="justify-self-end" {@count} />
      <%!-- in the text colour: the error colour is too faint for small text --%>
      <div :if={@error && !(@group || @groups || @union)} {@error} class="mt-1 text-sm">
        <p :for={message <- @texts.errors} data-error>{message}</p>
      </div>
    </div>
    """
  end

  # The control of a field that is typed or chosen from a list: typed
  # hidden for a sensitive input, which is text or a number (it starts
  # empty whatever the record holds, and left empty it gives the action
  # nothing, `AshDataTable.Act`: what it holds here is what was typed into
  # it, which a patch has to bring back as it does for any field); a text
  # in a textarea, a choice in a menu, anything else in an input of its
  # type. `limits` are what the constraints of a number say of its control.
  # Its projection (`AshDataTable.Kit.Projection`, a field's `control`).
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :editor, :atom, required: true
  attr :secret?, :boolean, required: true
  attr :invalid?, :boolean, required: true
  attr :required?, :boolean, required: true
  attr :described, :any, required: true
  attr :limits, :map, required: true
  attr :values, :list, required: true
  attr :typing, :map, required: true

  def control(%{secret?: true} = assigns) do
    ~H"""
    <input
      type="password"
      autocomplete="off"
      id={@id}
      name={@name}
      value={@value}
      aria-required={@required? && "true"}
      aria-invalid={@invalid? && "true"}
      aria-describedby={@described}
      class={["input w-full", Parts.Editors.control_edge()]}
      {@typing}
    />
    """
  end

  def control(%{editor: :text} = assigns) do
    ~H"""
    <textarea
      id={@id}
      name={@name}
      rows="3"
      aria-required={@required? && "true"}
      aria-invalid={@invalid? && "true"}
      aria-describedby={@described}
      class={["textarea w-full", Parts.Editors.control_edge()]}
      {@typing}
    >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
    """
  end

  def control(%{editor: :enum} = assigns) do
    ~H"""
    <select
      id={@id}
      name={@name}
      aria-required={@required? && "true"}
      aria-invalid={@invalid? && "true"}
      aria-describedby={@described}
      class={["select w-full", Parts.Editors.control_edge()]}
    >
      <option :if={not @required? or @value == ""} value=""></option>
      <option
        :for={choice <- @values}
        value={choice.value}
        selected={choice.chosen?}
      >
        {choice.label}
      </option>
    </select>
    """
  end

  def control(assigns) do
    ~H"""
    <input
      type={field_type(@editor)}
      step={@limits.step || Parts.Editors.input_step(@editor)}
      min={@limits.min}
      max={@limits.max}
      id={@id}
      name={@name}
      value={@value}
      aria-required={@required? && "true"}
      aria-invalid={@invalid? && "true"}
      aria-describedby={@described}
      class={["input w-full", Parts.Editors.control_edge()]}
      {@typing}
    />
    """
  end

  # The field of a map cell: an embedded resource, or a map that declares
  # its fields. A group, named by the field's label, of the value's inputs,
  # each a field of the panel with the control of its own type. Nothing
  # marks it but the label and the indentation of what belongs to it.
  #
  # A value that is not there has a button that adds it, and one that may
  # be left out a button that takes it away: no group is no value, and a
  # group is the value as its fields say it, empty fields included. The
  # server renders it either way, and the buttons ask it to with
  # `phx-click` (their bundles in `group`: `add`, `remove`).
  #
  # `group.members` are its fields while it holds a value, nil for none.
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :labelledby, :string, required: true
  attr :required?, :boolean, required: true
  attr :error, :map, required: true
  attr :group, :map, required: true
  attr :uploads, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true

  defp group(assigns) do
    ~H"""
    <div
      id={@id}
      role="group"
      aria-labelledby={@labelledby}
      aria-describedby={@error && @error["id"]}
      data-group
    >
      <div class="flex items-center gap-1">
        <span {@group.label} class="label mb-1 text-base-content">
          <span data-label>{@label}</span>
          <span :if={@required?} aria-hidden="true">*</span>
          <span :if={@required?} class="sr-only">{@texts.required}</span>
        </span>
        <button
          :if={@group.remove}
          type="button"
          {@group.remove}
          aria-label={@texts.remove_group}
          class="btn btn-ghost btn-xs mb-1"
        >
          <span aria-hidden="true">✕</span>
        </button>
      </div>
      <div :if={@error} {@error} class="mb-1 text-sm">
        <p :for={message <- @texts.errors} data-error>{message}</p>
      </div>
      <div :if={@group.members} class="ps-4">
        <.members members={@group.members} uploads={@uploads} kit={@kit} />
      </div>
      <button
        :if={@group.add}
        type="button"
        {@group.add}
        class="btn btn-sm"
      >
        {@texts.add_value}
      </button>
    </div>
    """
  end

  # The field of an array of map cells: one group per value (`items`), each
  # named by the field's label and the value's place ("Milestones 2"), with
  # a button that takes the value away, and after them a button that adds
  # one, as the field of an array of plain values has them.
  #
  # Each value is sent under a number of its own, which says where it
  # stands among the others and stays its own for as long as it is there:
  # taking a value away renames none of the others. The field sends an
  # entry of its own besides, so that a list without values is sent at all
  # (`hidden`).
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :labelledby, :string, required: true
  attr :error, :map, required: true
  attr :groups, :map, required: true
  attr :uploads, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true

  defp groups(assigns) do
    assigns = assign(assigns, items: Enum.with_index(assigns.groups.items))

    ~H"""
    <div
      id={@id}
      role="group"
      aria-labelledby={@labelledby}
      aria-describedby={@error && @error["id"]}
      data-groups
    >
      <span {@groups.label} class="label mb-1 text-base-content">
        <span data-label>{@label}</span>
      </span>
      <div :if={@error} {@error} class="mb-1 text-sm">
        <p :for={message <- @texts.errors} data-error>{message}</p>
      </div>
      <input :for={entry <- @groups.hidden} type="hidden" {entry} />
      <div
        :for={{item, index} <- @items}
        {item.element}
        role="group"
        aria-labelledby={item.labelledby}
        aria-describedby={item.error && item.error["id"]}
        data-group-item
        class="mb-2"
      >
        <div class="flex items-center gap-1">
          <span {item.label} class="label mb-1 text-base-content">
            {Enum.at(@texts.value_position, index)}
          </span>
          <button
            type="button"
            {item.remove}
            aria-label={Enum.at(@texts.remove_value, index)}
            class="btn btn-ghost btn-xs mb-1"
          >
            <span aria-hidden="true">✕</span>
          </button>
        </div>
        <div
          :if={item.error}
          {item.error}
          class="mb-1 text-sm"
        >
          <p :for={message <- Enum.at(@texts.item_errors, index)} data-error>{message}</p>
        </div>
        <div class="ps-4">
          <.members members={item.members} uploads={@uploads} kit={@kit} />
        </div>
      </div>
      <button
        type="button"
        {@groups.add}
        class="btn btn-sm"
      >
        {@texts.add_value}
      </button>
    </div>
    """
  end

  # The field of a union: a group, named by the field's label, of the choice
  # of its kind (`union.kind`, "" for none yet) and, under it, that kind's
  # value. A kind that holds one value has the one control of its type,
  # called what the kind is called (`single`); a kind made of fields has
  # those fields (`members`), each with its own control, as the group of a
  # map cell has them.
  #
  # No kind is no value: the choice has an empty entry where the value may
  # be left out, and until a kind is chosen. Choosing another kind is an
  # ordinary change of the panel's form: the server renders the fields of
  # that kind in place of the others. The field says which kind the value
  # it sends was given for (an entry of `hidden`), so that what was typed
  # for one kind is never taken as the value of another.
  #
  # What the action says of the union as a whole is shown at the value where
  # the kind holds one value, which is what it is about, and under the
  # group's label otherwise (`own_errors?`).
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :labelledby, :string, required: true
  attr :required?, :boolean, required: true
  attr :error, :map, required: true
  attr :union, :map, required: true
  attr :uploads, :map, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true

  defp union(assigns) do
    ~H"""
    <div
      id={@id}
      role="group"
      aria-labelledby={@labelledby}
      aria-describedby={@union.own_errors? && @error["id"]}
      data-union
    >
      <span {@union.label} class="label mb-1 text-base-content">
        <span data-label>{@label}</span>
        <span :if={@required?} aria-hidden="true">*</span>
        <span :if={@required?} class="sr-only">{@texts.required}</span>
      </span>
      <div :if={@union.own_errors?} {@error} class="mb-1 text-sm">
        <p :for={message <- @texts.errors} data-error>{message}</p>
      </div>
      <div class="ps-4">
        <input :for={entry <- @union.hidden} type="hidden" {entry} />
        <div class="fieldset mb-2" {@union.choice}>
          <label {@union.kind_label} class="label mb-1 text-base-content">
            <span data-label>{@texts.kind}</span>
          </label>
          <select
            {@union.select}
            class={["select w-full", Parts.Editors.control_edge()]}
          >
            <option :if={@union.empty?} value=""></option>
            <option
              :for={kind <- @union.kinds}
              value={kind.value}
              selected={kind.chosen?}
            >
              {kind.label}
            </option>
          </select>
        </div>
        <Kit.part
          :if={@union.single}
          part={:field}
          kit={@kit}
          uploads={@uploads}
          {@union.single}
        />
        <.members :if={@union.members} members={@union.members} uploads={@uploads} kit={@kit} />
      </div>
    </div>
    """
  end

  # The inputs of one value made of fields, each a field of the panel, whose
  # id is the group's and its own (`ID-panel-f-client-f-name`,
  # `ID-panel-f-milestones-0-f-title`: `AshDataTable.GroupValue`). The
  # value says that it is there with an entry of its own, so that one
  # without inputs, or with nothing but boxes, is sent at all; and sends
  # back the primary key it came with, where that is no input: Ash tells by
  # it which value of an array is which (both in `hidden`).
  attr :members, :map, required: true
  attr :uploads, :map, required: true
  attr :kit, :atom, required: true

  defp members(assigns) do
    ~H"""
    <input :for={entry <- @members.hidden} type="hidden" {entry} />
    <Kit.part
      :for={inner <- @members.fields}
      part={:field}
      kit={@kit}
      uploads={@uploads}
      {inner}
    />
    """
  end

  # The editor of a column's component as a field of the panel. It is given
  # what the same editor is given in a cell, with the field's value, and on
  # its control what a field of the panel has (`component.control`): the id
  # its label points at, the name its value is sent under, and what says
  # that it is required or has an error. The label, the mark and the
  # messages around it stay the table's.
  defp field_editor(assigns) do
    ~H"""
    <Parts.Common.dynamic_component
      module={@component.module}
      function={:editor}
      value={@value}
      label={@label}
      column={@component.column}
      place={:panel}
      control={@component.control}
    />
    """
  end

  defp field_type(:plain), do: "text"
  defp field_type(editor), do: Parts.Editors.input_type(editor)
end
