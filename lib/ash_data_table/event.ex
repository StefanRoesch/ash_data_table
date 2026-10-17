defmodule AshDataTable.Event do
  @moduledoc """
  What a table tells the LiveView it is on, when the page asks for it with
  `notify` (`AshDataTable.attach/4`, `<AshDataTable.table>`): one message
  per event, sent to the LiveView's own process,

      {:ash_data_table, id, {event, details}}

  `id` is the id of the table on the page, whichever of the tables it shows
  the event is of. A host hears them in `handle_info/2`:

      def handle_info({:ash_data_table, "task", {:row_saved, %{key: key}}}, socket), do: ...

  `notify: true` sends every event, a list of names only those; a table
  sends nothing without it. An event is sent once what it tells has
  happened, and never for what failed.

  ## The details

  Every event's details have `table`, the id of the table it is of,
  `resource`, and for a table nested in a row `path`, the ids from the
  table on the page down to it. A picker's table sends no events. Besides:

  | Event | When | Details |
  | --- | --- | --- |
  | `:read` | a page of rows is shown | `state` (the URL parameters of the table's sort, filters, arguments and page), `count` (rows shown), `total` (nil where the action does not count) |
  | `:read_failed` | a read failed, or was refused | `message` (what the person reads), `forbidden?` |
  | `:row_saved` | a cell was saved, emptied, given a chosen record, or saved from a map cell's panel | `action`, `key`, `changed` (the columns), `record` |
  | `:row_created` | a create | `action`, `key`, `arguments`, `record` |
  | `:row_destroyed` | a destroy action on a row | `action`, `key`, `arguments` |
  | `:action_ran` | an update or a generic action on a row, a table action | `action`, `key` (nil for a table action), `arguments`, `record` or `result` |
  | `:bulk_ran` | an action on a selection is done | `action`, `arguments`, `all?`, `succeeded` and `failed` (keys) |
  | `:selection_changed` | what is selected changed: by the person, or as the table ends or narrows it | `selected` (keys, as the browser named them: claims, not read again), `all?` (every record that matches) |
  | `:row_opened` | "Open" on a row, which the page offers with `open` (sent whatever `notify` says) | `key` |
  | `:requested` | controlled mode: the table holds a request for the page to draw (`AshDataTable.requests/1`) | `ref`, `kind` (`:confirm`, `:panel` or `:picker`) |
  | `:request_ended` | controlled mode: the table holds that request no more: it was answered, given up, taken over by another, or the table closed (a nested table whose row closed) | `ref`, `kind` |
  | `:row_expanded`, `:row_collapsed` | a relationship's line under a row opened or closed | `key`, `relationship` |

  A key is a primary key as a map (`%{id: "…"}`). A record is the one the
  action returned to the person, with every `sensitive?` value in it
  replaced by `%AshDataTable.Sensitive.Masked{}`, as a row is shown; a
  generic action's `result` is scrubbed the same way, every record in it: read
  the record yourself for a sensitive field. It is nil where the record is
  no longer the person's to read. `arguments` are what the action was
  given, as typed, by name: without sensitive ones, and a file by its name
  and type (`%{filename: …, content_type: …}`), without its content. The
  list of events only grows, and an event keeps its name and what it
  carries.
  """

  alias AshDataTable.Model
  alias AshDataTable.Sensitive
  alias AshDataTable.State

  @typedoc "The name of an event."
  @type name ::
          :read
          | :read_failed
          | :row_saved
          | :row_created
          | :row_destroyed
          | :action_ran
          | :bulk_ran
          | :selection_changed
          | :row_opened
          | :requested
          | :request_ended
          | :row_expanded
          | :row_collapsed

  @typedoc "What an event says, besides `table`, `resource` and `path`."
  @type details :: %{optional(atom) => term}

  @typedoc "An event, as a table makes it."
  @type t :: {name, details}

  @names [
    :read,
    :read_failed,
    :row_saved,
    :row_created,
    :row_destroyed,
    :action_ran,
    :bulk_ran,
    :selection_changed,
    :row_opened,
    :requested,
    :request_ended,
    :row_expanded,
    :row_collapsed
  ]

  @doc "The names of the events a table sends."
  @spec names() :: [name]
  def names, do: @names

  @doc false
  # A page of rows shown: its state as the URL holds it, how many rows it
  # shows, and how many there are in all where the action counts.
  @spec read(Model.t(), State.t(), non_neg_integer, non_neg_integer | nil) :: t
  def read(model, state, count, total),
    do: {:read, %{state: State.to_params(state, model), count: count, total: total}}

  @doc false
  @spec read_failed(String.t() | nil, boolean) :: t
  def read_failed(message, forbidden?),
    do: {:read_failed, %{message: message, forbidden?: forbidden?}}

  @doc false
  # A cell saved, by the column's update action.
  @spec saved(Model.t(), Model.Column.t(), map, Ash.Resource.record() | nil) :: t
  def saved(model, column, key, record) do
    {:row_saved,
     %{
       action: column.update_action,
       key: key,
       changed: [column.name],
       record: shown(model, record)
     }}
  end

  @doc false
  # A row action, a table action or a create: what it was given (by name,
  # as `arguments/3` says), and what came of it, `record` or `value`, or
  # `gone?` for a record that is no more or not the person's to read.
  @spec ran(Model.t(), Model.Action.t(), map | nil, map, map) :: t
  def ran(model, %Model.Action{type: :create} = action, _key, given, outcome) do
    record = if outcome.gone?, do: nil, else: outcome.record

    {:row_created,
     %{
       action: action.name,
       key: record && Map.take(record, model.primary_key),
       arguments: arguments(model, action, given),
       record: shown(model, record)
     }}
  end

  def ran(model, %Model.Action{type: :destroy} = action, key, given, %{gone?: true}),
    do:
      {:row_destroyed,
       %{action: action.name, key: key, arguments: arguments(model, action, given)}}

  def ran(model, %Model.Action{type: :action} = action, key, given, outcome) do
    {:action_ran,
     %{
       action: action.name,
       key: key,
       arguments: arguments(model, action, given),
       result: Sensitive.scrub(outcome.value)
     }}
  end

  def ran(model, %Model.Action{} = action, key, given, outcome) do
    {:action_ran,
     %{
       action: action.name,
       key: key,
       arguments: arguments(model, action, given),
       record: if(outcome.gone?, do: nil, else: shown(model, outcome.record))
     }}
  end

  @doc false
  # A run on a selection that is done: what each record was given, whether
  # it was of everything that matches, and the keys it ran on and did not.
  @spec bulk(Model.t(), Model.Action.t(), :all | {:rows, list}, map, map) :: t
  def bulk(model, action, selection, given, outcome) do
    {:bulk_ran,
     %{
       action: action.name,
       arguments: arguments(model, action, given),
       all?: selection == :all,
       succeeded: outcome.succeeded,
       failed: outcome.failed
     }}
  end

  @doc false
  @spec selection([map], boolean) :: t
  def selection(keys, all?), do: {:selection_changed, %{selected: keys, all?: all?}}

  @doc false
  # What a host draws of the request a table holds in controlled mode
  # (`AshDataTable.requests/1`, which says its message terms in words),
  # each kind with fields of its own: every one its `ref`, `kind`, the
  # `table` that holds it and its `path` from the table on the page, the
  # row's primary key (`key`) and the `question`. Of a question, the action
  # and, of a cell's, its column and the value it is to be given (nil for a
  # sensitive column); of a panel, the action, a map cell's column, its
  # title, what is said of none of its fields, and its fields, each with
  # its name, label, type, whether it is required, what it holds (nil for a
  # sensitive one), the values of a choice and what is said at it; of a
  # picker, the column or field it chooses for, what it chooses from, and
  # what is held now.
  @spec request(map) :: map | nil
  def request(%{request: nil}), do: nil

  def request(%{request: %{kind: :confirm} = request} = entry) do
    entry
    |> located(request.ref, :confirm, request.key)
    |> Map.merge(%{
      action: request.action,
      column: request.column,
      value: request.value,
      question: request.question
    })
  end

  def request(%{request: %{kind: :panel, ref: ref}, panel: %{} = panel, rows: rows} = entry) do
    shown = AshDataTable.Present.panel(panel)

    entry
    |> located(ref, :panel, panel.key && get_in(rows, [panel.key, :pk]))
    |> Map.merge(%{
      action: panel.action.name,
      column: Map.get(panel, :column),
      question: shown.question,
      title: shown.title,
      errors: List.wrap(shown.errors),
      fields:
        for %{input: input} = field <- shown.fields do
          input
          |> described()
          |> Map.merge(%{
            value: if(input.sensitive?, do: nil, else: field.value),
            errors: field.errors,
            chosen:
              for {key, %{label: label}} <- field.chosen || %{} do
                %{key: key, label: label}
              end
          })
        end
    })
  end

  def request(%{request: %{kind: :picker, ref: ref}, picker: %{} = picker} = entry) do
    {key, name, current} =
      case picker.for do
        {:cell, key, name} -> {get_in(entry.rows, [key, :pk]), name, picker.current}
        {:input, name} when picker.several? -> {nil, name, held(entry.panel, name)}
        {:input, name} -> {nil, name, picker.current}
      end

    entry
    |> located(ref, :picker, key)
    |> Map.merge(%{
      column: name,
      resource: picker.reference.destination,
      several?: picker.several?,
      allow_none?: picker.allow_none?,
      current: current,
      chosen: chosen(entry.panel, name),
      question: picker.question,
      title: picker.title,
      errors: List.wrap(picker.error)
    })
  end

  def request(_entry), do: nil

  # What every request says of where it is held.
  defp located(entry, ref, kind, key),
    do: %{ref: ref, kind: kind, table: entry.id, path: entry.path, key: key}

  # What a field is, as the page draws it: its name, label, type, the
  # control it has (`editor`), whether it is required, the choices of an
  # enum; of a value made of fields its `fields`, of a union its `kinds`,
  # each described the same way.
  defp described(input) do
    own = %{
      name: input.name,
      label: input.label,
      type: input.cell_type,
      editor: input.editor,
      required?: Map.get(input, :required?, false),
      values: input.values
    }

    case input.editor do
      editor when editor in [:group, :groups] ->
        Map.put(own, :fields, for(%{input?: true} = field <- input.fields, do: described(field)))

      :union ->
        Map.put(own, :kinds, Enum.map(input.members, &described/1))

      _plain ->
        own
    end
  end

  # What a field of the panel holds that the picker is open for: the keys,
  # as the field writes them.
  defp held(%{refs: refs}, name) when is_map_key(refs, name), do: refs[name]
  defp held(%{refs: refs}, name), do: Map.get(refs, Atom.to_string(name))
  defp held(_panel, _name), do: nil

  # What the records a field of the panel holds are called, as far as the
  # table knows them: by key, the label value and its column, scrubbed.
  defp chosen(%{chosen: chosen}, name) when is_map(chosen) do
    for {key, %{label: label}} <- Map.get(chosen, name, %{}), do: %{key: key, label: label}
  end

  defp chosen(_panel, _name), do: []

  @doc false
  @spec opened(map) :: t
  def opened(key), do: {:row_opened, %{key: key}}

  @doc false
  @spec line(:row_expanded | :row_collapsed, map, atom) :: t
  def line(event, key, relationship), do: {event, %{key: key, relationship: relationship}}

  @doc false
  # What an action was given, by name: the inputs of the action and the
  # arguments the page filled, as they were given, but a sensitive one,
  # and a file without its content. A name is the action's own: nothing
  # from outside becomes an atom.
  @spec arguments(Model.t(), Model.Action.t(), map) :: %{optional(atom) => term}
  def arguments(model, action, given) do
    declared = Ash.Resource.Info.action(model.resource, action.name)

    sensitive =
      for %{sensitive?: true, name: name} <- action.inputs, do: name

    sensitive =
      sensitive ++
        for %{sensitive?: true, name: name} <- (declared && declared.arguments) || [],
            do: name

    files = for %{editor: :file, name: name} <- action.inputs, do: name
    names = Enum.map(action.inputs, & &1.name) ++ action.page_arguments

    for name <- names,
        name not in sensitive,
        {:ok, value} <- [AshDataTable.Query.given(given, name)],
        into: %{},
        do: {name, if(name in files, do: file(value), else: value)}
  end

  # A file the table gave an action: its name and type, never its content.
  defp file(%{filename: filename} = file),
    do: %{filename: filename, content_type: Map.get(file, :content_type)}

  defp file(_none), do: nil

  defp shown(_model, nil), do: nil
  defp shown(model, %_{} = record), do: Sensitive.scrub(record, model.columns)
end
