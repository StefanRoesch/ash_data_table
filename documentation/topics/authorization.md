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
| Ada Admin | Acme's tasks | all 17 | every editable column, on every task | five buttons on every row, each of which runs; "New task" |
| Max Member | Acme's tasks | 16: no "External ref". "Estimate hours" is empty except on the tasks assigned to him | looks editable everywhere; a task that is not his refuses when a cell is saved | five buttons on every row; a task that is not his refuses when an action runs; "New task", without the field "External ref" |
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
| An **argument** of the read action, or of a calculation, is `public? false`, or is not asked for by a column | It is never on the [argument line](arguments.md), and nothing a person sends reaches it. What they give the public ones is given to Ash as they typed it, and Ash casts it. | `/tasks`: "Search", and the days of "Due within". |
| The person can **never run an update action** | The columns it saves are read-only for that person. If that is every editable column, the table offers them no editing at all. | `/tasks` as Vera Viewer. |
| The person may run an update action on **some records only** | Cells look editable. On a record the action refuses, the cell says "You are not allowed to change this." when it is saved. | `/tasks` as Max Member, on a task that is not his. |
| The person can **never run any row action** on several rows | The table has no boxes to select rows with, and no line of buttons above the grid. | `/tasks` as Vera Viewer. |
| The person may run a row action on **some of the selected records only** | It runs on those, and the table says of the others that it did not: "Archive: 2 done, 1 not done.", "You are not allowed to do this. (1)". The others stay selected. | `/tasks` as Max Member, with a task selected that is not his. |
| The person can **never run a row action** | The action has no button for them. If that is every row action, the table has no "Actions" column. | `/tasks` as Vera Viewer; `/projects` as Max Member has "Set status" and no "Destroy". |
| The person may run a row action on **some records only** | The button is on every row. On a record the action refuses, the row's actions cell, or the action panel, says "You are not allowed to do this." | `/tasks` as Max Member: "Archive" on a task that is not his. |
| The person can **never run the create action** | The table has no create button for them. | `/tasks` as Vera Viewer; `/projects` and `/labels` as Max Member. |
| The person can **never run a table action** | The action has no button for them, on the line of the table's name or on the line of a nested table. | `/labels` as Max Member: "Count unused", and neither "Recolour" nor "Remove unused". |
| A table action, or a generic action in a row, is **refused when it runs** (a check on an argument) | The button is there. The refusal is shown as any failure of the action: "You are not allowed to do this." | (none in the demo) |
| The person may create **some records only** | The button is there. A record the action refuses says "You are not allowed to do this." in the panel, and nothing is created. | (none in the demo) |

"No records" is only ever shown for a read that succeeded and found nothing.

None of this depends on how a column is shown. A column with a
[component](custom-components.md), such as "Estimate hours" on `/tasks`, has
the same hidden cells: the component is not called for a value the person
may not see, and it is never given the record.

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
- A reference cell is edited by choosing a record from the destination's
  own table, read as the person. The record that is chosen is read again by
  its key, as the person, before anything is saved: a key gives nobody a
  record to point at that the table to choose from would not show them.
  [Choosing a related record](choosing-a-related-record.md#who-may-choose-what)
  has every case.
- An argument that an action hands to a relationship is given the same
  way, one record or several, and the same holds for every key in it: one
  that was not related already is read as the person before the action
  runs. Where the argument is everything the relationship is to hold, its
  field starts with the related records as Ash reads them for that person
  when the action runs. One they may not read is neither shown nor taken
  away. Whether the relationship may be changed is the action's to say,
  with the policies of what it relates through.
  [Relationships an action manages](managing-relationships.md#who-may-choose-what)
  has every case.

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

## Every action a table runs is public

**A table runs only actions that the resource declares `public?`, however
it came by them**: named in the block, fallen back to, or reached through a
relationship, an aggregate or a calculation. Actions are public unless they say otherwise,
so a resource that marks none of its actions private never meets this rule.

The reason is what the option means in Ash. An action has had `public?`
since Ash 3.20, with the default `true`, and its documentation speaks to
interfaces: "When `false`, the action is internal-only and must not be
exposed by API extensions". Ash itself does not hold anybody to that. It
runs a private action for whoever the policies allow, and the policy that
its documentation gives for a private action allows everybody. This one is
from a resource of the demo's tests
([`demo/test/support/private_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/private_tables.ex)):

<!-- source: demo/test/support/private_tables.ex -->
```elixir
policies do
  bypass private_action?() do
    authorize_if always()
  end

  policy action(:open) do
    authorize_if expr(description == "open")
  end
end
```

`open` is the public read action and returns the open dossiers. The primary
read action of that resource is private, for the application's own code,
and returns every dossier to anybody. What keeps the sealed dossiers from a
person is that no interface runs the private action for them. A table is an
interface, so it does not.

The API extensions do the same. `ash_json_api`, `ash_graphql` and
`ash_typescript` refuse a private action that a route, a query or an RPC
action names, and `ash_json_api` and `ash_typescript` refuse a public
relationship whose read action is private: "Public relationships on JSON:API
resources must have `public?` read actions on their destination resources."

### Which actions

| How the table comes by it | The action | When it is private |
| --- | --- | --- |
| `read_action` in the block | That action. | Reported; the table is refused. |
| No `read_action` | The primary read action. | The same. |
| A relationship a row offers | The relationship's own `read_action`, else the read action of the destination's table. | A declared `relationship` is reported, and the table refused. One of the default set is not offered. |
| A many-to-many a row offers | Besides: the read action of the join resource, which says which records are related at all. It is the `read_action` of the join relationship, else the join resource's primary read action. | The same. |
| A relationship `through` a path of others | Besides: the primary read action of every resource the path passes. | The same. |
| A [reference cell](nested-tables.md#the-reference-cell) | The relationship's own `read_action`, else the destination's primary read action: Ash loads the related record. | Reported; the table is refused. |
| The [picker](choosing-a-related-record.md) of a reference cell, or of a field of the action panel | The relationship's own `read_action`, else the read action of the destination's table: the records to choose from, and the record that was chosen. | Nothing is offered: the cell is read-only, and the field is a typed key. The destination's own table is what is reported. |
| The field of an argument that is [everything a relationship is to hold](managing-relationships.md#what-a-field-starts-with) | Besides the picker's: the relationship's own `read_action`, else the destination's primary read action, and for a many-to-many the read action of the join resource. Ash loads the records that are related now. | The argument is not chosen: one key is typed, and a list of keys has no field. An action that requires such a list is reported. |
| An aggregate column | For every relationship of the aggregate's path: its own `read_action`, else the primary read action of its destination, and the read action of the join resource of a many-to-many. For the last relationship the aggregate's own `read_action` stands in for the primary one. | The same. |
| A calculation column that is an expression | The read actions of every aggregate the expression holds, by name or written out (`count(comments)`), also inside a calculation it references. | The same. |
| `update_action`, `action`, `create_action` | That action: an update, a destroy, a generic or a create action. | The same. |
| Any of those three, where it names an update, a destroy or a create action: the table changes records | The primary read action. Ash loads what a create, an update or a destroy action returns through it, and asks its policies and field policies what of the result the person may have. | The same. A table that only reads is not affected, nor is one whose only actions are generic: Ash loads nothing for those. |

"Reported" is a finding when the resource is compiled, with the path of the
declaration that leads to the action; the messages are in
[Mistakes at compile time](mistakes-at-compile-time.md#a-private-action).
"Refused" is what happens when the resource is compiled all the same: the
table raises when it is built, and reads nothing.

Each finding names two ways out:

- **Make the action public**, if a person may have what it returns. Its
  policies then have to say who.
- **Name a public action** in its place (`read_action` in the block, on the
  relationship, on the join relationship or on the aggregate), or **do not
  offer** what leads to the private one: leave the relationship or the
  column out, or leave the table read-only.

Only what a table offers is looked at: the relationships its rows expand
into and its own columns, not every relationship of the resource. So a
finding can always be settled in the `table` block, without a change to the
resource.

### What a table reads by itself

A table reads more than its pages. Each of these reads goes through a read
action that was looked at, and each read through the table's own read
action is given the [arguments](arguments.md#where-the-arguments-are-given)
the person gave it on the page:

- **The record of a row, before a cell of it is saved or a row action
  runs**: through the table's read action. A row the table shows is a row it
  can change, also where the primary read action would not return it.
- **The records an action runs on that a person selected**: each through
  the table's read action, by its primary key, before the action is run on
  it; and for "all that match" the keys of everything the filters match,
  through the same action. In a nested table both are read through the row
  it belongs to. What the browser names is a claim: a key reaches no
  record that the table would not show this person. See
  [Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#what-running-does).
- **The record a person chose in the picker**: through the read action the
  picker shows its rows through, by its primary key, before its key is
  saved or put into the action panel. And the record a key of the panel
  points at, by that key, when the panel opens (for what the field calls
  it) and when its button is used (for a key that was put there).
- **The records that are related now**, for the field of an argument that
  is everything a relationship is to hold: the relationship is loaded onto
  the row's record, as Ash loads it when the action runs, through the
  relationship's own `read_action`, else the destination's primary read
  action. When the panel opens, and when its button is used.
- **The row a nested table belongs to**: through the read action of the
  table that shows the row. For a row of the table on the page that is the
  table's read action; for a row of a nested table it is the action that
  nested table reads through, the relationship's own where it names one. A
  row a table shows is a row it can open.
- **The row a [full view](nested-tables.md#the-full-view) is limited to**:
  through the read action of that row's own table, since an address says
  which record and not which table showed it. A key in an address reaches
  no record that the table of that record would not show.
- **What is loaded onto the records of a page in a further step**
  (aggregates, and everything a nested table's columns show besides
  attributes): through the table's read action.
- **A row that is shown again after an action**: as Ash loads the action's
  result, through the primary read action, which is public for every table
  that changes records.

### What it does not reach

What a public action does while it runs is the action's own, as it is for
an API extension. An update action may run its statement over another read
action (`atomic_upgrade_with`; Ash asks no policy of it and shows nothing of
it), manage a relationship through actions of the related resource, or call
anything from a change. A table that named such an update action runs it as
it is.

The actions of an embedded resource are of this kind. Ash runs them while
it casts the value of an attribute the action accepts: the create, update
and destroy actions the attribute's constraints name, else the embedded
resource's primary ones. It runs them whichever interface gave the value,
does not ask whether they are `public?`, and neither do `ash_json_api` and
`ash_graphql`. A table does not name them and does not check them. They
are authorized as the action around them is, with the same actor: an
embedded resource's own policies apply. See
[Maps and embedded resources](maps-and-embedded-resources.md#what-ash-does-with-the-value).

Code of the resource is not looked into either: a calculation computed in
Elixir may load what it likes, and a manual relationship fetches as its
module says.

And what an expression references without an aggregate runs no action at
all: `exists(comments, …)` or `author.name` in a calculation is a join, to
which Ash applies no policy of the related resource, whichever read action
the relationship names. That is the subject of
[the warning about protected fields](columns-and-defaults.md#aggregates-and-calculations-over-protected-fields),
not of this rule.

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

A table action, and a generic action in a row, are asked about once too,
and without their arguments: before a button is used there are none. A
generic action is given no record, so Ash allows its policy no check on
one. It can look at the actor, which Ash answers ahead, and at an
argument, which answers when the action runs. See
[Table actions](table-actions.md#who-may-run-what).

So does an action on the rows a person has selected. Its button is on the
line above the grid unless the person can never run it. When it runs, the
action's policy answers for each record by itself, as it would from that
record's row: a bulk action is never one statement in which the policy is
turned into a filter. The records it refuses are counted and stay
selected. See
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#who-may-run-what).

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

The panel of an action on several selected rows goes one step further. An
attribute the person sees on some records only is no field of it at all:
over a selection the table cannot say on which records they see it, and it
does not read them to find out.

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
  person, through the table's read action, before the action runs, so a
  record that has left their reach since says "This record is no longer
  available."
- **An `act` or `create` event from a person who can never run the action
  is not run**, and opens no panel: the action is looked up among the ones
  the table offers that person.
- **A row action cannot reach a record the person cannot read.** As for a
  save, the event names a row of the person's own page, and the record is
  read again as the person before the action runs, and for a panel before
  it opens.
- **No event reaches a private action.** A table that would run one is not
  built, so there is nothing to send an event to. A relationship of the
  default set that leads to one has no line, and a `toggle` event that
  names it opens nothing.
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
- **A private primary read action under a table that edits.** The table
  names a public read action, and is refused all the same: Ash loads what
  an update returns through the primary one. Make it public, or keep the
  table read-only.
- **A relationship that is not under the row, with nothing reported.** Its
  read action is private, or that of its join resource is, and the block
  declares no `relationship`: it is left out of the default set, as one
  whose destination has no table is. Declare it to be told why.
- **A join resource whose primary read action is private.** Nobody names a
  join resource in a table, and Ash reads it for every many-to-many. Give
  the join relationship a public `read_action`.

## Not in the first version

No per-table authorization setting beside the domain's, no hiding of single
rows' edit affordance ahead of a save or of a row's buttons ahead of an
action, and no login or session handling: that is the host's. The roadmap
is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
