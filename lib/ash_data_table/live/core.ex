defmodule AshDataTable.Live.Core do
  @moduledoc false
  # The live core of a table, in two halves.
  #
  # The step, over the table: `step/3`, `(table, intent, context)` →
  # `{table, effects, reply}`, with no socket. `context` is what the socket
  # gives (`context/1`: its assigns, LiveView's uploads, whether the page
  # is connected, its endpoint); the effects are data (below); the reply
  # is what the hook is answered (nil for none). An intent is a browser's
  # (`AshDataTable.Intent`, run within the table it names), a host's answer
  # or command, or the core's own: what a table is told (`{:told, …}`), a
  # listener's batch (`{:heard, …}`), a task's answer (`{:task, …}`), the
  # files of a panel consumed (`{:consumed, …}`), and `:tidy`, which every
  # callback ends with. Each runs through the module of its topic
  # (`topic/1`), whose `step/2` clause is `(intent, table)` → `{table,
  # reply}`: the table holds the step's context (`table.context`) and
  # gathers its effects (`effect/2`), as LiveView's socket gathers the
  # events it pushes. Besides: who is asking (`reader/1`), what a write is
  # given (`operation/3`), the live region (`say/2`), what the host is told
  # (`notify/3`).
  #
  # The adapter, on the socket: the callbacks of the tag's component and
  # the hooks of an attached table, each the step of what came (`mount/1`,
  # `update/2`, `handle_event/3`, `handle_async/3`, `heard/3`, `tell/2`,
  # `command/2`), then the step `:tidy`, each step's table put and its
  # effects applied (`effects/2`) in their order:
  #
  #   * `{:push, event, payload}`: an event to the hooks (`push_event/3`),
  #     and a file for the browser to save (`download/2`);
  #   * `{:tell, top, message}`: an event to the host, sent to the
  #     LiveView's own process (`AshDataTable.Live.Core.Notify`);
  #   * `{:patch, url}`, `{:redirect, url}`: the URL of a table whose state
  #     is in it, and a page that is gone;
  #   * `{:stream, op}`: the stream of a table, `{:configure, name}`,
  #     `{:reset, name, items}`, `{:insert, name, item, opts}`,
  #     `{:delete, name, dom_id}`;
  #   * `{:async, key, fun}`: a task beside the process (`start_async/3`),
  #     which finishes its query whatever happens meanwhile
  #     (`Registry.finishing/1`); its answer comes back as `{:task, key,
  #     result}`. `{:async, key, fun, files}` gives the task temporary
  #     files of this process before its work starts (`Registry.owned/1`);
  #   * `{:uploads, op}`: the uploads of a panel's file fields,
  #     `{:allow, name, opts}`, `{:drop, names, spent}` (the files no action
  #     was given), `{:close, names}` (a table that closes), and
  #     `{:consume, id, files, panel, write}`: the files of a panel's
  #     submit, consumed one inside the other, and inside the last the
  #     intent `{:consumed, panel, write, files}` of the table `id`, which
  #     runs the rest of the write while LiveView holds them (see
  #     `AshDataTable.Live.Core.Panel`).

  require Logger

  import Phoenix.Component, only: [assign: 3]

  import Phoenix.LiveView,
    only: [
      allow_upload: 3,
      cancel_upload: 3,
      connected?: 1,
      consume_uploaded_entry: 3,
      disallow_upload: 2,
      push_event: 3,
      push_patch: 2,
      put_private: 3,
      redirect: 2,
      start_async: 3,
      stream: 4,
      stream_configure: 3,
      stream_delete_by_dom_id: 3,
      stream_insert: 4
    ]

  alias AshDataTable.Caller
  alias AshDataTable.Download
  alias AshDataTable.Intent
  alias AshDataTable.Live.Core.Bulk
  alias AshDataTable.Live.Core.Cells
  alias AshDataTable.Live.Core.Nesting
  alias AshDataTable.Live.Core.Notify
  alias AshDataTable.Live.Core.Opener
  alias AshDataTable.Live.Core.Panel
  alias AshDataTable.Live.Core.Picker
  alias AshDataTable.Live.Core.Reading
  alias AshDataTable.Live.Core.Selection
  alias AshDataTable.Live.Core.Told
  alias AshDataTable.Live.Core.Updates
  alias AshDataTable.Live.Core.Url
  alias AshDataTable.Live.Registry
  alias AshDataTable.Operation
  alias AshDataTable.Query
  alias AshDataTable.Table

  # the page's values of the callback that runs, by the table that asks (`callback/2`)
  @values {__MODULE__, :page_values}

  # ---- the adapter: the socket ------------------------------------------

  def mount(socket) do
    # Everything the table holds, in one value: what it was told, who is
    # asking, and the table itself (`AshDataTable.Table`; every field is
    # explained where it is defined), under the assign `table` of the
    # component, which draws it with the target of its events and the
    # router of its page.
    table = Table.put(Table.new(), target: socket.assigns.myself, router: socket.router)

    {:ok,
     socket
     |> put_private(:ash_data_table, %{current: :table})
     |> assign(:table, table)}
  end

  # What a listener hands over (`AshDataTable.Listener`): a batch of what was
  # announced, for the table whose listener it is. A batch for a table that
  # is no longer shown is dropped.
  def update(%{live: {:heard, id, batch}}, socket), do: {:ok, heard(socket, id, batch)}

  # What the table on the page is told by the tag's attributes.
  def update(assigns, socket), do: {:ok, tell(socket, assigns)}

  # The same for a table attached to a LiveView (`AshDataTable.Live.Hooks`),
  # whose listener sends it the batch as a message.
  def heard(socket, id, batch), do: socket |> callback({:to, id, {:heard, batch}}) |> elem(0)

  # What the table on the page is told, by the tag's attributes or by
  # `AshDataTable.attach/4`, and all that follows from it.
  def tell(socket, given), do: socket |> callback({:told, given}) |> elem(0)

  # What the host asks of the table on the page (`AshDataTable.refresh/2`
  # and the other commands, the answers to its requests): the socket, or
  # `{:reply, reply, socket}` where the command answers.
  def command(socket, intent) do
    case callback(socket, intent) do
      {socket, nil} -> socket
      {socket, reply} -> {:reply, reply, socket}
    end
  end

  # Every event of the browser, with the table it is named for.
  def handle_event(event, params, socket) do
    case callback(socket, {:event, event, params}) do
      {socket, nil} -> {:noreply, socket}
      {socket, reply} -> {:reply, reply, socket}
    end
  end

  # The answer of a task of a table (`{:async, …}`).
  def handle_async(key, result, socket),
    do: {:noreply, socket |> callback({:task, key, result}) |> elem(0)}

  # Every table closes, the one on the page too (`AshDataTable.detach/2`):
  # nothing is tidied after, as nothing is shown any more.
  def detach(socket), do: socket |> callback(:close_all, false) |> elem(0)

  # An event named for a table that is not attached, or no longer: the
  # answer of an event of another shape (`AshDataTable.Live.Hooks`).
  def unknown(event, socket) do
    case malformed(event |> addressed() |> elem(1)) do
      nil -> {:noreply, socket}
      reply -> {:reply, reply, socket}
    end
  end

  # One callback of the LiveView: the step of what came, then `:tidy`, each
  # step's table put and its effects applied. The page's values are called
  # once in it for each table that asks (`values/1`), and forgotten when it
  # ends, also when it raises. A callback inside another (a command a hook
  # of the page gives while the table's own runs) shares the outer one's.
  defp callback(socket, intent, tidy? \\ true) do
    once(fn ->
      {socket, reply} = stepped(socket, intent)
      socket = if tidy?, do: socket |> stepped(:tidy) |> elem(0), else: socket
      {socket, reply}
    end)
  end

  defp once(fun) do
    case Process.get(@values) do
      nil ->
        Process.put(@values, %{})

        try do
          fun.()
        after
          Process.delete(@values)
        end

      %{} ->
        fun.()
    end
  end

  # The step of `intent` over the socket's table, its table put back and
  # its effects applied: `{socket, reply}`.
  defp stepped(socket, intent) do
    {table, effects, reply} = step(table(socket), intent, context(socket))
    {socket |> put(table) |> effects(effects), reply}
  end

  # What a step is given of the socket: its assigns (the page's, for a
  # table attached to a LiveView, `page_assigns/1`), the uploads LiveView
  # knows (`%{}` for none), whether the page is connected, and its endpoint.
  def context(socket) do
    %{
      assigns: socket.assigns,
      uploads: socket.assigns[:uploads] || %{},
      connected?: connected?(socket),
      endpoint: socket.endpoint
    }
  end

  # The table the callback works on: the `AshDataTable.Table` under the
  # assign whose name the socket's private data holds (`current`).
  defp table(socket), do: Map.fetch!(socket.assigns, socket.private.ash_data_table.current)

  defp put(socket, %Table{} = table),
    do: assign(socket, socket.private.ash_data_table.current, table)

  # Applies the effects of a step to the socket, in their order (see the top).
  def effects(socket, effects), do: Enum.reduce(effects, socket, &applied/2)

  defp applied({:push, event, payload}, socket), do: push_event(socket, event, payload)

  defp applied({:tell, top, message}, socket) do
    send(self(), {:ash_data_table, top, message})
    socket
  end

  defp applied({:patch, url}, socket), do: push_patch(socket, to: url)
  defp applied({:redirect, url}, socket), do: redirect(socket, to: url)

  # `stream_configure/3` cannot be undone: a name is configured once
  # (`Registry.take_stream/1`)
  defp applied({:stream, {:configure, name}}, socket),
    do: stream_configure(socket, name, dom_id: & &1.dom_id)

  defp applied({:stream, {:reset, name, items}}, socket),
    do: stream(socket, name, items, reset: true)

  defp applied({:stream, {:insert, name, item, opts}}, socket),
    do: stream_insert(socket, name, item, opts)

  defp applied({:stream, {:delete, name, dom_id}}, socket),
    do: stream_delete_by_dom_id(socket, name, dom_id)

  defp applied({:async, key, fun}, socket),
    do: start_async(socket, key, Registry.finishing(fun))

  # A run that is given files of this process (#66): they are its own
  # before its work starts and before this callback is over
  # (`Registry.owned/1`).
  defp applied({:async, key, fun, files}, socket) do
    {task, hand_over} = Registry.owned(fun)
    socket = start_async(socket, key, Registry.finishing(task))
    hand_over.(files)
    socket
  end

  # allowed once, and again after a table of the same id closed and gave
  # it up; this table's either way, also when the table before it could
  # not give it up
  defp applied({:uploads, {:allow, name, opts}}, socket) do
    if match?(%{^name => %{allowed?: true}}, socket.assigns[:uploads] || %{}),
      do: socket,
      else: allow_upload(socket, name, opts)
  end

  # the files a person chose and no action was given (`Core.Files.allowed/1`)
  defp applied({:uploads, {:drop, names, spent}}, socket) do
    uploads = socket.assigns[:uploads] || %{}

    for name <- names,
        %{entries: entries} <- [uploads[name]],
        entry <- entries,
        not entry.cancelled? and entry.ref not in spent,
        reduce: socket do
      socket -> cancel_upload(socket, name, entry.ref)
    end
  end

  # An upload with entries cannot be given up: they are cancelled first.
  # One that is being sent is only told to stop, and is there until it
  # has: LiveView refuses to give up its upload till then.
  defp applied({:uploads, {:close, names}}, socket) do
    Enum.reduce(names, socket, fn name, socket ->
      case socket.assigns[:uploads] do
        %{^name => %{entries: entries}} ->
          socket = Enum.reduce(entries, socket, &cancel_upload(&2, name, &1.ref))

          if socket.assigns.uploads[name].entries == [],
            do: disallow_upload(socket, name),
            else: socket

        _gone ->
          socket
      end
    end)
  end

  defp applied({:uploads, {:consume, id, files, panel, write}}, socket),
    do: consume(socket, id, files, %{}, panel, write)

  # Each file in turn, consumed by LiveView (`consume_uploaded_entry/3`),
  # given as a `Plug.Upload`, which is what Ash takes for a file from a web
  # request: the path LiveView wrote it to, the name the browser gave (a
  # name, never a way to somewhere), its content type. Inside the last, the
  # step of `{:consumed, panel, write, files}` of the table `id`: the write
  # goes on while LiveView holds the files, and LiveView takes them away
  # when this returns. Its table and effects are what the socket comes to.
  defp consume(socket, id, [], files, panel, write),
    do: socket |> stepped({:to, id, {:consumed, panel, write, files}}) |> elem(0)

  defp consume(socket, id, [{name, entry} | rest], files, panel, write) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      file = %Plug.Upload{
        path: path,
        filename: Path.basename(entry.client_name),
        content_type: entry.client_type
      }

      {:ok, consume(socket, id, rest, Map.put(files, name, file), panel, write)}
    end)
  end

  # ---- the step: over the table ---------------------------------------

  @doc """
  The step of `intent` over `table` with what the socket gives (`context`):
  the table as it is then, the effects to apply (`effects/2`) and the reply
  to the hook (nil for none). No socket: a step reads through Ash and calls
  the page's functions, nothing else.
  """
  def step(%Table{} = table, intent, context) do
    {table, reply} = run(intent, %{table | context: context, effects: []})
    {%{table | context: nil, effects: []}, Enum.reverse(table.effects), reply}
  end

  @doc """
  Adds an effect, or a list of them in their order, to what the step gives
  back.
  """
  def effect(%Table{effects: effects} = table, list) when is_list(list),
    do: %{table | effects: Enum.reverse(list, effects)}

  def effect(%Table{effects: effects} = table, effect),
    do: %{table | effects: [effect | effects]}

  @doc """
  Runs an intent within the table: `{table, reply}`. What a step is, and
  what a topic hands on (a run on the selection its panel started,
  `{:bulk_start, …}`; Cancel of what the host held, `Opener.Host`).
  """
  # Every event of the browser is parsed first (`AshDataTable.Intent`): what
  # it asks for, its values still claims, run within the table it is named
  # for. One whose payload has another shape, and one that is not named for
  # a table shown, gets the answer the table gives such an event
  # (`malformed/1`).
  def run({:event, event, params}, table) do
    {id, plain} = addressed(event)

    case id && Registry.known?(table, id) && Intent.parse(plain, params) do
      {:ok, intent} -> Registry.within(table, id, &run(intent, &1))
      _another_table_or_malformed -> {table, malformed(plain)}
    end
  end

  # An intent of the table `id`, run within it; nothing for a table that is
  # no longer shown.
  def run({:to, id, intent}, table) do
    if Registry.known?(table, id),
      do: Registry.within(table, id, &run(intent, &1)),
      else: {table, nil}
  end

  # The answer of a task. One for a table that is no longer shown is
  # dropped here: its tasks were not stopped as it closed, but finish their
  # query (`Registry.finishing/1`), and answer all the same, maybe to a
  # table of the same id opened since (`Registry.current?/2`).
  def run({:task, {:ash_data_table, id, {kind, _token}} = key, result}, table) do
    if Registry.current?(table, key),
      do: Registry.within(table, id, &run({:async, kind, result}, &1)),
      else: {table, nil}
  end

  def run(:tidy, table), do: {tidy(table), nil}

  def run(:close_all, table), do: {Registry.close_all(table), nil}

  # The answers of the host to what a table holds for it (controlled mode,
  # `AshDataTable.confirm_request/3` and the other commands): the request
  # `ref`, where the table that holds it holds it as one of `kinds`. Each
  # table shown is asked (`Opener.answer/3`); the one that holds it gives
  # the intent `answer` makes of it, which runs within that table through
  # the module of its topic, as a browser's does, and what came of it is
  # told (`Opener.Host.replied/4`: only the host answers); nil runs
  # nothing. A stale or forged `ref` does nothing.
  def run({:answer, ref, kinds, answer}, table) do
    answered =
      each(table, fn table ->
        case Opener.answer(table, ref, {kinds, answer}) do
          {:ok, nil, table} ->
            table

          {:ok, intent, table} ->
            {table, reply} = run(intent, table)
            Opener.Host.replied(table, ref, intent, reply)

          :none ->
            table
        end
      end)

    {answered, nil}
  end

  def run(intent, table), do: topic(intent).step(intent, table)

  # The module of an intent's topic. A host's Confirm (`{:confirmed,
  # intent}`) is of the intent's.
  defp topic({:confirmed, intent}), do: topic(intent)
  defp topic({:async, :bulk, _result}), do: Bulk
  defp topic({:async, _read_or_summary, _result}), do: Reading
  defp topic(intent) when is_tuple(intent), do: topic(elem(intent, 0))

  defp topic(event)
       when event in [:sort, :filter, :clear_filter, :clear_filters, :filter_values, :page] or
              event in [:page_size, :refresh],
       do: Reading

  defp topic(event) when event in [:arguments, :argument_add, :argument_remove, :put_state],
    do: Url

  defp topic(event) when event in [:expand, :toggle], do: Nesting
  defp topic(event) when event in [:save, :clear, :reveal, :edit, :discard, :dismiss], do: Cells

  defp topic(event)
       when event in [:pick, :pick_input, :picked, :picker_cancel, :panel_unpick, :chosen] or
              event == :refer,
       do: Picker

  defp topic(event) when event in [:act, :open, :table_act, :table_run, :create], do: Panel

  defp topic(event)
       when event in [:panel_validate, :panel_submit, :panel_add, :panel_remove] or
              event in [:panel_clear, :panel_cancel, :consumed],
       do: Panel

  defp topic(event) when event in [:bulk, :bulk_run, :bulk_seen, :bulk_start], do: Bulk
  defp topic(event) when event in [:select, :clear_selection, :selected_records], do: Selection
  defp topic(event) when event in [:left, :read_again, :heard], do: Updates
  defp topic(:told), do: Told

  # The browser names an event with the table it is for:
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
  #   * what draws the panel and the picker is told whether each is open
  #     (`Opener.opened/3`): in controlled mode one is held or let go as a
  #     request, in every table;
  #   * the summaries that are due are asked for.
  defp tidy(table) do
    table
    |> Nesting.reconcile()
    |> each(&Updates.follow/1)
    |> Nesting.reconcile()
    |> each(&Selection.scoped/1)
    |> each(&Nesting.counted/1)
    |> each(&opened/1)
    |> each(&Reading.summarise/1)
  end

  # The panel and the picker, as what draws them is told (the panel
  # first: a picker the host draws comes before it).
  defp opened(table) do
    %{panel: panel, picker: picker} = table.entry
    table |> Opener.opened(:panel, panel) |> Opener.opened(:picker, picker)
  end

  # Runs `fun` on every table shown, parents first.
  defp each(table, fun) do
    table.entries
    |> Map.values()
    |> Enum.sort_by(&{length(&1.path), &1.id})
    |> Enum.reduce(fun.(table), fn %{id: id}, table ->
      if is_map_key(table.entries, id),
        do: Registry.within(table, id, fun),
        else: table
    end)
  end

  # What an event of a shape the table never sends is answered with: what
  # the hook that sends it takes as "nothing came of it"; nil for no
  # answer. An event the table does not know has no answer.
  defp malformed(event) when event in ~w(save clear reveal act bulk edit pick picked),
    do: %{ok: false}

  defp malformed("expand"), do: %{open: false}

  defp malformed(event) when event in ~w(panel_add panel_remove panel_unpick panel_clear),
    do: %{}

  defp malformed(event)
       when event in ~w(sort filter clear_filter clear_filters filter_values arguments argument_add
                        argument_remove page page_size toggle table_act table_run bulk_run
                        bulk_seen select panel_validate panel_submit panel_cancel pick_input
                        picker_cancel create open discard dismiss left read_again),
       do: nil

  # A name the table has no event of: nothing is done, and nothing is
  # answered. Only a browser that was changed sends one.
  defp malformed(event) do
    Logger.debug("ash_data_table: an event no table has was ignored: #{inspect(event)}")
    nil
  end

  @doc "Puts a text into the live region, to be read out."
  def say(%Table{} = table, text),
    do: Table.put(table, announcement: text, announcements: table.entry.announcements + 1)

  @doc """
  Tells the host `event` of the table, where the page asked for it
  (`Notify.told/3`): an effect; `always?` whatever `notify` says.
  """
  def notify(%Table{} = table, event, always? \\ false),
    do: effect(table, Notify.told(table, event, always?))

  @doc """
  Sends the page a file a generic action returned, for the person's
  browser to save (`AshDataTable.Download`, nil for none): the effect
  `{:push, "ash_data_table:download", …}`, which the library's own window
  listener hears (`assets/js/download.js`), whatever draws the table. It
  goes with the step's effects and stays nowhere: not in the table, not in
  an assign.
  """
  def download(%Table{} = table, nil), do: table

  def download(%Table{} = table, %Download{} = download),
    do:
      effect(
        table,
        {:push, "ash_data_table:download", Download.pushed(download, table.entry.id)}
      )

  # Who is reading and saving, with what the page gives every call to Ash
  # for the table (`values/1`).
  #
  # A table that follows live updates also says which listener is its own
  # (`origin`): what it changes itself is not announced to it, as it shows
  # what its action returned (`AshDataTable.Query.reader_opts/1`).
  def reader(%Table{} = table) do
    # with what the table resolved of `authorize?` for itself
    reader = [authorize?: table.entry.authorize?] ++ Caller.reader_opts(table.caller)

    reader =
      case table.entry.updates.live do
        %{pid: pid} -> [origin: pid] ++ reader
        _not_listening -> reader
      end

    reader ++ [page_values: values(table)]
  end

  # What a default of an asked argument and a function of the page are
  # given: the assigns the tag was given, or for a table attached to a
  # LiveView its assigns as they are now, as LiveView gives them (the
  # step's `context`, `socket.assigns`, a field of
  # `Phoenix.LiveView.Socket.t`).
  def page_assigns(%Table{options: %{page_assigns: :socket}, context: context}),
    do: context.assigns

  def page_assigns(%Table{options: %{page_assigns: assigns}}), do: assigns

  # What the page gives every call to Ash for the table, as its functions
  # say now: `context`, `private_arguments` and `page_arguments`, each a
  # map, or a function of the page's assigns and of which table asks
  # (`%{table: id, path: path, resource: resource}`). Called in the
  # LiveView's process, before any read or write starts; a change of what
  # they return reads nothing again by itself.
  #
  # Each function is called once per callback and table (`callback/2`): the
  # reads and the write of one event are given the same values.
  def values(%Table{entry: entry} = table) do
    ref = %{table: entry.id, path: entry.path, resource: entry.resource}

    case Process.get(@values) do
      %{^ref => values} ->
        values

      %{} = known ->
        values = values(table, page_assigns(table), ref)
        Process.put(@values, Map.put(known, ref, values))
        values

      nil ->
        values(table, page_assigns(table), ref)
    end
  end

  defp values(%Table{caller: caller}, assigns, ref) do
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

  # The page's veto, as `AshDataTable.Operation` asks it: a function of the
  # request, which holds the page's assigns as they are now and says which
  # table asks. It answers `:cont` or `{:halt, message}`; any other answer
  # raises, as a veto that answers `:ok` would otherwise refuse every write
  # without a word.
  def veto(%Table{caller: %{before_action: before}, entry: entry} = table) do
    assigns = page_assigns(table)

    fn request ->
      request = %{request | table: entry.id, path: entry.path}

      case vetoed(before, request, assigns) do
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

  defp vetoed(nil, _request, _assigns), do: :cont
  defp vetoed(fun, request, _assigns) when is_function(fun, 1), do: fun.(request)
  defp vetoed(fun, request, assigns), do: fun.(request, assigns)

  # What a write is given (`AshDataTable.Operation.Input`): the intent, the
  # table as it is now, and the page's veto and values, made now of the
  # step's context.
  def operation(%Table{} = table, intent, more \\ []) do
    entry = table.entry

    parent =
      if entry.parent_key,
        do: %{
          key: entry.parent_key,
          authorize?: entry.parent_authorize?,
          arguments: entry.arguments.parent_arguments
        }

    struct!(
      %Operation.Input{
        intent: intent,
        model: entry.model,
        state: entry.state,
        parent: parent,
        opts: reader(table),
        veto: veto(table),
        page_values: values(table),
        picking: Picker.picking(table),
        rows: entry.rows,
        selection: if(entry.selection.all?, do: :all, else: {:rows, entry.selection.selected}),
        read?: match?(%Query.Page{}, entry.page),
        offered: %{
          table: entry.offered,
          bulk: if(entry.selection.running, do: [], else: entry.selection.bulk)
        }
      },
      more
    )
  end
end
