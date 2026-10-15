defmodule AshDataTable.Live.Core do
  @moduledoc false
  # The live core of a table (target.md 4.4, stage 3c): socket in, socket
  # out. What the table component's callbacks were: `mount/1`, `update/2`
  # (what the table is told), `handle_event/3` (each event parsed once by
  # `AshDataTable.Intent` and handed to the module of its topic) and
  # `handle_async/3`, each ending in `tidy/1`. Besides: the fields of the
  # table (`put/2`), who is asking (`reader/1`), what a write is given
  # (`operation/3`), the live region (`say/2`), the resource's wording as
  # the person reads it (`in_words/1`), and the tables of the page in the
  # process dictionary (`@tables`), until stage 5 makes them a registry.

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 2]

  alias AshDataTable.Caller
  alias AshDataTable.Intent
  alias AshDataTable.Listener
  alias AshDataTable.Live.Core.Bulk
  alias AshDataTable.Live.Core.Cells
  alias AshDataTable.Live.Core.Nesting
  alias AshDataTable.Live.Core.Panel
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Updates
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Query
  alias AshDataTable.State
  alias AshDataTable.Table
  alias AshDataTable.Text

  # Where the tables of a page are noted, by their ids: for each, where it
  # is (the ids from the table on the page down to its own), its listener
  # while it follows live updates, whether a panel or a picker is open in
  # it, and whether it holds rows back for something that is open. In the
  # process of the page, which every table of it runs in, and not in a
  # table: a table that told the one around it by an update would have that
  # one rendered again every time. It goes with the process.
  @tables {__MODULE__, :tables}

  def mount(socket) do
    {:ok,
     socket
     |> stream_configure(:rows, dom_id: & &1.dom_id)
     # a nested table is rendered before its first read has come back
     |> stream(:rows, [])
     # Everything the table holds, in one value: what it was told, who is
     # asking, and the table itself (`AshDataTable.Table`; every field is
     # explained where it is defined).
     |> assign(table: Table.new())}
  end

  def update(assigns, socket) do
    {:ok, socket} = told(assigns, socket)
    socket = tidy(socket)

    {:ok, if(is_map_key(assigns, :live), do: Updates.redetail(socket), else: socket)}
  end

  # Every event is parsed first (`AshDataTable.Intent`): what it asks for,
  # its values still claims, handed to the module of its topic. One whose
  # payload has another shape, and one that is not named for this table,
  # gets the answer the table gives such an event (`malformed/2`).
  def handle_event(event, params, socket) do
    {own?, plain} = addressed(event, socket.assigns.table.entry.id)

    result =
      case own? && Intent.parse(plain, params) do
        {:ok, intent} -> topic(intent).on(intent, socket)
        _another_table_or_malformed -> malformed(plain, socket)
      end

    # Every update, event and answer ends the same way: see `tidy/1`.
    case result do
      {:noreply, socket} -> {:noreply, tidy(socket)}
      {:reply, reply, socket} -> {:reply, reply, tidy(socket)}
    end
  end

  # The browser names an event with the table it is for (target.md Q4):
  # `ash_data_table:ID:event`, split at the first and the last `:`. Whether
  # it is this table's, and the event's own name.
  defp addressed(event, id) do
    case String.split(event, ":") do
      ["ash_data_table" | [_, _ | _] = rest] ->
        {ids, [plain]} = Enum.split(rest, -1)
        {Enum.join(ids, ":") == id, plain}

      _unaddressed ->
        {false, event}
    end
  end

  # The module of an intent's topic.
  defp topic(intent) when is_tuple(intent), do: topic(elem(intent, 0))

  defp topic(event)
       when event in [:sort, :filter, :clear_filter, :clear_filters, :page, :page_size],
       do: Reading

  defp topic(event) when event in [:arguments, :argument_add, :argument_remove], do: Url
  defp topic(event) when event in [:expand, :toggle], do: Nesting
  defp topic(event) when event in [:save, :clear, :reveal, :edit, :discard, :dismiss], do: Cells

  defp topic(event) when event in [:pick, :pick_input, :picked, :picker_cancel, :panel_unpick],
    do: Picker

  defp topic(event) when event in [:act, :table_act, :table_run, :create], do: Panel

  defp topic(event)
       when event in [:panel_validate, :panel_submit, :panel_add, :panel_remove] or
              event in [:panel_clear, :panel_cancel],
       do: Panel

  defp topic(event) when event in [:bulk, :bulk_run, :bulk_seen], do: Bulk
  defp topic(event) when event in [:left, :read_again], do: Updates

  def handle_async(name, result, socket) do
    {:noreply, socket} =
      case name do
        :bulk -> Bulk.handle_async(name, result, socket)
        _read_or_summary -> Reading.handle_async(name, result, socket)
      end

    socket = tidy(socket)

    # the answer to the summaries renders the table again without any of
    # its rows, as what a listener hands over does: see `redetail/1`
    {:noreply, if(name == :summary, do: Updates.redetail(socket), else: socket)}
  end

  # Puts fields of the table where each lives (`AshDataTable.Table.put/2`).
  def put(socket, fields), do: assign(socket, table: Table.put(socket.assigns.table, fields))

  # What a listener hands over (`AshDataTable.Listener`): a batch of what was
  # announced, each the action's type and the record's primary key. It is
  # looked at once this update is done (`tidy/1`).
  defp told(%{live: {:heard, batch}}, socket) do
    {:ok, put(socket, waiting: socket.assigns.table.entry.waiting ++ batch)}
  end

  # Something that was open under one of this table's rows is open no
  # longer, and the table holds a row back for it: it looks again
  # (`tidy/1`).
  defp told(%{live: :released}, socket), do: {:ok, socket}

  defp told(assigns, socket) do
    socket =
      put(
        socket,
        Map.take(
          assigns,
          [:id, :resource, :table, :scope, :actor, :tenant, :url, :label, :mounted?, :heading] ++
            [:via, :parent_key, :parent_authorize?, :depth, :depth_limit, :labelledby] ++
            [:select, :choose, :page_assigns, :parent_arguments, :lineage]
        )
      )

    # what the table was told about live updates: nil where it was told nothing
    socket = put(socket, live_given: assigns[:live?])

    # the zone of the page, nil and "UTC" being UTC
    socket =
      if Map.has_key?(assigns, :time_zone),
        do:
          put(socket,
            time_zone: AshDataTable.Zone.check!(assigns.time_zone, "The `time_zone` of the table")
          ),
        else: socket

    # Unless the table is told, it authorizes as its resource's domain says.
    # What it was told is kept as it was given, for the tables nested in it.
    socket =
      put(socket,
        authorize_given: assigns[:authorize?],
        authorize?:
          case assigns[:authorize?] do
            nil -> AshDataTable.Domain.Info.authorize?(socket.assigns.table.entry.resource)
            authorize? -> authorize?
          end
      )

    # nil is the default table, as `:default` is
    socket = put(socket, table: socket.assigns.table.entry.table || :default)

    socket =
      socket
      |> put(nested?: socket.assigns.table.entry.depth > 0)
      |> Nesting.relate()
      |> Nesting.build()

    # The table as the person asking meets it: without the columns they can
    # never see, and with the columns they can never edit read-only. Ash is
    # asked again on every update, which for a table with its state in the
    # URL is every sort, filter and page change; it costs no query.
    model =
      socket.assigns.table.entry.built.model
      |> Model.for_actor(reader(socket.assigns))
      |> Model.zoned(socket.assigns.table.caller.time_zone)
      |> in_words()
      |> Model.defaults(socket.assigns.table.options.page_assigns)

    # What the person chose for the arguments is given to Ash to look at,
    # here and before every read: the model then holds what the read action
    # and the calculations are given. What Ash refuses is not kept.
    {state, model, missing, refused} =
      Reading.settle(model, current_state(socket.assigns.table, model), reader(socket.assigns))

    # what was refused before is shown for as long as nothing else has
    # taken its place
    refused =
      socket.assigns.table.entry.refused
      |> Map.filter(fn {key, %{held: held}} -> Map.get(state.arguments, key) == held end)
      |> Map.merge(refused)

    # How deep a person can expand is said by the table on the page, for
    # everything beneath it.
    depth_limit = socket.assigns.table.entry.depth_limit || model.max_depth

    expandable? = expandable?(model, socket.assigns.table.entry.depth, depth_limit)
    selecting = selecting(socket.assigns.table.options.select, model)

    {:ok,
     socket
     |> put(model: model, state: state, editing?: Enum.any?(model.columns, & &1.editable?))
     |> put(
       pending:
         awaited(
           socket.assigns.table.entry.pending,
           socket.assigns.table.entry.state.filters,
           state.filters
         )
     )
     |> put(missing: missing, refused: refused)
     |> put(lines: lines(socket.assigns.table.entry.lines, model, state, refused))
     # whether the rows have an actions cell: the last column of the grid
     |> put(acting?: model.actions != [])
     # whether the grid has a footer row: a column of this person's has a summary
     |> put(summarised?: Model.summarised(model) != [])
     # the table actions are offered once the table has read, as create is
     |> put(offered: model.table_actions)
     |> put(depth_limit: depth_limit)
     |> put(expandable?: expandable?)
     # the column that stays in view when the table scrolls sideways
     |> put(label_column: Model.label_column(model))
     # the actions offered for the selected rows are this person's row
     # actions that run on several records
     |> put(selecting: selecting, lead: lead(selecting, expandable?))
     |> put(bulk: if(selecting == :multi, do: Model.bulk_actions(model), else: []))
     |> Nesting.creates()
     # before the read: what changes from here on is heard
     |> Updates.listen()
     |> Reading.read()}
  end

  # Whether the rows of the table can be selected, and how many at a time.
  # They can where the table was told so, and where it has something to do
  # with a selection: an action that runs on several rows. Never in a table
  # whose records have no primary key: a row that cannot be named cannot be
  # told from another.
  defp selecting(_select, %{primary_key: []}), do: nil

  defp selecting(select, _model) when select in [:multi, :single], do: select

  defp selecting(_select, model), do: if(Model.bulk_actions(model) != [], do: :multi)

  # Whether the rows of the table have an expander: there is something to
  # offer this person, the table lets its rows expand at all (`max_depth 0`
  # says never, wherever the table is shown), and the table on the page lets
  # them expand this deep.
  defp expandable?(model, depth, depth_limit),
    do: model.relationships != [] and model.max_depth > 0 and depth < depth_limit

  # The resource's own wording, as the person reads it: the labels of the
  # columns and of their values, and the questions, in the host's
  # translation where it has one. Done here, once per update and in the
  # process whose locale the host has set, so that everything rendered from
  # the model, and every message that names a column, uses the same words.
  def in_words(model) do
    columns =
      for column <- model.columns do
        label = Text.label(column.label)

        values =
          column.values &&
            Enum.map(column.values, fn {value, label} -> {value, Text.label(label)} end)

        %{
          column
          | label: label,
            confirm: column.confirm && Text.label(column.confirm),
            values: values,
            fields: fields_in_words(column.fields),
            members: fields_in_words(column.members),
            # what the column's component is told, in the same words
            component:
              column.component &&
                %{
                  column.component
                  | column: %{column.component.column | label: label, values: values}
                }
        }
      end

    # the components of the columns, by column: those of the inputs below
    # are told the same
    components =
      for %{component: %{} = component, name: name} <- columns, into: %{}, do: {name, component}

    relationships = Enum.map(model.relationships, &%{&1 | label: Text.label(&1.label)})

    # An argument is called by its label; one that a column asks for, and
    # that has no label of its own, by the column's label and its own name,
    # so that it says which column it belongs to.
    arguments =
      for argument <- model.arguments do
        label = Text.label(argument.label)

        label =
          case argument.column_label do
            nil -> label
            column -> Text.t(:argument_of, column: Text.label(column), argument: label)
          end

        values =
          argument.values &&
            Enum.map(argument.values, fn {value, label} -> {value, Text.label(label)} end)

        %{argument | label: label, column_label: nil, values: values}
      end

    # an input of an attribute the table has a column for is called what
    # that column is; the others by their own names
    action = fn action ->
      inputs =
        for input <- action.inputs do
          %{
            input
            | label: Text.label(input.label),
              values:
                input.values &&
                  Enum.map(input.values, fn {value, label} -> {value, Text.label(label)} end),
              fields: fields_in_words(input.fields),
              members: fields_in_words(input.members),
              component: input.component && Map.get(components, input.name, input.component)
          }
        end

      # the values a generic action returns are said by their labels
      returns =
        with %{values: values} = returns <- action.returns do
          %{
            returns
            | values: Enum.map(values, fn {value, label} -> {value, Text.label(label)} end)
          }
        end

      %{
        action
        | label: Text.label(action.label),
          confirm: action.confirm && Text.label(action.confirm),
          inputs: inputs,
          returns: returns
      }
    end

    # the create action is called after the resource: "New task"
    create =
      model.create &&
        %{action.(model.create) | label: Text.t(:new_record, name: Text.label(model.name))}

    %{
      model
      | columns: columns,
        arguments: arguments,
        relationships: relationships,
        actions: Enum.map(model.actions, action),
        table_actions: Enum.map(model.table_actions, action),
        create: create
    }
  end

  # The fields of a map cell, in the same words: what each is called, the
  # labels of its values, and the fields of a field that is one itself.
  defp fields_in_words(nil), do: nil

  defp fields_in_words(fields) do
    for field <- fields do
      %{
        field
        | label: Text.label(field.label),
          values:
            field.values &&
              Enum.map(field.values, fn {value, label} -> {value, Text.label(label)} end),
          fields: fields_in_words(field.fields),
          # the kinds of a union are called in the same words
          members: fields_in_words(field.members)
      }
    end
  end

  # A table whose state lives in the URL takes it from there on every update;
  # an embedded table keeps what its own events set.
  defp current_state(%{options: %{url: url}, entry: %{id: id}}, model) when is_binary(url) do
    State.from_params(model, url |> Url.query_params() |> Map.get(id))
  end

  # What it kept is fitted to the model of the person who is asking now.
  defp current_state(%{entry: %{state: state}}, model), do: State.fit(state, model)

  # What the filter row shows beside the filters that apply (`pending`),
  # when an update brings the filters: kept while they are as they were, and
  # when they are the ones the row's last change was to give, which is then
  # all they are shown among. Filters from anywhere else (the back button, a
  # link) are shown as they are.
  defp awaited(pending, filters, filters), do: pending

  defp awaited(%{among: [_before, filters]} = pending, _old, filters),
    do: %{pending | among: [filters]}

  defp awaited(_pending, _old, _filters), do: %{controls: %{}, among: []}

  # The rows of the arguments that are given value by value, as far as
  # they still say what their argument shows: an empty row holds no value,
  # so rows that differ in more than those are of another time.
  defp lines(lines, model, state, refused) do
    Map.filter(lines, fn {key, rows} ->
      case Model.argument(model, key) do
        nil ->
          false

        argument ->
          Enum.reject(rows, &(&1 == "")) == Model.Argument.shown(argument, state, refused)
      end
    end)
  end

  # Who is reading and saving.
  #
  # A table that follows live updates also says which listener is its own
  # (`origin`): what it changes itself is not announced to it, as it shows
  # what its action returned (`AshDataTable.Query.reader_opts/1`).
  def reader(assigns) do
    reader = Caller.reader_opts(assigns.table.caller)

    case assigns.table.entry.live do
      %{pid: pid} -> [origin: pid] ++ reader
      _not_listening -> reader
    end
  end

  # What is done after every update, event and answer of the table:
  #
  #   * the tables under it that it no longer renders are forgotten, and
  #     their listeners stopped (`close/1`);
  #   * what was announced is looked at (`follow/1`), which may take rows
  #     away, and so tables under them;
  #   * the table notes what the others need to know of it (`@tables`);
  #   * and when something that was open in it or under it is open no
  #     longer, the tables around it that hold a row back for that are told
  #     to look again.
  defp tidy(socket) do
    %{
      table: %{
        options: %{lineage: lineage},
        entry: %{id: id, live: live, panel: panel, picker: picker}
      },
      myself: myself
    } = socket.assigns

    before = tables()
    was_open? = match?(%{open?: true}, before[id])

    socket = socket |> close() |> Updates.follow() |> close() |> Reading.summarise()

    open? = not is_nil(panel) or not is_nil(picker)

    entry = %{
      path: lineage ++ [id],
      cid: myself,
      listener: live && live.pid,
      open?: open?,
      held?: socket.assigns.table.entry.held != []
    }

    Process.put(@tables, Map.put(tables(), id, entry))

    # something under this table that was open is gone with its table
    closed_under? =
      Enum.any?(before, fn {other, %{open?: was}} ->
        was and other != id and not is_map_key(tables(), other)
      end)

    if (was_open? and not open?) or closed_under? do
      for around <- lineage, %{held?: true, cid: cid} <- [tables()[around]] do
        send_update(cid, live: :released)
      end
    end

    socket
  end

  def tables, do: Process.get(@tables, %{})

  # Forgets the tables under this one that it no longer renders, and stops
  # their listeners: a nested table whose line or row was closed or is gone,
  # the table of a picker that was closed, and every table inside those. The
  # server is not told when a component is taken out of the page, and
  # these would listen on until the page is left.
  defp close(socket) do
    %{id: id} = socket.assigns.table.entry
    rendered = rendered(socket.assigns.table.entry)

    for {other, %{path: path, listener: listener}} <- tables(),
        other != id,
        [^id, child | _] <- [Enum.drop_while(path, &(&1 != id))],
        child not in rendered do
      if listener, do: Listener.stop(listener)
      Process.put(@tables, Map.delete(tables(), other))
    end

    socket
  end

  # The ids of the tables this table renders now: the nested tables of its
  # open lines, and the table of its picker.
  defp rendered(%{id: id, open: open, picker: picker}) do
    for({key, lines} <- open, name <- lines, do: "#{id}-row-#{key}-t-#{name}") ++
      if(picker, do: ["#{id}-pick-#{picker.name}"], else: [])
  end

  # Puts a text into the live region, to be read out.
  def say(socket, text) do
    put(socket, announcement: text, announcements: socket.assigns.table.entry.announcements + 1)
  end

  # What an event of a shape the table never sends is answered with: what
  # the hook that sends it takes as "nothing came of it". An event the table
  # does not know has no answer: it is no event of the table's.
  defp malformed(event, socket)
       when event in ~w(save clear reveal act bulk edit pick picked),
       do: {:reply, %{ok: false}, socket}

  defp malformed("expand", socket), do: {:reply, %{open: false}, socket}

  defp malformed(event, socket)
       when event in ~w(panel_add panel_remove panel_unpick panel_clear),
       do: {:reply, %{}, socket}

  defp malformed(event, socket)
       when event in ~w(sort filter clear_filter clear_filters arguments argument_add
                        argument_remove page page_size toggle table_act table_run bulk_run
                        bulk_seen panel_validate panel_submit panel_cancel pick_input
                        picker_cancel create discard dismiss left read_again),
       do: {:noreply, socket}

  # What a write is given (`AshDataTable.Operation.Input`): the intent, and
  # the table as it is now. The veto and the page values are the defaults
  # until stage 6.
  def operation(socket, intent, more \\ []) do
    %{assigns: assigns} = socket
    entry = assigns.table.entry

    parent =
      if entry.parent_key,
        do: %{
          key: entry.parent_key,
          authorize?: entry.parent_authorize?,
          arguments: entry.parent_arguments
        }

    struct!(
      %Operation.Input{
        intent: intent,
        model: entry.model,
        state: entry.state,
        parent: parent,
        opts: reader(assigns),
        picking: Picker.picking(assigns),
        rows: entry.rows,
        panel: entry.panel,
        read?: match?(%Query.Page{}, entry.page),
        offered: %{table: entry.offered, bulk: if(entry.running, do: [], else: entry.bulk)}
      },
      more
    )
  end

  # The columns before the first data column: the boxes that select a row,
  # where rows can be selected, and after them the expanders, when the rows
  # have them.
  defp lead(selecting, expandable?),
    do: if(selecting, do: 1, else: 0) + if(expandable?, do: 1, else: 0)
end
