# Named tables

After reading this guide you can give a resource a second table beside its
first, mount it, place it, nest it under another resource's rows, and move a
table's declaration into a file of its own.

## The smallest example

A resource has one table without anything being named: its **default
table**, the one of the `table` block. A **named table** is another table of
the same resource, declared in the `tables` block under a name. The demo's
labels have both
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/label.ex)):

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
tables do
  table :short do
    max_depth 0

    column :name
    column :colour
  end
end
```

The default table of the labels, at `/labels`, edits, deletes and creates.
`:short` shows two columns and does nothing else.

**Try it:** `/tasks/board` in the demo, as Ada Admin. This is a named table
of the tasks. Expand a row and open "Labels": the nested table is the short
one. Then open `/labels`: the same records in the default table.

## What a named table is

A named table has everything the `table` block has: `read_action`,
`paginate_with`, `update_action`, `create_action`, `max_depth`,
`on_forbidden`, and its own `column`, `relationship`, `action`, `argument`
and `upload` declarations. Each guide about one of these holds for a named
table as it is written.

Two rules are its own.

**A named table takes nothing over from the default table.** It does not
inherit its columns, its `update_action`, its actions or its `on_forbidden`.
What it does not say has the default, exactly as in a `table` block: with no
`column` it shows every public attribute, with no `read_action` it reads
through the primary read action, with no `update_action` nothing is edited.
So each table can be read by itself, top to bottom.

**`label_field` is not an option of a named table.** It says what a record
of the resource is called, in a reference cell, in the picker, in a heading
and in a message, whichever table shows the record. It belongs to the
resource and is written once, in the `table` block. Written in a named
table it is reported when the resource is compiled.

| | Default table | Named table |
| --- | --- | --- |
| Written in | `table do … end` | `tables do table :name do … end end` |
| How many | one, always | any number |
| There without a block | yes, with every default | no |
| Named by | nothing, or `:default` | its name |
| `label_field` | here | not here |

### The default table is always there

A resource that lists the extension has a default table whether it writes a
`table` block or not, as before. So a resource may declare named tables
only: its default table is then the default set of columns, read through the
primary read action. It is the table that a picker shows, that a
relationship nests when it names no table, and that `ash_table` mounts
without `table:`.

### Names

A name is an atom of lower-case letters, digits and `_` that starts with a
letter, such as `:compact` or `:by_week`. It becomes part of the table's id,
and so of ids in the page and of the parameters of its URL. No two tables of
a resource have the same name.

`:default` is the name of the default table. No named table can have it, and
wherever a table is named, `:default` names the default table:
`table: :default` in the router, `table={:default}` on the component and
`table :default` in a `relationship` all mean the same as leaving it out.

## Mounting a named table

`ash_table` takes the name as `table:`
([`demo/lib/demo_web/router.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/router.ex)):

<!-- source: demo/lib/demo_web/router.ex -->
```elixir
ash_table "/tasks/board", Demo.Tracker.Task, table: :board
ash_table "/comments/compact", Demo.Tracker.Comment, table: :compact
```

The page is like any mounted table: the layout, who is reading, the heading
and the URL work as [Layout and embedding](layout-and-embedding.md) says.
The heading and the page title are the resource's name, as on the page of
the default table.

**Try it:** `/comments/compact` and `/comments` as Ada Admin. The first has
three columns and nothing to click in a row; the second has the comments'
own columns, "Destroy" and "New comment".

The router does not look at the resource, so that it does not depend on it
at compile time. A name the resource has no table for is therefore found
when the page is opened, not when the router is compiled. The page raises,
and lists the tables there are:

<!-- sketch -->
```text
** (ArgumentError) `ash_table` mounts the table `:compakt` of Demo.Tracker.Comment at "/comments/compact", but Demo.Tracker.Comment has no table named `:compakt`. Its tables: `:compact`, and the default table.
```

A `table:` that cannot be a name at all (a string, an atom with a capital
letter) raises when the router is compiled.

## Placing a named table

`<AshTable.table>` takes the name as `table`. The demo's page `/named`
places two tables of the comments
([`demo/lib/demo_web/live/named_live.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/live/named_live.ex)):

<!-- source: demo/lib/demo_web/live/named_live.ex -->
```heex
<AshTable.table
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

A name the resource has no table for raises when the component is rendered,
with the same list of tables.

Two tables of one resource are called the same unless you say otherwise:
the name on the line above the grid is the resource's. `label` gives each
its own, as above.

## Ids and the URL

The id of a table names its URL parameters and prefixes its ids in the
page. Unless you give one, it is:

| Table | Default id | Example |
| --- | --- | --- |
| The default table | the last part of the resource's module name, underscored | `comment` |
| A named table | that, `_` and the table's name | `comment_compact` |

So two tables of one resource stand on one page, and in one address,
without an `id` being written. This holds for `ash_table` and for
`<AshTable.table>`, where `id` can now be left out.

**Try it:** `/named` as Ada Admin. Click "Body" in the lower table, then in
the upper one. The address holds both, each under its own id:

<!-- sketch -->
```text
/named?comment[sort]=body&comment_compact[sort]=body
```

The same table placed twice on one page still needs an `id` for each
placement. [State in the URL](state-in-the-url.md) has the parameters.

## A relationship that names a table

A `relationship` of a table says which of the destination's tables it nests
with `table`. The board of the tasks
([`demo/lib/demo/tracker/task/board_table.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task/board_table.ex)):

<!-- source: demo/lib/demo/tracker/task/board_table.ex -->
```elixir
relationship :comments do
  table :compact
end

relationship :labels do
  table :short
end
```

Without `table`, the destination's default table is nested, as before. A
relationship of the default set (a table that declares no `relationship`)
always nests the default table.

**Try it:** `/tasks/board` as Ada Admin: expand a row and open "Comments".
The nested table has three columns and no "New comment" on its line. Do the
same on `/tasks`: there the comments are the default table, with their
actions and "New comment".

Each table of a resource says this for itself. `/tasks` and `/tasks/board`
both offer "Comments", and each nests another table of the comments.

The nested table reads through the relationship's own `read_action` when it
names one, else through the `read_action` of the table that is nested. A
name the destination has no table for is reported when the resource is
compiled: see [Mistakes at compile time](mistakes-at-compile-time.md#named-tables).

### The full view of a nested named table

"Open in full view" leads to the mounted page of **the same table**: the
compact comments under a task of the board lead to `/comments/compact`,
never to `/comments`. A person is not sent from one table to another with
other columns and other actions.

When that table is mounted nowhere, the nested table has no link. In the
demo the short table of the labels is mounted nowhere, so "Labels" under a
task of the board has none, although `/labels` mounts the labels' default
table.

The address names the table that offers the relationship. For the default
table of the parent that is the resource's short name, as before; for a
named table it is followed by `_` and the table's name:

<!-- sketch -->
```text
/comments/compact?comment_compact[of][task_board][comments]=3f649715-4294-4816-9e2a-02c24949cef5
```

A limit is only taken from a table that nests this very table. On
`/comments/compact`, `comment_compact[of][task][comments]=KEY` is no limit:
the default table of the tasks nests the default comments, not the compact
ones. The page then shows every record, as it does for any limit it cannot
take. [Nested tables](nested-tables.md#the-full-view) has the rest.

## The picker

The picker shows the destination's **default table**, from whichever table
it is opened. On `/tasks/board` the assignee is chosen from the people's
table as on `/tasks`. A reference cell and a `reference` of an action cannot
name another table yet.

## A table in a file of its own

A table's declaration can become long. It can live in a file of its own, as
a resource's actions or policies can: as a **fragment** of the resource.
This is Spark's own mechanism (`Spark.Dsl.Fragment`) and needs nothing from
this library.

The fragment is a module that says what it is a fragment of, and lists the
extension. The compact table of the comments
([`demo/lib/demo/tracker/comment/compact_table.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/comment/compact_table.ex)):

<!-- source: demo/lib/demo/tracker/comment/compact_table.ex -->
```elixir
defmodule Demo.Tracker.Comment.CompactTable do
  # ...
  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshTable.Resource]

  tables do
    table :compact do
      on_forbidden :message
      max_depth 0

      column :body
      # a reference cell: the author's name
      column :author
      column :inserted_at
    end
  end
end
```

The resource lists it
([`demo/lib/demo/tracker/comment.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/comment.ex)):

<!-- source: demo/lib/demo/tracker/comment.ex -->
```elixir
use Ash.Resource,
  otp_app: :demo,
  domain: Demo.Tracker,
  data_layer: AshPostgres.DataLayer,
  authorizers: [Ash.Policy.Authorizer],
  extensions: [AshTable.Resource],
  # A second table of the comments, declared in a file of its own:
  # `comment/compact_table.ex`.
  fragments: [Demo.Tracker.Comment.CompactTable],
```

What works:

- **One fragment per named table.** Each fragment has a `tables` block with
  its table; the resource lists them all. The tables come in this order:
  those of the resource's own file, then those of the fragments in the order
  of `fragments:`.
- **The default table in a fragment.** A fragment can hold the `table`
  block, `label_field` included, while the named tables stay in the
  resource, or the other way round, or everything in fragments.
- **Every compile-time check.** A fragment is not checked by itself. It is
  part of the resource that lists it, and is checked with it, completely.

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

Keep each table whole in one place. Spark puts a block that is written in
several places together, and for one table that is rarely what you want:

- **Declarations are added up.** A `table` block in the resource and another
  in a fragment become one default table, with the resource's columns
  first, then the fragment's.
- **An option is the one that was given.** `label_field` in a fragment and
  `update_action` in the resource both count.
- **An option given twice with two values is a warning, and the fragment
  wins.** `max_depth 1` in the resource and `max_depth 2` in a fragment give
  2, and Spark prints
  `table.max_depth is being overwritten from 1 to 2 by fragment: …`.
- **A named table cannot be split.** Two `table :board` in two places are
  two tables of one name, which is reported.

**Try it:** in a checkout of the demo, add `column :nothing` to
`demo/lib/demo/tracker/comment/compact_table.ex` and run `mix compile` in
`demo/`. The warning names `Demo.Tracker.Comment` and the fragment's file.
Take the line out again.

## Reading a resource's tables

`AshTable.Resource.Info.tables/1` returns every table of a resource, the
default table first, and `AshTable.Resource.Info.table/2` the one of a
name. Both give an `AshTable.Resource.Table`, in one shape for the default
table and a named one:

<!-- sketch -->
```elixir
AshTable.Resource.Info.tables(Demo.Tracker.Comment) |> Enum.map(& &1.name)
#=> [:default, :compact]

{:ok, table} = AshTable.Resource.Info.table(Demo.Tracker.Comment, :compact)
Enum.map(table.columns, & &1.name)
#=> [:body, :author, :inserted_at]
```

The functions that were there before (`columns/1`, `table_read_action/1` and
the others) are about the default table.

## Edge cases

- **A resource with named tables and no `table` block** has its default
  table all the same, with every default. If the primary read action is
  private, that default table is reported, although nothing mounts it: name
  a public `read_action` in a `table` block.
- **The same column in several tables** is fine. Each table declares its
  own; a duplicate is one inside a single table.
- **A named table without any declaration** (`table :plain`) is the default
  set of columns under another name and id.
- **Authorization is the resource's.** A named table adds no rule and
  removes none: the policies and field policies of the resource decide what
  a person sees in every table of it. A column a person can never see is
  left out of each table that has it.
- **`max_depth` and `on_forbidden` are per table.** A page of a named table
  uses its own, and a nested named table says what its own `on_forbidden`
  says when its read is refused.
- **An upload** belongs to the table that declares it, and limits the file
  arguments of that table's actions only.
- **The settings of the domain** (`AshTable.Domain`: the assign names and
  `authorize?`) hold for every table of the domain's resources.
- **A full view from a table placed with another `id`** works as before: the
  link is found by resource and table, not by id.

## Things people trip over

- **Expecting a named table to start from the default one.** It starts from
  nothing. Copy what it should have.
- **Writing `label_field` in a named table.** It is the resource's: write
  it in the `table` block.
- **Nesting a named table and missing the link.** "Open in full view" is
  there only when that very table is mounted. Mount it, or accept that the
  nested table is the only place it is shown.
- **The id is `comment_compact`, not `compact`.** It starts with the
  resource's, so that tables of two resources with the same table name do
  not meet.
- **Forgetting `fragments:`.** A fragment that no resource lists declares
  nothing, and nothing warns.
- **Forgetting `extensions: [AshTable.Resource]` on the fragment.** The
  `tables` block is then unknown there, and the fragment does not compile.

## Not in the first version

A reference cell and a `reference` cannot name which table their picker
shows; it is always the default table. A named table has no name of its own
for people: its heading is the resource's unless `label` says otherwise. A
relationship of the default set cannot be told to nest a named table: declare
the `relationship`. The roadmap is in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
