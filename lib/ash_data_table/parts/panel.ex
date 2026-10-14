defmodule AshDataTable.Parts.Panel do
  @moduledoc false
  # The action panel and its fields: groups, unions and chosen records.
  # Moved out of `AshDataTable.Live.TableComponent` in stage 1 of the
  # refactor (docs/architecture/target.md); it still draws from the
  # component's assigns.
  use Phoenix.Component

  alias AshDataTable.Act
  alias AshDataTable.Format
  alias AshDataTable.Model
  alias AshDataTable.Model.Limits
  alias AshDataTable.Parts
  alias AshDataTable.Resource.Exposing
  alias AshDataTable.Text
  alias Phoenix.LiveView.JS

  # The action panel: where a person gives the inputs of a row action, or of
  # the create action, before it runs. A modal dialog at the right edge of
  # the window, which its hook opens when it is put into the page and which
  # goes when the server takes it out again. Its form is an
  # `AshPhoenix.Form` of the action, kept by the table while the panel is
  # open: what is typed is given to the action as it is typed, and the
  # action's errors are shown at their fields.
  attr :id, :string, required: true
  attr :panel, :map, required: true
  # the file fields, by name: the upload LiveView keeps for each, and what
  # is said of its file (`errors`), as the live layer tells it
  attr :files, :map, default: %{}
  attr :target, :any, required: true

  def panel(assigns) do
    assigns = assign(assigns, form: to_form(assigns.panel.form))

    ~H"""
    <%!-- `open` is the hook's: a patch leaves it alone. Not daisyUI's `modal`,
    for the reason given at the other dialog. --%>
    <dialog
      id={"#{@id}-panel"}
      phx-hook="AshDataTable.Live.TableComponent.Panel"
      phx-mounted={JS.ignore_attributes(["open"])}
      phx-target={@target}
      data-question={Map.get(@panel, :question) || @panel.action.confirm}
      data-ask={@panel.kind == :cell && "changed"}
      data-destructive={@panel.action.type == :destroy}
      aria-labelledby={"#{@id}-panel-title"}
      class="m-0 ms-auto h-dvh max-h-dvh w-full max-w-md overflow-y-auto bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/40 forced-colors:border"
    >
      <%!-- `novalidate`, for the reason given at the argument line: the
      limits on a field describe, and the action judges. --%>
      <.form
        for={@form}
        id={"#{@id}-panel-form"}
        phx-change="panel_validate"
        phx-submit="panel_submit"
        phx-target={@target}
        novalidate
      >
        <h2 id={"#{@id}-panel-title"} class="mb-4 text-lg font-semibold">{@panel.title}</h2>
        <%!-- what the action says that is about none of the fields --%>
        <div
          :if={@panel.errors[nil]}
          id={"#{@id}-panel-errors"}
          role="alert"
          class="mb-4 text-sm font-medium"
        >
          <p :for={message <- @panel.errors[nil]}>{message}</p>
        </div>
        <.field
          :for={input <- @panel.inputs}
          id={"#{@id}-panel-f-#{input.name}"}
          input={input}
          name={@form[input.name].name}
          value={panel_value(@panel, @form, input)}
          errors={field_errors(@panel, input, @files)}
          places={field_places(@panel, input, @files)}
          chosen={@panel.chosen[input.name]}
          clear={
            cond do
              input.name in @panel.cleared -> :asked
              input.name in @panel.clearable -> :offered
              true -> nil
            end
          }
          upload={@files[input.name][:upload]}
          inside={
            %{
              errors: @panel.errors,
              touched: @panel.touched,
              submitted?: @panel.submitted?,
              place: [input.name],
              path: [Atom.to_string(input.name)],
              time_zone: @panel.time_zone
            }
          }
          target={@target}
        />
        <div class="mt-6 flex justify-end gap-2">
          <button type="button" id={"#{@id}-panel-cancel"} class="btn" data-cancel>
            {Text.t(:cancel)}
          </button>
          <button
            type="submit"
            id={"#{@id}-panel-submit"}
            class={["btn", if(@panel.action.type == :destroy, do: "btn-error", else: "btn-primary")]}
          >
            {@panel.submit}
          </button>
        </div>
      </.form>
    </dialog>
    """
  end

  # What a field of the panel holds, as its control holds it: a field made
  # of groups as its form sends it; the field of an argument that is given
  # by choosing related records their keys, as the panel keeps them (a list
  # for several, one key or "" for one); a sensitive field what was typed
  # into it; and any other what the action's form holds for it
  # (`field_value/3`).
  defp panel_value(panel, form, input) do
    name = Atom.to_string(input.name)

    cond do
      Model.group?(input) ->
        panel.groups[name]

      is_map_key(panel.refs, name) and input.editor == :references ->
        panel.refs[name]

      is_map_key(panel.refs, name) ->
        List.first(panel.refs[name], "")

      # A sensitive field holds what was typed into it, and nothing else:
      # never what the record has, nor a default. It starts empty.
      Exposing.sensitive?(input) ->
        case panel.typed do
          %{^name => typed} when is_binary(typed) -> typed
          _nothing_typed -> ""
        end

      # A datetime that was typed is shown as it was typed, a wall time in
      # the page's zone: the form holds the instant it was given as.
      is_map_key(panel.typed, name) and AshDataTable.Zone.zoned?(input.type) ->
        field_value(input, Act.typed(input, panel.typed[name], panel.time_zone), false, panel)

      true ->
        field_value(
          input,
          form[input.name].value,
          panel.kind == :create or input.kind == :argument,
          panel
        )
    end
  end

  # The errors of a field that are shown: all of them once the person has
  # used "Run", and until then those of the fields they have been in.
  # of a file: what the action said of the file it was given
  # (`files`, with what LiveView says of the file before it)
  defp field_errors(_panel, %{editor: :file} = input, files) do
    case Map.get(files, input.name) do
      %{errors: errors} -> errors
      nil -> []
    end
  end

  # of a union: once they have been at its choice, or in its value
  defp field_errors(panel, %{editor: :union} = input, _files) do
    if panel.submitted? or in_union?(panel.touched, [Atom.to_string(input.name)]),
      do: Map.get(panel.errors, input.name, []),
      else: []
  end

  defp field_errors(panel, input, _files) do
    if panel.submitted? or Atom.to_string(input.name) in panel.used,
      do: Map.get(panel.errors, input.name, []),
      else: []
  end

  # Whether a person has been in the field of a union: at the choice of its
  # kind, or in the value of the kind. `path` is the way to the field, as
  # the names it is sent under. That the field was sent says nothing: it
  # always is, and so are the entries of its own that say what is there
  # (`_of`, `_present`).
  defp in_union?(touched, path) do
    value = path ++ ["_union_value"]
    inside = Enum.filter(touched, &(List.starts_with?(&1, value) and &1 != value))

    (path ++ ["_union_type"]) in touched or
      Enum.any?(inside, &(List.last(&1) not in ["_present", "_of"])) or
      (inside == [] and value in touched)
  end

  # The values of an array field that the errors shown at it are about, by
  # their places.
  defp field_places(panel, input, files) do
    if field_errors(panel, input, files) == [],
      do: [],
      else: panel |> Map.get(:places, %{}) |> Map.get(input.name, [])
  end

  # One field of the action panel: its label, the control of its type, and
  # the action's errors about it. The controls are those of the cell
  # editors, at the size of a form's.
  #
  # `name` is what the field is sent under and `value` what it holds, as its
  # control holds it (`field_value/3`). A field inside a group is one of
  # these too: `input` is then a field of a map cell
  # (`AshDataTable.Model.Field`). `inside` is what a field made of groups needs
  # to know of the panel for the fields in it: see `group/1`. Its `path` is
  # also what the field says of itself (`data-field`): its name, and for a
  # field inside a group the names on the way to it, with a dot between.
  attr :id, :string, required: true
  attr :input, :map, required: true
  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :errors, :list, required: true
  attr :places, :list, default: []
  attr :chosen, :any, default: nil
  attr :clear, :atom, default: nil
  attr :upload, :any, default: nil
  attr :inside, :map, required: true
  attr :target, :any, default: nil

  defp field(assigns) do
    value = assigns.value

    # typed hidden: a password input in place of the control of its type
    secret? = Exposing.sensitive?(assigns.input)

    # The counter of a text that has a most it can be long, and of each
    # value of an array of such texts. Not of a sensitive one: nothing is
    # said of what is typed hidden but what its control shows.
    counted =
      case assigns.input do
        _typed_hidden when secret? -> nil
        %{editor: :text} = input -> Limits.counted(input)
        %{editor: :list, cell_type: {:array, :text}} = input -> Limits.counted(input)
        _another_control -> nil
      end

    assigns =
      assign(assigns,
        described:
          Parts.Editors.described([
            assigns.errors != [] && "#{assigns.id}-error",
            counted && assigns.input.editor == :text && "#{assigns.id}-count"
          ]),
        counted: counted,
        array?: assigns.input.editor in [:choices, :list],
        # what the constraints of a number say of its control; of an array,
        # of the control of each value
        limits: Limits.of(assigns.input),
        group?: Model.group?(assigns.input),
        secret?: secret?,
        file?: assigns.input.editor == :file and not is_nil(assigns.upload),
        reference?: assigns.input.editor == :reference,
        references?: assigns.input.editor == :references,
        # what the record is called whose key the field holds, while it
        # holds that key
        called:
          case assigns.chosen do
            %{^value => %{called: called}} -> called
            _other -> nil
          end,
        # the records a field of several holds, each with its key, what it
        # is called, and its place, counted from 1
        entries:
          if assigns.input.editor == :references do
            for {key, position} <- Enum.with_index(value, 1) do
              {key, with(%{called: called} <- (assigns.chosen || %{})[key], do: called), position}
            end
          end
      )

    ~H"""
    <div class="fieldset mb-2" data-field={Enum.join(@inside.path, ".")}>
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
        <span :if={@input.required?} class="sr-only">{Text.t(:required)}</span>
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
          id={"#{@id}-choose"}
          class="btn btn-sm"
          aria-describedby={@called && "#{@id}-chosen"}
          phx-click="pick_input"
          phx-value-input={@input.name}
          phx-target={@target}
        >
          {Text.t(:choose)}
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
          :for={{key, called, position} <- @entries}
          class="flex items-center gap-1"
          data-chosen-item
        >
          <input type="text" name={@name <> "[]"} value={key} hidden data-key />
          <span id={"#{@id}-c-#{position - 1}"} class="text-sm" data-chosen>
            {called || Text.t(:not_available)}
          </span>
          <button
            type="button"
            id={"#{@id}-r-#{position - 1}"}
            data-unpick={Parts.Grid.held([Atom.to_string(@input.name), key])}
            aria-label={
              if called,
                do: Text.t(:remove_group, column: called),
                else: Text.t(:remove_value, column: @input.label, position: position)
            }
            class="btn btn-ghost btn-xs"
          >
            <span aria-hidden="true">✕</span>
          </button>
        </div>
        <button
          type="button"
          id={"#{@id}-choose"}
          class="btn btn-sm self-start"
          phx-click="pick_input"
          phx-value-input={@input.name}
          phx-target={@target}
        >
          {Text.t(:choose)}
        </button>
      </div>
      <div
        :if={@array?}
        id={@id}
        role="group"
        aria-labelledby={"#{@id}-label"}
        aria-describedby={@described}
        data-invalid={@places != [] && Parts.Grid.held(@places)}
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
        <Parts.Editors.list
          :if={@input.editor == :list}
          id={"#{@id}-values"}
          phx-update="ignore"
          label={@input.label}
          item={elem(@input.cell_type, 1)}
          limits={@limits}
          counted={@counted}
          place={:panel}
          values={@value}
          name={@name <> "[]"}
        />
      </div>

      <%!-- a value made of fields, and an array of them --%>
      <.group
        :if={@input.editor == :group}
        id={@id}
        name={@name}
        field={@input}
        held={@value}
        errors={@errors}
        inside={@inside}
        target={@target}
      />
      <.groups
        :if={@input.editor == :groups}
        id={@id}
        name={@name}
        field={@input}
        held={@value}
        errors={@errors}
        inside={@inside}
        target={@target}
      />
      <%!-- a union: the choice of its kind, and under it that kind's value --%>
      <.union
        :if={@input.editor == :union}
        id={@id}
        name={@name}
        field={@input}
        held={@value}
        errors={@errors}
        inside={@inside}
        target={@target}
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
      <input
        :if={@secret? and @clear != :asked}
        type="password"
        autocomplete="off"
        id={@id}
        name={@name}
        value={@value}
        aria-required={@input.required? && "true"}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={@described}
        class={["input w-full", Parts.Editors.control_edge()]}
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
        {Text.t(:will_be_cleared)}
      </p>
      <button
        :if={@clear}
        type="button"
        id={"#{@id}-clear"}
        class="btn btn-sm justify-self-start"
        aria-label={
          if @clear == :asked,
            do: Text.t(:keep_value, column: @input.label),
            else: Text.t(:clear_value, column: @input.label)
        }
        aria-describedby={@clear == :asked && "#{@id}-cleared"}
        data-clear-field={@input.name}
      >
        {if @clear == :asked, do: Text.t(:keep), else: Text.t(:clear)}
      </button>
      <textarea
        :if={@input.editor == :text and not @secret?}
        id={@id}
        name={@name}
        rows="3"
        aria-required={@input.required? && "true"}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={@described}
        class={["textarea w-full", Parts.Editors.control_edge()]}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <%!-- how long the text is, and the most it can be: under its control,
      at the end, where the eye is when the text gets long --%>
      <Parts.Editors.count
        :if={@counted && @input.editor == :text}
        id={"#{@id}-count"}
        counted={@counted}
        value={@value}
        class="justify-self-end"
      />
      <select
        :if={@input.editor == :enum}
        id={@id}
        name={@name}
        aria-required={@input.required? && "true"}
        aria-invalid={@errors != [] && "true"}
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
      <input
        :if={@input.editor in [:number, :date, :datetime, :plain] and not @secret?}
        type={field_type(@input.editor)}
        step={@limits.step || Parts.Editors.input_step(@input.editor)}
        min={@limits.min}
        max={@limits.max}
        id={@id}
        name={@name}
        value={@value}
        aria-required={@input.required? && "true"}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={@described}
        class={["input w-full", Parts.Editors.control_edge()]}
      />
      <%!-- in the text colour: the error colour is too faint for small text --%>
      <div :if={@errors != [] and not @group?} id={"#{@id}-error"} class="mt-1 text-sm">
        <p :for={message <- @errors} data-error>{message}</p>
      </div>
    </div>
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
  # server renders it either way, and the panel's hook asks it to
  # (`data-add-group`, `data-remove-group`: the way to the group, as JSON).
  #
  # `held` is what the field holds, as its form sends it
  # (`AshDataTable.Act.sent/2`), nil for no value. `inside` says what the panel
  # knows of the fields in it: the action's `errors` by the way to a field
  # (`place`: names, and the places of values in an array), and which
  # fields a person has been in (`touched`, by `path`: the names they are
  # sent under), whose errors are shown before "Run" is used.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :field, :map, required: true
  attr :held, :any, required: true
  attr :errors, :list, required: true
  attr :inside, :map, required: true
  attr :target, :any, default: nil

  defp group(assigns) do
    ~H"""
    <div
      id={@id}
      role="group"
      aria-labelledby={"#{@id}-label"}
      aria-describedby={@errors != [] && "#{@id}-error"}
      data-group
    >
      <div class="flex items-center gap-1">
        <span id={"#{@id}-label"} class="label mb-1 text-base-content">
          <span data-label>{@field.label}</span>
          <span :if={@field.required?} aria-hidden="true">*</span>
          <span :if={@field.required?} class="sr-only">{Text.t(:required)}</span>
        </span>
        <button
          :if={is_map(@held) and not @field.required?}
          type="button"
          id={"#{@id}-remove"}
          data-remove-group={Parts.Grid.held(@inside.path)}
          aria-label={Text.t(:remove_group, column: @field.label)}
          class="btn btn-ghost btn-xs mb-1"
        >
          <span aria-hidden="true">✕</span>
        </button>
      </div>
      <div :if={@errors != []} id={"#{@id}-error"} class="mb-1 text-sm">
        <p :for={message <- @errors} data-error>{message}</p>
      </div>
      <div :if={is_map(@held)} class="ps-4">
        <.members
          id={@id}
          name={@name}
          field={@field}
          held={@held}
          inside={@inside}
          target={@target}
        />
      </div>
      <button
        :if={not is_map(@held)}
        type="button"
        id={"#{@id}-add"}
        data-add-group={Parts.Grid.held(@inside.path)}
        class="btn btn-sm"
      >
        {Text.t(:add_value)}
      </button>
    </div>
    """
  end

  # The field of an array of map cells: one group per value, each named by
  # the field's label and the value's place ("Milestones 2"), with a button
  # that takes the value away, and after them a button that adds one, as
  # the field of an array of plain values has them.
  #
  # Each value is sent under a number of its own, which says where it
  # stands among the others and stays its own for as long as it is there:
  # taking a value away renames none of the others. The field sends an
  # entry of its own besides, so that a list without values is sent at all.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :field, :map, required: true
  attr :held, :any, required: true
  attr :errors, :list, required: true
  attr :inside, :map, required: true
  attr :target, :any, default: nil

  defp groups(assigns) do
    assigns = assign(assigns, items: Enum.with_index(Act.items(assigns.held)))

    ~H"""
    <div
      id={@id}
      role="group"
      aria-labelledby={"#{@id}-label"}
      aria-describedby={@errors != [] && "#{@id}-error"}
      data-groups
    >
      <span id={"#{@id}-label"} class="label mb-1 text-base-content">
        <span data-label>{@field.label}</span>
      </span>
      <div :if={@errors != []} id={"#{@id}-error"} class="mb-1 text-sm">
        <p :for={message <- @errors} data-error>{message}</p>
      </div>
      <input type="hidden" name={"#{@name}[_present]"} value="" />
      <div
        :for={{{key, item}, index} <- @items}
        id={"#{@id}-#{key}"}
        role="group"
        aria-labelledby={"#{@id}-#{key}-label"}
        aria-describedby={item_errors(@inside, index) != [] && "#{@id}-#{key}-error"}
        data-group-item
        class="mb-2"
      >
        <div class="flex items-center gap-1">
          <span id={"#{@id}-#{key}-label"} class="label mb-1 text-base-content">
            {Text.t(:value_position, column: @field.label, position: index + 1)}
          </span>
          <button
            type="button"
            id={"#{@id}-#{key}-remove"}
            data-remove-group={Parts.Grid.held(@inside.path ++ [key])}
            aria-label={Text.t(:remove_value, column: @field.label, position: index + 1)}
            class="btn btn-ghost btn-xs mb-1"
          >
            <span aria-hidden="true">✕</span>
          </button>
        </div>
        <div
          :if={item_errors(@inside, index) != []}
          id={"#{@id}-#{key}-error"}
          class="mb-1 text-sm"
        >
          <p :for={message <- item_errors(@inside, index)} data-error>{message}</p>
        </div>
        <div class="ps-4">
          <.members
            id={"#{@id}-#{key}"}
            name={"#{@name}[#{key}]"}
            field={@field}
            held={item}
            inside={%{@inside | place: @inside.place ++ [index], path: @inside.path ++ [key]}}
            target={@target}
          />
        </div>
      </div>
      <button
        type="button"
        id={"#{@id}-add"}
        data-add-group={Parts.Grid.held(@inside.path)}
        class="btn btn-sm"
      >
        {Text.t(:add_value)}
      </button>
    </div>
    """
  end

  # The field of a union: a group, named by the field's label, of the choice
  # of its kind and, under it, that kind's value. A kind that holds one
  # value has the one control of its type, called what the kind is called;
  # a kind made of fields has those fields, each with its own control, as
  # the group of a map cell has them.
  #
  # No kind is no value: the choice has an empty entry where the value may
  # be left out, and until a kind is chosen. Choosing another kind is an
  # ordinary change of the panel's form: the server renders the fields of
  # that kind in place of the others. The field says which kind the value
  # it sends was given for (`_of`), so that what was typed for one kind is
  # never taken as the value of another (`AshDataTable.Act.kind/2`).
  #
  # What the action says of the union as a whole is shown at the value where
  # the kind holds one value, which is what it is about, and under the
  # group's label otherwise.
  #
  # `held` is what the field holds, as its form sends it
  # (`AshDataTable.Act.sent/2`); `inside` is as for `group/1`.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :field, :map, required: true
  attr :held, :any, required: true
  attr :errors, :list, required: true
  attr :inside, :map, required: true
  attr :target, :any, default: nil

  defp union(assigns) do
    {member, held} =
      case Act.kind(assigns.field, assigns.held, assigns.inside.time_zone) do
        {%{cell_type: :map} = member, held} when not is_map(held) ->
          {member, Act.fresh(member, assigns.inside.time_zone)}

        {member, held} ->
          {member, held}

        nil ->
          {nil, nil}
      end

    single? = not is_nil(member) and member.cell_type != :map

    assigns =
      assign(assigns,
        member: member,
        value: held,
        kind: if(member, do: Atom.to_string(member.name), else: ""),
        single?: single?,
        own_errors: if(single?, do: [], else: assigns.errors),
        value_errors: if(single?, do: assigns.errors, else: []),
        within: %{assigns.inside | path: assigns.inside.path ++ ["_union_value"]}
      )

    ~H"""
    <div
      id={@id}
      role="group"
      aria-labelledby={"#{@id}-label"}
      aria-describedby={@own_errors != [] && "#{@id}-error"}
      data-union
    >
      <span id={"#{@id}-label"} class="label mb-1 text-base-content">
        <span data-label>{@field.label}</span>
        <span :if={@field.required?} aria-hidden="true">*</span>
        <span :if={@field.required?} class="sr-only">{Text.t(:required)}</span>
      </span>
      <div :if={@own_errors != []} id={"#{@id}-error"} class="mb-1 text-sm">
        <p :for={message <- @own_errors} data-error>{message}</p>
      </div>
      <div class="ps-4">
        <input type="hidden" name={"#{@name}[_of]"} value={@kind} />
        <div class="fieldset mb-2" data-field={Enum.join(@inside.path ++ ["_union_type"], ".")}>
          <label for={"#{@id}-kind"} class="label mb-1 text-base-content">
            <span data-label>{Text.t(:kind)}</span>
          </label>
          <select
            id={"#{@id}-kind"}
            name={"#{@name}[_union_type]"}
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
        <.field
          :if={@single?}
          id={"#{@id}-value"}
          input={@member}
          name={"#{@name}[_union_value]"}
          value={member_value(@member, @value)}
          errors={@value_errors}
          inside={@within}
          target={@target}
        />
        <.members
          :if={@member && not @single?}
          id={@id}
          name={"#{@name}[_union_value]"}
          field={@member}
          held={@value}
          inside={@within}
          target={@target}
        />
      </div>
    </div>
    """
  end

  # The inputs of one value made of fields, each a field of the panel, whose
  # id is the group's with `-f-` and its name: `ID-panel-f-client-f-name`,
  # `ID-panel-f-milestones-0-f-title`. The
  # value says that it is there with an entry of its own (`_present`), so
  # that one without inputs, or with nothing but boxes, is sent at all; and
  # sends back the primary key it came with, where that is no input: Ash
  # tells by it which value of an array is which.
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :field, :map, required: true
  attr :held, :map, required: true
  attr :inside, :map, required: true
  attr :target, :any, default: nil

  defp members(assigns) do
    ~H"""
    <input type="hidden" name={"#{@name}[_present]"} value="" />
    <input
      :for={%{key?: true, name: name} <- @field.fields}
      :if={is_binary(@held[Atom.to_string(name)])}
      type="hidden"
      name={"#{@name}[#{name}]"}
      value={@held[Atom.to_string(name)]}
    />
    <.field
      :for={%{input?: true} = inner <- @field.fields}
      id={"#{@id}-f-#{inner.name}"}
      input={inner}
      name={"#{@name}[#{inner.name}]"}
      value={member_value(inner, @held[Atom.to_string(inner.name)])}
      errors={member_errors(@inside, inner)}
      inside={
        %{
          @inside
          | place: @inside.place ++ [inner.name],
            path: @inside.path ++ [Atom.to_string(inner.name)]
        }
      }
      target={@target}
    />
    """
  end

  # What a field inside a group holds, of what its group holds: a field
  # made of groups as its form sends it, an array without the entry of its
  # own, and anything else as text.
  defp member_value(%{editor: editor}, held) when editor in [:group, :groups, :union], do: held
  defp member_value(%{cell_type: {:array, _item}}, [_own | values]), do: values
  defp member_value(%{cell_type: {:array, _item}}, _nothing), do: []
  defp member_value(_field, held) when is_binary(held), do: held
  defp member_value(_field, _nothing), do: ""

  # The errors of a field inside a group that are shown: all of them once
  # the person has used the panel's button, and until then those of the
  # fields they have been in.
  defp member_errors(inside, field) do
    path = inside.path ++ [Atom.to_string(field.name)]

    been? =
      if field.editor == :union,
        do: in_union?(inside.touched, path),
        else: path in inside.touched

    if inside.submitted? or been?,
      do: Map.get(inside.errors, inside.place ++ [field.name], []),
      else: []
  end

  # The errors about one value of an array of map cells as a whole.
  defp item_errors(inside, index) do
    if inside.submitted? or inside.path in inside.touched,
      do: Map.get(inside.errors, inside.place ++ [index], []),
      else: []
  end

  # The editor of a column's component as a field of the panel. It is given
  # what the same editor is given in a cell, with the field's value, and on
  # its control what a field of the panel has: the id its label points at,
  # the name its value is sent under, and what says that it is required or
  # has an error. The label, the mark and the messages around it stay the
  # table's.
  defp field_editor(%{input: %{component: component} = input} = assigns) do
    component.module.editor(%{
      __changed__: nil,
      value: assigns.value,
      label: input.label,
      column: component.column,
      place: :panel,
      control: %{
        "id" => assigns.id,
        "name" => assigns.name,
        "aria-required" => input.required? && "true",
        "aria-invalid" => assigns.errors != [] && "true",
        "aria-describedby" => assigns.described,
        "data-control" => true
      }
    })
  end

  defp field_type(:plain), do: "text"
  defp field_type(editor), do: Parts.Editors.input_type(editor)

  # Meaning, not drawing: it stays here until `AshDataTable.Present` takes it (stage 3a).
  #
  # What a field holds: what the person typed, once they have; else the
  # value of the record; or, for an input that has no record to take one
  # from (an argument, an attribute of a record that is being created), its
  # default. Written as the editor of its type writes it. An attribute that
  # is empty on a record is empty in the field, whatever its default.
  #
  # The field of an array holds a list: the values as they were typed, else
  # those of the record or of the default, each written as the editor of
  # its type writes it. Without any it is empty.
  def field_value(%{cell_type: {:array, _item}} = input, values, default?, panel) do
    cond do
      is_list(values) -> Format.input(input, values, panel.time_zone)
      default? and is_list(input.default) -> Format.input(input, input.default, panel.time_zone)
      true -> []
    end
  end

  def field_value(_input, typed, _default?, _panel) when is_binary(typed), do: typed

  def field_value(%{default: default} = input, nil, true, panel) when not is_nil(default),
    do: Format.input(input, default, panel.time_zone)

  def field_value(_input, nil, _default?, _panel), do: ""

  def field_value(input, value, _default?, panel),
    do: Format.input(input, value, panel.time_zone)

  # The values of a multiple choice's field that are none of its choices.
  defp boxless(%{values: values}, held) do
    choices = Enum.map(values, fn {choice, _label} -> to_string(choice) end)
    Enum.reject(held, &(&1 in choices))
  end
end
