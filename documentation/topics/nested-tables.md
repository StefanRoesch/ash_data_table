# Nested tables

A row of a table expands into the tables of its related records. This guide
covers which relationships a row offers, what each kind's table can do, how
deep a person can go, how a nested table is read and what it shows a person
who may not see everything, its keyboard use, and the full view that opens
its records on a page of their own. The last part is the reference cell,
which shows a related record in place of its key.

## The smallest example

There is nothing to declare. A row offers every public relationship whose
destination resource has a table. The demo's projects have one
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
has_many :tasks, Demo.Tracker.Task, public?: true
```

`Demo.Tracker.Task` lists `AshDataTable.Resource`, so a project's row has an
expander.

**Try it:** `/projects` as Ada Admin. Click the mark at the start of "Mobile
app": a line "Tasks" appears under the row. Click it: the project's tasks,
in the table `/tasks` shows, with its own sortable headings, filter row and
pages ("1–25 of 57"). Edit a title in it. Neither the projects around it
nor the page's address change.

Three words, as this guide uses them:

- The **expander** is a row's first cell (after the selection box, where
  rows can be selected). It opens and closes what is under the row.
- A **relationship line** is one relationship of the expanded row, under
  it. It opens and closes the nested table.
- A **nested table** is the destination resource's table, as that resource
  declares it, limited to the records related to the row.

A table whose resource offers nothing has no expanders and no column for
them: `/specimens` in the demo.

## Which relationships a row offers

This is per table. A resource with [named tables](named-tables.md) has a
set of relationships for each, and a `relationship` can name which of the
destination's tables it nests (`table :compact`); else it is the
destination's default table.

With no `relationship` in the `table` block, a row offers every
relationship that

- is `public?`,
- leads to a resource with a table (one that lists `AshDataTable.Resource`),
- is not manual, and
- is read through `public?` actions only: its own `read_action`, else the
  read action of the destination's table; for a many-to-many also the join
  resource's read action (the join relationship's `read_action`, else the
  join resource's primary read action); for a relationship `through` a path,
  the primary read action of every resource on the path.

They appear in declaration order, each under its name in words.

Once one `relationship` is declared, the row offers exactly the declared
ones, in declared order: explicit wins, as with columns. The demo's tasks
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
relationship :comments

# two has-ones that each pick one of many: the one their own sort puts first
relationship :first_comment

relationship :latest_comment do
  label "Newest comment"
end

# many-to-many, to a destination that is not paginated
relationship :labels
# belongs-to: a nested table of one row
relationship :project
relationship :assignee

relationship :reporter do
  label "Reported by"
end
```

`label` replaces the name on the line; `relationship` takes no other
option.

| Demo page | A row expands into | Declared how |
| --- | --- | --- |
| `/tasks` | Comments, First comment, Newest comment, Labels, Project, Assignee, Reported by | the seven lines above |
| `/projects` | Tasks | nothing: the default |
| `/comments` | Task, Author | nothing |
| `/labels` | Tasks | nothing |
| `/task_labels` | Task, Label | nothing |

A declared `relationship` is reported at compile time when it names no
public relationship, when its destination has no table, or when its nested
table would run a private read action (a table runs only `public?` actions,
however it got them). Without a declaration, such a relationship is simply
not offered. See
[Mistakes at compile time](mistakes-at-compile-time.md#a-private-action) and
[Authorization](authorization.md#every-action-a-table-runs-is-public).

## What each kind of relationship looks like

A nested table is the destination's own table: its columns, editing,
filters and row actions. What else it can do follows from the relationship,
because it is read as Ash loads that relationship.

| Relationship | The nested table | Under a row of `/tasks` |
| --- | --- | --- |
| has-many, many-to-many, through: read action with `pagination` | Pages, a total where the action counts, sort and filters. | Comments: keyset pages of 20, "5 records". |
| has-many, many-to-many, through: read action without `pagination` | Every related record, with sort and filters. | Labels. |
| belongs-to, has-one | At most one row. No sort, filters or pages. | Project, Assignee, Reported by; First comment, Newest comment. |
| With `no_attributes?` | Every related record, with sort and filters, even when the action has `pagination`: Ash cannot page it. | (none) |
| has-many, many-to-many, through: read action that requires an argument | Every related record, with sort and filters, once the argument is given in the nested table's [argument line](arguments.md#nested-tables-the-full-view-and-the-picker): Ash cannot page related records through such an action. | (none) |
| Manual | Every related record. No sort, filters or pages: a table cannot know whether the module honours them. Offered only when declared. | (none) |

Which records, in which order:

- **The read action** is the relationship's own `read_action`, else that of
  the destination's table. A relationship that names an action says which
  records it means.
- **The relationship's own `sort` comes first** while the person has chosen
  none. (Ash would put it behind the read action's default sort, where it
  is never seen.) For a has-one with `from_many?` this picks the record: the
  demo's "First comment" and "Newest comment" are one relationship with
  opposite sorts.
- **A person's sort or filter never applies to a single record**: on a
  has-one that picks one of many it would change which one.

**Try it:** `/tasks` as Ada Admin, expand a row. Edit a body under
"Comments", a colour under "Labels", the name under "Project": each saves
through its own table's `update_action`, as on `/comments`, `/labels` and
`/projects`. Under "Assignee" no cell opens: the people's table names no
`update_action`, so it is read-only everywhere.

The demo has no `no_attributes?` and no manual relationship; the library's
tests have both
([`test/support/relating.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/test/support/relating.ex)):

<!-- source: test/support/relating.ex -->
```elixir
has_many :by_the_same_author, __MODULE__ do
  no_attributes? true
  filter expr(author_id == parent(author_id) and id != parent(id))
  public? true
end

has_many :manual_notes, AshDataTable.Test.Relating.Note do
  manual AshDataTable.Test.Relating.ManualNotes
  public? true
end
```

## Row actions and create in a nested table

A nested table has the destination table's actions column, and its buttons
do what they do on the destination's own page: under a task, a comment has
"Destroy", and a label has it for an admin.

It also has that table's selection boxes, where the destination's table has
a row action that runs on several rows. Its selection is its own, with its
own line above its grid, and an action on it runs only on the records under
its row. See
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#nested-tables).

Create is offered only where the relationship is a has-many joined by
attributes and the destination table's `create_action` accepts the
relationship's destination attribute. The table fills that attribute from
the row above (read again as the person) and leaves it out of the panel.
The button is at the far end of the relationship line once the nested table
has read: "New comment" under a task, "New task" under a project.
Belongs-to, has-one, many-to-many, manual and `no_attributes?`
relationships offer none.

**Try it:** `/projects` as Ada Admin: expand "Mobile app", open "Tasks",
use "New task". The panel has no "Project ID", and the new task is the
nested table's first row.

The full rule and the panel:
[Row actions and create](row-actions-and-create.md#creating-in-a-nested-table).

## `max_depth`

A nested table's rows expand again: a task's project, its tasks, their
comments. `max_depth` says how deep a person can go, counted from the table
on the page, whose nested tables are depth 1. The default is 3; tables at
that depth have no expanders.

The setting of the table **on the page** counts for everything beneath it.
Only `0` also acts elsewhere: a table with `max_depth 0` never expands its
rows, wherever it is shown. The demo's people
([`demo/lib/demo/tracker/user.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/user.ex)):

<!-- source: demo/lib/demo/tracker/user.ex -->
```elixir
# Read-only, and its rows never expand: `max_depth 0` switches off the
# assigned and the reported tasks a row would otherwise offer, wherever
# this table is shown.
table do
  max_depth 0
```

**Try it:** `/tasks`: expand a row, open "Project"; expand the project,
open "Tasks"; expand a task, open "Comments". That is depth 3, and the
comments have no expander. The cycle Task → Comments → Task → Comments ends
the same way. `/task_labels` says `max_depth 1`: the task under one of its
rows has no expander.

## How a nested table is read, and why

A table keeps only its rows' primary keys, so a nested table knows its
parent by a key, and a key does not prove the person may read the record.

So every read of a nested table reads the **parent record, by primary key,
as the person**, with the relationship as a load carrying the nested
table's sort, filters and page. This happens when the line opens and at
every change of the nested table's sort, filters or page.

- **The parent** is read through the read action of the table showing it,
  with the [arguments](arguments.md) that table was given: for a row of the
  table on the page, that table's action; for a row of a nested table, the
  action that nested table reads through. So any row a table shows can be
  opened, and a key reaches no record the table keeps back.
- **The related records** are read through the relationship's own
  `read_action`, else the destination table's read action. For a
  many-to-many Ash reads the join resource on the way, through the join
  relationship's `read_action`, else the join resource's primary read
  action; its policies decide which records are related at all.
- If the parent is gone or no longer readable, Ash returns nothing, and the
  nested table says so.
- What "related" means is up to Ash's loader for every kind: a
  relationship's `filter`, a many-to-many's join resource, a manual
  relationship's module.
- The destination's policies and field policies apply to nested rows as on
  their own page.

Nothing is fetched before a line opens. Expanding a row sends one event and
reads nothing.

**Columns beyond attributes are read in further steps.** A nested table's
records are read bare; its calculations, aggregates and reference cells
are then loaded onto them as the person (`Ash.load/3`). (A table of its own
reads calculations with the page and aggregates in a step after.) Loaded
in a separate statement onto records already read, they leave the page in
its order.

## What a person may not see

| The resource says | Under an expanded row |
| --- | --- |
| The person can never read the destination (refused outright) | No line. |
| The person may not read some related records | Those rows are absent and not counted. |
| The person can never see a field of the destination | No column for it. |
| The person sees a field on some records only | The column stays; hidden cells are empty, announced as "Not available". |
| The person can never run an update action of the destination | Its columns are read-only. |
| The person can never run a row action of the destination | No button for it; no actions column when that is every one. |
| The person can never run the destination's create action | No create button on the line. |
| The person can never run a table action of the destination | No button for it on the line. |
| The parent row is gone or no longer readable | "This record is no longer available." instead of rows. |
| The destination's read becomes refused while the line is open | "You are not allowed to see these records." with `on_forbidden :message` on the destination's table, else "These records are not available." |

A nested table never shows "No records" for a refusal, and never makes the
page answer "not found": its line has already shown there is a table.

**Try it:** `/tasks` as Vera Viewer: no "Assignee" or "Reported by" under a
task, since a viewer's read of people is refused outright. As Max Member,
the tasks under a project on `/projects` have no "External ref", and
"Estimate hours" is "Not available" except on his own tasks.

Whether a line is offered is asked of Ash, without a query, each time the
table around it reads (`Ash.can/3` for the destination's read action). A
person who may read some of the destination's records keeps the line; which
ones is known when they are read. See [Authorization](authorization.md).

## The keyboard

A nested table's controls and editable cells are Tab stops in the same
order as in a table on the page; Tab goes into it and out of it.

| Key | Where | Effect |
| --- | --- | --- |
| Enter, Space | On a row's expander | Opens or closes the row. Focus stays. |
| Enter, Space | On a line's button | Opens or closes the line and its nested table. Focus stays. |
| Tab | On an open line's button | Goes on to the nested table's stops: its "Columns", its argument line, its create button and its table actions on the line, then "Skip table Comments", its header, filters, rows, pages and its link to the full view. |
| Tab | After a nested table's last stop | The parent row's next line, then the next row. |
| Enter | On "Skip table Comments" | Jumps past that nested table only. |

Inside, every key works as in a table on a page. Deeper levels and several
open nested tables behave the same: each stands under its own line, and Tab
goes through them in page order. No key enters or leaves a nested table,
and Escape does not leave one.

Closing a line or row with focus inside moves focus to the line's button or
the row's expander.

All keys, and the Tab order two levels deep:
[Keyboard and accessibility](keyboard-and-accessibility.md#through-nested-tables).

## The full view

A nested table's last row holds "Open in full view", a link to the
destination's own table page limited to the same records: the comments of
this task, on `/comments`, headed e.g. "Write the report: Comments". There
the table has the page's width, its state in the address, and its own
nested tables counted from depth 0.

**Try it:** `/tasks` as Ada Admin: expand a row, open "Comments", follow
"Open in full view". Sort and reload: same comments, same sort. "Show all
records" above the table removes the limit.

### When the link is there

The link is there when the host's router mounts the nested table with an
`ash_data_table` line: the destination's default table, or, if the
`relationship` names another (`table :compact`), that named table's page
and no other. A nested named table mounted nowhere has no link, even if
the default table is mounted. See
[Named tables](named-tables.md#the-full-view-of-a-nested-named-table).

For the default table, the library takes the first route in the router's
order (`Phoenix.Router.routes/1`) whose `ash_data_table` names the
destination resource without `table:` and whose path has no parameter. The
demo mounts five tracker tables
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/tasks", Demo.Tracker.Task, layout: {DemoWeb.Layouts, :tasks}
ash_data_table "/projects", Demo.Tracker.Project
ash_data_table "/comments", Demo.Tracker.Comment
ash_data_table "/labels", Demo.Tracker.Label
ash_data_table "/task_labels", Demo.Tracker.TaskLabel
```

`Demo.Tracker.User` has a table and no page, so under a task "Comments",
"Labels" and "Project" have the link and "Assignee" and "Reported by" have
nothing in its place.

A table placed with `<AshDataTable.table>` in a page of your own links the
same way (the tasks on the demo's `/dashboard`). The link is a live
navigation; LiveView turns it into a page load where the destination is in
another `live_session`.

### The address

The limit is one more parameter of the table, under its id:

<!-- sketch -->
```text
/comments?comment[of][task][comments]=3f649715-4294-4816-9e2a-02c24949cef5
```

| Part | Is |
| --- | --- |
| `comment` | the id of the table on the page |
| `of` | the parameter |
| `task` | the short name of the parent's resource (`Ash.Resource.Info.short_name/1`); followed by `_` and the table's name where a named table of the parent offers the relationship (`task_board`) |
| `comments` | the name of the parent's relationship |
| the value | the parent's primary key |

A primary key of several attributes is written by attribute:

<!-- sketch -->
```text
/tasks?task[of][task_label][task][label_id]=13eeb792-…&task[of][task_label][task][task_id]=00a93d01-…
```

Sort, filters and page sit beside it and work as on any page; the limit
stays in the address through them and in shared links. "Show all records"
drops the limit along with the sort, filters and page chosen under it.

### What the address cannot do

The parent in the address is looked up, never trusted:

1. **The parent's resource is found by short name** among the resources of
   the domains in `config :my_app, ash_domains: […]` (the app of the host's
   endpoint) and of the table's own domain. The name is compared as text;
   no module is made from it, nothing is called by it.
2. **Only a relationship the parent's table offers this person counts**,
   and only one leading to the table on the page: public, with a
   destination that has a table, among the declared ones where the parent's
   block declares any, from a table whose rows expand (not `max_depth 0`),
   to a destination the person is not refused.
3. **The key's values are cast** to the primary key's types.
4. **The parent is read as the person on every read**, as for a nested
   table, through the read action of the parent's own table: an address
   says which record, not which table showed it. A key of a record not
   theirs, or that the parent's table would not show, gives nothing. That
   includes a row only a nested table showed, through a relationship whose
   own `read_action` returns more than its destination's table: its full
   view says "This record is no longer available."

A limit that fails the first three is ignored silently: the page shows the
unlimited table, and the person's next change writes a clean address.

| In the address | The page shows |
| --- | --- |
| `comment[of][nothing][comments]=…`, `comment[of][Elixir.Demo.Tracker.Task][comments]=…` | The table, not limited. |
| `comment[of][task][labels]=…` (a relationship to another resource), `task_label[of][task][task_labels]=…` (a private one) | The table, not limited. |
| `comment[of][task][comments]=not-a-key` | The table, not limited. |
| `task[of][user][assigned_tasks]=…` (the people's table says `max_depth 0`) | The table, not limited. |
| `comment[of][deadline][comments]=…` (the parent's table reads through an action that requires an argument, which an address cannot give it) | The table, not limited. Such a table has no "Open in full view" under its nested tables either. |
| The key of a task that does not exist, or of one in another organization | "This record is no longer available.", no rows, and a heading that names no record. |

### The heading

Above the grid, the table names its limit: the record, a colon, and the
relationship as its line is labelled. Beside it is "Show all records",
preceded by the create button where the nested table would have one on its
line (a record created there goes under the same parent), with the
buttons of the table's [table actions](table-actions.md) between the two.
The line of the page's own name, above, then has neither.

The record is called by the first of these the person sees on it:

1. the attribute the parent's `table` block names as `label_field` (see
   [the reference cell](#the-reference-cell));
2. the parent table's attribute columns, in order.

It comes only from the parent as read for the person. A value a field
policy hides is skipped; a record not read for them is not named, and the
heading is the relationship alone. Where the router mounts the parent's
table, the record's name links to that page.

The demo's labels are called by their name
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/label.ex)):

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
# No `column`: the table shows the public attributes, and edits those its
# `update` action accepts. A label is called by its name: over the tasks of
# one label, in their full view.
table do
  update_action :update
  label_field :name
  # ...
end
```

(`# ...` stands for lines left out.) Without it, the tasks of a label would
be headed by the label's first column, its ID.

### What is the same as in a nested table, and what is not

The page is read as the nested table is: through the parent, with the
relationship's own read action and sort, no sort, filters or pages for a
single record, and in full where Ash cannot page.

It differs as a table of its own differs from one in a cell: its state is
in the address, its first read happens while the page mounts, and a
destination whose read is refused outright is the page's refusal: 404, or
"You are not allowed to see these records." with `on_forbidden :message`.

**Going back.** The browser's back button returns to the linking page with
its own sort, filters and page from its address. Rows expanded there are
closed: expansion is in no address.

## How a nested table looks

The default kit keeps the nesting readable:

- **The open row stays tinted** in the primary colour, with a bar at its
  left edge.
- **One line down the left of the nested area**, in the primary colour at
  reduced strength, starting under the open row's bar, then one inset about
  an expander wide. Each deeper level adds its own line and inset, in the
  same colour.
- **A title per relationship**: its arrow opens and closes that nested
  table; while open and once read, it says how many records there are (where known: the
  read action counts, or there is one page). While open, the title is the
  nested table's heading line, as above a table on the page: after name
  and count, its "Columns" and argument-line inputs, and at the far end its
  create button and table actions. One line, wrapping only where it does
  not fit. Below it, the selection line takes room only while rows are
  selected or a filter is set, as on the page.
- **About a row of space between two nested tables**, no card around them,
  and **one stronger rule** where the nested area ends.
- With `sticky_header`, a nested table is about ten rows high and scrolls
  by itself, its header staying in view: see
  [Layout and embedding](layout-and-embedding.md#a-header-that-stays-in-view).

Every tint is mixed from the theme's colours. In forced colours the tints
go, and lines and borders carry the structure.

## How a nested table is drawn

The table on the page draws every table it shows. A nested table is moved
into the cell under its relationship line through a portal (`<.portal>`),
and its heading line onto the relationship line through a second one. It is
no live component of its own, however the table on the page is placed (see
[Layout and embedding](layout-and-embedding.md)).

- **It uses the kit of the table on the page**; its action panel, picker
  and question open as that table's do, over the page or in it. See
  [Kits](kits.md).
- **Controlled mode reaches it.** Where the page draws its table's
  questions, panels or pickers, it draws the nested tables' too: see
  [Controlled mode](controlled-mode.md).
- **Its events go to the page of the table on the page**, with `path`, the
  ids from that table down to the nested one. See
  [Events and commands](events-and-commands.md).
- **`Phoenix.LiveViewTest` does not look into a portal.** In tests,
  `AshDataTable.Test.page/1` reads the page as the browser shows it,
  `AshDataTable.Test.send_event/5` sends a nested table its event, and
  `AshDataTable.Test.send_form/5` one of its forms. See
  [Testing](testing.md).

## Performance

- Each nested table has its own stream. The server keeps its page's keys,
  its state and its table model, no records. LiveView keeps the rows last
  sent in its change tracking until the next render; the table stores no
  rows.
- An event of one nested table sends and patches only that table, however
  many are open.
- It queries when opened, sorted, filtered or paged, and when a cell is
  saved or an action run in it.
- While an action panel is open, its table also keeps the panel's form and,
  for a row action, the record it opened with.

Statements per read, counted on Postgres with the demo's data
([`demo/perf/NESTED.md`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/perf/NESTED.md)
has the browser run the times come from):

| Read | Statements | From click to rows |
| --- | --- | --- |
| `/tasks` → Comments (has-many, keyset, counted) | 2: the parent with the count, the page | 37 ms |
| `/tasks` → Labels (many-to-many, in full) | 2 | 38 ms |
| `/tasks` → Project (belongs-to) | 2 | 36 ms |
| `/tasks` → Newest comment (has-one of many) | 2 | 35 ms |
| `/projects` → Tasks (page of 25, counted; a calculation, an aggregate and three reference cells among the columns) | 9 | 77 ms |

The page's LiveView process holds about 20 KiB more per open nested table
after a garbage collection: 0.3 MiB with 10 open under one page of
`/tasks`, 1.1 MiB with 50. Nested tables of one relationship share one
table model. Opening one more slows as they add up, from about 40 ms for
the first to about 90 ms with fifty open. Rendering and scrolling with
fifty grids on a page were not measured.

## The reference cell

A column that names a belongs-to relationship shows the related record's
**label** in place of its key. The demo's tasks have three
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# Reference cells: each names a belongs-to relationship and shows the
# related record's label, the `label_field` of that resource's table, in
# place of the key. Neither sorted nor filtered by.
#
# ...
column :project do
  confirm "Move this task to another project?"
end

column :assignee

# No update action accepts `reporter_id`: read-only.
column :reporter do
  label "Reported by"
end
```

The label is declared where the record lives: `label_field` in the
destination's `table` block. A person is called by their name
([`demo/lib/demo/tracker/user.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/user.ex)):

<!-- source: demo/lib/demo/tracker/user.ex -->
```elixir
# What a person is called where a table shows them as one value: in the
# "Assignee" and "Reported by" columns of /tasks.
label_field :name
```

**Try it:** `/tasks` as Ada Admin: the last three columns, "Project",
"Assignee" and "Reported by", hold names. On `/comments`, "Task ID" and
"Author ID" are the keys themselves: that table has no `column`, so it
shows the public attributes.

- **Its column names a public belongs-to relationship** whose destination
  has a table with a `label_field`, which names a public attribute.
  Anything else is reported at compile time.
- **The related record is read through a `public?` action**; a relationship
  leading to a private one is reported (see below).
- **It is shown as the label's type is**: text as text, an enum by its
  labels.
- **It is edited by choosing another related record** where the column's
  update action accepts the foreign key or takes the related record through
  an argument: Enter on the cell opens the picker with the destination's
  own table. Otherwise it is read-only. See
  [Choosing a related record](choosing-a-related-record.md) and
  [Relationships an action manages](managing-relationships.md#a-reference-cell-that-is-edited-through-an-argument).
- **It is not sorted by** in this version.
- **It is not filtered by** in this version.
- **It is not in the default set.** A table without `column` shows the
  public attributes, the foreign key among them when public.

### How it is read

The label is read as Ash loads the relationship: one statement per
reference column per page, selecting the related records' primary key and
label, as the person. Never an aggregate or a calculation over the
relationship: that would save a statement but apply less than the
destination's policies; see
[Columns and defaults](columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).

Ash loads a relationship through its own `read_action`, else the
destination's **primary** read action; the read action the destination's
table names serves that table and its nested tables, not loads. Whichever
it is must be `public?`. A destination with a private primary read action
can still be shown, if the relationship names a public action, as in this
resource from the demo's tests
([`demo/test/support/private_tables.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/support/private_tables.ex)):

<!-- source: demo/test/support/private_tables.ex -->
```elixir
belongs_to :dossier, Demo.Support.Vault.Dossier do
  source_attribute :project_id
  read_action :open
  public? true
  attribute_public? true
  attribute_writable? true
end
```

The destination decides what the cell shows:

| The destination says | The cell |
| --- | --- |
| There is no related record | Empty. |
| The person may not read the related record | Empty: Ash returns nothing, as for none. |
| The person may read the record but not its label field | Empty, announced as "Not available": a hidden field's cell. |
| The person can never read the destination, or never see its label field | The column is left out for them. |

The first two are the same cell on purpose: a person who may not read the
related record is not told through it that one exists. If the table also
shows the foreign key as a column they can compare the two; that is the
resource's choice, settled by a field policy on the key.

**Try it:** `/tasks` as Vera Viewer: no "Assignee" or "Reported by" (a
viewer may not read people), but "Project". As nobody it is the reverse:
projects are refused outright when nobody is logged in.

The label is read again with the row after one of its cells is saved, and
in a nested table for each of its rows.

## Edge cases

- **The argument line** of a nested table is that of the action it reads
  through, whichever table's it is, and keeps its own values, like its sort
  and filters: see
  [Arguments](arguments.md#nested-tables-the-full-view-and-the-picker).
- **A record that no longer matches the relationship stays** until the
  nested table reads again. A saved comment or task under a row shows what
  the action returned, as on a page.
- **The parent row's cells do not follow.** After a comment is created or
  deleted or a task edited below it, the parent's aggregates stay as read:
  a task's "Comments" cell keeps the old count.
- **A new read of a table closes what is open in it.** A change of its
  sort, filters or page forgets which rows were expanded. A save in a row,
  and a row action that changes it, keep what is open under it; a destroy
  removes the row and everything under it.
- **A many-to-many edits the destination**, not the join: a label edited
  under one task changes for every task carrying it. The join resource's
  fields are not columns of the destination's table.
- **A destination readable only through the relationship** (a policy with
  `accessing_from/2`) shows its rows nested but can neither be edited there
  nor expanded further: both read the record by its key, outside the
  relationship.
- **Several routes for one resource**: the link goes to the first in router
  order. The demo mounts labels at `/labels` and `/bare/labels`; the link
  goes to `/labels`.
- **Two resources with one short name** that both have such a relationship
  to the table: the address could not say which, so the nested table has no
  link and such a limit is ignored.
- **A parent resource outside the application's domains and the table's
  own domain** is not found: no link.
- **A reference cell to a destination whose read becomes refused while the
  page is open**: a saved row shows the cell as "Not available". With
  `allow_forbidden_field? false` on the relationship, the refusal fails the
  whole read, shown as the refusal of the table's own read.
- **Hidden columns.** A nested table has its own "Columns" button on its
  line, named for it ("Columns of Comments"); what is hidden there is its
  alone. Closing and reopening the line shows every column again. Hiding
  columns of the table around it leaves the nested table as wide as the
  visible part of that table. See
  [Columns and defaults](columns-and-defaults.md#hiding-columns).
- **Column widths** of a nested table are changed as in any table and are
  its alone; closing and reopening the line restores the first layout. See
  [Columns and defaults](columns-and-defaults.md#column-widths).
- **A join resource's policy does not restrict an aggregate over a
  many-to-many.** Seen in one investigation, not verified independently. If
  the join resource's policy is what hides some related records, do not
  rely on it for an aggregate column.

## Things people trip over

- **A relationship is missing under the row:** it is not `public?`; its
  destination does not list `AshDataTable.Resource`; it is manual, or read
  through a private action (its own or its join resource's), and not
  declared; or the block declares others. For one person only: they can
  never read the destination.
- **Declaring one `relationship` removes the defaults**, as one `column`
  does.
- **`max_depth` on the nested resource has no effect:** the table on the
  page decides, except for `0`.
- **The nested table's state is not in the address.** Open the full view
  for a shareable link.
- **No full-view link:** the destination is not mounted with
  `ash_data_table`.
- **A UUID in the heading:** the parent's table has no `label_field`, and
  its first column is the key.
- **`column :author` reports that the destination declares no
  `label_field`:** the label is declared on the destination's table, not
  the column.
- **A sort by an aggregate that the page offers and the nested table does
  not:** the nested table reads through another action, which pages by
  keyset, or a field policy hides the aggregate on some records. See
  [Reading, sorting and pagination](reading-sorting-and-pagination.md#sorting).

## Not in the first version

No count on a closed relationship line (the count shows only while the line
is open, once its nested table has read), no creating under a many-to-many, a
has-one or a belongs-to (an existing record is linked by a row action: see
[Relationships an action manages](managing-relationships.md)), no sorting
or filtering by a reference cell, no label that is a calculation, no link
from a reference cell to its record, and nothing of a nested table in the
address but its full view. Later slices are in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
