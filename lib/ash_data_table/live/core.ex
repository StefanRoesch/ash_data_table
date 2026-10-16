defmodule AshDataTable.Live.Core do
  @moduledoc false
  # The live core of a table (target.md 4.4, stage 3c): socket in, socket
  # out. What the table component's callbacks were: `mount/1`, `update/2`
  # (what the table is told), `handle_event/3` (each event parsed once by
  # `AshDataTable.Intent` and handed to the module of its topic) and
  # `handle_async/3`, each ending in `tidy/1`. Besides: the fields of the
  # table (`put/2`), who is asking (`reader/1`), what a write is given
  # (`operation/3`), the live region (`say/2`), the resource's wording as
  # the person reads it (`in_words/1`). Every table the component shows is
  # an entry of its `AshDataTable.Table` (`AshDataTable.Live.Registry`).

  require Logger

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [put_private: 3]

  alias AshDataTable.Caller
  alias AshDataTable.Intent
  alias AshDataTable.Live.Core.Bulk
  alias AshDataTable.Live.Core.Cells
  alias AshDataTable.Live.Core.Nesting
  alias AshDataTable.Live.Core.Panel
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Selection
  alias AshDataTable.Live.Core.Updates
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Live.Registry
  alias AshDataTable.Model
  alias AshDataTable.Operation
  alias AshDataTable.Query
  alias AshDataTable.State
  alias AshDataTable.Table
  alias AshDataTable.Text

  def mount(socket) do
    # Everything the table holds, in one value: what it was told, who is
    # asking, and the table itself (`AshDataTable.Table`; every field is
    # explained where it is defined), under the assign `table` of the
    # component, which draws it with the target of its events and the
    # router of its page.
    socket =
      socket
      |> put_private(:ash_data_table, %{current: :table})
      |> assign(table: Table.new())

    {:ok, put(socket, target: socket.assigns.myself, router: socket.router)}
  end

  # What a listener hands over (`AshDataTable.Listener`): a batch of what was
  # announced, each the action's type and the record's primary key, for the
  # table whose listener it is. It is looked at once this update is done
  # (`tidy/1`). A batch for a table that is no longer shown is dropped.
  def update(%{live: {:heard, id, batch}}, socket), do: {:ok, heard(socket, id, batch)}

  def update(assigns, socket), do: {:ok, tell(socket, assigns)}

  # The same for a table attached to a LiveView (`AshDataTable.Live.Hooks`),
  # whose listener sends it the batch as a message.
  def heard(socket, id, batch) do
    if Registry.known?(socket, id) do
      socket
      |> Registry.within(id, &put(&1, waiting: table(&1).entry.waiting ++ batch))
      |> tidy()
    else
      socket
    end
  end

  # What the host asks of the table on the page (`AshDataTable.refresh/2`
  # and the other commands), and all that follows from it.
  def command(socket, fun), do: socket |> fun.() |> tidy()

  # What the table on the page is told, by the tag's attributes or by
  # `AshDataTable.attach/4`, and all that follows from it.
  def tell(socket, given) do
    {:ok, socket} = told(given, socket)
    tidy(socket)
  end

  # Every event is parsed first (`AshDataTable.Intent`): what it asks for,
  # its values still claims, handed to the module of its topic. One whose
  # payload has another shape, and one that is not named for this table,
  # gets the answer the table gives such an event (`malformed/2`).
  def handle_event(event, params, socket) do
    {id, plain} = addressed(event)

    result =
      case id && Registry.known?(socket, id) && Intent.parse(plain, params) do
        {:ok, intent} -> Registry.within(socket, id, &topic(intent).on(intent, &1))
        _another_table_or_malformed -> malformed(plain, socket)
      end

    # Every update, event and answer ends the same way: see `tidy/1`.
    case result do
      {:noreply, socket} -> {:noreply, tidy(socket)}
      {:reply, reply, socket} -> {:reply, reply, tidy(socket)}
    end
  end

  # The browser names an event with the table it is for (target.md Q4):
  # `ash_data_table:ID:event`, split at the first and the last `:`. The
  # table's id, a claim that is looked up among the tables shown (nil for
  # an event without it), and the event's own name.
  def addressed(event) do
    case String.split(event, ":") do
      ["ash_data_table" | [_, _ | _] = rest] ->
        {ids, [plain]} = Enum.split(rest, -1)
        {Enum.join(ids, ":"), plain}

      _unaddressed ->
        {nil, event}
    end
  end

  # An event named for a table that is not attached, or no longer: the
  # answer of an event of another shape (`AshDataTable.Live.Hooks`).
  def unknown(event, socket), do: malformed(event |> addressed() |> elem(1), socket)

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

  defp topic(event) when event in [:act, :open, :table_act, :table_run, :create], do: Panel

  defp topic(event)
       when event in [:panel_validate, :panel_submit, :panel_add, :panel_remove] or
              event in [:panel_clear, :panel_cancel],
       do: Panel

  defp topic(event) when event in [:bulk, :bulk_run, :bulk_seen], do: Bulk
  defp topic(:select), do: Selection
  defp topic(event) when event in [:left, :read_again], do: Updates

  # An answer for a table that is no longer shown is dropped: its tasks
  # were cancelled as it closed, and the answer of a cancelled task comes
  # all the same, maybe to a table of the same id opened since
  # (`Registry.current?/2`).
  def handle_async({:ash_data_table, id, {kind, _token}} = key, result, socket) do
    if Registry.current?(socket, key) do
      {:noreply, socket} =
        Registry.within(socket, id, fn socket ->
          case kind do
            :bulk -> Bulk.handle_async(kind, result, socket)
            _read_or_summary -> Reading.handle_async(kind, result, socket)
          end
        end)

      {:noreply, tidy(socket)}
    else
      {:noreply, socket}
    end
  end

  # The table the current callback works on: the `AshDataTable.Table` under
  # the assign whose name the socket's private data holds (`current`), as
  # `AshDataTable.Live.Registry.within/3` holds the entry it works on.
  def table(socket), do: Map.fetch!(socket.assigns, socket.private.ash_data_table.current)

  # Puts the table back whole, or fields of it where each lives
  # (`AshDataTable.Table.put/2`).
  def put(socket, %Table{} = table),
    do: assign(socket, socket.private.ash_data_table.current, table)

  def put(socket, fields), do: put(socket, Table.put(table(socket), fields))

  # What a table is told: by the host for the table on the page
  # (`update/2`), by the table it is in for any other (`Nesting.reconcile/1`).
  def told(assigns, socket) do
    socket = asker(assigns, socket)

    socket =
      put(
        socket,
        Map.take(
          assigns,
          [:id, :resource, :table, :scope, :actor, :tenant, :url, :label, :mounted?, :heading] ++
            [:via, :parent_key, :parent_authorize?, :depth, :depth_limit, :labelledby] ++
            [:select, :choose, :page_assigns, :parent_arguments] ++
            [:context, :private_arguments, :page_arguments, :before_action, :notify]
        )
      )

    # its stream, named after the table on the page: a nested table is
    # rendered before its first read has come back
    socket =
      if table(socket).entry.stream do
        socket
      else
        {stream, socket} = Registry.take_stream(socket)
        put(socket, stream: stream)
      end

    # where it is: under the tables it was told it is rendered in
    socket = put(socket, path: Map.get(assigns, :path, []) ++ [table(socket).entry.id])

    # what the table was told about live updates: nil where it was told nothing
    socket = put(socket, live_given: assigns[:live?])

    # what the page's "Open" of a row says: the table on the page's only
    socket =
      if Map.has_key?(assigns, :open),
        do: put(socket, open_label: if(length(table(socket).entry.path) == 1, do: assigns.open)),
        else: socket

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
            nil -> AshDataTable.Domain.Info.authorize?(table(socket).entry.resource)
            authorize? -> authorize?
          end
      )

    # nil is the default table, as `:default` is
    socket = put(socket, table: table(socket).entry.table || :default)

    socket =
      socket
      |> put(nested?: table(socket).entry.depth > 0)
      |> Nesting.relate()
      |> Nesting.build()

    # The table as the person asking meets it: without the columns they can
    # never see, and with the columns they can never edit read-only. Ash is
    # asked again on every update, which for a table with its state in the
    # URL is every sort, filter and page change; it costs no query.
    model =
      table(socket).entry.built.model
      |> Model.for_actor(reader(socket))
      |> Model.zoned(table(socket).caller.time_zone)
      |> in_words()
      |> Model.defaults(page_assigns(socket))

    # What the person chose for the arguments is given to Ash to look at,
    # here and before every read: the model then holds what the read action
    # and the calculations are given. What Ash refuses is not kept.
    {state, model, missing, refused} =
      Reading.settle(model, current_state(table(socket), model), reader(socket))

    # what was refused before is shown for as long as nothing else has
    # taken its place
    refused =
      table(socket).entry.refused
      |> Map.filter(fn {key, %{held: held}} -> Map.get(state.arguments, key) == held end)
      |> Map.merge(refused)

    # How deep a person can expand is said by the table on the page, for
    # everything beneath it.
    depth_limit = table(socket).entry.depth_limit || model.max_depth

    expandable? = expandable?(model, table(socket).entry.depth, depth_limit)
    selecting = selecting(table(socket).entry.select, model)

    {:ok,
     socket
     |> put(model: model, state: state, editing?: Enum.any?(model.columns, & &1.editable?))
     |> put(
       pending:
         awaited(
           table(socket).entry.pending,
           table(socket).entry.state.filters,
           state.filters
         )
     )
     |> put(missing: missing, refused: refused)
     |> put(lines: lines(table(socket).entry.lines, model, state, refused))
     # whether the rows have an actions cell: the last column of the grid,
     # for the row actions and the page's "Open"
     |> put(acting?: model.actions != [] or not is_nil(table(socket).entry.open_label))
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
  # Who is asking, with what the page gives every call to Ash for the table
  # the callback works on (`values/1`).
  def reader(%Phoenix.LiveView.Socket{} = socket),
    do: reader(table(socket)) ++ [page_values: values(socket)]

  def reader(%Table{} = table) do
    # with what the table resolved of `authorize?` for itself
    reader = [authorize?: table.entry.authorize?] ++ Caller.reader_opts(table.caller)

    case table.entry.live do
      %{pid: pid} -> [origin: pid] ++ reader
      _not_listening -> reader
    end
  end

  # When who is asking changes (another `scope`, `actor`, `tenant` or
  # `authorize?`), the table forgets what is open in it: its expanded rows
  # are put back closed and its picker goes, and the tables under them close
  # in this update (`tidy/1`), before they start a read for the new person
  # that their closing would cut off (target 6a). The table reads again.
  defp asker(assigns, socket) do
    case table(socket) do
      %{entry: %{read: nil}} -> socket
      table -> asker(assigns, socket, table)
    end
  end

  defp asker(assigns, socket, %{caller: caller, entry: entry}) do
    asking = fn assigns ->
      {Map.get(assigns, :scope, caller.scope), Map.get(assigns, :actor, caller.actor),
       Map.get(assigns, :tenant, caller.tenant),
       Map.get(assigns, :authorize?, entry.authorize_given)}
    end

    if asking.(assigns) == asking.(%{}) do
      socket
    else
      %{open: open, rows: rows} = entry

      open
      |> Map.keys()
      |> Enum.filter(&is_map_key(rows, &1))
      |> Enum.reduce(put(socket, open: %{}, picker: nil), &Reading.put_detail(&2, &1))
    end
  end

  # What is done after every update, event and answer, over every table
  # shown (`AshDataTable.Live.Registry`):
  #
  #   * the tables that are rendered are opened, and those that are not are
  #     closed (`Nesting.reconcile/1`), with their listeners and tasks;
  #   * what was announced is looked at, and the rows held back for what was
  #     open under them are looked at again (`follow/1`), parents first: a
  #     row whose panel or picker closed, here or in a table under it, is
  #     let go in the same render. It may take rows away, and so tables
  #     under them, which are closed;
  #   * a selection made under other filters is given up (`Selection.scoped/1`);
  #   * the summaries that are due are asked for.
  defp tidy(socket) do
    socket
    |> Nesting.reconcile()
    |> each(&Updates.follow/1)
    |> Nesting.reconcile()
    |> each(&Selection.scoped/1)
    |> each(&Reading.summarise/1)
  end

  # Runs `fun` on every table shown, parents first.
  defp each(socket, fun) do
    table(socket).entries
    |> Map.values()
    |> Enum.sort_by(&{length(&1.path), &1.id})
    |> Enum.reduce(fun.(socket), fn %{id: id}, socket ->
      if is_map_key(table(socket).entries, id),
        do: Registry.within(socket, id, fun),
        else: socket
    end)
  end

  # What a default of an asked argument and a function of the page are
  # given (stage 4 D9, stage 6 D5): the assigns the tag was given, or for a
  # table attached to a LiveView its assigns as they are now, as LiveView
  # gives them (`socket.assigns`, a field of `Phoenix.LiveView.Socket.t`).
  def page_assigns(socket) do
    case table(socket).options.page_assigns do
      :socket -> socket.assigns
      assigns -> assigns
    end
  end

  # What the page gives every call to Ash for the table the callback works
  # on, as its functions say now (stage 6 D5): `context`, `private_arguments`
  # and `page_arguments`, each a map, or a function of the page's assigns and
  # of which table asks (`%{table: id, path: path, resource: resource}`).
  # Called in the LiveView's process, before any read or write starts; a
  # change of what they return reads nothing again by itself.
  def values(socket) do
    %{caller: caller, entry: entry} = table(socket)
    assigns = page_assigns(socket)
    ref = %{table: entry.id, path: entry.path, resource: entry.resource}

    %{
      context: value(caller.context, :context, assigns, ref),
      private_arguments: value(caller.private_arguments, :private_arguments, assigns, ref),
      page_arguments: value(caller.page_arguments, :page_arguments, assigns, ref)
    }
  end

  defp value(nil, _name, _assigns, _ref), do: %{}
  defp value(%{} = given, _name, _assigns, _ref), do: given

  defp value(fun, name, assigns, ref) do
    case called(name, fn ->
           if is_function(fun, 1), do: fun.(assigns), else: fun.(assigns, ref)
         end) do
      %{} = given ->
        given

      other ->
        raise ArgumentError,
              "the `#{name}` function of the table returned #{inspect(other, limit: 5)}; it " <>
                "returns a map"
    end
  end

  defp called(name, fun) do
    fun.()
  rescue
    error ->
      reraise ArgumentError,
              [
                message:
                  "the `#{name}` function of the table raised: " <> Exception.message(error)
              ],
              __STACKTRACE__
  end

  # The page's veto, as `AshDataTable.Operation` asks it (stage 6 D9): a
  # function of the request, which holds the page's assigns as they are now
  # and says which table asks. It answers `:cont` or `{:halt, message}`;
  # any other answer raises, as a veto that answers `:ok` would otherwise
  # refuse every write without a word.
  def veto(socket) do
    %{caller: %{before_action: before}, entry: entry} = table(socket)
    assigns = page_assigns(socket)

    fn request ->
      request = %{request | table: entry.id, path: entry.path}

      case answer(before, request, assigns) do
        :cont ->
          :cont

        {:halt, message} when is_binary(message) ->
          {:halt, message}

        other ->
          raise ArgumentError,
                "the `before_action` of the table answered #{inspect(other, limit: 5)}; it " <>
                  "answers `:cont`, or `{:halt, message}` with the message as a string"
      end
    end
  end

  defp answer(nil, _request, _assigns), do: :cont
  defp answer(fun, request, _assigns) when is_function(fun, 1), do: fun.(request)
  defp answer(fun, request, assigns), do: fun.(request, assigns)

  # Puts a text into the live region, to be read out.
  def say(socket, text) do
    put(socket, announcement: text, announcements: table(socket).entry.announcements + 1)
  end

  # What an event of a shape the table never sends is answered with: what
  # the hook that sends it takes as "nothing came of it". An event the table
  # does not know has no answer.
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
                        bulk_seen select panel_validate panel_submit panel_cancel pick_input
                        picker_cancel create open discard dismiss left read_again),
       do: {:noreply, socket}

  # A name the table has no event of: nothing is done, and nothing is
  # answered. Only a browser that was changed sends one.
  defp malformed(event, socket) do
    Logger.debug("ash_data_table: an event no table has was ignored: #{inspect(event)}")
    {:noreply, socket}
  end

  # What a write is given (`AshDataTable.Operation.Input`): the intent, the
  # table as it is now, and the page's veto and values, made now.
  def operation(socket, intent, more \\ []) do
    table = table(socket)
    entry = table.entry

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
        opts: reader(table),
        veto: veto(socket),
        page_values: values(socket),
        picking: Picker.picking(table),
        rows: entry.rows,
        panel: entry.panel,
        selection: if(entry.all?, do: :all, else: {:rows, entry.selected}),
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
