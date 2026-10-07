# Authorization

The table has no authorization rules of its own. It passes the actor and the
tenant into ordinary Ash calls, asks Ash what the person may see and do, and
shows the answer. After reading this guide you know where the table finds
the actor, what each kind of policy looks like to a person, and why some
refusals show before a person acts and others only when they save or run an
action.

## The smallest example

There is nothing to declare in the `table` block. A mounted table reads who
is asking from the socket assigns that your `on_mount` hook sets. In the demo
the hook is `DemoWeb.Actor`
([`demo/lib/demo_web/actor.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/actor.ex)):

<!-- source: demo/lib/demo_web/actor.ex -->
```elixir
def on_mount(:default, _params, session, socket) do
  socket =
    socket
    |> Phoenix.Component.assign_new(:current_user, fn ->
      session |> Map.get(Actors.session_key()) |> Actors.fetch()
    end)
    |> then(fn socket ->
      Phoenix.Component.assign_new(socket, :current_tenant, fn ->
        Actors.tenant(socket.assigns.current_user)
      end)
    end)

  {:cont, socket}
end
```

The tables are mounted inside the `live_session` that runs this hook, and
that is all the wiring there is.

**Try it:** `/tasks` in the demo. The "Acting as" switcher in the page
header changes who you are, and the same page changes with it:

| Actor | Rows | Columns | Editing | Row actions and "New task" |
| --- | --- | --- | --- | --- |
| Ada Admin | Acme's tasks | all 17 | every editable column, on every task | four buttons on every row, each of which runs; "New task" |
| Max Member | Acme's tasks | 16: no "External ref". "Estimate hours" is empty except on the tasks assigned to him | looks editable everywhere; a task that is not his refuses when a cell is saved | four buttons on every row; a task that is not his refuses when an action runs; "New task", without the field "External ref" |
| Vera Viewer | Acme's tasks | 14: as the member, and no "Assignee" and no "Reported by", since a viewer may not read people | none | no actions column, no "New task" |
| Olga Outsider | Globex's tasks | 16, as the member | as the member, on Globex's tasks | as the member, on Globex's tasks |
| Nobody | none: "No records" | 14: no "External ref", no "Estimate hours" and no "Project" | none | none |

The columns counted here are the table's own. The column of the expanders
and the "Actions" column are not among them.

## Where actor and tenant come from

A mounted table looks at three socket assigns:

1. `current_scope`, when it is assigned and not nil, is passed to Ash as the
   `scope`. It must implement `Ash.Scope.ToOpts`, and it then carries the
   actor and the tenant.
2. Otherwise `current_user` is the actor and `current_tenant` the tenant.
3. An assign that is not there counts as nil. With none of them nobody is
   logged in, which is not an error: the table shows what the resource
   leaves to an anonymous visitor.

Who may open the page at all is not the table's concern. It is decided by
your router, your pipelines and your `live_session`, as for any LiveView.

A table placed in your own LiveView is given `scope`, or `actor` and
`tenant`, as attributes and does not look at the assigns. See
[Layout and embedding](layout-and-embedding.md).

## The domain section

The assign names, and whether the tables authorize at all, are settings of
the resource's domain, with the extension `AshTable.Domain`. The demo's
tracker writes the defaults out
([`demo/lib/demo/tracker.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker.ex)):

<!-- source: demo/lib/demo/tracker.ex -->
```elixir
use Ash.Domain, otp_app: :demo, extensions: [AshTable.Domain]

# How the tables of these resources authorize, and under which socket
# assigns a mounted table finds who is asking. These are the defaults,
# written out; `DemoWeb.Actor` sets the two assigns.
table do
  authorize? true
  actor_assign :current_user
  tenant_assign :current_tenant
end
```

| Option | Default | Meaning |
| --- | --- | --- |
| `authorize?` | `true` | Whether the tables of this domain's resources authorize. |
| `scope_assign` | `:current_scope` | The socket assign holding an `Ash.Scope`. |
| `actor_assign` | `:current_user` | The socket assign holding the actor, used when there is no scope. |
| `tenant_assign` | `:current_tenant` | The socket assign holding the tenant, used when there is no scope. |

The extension is optional. A domain that does not list it behaves as one
with these defaults.

An app whose assigns have other names says so once per domain. The demo's
own domains keep the defaults, so this example is from a domain that exists
for the demo's tests
([`demo/test/support/guarded_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/guarded_tables.ex)):

<!-- source: demo/test/support/guarded_tables.ex -->
```elixir
table do
  scope_assign :viewer_scope
  actor_assign :reader
  tenant_assign :reader_organization
end
```

A domain that names its own assigns does not fall back to the conventional
ones: with `actor_assign :reader`, a `current_user` on the socket is not
looked at.

### `authorize? false`

From the same test support file, a domain whose tables do not authorize:

<!-- source: demo/test/support/guarded_tables.ex -->
```elixir
table do
  authorize? false
end
```

**`authorize? false` removes every check.** The tables of that domain's
resources read and save with no policy and no field policy applied, whoever
is asking and even when nobody is logged in: every record the read reaches,
every column, every declared edit. The resource behind this example forbids
everything in its policies, and its table shows and saves everything. Use the
setting only for a domain whose tables sit behind a gate of your own, such
as an admin area that the router already restricts.

## What each restriction looks like

| The resource says | The table shows | In the demo |
| --- | --- | --- |
| The person may not see some **records**: a policy that filters | Those rows are not there and are not counted. Nothing indicates them. | `/tasks` as Olga Outsider shows Globex's tasks only; as nobody, "No records". |
| The read is **refused outright**: a `Forbidden` error, as from an `access_type :strict` policy | The page answers as if it did not exist: status 404 and your "not found" page. With `on_forbidden :message` the page stays and says "You are not allowed to see these records." | `/projects` as nobody is a 404; `/comments` as nobody shows the message. |
| The person can **never see a field**: a field policy that depends on the actor only | The column is left out for that person: no heading, no filter, no cells. A URL that sorts or filters by it is ignored. | "External ref" on `/tasks` exists for Ada Admin only. |
| The person sees a field on **some records only**: a field policy with a check on the record | The column stays. Hidden cells are empty, announced as "Not available", and cannot be edited. | "Estimate hours" on `/tasks` as Max Member. |
| The person can **never read a related resource** that a column or a row leads to | A [reference cell](nested-tables.md#the-reference-cell) of that relationship has no column for them, and the relationship has no line under an expanded row. | `/tasks` as Vera Viewer: no "Assignee" column, and no "Assignee" line under a task. |
| The person may **not read one related record** | Its reference cell is empty, as for no related record. In a nested table its row is not there. | A task assigned to somebody of another organization. |
| The person can **never run an update action** | The columns it saves are read-only for that person. If that is every editable column, the table offers them no editing at all. | `/tasks` as Vera Viewer. |
| The person may run an update action on **some records only** | Cells look editable. On a record the action refuses, the cell says "You are not allowed to change this." when it is saved. | `/tasks` as Max Member, on a task that is not his. |
| The person can **never run a row action** | The action has no button for them. If that is every row action, the table has no "Actions" column. | `/tasks` as Vera Viewer; `/projects` as Max Member has "Set status" and no "Destroy". |
| The person may run a row action on **some records only** | The button is on every row. On a record the action refuses, the row's actions cell, or the action panel, says "You are not allowed to do this." | `/tasks` as Max Member: "Archive" on a task that is not his. |
| The person can **never run the create action** | The table has no create button for them. | `/tasks` as Vera Viewer; `/projects` and `/labels` as Max Member. |
| The person may create **some records only** | The button is there. A record the action refuses says "You are not allowed to do this." in the panel, and nothing is created. | (none in the demo) |

"No records" is only ever shown for a read that succeeded and found nothing.

The policies behind the first two rows differ in one line. The tasks' read
policy filters:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
policy action_type(:read) do
  description """
  Filtered: everyone with an organization sees all its tasks, and
  nobody else's. Without an actor the filter matches nothing.
  """

  authorize_if expr(organization_id == ^actor(:organization_id))
end
```

The projects' read policy refuses
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
policy action_type(:read) do
  description "Refused outright, not filtered, when nobody is logged in."
  access_type :strict
  authorize_if actor_present()
end
```

The two kinds of hidden field are the two field policies of the tasks:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
field_policies do
  field_policy :external_ref do
    description "Actor only: admins."
    authorize_if actor_attribute_equals(:role, :admin)
  end

  field_policy :estimate_hours do
    description "Record-dependent: admins, or the task's own assignee."
    authorize_if actor_attribute_equals(:role, :admin)
    authorize_if expr(assignee_id == ^actor(:id))
  end
  # ...
end
```

(A line `# ...` stands for lines that are left out.)

## Related records

A row leads to other resources in two ways: a reference cell shows one
related record by its label, and an expanded row opens the tables of its
related records. The destination's own policies decide both, with the same
actor, and the table asks the same two kinds of question of the destination
that it asks of its own resource.

- A destination the person can **never** read is left out: no column for
  its reference cell, no line for its nested table.
- What they may read of it is known when it is read. A related record that
  is not theirs is an empty cell, and is not among a nested table's rows.
- A nested table, and a page limited to the records of one parent, read that
  parent again as the person on every read. A key in an event or in an
  address gives access to nothing.

[Nested tables](nested-tables.md#what-a-person-may-not-see) has every case.

### Aggregates and calculations

One thing here is Ash's rule and easy to get wrong in the resource: an
**aggregate** applies the related resource's read policy and not its field
policies, and a **calculation** applies no policy to what it references. An
aggregate over a protected field, and a calculation that references one,
need a field policy of their own on the resource that declares them. The
table shows such a field as a column like any other, and warns when it is
not protected. The rule, the warning and how to answer it are in
[Columns and defaults](columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).

## `on_forbidden`

By default a person whose read is refused outright is not told that the
table exists. The mounted page raises `AshTable.NotFoundError`, which Phoenix
renders as it renders a missing route. `on_forbidden :message` tells them
instead. The demo's comments do
([`demo/lib/demo/tracker/comment.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/comment.ex)):

<!-- source: demo/lib/demo/tracker/comment.ex -->
```elixir
table do
  update_action :update
  on_forbidden :message
  # ...
end
```

| `on_forbidden` | A request for the page | A live navigation to the page | The read is refused while the page is open |
| --- | --- | --- | --- |
| `:not_found` (default) | 404 | LiveView makes the browser ask for the page afresh, which answers 404 | The browser is redirected to the same URL, which answers 404 |
| `:message` | The page, with the message in place of the rows | The same | The rows are replaced by the message |

Choose `:message` when people know the table exists and should learn that
they lack access. Keep `:not_found` when the table's existence is itself
something not everybody should learn.

## Why a rule that depends on the record shows on save

The table asks Ash three questions, each time it reads: when the page is
opened and at every change of sort, filter or page.

- **Which of these fields can this person never see?** One call of
  `Ash.can_see_fields/4` for all columns, and one for the attributes that
  the table's row actions and its create action accept.
- **Which of these update actions can this person never run?** One call of
  `Ash.can/3` per distinct update action, not per cell.
- **Which of the row actions, and the create action, can this person never
  run?** One call of `Ash.can/3` per action, not per row.

None of them reads a record or runs a query. Ash can answer "yes", "never",
or "that depends on the record". Only "never" changes the table: the column
is left out or made read-only, the button is left out. An answer Ash cannot
give at all is taken as "never".

"That depends on the record" leaves the cell looking editable, and this is
the surprising part. The alternative would be to check every action against
every row of the page before showing it. That is a check per cell, each of
which may need the database, for an answer that can be out of date by the
time the person presses Enter. The table asks once per action and leaves the
decision about one record to the moment it matters: the action runs, and the
action's policy answers. A refusal then appears on the cell.

A row action follows the same reasoning. Its button is on every row unless
the person can never run it, and a refusal appears when it runs: on the
row's actions cell for an action that runs straight away, above the fields
for one that runs from the action panel. See
[Row actions and create](row-actions-and-create.md#who-may-run-what).

The same reasoning applies to fields. Whether a field is visible on one
record is known once the record is read; Ash puts an `Ash.ForbiddenField` in
its place, and the table renders the placeholder.

The demo's update policy has both kinds of rule in it. The viewer's line
depends on the actor only, the member's on the record:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
forbid_if actor_attribute_equals(:role, :viewer)
authorize_if actor_attribute_equals(:role, :admin)
authorize_if expr(assignee_id == ^actor(:id) or reporter_id == ^actor(:id))
```

## Refusing to edit a hidden field protects the table only

When a person is not shown a field on a record, the table does not let them
change it there either. That is the table's doing, and it stops at the
table.

The action panel follows the same rule. An attribute the person can never
see is no field of a row action's panel or of the create panel, an
attribute hidden from them on one record is no field of that record's
panel, and a value sent for either all the same is dropped before the
action is given its inputs. On `/tasks`, "New task" has the field "External
ref" for Ada Admin only.

A field policy is about reading. The update action itself accepts the field
from anyone its *policy* allows: the same action called through
`ash_json_api`, `ash_graphql` or your own code changes a field the caller
cannot see. The same holds for a create action. If a field must not be
changed by people who cannot see it, say so in the resource: an action that
does not accept the field, or a policy or validation on the one that does.

## Edge cases

- **Filtering and sorting by a field hidden on some records** stays
  possible and gives nothing away, because Ash treats a hidden value as
  empty. A filter by a value finds only records whose value the person sees;
  "is empty" also finds every record whose value is hidden; a sort puts the
  hidden ones together with the empty ones.
- **A field hidden by a record check from somebody no record can match.**
  Nobody is no task's assignee, so "Estimate hours" is left out for nobody
  on `/tasks`, although its policy depends on the record.
- **A `save` event from a person who can never run the action is not run.**
  The column is read-only in their table, and the server ignores the event
  as it ignores one for any cell that cannot be edited.
- **A save cannot reach a record the person cannot read.** A `save` event
  names a row of the person's own page; an id that is not on it saves
  nothing. For a row that is on the page, the record is read again as the
  person before the action runs, so a record that has left their reach since
  says "This record is no longer available."
- **An `act` or `create` event from a person who can never run the action
  is not run**, and opens no panel: the action is looked up among the ones
  the table offers that person.
- **A row action cannot reach a record the person cannot read.** As for a
  save, the event names a row of the person's own page, and the record is
  read again as the person before the action runs, and for a panel before
  it opens.
- **A record created in a nested table is joined to the row above by the
  table**, from that row as it is read again for the person. A key sent
  with the form is not looked at.
- **A record the person creates and may not read** is created, and is no
  row of their table.
- **A public `sensitive?` field is a column.** Sensitivity is not an
  exposure rule, here or in the API extensions. Hide a field with a field
  policy or make it private.
- **An error names a field only if the person has a column for it.** An
  error about a field whose column was left out for them is shown without
  the field's name.
- **Columns keep their numbering.** With a column left out, the remaining
  ones are numbered without a gap for assistive technology.
- **An aggregate hidden on some records cannot be sorted by.** Ash raises
  for such a sort, so the table does not offer it to that person. Its filter
  stays. See
  [Columns and defaults](columns-and-defaults.md#what-a-table-does-not-sort-by).

## Things people trip over

- **Changing who is logged in without mounting again.** The table follows
  the person who mounted the page. Mount the page again when the user
  changes, as a login or a logout does.
- **A table mounted outside the `live_session` that assigns the user** reads
  as nobody.
- **Custom assign names without the domain section.** A table whose domain
  says nothing looks at `current_scope`, `current_user` and
  `current_tenant` only.
- **An empty table that should be a 404, or the reverse.** A policy with a
  filter check gives an empty table; a strict policy gives a refusal. The
  table shows which of the two the resource chose.
- **`authorize? false` for convenience.** It is the whole domain's tables,
  for everybody.
- **Relying on the table to protect a hidden field from being written.** See
  above.

## Not in the first version

No per-table authorization setting beside the domain's, no hiding of single
rows' edit affordance ahead of a save or of a row's buttons ahead of an
action, and no login or session handling: that is the host's. The roadmap
is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
