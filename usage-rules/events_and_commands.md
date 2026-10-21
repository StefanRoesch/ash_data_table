# Events and commands

A table tells its page what happened (events); the page tells the table what
to do (commands), hands it server-only values (page values) and can stop a
write (the veto). None of these skips a check: every write still goes
through the table's checks, the record read again as the person, and Ash's
policies. Details:
[Events and commands](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/events-and-commands.md).

## Hear events

With `notify: true` (or a list of event names) the table sends its LiveView
`{:ash_data_table, id, {event, details}}`; without `notify` it sends nothing
but `:row_opened`. `AshDataTable.Event` lists each event's details.

<!-- source: demo/e2e/server/opened_live.ex -->
```elixir
@impl true
def handle_info({:ash_data_table, "task", {:row_opened, %{key: %{id: id}}}}, socket),
  do: {:noreply, assign(socket, opened: id)}
```

- A router page is the library's LiveView: hear its events in an `on_mount`
  hook of its `live_session`, with `Phoenix.LiveView.attach_hook/4` on
  `:handle_info`.
- The keys of `:selection_changed` are what the browser named: claims. For
  the records, call `AshDataTable.selected_records/2`, which reads them
  again as the person.
- A record in the details has every `sensitive?` value masked
  (`%AshDataTable.Sensitive.Masked{}`).

## Page values

`context`, `private_arguments` and `page_arguments` reach every call to Ash
the table makes, nested tables and pickers included; the browser never sees
them. Each is a map or a function of the assigns. On a router line a function
is `{module, function}`.

- `private_arguments` reach only arguments the action declares
  `public?: false`.
- `page_arguments` fill the arguments an `action` of the block names with
  `page_argument`; the panel does not ask for them.
- A new value reads nothing again by itself: call `AshDataTable.refresh/2`.

## The veto

`before_action` is asked before every write, with an `AshDataTable.Request`
(which table, action and row; never the typed value). It answers `:cont` or
`{:halt, message}`:

<!-- sketch -->
```elixir
def before_action(%AshDataTable.Request{action: :destroy}, _assigns),
  do: {:halt, "Nothing is deleted today."}

def before_action(_request, _assigns), do: :cont
```

Rules about values belong in the resource's validations and policies.

## Commands

Commands need an attached table (`AshDataTable.attach/4`), or an `on_mount`
hook of a router page for the table `:table`; the tag takes none. Each takes
the socket and the name the table is attached under and returns the socket:
`refresh/2`, `put_state/3`, `clear_selection/2`, `selected_records/2`
(returns `{:ok, records}`), `detach/2`. `AshDataTable.status/1` reads what a
page may know of the table. No command writes a record.

<!-- sketch -->
```elixir
def handle_event("export", _params, socket) do
  {:ok, records} = AshDataTable.selected_records(socket, :tasks)
  {:noreply, socket |> export(records) |> AshDataTable.clear_selection(:tasks)}
end
```
