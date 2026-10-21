# Named tables

Give a resource a second table beside its first; mount it, place it, nest it
under another resource's rows, and move a table's declaration into a file of
its own.

## The smallest example

Every resource has a **default table**: the one of the `table` block. A
**named table** is another table of the same resource, declared under a name
in the `tables` block. The demo's labels have both
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/label.ex)):

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
tables do
  table :short do
    max_depth 0

    column :name
    column :colour
  end

  # ...
end
```

The labels' default table, at `/labels`, edits, deletes and creates. `:short`
shows two columns and nothing else.

**Try it:** `/tasks/board` in the demo, as Ada Admin, is a named table of the
tasks. Expand a row and open "Labels": the nested table is the short one. Then
open `/labels`: the same records in the default table.

## What a named table is

A named table takes everything the `table` block takes: `read_action`,
`paginate_with`, `update_action`, `create_action`, `max_depth`,
`on_forbidden`, and its own `column`, `relationship`, `action`, `argument` and
`upload` declarations. The guides on these apply to a named table unchanged.

Two rules are its own.

**A named table inherits nothing from the default table**: not its columns,
`update_action`, actions or `on_forbidden`. What it leaves out has the default,
as in a `table` block: no `column` shows every public attribute, no
`read_action` reads through the primary read action, no `update_action` edits
nothing. So each table reads on its own, top to bottom.

**`label_field` is not an option of a named table.** It names a record of the
resource in a reference cell, the picker, a heading and a message, whichever
table shows the record. It belongs to the resource and is written once, in the
`table` block. In a named table it is reported at compile time.

| | Default table | Named table |
| --- | --- | --- |
| Written in | `table do … end` | `tables do table :name do … end end` |
| How many | one, always | any number |
| There without a block | yes, with every default | no |
| Named by | nothing, or `:default` | its name |
| `label_field` | here | not here |

### The default table is always there

A resource that lists the extension has a default table with or without a
`table` block. A resource may declare only named tables: its default table is
then the default set of columns, read through the primary read action. It is
the table a picker shows, that a relationship nests when it names no table,
and that `ash_data_table` mounts without `table:`.

### Names

A name is an atom of lower-case letters, digits and `_`, starting with a
letter, such as `:compact` or `:by_week`. It becomes part of the table's id,
so of ids in the page and of its URL parameters. No two tables of a resource
share a name.

`:default` names the default table; no named table can take it. `table:
:default` in the router and in `attach/4`, `table={:default}` on the tag and
`table :default` in a `relationship` all mean the same as leaving it out.

## Mounting a named table

`ash_data_table` takes the name as `table:`
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_data_table "/tasks/board", Demo.Tracker.Task, table: :board
ash_data_table "/comments/compact", Demo.Tracker.Comment, table: :compact
```

The page works like any mounted table: layout, reader, heading and URL as in
[Layout and embedding](layout-and-embedding.md). The heading and page title
are the resource's name, as for the default table.

**Try it:** `/comments/compact` and `/comments` as Ada Admin. The first has
three columns and nothing to click in a row; the second has the comments' own
columns, "Destroy" and "New comment".

The router does not look at the resource, so as not to depend on it at
compile time. An unknown name is therefore found when the page is opened, not
when the router compiles. The page raises and lists the tables there are:

<!-- sketch -->
```text
** (ArgumentError) `ash_data_table` mounts the table `:compakt` of Demo.Tracker.Comment at "/comments/compact", but Demo.Tracker.Comment has no table named `:compakt`. Its tables: `:compact`, and the default table.
```

A `table:` that cannot be a name at all (a string, an atom with a capital
letter) raises when the router compiles.

## Placing a named table

`<AshDataTable.table>` takes the name as `table`, `AshDataTable.attach/4` as
the option `table:`. The demo's page `/named` places two tables of the
comments
([`demo/lib/demo_web/live/named_live.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/live/named_live.ex)):

<!-- source: demo/lib/demo_web/live/named_live.ex -->
```heex
<AshDataTable.table
  resource={Demo.Tracker.Comment}
  table={:compact}
  label="Comments, compact"
  heading={2}
  url={@url}
  actor={@current_user}
  tenant={@current_tenant}
  time_zone={@time_zone}
/>
```

An unknown name raises when the table is placed, with the same list of
tables.

Two tables of one resource carry the same name above the grid, the
resource's, unless `label` gives each its own, as above.

## Ids and the URL

A table's id names its URL parameters and prefixes its ids in the page. The
default:

| Table | Default id | Example |
| --- | --- | --- |
| The default table | the last part of the resource's module name, underscored | `comment` |
| A named table | that, `_` and the table's name | `comment_compact` |

So two tables of one resource fit on one page and in one address without an
`id`. This holds for `ash_data_table`, `<AshDataTable.table>` and `attach/4`.

**Try it:** `/named` as Ada Admin. Click "Body" in the lower table, then in the
upper one. The address holds both, each under its own id:

<!-- sketch -->
```text
/named?comment[sort]=body&comment_compact[sort]=body
```

The same table placed twice on one page still needs an `id` per placement.
[State in the URL](state-in-the-url.md) has the parameters.

## A relationship that names a table

A table's `relationship` picks which of the destination's tables it nests with
`table`. The tasks' board
([`demo/lib/demo/tracker/task/board_table.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task/board_table.ex)):

<!-- source: demo/lib/demo/tracker/task/board_table.ex -->
```elixir
relationship :comments do
  table :compact
end

relationship :labels do
  table :short
end
```

Without `table`, the destination's default table is nested. A relationship of
the default set (a table that declares no `relationship`) always nests the
default table.

**Try it:** `/tasks/board` as Ada Admin: expand a row and open "Comments". The
nested table has three columns and no "New comment". On `/tasks` the comments
are the default table, with their actions and "New comment".

Each table decides this for itself: `/tasks` and `/tasks/board` both offer
"Comments", each nesting another table of the comments.

The nested table reads through the relationship's own `read_action` when it
names one, else through the nested table's `read_action`. A name the
destination has no table for is reported at compile time: see
[Mistakes at compile time](mistakes-at-compile-time.md#named-tables).

### The full view of a nested named table

"Open in full view" leads to the mounted page of **the same table**: the
compact comments under a board task lead to `/comments/compact`, never to
`/comments`. A person is never sent to another table with other columns and
actions.

When that table is mounted nowhere, the nested table has no link. In the demo
the labels' short table is mounted nowhere, so "Labels" under a board task has
none, although `/labels` mounts the labels' default table.

The address names the table that offers the relationship: the resource's short
name for the parent's default table, followed by `_` and the table's name for a
named one:

<!-- sketch -->
```text
/comments/compact?comment_compact[of][task_board][comments]=3f649715-4294-4816-9e2a-02c24949cef5
```

A limit is only taken from a table that nests this very table. On
`/comments/compact`, `comment_compact[of][task][comments]=KEY` is no limit: the
tasks' default table nests the default comments, not the compact ones. The
page then shows every record, as for any limit it cannot take.
[Nested tables](nested-tables.md#the-full-view) has the rest.

## The picker

The picker always shows the destination's **default table**, whichever table
opens it. On `/tasks/board` the assignee is chosen from the people's table as
on `/tasks`. A reference cell and an action's `reference` cannot name another
table yet.

## A table in a file of its own

A long table declaration can live in a file of its own, as a resource's
actions or policies can: as a **fragment** of the resource. This is Spark's own
mechanism (`Spark.Dsl.Fragment`) and needs nothing from this library.

The fragment is a module that says what it is a fragment of and lists the
extension. The comments' compact table
([`demo/lib/demo/tracker/comment/compact_table.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/comment/compact_table.ex)):

<!-- source: demo/lib/demo/tracker/comment/compact_table.ex -->
```elixir
defmodule Demo.Tracker.Comment.CompactTable do
  # ...
  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshDataTable.Resource]

  tables do
    table :compact do
      on_forbidden :message
      max_depth 0

      # ...
      column :body do
        max_lines 3
      end

      # a reference cell: the author's name
      column :author
      column :inserted_at
    end
  end
end
```

The resource lists it
([`demo/lib/demo/tracker/comment.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/comment.ex)):

<!-- source: demo/lib/demo/tracker/comment.ex -->
```elixir
use Ash.Resource,
  otp_app: :demo,
  domain: Demo.Tracker,
  data_layer: AshPostgres.DataLayer,
  authorizers: [Ash.Policy.Authorizer],
  extensions: [AshDataTable.Resource],
  # A second table of the comments, declared in a file of its own:
  # `comment/compact_table.ex`.
  fragments: [Demo.Tracker.Comment.CompactTable],
```

What works:

- **One fragment per named table.** Each fragment has a `tables` block with its
  table; the resource lists them all. Order: the tables of the resource's own
  file, then those of the fragments in `fragments:` order.
- **The default table in a fragment.** A fragment can hold the `table` block,
  `label_field` included, with the named tables in the resource, or the other
  way round, or everything in fragments.
- **Every compile-time check.** A fragment is not checked alone; it is checked
  completely as part of the resource that lists it.

A mistake inside a fragment is reported for the resource and **points at the
fragment's file and line**:

<!-- sketch -->
```text
warning: ** (Spark.Error.DslError) [Demo.Tracker.Comment]
tables -> table -> compact -> column -> nothing defined in lib/demo/tracker/comment/compact_table.ex:24::
  The resource has no attribute, calculation, aggregate or belongs-to relationship named `nothing`.

    │
 24 │       column :nothing
    │       ~~~~~~~~~~~~~~~
    │
    └─ lib/demo/tracker/comment/compact_table.ex:24: (file)
```

The module in brackets is the resource, not the fragment.

### One table, one place

Keep each table whole in one place. Spark merges a block written in several
places, which for one table is rarely what you want:

- **Declarations add up.** A `table` block in the resource and one in a
  fragment become one default table: the resource's columns first, then the
  fragment's.
- **Each option given once counts.** `label_field` in a fragment and
  `update_action` in the resource both apply.
- **An option given twice with two values warns, and the fragment wins.**
  `max_depth 1` in the resource and `max_depth 2` in a fragment give 2, and
  Spark prints `table.max_depth is being overwritten from 1 to 2 by fragment: …`.
- **A named table cannot be split.** Two `table :board` in two places are two
  tables of one name, which is reported.

**Try it:** in a demo checkout, add `column :nothing` to
`demo/lib/demo/tracker/comment/compact_table.ex` and run `mix compile` in
`demo/`. The warning names `Demo.Tracker.Comment` and the fragment's file.
Remove the line again.

## Reading a resource's tables

`AshDataTable.Resource.Info.tables/1` returns every table of a resource,
default first; `AshDataTable.Resource.Info.table/2` returns one by name. Both
give an `AshDataTable.Resource.Table`, the same shape for default and named
tables:

<!-- sketch -->
```elixir
AshDataTable.Resource.Info.tables(Demo.Tracker.Comment) |> Enum.map(& &1.name)
#=> [:default, :compact]

{:ok, table} = AshDataTable.Resource.Info.table(Demo.Tracker.Comment, :compact)
Enum.map(table.columns, & &1.name)
#=> [:body, :author, :inserted_at]
```

The single-table functions (`columns/1`, `table_read_action/1` and the others)
are about the default table.

## Edge cases

- **Named tables and no `table` block:** the default table still exists, with
  every default. If the primary read action is private, that default table is
  reported even though nothing mounts it: name a public `read_action` in a
  `table` block.
- **The same column in several tables** is fine; a duplicate is one inside a
  single table.
- **A named table with no declaration** (`table :plain`) is the default set of
  columns under another name and id.
- **Authorization is the resource's.** A named table adds and removes no rule:
  the resource's policies and field policies decide what a person sees in each
  of its tables. A column a person can never see is left out of every table
  that has it.
- **`max_depth` and `on_forbidden` are per table.** A named table's page uses
  its own, and a nested named table follows its own `on_forbidden` when its
  read is refused.
- **An upload** belongs to the table that declares it and limits only the file
  arguments of that table's actions.
- **The domain's settings** (`AshDataTable.Domain`: the assign names and
  `authorize?`) hold for every table of the domain's resources.
- **A full view from a table placed with another `id`** works the same: the
  link is found by resource and table, not by id.

## Things people trip over

- **Expecting a named table to start from the default one.** It starts from
  nothing; copy what it should have.
- **`label_field` in a named table.** It is the resource's: write it in the
  `table` block.
- **A nested named table without the full-view link.** The link is there only
  when that very table is mounted. Mount it, or accept that the nested table
  is the only place it shows.
- **The id is `comment_compact`, not `compact`.** It starts with the
  resource's, so tables of two resources with the same table name do not
  clash.
- **Forgetting `fragments:`.** A fragment no resource lists declares nothing,
  and nothing warns.
- **Forgetting `extensions: [AshDataTable.Resource]` on the fragment.** The
  `tables` block is then unknown there and the fragment does not compile.

## Not in the first version

- A reference cell or `reference` choosing which table its picker shows; it is
  always the default table.
- A people-facing name for a named table: its heading is the resource's unless
  `label` says otherwise.
- Telling a relationship of the default set to nest a named table: declare the
  `relationship`.

The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
