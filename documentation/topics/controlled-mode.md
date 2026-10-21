# Controlled mode

A table asks its own questions, opens its own action panels and its own
pickers. In controlled mode it hands them to the page instead: it holds each
as a **request**, tells the page, and waits until the page answers. The page
draws the question, the panel or the picker however it likes, in its own
markup, and answers with a command. After reading this guide you can attach
a table in controlled mode, draw what it holds, and answer it.

Controlled mode needs an attached table (`AshDataTable.attach/4`, see
[Layout and embedding](layout-and-embedding.md#attaching-a-table-to-your-own-liveview)):
the page answers with commands, which the tag and the router page do not
take. A table that draws everything itself is **uncontrolled**, the default.

To change only how the table's questions, panels and pickers *look*, a
[kit](kits.md) is the simpler way: it draws them with your markup and the
table keeps running them. Controlled mode is for a page that wants to run
them itself.

## Turning it on

`controlled:` lists what the page draws itself, any of three:

| Kind | What the page draws |
| --- | --- |
| `:confirm` | Every question outside a panel: before a row action, a table action or an action on the selected rows, before a cell of a column with `confirm` is saved (what was typed is held by the table, and the cell waits), and before the record chosen for a reference cell is saved. |
| `:panel` | Every action panel: of a row action, a table action, a create, an action on the selected rows, a cell edited in the side panel, and the panel of a filter for several values. With its files, its groups of fields and unions, and the records chosen for a field. |
| `:picker` | The picker of a reference cell, and of a field of a panel the table draws. |

A page of the demo's browser tests draws the panel of its memos' "Rename"
itself
([`demo/e2e/server/controlled_live.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/e2e/server/controlled_live.ex)):

<!-- source: demo/e2e/server/controlled_live.ex -->
```elixir
{:ok,
 socket
 |> assign(page_title: "Controlled")
 |> AshDataTable.attach(:memos, Memo, controlled: [:panel])}
```

It holds for every table the table shows: its nested tables, at every depth,
hold what they open as the table on the page does. A picker's own table opens
nothing.

## What the table holds: `requests/1`

`AshDataTable.requests/1` gives the requests the tables of an attached table
hold now, the table on the page's first, then its nested tables, parents
before their children; `[]` for none. Each table holds one request at a
time: a new one ends the one before.

Every request has:

| Field | What it is |
| --- | --- |
| `ref` | What the answer names. A new request has another. |
| `kind` | `:confirm`, `:panel` or `:picker`. |
| `table`, `path` | The id of the table that holds it, and the ids from the table on the page down to it. |
| `key` | The primary key of the row it is about, or nil. |
| `question` | The question to ask before it runs, or nil. |
| `messages` | What its texts are made of, by name, each a map `%{key: key, values: values}` as `AshDataTable.Messages` lists them, for a page that translates for itself. |

And by kind:

- **`:confirm`**: `action`; for a cell's question also `column` and
  `value`, the value the cell is to be given (nil for a sensitive column).
- **`:panel`**: `action` (nil for the panel of a filter), `column` (of a
  cell's or a filter's panel), `title`, `errors` (what is said about none of
  its fields) and `fields`. Each field is what a kit draws the field from,
  its projection (`AshDataTable.Kit.Projection`, a field of `panel`), without
  its bundles (the attributes of its elements, which a kit spreads): its
  `path` (the names it is sent under, `["title"]`, inside a value made of
  fields the names on the way to it), `label`, `editor` (its control),
  `required?`, `value` (as its form sends it, a value made of fields too;
  nil for a sensitive field), `values` (the choices of an enum, each
  `%{value:, label:, chosen?:}`), `invalid?`, `texts` and `messages` (what
  is said at it, `errors` among them), and by what it is: `reference` and
  `references` (the records it holds, each its `key` and what it is called,
  `text`), `group`, `groups` and `union` (what a value made of fields holds,
  each field described the same way; a union's `kinds`), `list`, `control`,
  `clear`, `count`. A file field has `upload`, the name of its upload among
  the LiveView's.
- **`:picker`**: `column` (what it chooses for), `resource` (what is chosen
  from), `several?`, `allow_none?`, `current` (the key or keys held now),
  `chosen`, `title` and `errors` (why a key chose nothing). Its `question`
  is the column's question: see [Picking](#picking).

A request is plain data, maps, lists, strings, numbers and atoms, so a
page can hand it to a client as JSON as it is (to a React component, say).

Texts are in words, in the person's language. The page draws from them in
its `render/1`. The demo's page draws the first request as a form of its
own:

<!-- source: demo/e2e/server/controlled_live.ex -->
```elixir
def render(assigns) do
  assigns = assign(assigns, request: List.first(AshDataTable.requests(assigns.memos)))
```

<!-- source: demo/e2e/server/controlled_live.ex -->
```heex
<form :if={@request} id="request" phx-submit="submit">
  <h2 id="request-heading">{@request.title}</h2>
  <input type="hidden" name="ref" value={@request.ref} />
  <label :for={field <- @request.fields} class="block">
    {field.label}
    <input
      type="text"
      id={"request-#{hd(field.path)}"}
      name={"request[#{hd(field.path)}]"}
      value={field.value}
      class="input"
    />
    <span :for={error <- field.texts.errors} class="request-error">{error}</span>
  </label>
```

With `notify: [:requested, :request_ended]` the page also hears when a
request is waiting (`:requested`, with its `ref` and `kind`) and when it is
held no more (`:request_ended`): answered, given up, taken over by a new
one, or gone with its table, a nested table whose row closed. A page that
draws from `requests/1` in `render/1` needs neither: every change of a
request renders the LiveView again.

## Answering

Each command takes the socket, the name the table is attached under, and the
request's `ref`, whichever table of the tree holds it. It does nothing for a
`ref` no table holds any more.

| Command | Kind | What it does |
| --- | --- | --- |
| `confirm_request/3` | `:confirm` | Confirm: what was asked about runs, as the person's Confirm would run it. |
| `validate_request/4` | `:panel` | What the page's form holds now, `params` by field name as typed: the action says what it makes of it, and `requests/1` shows that. Nothing runs. |
| `submit_request/4` | `:panel` | Runs the action with `params`, as the panel's Run does. Done, the request is gone; refused, it stays, with what the action said at its fields. |
| `pick_request/4` | `:picker` | Chooses a record by its primary key (a map, or the value of a one-field key), a list of them where several are chosen, or nil for none. |
| `add_group_request/4` | `:panel` | Adds a value to a field made of groups, by its path: `[:place]`, `[:stops]`. |
| `remove_group_request/4` | `:panel` | Takes a value away, by its path: `[:place]`, `[:stops, "1"]`. |
| `cancel_request/3` | any | Gives the request up, as Cancel does: nothing runs, and a waiting cell is put back. |

The demo's page answers its form:

<!-- source: demo/e2e/server/controlled_live.ex -->
```elixir
@impl true
def handle_event("submit", %{"request" => params, "ref" => ref}, socket),
  do: {:noreply, AshDataTable.submit_request(socket, :memos, ref, params)}

def handle_event("cancel", %{"ref" => ref}, socket),
  do: {:noreply, AshDataTable.cancel_request(socket, :memos, ref)}
```

An answer goes the way the person's own answer would: through the table's
checks of what was named, the page's `before_action` veto, the record read
again as the person, and the action with Ash's policies. A key given to
`pick_request/4` is a claim like any key from the browser: the record is
read again as the person, through the picker's read action, and a key that
names nothing they may read chooses nothing (the request then says why in
`errors`). A map without a field of the primary key raises an
`ArgumentError`.

A panel's file field names its `upload`: the page draws
`Phoenix.Component.live_file_input/1` of it, and `submit_request/4` takes
the file as the panel would. Records chosen for a field come back as their
keys in the params, and are read again as the person.

## Picking

A reference cell's choice saves as the person's would, after the column's
question. With `:confirm` that question is a request of its own, after the
pick. Without `:confirm`, the picker request's `question` is the column's
question, and the page must show it beside its chooser: the choice is the
person's answer to it, and saves at once. A field's choice goes into the
field, and nothing is saved until the panel runs.

A page of the demo's browser tests draws the questions and the picker of a
table of `AshDataTable.Test.Resource`
([`demo/e2e/server/controlled_kit_live.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/e2e/server/controlled_kit_live.ex)):

<!-- source: demo/e2e/server/controlled_kit_live.ex -->
```elixir
def handle_event("confirm", _params, socket),
  do: {:noreply, by_request(socket, &AshDataTable.confirm_request(&1, :table, &2))}

def handle_event("cancel", _params, socket),
  do: {:noreply, by_request(socket, &AshDataTable.cancel_request(&1, :table, &2))}

def handle_event("pick", %{"key" => key}, socket),
  do: {:noreply, by_request(socket, &AshDataTable.pick_request(&1, :table, &2, key))}
```

## A question is no safety check

A question guards a person against a mistake, not the data against them. In
controlled mode with `:confirm` the page shows the question, and the table's
own behaviour in the browser sends nothing that skips it. But a browser can
still send an event as if it had been confirmed, and the server does not
refuse it: it runs as it would without the question. The same holds without
controlled mode. What must not run is for Ash's policies and validations on
the resource, and for the page's `before_action` veto, to refuse. They run
for every write, whoever sends it. See [Confirm](confirm.md).

## Edge cases

- **One request per table.** A table that opens something new while it
  holds a request ends the old one (`:request_ended`), and the old `ref`
  is answered no more. A question ends a panel or picker the table held.
- **A nested table's request** ends when its row is collapsed and the
  nested table closes. A cell that waited on it is put back.
- **A stale `ref`.** An answer to a request that is gone, or of another kind
  than the command answers, does nothing.
- **A cell waits.** While a column's question is the page's, the cell keeps
  what was typed and is marked busy. Confirm saves it; Cancel, or a new
  request, puts it back.
- **A panel's own question** (a row action with inputs, the count of a
  selection) is asked with the panel: by the table, or by the page when it
  draws the panel.
- **A filter's panel** is a `:panel` request without an action: its one
  field holds the column's values, and `submit_request/4` filters by what
  it is sent.
- **A path that names no group** of the panel changes nothing; a path that
  is no list of names raises.

## Things people trip over

- **`controlled:` on the tag or the router line.** Neither takes it: attach
  the table.
- **Nothing is drawn.** The page draws from `requests/1`, and the table
  draws no question, panel or picker of the kinds it hands over: a page
  that forgets one leaves the person without it.
- **A picker that shows records the person may not choose.** The page
  decides what it offers; the table reads every key again as the person, so
  such a key chooses nothing and `errors` says so. Offer the records the
  person may read.
- **A sensitive field's value is nil.** The request never holds a sensitive
  value; the page's control starts empty, as the table's does.

## Not in the first version

No controlled mode for the tag or the router page, and no request for the
"Show" of a sensitive cell. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
