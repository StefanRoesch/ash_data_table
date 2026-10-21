# Controlled mode

In controlled mode a table hands its questions, action panels and pickers to
the page: it holds each as a **request**, and the page draws it in its own
markup and answers it with a command. To change only how they look, a kit is
simpler (`ash_data_table:kits`). Details:
[Controlled mode](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/controlled-mode.md).

## Turn it on

Controlled mode needs an attached table: the tag and the router line take no
`controlled:`. List what the page draws, any of `:confirm`, `:panel` and
`:picker`:

<!-- source: demo/e2e/server/controlled_live.ex -->
```elixir
{:ok,
 socket
 |> assign(page_title: "Controlled")
 |> AshDataTable.attach(:memos, Memo, controlled: [:panel])}
```

It holds for the table's nested tables at every depth too. The table then
draws none of those kinds: the page draws every kind it lists.

## Draw the requests

Draw from `AshDataTable.requests/1` in `render/1`; every change of a request
renders the LiveView again. Each table holds one request at a time, and a
new one ends the one before.

<!-- source: demo/e2e/server/controlled_live.ex -->
```elixir
def render(assigns) do
  assigns = assign(assigns, request: List.first(AshDataTable.requests(assigns.memos)))
```

- A request has `ref`, `kind`, `table`, `path`, `key`, `question` and
  `messages`, plus by kind: `action` and `column`/`value` for `:confirm`;
  `title`, `errors` and `fields` for `:panel`; `column`, `resource`,
  `several?`, `allow_none?`, `current` and `chosen` for `:picker`.
- It is plain data, with texts in the person's language, so it goes to a
  client as JSON as it is.
- A sensitive value is nil in it: the page's control starts empty.
- Without `:confirm`, a picker request's `question` is the column's
  question: show it beside the chooser, since the choice saves at once.

## Answer them

Each command takes the socket, the name the table is attached under and the
request's `ref`: `confirm_request/3`, `validate_request/4`,
`submit_request/4`, `pick_request/4`, `add_group_request/4`,
`remove_group_request/4`, `cancel_request/3`, all on `AshDataTable`.

<!-- source: demo/e2e/server/controlled_live.ex -->
```elixir
@impl true
def handle_event("submit", %{"request" => params, "ref" => ref}, socket),
  do: {:noreply, AshDataTable.submit_request(socket, :memos, ref, params)}

def handle_event("cancel", %{"ref" => ref}, socket),
  do: {:noreply, AshDataTable.cancel_request(socket, :memos, ref)}
```

An answer goes through the same checks as the person's own: the `before_action`
veto, the record read again as the person, and the action with Ash's
policies. A key given to `pick_request/4` is read again through the picker's
read action. A question guards the person against a mistake; what must not
run is for the policies and validations to refuse.
