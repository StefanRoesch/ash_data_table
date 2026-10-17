# Events and commands

A table can tell the page it is on what happened in it, and the page can
tell the table what to do. After reading this guide you can hear a table's
events, give it commands, hand every call it makes to Ash values that only
the server knows, and stop a write before it runs.

| | What it is | Mounted | Embedded | Attached |
| --- | --- | --- | --- | --- |
| [Events](#what-the-page-hears) | The table tells the page what happened | in an `on_mount` hook | yes | yes |
| ["Open"](#open-on-every-row) | A button on every row that tells the page | yes | yes | yes |
| [Page values](#page-values) | `context`, `private_arguments`, `page_arguments`, for every call to Ash | on the router line | yes | yes |
| [The veto](#the-veto) | `before_action`, asked before every write | on the router line | yes | yes |
| [Commands](#commands) | The page tells the table what to do | in an `on_mount` hook | no | yes |

The three ways of placing a table are in
[Layout and embedding](layout-and-embedding.md). None of this lets a page
skip a check of the table's: a write still runs only through the table's own
checks, the record read again as the person, and Ash's policies.

## What the page hears

With `notify`, a table sends the LiveView it is on one message per event:

<!-- sketch -->
```elixir
{:ash_data_table, id, {event, details}}
```

`id` is the id of the table on the page, whichever of the tables it shows
the event is of. `notify: true` sends every event, a list of names only
those. Without `notify` the table sends none, so a LiveView whose
`handle_info/2` has no clause for them is safe.

| Event | When |
| --- | --- |
| `:read` | A page of rows is shown. |
| `:read_failed` | A read failed, or was refused. |
| `:row_saved` | A cell was saved, emptied, given a chosen record, or saved from the side panel. |
| `:row_created` | A create ran. |
| `:row_destroyed` | A destroy action ran on a row. |
| `:action_ran` | An update or generic action ran on a row, or a table action ran. |
| `:bulk_ran` | An action on the selected rows is done. |
| `:selection_changed` | What is selected changed. |
| `:row_opened` | "Open" was used on a row (see below). |
| `:requested`, `:request_ended` | [Controlled mode](controlled-mode.md): a request is waiting, or is held no more. |
| `:row_expanded`, `:row_collapsed` | A relationship's line under a row opened or closed. |

`AshDataTable.Event` lists the details of each. Every event's details have
`table` (the id of the table it is of) and `resource`, and an event of a
table nested in a row has `path`, the ids from the table on the page down to
it. A picker's table sends no events.

An event is sent once what it tells has happened, and never for what failed.
A record in its details is the one the action returned to the person, with
every `sensitive?` value replaced by `%AshDataTable.Sensitive.Masked{}`;
`arguments` leave out sensitive ones, and a file is given by its name and
type. A key is a primary key as a map, `%{id: "…"}`. The keys of
`:selection_changed` are what the browser named: claims, not records read
again. Use `selected_records/2` (below) for the records.

### On a page of your own

A LiveView of yours hears them in `handle_info/2`. A page of the demo's
browser tests attaches the tasks with an "Open" button and shows the key of
the row opened last
([`demo/e2e/server/opened_live.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/e2e/server/opened_live.ex)):

<!-- source: demo/e2e/server/opened_live.ex -->
```elixir
@impl true
def handle_info({:ash_data_table, "task", {:row_opened, %{key: %{id: id}}}}, socket),
  do: {:noreply, assign(socket, opened: id)}
```

The tag takes `notify` as an attribute, `attach/4` as an option:
`notify={[:read, :row_saved]}`, `notify: true`.

### On a mounted page

The router page is the library's LiveView, so your code runs in the
`on_mount` hooks of its `live_session`. A hook hears the events with
`Phoenix.LiveView.attach_hook/4` on `:handle_info`. From the demo's tests
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)
and
[`demo/test/support/given_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/given_tables.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
live_session :heard, on_mount: [DemoWeb.Support.Heard] do
  ash_data_table "/heard/cards", Demo.Support.Given.Card,
    layout: false,
    notify: true,
    open: "Open",
    context: {DemoWeb.Support.Heard, :context},
    private_arguments: %{secret: "s3"},
    page_arguments: %{to: "ann"},
    before_action: {DemoWeb.Support.Heard, :before_action}
end
```

<!-- source: demo/test/support/given_tables.ex -->
```elixir
def on_mount(:default, _params, session, socket) do
  socket =
    socket
    |> Phoenix.Component.assign(test: session["test"], answer: :cont)
    |> attach_hook(:heard, :handle_info, fn
      {:ash_data_table, _id, _event} = message, socket ->
        send(socket.assigns.test, {:heard, message})
        {:halt, socket}

      {:run, fun}, socket ->
        {:halt, fun.(socket)}

      _other, socket ->
        {:cont, socket}
    end)

  {:cont, socket}
end
```

A route holds no anonymous function, so a function is written there as
`{module, function}`.

## "Open" on every row

`open: "Open"` (on the tag `open="Open"`) puts a button with that label first
in the actions cell of every row of the table on the page. It reads nothing
and writes nothing: it tells the page `:row_opened` with the row's primary
key, whatever `notify` says, and what "open" means is the page's: a
`push_navigate/2` to a page of the record, a panel of your own. Nested tables
have no such button.

**Try it:** the demo's browser tests drive it at `/e2e/opened`, in the e2e
environment.

## Page values

Three options hand server values to what the table does. They reach every
table the table shows, its nested tables and its pickers' tables too, and
the browser never sees them.

| Option | What it does |
| --- | --- |
| `context` | Put into the `context` of every call to Ash the table makes (reads, writes, summaries), deep-merged with the scope's. Your preparations, changes and policies read it there. |
| `private_arguments` | Arguments by name. An action is given those it declares `public?: false`, and no others: a read through `Ash.Query.set_argument/3`, a write as its private arguments. |
| `page_arguments` | The values of the arguments an `action` of the table's block says the page fills, with `page_argument`. The action panel does not ask for them, and nothing from the browser replaces them. |

Each is a map, or a function of the LiveView's assigns, or of them and which
table asks (`%{table: id, path: path, resource: resource}`). A function is
called in the LiveView's process before the reads and writes of a callback,
once in it for each table that asks, so it sees the assigns as they are
then. A new value reads nothing again by itself: call
[`refresh/2`](#commands) when it should.

A table action of the demo's tests is assigned to the person the page says,
never to one the browser names. The declaration
([`demo/test/support/given_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/given_tables.ex)):

<!-- source: demo/test/support/given_tables.ex -->
```elixir
action :assign do
  page_argument :to
end
```

and a page that attaches the table with all three:

<!-- source: demo/test/support/given_tables.ex -->
```elixir
|> AshDataTable.attach(:cards, Card,
  table: Map.get(session, "table"),
  context: context,
  private_arguments: %{secret: "s3", to: "browser"},
  page_arguments: Map.get(session, "page", %{to: "ann"}),
```

`page_argument` names a public argument of the action. A `private_argument`
named the same is not used for it: a page argument is only ever filled from
`page_arguments`. An action whose page argument the page gives no value
raises an `ArgumentError` when it opens or runs: that is a mistake of the
page's.

On the tag the options are attributes, and a function there is given the
`assigns` attribute (see
[Layout and embedding](layout-and-embedding.md#passing-scope-actor-and-tenant)).

## The veto

`before_action` is asked before every write of the table: a cell saved or
emptied, a record chosen for a reference cell, a cell saved from the side
panel, a row action, a table action, a create, an action on the selected
rows. It is a function of an `AshDataTable.Request`, or of it and the
LiveView's assigns, and answers `:cont` to let the write go on, or
`{:halt, message}` to stop it, with a string the table shows where the
write's outcome would be shown. Anything else raises.

<!-- sketch -->
```elixir
def before_action(%AshDataTable.Request{action: :destroy}, _assigns),
  do: {:halt, "Nothing is deleted today."}

def before_action(_request, _assigns), do: :cont
```

The request says which table asks (`table`, `path`), which action of which
resource (`resource`, `action`, `type`), from where (`from`: `:cell`,
`:clear`, `:reference`, `:map_cell`, `:row`, `:table`, `:create`, `:bulk`),
and the row's `key`, the `column` or the `selection`. It holds no typed
value, no input and no record: the veto can only stop a write. What a page
adds to an action goes through the page values above, which Ash checks as it
checks everything else.

It is asked after the table's own checks of what the browser named, and
before the record is read again and the action runs, in the LiveView's
process. "Show" on a sensitive cell and opening a panel are reads, and are
not asked.

## Commands

A page that attaches its table, and an `on_mount` hook of a router page (for
the table `:table`), can tell the table what to do. A tag takes no commands.
Each takes the socket and the name the table is attached under, and returns
the socket.

| Command | What it does |
| --- | --- |
| `AshDataTable.refresh/2` | Reads the table again, as it is, with its summaries: for page values or records that changed in a way the table cannot know of. What is open in it closes, as on any read. |
| `AshDataTable.put_state/3` | Gives the table a sort, filters, arguments, page or page size, as its URL parameters hold them: `%{"sort" => "-title", "page" => "2"}`. What the table does not allow is dropped. With `url: true` the URL is patched. |
| `AshDataTable.clear_selection/2` | Takes every row out of the selection. |
| `AshDataTable.selected_records/2` | Returns `{:ok, records}`: the selected rows, or every record the filters match, each read again as the person through the table's read action, with sensitive values masked. |
| `AshDataTable.detach/2` | Takes the table off the LiveView, with everything it shows. |

<!-- sketch -->
```elixir
def handle_event("export", _params, socket) do
  {:ok, records} = AshDataTable.selected_records(socket, :tasks)
  {:noreply, socket |> export(records) |> AshDataTable.clear_selection(:tasks)}
end
```

None of them writes a record. A name no table is attached under raises.
`AshDataTable.status/1` reads what a page may know of the table without a
command: its `id`, `state`, `count`, `total`, `loading?`, `error`, and what
is `selected`.

[Controlled mode](controlled-mode.md) adds the commands that answer a
request.

## Edge cases

- **The events of a table you never see.** A picker's table sends none. A
  nested table's events reach the page with its `path`.
- **A selection is a claim.** `:selection_changed` and `status/1` give the
  keys as the browser named them. `selected_records/2` reads them as the
  person; a key that names nothing they may read is not among the records.
- **`:row_opened` without `notify`.** It is sent anyway: a page that offers
  "Open" wants to hear it.
- **A page value function that raises** raises in the LiveView's process,
  as any of your code there would.
- **The veto on a selection.** It is asked once for the action on the
  selection, with `selection` (`:all`, or the rows as the browser named
  them), not once per record.

## Things people trip over

- **No events arrive.** `notify` was not given, or names other events.
- **Commands on a page with the tag.** The tag takes none, and a command
  raises for the name: attach the table instead.
- **A context that does not change what is shown.** A new value reads
  nothing again by itself: call `refresh/2`.
- **A private argument the action does not get.** Only an argument the
  action declares `public?: false` is given; a public one comes from the
  person, or from `page_arguments` where the action says `page_argument`.
- **Expecting the veto to see the value.** It sees which write is about to
  run, never what was typed: rules about values belong in the resource's
  validations and policies.

## Not in the first version

No command that writes, no event before a read, and no veto of reads. See
the [specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
