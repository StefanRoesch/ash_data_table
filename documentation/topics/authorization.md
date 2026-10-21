# Authorization

The table has no authorization rules of its own. It passes the actor and the
tenant into ordinary Ash calls, asks Ash what the person may see and do, and
shows the answer.

## The smallest example

Nothing goes in the `table` block. The page of a router line reads who is
asking from the socket assigns your `on_mount` hook sets; in the demo that is
`DemoWeb.Actor`
([`demo/lib/demo_web/actor.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/actor.ex)):

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

Mount the tables inside the `live_session` that runs this hook; that is all
the wiring.

**Try it:** `/tasks` in the demo, switching person with "Acting as" in the
page header:

| Actor | Rows | Columns | Editing | Row actions and "New task" |
| --- | --- | --- | --- | --- |
| Ada Admin | Acme's tasks | all 17 | every editable column, on every task | five buttons on every row, each of which runs; "New task" |
| Max Member | Acme's tasks | 16: no "External ref". "Estimate hours" is empty except on the tasks assigned to him | looks editable everywhere; a task that is not his refuses when a cell is saved | five buttons on every row; a task that is not his refuses when an action runs; "New task", without the field "External ref" |
| Vera Viewer | Acme's tasks | 14: as the member, and no "Assignee" and no "Reported by", since a viewer may not read people | none | no actions column, no "New task" |
| Olga Outsider | Globex's tasks | 16, as the member | as the member, on Globex's tasks | as the member, on Globex's tasks |
| Nobody | none: "No records" | 14: no "External ref", no "Estimate hours" and no "Project" | none | none |

The counts leave out the expander column and the "Actions" column.

## Where actor and tenant come from

The page of a router line (`ash_data_table "/tasks", MyApp.Tracker.Task`)
looks at three socket assigns:

1. `current_scope`, when assigned and not nil, is passed to Ash as the
   `scope`. It must implement `Ash.Scope.ToOpts` and carries actor and
   tenant.
2. Otherwise `current_user` is the actor and `current_tenant` the tenant.
3. A missing assign counts as nil. With none, nobody is logged in. That is
   no error: the table shows what the resource leaves to an anonymous
   visitor.

If an `on_mount` hook of yours assigns another user, scope or tenant while
the page is open (a login elsewhere, say), the page attaches its table again
as that person before the rest of the callback runs: expanded rows close,
the picker goes, the table reads anew.

Who may open the page at all is for your router, pipelines and
`live_session`, as for any LiveView.

A table in your own LiveView ignores the assigns and is told who is asking:
a tag (`<AshDataTable.table>`) takes `scope`, or `actor` and `tenant`, as
attributes; `AshDataTable.attach/4` takes them as options. New attributes,
or attaching again under the same name, make it read anew as the new
person. See [Layout and embedding](layout-and-embedding.md).

## The domain section

The assign names, and whether the tables authorize at all, are settings of
the resource's domain, with the extension `AshDataTable.Domain`. The demo's
tracker writes the defaults out
([`demo/lib/demo/tracker.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker.ex)):

<!-- source: demo/lib/demo/tracker.ex -->
```elixir
use Ash.Domain, otp_app: :demo, extensions: [AshDataTable.Domain]

# How the tables of these resources authorize, and under which socket
# assigns a mounted table finds who is asking. These are the defaults,
# written out; `DemoWeb.Actor` sets the two assigns.
table do
  authorize? true
  actor_assign :current_user
  tenant_assign :current_tenant

  # Live updates: the resources that say `live? true` (the tasks and the
  # comments) announce their changes through this server, and their
  # tables listen to it.
  pub_sub Demo.PubSub
end
```

(`pub_sub` is for [live updates](live-updates.md), not authorization.)

| Option | Default | Meaning |
| --- | --- | --- |
| `authorize?` | `true` | Whether the tables of this domain's resources authorize. |
| `scope_assign` | `:current_scope` | The socket assign holding an `Ash.Scope`. |
| `actor_assign` | `:current_user` | The socket assign holding the actor, used when there is no scope. |
| `tenant_assign` | `:current_tenant` | The socket assign holding the tenant, used when there is no scope. |

The extension is optional; without it a domain has these defaults. Other
assign names are said once per domain, as in this domain for the demo's
tests
([`demo/test/support/guarded_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/guarded_tables.ex)):

<!-- source: demo/test/support/guarded_tables.ex -->
```elixir
table do
  scope_assign :viewer_scope
  actor_assign :reader
  tenant_assign :reader_organization
end
```

There is no fallback to the conventional names: with `actor_assign :reader`,
a `current_user` on the socket is ignored.

### `authorize? false`

From the same file, a domain whose tables do not authorize:

<!-- source: demo/test/support/guarded_tables.ex -->
```elixir
table do
  authorize? false
end
```

**`authorize? false` removes every check.** The domain's tables read and
save with no policy and no field policy, for anyone, even nobody: every
record the read reaches, every column, every declared edit. The resource
behind this example forbids everything, and its table shows and saves
everything. Use it only behind a gate of your own, such as an admin area
the router already restricts.

### `authorize?: false` on one page

The same for one mounted page, in the router. The demo's test routes mount a
table twice, once as its domain says and once without authorization
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/closed/cases", Demo.Support.Closed.Case, layout: false
ash_data_table "/closed/entries", Demo.Support.Closed.Entry, layout: false
ash_data_table "/open/cases", Demo.Support.Closed.Case, layout: false, authorize?: false
```

Every read and action of that page gets `authorize?: false`, as in
`Ash.read/2`: also its nested tables, pickers and actions on selected rows.
With no check, every public column and every declared action is offered.

> **Warning: this page shows everything to whoever can open it.** No policy
> and no field policy applies. Use it only for a page your own code already
> protects (an admin area behind a pipeline and an `on_mount` hook that let
> only administrators in), never for a page anybody can reach.

What stays:

- Only `public?` fields are columns, and only `public?` actions run.
- Actor and tenant are still passed to Ash: a change that reads the actor
  finds it, a multitenant resource still needs its tenant.
- A sensitive column is still masked.

| Said where | Applies to |
| --- | --- |
| `authorize? false` in the domain's `table` block | every table of the domain's resources |
| `authorize?: false` on an `ash_data_table` line | that page, and the tables nested in it |
| `authorize?={false}` on `<AshDataTable.table>` | that table, and the tables nested in it |
| `authorize?: false` given to `AshDataTable.attach/4` | that table, and the tables nested in it |

Route, attribute and option win over the domain in both directions
(`authorize?: true` authorizes a table of a domain that says `false`).
Nothing in a URL, a session or an event can change it.

A nested table links to its full view only on a page mounted the same way,
with or without authorization.

**Try it:** these routes exist in the demo's test environment only. Run
`mix test test/demo_web/tables/unchecked_table_test.exs` in `demo/`: the
resources forbid everything, the "closed" pages answer "not found", the
"open" pages read, save and run every action.

## What each restriction looks like

| The resource says | The table shows | In the demo |
| --- | --- | --- |
| Some **records** are not the person's: a policy that filters | Those rows are not there and not counted. Nothing indicates them. | `/tasks` as Olga Outsider: Globex's tasks only; as nobody, "No records". |
| The read is **refused outright**: a `Forbidden` error, as from an `access_type :strict` policy | The page answers as if it did not exist: status 404 and your "not found" page. With `on_forbidden :message` it stays and says "You are not allowed to see these records." | `/projects` as nobody: 404; `/comments` as nobody: the message. |
| A field is **never visible** to them: a field policy on the actor only | No column for them: no heading, filter or cells. A URL that sorts or filters by it is ignored. | "External ref" on `/tasks`: Ada Admin only. |
| A field is visible on **some records only**: a field policy with a check on the record | The column stays. Hidden cells are empty, announced as "Not available", and not editable. | "Estimate hours" on `/tasks` as Max Member. |
| A **related resource** that a column or row leads to is **never readable** | No column for a [reference cell](nested-tables.md#the-reference-cell) of that relationship, no line for it under an expanded row. | `/tasks` as Vera Viewer: no "Assignee" column or line. |
| **One related record** is not readable | Its reference cell is empty, as for none. In a nested table its row is not there. | A task assigned to somebody of another organization. |
| An **argument** of the read action or of a calculation is `public? false`, or no column asks for it | Never on the [argument line](arguments.md); nothing a person sends reaches it. Values for the public ones go to Ash as typed, and Ash casts them. | `/tasks`: "Search", and the days of "Due within". |
| An **update action** is **never** allowed | The columns it saves are read-only for them. If that is every editable column, no editing at all. | `/tasks` as Vera Viewer. |
| An update action is allowed on **some records only** | Cells look editable. On a refused record, saving says "You are not allowed to change this." | `/tasks` as Max Member, on a task not his. |
| **No row action** is ever allowed on several rows | No boxes to select rows, no button line above the grid. | `/tasks` as Vera Viewer. |
| A row action is allowed on **some selected records only** | It runs on those and reports the others: "Archive: 2 done, 1 not done.", "You are not allowed to do this. (1)". The others stay selected. | `/tasks` as Max Member, with a task selected that is not his. |
| A **row action** is **never** allowed | No button for it. If that is every row action, no "Actions" column. | `/tasks` as Vera Viewer; `/projects` as Max Member: "Set status", no "Destroy". |
| A row action is allowed on **some records only** | The button is on every row. On a refused record the row's actions cell, or the action panel, says "You are not allowed to do this." | `/tasks` as Max Member: "Archive" on a task not his. |
| The **create action** is **never** allowed | No create button. | `/tasks` as Vera Viewer; `/projects` and `/labels` as Max Member. |
| A **table action** is **never** allowed | No button for it, on the line of the table's name or of a nested table. | `/labels` as Max Member: "Count unused", no "Recolour" or "Remove unused". |
| A table action, or a generic action in a row, is **refused when it runs** (a check on an argument) | The button is there; the refusal shows as any failure: "You are not allowed to do this." | (none in the demo) |
| Create is allowed for **some records only** | The button is there. A refused record says "You are not allowed to do this." in the panel; nothing is created. | (none in the demo) |

"No records" only means a read that succeeded and found nothing.

A column with a [component](custom-components.md), such as "Estimate hours"
on `/tasks`, has the same hidden cells: the component is not called for a
value the person may not see, and never gets the record.

The first two rows differ in one policy line. The tasks' read policy
filters:

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
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
policy action_type(:read) do
  description "Refused outright, not filtered, when nobody is logged in."
  access_type :strict
  authorize_if actor_present()
end
```

The two kinds of hidden field are the tasks' two field policies (`# ...`
marks lines left out):

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

## Related records

A reference cell shows one related record by its label; an expanded row
opens the tables of its related records. Both are decided by the
destination's own policies, with the same actor and the same two kinds of
question:

- A destination the person can **never** read is left out: no reference
  cell column, no nested table line.
- A related record that is not theirs is an empty cell, and no row of a
  nested table.
- A nested table, and a page limited to one parent's records, read that
  parent again as the person on every read. A key in an event or an address
  gives access to nothing.
- A reference cell is edited by choosing from the destination's own table,
  read as the person
  ([Choosing a related record](choosing-a-related-record.md#who-may-choose-what)).
  An argument an action hands to a relationship is chosen the same way, for
  every key not related already; a related record the person may not read
  is neither shown nor taken away. Whether the relationship may change is
  for the action and the policies of what it relates through
  ([Relationships an action manages](managing-relationships.md#who-may-choose-what)).

[Nested tables](nested-tables.md#what-a-person-may-not-see) has every case.

### Aggregates and calculations

Ash's rule, easy to get wrong: an **aggregate** applies the related
resource's read policy but not its field policies; a **calculation** applies
no policy to what it references. Over a protected field, both need a field
policy of their own on the declaring resource. The table shows them as any
column and warns when they are not protected: see
[Columns and defaults](columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).

## Every action a table runs is public

**A table runs only actions the resource declares `public?`**, whether named
in the block, fallen back to, or reached through a relationship, an
aggregate or a calculation. Actions are public by default, so a resource
that marks none private never meets this rule.

Why: actions have had `public?` since Ash 3.20 (default `true`), and Ash's
documentation addresses interfaces: "When `false`, the action is
internal-only and must not be exposed by API extensions". Ash itself runs a
private action for whoever the policies allow, and the policy its
documentation gives for private actions allows everybody. From a resource
of the demo's tests
([`demo/test/support/private_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/private_tables.ex)):

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

`open` is the public read action and returns the open dossiers. The private
primary read action, for the application's own code, returns every dossier
to anybody. Only interfaces not running it keep the sealed dossiers from a
person, and a table is an interface.

The API extensions agree. `ash_json_api`, `ash_graphql` and `ash_typescript`
refuse a private action that a route, query or RPC action names;
`ash_json_api` and `ash_typescript` refuse a public relationship whose read
action is private: "Public relationships on JSON:API resources must have
`public?` read actions on their destination resources."

### Which actions

| How the table comes by it | The action | When it is private |
| --- | --- | --- |
| `read_action` in the block | That action. | Reported; the table is refused. |
| No `read_action` | The primary read action. | The same. |
| A relationship a row offers | Its own `read_action`, else the read action of the destination's table. | A declared `relationship` is reported and the table refused; one of the default set is not offered. |
| A many-to-many a row offers | Also the join resource's read action, which says which records are related at all: the join relationship's `read_action`, else the join resource's primary read action. | The same. |
| A relationship `through` a path of others | Also the primary read action of every resource on the path. | The same. |
| A [reference cell](nested-tables.md#the-reference-cell) | The relationship's own `read_action`, else the destination's primary read action: Ash loads the related record. | Reported; the table is refused. |
| The [picker](choosing-a-related-record.md) of a reference cell, or of an action panel field | The relationship's own `read_action`, else the read action of the destination's table: the records to choose from, and the chosen one. | Nothing is offered: the cell is read-only, the field a typed key. The destination's own table is reported. |
| The field of an argument that is [everything a relationship is to hold](managing-relationships.md#what-a-field-starts-with) | Besides the picker's: the relationship's own `read_action`, else the destination's primary read action, plus the join resource's for a many-to-many. Ash loads the records related now. | Not chosen: one key is typed, a list of keys has no field. An action that requires such a list is reported. |
| An aggregate column | For each relationship of its path: its own `read_action`, else its destination's primary read action, plus the join resource's for a many-to-many. For the last relationship the aggregate's own `read_action` replaces the primary one. | The same. |
| A calculation column that is an expression | The read actions of every aggregate the expression holds, by name or written out (`count(comments)`), also inside a calculation it references. | The same. |
| `update_action`, `action`, `create_action` | That action: an update, destroy, generic or create action. | The same. |
| Any of those three naming an update, destroy or create action (the table changes records) | The primary read action: Ash loads the action's result through it, and asks its policies and field policies what of the result the person may have. | The same. A table that only reads is not affected, nor one with only generic actions: Ash loads nothing for those. |

"Reported" is a compile-time finding naming the path of the declaration
that leads to the action; the messages are in
[Mistakes at compile time](mistakes-at-compile-time.md#a-private-action).
"Refused": if the resource compiles all the same, the table raises when it
is built and reads nothing.

Each finding names the ways out:

- **Make the action public**, if a person may have what it returns; its
  policies then say who.
- **Name a public action** instead (`read_action` in the block, on the
  relationship, the join relationship or the aggregate), or **do not offer**
  what leads to the private one: leave out the relationship or column, or
  keep the table read-only.

Only what a table offers is checked (the relationships its rows expand into
and its own columns), so a finding can always be settled in the `table`
block without changing the resource.

### What a table reads by itself

Besides its pages, a table reads the following, each through a checked read
action. Reads through the table's own read action get the
[arguments](arguments.md#where-the-arguments-are-given) the person gave on
the page.

- **A row's record, before a cell is saved or a row action runs**: through
  the table's read action. A row the table shows is a row it can change,
  even where the primary read action would not return it.
- **Selected records an action runs on**: each by primary key through the
  table's read action, before the action runs on it; for "all that match",
  the keys of everything the filters match, through the same action. In a
  nested table both go through the row it belongs to. A key from the
  browser reaches no record the table would not show this person. See
  [Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#what-running-does).
- **The record chosen in the picker**: by primary key, through the read
  action the picker shows its rows through, before its key is saved or put
  into the action panel. Likewise the record a panel key points at, when the
  panel opens (for the field's label) and when its button is used (for a key
  put there).
- **The records related now**, for an argument that is everything a
  relationship is to hold: loaded onto the row's record as Ash loads it when
  the action runs, through the relationship's own `read_action`, else the
  destination's primary read action; when the panel opens and when its
  button is used.
- **The row a nested table belongs to**: through the read action of the
  table showing the row: the table's own for a row on the page; for a row of
  a nested table, the action that nested table reads through (the
  relationship's own where it names one). A row a table shows is a row it
  can open.
- **The row a [full view](nested-tables.md#the-full-view) is limited to**:
  through the read action of that row's own table, since an address names
  the record, not the table that showed it. A key in an address reaches no
  record that table would not show.
- **What a further step loads onto a page's records** (aggregates, and what
  a nested table's columns show besides attributes): through the table's
  read action.
- **A row shown again after an action**: Ash loads the result through the
  primary read action, which is public for every table that changes
  records.

### What it does not reach

The rule does not cover:

- **What a public action does while it runs**, as for an API extension. An
  update may run its statement over another read action
  (`atomic_upgrade_with`; Ash asks no policy of it and shows nothing of
  it), manage a relationship through actions of the related resource, or
  call anything from a change. The table runs it as it is.
- **An embedded resource's actions.** Ash runs them while casting the value
  of an attribute the action accepts (the create, update and destroy actions
  the attribute's constraints name, else the embedded resource's primary
  ones), whichever interface gave the value, without asking whether they are
  `public?`; nor do `ash_json_api` and `ash_graphql`. They are authorized as
  the surrounding action, with the same actor, and the embedded resource's
  own policies apply. See
  [Maps and embedded resources](maps-and-embedded-resources.md#what-ash-does-with-the-value).
- **Resource code**: a calculation computed in Elixir may load what it
  likes, and a manual relationship fetches as its module says.
- **References without an aggregate**: `exists(comments, …)` or
  `author.name` in a calculation is a join, running no action, and Ash
  applies no policy of the related resource to it, whatever read action
  the relationship names. That is for
  [the warning about protected fields](columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).

## `on_forbidden`

By default a person whose read is refused outright is not told the table
exists. The page of a router line raises `AshDataTable.NotFoundError`, which
Phoenix renders as a missing route; a tag or an attached table, which cannot
make the host's page disappear, renders nothing. `on_forbidden :message`
tells them instead, as on the demo's comments
([`demo/lib/demo/tracker/comment.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/comment.ex)):

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

Use `:message` when people know the table exists and should learn they lack
access; keep `:not_found` when its existence is itself not for everybody.

## What the page adds is no authorization

A page can give its table `context` and `private_arguments` for every call
to Ash, and `before_action`, a veto asked before every write. They serve a
page's own rules (a value an action needs, a write to hold back). Who may
see and do what belongs in the resource's policies, where every interface
meets it. See [Events and commands](events-and-commands.md).

A question (`confirm`) guards the person against a mistake, not the data
against them. The server does not enforce it, also not where the page draws
it ([Controlled mode](controlled-mode.md)), and a hand-made event can skip
it. Leave refusing to the policies, or the veto.

## Why a rule that depends on the record shows on save

On every read (page open, and each change of sort, filter or page) the table
asks Ash three questions, none of which reads a record or runs a query:

- **Which fields can this person never see?** One `Ash.can_see_fields/4`
  call for all columns, one for the attributes its row actions and create
  action accept.
- **Which update actions can they never run?** One `Ash.can/3` call per
  distinct update action, not per cell.
- **Which row actions, and the create action, can they never run?** One
  `Ash.can/3` call per action, not per row.

Ash answers "yes", "never" or "that depends on the record". Only "never"
changes the table: the column is left out or read-only, the button left out.
An answer Ash cannot give counts as "never".

"Depends on the record" leaves the cell looking editable. Checking every
action against every row first would be a check per cell, possibly each on
the database, for an answer that may be stale when the person presses Enter.
So the table asks once per action and leaves one record to the moment the
action runs: its policy answers, and a refusal appears on the cell.

The same goes for:

- **Row actions.** The button is on every row unless the person can never
  run it; a refusal shows on the row's actions cell for an action that runs
  straight away, above the fields for one run from the action panel. See
  [Row actions and create](row-actions-and-create.md#who-may-run-what).
- **Table actions and generic actions in a row**, asked about once without
  their arguments, since there are none before a button is used. A generic
  action gets no record, so Ash allows its policy no check on one. It can
  check the actor (answered ahead) and an argument (answered when it runs).
  See [Table actions](table-actions.md#who-may-run-what).
- **Actions on selected rows.** The button is above the grid unless the
  person can never run it. When it runs, the policy answers for each record
  by itself, as from its row: a bulk action is never one statement with the
  policy turned into a filter. Refused records are counted and stay
  selected. See
  [Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#who-may-run-what).
- **Fields.** Visibility on one record is known once it is read; Ash puts an
  `Ash.ForbiddenField` there, and the table renders the placeholder.

The demo's update policy has both kinds of rule: the viewer's line depends
on the actor only, the member's on the record.

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
forbid_if actor_attribute_equals(:role, :viewer)
authorize_if actor_attribute_equals(:role, :admin)
authorize_if expr(assignee_id == ^actor(:id) or reporter_id == ^actor(:id))
```

## Refusing to edit a hidden field protects the table only

The table does not let a person change a field it does not show them on a
record. That stops at the table.

In the action panel, an attribute the person can never see is no field of a
row action's panel or the create panel; one hidden from them on a record is
no field of that record's panel; a value sent for either is dropped before
the action gets its inputs. On `/tasks`, "New task" has "External ref" for
Ada Admin only. The panel of an action on several selected rows also leaves
out an attribute the person sees on some records only: the table cannot say
on which, and does not read them to find out.

A field policy is about reading. The update action accepts the field from
anyone its *policy* allows: through `ash_json_api`, `ash_graphql` or your
own code, it changes a field the caller cannot see. The same for a create
action. If a field must not be changed by those who cannot see it, say so in
the resource: an action that does not accept it, or a policy or validation
on the one that does.

## Edge cases

- **Filtering and sorting by a field hidden on some records** works and
  gives nothing away: Ash treats a hidden value as empty. A filter by value
  finds only records whose value the person sees; "is empty" also finds
  every hidden one; a sort puts hidden values with the empty ones.
- **A record-dependent field policy that nobody can match.** Nobody is no
  task's assignee, so "Estimate hours" is left out for nobody on `/tasks`.
- **A `save` event from a person who can never run the action** is ignored,
  as for any cell that cannot be edited.
- **A save or row action cannot reach a record the person cannot read.**
  The event names a row of the person's own page; an id not on it does
  nothing. The row's record is read again first (see
  [What a table reads by itself](#what-a-table-reads-by-itself)), for a
  panel also before it opens; a record out of their reach since says "This
  record is no longer available."
- **An `act` or `create` event for an action the person can never run** is
  not run and opens no panel: the action is looked up among those offered
  to that person.
- **No event reaches a private action.** A table that would run one is not
  built. A default-set relationship that leads to one has no line, and a
  `toggle` event naming it opens nothing.
- **A record created in a nested table is joined to the row above by the
  table**, from that row as read again for the person. A key sent with the
  form is ignored.
- **A created record the person may not read** is created, and is no row of
  their table.
- **A public `sensitive?` field is a column, with masked cells.**
  Sensitivity is no access rule, here or in the API extensions: whoever may
  read the field can ask for a cell's value. Hide it with a field policy or
  make it private. See [Sensitive columns](sensitive-columns.md).
- **An error names a field only if the person has its column**; otherwise
  it is shown without the field's name.
- **Columns keep their numbering**: with one left out, assistive technology
  gets the rest numbered without a gap.
- **An aggregate hidden on some records cannot be sorted by** (Ash raises),
  so it is not offered to that person; its filter stays. See
  [Columns and defaults](columns-and-defaults.md#what-a-table-does-not-sort-by).

## Things people trip over

- **Changing who is logged in, in your own LiveView, without telling the
  table.** A tag follows its attributes; an attached table, what it was last
  attached with: attach again under the same name. The router page follows
  its socket assigns by itself.
- **A table mounted outside the `live_session` that assigns the user** reads
  as nobody.
- **Custom assign names without the domain section.** Then only
  `current_scope`, `current_user` and `current_tenant` are read.
- **An empty table that should be a 404, or the reverse.** A filter check
  gives an empty table, a strict policy a refusal.
- **`authorize? false` for convenience.** It covers every table of the
  domain, for everybody.
- **Relying on the table to keep a hidden field from being written.**
- **A private primary read action under a table that edits.** Naming a
  public read action does not help: Ash loads what an update returns through
  the primary one. Make it public, or keep the table read-only.
- **A relationship missing under the row, with nothing reported.** Its read
  action, or its join resource's, is private and the block declares no
  `relationship`, so it is left out of the default set (like one whose
  destination has no table). Declare it to be told why.
- **A join resource whose primary read action is private.** Ash reads it for
  every many-to-many; give the join relationship a public `read_action`.

## Not in the first version

No authorization setting in the `table` block, no hiding of single rows'
edit affordance ahead of a save or of a row's buttons ahead of an action,
and no login or session handling: that is the host's. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
