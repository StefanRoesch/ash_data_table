defmodule AshDataTable.Parts.Panel do
  @moduledoc false
  # The action panel and its fields: groups, unions and chosen records.
  # The parts `panel`, `field` and `control` of `AshDataTable.Kit.Default`;
  # what a part draws inside it, it draws through the kit
  # (`Parts.Common.part/1`).
  use Phoenix.Component

  alias AshDataTable.Attrs
  alias AshDataTable.Ids
  alias AshDataTable.Kit
  alias AshDataTable.Kit.Words
  alias AshDataTable.Parts

  # The action panel: where a person gives the inputs of a row action, or of
  # the create action, before it runs. A modal dialog at the right edge of
  # the window, which its hook opens when it is put into the page and which
  # goes when the server takes it out again. Its form is the form of an
  # `AshPhoenix.Form` of the action, which the table keeps while the panel
  # is open: what is typed is given to the action as it is typed, and the
  # action's errors are shown at their fields. What is drawn is what
  # `AshDataTable.Panel.shown/2` gives of it (`panel`): never the form.
  attr :id, :string, required: true
  # what `AshDataTable.Panel.shown/2` gives of the open panel, nil while
  # it is closed: then nothing is drawn
  attr :panel, :any, required: true
  # the assigns of each field's `field` part (`AshDataTable.Kit.fields/3`)
  attr :fields, :list, required: true
  attr :target, :any, required: true
  # `:modal`, a dialog over the page, or `:inline`, a part of it
  attr :presentation, :atom, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true

  def panel(%{panel: nil} = assigns), do: ~H""

  def panel(assigns) do
    ~H"""
    <%!-- `open` is the hook's: a patch leaves it alone. Not daisyUI's `modal`,
    for the reason given at the other dialog. --%>
    <.dynamic_tag
      tag_name={if @presentation == :modal, do: "dialog", else: "section"}
      {Attrs.panel(@id, @panel, @texts.question, @target, @presentation)}
      class={@kit.class(:panel, %{destructive?: @panel.destructive?, presentation: @presentation})}
    >
      <%!-- `novalidate`, for the reason given at the argument line: the
      limits on a field describe, and the action judges. --%>
      <form
        id={"#{@id}-panel-form"}
        method={@panel.method}
        phx-change={Attrs.event(@id, "panel_validate")}
        phx-submit={Attrs.event(@id, "panel_submit")}
        phx-target={@target}
        novalidate
      >
        <h2 id={"#{@id}-panel-title"} class="mb-4 text-lg font-semibold">{@texts.title}</h2>
        <%!-- what the action says that is about none of the fields --%>
        <div
          :if={@panel.errors}
          id={"#{@id}-panel-errors"}
          role="alert"
          class="mb-4 text-sm font-medium"
        >
          <p :for={message <- @texts.errors}>{message}</p>
        </div>
        <Kit.part :for={field <- @fields} part={:field} kit={@kit} target={@target} {field} />
        <div class="mt-6 flex justify-end gap-2">
          <button type="button" {Attrs.cancel("#{@id}-panel-cancel")} class="btn">
            {@texts.cancel}
          </button>
          <button
            type="submit"
            id={"#{@id}-panel-submit"}
            class={["btn", if(@panel.destructive?, do: "btn-error", else: "btn-primary")]}
          >
            {@texts.submit}
          </button>
        </div>
      </form>
      <%!-- what opens inside it is moved in here (`Phoenix.Component.portal/1`) --%>
      <div id={Ids.panel_place(@id)} class="contents"></div>
    </.dynamic_tag>
    """
  end

  # One field of the action panel: its label, the control of its type, and
  # the action's errors about it. The controls are those of the cell
  # editors, at the size of a form's.
  #
  # `name` is what the field is sent under and `value` what it holds, as its
  # control holds it. A field inside a group is one of these too: `input` is
  # then a field of a map cell (`AshDataTable.Model.Field`). Its `path` is
  # what the field says of itself (`data-field`): its name, and for a field
  # inside a group the names on the way to it, with a dot between; `table`
  # the id its events name. What a value made of fields holds is given
  # (`hidden`, `members`, `items`, `kind`, `kind_id`, `kind_name`,
  # `kind_path`, `single`, and the ids of its buttons `add_id` and
  # `remove_id`: `AshDataTable.Kit.fields/3`), and what its control says
  # (`limits`, `counted`).
  attr :id, :string, required: true
  attr :input, :map, required: true
  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :errors, :list, required: true
  attr :places, :list, required: true
  attr :chosen, :any, required: true
  attr :clear, :atom, required: true
  attr :upload, :any, required: true
  attr :path, :list, required: true
  attr :table, :string, required: true
  attr :limits, :map, required: true
  attr :counted, :map, required: true
  attr :hidden, :list, required: true
  attr :members, :map, required: true
  attr :items, :list, required: true
  attr :kind, :string, required: true
  attr :kind_id, :string, required: true
  attr :kind_name, :string, required: true
  attr :kind_path, :list, required: true
  attr :add_id, :string, required: true
  attr :remove_id, :string, required: true
  attr :single, :map, required: true
  attr :target, :any, required: true
  attr :kit, :atom, required: true
  attr :texts, :map, required: true
  attr :locale, :string, required: true

  def field(assigns) do
    value = assigns.value

    # typed hidden: a password input in place of the control of its type
    secret? = Map.get(assigns.input, :sensitive?) == true

    assigns =
      assign(assigns,
        described:
          Parts.Editors.described([
            assigns.errors != [] && Ids.error(assigns.id),
            assigns.counted && assigns.input.editor == :text && "#{assigns.id}-count"
          ]),
        array?: assigns.input.editor in [:choices, :list],
        group?: assigns.input.editor in [:group, :groups, :union],
        secret?: secret?,
        file?: assigns.input.editor == :file and not is_nil(assigns.upload),
        reference?: assigns.input.editor == :reference,
        references?: assigns.input.editor == :references,
        # what the record is called whose key the field holds, while it
        # holds that key
        called: if(assigns.input.editor == :reference, do: List.first(assigns.texts.chosen)),
        # the records a field of several holds, each with its key, what it
        # is called and the name of its button that takes it out
        entries:
          if assigns.input.editor == :references do
            Enum.zip([value, assigns.texts.chosen, assigns.texts.remove_chosen])
            |> Enum.with_index()
          end
      )

    ~H"""
    <div class="fieldset mb-2" {Attrs.field(@path)}>
      <%!-- an unchecked box sends nothing: this says "false" for it --%>
      <input :if={@input.editor == :boolean} type="hidden" name={@name} value="false" />
      <label
        :if={not @array? and not @reference? and not @references? and not @group? and not @file?}
        for={@id}
        class="label mb-1 text-base-content"
      >
        <input
          :if={@input.editor == :boolean}
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@value == "true"}
          aria-invalid={@errors != [] && "true"}
          aria-describedby={@described}
          class={["checkbox checkbox-sm", Parts.Editors.box_edge()]}
        />
        <span data-label>{@input.label}</span>
        <span :if={@input.required? and @input.editor != :boolean} aria-hidden="true">*</span>
      </label>
      <%!-- An array has several controls, and its label is for none of them
      alone: they are a group, which the label names. It has no mark of a
      required field: the field always gives a list, with or without values,
      and how many it has to have is the action's to say. --%>
      <span
        :if={@array? or @references?}
        id={"#{@id}-label"}
        class="label mb-1 text-base-content"
      >
        <span data-label>{@input.label}</span>
      </span>
      <%!-- The key of a related record is not typed: the field says what the
      record is called, as plain text, and its button opens the picker. The
      two are a group, which the label names; the key itself is sent by an
      input that is not shown. (Not of the type `hidden`, for the reason given
      at the field of an array.) A group cannot say that it is required, so
      the label says it. --%>
      <span :if={@reference?} id={"#{@id}-label"} class="label mb-1 text-base-content">
        <span data-label>{@input.label}</span>
        <span :if={@input.required?} aria-hidden="true">*</span>
        <span :if={@input.required?} class="sr-only">{@texts.required}</span>
      </span>
      <div
        :if={@reference?}
        id={@id}
        role="group"
        aria-labelledby={"#{@id}-label"}
        aria-describedby={@described}
        class="flex items-center gap-2"
      >
        <input type="text" name={@name} value={@value} hidden data-key />
        <span :if={@called} id={"#{@id}-chosen"} class="text-sm" data-chosen>{@called}</span>
        <button
          type="button"
          id={Ids.choose(@id)}
          class="btn btn-sm"
          aria-describedby={@called && "#{@id}-chosen"}
          phx-click={Attrs.event(@table, "pick_input")}
          phx-value-input={@input.name}
          phx-target={@target}
        >
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
        :if={@references?}
        id={@id}
        role="group"
        aria-labelledby={"#{@id}-label"}
        aria-describedby={@described}
        data-references
        class="flex flex-col gap-1"
      >
        <input type="text" name={@name <> "[]"} value="" hidden data-own />
        <div
          :for={{{key, called, remove}, at} <- @entries}
          class="flex items-center gap-1"
          data-chosen-item
        >
          <input type="text" name={@name <> "[]"} value={key} hidden data-key />
          <span id={"#{@id}-c-#{at}"} class="text-sm" data-chosen>
            {called}
          </span>
          <button
            type="button"
            id={Ids.unpick(@id, at)}
            {Attrs.unpick(@table, @input.name, key, @target)}
            aria-label={remove}
            class="btn btn-ghost btn-xs"
          >
            <span aria-hidden="true">✕</span>
          </button>
        </div>
        <button
          type="button"
          id={Ids.choose(@id)}
          class="btn btn-sm self-start"
          phx-click={Attrs.event(@table, "pick_input")}
          phx-value-input={@input.name}
          phx-target={@target}
        >
          {@texts.choose}
        </button>
      </div>
      <div
        :if={@array?}
        id={@id}
        role="group"
        aria-labelledby={"#{@id}-label"}
        aria-describedby={@described}
        data-invalid={@places != [] && Attrs.held(@places)}
        class="flex flex-col gap-1"
      >
        <%!-- A form sends nothing for a list without values. This entry is
        sent before the values in every case, and is left out where they are
        taken (`AshDataTable.Act`). It is not of the type `hidden`: LiveView then
        says of the field whether a person has used it, as of any other. --%>
        <input type="text" name={@name <> "[]"} value="" hidden data-own />
        <%!-- multiple choice: one box per value of the enum --%>
        <label
          :for={{choice, label} <- (@input.editor == :choices && @input.values) || []}
          class="label text-base-content"
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
        <%!-- What the field holds that is none of the enum's values, and so
        has no box: sent with the ticked ones, after them, so that the
        action is given back what a person could not see or change. --%>
        <input
          :for={value <- (@input.editor == :choices && boxless(@input, @value)) || []}
          type="hidden"
          name={@name <> "[]"}
          value={value}
        />
        <%!-- The rows are the hook's from here on: a patch leaves them alone,
        so that a value a person has added is not taken away by the answer
        to an earlier change. Which of them the action refuses is said on the
        group around them (`data-invalid`: their places, counted from 0, as
        JSON), and the hook marks their controls. --%>
        <Kit.part
          :if={@input.editor == :list}
          part={:list}
          kit={@kit}
          id={"#{@id}-values"}
          rest={%{"phx-update" => "ignore"}}
          label={@input.label}
          item={elem(@input.cell_type, 1)}
          limits={@limits}
          counted={@counted}
          values={@value}
          name={@name <> "[]"}
          texts={Words.texts(:list, %{label: @input.label, values: @value})}
          messages={Words.messages(:list, %{label: @input.label, values: @value})}
        />
      </div>

      <%!-- a value made of fields, and an array of them --%>
      <.group
        :if={@input.editor == :group}
        id={@id}
        name={@name}
        field={@input}
        add_id={@add_id}
        remove_id={@remove_id}
        members={@members}
        items={@items}
        kind={@kind}
        single={@single}
        errors={@errors}
        path={@path}
        table={@table}
        target={@target}
        kit={@kit}
        texts={@texts}
      />
      <.groups
        :if={@input.editor == :groups}
        id={@id}
        name={@name}
        field={@input}
        hidden={@hidden}
        add_id={@add_id}
        members={@members}
        items={@items}
        kind={@kind}
        single={@single}
        errors={@errors}
        path={@path}
        table={@table}
        target={@target}
        kit={@kit}
        texts={@texts}
      />
      <%!-- a union: the choice of its kind, and under it that kind's value --%>
      <.union
        :if={@input.editor == :union}
        id={@id}
        name={@name}
        field={@input}
        hidden={@hidden}
        members={@members}
        items={@items}
        kind={@kind}
        kind_id={@kind_id}
        kind_name={@kind_name}
        kind_path={@kind_path}
        single={@single}
        errors={@errors}
        path={@path}
        table={@table}
        target={@target}
        kit={@kit}
        texts={@texts}
      />
      <%!-- An argument that takes a file: LiveView's own file input, which
      shows the name of the file that was chosen, as a browser does. Its id
      is LiveView's to say, so the label is pointed at that. The file is sent
      when the panel's button is used, and a bar says how far it has come
      while that takes time. --%>
      <label :if={@file?} for={@upload.ref} class="label mb-1 text-base-content">
        <span data-label>{@input.label}</span>
        <span :if={@input.required?} aria-hidden="true">*</span>
      </label>
      <.live_file_input
        :if={@file?}
        upload={@upload}
        aria-required={@input.required? && "true"}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={@described}
        class={["file-input w-full", Parts.Editors.control_edge()]}
      />
      <progress
        :for={entry <- (@file? && @upload.entries) || []}
        :if={entry.progress > 0 and not entry.done? and not entry.cancelled?}
        value={entry.progress}
        max="100"
        aria-label={entry.client_name}
        class="progress mt-1 w-full"
      >
        {entry.progress}%
      </progress>
      <%!-- an attribute whose column has a component that edits: its editor --%>
      {if @input.editor == :component, do: field_editor(assigns)}
      <%!-- A sensitive input, which is text or a number: typed hidden. It
      starts empty whatever the record holds, and left empty it gives the
      action nothing (`AshDataTable.Act`). What it holds here is what was typed
      into it, which a patch has to bring back as it does for any field. --%>
      <Kit.part
        :if={
          (@secret? and @clear != :asked) or
            (not @secret? and @input.editor in [:text, :enum, :number, :date, :datetime, :plain])
        }
        part={:control}
        kit={@kit}
        id={@id}
        input={@input}
        name={@name}
        value={@value}
        secret?={@secret?}
        invalid?={@errors != []}
        described={@described}
        limits={@limits}
      />
      <%!-- A sensitive field that is left empty changes nothing, so it cannot
      say "no value". Where the record has a value and the action takes none,
      a button says it: "Clear". The value is emptied when the action runs.
      Until then the field says so in place of its input, and the button
      takes it back: "Keep". Nothing of this is in the form: the panel
      keeps it, and the server gives the action the field without a value.
      The panel's hook sends it (`panel_clear`), and puts the focus back on
      the button, which a patch that changes what stands before it takes off. --%>
      <p :if={@clear == :asked} id={"#{@id}-cleared"} class="text-sm" data-cleared>
        {@texts.will_be_cleared}
      </p>
      <button
        :if={@clear}
        type="button"
        id={Ids.clear(@id)}
        class="btn btn-sm justify-self-start"
        aria-label={
          if @clear == :asked,
            do: @texts.keep_value,
            else: @texts.clear_value
        }
        aria-describedby={@clear == :asked && "#{@id}-cleared"}
        {Attrs.clear_field(@table, @input.name, @target)}
      >
        {if @clear == :asked, do: @texts.keep, else: @texts.clear}
      </button>
      <%!-- how long the text is, and the most it can be: under its control,
      at the end, where the eye is when the text gets long --%>
      <Kit.part
        :if={@counted && @input.editor == :text}
        part={:count}
        kit={@kit}
        class="justify-self-end"
        {AshDataTable.Kit.Projection.Count.of("#{@id}-count", @counted, @value)}
      />
      <%!-- in the text colour: the error colour is too faint for small text --%>
      <div :if={@errors != [] and not @group?} id={Ids.error(@id)} class="mt-1 text-sm">
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
  attr :id, :string, required: true
  attr :input, :map, required: true
  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :secret?, :boolean, required: true
  attr :invalid?, :boolean, required: true
  attr :described, :any, required: true
  attr :limits, :map, required: true

  def control(%{secret?: true} = assigns) do
    ~H"""
    <input
      type="password"
      autocomplete="off"
      id={@id}
      name={@name}
      value={@value}
      aria-required={@input.required? && "true"}
      aria-invalid={@invalid? && "true"}
      aria-describedby={@described}
      class={["input w-full", Parts.Editors.control_edge()]}
    />
    """
  end

  def control(%{input: %{editor: :text}} = assigns) do
    ~H"""
    <textarea
      id={@id}
      name={@name}
      rows="3"
      aria-required={@input.required? && "true"}
      aria-invalid={@invalid? && "true"}
      aria-describedby={@described}
      class={["textarea w-full", Parts.Editors.control_edge()]}
    >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
    """
  end

  def control(%{input: %{editor: :enum}} = assigns) do
    ~H"""
    <select
      id={@id}
      name={@name}
      aria-required={@input.required? && "true"}
      aria-invalid={@invalid? && "true"}
      aria-describedby={@described}
      class={["select w-full", Parts.Editors.control_edge()]}
    >
      <option :if={not @input.required? or @value == ""} value=""></option>
      <option
        :for={{choice, label} <- @input.values}
        value={choice}
        selected={to_string(choice) == @value}
      >
        {label}
      </option>
    </select>
    """
  end

  def control(assigns) do
    ~H"""
    <input
      type={field_type(@input.editor)}
      step={@limits.step || Parts.Editors.input_step(@input.editor)}
      min={@limits.min}
      max={@limits.max}
      id={@id}
      name={@name}
      value={@value}
      aria-required={@input.required? && "true"}
      aria-invalid={@invalid? && "true"}
      aria-describedby={@described}
      class={["input w-full", Parts.Editors.control_edge()]}
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
  # `phx-click` (`Attrs.add_group/4`, `Attrs.remove_group/4`: the way to
  # the group, and the button's id, `add_id`, `remove_id`).
  #
  # `members` are its fields while it holds a value, nil for none.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :field, :map, required: true
  attr :add_id, :string, required: true
  attr :remove_id, :string, required: true
  attr :members, :map, required: true
  attr :items, :list, required: true
  attr :kind, :string, required: true
  attr :single, :map, required: true
  attr :errors, :list, required: true
  attr :path, :list, required: true
  attr :table, :string, required: true
  attr :target, :any, default: nil
  attr :kit, :atom, required: true
  attr :texts, :map, required: true

  defp group(assigns) do
    ~H"""
    <div
      id={@id}
      role="group"
      aria-labelledby={"#{@id}-label"}
      aria-describedby={@errors != [] && Ids.error(@id)}
      data-group
    >
      <div class="flex items-center gap-1">
        <span id={"#{@id}-label"} class="label mb-1 text-base-content">
          <span data-label>{@field.label}</span>
          <span :if={@field.required?} aria-hidden="true">*</span>
          <span :if={@field.required?} class="sr-only">{@texts.required}</span>
        </span>
        <button
          :if={@members && not @field.required?}
          type="button"
          {Attrs.remove_group(@remove_id, @table, @path, @target)}
          aria-label={@texts.remove_group}
          class="btn btn-ghost btn-xs mb-1"
        >
          <span aria-hidden="true">✕</span>
        </button>
      </div>
      <div :if={@errors != []} id={Ids.error(@id)} class="mb-1 text-sm">
        <p :for={message <- @texts.errors} data-error>{message}</p>
      </div>
      <div :if={@members} class="ps-4">
        <.members members={@members} target={@target} kit={@kit} />
      </div>
      <button
        :if={!@members}
        type="button"
        {Attrs.add_group(@add_id, @table, @path, @target)}
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
  attr :name, :string, required: true
  attr :field, :map, required: true
  attr :hidden, :list, required: true
  attr :add_id, :string, required: true
  attr :members, :map, required: true
  attr :items, :list, required: true
  attr :kind, :string, required: true
  attr :single, :map, required: true
  attr :errors, :list, required: true
  attr :path, :list, required: true
  attr :table, :string, required: true
  attr :target, :any, default: nil
  attr :kit, :atom, required: true
  attr :texts, :map, required: true

  defp groups(assigns) do
    assigns = assign(assigns, items: Enum.with_index(assigns.items))

    ~H"""
    <div
      id={@id}
      role="group"
      aria-labelledby={"#{@id}-label"}
      aria-describedby={@errors != [] && Ids.error(@id)}
      data-groups
    >
      <span id={"#{@id}-label"} class="label mb-1 text-base-content">
        <span data-label>{@field.label}</span>
      </span>
      <div :if={@errors != []} id={Ids.error(@id)} class="mb-1 text-sm">
        <p :for={message <- @texts.errors} data-error>{message}</p>
      </div>
      <input :for={entry <- @hidden} type="hidden" {entry} />
      <div
        :for={{item, index} <- @items}
        id={item.id}
        role="group"
        aria-labelledby={"#{item.id}-label"}
        aria-describedby={Enum.at(@texts.item_errors, index) != [] && Ids.error(item.id)}
        data-group-item
        class="mb-2"
      >
        <div class="flex items-center gap-1">
          <span id={"#{item.id}-label"} class="label mb-1 text-base-content">
            {Enum.at(@texts.value_position, index)}
          </span>
          <button
            type="button"
            {Attrs.remove_group(item.remove_id, @table, item.path, @target)}
            aria-label={Enum.at(@texts.remove_value, index)}
            class="btn btn-ghost btn-xs mb-1"
          >
            <span aria-hidden="true">✕</span>
          </button>
        </div>
        <div
          :if={Enum.at(@texts.item_errors, index) != []}
          id={Ids.error(item.id)}
          class="mb-1 text-sm"
        >
          <p :for={message <- Enum.at(@texts.item_errors, index)} data-error>{message}</p>
        </div>
        <div class="ps-4">
          <.members members={item.members} target={@target} kit={@kit} />
        </div>
      </div>
      <button
        type="button"
        {Attrs.add_group(@add_id, @table, @path, @target)}
        class="btn btn-sm"
      >
        {@texts.add_value}
      </button>
    </div>
    """
  end

  # The field of a union: a group, named by the field's label, of the choice
  # of its kind (`kind`, "" for none yet) and, under it, that kind's value.
  # A kind that holds one value has the one control of its type, called
  # what the kind is called (`single`); a kind made of fields has those
  # fields (`members`), each with its own control, as the group of a map
  # cell has them.
  #
  # No kind is no value: the choice has an empty entry where the value may
  # be left out, and until a kind is chosen. Choosing another kind is an
  # ordinary change of the panel's form: the server renders the fields of
  # that kind in place of the others. The field says which kind the value
  # it sends was given for (an entry of `hidden`), so that what was typed
  # for one kind is never taken as the value of another
  # (`AshDataTable.GroupValue.kind/3`). The choice is sent under
  # `kind_name`, and says what it is under `kind_path`.
  #
  # What the action says of the union as a whole is shown at the value where
  # the kind holds one value, which is what it is about, and under the
  # group's label otherwise.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :field, :map, required: true
  attr :hidden, :list, required: true
  attr :members, :map, required: true
  attr :items, :list, required: true
  attr :kind, :string, required: true
  attr :kind_id, :string, required: true
  attr :kind_name, :string, required: true
  attr :kind_path, :list, required: true
  attr :single, :map, required: true
  attr :errors, :list, required: true
  attr :path, :list, required: true
  attr :table, :string, required: true
  attr :target, :any, default: nil
  attr :kit, :atom, required: true
  attr :texts, :map, required: true

  defp union(assigns) do
    assigns = assign(assigns, own_errors: if(assigns.single, do: [], else: assigns.texts.errors))

    ~H"""
    <div
      id={@id}
      role="group"
      aria-labelledby={"#{@id}-label"}
      aria-describedby={@own_errors != [] && Ids.error(@id)}
      data-union
    >
      <span id={"#{@id}-label"} class="label mb-1 text-base-content">
        <span data-label>{@field.label}</span>
        <span :if={@field.required?} aria-hidden="true">*</span>
        <span :if={@field.required?} class="sr-only">{@texts.required}</span>
      </span>
      <div :if={@own_errors != []} id={Ids.error(@id)} class="mb-1 text-sm">
        <p :for={message <- @own_errors} data-error>{message}</p>
      </div>
      <div class="ps-4">
        <input :for={entry <- @hidden} type="hidden" {entry} />
        <div class="fieldset mb-2" {Attrs.field(@kind_path)}>
          <label for={@kind_id} class="label mb-1 text-base-content">
            <span data-label>{@texts.kind}</span>
          </label>
          <select
            id={@kind_id}
            name={@kind_name}
            aria-required={@field.required? && "true"}
            class={["select w-full", Parts.Editors.control_edge()]}
          >
            <option :if={not @field.required? or @kind == ""} value=""></option>
            <option
              :for={kind <- @field.members}
              value={kind.name}
              selected={Atom.to_string(kind.name) == @kind}
            >
              {kind.label}
            </option>
          </select>
        </div>
        <Kit.part :if={@single} part={:field} kit={@kit} target={@target} {@single} />
        <.members :if={@members} members={@members} target={@target} kit={@kit} />
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
  attr :target, :any, default: nil
  attr :kit, :atom, required: true

  defp members(assigns) do
    ~H"""
    <input :for={entry <- @members.hidden} type="hidden" {entry} />
    <Kit.part
      :for={inner <- @members.fields}
      part={:field}
      kit={@kit}
      target={@target}
      {inner}
    />
    """
  end

  # The editor of a column's component as a field of the panel. It is given
  # what the same editor is given in a cell, with the field's value, and on
  # its control what a field of the panel has: the id its label points at,
  # the name its value is sent under, and what says that it is required or
  # has an error. The label, the mark and the messages around it stay the
  # table's.
  defp field_editor(assigns) do
    ~H"""
    <Parts.Common.dynamic_component
      module={@input.component.module}
      function={:editor}
      value={@value}
      label={@input.label}
      column={@input.component.column}
      place={:panel}
      control={
        %{
          "id" => @id,
          "name" => @name,
          "aria-required" => @input.required? && "true",
          "aria-invalid" => @errors != [] && "true",
          "aria-describedby" => @described,
          "data-control" => true
        }
      }
    />
    """
  end

  defp field_type(:plain), do: "text"
  defp field_type(editor), do: Parts.Editors.input_type(editor)

  # What a record that a field holds is called: the value its label is,
  # as a cell of that column shows it (`AshDataTable.Present.Field`).
  # The values of a multiple choice's field that are none of its choices.
  defp boxless(%{values: values}, held) do
    choices = Enum.map(values, fn {choice, _label} -> to_string(choice) end)
    Enum.reject(held, &(&1 in choices))
  end
end
