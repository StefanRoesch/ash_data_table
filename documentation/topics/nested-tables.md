# Nested tables

A row of a table expands into the tables of its related records. After
reading this guide you can say which relationships a row offers, what the
table of each kind of relationship can do, how deep a person can go, how a
nested table is read and what it shows a person who may not see everything,
how it is used from the keyboard, and how its records are opened on a page of
their own. The last part is about the cell that shows a related record in
place of its key.

## The smallest example

There is nothing to declare. A row offers every public relationship of the
resource whose destination resource has a table. The demo's projects have
one
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
has_many :tasks, Demo.Tracker.Task, public?: true
```

`Demo.Tracker.Task` lists `AshTable.Resource`, so a project's row has an
expander.

**Try it:** `/projects` in the demo, as Ada Admin. Click the mark at the
start of the row "Mobile app": one line appears under the row, "Tasks". Click
the line: the tasks of that project, in the table that `/tasks` shows, with
its own headings to sort by, its own filter row and its own pages ("1–25 of
57"). Edit a title in it. Nothing of this changes the projects around it or
the address of the page.

Three words, as this guide uses them:

- The **expander** is the first cell of a row, after the box that selects
  the row where rows can be selected. It opens and closes what is under the
  row.
- A **relationship line** is one relationship of the row, under the expanded
  row. It opens and closes the nested table.
- A **nested table** is the table of the destination resource, as that
  resource declares it, limited to the records related to the row.

A table whose resource has nothing to offer has no expanders and no column
for them: `/specimens` in the demo.

## Which relationships a row offers

With no `relationship` in the `table` block, a row offers every relationship
of the resource that

- is `public?`,
- leads to a resource that has a table (lists `AshTable.Resource`),
- is not a manual relationship, and
- is read through `public?` actions only: its own `read_action` when it
  names one, else the read action of the destination's table; for a
  many-to-many the read action of the join resource as well (the
  `read_action` of the join relationship, else the join resource's primary
  read action); and for a relationship `through` a path of others the
  primary read action of every resource the path passes.

They appear in the order in which the resource declares them, each under its
name in words.

Once one `relationship` is declared, the row offers exactly the declared
ones, in the declared order. This is the rule columns follow: explicit wins.
The demo's tasks declare theirs
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

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

`label` replaces the name on the line. A `relationship` takes no other
option.

| Demo page | A row expands into | Declared how |
| --- | --- | --- |
| `/tasks` | Comments, First comment, Newest comment, Labels, Project, Assignee, Reported by | the seven lines above |
| `/projects` | Tasks | nothing: the default |
| `/comments` | Task, Author | nothing |
| `/labels` | Tasks | nothing |
| `/task_labels` | Task, Label | nothing |

A `relationship` that names something that is no public relationship, or
one whose destination has no table, is reported when the resource is
compiled. So is one whose nested table would run a private read action: a
table runs only `public?` actions, however it came by them. With no
`relationship` in the block, such a relationship is quietly not offered,
like one whose destination has no table. See
[Mistakes at compile time](mistakes-at-compile-time.md#a-private-action) and
[Authorization](authorization.md#every-action-a-table-runs-is-public).

## What each kind of relationship looks like

A nested table is the destination's own table: the columns of its block, its
editing, its filters, its row actions. What it can do beyond showing its
rows follows from the relationship, because it is read as Ash loads that
relationship.

| Relationship | The nested table | In the demo, under a row of `/tasks` |
| --- | --- | --- |
| has-many, many-to-many, through a read action with `pagination` | Pages, a total where the action counts, sort and filters. | Comments: keyset pages of 20, "5 records". |
| has-many, many-to-many, through a read action without `pagination` | Every related record, with sort and filters. | Labels. |
| belongs-to, has-one | At most one row. No sort, no filters, no pages. | Project, Assignee, Reported by; First comment and Newest comment. |
| A relationship with `no_attributes?` | Every related record, with sort and filters, also when the action has `pagination`: Ash cannot page it. | (none) |
| has-many, many-to-many, through a read action that requires an argument | Every related record, with sort and filters, once the argument is given in the nested table's [argument line](arguments.md#nested-tables-the-full-view-and-the-picker): Ash cannot page related records through such an action. | (none) |
| A manual relationship | Every related record. No sort, no filters, no pages: whether its module honours a sort or a filter is not something a table can know. Offered only when declared. | (none) |

Three rules decide which records and in which order:

- **The read action is the relationship's own `read_action` when it declares
  one, else the read action of the destination's table.** A relationship that
  names an action says which records it means.
- **The relationship's own `sort` comes first, as long as the person has
  chosen none.** Ash puts it behind the read action's default sort, where it
  would never be seen. For a has-one with `from_many?` this decides which
  record is shown: "First comment" and "Newest comment" in the demo are the
  same relationship with opposite sorts, and each shows its own.
- **A person's sort or filter never applies to a single record.** On a
  has-one that picks one of many it would change which one that is.

**Try it:** `/tasks` as Ada Admin: expand a row. Under "Comments", edit a
body; under "Labels", a colour; under "Project", the name of the one row.
Each is saved through the `update_action` of its own table, as on `/comments`,
`/labels` and `/projects`. Under "Assignee" no cell opens: the table of the
demo's people names no `update_action`, so it is read-only wherever it is
shown.

The demo has no `no_attributes?` and no manual relationship. The library's
own tests have both
([`test/support/relating.ex`](https://github.com/StefanRoesch/ash_table/blob/main/test/support/relating.ex)):

<!-- source: test/support/relating.ex -->
```elixir
has_many :by_the_same_author, __MODULE__ do
  no_attributes? true
  filter expr(author_id == parent(author_id) and id != parent(id))
  public? true
end

has_many :manual_notes, AshTable.Test.Relating.Note do
  manual AshTable.Test.Relating.ManualNotes
  public? true
end
```

## Row actions and create in a nested table

A nested table has the actions column of the destination's table, and its
buttons do there what they do on the destination's own page: under a task
on `/tasks`, a comment has "Destroy", and a label has it for an admin.

It has that table's boxes too, where the destination's table has a row
action that runs on several rows. A nested table's selection is its own:
it has its own line above its own grid, and an action on it runs on the
records under its row and on no others. See
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#nested-tables).

Creating is narrower, because a record created under a row has to be joined
to that row, and the table has to be the one that says how. A nested table
offers create only where

- the relationship is a has-many joined by attributes, and
- the `create_action` of the destination's table accepts the relationship's
  destination attribute.

The table then fills that attribute in from the row above, which it reads
again as the person, and leaves it out of the panel. The button is on the
relationship line, after the label, once the nested table has read: "New
comment" on the "Comments" line of a task, "New task" on the "Tasks" line
of a project. A belongs-to, a has-one, a many-to-many, a manual
relationship and one with `no_attributes?` offer none.

**Try it:** `/projects` as Ada Admin: expand "Mobile app", open "Tasks" and
use "New task" on the line. The panel has no field "Project ID", and the new
task is the first row of the nested table.

[Row actions and create](row-actions-and-create.md#creating-in-a-nested-table)
has the rule in full, and what the panel shows.

## `max_depth`

A nested table's rows expand again: a task's project, that project's tasks,
their comments. `max_depth` says how deep a person can go, counted from the
table on the page. Its nested tables are at depth 1. The default is 3, and
the tables at that depth have no expanders.

It is the setting of the table **on the page** that counts for everything
beneath it. A second meaning belongs to `0` alone: the rows of a table with
`max_depth 0` never expand, wherever that table is shown. The demo's people
say so
([`demo/lib/demo/tracker/user.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/user.ex)):

<!-- source: demo/lib/demo/tracker/user.ex -->
```elixir
# Read-only, and its rows never expand: `max_depth 0` switches off the
# assigned and the reported tasks a row would otherwise offer, wherever
# this table is shown.
table do
  max_depth 0
```

**Try it:** `/tasks`, expand a row and open "Project"; in the project's one
row, expand again and open "Tasks"; expand one of those and open "Comments".
That is depth 3, and the comments have no expander. Task → Comments → Task →
Comments is a cycle, and ends the same way. `/task_labels` says
`max_depth 1`: the task under one of its rows has no expander.

## How a nested table is read, and why

A table keeps of its rows only their primary keys. So a nested table knows
its parent by a key, and a key proves nothing: it does not say that the
person may read the record it names.

Every read of a nested table is therefore a read of the **parent record, by
its primary key, as the person**, with the relationship as a load that
carries the nested table's query: its sort, its filters and its page. This
happens when the line is opened and again at every change of the nested
table's sort, filters or page.

The parent is read through the read action of the table that shows it, with
the [arguments](arguments.md) that table was given: the read action of the
table on the page for one of its rows, and for a row of a nested table the
action that nested table reads through. So a row a table
shows is a row it can open, and a key reaches no record that the table keeps
back. The related records are read through the relationship's own
`read_action` when it names one, else through the read action of the
destination's table. For a many-to-many Ash reads the join resource on the
way, through the `read_action` of the join relationship, else the join
resource's primary read action: its policies say which records are related
at all.

- If the parent is gone, or is no longer the person's to read, Ash returns
  nothing, and the nested table says so.
- What "related" means is Ash's own loader's to say, for every kind of
  relationship: a relationship's `filter`, a many-to-many's join resource, a
  manual relationship's module.
- The destination's policies and field policies apply to the nested rows as
  on a page of their own.

Nothing is fetched before a line is opened. Expanding a row sends one event
and reads nothing.

**What the columns show besides attributes is read in further steps.** A
nested table's records are read bare. Its calculations, its aggregates and
its reference cells are then loaded onto those records, as the person
(`Ash.load/3`). A table of its own reads its calculations with the page and
its aggregates in a step after it. The reason is a defect in the SQL layer
(tracked as #35): a statement that selects an aggregate beside a field that a
field policy hides on some records fails where it is wrapped in a subquery,
which a page of related records always is. The steps go when it is fixed.

## What a person may not see

| The resource says | Under an expanded row |
| --- | --- |
| The person can never read the destination: its read is refused outright for them | The line is not there. |
| The person may not read some of the related records | Those rows are not there and are not counted. |
| The person can never see a field of the destination | The nested table has no column for it. |
| The person sees a field on some records only | The column stays; hidden cells are empty and announced as "Not available". |
| The person can never run an update action of the destination | Its columns are read-only in the nested table. |
| The person can never run a row action of the destination | The nested table has no button for it, and no actions column when that is every one. |
| The person can never run the destination's create action | The line has no create button. |
| The parent row is gone, or no longer theirs to read | "This record is no longer available." in place of the nested rows. |
| The destination's read comes to be refused while the line is open | "You are not allowed to see these records." when the destination's table says `on_forbidden :message`, else "These records are not available." |

A nested table never says "No records" for a refusal, and it never makes the
page around it answer "not found": its line has already told the person that
there is a table.

**Try it:** `/tasks` as Vera Viewer. Under a task there is no "Assignee" and
no "Reported by": a viewer's read of the people is refused outright. As Max
Member, the tasks under a project on `/projects` have no "External ref", and
"Estimate hours" is "Not available" except on his own tasks.

Whether a line is offered is asked of Ash each time the table around it
reads, without a query (`Ash.can/3` for the destination's read action). A
line stays for a person who may read some of the destination's records:
which ones is known when they are read. See
[Authorization](authorization.md).

## When a total is not shown

A nested table shows and announces no total while a filter is set on a
column that the person sees on some records only. It then looks like a
table whose read action does not count: "1–25", and Next as long as there is
more.

Ash counts a page of related records with the person's filter as it is
written, without the field policies (tracked as #30). The rows are right: a
hidden value counts as empty there. The count is not: it would say how many
records match among those whose value the person may not see.

**Try it:** `/projects` as Max Member, the tasks of "Mobile app". Filter
"Estimate hours" by "at least" 1: the rows are his own tasks, and the range
under them has no "of".

A table of its own is not affected. It counts through the read itself.

## Aggregate columns in a nested table

Two sorts are not offered, because Ash cannot run them:

- **By an aggregate that a field policy hides from the person on some
  records.** This holds for every table, nested or not. See
  [Columns and defaults](columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).
- **By any aggregate, in a nested table that is read in pages, for a person
  who sees some field of that resource on some records only** (tracked as
  #35). Filtering by the aggregate stays, and so does sorting by a
  calculation.

A person who sees every field on every record sorts by an aggregate in a
nested table as on a page.

## The keyboard

The whole tree of tables is one tab stop: Tab enters it and Tab leaves all
of it. Inside, the arrow keys move, and each nested table is a grid of its
own in a cell of the grid around it.

| Key | Where | Effect |
| --- | --- | --- |
| Left Arrow | On the first data cell of a row | Moves to the row's expander. |
| Right Arrow | On an expander or a line that is closed | Opens it. |
| Left Arrow | On an expander or a line that is open | Closes it, with everything open under it. |
| Enter | On an expander or a line | Opens or closes it. |
| F2 | On a line that has a create button | Goes to the line's controls: the button that opens and closes it, and the create button. Left Arrow and Right Arrow move between them, Enter uses one, Escape returns to the line. |
| Down Arrow, Up Arrow | In the grid | Go through the lines of an expanded row and the cell of each open nested table, as through rows. |
| Enter, F2 | On the cell that holds a nested table | Goes into the nested table: to the cell that was left last, or to its first. |
| Escape | In a nested table | Comes back out, to the cell that holds it. |
| Down Arrow, Ctrl+End | In a nested table | Reach its last rows: its pages, where it has any, and its link to the full view, where it has one. |
| Enter, F2 | On the cell of a nested table's pages | Goes to its buttons. Left Arrow and Right Arrow move between them, Enter uses one, Escape returns to the cell. |
| Enter, F2 | On the cell of the link to the full view | Follows the link. |

Inside a nested table every key works as in a table on a page: headings
sort, filter cells are entered, cells are edited, the buttons of a row's
actions cell are reached with Enter. The pages and the link of
a nested table are rows of its grid and no tab stops of their own, so that
Tab from anywhere in the tree leaves it. Its create button is on its line
for the same reason. The "Clear filters" button of a
nested table is not reached from the keyboard; each filter is cleared from
its own cell.

Focus is kept through everything that patches the page. When a line or a
row is closed while focus is inside it, focus goes to the line, or to the
expander.

The keys of a table without nesting are in
[Keyboard and accessibility](keyboard-and-accessibility.md).

## The full view

A nested table is a table in a cell. Its last row holds a link, "Open in
full view", to the page of the destination's own table, limited to the same
records: the comments of this task, on `/comments`, under a heading such as
"Write the report: Comments". There the table has the page's width, its state in
the address, and its own nested tables counted from depth 0.

**Try it:** `/tasks` as Ada Admin: expand a row, open "Comments", and follow
"Open in full view". Sort the comments and reload: the same comments, the
same sort. "Show all records" above the table takes the limit away.

### When the link is there

The link is there when the host's router mounts the destination's table
with an `ash_table` line. The library looks through the router's routes
(`Phoenix.Router.routes/1`) for the first one, in the router's order, whose
`ash_table` names the destination resource and whose path has no parameter.
The demo's router mounts five tracker tables
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_table "/tasks", Demo.Tracker.Task
ash_table "/projects", Demo.Tracker.Project
ash_table "/comments", Demo.Tracker.Comment
ash_table "/labels", Demo.Tracker.Label
ash_table "/task_labels", Demo.Tracker.TaskLabel
```

`Demo.Tracker.User` has a table and no page. So under a task the nested
tables "Comments", "Labels" and "Project" have the link, and "Assignee" and
"Reported by" have none. Nothing is rendered in its place.

A table placed in a page of your own with `<AshTable.table>` links to the
destination's mounted page in the same way: the tasks on the demo's
`/dashboard` do. The link is a live navigation; LiveView turns it into a
page load by itself where the destination is in another `live_session`.

### The address

The limit is one more parameter of the table, under its id like the others:

<!-- sketch -->
```text
/comments?comment[of][task][comments]=3f649715-4294-4816-9e2a-02c24949cef5
```

| Part | Is |
| --- | --- |
| `comment` | the id of the table on the page |
| `of` | the parameter |
| `task` | the short name of the parent's resource (`Ash.Resource.Info.short_name/1`) |
| `comments` | the name of the parent's relationship |
| the value | the parent's primary key |

A primary key of several attributes is written by attribute:

<!-- sketch -->
```text
/tasks?task[of][task_label][task][label_id]=13eeb792-…&task[of][task_label][task][task_id]=00a93d01-…
```

Sort, filters and page are written beside it and work as on any page; the
limit stays in the address through each of them, and is part of a link that
is shared. "Show all records" drops the limit together with the sort, the
filters and the page that were chosen under it.

### What the address cannot do

The parent in the address is looked up, never trusted.

- **The parent's resource is found by its short name among the resources the
  application knows**: those of the domains in
  `config :my_app, ash_domains: […]` (the app of the host's endpoint) and
  those of the table's own domain. The name is compared as text. No module
  is made from it and nothing is called by it.
- **Only a relationship that the parent's table offers this person counts**,
  and only one that leads to the table on the page: public, with a
  destination that has a table, among the declared ones where the parent's
  block declares any, from a table whose rows expand at all (not
  `max_depth 0`), to a destination the person is not refused.
- **The key's values are cast to the types of the primary key.**
- **The parent is read as the person on every read**, as for a nested table,
  and through the read action of the parent's own table: an address says
  which record, not which table showed it. A key of a record that is not
  theirs, or that the parent's table would not show, gives them nothing.
  That includes a row that only a nested table showed, through a
  relationship whose own `read_action` returns more than the table of its
  destination: its full view says "This record is no longer available."

A limit that fails the first three is no limit: the page shows the table as
if nothing had been asked, with no word about it, and the next change the
person makes writes a clean address.

| In the address | The page shows |
| --- | --- |
| `comment[of][nothing][comments]=…`, `comment[of][Elixir.Demo.Tracker.Task][comments]=…` | The table, not limited. |
| `comment[of][task][labels]=…` (a relationship to another resource), `task_label[of][task][task_labels]=…` (a private one) | The table, not limited. |
| `comment[of][task][comments]=not-a-key` | The table, not limited. |
| `task[of][user][assigned_tasks]=…` (the people's table says `max_depth 0`) | The table, not limited. |
| `comment[of][deadline][comments]=…` (the parent's table reads through an action that requires an argument, which an address cannot give it) | The table, not limited. Such a table has no "Open in full view" under its nested tables either. |
| The key of a task that does not exist, or of one in another organization | "This record is no longer available.", no rows, and a heading that names no record. |

### The heading

Above the grid, the table says what it is limited to: the record, a colon,
and the relationship as its line is labelled. "Show all records" is beside
it, and before that the create button, where the nested table would have
one on its line: a record created there is created under the same parent.
The line of the page's own name, above this one, then has no create button.

The record is called by the first of these that the person sees on it:

1. the attribute that the parent's `table` block names as `label_field` (see
   [the reference cell](#the-reference-cell) below);
2. the parent table's attribute columns, in their order.

It is taken from the parent as it was read for the person, and from nothing
else. A value that a field policy hides from them is passed over, and a
record that was not read for them is not named at all: the heading is then
the relationship alone. Where the router mounts the parent's own table, the
record's name is a link to that page.

The demo's labels declare what they are called by
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/label.ex)):

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

(A line `# ...` stands for lines of the block that are left out here.)

Without it the tasks of a label would be headed by the label's first
column, its ID.

### What is the same as in a nested table, and what is not

The page is read as the nested table is: through the parent, with the
relationship's own read action and sort, without sort, filters and pages for
a single record, in full where Ash cannot page, and without a total while a
filter is set on a column the person sees on some records only.

It differs where a table of its own differs from a table in a cell. Its
state is in the address. Its first read happens while the page is mounted.
And a destination whose read is refused outright is the page's refusal: 404,
or "You are not allowed to see these records." with `on_forbidden :message`.

**Going back.** The browser's back button returns to the page the link was
on, with that page's own sort, filters and page, which are in its address.
The rows that were expanded there are closed: what is expanded is in no
address.

## Performance

Each nested table is a component of its own with its own stream. The server
keeps the keys of its page, its state and its table model, and no records.
It queries when it is opened, sorted, filtered or paged, and when a person
saves a cell or runs an action in it. While an action panel is open, the
table it belongs to also keeps the panel's form and, for a row action, the
record it was opened with.

Statements for one read, counted on Postgres with the demo's data
([`demo/perf/NESTED.md`](https://github.com/StefanRoesch/ash_table/blob/main/demo/perf/NESTED.md)
has the run in a browser that the times are from; the statement counts are
those of the library as it is now):

| Read | Statements | From click to rows |
| --- | --- | --- |
| `/tasks` → Comments (has-many, keyset, counted) | 2: the parent with the count, the page | 17 ms |
| `/tasks` → Labels (many-to-many, in full) | 2 | 16 ms |
| `/tasks` → Project (belongs-to) | 2 | 14 ms |
| `/tasks` → Newest comment (has-one of many) | 2 | 13 ms |
| `/projects` → Tasks (page of 25, counted; a calculation, an aggregate and three reference cells among the columns) | 6: the parent with the count, the page, the calculation and the aggregate, one per reference cell | 38 ms, measured before the reference cells were columns |

About 17 KiB of the page's process for each open nested table: 0.93 MB with
fifty open. Opening one more does not get much slower as they add up.
Rendering and scrolling with fifty grids in one page were not measured. The
browser, not the server, is where many open tables cost.

## The reference cell

A column that names a belongs-to relationship shows the related record's
**label** in place of its key. The demo's tasks have three
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

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

The label is declared where the record lives: `label_field` in the `table`
block of the destination. A person is called by their name
([`demo/lib/demo/tracker/user.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/user.ex)):

<!-- source: demo/lib/demo/tracker/user.ex -->
```elixir
# What a person is called where a table shows them as one value: in the
# "Assignee" and "Reported by" columns of /tasks.
label_field :name
```

**Try it:** `/tasks` as Ada Admin: the last three columns are "Project",
"Assignee" and "Reported by", with names in them. `/comments` shows the
difference: its "Task ID" and "Author ID" are the keys themselves, because
that table has no `column` and so shows the public attributes.

What a reference cell is, and is not:

- **Its column names a public belongs-to relationship** whose destination
  has a table with a `label_field`. `label_field` names a public attribute.
  Everything else is reported when the resource is compiled.
- **The related record is read through a `public?` action.** A relationship
  that leads to a private one is reported; see below.
- **It is shown as the label's type is shown**: text as text, an enum by its
  labels.
- **It is edited by choosing another related record**, where the column's
  update action accepts the relationship's foreign key: Enter on the cell
  opens the picker, with the destination's own table to choose from. Where
  no action accepts the key it is read-only. See
  [Choosing a related record](choosing-a-related-record.md).
- **It is not sorted by.** Ash accepts a sort through a relationship from
  outside and applies no policy of the related resource to it (tracked as
  #31), so the order of the rows would follow names the person may not read.
- **It is not filtered by** in this version.
- **It is not in the default set.** A table without `column` shows the
  public attributes, the foreign key among them when it is public.

### How it is read

The label is read as Ash loads the relationship: one statement per reference
column for a whole page, which selects the primary key and the label of the
related records, as the person. It is never an aggregate or a calculation
over the relationship. Those would be one statement less, and would apply
less than the destination's policies: see
[Columns and defaults](columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).

Ash loads a relationship through the relationship's own `read_action` when
it names one, else through the destination's **primary** read action. The
read action that the destination's table names does not come into it: that
one serves the destination's own table and a nested table of it, not a
load. Whichever of the two it is has to be `public?`. A destination whose
primary read action is private can still be shown in a reference cell: the
relationship says which public action reads it. This one is from a
resource of the demo's tests
([`demo/test/support/private_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/private_tables.ex)):

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

So the destination decides what a person reads in the cell:

| The destination says | The cell |
| --- | --- |
| There is no related record | Empty. |
| The person may not read the related record | Empty. Ash returns nothing for it, as for none, and the cell says nothing more. |
| The person may read the related record and not its label field | Empty, announced as "Not available": the cell of a hidden field. |
| The person can never read the destination, or can never see its label field | The column is left out for them. |

The first two rows are the same cell on purpose. A person who may not read
the related record is not told through this cell that there is one. If the
table also shows the foreign key itself as a column, they can compare the
two: that is the resource's choice, which a field policy on the key settles.

**Try it:** `/tasks` as Vera Viewer: no "Assignee" and no "Reported by",
since a viewer may not read people; "Project" is there. As nobody, it is the
other way round: projects are refused outright when nobody is logged in.

The label is read again with the row after one of its cells is saved, and
in a nested table for each of its rows.

## Edge cases

- **A nested table has the argument line of the action it reads through**,
  whichever table's it is, and keeps what a person gave there itself, as its
  sort and filters: see
  [Arguments](arguments.md#nested-tables-the-full-view-and-the-picker).
- **A record that no longer matches the relationship stays in place** until
  the nested table reads again. Editing a comment or a task under a row
  saves, and the row is shown from what the action returns, as on a page.
- **The cells of the parent row do not follow.** After a comment is created,
  deleted or a task edited below it, the parent's own aggregates are as they
  were when its page was read: the "Comments" cell of a task still counts
  the old number.
- **A new read of a table closes what is open in it.** A change of its sort,
  filters or page reads again and forgets which rows were expanded. A save in
  a row, and a row action that changes it, leave what is open under it open.
  A destroy takes the row away with everything open under it.
- **Many-to-many edits the destination**, not the join. A label edited under
  a task changes for every task that carries it. The fields of the join
  resource are not columns of the destination's table.
- **A destination that is readable only through the relationship** (a policy
  with `accessing_from/2`) shows its rows nested, and can neither be edited
  there nor expanded further: both read the record by its key, outside the
  relationship.
- **Several routes for one resource.** The link goes to the first in the
  router's order. In the demo the labels are mounted at `/labels` and at
  `/bare/labels`; the link goes to `/labels`.
- **Two resources with one short name** that both have such a relationship
  to the table: the address would not say which is meant, so the nested
  table has no link, and such a limit is ignored.
- **A parent resource outside the application's domains and the table's own
  domain** is not found: no link.
- **A reference cell to a destination whose read is refused while the page
  is open**: a row that is saved shows the cell as "Not available". Where the
  relationship says `allow_forbidden_field? false`, the refusal fails the
  whole read, and the table shows that as the refusal of its own read.
- **A join resource's policy does not restrict an aggregate over a
  many-to-many.** This was seen in one investigation and not verified
  independently. If the join resource's policy is what keeps a person from
  some related records, do not rely on it for an aggregate column.

## Things people trip over

- **A relationship is missing under the row.** It is not `public?`, its
  destination does not list `AshTable.Resource`, it is manual and not
  declared, it is read through a private action (its own, or that of its
  join resource) and not declared, or the block declares others. For one person only: they can never read the
  destination.
- **Declaring one `relationship` removes the defaults**, as declaring one
  `column` does.
- **`max_depth` on the nested resource has no effect.** The table on the
  page decides, except for `0`.
- **Expecting the nested table's state in the address.** It is not. Open the
  full view for a link that can be shared.
- **No link on a nested table.** The destination is not mounted with
  `ash_table`.
- **A heading with a UUID in it.** The parent's table has no `label_field`,
  and its first column is the key.
- **`column :author` reports that the destination declares no
  `label_field`.** The label is declared on the destination's table, not on
  the column.
- **A sort by an aggregate that the page offers and the nested table does
  not.** See "Aggregate columns in a nested table" above.

## Not in the first version

No counts on the relationship lines, no adding or linking a record through
a many-to-many, no creating under a has-one or a belongs-to, no
sorting or filtering by a reference cell, no label that is a calculation, no
link from a reference cell to its record, and nothing of a nested table in
the address but its full view. The later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
