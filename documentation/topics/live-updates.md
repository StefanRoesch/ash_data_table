# Live updates

Make a table follow what other people change, turn it off where it is not
wanted, and know what a person is shown of a change and what never.

## The smallest example

A table shows what it read. Two lines make it follow what others change: one
in the resource
([`demo/lib/demo/tracker/comment.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/comment.ex)),

<!-- source: demo/lib/demo/tracker/comment.ex -->
```elixir
table do
  update_action :update
  on_forbidden :message

  # Live updates, also where the comments are nested under a task.
  live? true
```

and one in its domain, naming the `Phoenix.PubSub` server that carries the
announcements
([`demo/lib/demo/tracker.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker.ex)):

<!-- source: demo/lib/demo/tracker.ex -->
```elixir
pub_sub Demo.PubSub
```

That is the name the server is started under in the application's supervisor,
which a Phoenix application already does:

<!-- source: demo/lib/demo/application.ex -->
```elixir
{Phoenix.PubSub, name: Demo.PubSub},
```

**Try it, in one window:** `/named` in the demo, as Ada Admin. The page has two
tables of the comments. Change a comment's text in the first: the same row
changes in the second. Create a comment in the first: the second says "There
are new or changed records." with a "Read again" button. Delete a comment in
the first: its row goes from both.

**Try it, with two people:** open `/tasks` in two browser windows, one
private, as Ada Admin and as Max Member. Change a title as Ada: Max sees it
without a reload.

## How it works

Three ordinary parts, no rule of the table's own.

1. **Ash announces.** `live? true` gives the resource a notifier
   (`AshDataTable.Resource.Notifier`), as GraphQL subscriptions give a
   resource ash_graphql's. After every create, update and destroy it sends one
   small message: the resource, the kind of action, the primary key and the
   tenant.
2. **Phoenix PubSub carries it**, on one topic per resource and tenant.
3. **The table reads again, as the person.** A table that hears a key reads
   that record through its own read action, with its arguments and as the
   person looking, and shows what comes back.

An announcement is never shown. It holds no record, no value and no name of
who changed something: only which record to look at again.

<!-- sketch -->
```elixir
{:ash_data_table_changed, MyApp.Tracker.Task, :update, %{id: "0b0f…"}, "the-tenant"}
```

## What a person sees

| What happened | What the table does |
| --- | --- |
| A record that is a row of the page was changed | The row is read again and updated in place. It stays where it is, even if the sort would now put it elsewhere. |
| The same, and the read does not return the record | The row goes, and the count drops by one. The record was deleted or is no longer the person's to read; the table cannot tell which and does not say. |
| The row no longer matches the person's filter | It stays, as after the person's own edit, and goes with the next read. |
| A record was created, or a record that is no row of the page was changed | No row is put in: where it belongs depends on sort and page. The table says "There are new or changed records." above the grid and through its live region, with a "Read again" button. |
| A record that is no row of the page was deleted | Nothing. |

"Read again" reads the page as currently asked for: same sort, filters and
position. The notice goes with any new read.

## What a person is never shown

- **A record they may not read.** A row is only made from the read action's
  answer, as that person. A key that returns nothing shows nothing.
- **A field a field policy hides.** The row is read with the read action's
  field policies, so the cell says "Not available" after an update as before.
- **A sensitive value.** The column stays masked.
- **A hint that something exists.** Before showing the notice, the table asks,
  in one read with the person's filters, whether at least one announced record
  is one they would be shown. If none is, there is no notice.
- **Another tenant's changes.** Tenants do not share a topic, and the read is
  in the person's tenant anyway.

A page mounted with `authorize?: false` reads again without authorization, as
it reads everything else.

## While a person is working on a row

Nothing a person is working on changes or goes away under them.

- **A cell being edited keeps what was typed.** The row around it is updated,
  the cell is not. Closed without a save, the cell shows the new value; a save
  runs as always, and the record is read again before the action.
- **A row with something open is left as it is** until that closes, then
  updated or removed. This covers the row the action panel or picker is open
  for, and every row under which a panel or picker is open, in a nested table
  at any depth.
- **A row whose record is gone stays while an editor is open in it.** Given
  up, the row goes. Saved, the cell says "This record is no longer
  available.", as after any save into a record that is gone, and the row stays
  until the next read so this can be read.

The server is never told which cell a person edits. Before it removes a row
for a live update, it asks the browser about that one row; the browser answers
at once, or when the editor in the row is gone.

## Which tables follow

Every table of a resource with `live? true`: mounted as a page, placed with
the tag, attached to a LiveView, nested in a row, and in a picker. A nested
table follows its own resource, limited to its row as its reads are; a nested
table of a resource that announces nothing does not listen.

Three places say no:

<!-- sketch -->
```elixir
# a named table that does not follow
tables do
  table :archive do
    live? false
  end
end

# a page, in the router
ash_data_table "/tasks/print", MyApp.Tracker.Task, live?: false

# a table attached to a LiveView of your own
AshDataTable.attach(socket, :tasks, MyApp.Tracker.Task, live?: false)
```

<!-- sketch -->
```heex
<AshDataTable.table resource={MyApp.Tracker.Task} live?={false} />
```

A page that says no also says it for the tables nested in its rows and for its
pickers. `live?: true` on the router line, the tag or `attach/4` requires
following, and is an error when the page is opened for a resource that
announces nothing.

## What is announced, and what is not

Announced: every create, update and destroy run through an Ash action,
anywhere in the application, not only from a table.

Not announced, because Ash sends no notification:

- a bulk action not run with `notify?: true` (the table's own actions on
  selected rows are);
- a write outside an action: `Ash.Seed`, the repo, SQL;
- a generic action, which has no record. What it changes through other actions
  is announced by those;
- an action in a transaction that is rolled back. Inside a transaction the
  announcement waits for the commit.

A table is not told of its own changes: it already shows what its action
returned. Every other table is told, including another table of the same
resource on the same page.

## What it costs

- One process and one subscription per open table that follows, none for a
  table that does not. They end with the page, or when a nested table or
  picker closes. A test counts them with `AshDataTable.Test.listening/2`.
- One small message per changed record. With nobody listening, that is all.
- Announcements are gathered for 100 ms. Per batch a table does at most two
  reads, however many records were announced: one for the rows of its page,
  one asking whether any of the others is the person's to see. A bulk action
  on 1,000 records is 1,000 messages and, in each open table, a handful of
  batches.

## Edge cases

- **The host's own notifiers and `pub_sub` block** are left alone; the table's
  notifier is one more.
- **A record written without a tenant** (the resource is `global? true`) is
  announced to the tenant its attribute names.
- **A table that reads without a tenant** hears every tenant's changes and
  reads each as it reads its page.
- **The PubSub server is not running.** A table that has to listen raises when
  opened, naming the server. A write is never refused for it; it logs a
  warning.
- **A read is in flight** when something is announced: the table looks at it
  once the read is back.
- **A value in a sensitive cell** is masked again when its row is updated.
- **A failed edit in a row** keeps its mark and what was typed when the row is
  updated.
- **A nested table in a test** is inside a portal, which
  `Phoenix.LiveViewTest` does not look into: read the page with
  `AshDataTable.Test.page/1`. See [Testing](testing.md).
- **A selected row that goes** is no longer selected. "All that match" stays
  as it is.

## Things people trip over

- **"Nothing happens."** The change was made without an action, or by a bulk
  action without `notify?: true` (see "What is announced"). A page that knows
  of such a change can tell an attached table to read again with
  `AshDataTable.refresh/2`: see [Events and commands](events-and-commands.md).
- **"`live? true`, and the domain does not compile."** The domain must name
  the server: `pub_sub MyApp.PubSub` in its `table` block, with
  `extensions: [AshDataTable.Domain]`.
- **"The comment count did not change."** A column that shows another resource
  does not follow that resource. See below.
- **"The new record is not in the table."** It is not put in; use "Read
  again".
- **`render_async/2` in a test** does not wait for live updates: they come from
  a process of their own, 100 ms after the change. Call
  `AshDataTable.Test.flush(view)` after the change instead of sleeping. A row
  that is to go waits for the browser's answer, which a LiveView test gives
  itself: see `AshDataTable.Test`.
- **A test that changes a record of a live resource behind an open page** has
  that page follow a moment later. A row is updated in place; none is removed
  without the browser's answer.

## Not in the first version

- **Columns that show another resource:** an aggregate column, the label of a
  reference cell, a calculation over related records. They are right again
  after the next read; "Read again" is not offered for them.
- **A record that moves to another tenant** is not announced to the tenant it
  left.
- **A setting for the 100 ms**, or for which actions are announced.
- **A highlight on an updated row.**
- **Hearing of a change made without an Ash action.**

Further work is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
