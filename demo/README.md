# ash_table demo

A real Phoenix and Ash host app for `ash_table`. It holds the domain, the data
and the infrastructure that the library's tables are shown and tested on: an
issue tracker with one of everything a table has to cope with, and a
kitchen-sink resource with one attribute per built-in Ash type.

Phoenix 1.8, LiveView 1.2, Ash 3.34, `ash_postgres`, `ash_phoenix`; Tailwind
and daisyUI through the `tailwind` and `esbuild` Hex packages, no npm.

## Start

From the repository root, start Postgres 18.6 (loopback only, port **5477**):

```sh
docker compose up -d postgres
```

Then, in `demo/`:

```sh
mix setup        # deps, create and migrate the database, build assets, seed
mix phx.server   # http://localhost:4478
```

`mix test` runs the tests against the database `demo_test` on the same
Postgres, in the Ecto sandbox.

### Tidewave

In development the demo has [Tidewave](https://hexdocs.pm/tidewave): an MCP
endpoint for coding agents (logs, evaluating code, SQL, documentation) at
http://127.0.0.1:4478/tidewave/mcp, over streamable HTTP. It answers requests
from this machine only, and no other environment has it. For Claude Code:
`claude mcp add --transport http tidewave http://127.0.0.1:4478/tidewave/mcp`.

### Without Elixir on the host

```sh
docker compose --profile demo up --build
```

builds the demo in dev mode, creates and seeds its own database
(`demo_docker`) and serves it on http://localhost:4478. Plain
`docker compose up -d` starts Postgres only.

### Settings

`.env.example` at the repository root lists the variables. Compose reads them
from `.env`; the app reads the same names from the environment
(`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`,
`POSTGRES_DB` in dev, `PORT`). The defaults need no `.env` at all.

| What | Where |
| --- | --- |
| Demo | http://localhost:4478 |
| Postgres | `localhost:5477`, user and password `ash_table`, databases `demo_dev` and `demo_test` |

## The tables

Every table is one `ash_table` line in `DemoWeb.Router`, rendered in the
demo's app layout (`config :ash_table, layout: {DemoWeb.Layouts, :app}`).

| URL | Resource | Shows |
| --- | --- | --- |
| http://localhost:4478/tasks | `Task` | a `table` block: chosen columns in a chosen order, a relabelled column, an aggregate, two calculations, and three reference cells ("Project", "Assignee", "Reported by": each shows a related record by its name, with no sort and no filter; the first two are edited by choosing another record from that resource's own table, in the picker, see below; the third is read-only); offset pages of 25. Two array columns, "Tags" (an array of text) and "Checks" (an array of enum values), shown as their values and edited as a whole, with neither a sort nor a filter. "Repeats", a map that declares its fields, shown on one line and edited in the side panel (see below). A box at the start of every row selects it, and the five row actions run on the selected rows (see below). Inline editing of every cell type (see below). Filters of every kind: text (`title`, `external_ref`), numbers (`progress`, `estimate_hours`), a date (`due_on`), datetimes (`completed_at`, `inserted_at`), booleans (`billable?` and the calculation `overdue?`), enums (`status`, `priority`), an aggregate (`comment_count`). No filter on `description` (`sortable? false` and `filterable? false`) and none on `headline` (computed in Elixir). Five row actions in a last column, "Actions", the last of which, "Set labels", takes the labels of a task as an argument and hands them to the relationship: its panel lists the task's labels, and they are chosen in the picker (see below); and "New task" on the line of the table's name (see below). Above the grid, the argument line: "Search", an argument of the read action that may be left empty, finds tasks by a text in their title or description, and "Due within: Days" is the argument of the column "Due within", which shows the calculation `due_within?` with the days a person gives it (30 to start with); the column beside it, "Due within 7 days", shows the same calculation with its argument fixed (see below) |
| http://localhost:4478/projects | `Project` | no column declared: the public attributes, edited in place through `update_action :update` (Name, Description, Status, Starts on, Budget) by an admin or a member. Two of them are made of fields and edited in the side panel: "Client", an embedded resource with an address inside it, and "Milestones", an array of embedded resources (see below). Its block also says what a project is called in other tables (`label_field :name`). Four row actions: "Set status", whose one input is a choice; "Set budget", whose one input is sensitive, typed hidden, and can be emptied with "Clear"; "Destroy", which asks first; and "Assign open tasks", a generic action that the table gives the row's key and that takes a person, chosen in the picker (`reference`); and "New project". Refused outright for nobody, who gets a 404: the page answers as if it did not exist |
| http://localhost:4478/comments | `Comment` | the public attributes again, the foreign keys among them: "Task ID" and "Author ID" are the raw keys, where `/tasks` shows names. "Body" is edited in place, by an admin and by a comment's own author; anyone else's save is refused on the cell. Keyset pagination: next and previous only, and no page numbers. The action counts (Ash's `countable` is on unless an action says otherwise), so the line under the table gives the number of records without a range, and a filter change is announced with its count. A row action, "Destroy", which asks first, and "New comment", whose panel has a field for the task that opens the picker: the table of the tasks to choose one from. Refused outright for nobody too, but declared with `on_forbidden :message`: nobody is told "You are not allowed to see these records." |
| http://localhost:4478/labels | `Label` | no pagination: every record. "Name" and "Colour" are edited in place by an admin (`update_action :update`); a member and a viewer are offered no editing. `label_field :name` says what a label is called. "Destroy", which asks first, and "New label", for an admin: a member and a viewer have no actions column and no create button. Five table actions, generic actions with their buttons after "New label": "Count unused" for everybody, "Recolour", "Remove unused", "Merge", whose two arguments are labels chosen in the picker (`reference`), and "Import", which takes a CSV file, for an admin; and "Copy" in every row, a generic action that is given the row's key (see below) |
| http://localhost:4478/bare/labels | `Label` | the same, mounted with `layout: false`: the heading and the table straight in the root layout. A bare table brings no landmark, so the demo's root layout has the `<main>` around every page, beside its header |
| http://localhost:4478/task_labels | `TaskLabel` | a primary key of two attributes: rows are named, found and saved by both parts together. `Note` is editable; offset pages of 25. One row action, a destroy relabelled "Remove", which runs at one click and says so (`confirm false`); "New task label", whose panel has a field for the task and one for the label, each of which opens the picker |
| http://localhost:4478/specimens | `Specimen` | no columns declared: how every built-in type is shown, and the filter each gets by default. With `update_action :update`, every type with an editor is editable, beside the read-only ones: among them the arrays "Strings" and "Integers", edited value by value, and "Shades", a multiple choice; and the values made of fields, edited in the side panel: "An address" (an embedded resource), "Addresses" (an array of them, without a primary key) and "A typed map" (a map that declares its fields). "A map", which declares none, is shown from whatever it holds and is read-only; "A keyword", "A tuple" and "A struct" stay read-only text. "A union" is a number, a text, a shade or an address: its cell shows the value it holds, and it is edited in the side panel, the kind first. `A string` is case-sensitive, `A ci string` beside it is not; the `opt_*` columns offer "is empty" |
| http://localhost:4478/deadlines | `Deadline` | the tasks once more, as a resource of its own over the same table, read through an action that **requires** an argument: the day they are due by. Until "Due by" is given the table reads nothing and says "Fill in Due by to see records."; "Include done?" is an argument with a default, and "Tags" a list that is given value by value. "Due on" is edited in place: a task that is put off beyond the day stays in its row until the table reads again. "Assignee" is a reference cell that is edited through an argument: its action, `hand_over`, does not accept `assignee_id`; it takes the person as an argument and hands it to the relationship, and the cell opens the picker all the same (see "Row actions and create" below). A row expands into its comments |

The tasks have **footer summaries**: under the last row, the average
progress, the sum of the estimates, the latest due date and the number of
completed tasks, each over every task that matches and not only the page
(`summary` on four columns of `lib/demo/tracker/task.ex`). Max Member sees
the estimate of his own tasks only, and has "Sum –" under that column. The
tasks nested under a project on `/projects` end with the same row.

The tasks and the comments have **live updates**: `live? true` in their
`table` blocks, and `pub_sub Demo.PubSub` in the domain's
(`lib/demo/tracker.ex`). Open `/tasks` in two browser windows, one of them
private, as Ada Admin and as Max Member, and change a title as Ada: Max sees
it without a reload. Create a task as Ada: Max's table says "There are new
or changed records." and offers "Read again". In one window, `/named` shows
the same between two tables of the comments. The projects and the labels
announce nothing, and their tables stay as they were read.

Three more pages show **named tables**: a resource with a second table
beside its default one.

| URL | Resource | Shows |
| --- | --- | --- |
| http://localhost:4478/tasks/board | `Task`, table `:board` | a second table of the tasks, declared in a file of its own (`lib/demo/tracker/task/board_table.ex`, a fragment of the resource): four columns, "Title" and "State" edited in place, one row action ("Archive"), no "New task". Its id is `task_board`. A row expands into "Comments", which nests the compact table of the comments and links to its full view at `/comments/compact`, and into "Labels", which nests the short table of the labels (`:short`, declared in `label.ex`): that table is mounted nowhere, so it has no "Open in full view", although `/labels` exists. The assignee is chosen in the picker, which shows the people's default table |
| http://localhost:4478/comments/compact | `Comment`, table `:compact` | a second table of the comments, in a file of its own too (`lib/demo/tracker/comment/compact_table.ex`): "Body", "Author" (the author's name, where `/comments` shows the key) and "Inserted at"; "Body" shows up to three lines of a comment (`max_lines 3`), and what is cut off after that under the cell, on focus or under the pointer; nothing is edited, there is no row action and no "New comment", and rows do not expand. Its id is `comment_compact`. For nobody it says "You are not allowed to see these records.": the named table says `on_forbidden :message` itself, since it takes nothing over from the default table |
| http://localhost:4478/named | `Comment`, both tables | a LiveView of the demo's own (`DemoWeb.NamedLive`) with the default table and the compact table of the comments, placed with `<AshTable.table>` and no `id`. Sort both: the address holds `comment[sort]=…` and `comment_compact[sort]=…` side by side. The comments have **live updates** (`live? true`), so the two tables follow each other: change a comment's text in the first and the same row changes in the second; create one in the first and the second says "There are new or changed records." with "Read again"; delete one and its row goes from both |

http://localhost:4478/dashboard is a LiveView of the demo's own
(`DemoWeb.DashboardLive`) with two tables placed in it with
`<AshTable.table … />`: the projects and the tasks, each given the actor and
the tenant as attributes. Each sorts, filters, pages, saves and runs its
actions by itself, and nothing of it is in the URL. Each table renders the
line above it, its name and its create button; `heading={2}` makes that name
an `h2` of the page, and the page's sections are labelled by it. As nobody,
the projects' read is refused, and that table renders nothing at all, its
name included.

### Rows that expand: nested tables

The mark at the start of a row expands it into one line per relationship,
and a line opens the table of the related records inside the row: the
destination resource's own table, with its own sort, filters, pages and
editing. Nothing of it is in the URL.

| Table | A row expands into | Declared how |
| --- | --- | --- |
| `/tasks` | Comments (has-many, keyset pages), First comment and Newest comment (has-ones that each pick one of many by their own sort: the first one sorts against the comments' read action), Labels (many-to-many, not paginated), Project, Assignee and "Reported by" (belongs-tos: a table of one row) | seven `relationship` lines in the `table` block, two of them relabelled; `max_depth` is the default, 3 |
| `/projects` | Tasks (has-many, offset pages of 25) | nothing declared: every public relationship whose destination has a table |
| `/comments` | Task, Author | nothing declared |
| `/labels` | Tasks (many-to-many, offset pages) | nothing declared |
| `/task_labels` | Task, Label, from a row with a key of two attributes | nothing declared; `max_depth 1`: the nested task has no expanders |

`User` has a table and no page: it is seen nested, as the assignee
or the reporter of a task or the author of a comment, and in the picker,
where the assignee of a task is chosen from it. Its block says
`max_depth 0`, so a person's row never expands, although a user has assigned
and reported tasks that would be offered. Its last column, "Assigned hours",
is an aggregate over the estimates of a person's tasks, which a field policy
protects on the tasks: the aggregate has a field policy of its own (admins),
because Ash does not apply the tasks' one to it.

### The full view of a nested table

The last row of a nested table is a link, "Open in full view". It goes to the
page of the destination's own table, limited to the same records: from the
comments under a task to
`/comments?comment[of][task][comments]=THE-TASK'S-ID`, under a heading that
names the task ("…: Comments") with "Show all records" beside it. There the
table has its state in the address.

The link is there where the router mounts the destination: comments, labels,
projects, tasks and task labels. It is **not** there for people ("Assignee",
"Reported by", "Author"), whose table has no page: `User` is left unmounted
as the example of that.

- Open the tasks of "Mobile app" from `/projects` in the full view, sort and
  page them, reload, and send the address to yourself as another actor.
- Change the key in the address to something else: "This record is no longer
  available.", and no record is named. Change `task` to `nothing`: the plain
  table.
- Go back with the browser: the page you came from, with its sort and page,
  and its rows closed again.

Things to try:

- `/tasks`: expand a row, open "Comments" and "Project"; in the project's
  one row, expand again and open "Tasks": three levels deep, and at the
  third the rows have no expander. Task → Comments → Task → Comments is a
  cycle that ends the same way.
- `/projects`: expand "Mobile app" and open its tasks. Sort them, filter
  them, go to their second page, edit a title: the projects around them stay
  as they are, and so does the URL.
- `/tasks` as Ada Admin: under a task, edit the body of a comment, the
  colour of a label and the name of the project. A nested table is the
  destination's own table, so it edits what that table edits on its own
  page. Under "Assignee" and "Reported by" no cell opens: the table of the
  people names no `update_action`, as the demo's one read-only table.
- With the keyboard: Left Arrow from the first data cell of a row reaches
  its expander; Right Arrow opens it and Left Arrow closes it; Down Arrow goes
  through the lines; on the cell of a nested table Enter goes in and Escape
  comes back out. Tab leaves the whole tree.
- As **Vera Viewer**, the lines "Assignee" and "Reported by" are not there
  under a task, nor "Author" under a comment: a viewer's read of the people
  is refused outright. For the same reason `/tasks` has no "Assignee" and no
  "Reported by" column for her. The tasks under a project have no editors
  for her.
- As **Max Member**, the tasks under a project have no "External ref"
  column, and "Estimate hours" is "Not available" except on his own tasks.
  Filter them by "Estimate hours" greater than 10: the total under the
  nested table goes away while the filter is set (see the README's
  "Nested tables").
- As **Olga Outsider**, everything nested is Globex's.
- As Ada Admin or Max Member: under a task, open "Comments" and use "New
  comment" on the line. The panel asks for the body alone; the task is the
  row above. The comment is the first row of the nested table, and the
  "Comments" cell of the task still shows the old count until the page is
  read again. On `/projects`, the "Tasks" line of a project has "New task",
  without the field "Project ID". "Labels", "Project" and the other lines
  have no such button: a nested table creates only under a has-many whose
  create action takes the joining key.
- With the keyboard: F2 on a line that has a create button goes to its
  controls; Enter on the line opens and closes it, as before.

### The argument line

A table whose read action takes arguments, or whose columns ask for the
arguments of their calculations, has a line of inputs above its grid.

- `/tasks`: type `login` into "Search" and press Enter, or leave the input.
  The rows, the count under the table and the address follow
  (`/tasks?task[a][search]=login`); reload, or send the address to yourself
  as another actor. Nothing is sent while you type.
- `/tasks`: "Due within 7 days" and "Due within" are one calculation,
  `due_within?`, twice: `arguments days: 7` fixes the first, and
  `ask :days, default: 30` asks for the second, which is named with
  `as :due_within`. Change "Due within: Days" to `365`: the second column
  follows, the first does not. Sort by either, and filter "Due within" to
  "Yes" and "Due within 7 days" to "No" at once.
- `/tasks`: type `-1` into "Due within: Days". The calculation's argument
  has `min: 0`: the input is marked and says "must be greater than or equal
  to 0", and the rows stay as they are.
- `/deadlines`: "Fill in Due by to see records." Give a day; tick "Include
  done?"; use "Add value" beside "Tags", type `api` and press Enter. Empty
  "Due by" again.
- `/deadlines`, with a day: change the "Due on" of a row to a day after it.
  The row stays; press Enter on it again and change something else: "This
  record is no longer available.", as the action no longer returns it.
- `/projects`: expand a project and open "Tasks". The nested table has the
  line of the tasks, and what is typed there narrows that table alone, with
  nothing in the address.
- `/comments`: "New comment", then "Choose" beside "Task": the tasks to
  choose from can be searched.

### In your time zone

The tables show, take and filter by datetimes ("Completed at" of `/tasks`)
in the time zone of your browser, which `assets/js/app.js` sends when the
page connects. `DemoWeb.Zone` (an `on_mount` hook) checks it against the
time zone database (`tz`) and assigns it as `time_zone`, UTC for a zone it
does not know. Where it is not UTC, a line above the tables says which:
"Times in Europe/Berlin". To see another zone, start the browser in one
(`TZ=America/New_York chromium`, or the "Sensors" panel of Chrome's
developer tools), and open `/tasks` once more. The browser tests run in UTC,
`zones.spec.ts` in Europe/Berlin.

### In German

The language switcher beside the actor switcher posts to `POST /locale`,
which stores `"en"` or `"de"` in the session under `"locale"`;
`DemoWeb.Locale` (a plug and an `on_mount` hook) puts it into the process
with `Gettext.put_locale/1`. The demo's own pages stay in English; the
tables follow:

- `config :ash_table, gettext_backend: DemoWeb.Gettext` and
  `priv/gettext/de/LC_MESSAGES/ash_table.po`: the table's own texts, and the
  wording of `/tasks` (its name, column labels, enum labels, the question
  before a change of state, the labels of its row actions and of the fields
  of their panels). For every table: the row actions, their questions, and
  what one record is called, so that "New task" is "Aufgabe anlegen". The
  other tables' column labels are not translated, and show as they are.
- `config :ash_table, translate_error: {DemoWeb.CoreComponents, :translate_error}`
  and `priv/gettext/de/LC_MESSAGES/errors.po`: the messages of the tasks'
  actions. Try a title of two characters, a progress of 150, or the state
  "Erledigt" on a task below 100.

The table tests are in `test/demo_web/tables/`: LiveView tests that open
these pages and click through them as each of the actors. Filtering is in
`task_filter_test.exs` and `specimen_filter_test.exs`, inline editing in
`task_edit_test.exs` and `specimen_edit_test.exs`, what each actor sees and
may edit in `task_authorization_test.exs` and `nobody_test.exs`. Row actions
are in `task_actions_test.exs`, row create in `task_create_test.exs`, create
in a nested table in `nested_create_test.exs`, both on the other pages, in
the dashboard and in German in `actions_elsewhere_test.exs`, and what the
action panel does with hidden fields and with every kind of failure in
`action_fields_test.exs`, on a resource of `test/support/plain_tables.ex`.
Row selection and bulk actions are in `task_bulk_test.exs` and, for the
other tables, a nested table and the resources of
`test/support/bulk_tables.ex`, in `bulk_elsewhere_test.exs`.
Table actions are in `label_actions_test.exs`, on `/labels`, and in
`table_actions_test.exs`, on the resources of
`test/support/action_tables.ex`: every kind of generic action, in a row, on
the selected rows and in a nested table.
Unions are in `specimen_union_test.exs` ("A union" on `/specimens`: its
cell, the side panel, the kinds one after the other, saving and what a
refused save says) and in `union_table_test.exs`, on the resource of
`test/support/union_tables.ex`: a union that cannot be empty, a tagged one,
a kind with a value in it that can be left out, a union inside an embedded
resource, unions that cannot be edited, and a union among the inputs of a
row action, of the create action and of an action on the selected rows.
Files are in `label_import_test.exs` ("Import" on `/labels`: the file
input, the upload and its limits, what the action reads and what it
refuses) and in `file_actions_test.exs`, on the resource of
`test/support/file_tables.ex`: a file for a row action, for a generic
action, for the create action and for the selected rows, two files in one
action, a file that can be left out, and what becomes of the file
afterwards.
Relationships an action manages are in `task_labels_action_test.exs` ("Set
labels" on `/tasks`: its field, the picker for several, what a hand-made
form cannot do, the action's policies, the selected rows, a nested table,
German), in `deadline_assignee_test.exs` (the "Assignee" cell of
`/deadlines`, which is edited through an argument) and in
`managed_relationships_test.exs`, on the resources of
`test/support/relation_tables.ex`: an argument that adds, one that takes
away, one key for a relationship of many, keys that are not the primary
key, a destination whose rows are named by two attributes, a picker in
pages and with an argument line, records a person may not read, and an
action that is refused.
Languages are in `translation_test.exs` and `translation_settings_test.exs`,
tables placed in a LiveView in `embedded_table_test.exs`, the key of two
attributes in `task_label_table_test.exs`, a read that fails in
`failed_read_test.exs` and what a failed save says about other fields in
`save_error_fields_test.exs`; the last two use resources of
`test/support/plain_tables.ex`.
`domain_settings_test.exs` covers the `table` block of a domain, and what a
layout is told about who is asking; the demo's own domains keep the
defaults, so it uses two small domains of its own
(`test/support/guarded_tables.ex`), mounted under `/support` in the test
environment only. A keyset table whose action does not count is in
`uncounted_table_test.exs`, and tables placed in a LiveView with their state
in its URL in `embedded_url_table_test.exs`; both use resources of
`test/support/plain_tables.ex` too.

Some filters to try, as the admin:

- http://localhost:4478/tasks?task[f][title]=session — text. `Session` with a
  capital finds nothing, because `title` is a `:string`
- http://localhost:4478/tasks?task[f][progress][at_least]=50&task[f][billable%3F]=yes&task[sort]=progress
  — two filters and a sort
- http://localhost:4478/tasks?task[f][due_on][is_empty]= — tasks without a due date
- http://localhost:4478/tasks?task[f][overdue%3F]=yes&task[f][comment_count][greater_than]=2
  — a calculation and an aggregate
- http://localhost:4478/specimens?specimen[f][a_ci_string]=ALPHA — a
  `:ci_string` finds `Alpha`, `alpha` and `ALPHA`

### Editing on `/tasks`

Enter or F2 on a cell starts editing, as does typing or a double click;
Enter or leaving the cell saves, Escape gives up.

| Column | Edited as | Through |
| --- | --- | --- |
| `title`, `description` | text; Shift+Enter makes a new line | the table's `update_action :update` |
| `status` ("State") | a choice | `update`, after the question of its `confirm`: "Change the state of this task?" |
| `priority` | a choice | its own action, `reprioritise` |
| `progress` | a slider, with the number beside it: its column's component. It saves when it is let go and stays open; a step with the arrow keys is saved by Enter or by leaving | its own action, `set_progress`, which also starts a task that is still to do: its state changes in the same row |
| `estimate_hours` | a number with its unit beside it: the demo's own component | `update`. Empty it to see nil saved |
| `billable?` | a boolean: Enter toggles and saves | `update` |
| `due_on`, `completed_at` | a date, a datetime | `update` |
| `tags` | an array of text: Enter opens one field per tag in the cell, each with a button that takes it away, and "Add value" under them. Enter in a tag saves the list, as leaving the editor does; Escape gives it up | `update`, with the whole list. A task has five tags at most, of two to twenty characters each |
| `checks` | an array of enum values, as multiple choice: Enter opens a list of boxes in the cell, Space ticks, the arrow keys go from box to box, Enter saves | `update`, with the values that are ticked |
| `project` | a related record, chosen in the picker: Enter opens the projects' own table in a dialog at the right edge; a row is selected and "Choose" takes it | `update`, with `project_id` alone, after the question of its `confirm`: "Move this task to another project?". A task has to have a project: the picker has no "None" |
| `assignee` | a related record, chosen in the picker from the people's table | `update`, with `assignee_id` alone. "None" takes the assignee off |
| `reporter` ("Reported by") | read-only | no update action accepts `reporter_id` |
| `external_ref` | read-only | `update` accepts it, the column says `update_action false` |
| `overdue?`, `comment_count`, `headline`, `inserted_at` | read-only | a calculation, an aggregate, and an attribute no action accepts |

`reassign`, the action with a required argument, cannot be behind a column:
naming it as a column's `update_action` is reported when the resource is
compiled. It is a row action instead, whose panel asks for the reason.

Saves that fail, to try:

- as anyone: a `title` shorter than 3 characters, or an estimate below 0:
  the action's message on the cell, which keeps what was typed. Escape on the
  cell restores the saved value
- a tag of one character, or a sixth tag: refused with the action's message
  ("Tags 2: length must be greater than or equal to 2", "must have 5 or
  fewer items"); the cell shows the list as it was typed, and opens with it
  again, the tag that was refused marked
- move the progress of a task that is "Done" below 100: refused ("must be
  100 when the task is done"), the slider closes and the cell is marked
- set the state of a task with progress below 100 to "Done": refused because
  of another field, shown on the state cell as "Progress: must be 100 when
  the task is done"
- as the member: an edit of a task they neither reported nor are assigned
  to is refused on the cell, "You are not allowed to change this."; their own
  tasks they can change. On rows where `estimate_hours` is hidden from them,
  its cell cannot be edited
- as the member: choose another assignee for a task they neither reported
  nor are assigned to: the cell shows the chosen name, is marked, and says
  "You are not allowed to change this."
- as the viewer there is nothing to try: the table offers them no editing

The picker, to try, as Ada Admin:

- Enter on a cell of "Assignee": the people's table in a dialog at the right
  edge, with the row of the task's assignee selected and focused. Down
  Arrow, Space, then "Choose"; or Enter on a row; or a double click on a
  row. Focus is back on the cell.
- "None" takes the assignee off. Escape and "Cancel" change nothing.
- Up Arrow from the first row reaches the filters of the people's table:
  type a name, Enter. Escape there comes back to the grid, and once more
  closes the picker.
- Enter on a cell of "Project", choose another project: "Move this task to
  another project?" is asked on top of the picker.
- "Reported by" does not open: no action accepts its key.
- As Olga Outsider, the pickers offer Globex's people and projects.

After a save the row is shown from the action's result: `headline` follows a
new title, `overdue?` a new due date, without the page being read again.

### Maps and embedded resources

A value made of fields is shown on one line, `field: value, field: value`,
and edited in the side panel: Enter, F2 or a double click on its cell.

| Where | What it is | In the panel |
| --- | --- | --- |
| `/projects`, "Client" | an embedded resource, `Demo.Tracker.Client`, with another one inside it, `Demo.Tracker.Address`; it has a private attribute, which is never shown | a group "Client" with Name \*, Email, Key account? and, in it, a group "Address" with Street \*, City \* and Postcode |
| `/projects`, "Milestones" | an array of embedded resources, `Demo.Tracker.Milestone`, with a generated primary key, which is not shown | a group per milestone, "Milestones 1", "Milestones 2", each with Title \*, Due on and Reached?, a button that takes it away, and "Add value" |
| `/tasks`, "Repeats" | a map that declares its fields (`recurrence`): every, unit, until. Its column asks "Change how often this task comes round?" | a group "Repeats" with Every \* (a number), Unit \* (a choice) and Until (a date) |
| `/specimens` | "An address", "Addresses", "A typed map", and "A map", which is read-only | as above |

Things to try, as Ada Admin:

- `/projects`: Enter on the "Client" of "Customer portal". Focus is in
  "Name". Change the city and use "Save": the cell shows the new value and
  has the focus again. Open it again and use "Save" at once: nothing is
  saved.
- Empty "Name", or type `nobody` into "Email", and use "Save": "is
  required" and "must be an email address" at the fields, and the panel
  stays open with everything else as it was typed.
- Use the button beside "Address" ("Remove Address"): the address is gone
  and "Add value" stands in its place. "Save": the client has no address.
- The "Client" of "Data warehouse" is empty: the panel has "Add value" and
  nothing else. Add it, give a name, save.
- "Milestones" of "Internal tools": change a title, take the second one
  away, use "Add value" and fill it in, save. Empty a title and save: the
  message is at that milestone's "Title".
- "New project": add the client, its address and a milestone, and create.
- `/tasks`: "Repeats" of the second row ("Every: 4, Unit: Week"). Change
  "Every" and use "Save": the column's question is asked; Cancel comes back
  to the panel. Set "Every" to 0: "must be greater than or equal to 1".
  "Save" without a change asks nothing.
- As Max Member, change "Repeats" on a task that is not his: "You are not
  allowed to change this." above the fields. As Vera Viewer, nothing opens.
- In German (the language switcher): "Wiederholung", "Alle: 4, Einheit:
  Woche", "Speichern".

### Unions

A union is a value that is one of several kinds. `/specimens` has one, "A
union": a number, a text, a shade or an address (an embedded resource). Its
cell shows the value it holds and nothing of the kind: `969`, `chore`,
`Light`, `Street: Unionsweg 559, City: Leipzig, Primary?: No`.

Things to try (anyone may edit a specimen):

- Enter on the "A union" of the first row. The side panel has "Kind", which
  says "Number" and has the focus, and under it "Number" with 969.
- Choose "Text" under "Kind": the number goes and a text field is there,
  empty. Choose "Address": the fields of an address. Nothing is saved yet;
  Escape leaves the cell as it was.
- Type `-3` into "Number" and use "Save": "must be greater than or equal
  to 0" at the number. Choose "Address", leave "Street" empty and save: "is
  required" at "Street".
- Choose the empty entry of "Kind" and save: the cell is empty, and the
  panel then opens without a kind.
- With the keyboard alone: Enter on the cell, Down Arrow for the next kind,
  Tab into its field, type, Tab to "Save", Enter.
- In German: "Art", with "Zahl", "Text", "Farbton" and "Adresse".

### Components on `/tasks`

Four columns of `/tasks` name a `component`, a module that says how their
cells look and what they are edited with. Nothing else about them changes:
they are saved through the same actions, sorted and filtered as before, and
hidden from the same people.

| Column | Component | Shows | Edits |
| --- | --- | --- | --- |
| `status` ("State"), `priority` | `AshTable.Components.Badge`, shipped | the value's label in a badge | with the table's own menu |
| `progress` | `DemoWeb.Cells.Progress`, which takes its two parts from the shipped `AshTable.Components.Progress` and `AshTable.Components.Slider` | a bar with the number beside it | with a slider |
| `estimate_hours` | `DemoWeb.Cells.Hours`, the demo's own (`lib/demo_web/components/cells/hours.ex`) | the number with "h" | in a number input with "h" beside it |

- "Set progress" and "New task" have the slider and the hours input as
  fields of their panel. There a change saves nothing: it goes with the form.
- As Max Member, the estimates of tasks that are not his say "Not
  available": the component is not asked to show a hidden value.
- `/specimens` has no component on any column, so that the table's own look
  of every type stays visible beside `/tasks`.
- `Demo.Tracker.Task` names `DemoWeb.Cells.Progress`, a module of the web
  layer, and does not depend on it: `mix xref graph --source
  lib/demo/tracker/task.ex` lists no file of `lib/demo_web`.

### Row actions and create

A button in the last column of a row runs an update or destroy action on
that row's record; the button on the line of a table's name creates a
record. An action with inputs opens the action panel at the right edge of
the window first.

| Table | Row actions | Create |
| --- | --- | --- |
| `/tasks` | "Archive" (no inputs: runs at once), "Reassign" (the assignee, chosen in the picker, and a required reason: opens the panel), "Set progress" (one number, with the task's progress in it), "Destroy" (asks "Delete this task? This cannot be undone."), "Set labels" (the task's labels, any number of them chosen in the picker) | "New task": thirteen fields, among them "Project" and "Assignee", each with a button that opens the picker, "Tags" as a list of values and "Checks" as a multiple choice |
| `/projects` | "Set status" (a choice), "Destroy" (asks) | "New project" |
| `/comments` | "Destroy" (asks) | "New comment": the body, and the task, chosen in the picker |
| `/labels` | "Destroy" (asks), "Copy" (a generic action, see "Table actions" below) | "New label": the colour starts with the attribute's default |
| `/task_labels` | "Remove": a destroy that runs at one click, declared with `confirm false` | "New task label": the task and the label, each chosen in the picker, and a note |

Things to try, on `/tasks`:

- "Archive": the "State" cell of the row changes at once, and the row stays
  where it is.
- "Reassign": the panel is headed "Reassign:" and the task's title. Type a
  reason of two characters: the action's message is at the field. Use "Run"
  with the reason empty: "is required", and the panel stays open.
- "Destroy": Cancel in the dialog changes nothing; Confirm, which is in the
  error colour, takes the row away, and the range under the table counts one
  less.
- "New task": give a title, use "Choose" under "Project" and choose a
  project in the picker, which opens on top of the panel; the title is still
  there. The task is the first row of the page, whatever the sort,
  until you sort, filter or change page.
- "Set labels": the panel lists the task's labels under "Labels", each with
  a button "✕" that takes it out of the list. "Choose" opens the table of
  the labels on top of the panel, with a box in every row and the rows of
  the task's labels ticked; tick another, use "Choose", and the label is in
  the list. Nothing is saved until "Run". The action takes the labels as an
  argument (`argument :labels, {:array, :uuid}`) and hands them to the
  relationship (`manage_relationship(:labels, type: :append_and_remove)`):
  these labels and no others.
- As **Max Member**, "Archive" a task that is neither assigned to him nor
  reported by him: the row's last cell is marked and says "You are not
  allowed to do this." Escape on that cell clears it. His "New task" has no
  field "External ref". "Set labels" on such a task shows its labels, and
  "Run" is refused in the panel.
- With the keyboard: End moves to the actions cell, Enter to its first
  button, Left and Right Arrow between the buttons, Escape back to the cell.

And on `/deadlines`, once "Due by" has a day:

- Enter on an "Assignee" cell opens the picker on that person. Choose
  another: the cell shows the new name. "None" takes the assignee away.
  The column's action takes the person as an argument
  (`argument :assignee, :uuid`, `manage_relationship(:assignee, type:
  :append_and_remove)`); no update action of `Deadline` accepts
  `assignee_id`.
- As **Max Member**, on a task that is neither assigned to him nor reported
  by him: the cell is marked and says "You are not allowed to change this."

### Table actions

A table action runs on the table as a whole: a generic action of the
resource, named with `action` like a row action. Its button is on the line
of the table's name, after the create button. The demo's labels have five,
and one generic action in the rows.

| On `/labels` | The action | What its button does |
| --- | --- | --- |
| "Count unused" | no argument, returns a number | runs at once; the table says "Count unused: 0" above the grid |
| "Recolour" | two required arguments, returns how many labels it changed | opens the action panel with "From" and "To" |
| "Remove unused" | no argument, returns nothing, declared with `confirm` | asks "Delete every label that no task carries?", then says "Remove unused: done" |
| "Merge" | a key of a label and a list of such keys (`reference :into, …` and `reference :labels, …` in the block), returns how many labels it deleted | opens the action panel with "Into" and "Labels": each says what is chosen and has "Choose", which opens the picker with the labels |
| "Import" | one required argument that takes a file (`:file`), returns how many labels it made | opens the action panel with a file input, "File" |
| "Copy", in every row | takes the label's key (`record_argument :label_id`) and a name | opens the panel with "Name" alone; the table gives the key |

Things to try, on `/labels` as **Ada Admin**:

- "Count unused": "Count unused: 0". In the seed every label is on some
  task. Make one with "New label" and count again: 1.
- "Remove unused": Cancel changes nothing; Confirm deletes the label you
  made, and the table reads again.
- "Recolour": type `red` into "From" and use "Run": the action's message is
  at the field. With the colour of a label and `#123456`, the table says how
  many labels it changed, and shows them.
- "Merge": choose one label for "Into" and two others for "Labels", then
  "Run": the table says "Merge: 2", and every task that carried one of the
  two carries the first. No key is typed anywhere.
- "Copy" on a row: the panel is headed "Copy:" and the label's name. The
  name of another label is refused at the field, "has already been taken";
  a new name makes a label of the same colour.
- As **Max Member** or **Vera Viewer**: "Count unused" alone, and no
  "Copy". The actions that change labels are for admins.
- As **Olga Outsider**: the same buttons as her role in Globex has, and
  every action counts and changes Globex's labels alone.
- On `/tasks`, expand a row and open "Labels": the five buttons are on
  that line, after "Labels". A table action is the same there as on
  `/labels`: it is not told which task the line is under, so "Count unused"
  still counts the labels of the whole organization.
- With the keyboard: Tab reaches the buttons before the grid; on the
  "Labels" line of a task, F2 goes into the line's buttons, and Left and
  Right Arrow move between them.
- In German (the language switcher): "Unbenutzte zählen", "Umfärben",
  "Unbenutzte entfernen", "Importieren", "Kopieren".

### A file for an action

"Import" on `/labels` takes a file: a CSV with a label on each line, its
name and, after a comma, its colour (`#rrggbb`), which may be left out. The
`table` block limits the upload to one `.csv` file of 100 kB.

Things to try, as **Ada Admin**:

- Save two lines, `zebra,#00aa00` and `yak`, as `labels.csv`. "Import",
  choose the file, "Run": "Import: 2", and the labels are in the table.
- Change the second line to `yak,red` and import again: the panel stays
  open, with "line 2: colour must match the pattern …" at "File", and no
  label was made. The file input is empty again: a file is given once.
  Choose a corrected file and "Run".
- "Run" without a file: "is required" at "File".
- Choose a file that is larger than 100 kB: "The file is too large. The
  limit is 100 kB." at once, and "Run" runs nothing. A file that is no
  `.csv` is not offered by the file dialog, and refused if it is given all
  the same: "This type of file is not accepted."
- As **Max Member**: no "Import".
- In German: "Importieren", "Datei", "Die Datei ist zu groß. …".

### Selecting rows and bulk actions

A table with a row action has a box at the start of every row and one in
its header. Selected rows are counted on a line above the grid, which has a
button per action that runs on several rows: the table's row actions,
unless one says `bulk? false`, as "Destroy" on `/projects` does.

| Table | For the selected rows | Kept to one row |
| --- | --- | --- |
| `/tasks` | "Archive", "Reassign", "Set progress", "Destroy", "Set labels" | |
| `/projects` | "Set status" | "Destroy" (`bulk? false`) |
| `/comments` | "Destroy" | |
| `/labels` | "Destroy" | "Copy" (`bulk? false`: a name can be given to one label only) |
| `/task_labels` | "Remove", which asks here though it does not in a row | |
| `/specimens` | no boxes: the table has no row action | |

Things to try, on `/tasks`:

- **All rows succeed.** As Ada Admin, tick three boxes and use "Archive".
  A dialog asks "Run “Archive” on 3 records?"; Confirm, and the table says
  above the grid: "Archive: 3 done."
- **Some rows are refused by a policy.** As Max Member, tick the box in the
  header and use "Archive". He may change the tasks he is assigned to or
  reported: "Archive: … done, … not done.", "You are not allowed to do
  this. (…)", and the rows that were refused are still selected.
- **Some rows are refused by a validation.** As Ada Admin, select a task
  that is "Done" and one that is not, and use "Set progress". The panel
  asks once for the progress, with nothing in it: there is no one task to
  take it from. Choose 50: "Set progress: 1 done, 1 not done.", "Progress:
  must be 100 when the task is done (1)".
- **An action with inputs.** Select two tasks, "Reassign". The panel is
  headed "Reassign: 2 records". A reason of two characters is refused at
  the field before anything runs; with a reason, "Run" asks "Run
  “Reassign” on 2 records?" and both tasks get it. "Assignee ID" left
  empty unassigns both: an empty field is an empty value.
- **A question of its own.** "Destroy" asks "Delete this task? This cannot
  be undone. 3 records are selected."
- **Related records for all of them.** Select two tasks, "Set labels". The
  panel is headed "Set labels: 2 records" and lists no label: there is no
  one task to take them from. Choose a label and use "Run": both tasks
  carry that label and no other.
- **All that match.** Tick the box in the header: "25 selected", and
  "Select all 320 that match" appears. Use it, then filter "Title" by
  `email`: the selection is given up, as it was made under other filters.
  Sorting and paging keep it.
- **With the keyboard.** Space on any cell of a row selects the row. Shift
  with Down or Up Arrow selects as it goes. Shift+Tab from the grid reaches
  the buttons of the line.
- **A nested table has its own.** Expand a task, open "Comments", tick two
  comments and use "Destroy" on the line above them. The tasks around them
  are not selected.
- As **Vera Viewer** there are no boxes: she can run no action.

| Actor | Row actions | Create |
| --- | --- | --- |
| admin | every button on every table, and each runs | every "New …" button |
| member | on `/tasks` and `/comments` the buttons are on every row, and a record that is not theirs refuses when the action runs; "Set status" and no "Destroy" on `/projects`; "Remove" on `/task_labels`; no actions column on `/labels` | "New task", "New comment" and "New task label"; no "New project" and no "New label" |
| viewer | no actions column on any table | no create button |
| outsider | as the member, on Globex's records | as the member; the records are Globex's |
| nobody | none | none |

### `/tasks`, actor by actor

Switch the actor at the top right and the same page changes:

| Actor | Rows | Columns | Editing | Row actions and "New task" |
| --- | --- | --- | --- | --- |
| admin | Acme's 320 tasks | all 17, `External ref` among them | every editable column, on every task | five buttons on every row, and each runs; "New task" |
| member | Acme's 320 tasks | 16: no `External ref`. `Estimate hours` is empty ("Not available") except on the tasks assigned to them | looks editable everywhere; a task that is not theirs refuses on the cell when it is saved | five buttons on every row; a task that is not theirs refuses on the actions cell or in the panel; "New task" |
| viewer | Acme's 320 tasks | 14: as the member, and no `Assignee` and no `Reported by`, as a viewer may not read people | none: no cell opens, nothing is marked read-only, there are no editors in the page | no actions column, no "New task" |
| outsider | Globex's 80 tasks | 16, as the member | as the member, on Globex's tasks | as the member, on Globex's tasks |
| nobody | none: "No records" | 14: no `External ref`, no `Estimate hours`, which nobody can ever see, and no `Project`, whose read is refused when nobody is logged in | none | none |

A column the actor can never see is left out of the page altogether, and
http://localhost:4478/tasks?task[sort]=external_ref or
http://localhost:4478/tasks?task[f][external_ref]=EXT shows them the plain
page. As the member, filter `Estimate hours` by "greater than 10": only their
own tasks are found; by "is empty": every task whose estimate is hidden from
them comes back too, whatever it holds.

## Who you are: the five actors

There is no login. The switcher at the top right of every page posts to
`POST /actor`, which stores the chosen user's id in the session under
`"actor_id"`; choosing "Nobody" removes it. `DemoWeb.Actor` (a plug and an
`on_mount` hook) turns the session into two assigns, on the conn and on the
socket. They are the names `ash_table` reads by default, and `Demo.Tracker`
writes them out in its `table` block (the extension `AshTable.Domain`):

- `current_user`: the `Demo.Tracker.User`, or `nil`
- `current_tenant`: that user's `organization_id`, or `nil`

| Actor | Name | Email | Role | Organization | User id |
| --- | --- | --- | --- | --- | --- |
| admin | Ada Admin | `admin@acme.test` | admin | Acme | `0b000000-0000-4000-8000-000000000001` |
| member | Max Member | `member@acme.test` | member | Acme | `0b000000-0000-4000-8000-000000000002` |
| viewer | Vera Viewer | `viewer@acme.test` | viewer | Acme | `0b000000-0000-4000-8000-000000000003` |
| outsider | Olga Outsider | `outsider@globex.test` | member | Globex | `0b000000-0000-4000-8000-000000000004` |
| nobody | | | | | no id in the session |

The organizations are Acme (`0a000000-0000-4000-8000-000000000001`) and Globex
(`0a000000-0000-4000-8000-000000000002`). All of this is in `Demo.Actors`.

## Seed data

`Demo.Seeds` empties the database and fills it again, so seeding can be
repeated at will. With the same profile it always produces the same records
with the same ids; only dates move, because they are relative to today.

```sh
mix run priv/repo/seeds.exs              # standard (also run by mix setup)
SEED=large mix run priv/repo/seeds.exs   # large
```

| Profile | Tasks | Also | Takes about |
| --- | --- | --- | --- |
| standard | 400 (Acme 320, Globex 80) | 2 organizations, 14 users, 10 projects, 16 labels, 480 comments, 36 specimens | 1 s |
| large | 50,000 (Acme 45,000, Globex 5,000) | the same, with 60,000 comments | 25 s |

Seeds write straight to the data layer (`Ash.Seed` and bulk `insert_all`), so
no actor, tenant check or policy is involved.

`Demo.Generator` holds the generators, built on `Ash.Generator`. It keeps its
own random state, seeded with `Demo.Generator.reseed/1`, and draws the values
of a record in the order they are written in (a map of generators would be
walked in an order that changes from one start of the VM to the next), which
is what makes the data repeatable. Tests get a small data set from the same
generators:

```elixir
use DemoWeb.ConnCase, async: true

setup %{conn: conn} do
  world = world(tasks: 30)                      # Demo.Fixtures.world/1
  %{world: world, conn: log_in(conn, world.member)}
end
```

`world/1` returns the two organizations, the actors (`admin`, `member`,
`viewer`, `outsider`, and `nobody`, which is `nil`), projects, labels and
tasks. In tests the ids are fresh ones, not the fixed ones above.

## The domain at a glance

`Demo.Tracker`, on Postgres:

| Resource | Tenant | Read actions and pagination |
| --- | --- | --- |
| `Organization` | is the tenant | `read`: none |
| `User` | no (filtered by policy) | `read`: offset, countable, 25 |
| `Project` | yes | `read`: offset, countable, 10 |
| `Task` | yes | `read`: offset and keyset, countable, 25, at most 100 · `offset_only` · `keyset_only` · `unpaginated` · `open`: offset and keyset, countable, 10, its own filter and sort |
| `Comment` | yes | `read`: keyset only, 20 |
| `Label` | yes | `read`: none |
| `TaskLabel` | yes | `read`: offset, countable, 25 |
| `Deadline` | yes | `read`: offset, countable, 25 · `due`: the same, with the required argument `by`, `include_done?` (false unless given) and `tags` |

`Deadline` is a second resource over the tasks' table (`migrate? false`):
the tasks that are due by a day. It has no records of its own, so the seed
is the tasks'. Its `hand_over` takes the assignee as an argument and hands
it to the relationship; its table edits the "Assignee" cell through it.

Every primary read action carries its default sort (`prepare build(sort: …)`).

Multitenancy is Ash's attribute strategy on `organization_id`, with
`global? true`: a read without a tenant is not an error, and the policies then
decide (nobody sees nothing).

`Task` has, on purpose:

- every relationship kind: `belongs_to` project, assignee and reporter;
  `has_many` comments; `has_one` latest_comment and first_comment (each
  picks one of many by its own sort); `many_to_many` labels
- enums with labels (`status`, `priority`), a 0 to 100 `progress`, a decimal,
  a boolean (`billable?`), a date, a datetime, long text
- two arrays: `tags`, text, at most five values of two to twenty characters,
  and `checks`, values of the enum `TaskCheck`
- a map that declares its fields: `recurrence` (every, unit, until)
- aggregates: `comment_count`, `last_commented_at`, `label_count`
- calculations: `overdue?` (an expression), `headline` (a module, computed in
  Elixir), `due_within?` (needs the argument `days`: a column twice, once
  with seven days fixed and once asking the person for them)
- a read action with an argument that may be left empty: `read` takes
  `search`, a text looked for in the title and the description
- update actions accepting different fields: `update` (most), `reprioritise`
  (priority; it also leaves "Reprioritised" in the private `internal_note`),
  `set_progress` (progress; it also moves a task from "To do" to "In
  progress"), `reassign` (assignee, and a required argument `reason`),
  `archive` (nothing), `set_labels` (nothing; it takes the labels as an
  argument, a list of keys, and hands them to the relationship with
  `manage_relationship`); plus `create` and `destroy`. Five of them are row
  actions of its table (`archive`, `reassign`, `set_progress`, `destroy`,
  `set_labels`), and `create` is its create action
- a validation that fails on another field: a task can only be `done` with
  progress 100

`Project` has two values made of fields: `client`, an embedded resource
(`Demo.Tracker.Client`: name, email, key_account?, an `address` that is an
embedded resource itself, and a private `credit_note`), and `milestones`, an
array of embedded resources (`Demo.Tracker.Milestone`: a generated primary
key, title, due_on, reached?). Both are accepted by `create` and `update`.

`Demo.KitchenSink.Specimen` has one public attribute per built-in Ash type:
string, ci_string, atom (`one_of`), integer (min and max), float, decimal,
boolean, date, time, time_usec, utc_datetime, utc_datetime_usec, datetime,
naive_datetime, duration, duration_name, uuid, uuid_v7, binary,
url_encoded_binary, map, map with fields, keyword, tuple, struct, term, module,
a date range, arrays of strings, integers and an enum, an embedded resource and
an array of it, a union (of a number, a text, an enum and that embedded
resource), a NewType and an `Ash.Type.Enum`, plus `opt_*`
nil-able variants. It has no tenant, is open to anyone, and paginates by
offset (20). Its table is edited through `update`, which accepts all of them. Left out: `function`, `file` and `vector`, which have no sensible
column here (the last needs the pgvector extension). A file is no attribute
at all: Ash stores none. The labels' "Import" has one as an argument.

## What is private or restricted, and why

So that the rule "only public things appear" and every authorization outcome
can be seen:

**Private fields** (never a column):

- `Task.internal_note`, `Task.updated_at`, the private calculation
  `Task.stale?`, and the relationship `Task.task_labels`
- `organization_id` on every tenant resource

`Task.inserted_at` is a timestamp made public. `Task.external_ref` is public
and an admin's alone by its field policy.

`Project.budget` is public and `sensitive?`. Sensitive is not hidden, so it
is a column, and its cells are masked: `••••••` and a "Show" button. Open
http://localhost:4478/projects as Max Member, use "Show" on a row (or
Shift+Enter on the cell), then click elsewhere: the number is gone again.
Enter on the cell opens an editor that hides what is typed; left empty it
saves nothing, and "Clear" beside it (Tab, then Enter) empties the budget.
"Set budget" in the row has the same button in its panel. As Vera Viewer
the column is not there: a field policy keeps the budget to admins and
members.

**Policies on `Task`**

- Read is *filtered*: you see the tasks of your own organization; nobody sees
  none. Members and viewers see all of them.
- Actor only: an admin may run every action; a viewer may run no create,
  update or destroy.
- Record-dependent: a member may update or destroy only the tasks they are
  assigned to or reported.

**Field policies on `Task`**

- `external_ref`: admins only (actor only). For everyone else the field is
  never visible, and the table leaves its column out.
- `estimate_hours`: admins, or the task's own assignee (record-dependent). A
  member sees it on some rows and not on others; the column stays, with
  "Not available" in the hidden cells. Nobody is no task's assignee, so for
  nobody the column is left out as well.

**Elsewhere**

- `Project`'s read is *refused outright* for nobody (a strict policy), where
  most resources return nothing. Its table answers 404. Only admins create or
  destroy projects.
- `Comment`'s read is refused outright for nobody as well, and its table is
  declared with `on_forbidden :message`. Its author or an admin may change a
  comment.
- `User`'s read is refused outright for a viewer (a strict policy), and
  filtered to the reader's organization for everybody else. So the lines to
  people, and the columns that show a person, are left out for a viewer: the
  table asks Ash whether the reader can ever read a relationship's
  destination.
- `User.assigned_hours` and `Project.estimated_hours` add up
  `Task.estimate_hours`, which a field policy protects on the tasks. Ash
  applies the tasks' read policy to an aggregate and not their field
  policies, so each aggregate has a field policy of its own: admins. The
  first is a column of the people's table; the second is no column anywhere,
  and is protected for the resource's other interfaces.
- `Label`, `User`, `Organization`: only admins write.

## Browser tests

`demo/e2e` holds the tests that need a real browser: the keyboard, focus
after a patch, the editors and the dialog, what each actor's page contains,
and axe-core on every table in every state. They are written with Playwright
and `@axe-core/playwright` and run in headless Chromium.

Node is a tool for developing `ash_table` here, nothing more: the library
puts no npm package into a host app, and neither does the demo itself.

```sh
docker compose up -d postgres   # in the repository root, if it is not running
cd demo && mix deps.get
cd e2e
npm ci                          # Node 24, pinned in e2e/.tool-versions
npm run browsers                # once: Playwright's Chromium
npm test
```

`npm test` does everything else by itself, in a Mix environment of its own,
`e2e` (`config/e2e.exs`): compiled once into `_build/e2e`, without code
reloading or watchers. A dev server on 4478 and `demo_dev` are not touched.
The first run compiles the demo for that environment, which takes a few
minutes.

The files run side by side, the tests of a file in their order. Each worker
of Playwright has a server and a database to itself (`e2e/support/server.ts`):

- Before the first worker, the demo is compiled, its assets are built, and
  one database, **`demo_e2e_template`**, is created, migrated and filled
  with the standard seed.
- A worker starts its own server from that build when it starts
  (`e2e/server/worker.exs`, nothing is compiled then): worker 0 on port
  **4480** with the database **`demo_e2e_0`**, worker 1 on 4481 with
  `demo_e2e_1`, and so on. The database is made anew as a copy of the
  template (`CREATE DATABASE … TEMPLATE …`), so every worker has the same
  records with the same ids.
- A worker stops its server when it is done. A server also ends by itself
  when its worker is gone, however that went, and one that is found on a
  worker's port from an earlier run is stopped first. What the servers wrote
  is in `e2e/.servers/<port>.log`; warnings and errors only.

`E2E_WORKERS` sets how many workers there are; the default is half the cores
and no more than six. A worker takes about 0.7 GB (a BEAM of 0.2 GB and a
Chromium of 0.45 GB). `E2E_WORKERS=1 npm test` runs the files one after the
other. `E2E_FIRST_PORT` moves the ports.

A failed test leaves a screenshot of the page as it was. No trace is
recorded: recording one costs about a third of a run. To see the steps of a
failed test, run it again with a trace, `npm test -- editing.spec.ts:765
--trace on`, and open it with `npx playwright show-trace …`.

While writing tests, `./server.sh` in a second terminal keeps one server
running, on port **4479** and the database **`demo_e2e`**, and
`npm run test:server` runs against it, one test at a time, with nothing
started or stopped (`npm run test:server -- editing`; it sets
`E2E_BASE_URL=http://127.0.0.1:4479`). `npx playwright test editing` and
`npm run test:ui` start servers of their own as `npm test` does;
`npm run report` shows the HTML report of the last run.

| File | What it covers |
| --- | --- |
| `navigation.spec.ts` | the grid as one tab stop; arrow keys, Home, End, Page Up and Down; the header rows; that moving sends nothing; where focus is after the rows were replaced |
| `sorting.spec.ts` | the cycle by click and by Enter, `aria-sort`, what cannot be sorted, the sort in the URL |
| `pagination.spec.ts` | offset pages, keyset pages, no pages; the page in the URL, reload, a shared link, the back button; that focus stays on the control that was used, and where it goes when that control is disabled or gone |
| `filtering.spec.ts` | every kind of filter and operator; a printable key on a filter cell, for each kind of control; Enter, leaving and choosing; Escape; clearing; what is read out; a value that is none; filters in the URL |
| `filter_values.spec.ts` | the filters that take more than one value: "is any of" and "is none of" by mouse and by keyboard (the list of boxes, that a tick asks the server nothing, Enter, Escape, Tab), "between" for a date and a number with one and both ends, the URL after each, a reload, "Clear filters", a narrow column, axe in both themes with the list open |
| `editing.spec.ts` | starting, giving up and saving an edit in every editor; the question before saving; a save that fails; a save that returns while another cell is typed in; a record that is gone |
| `authorization.spec.ts` | `/tasks` as each of the five actors; the member's hidden cells and refused save; the viewer; switching; reads that are refused |
| `tables.spec.ts` | that each mounted table opens and works, with what makes it different |
| `task_labels.spec.ts` | the table of a resource with a primary key of two attributes: its order, sorting, paging, the filter and the editing of its note, on the row that was meant |
| `dashboard.spec.ts` | two tables embedded in one LiveView: each with its own sort, filters and page and none of it in the URL; two grids, each one tab stop with a keyboard of its own; editing; a table whose read is refused |
| `locale.spec.ts` | the language switcher: the tables in German (labels, operators, counts in singular and plural, the messages of failed saves and reads), and back in English |
| `nesting.spec.ts` | nested tables: the expander and the lines by pointer and by keyboard; Right and Left Arrow; into a nested table and back out; one tab stop for the whole tree at every depth, and Tab out of it; that moving sends nothing and opening sends one event; focus after a nested table's own sort, filter and page, after a line or a row is closed, and after a save in the row around it; editing and filtering in a nested table; three levels and the limit; fifty tables open on one page |
| `full_view.spec.ts` | the link of a nested table to the full view, by pointer and by keyboard, and where it is not there; the page it leads to: its heading, the limit in the address through sort, filter and page and after a reload, the way back to all records, editing and expanding under the limit; the browser's back button; the page as the member, the viewer and the outsider; axe on it |
| `picker.spec.ts` | the picker: which reference cells open one, by Enter, F2 and a double click; the dialog, its heading and the table in it, with focus on the row of the record chosen now; the keyboard in its grid, and that moving and selecting send nothing; Tab within the dialog; its own filters and sort; Space and "Choose", Enter on a row, a double click, a click on a row, "None", Escape and Cancel, and where focus is afterwards; the question of a column on top of it; a choice the action refuses, on the cell; a row that names no record the person may read; in a nested table; from the action panel, on top of it, for a row action, a create and an action on the selected rows; a narrow window; German; axe in both themes |
| `relationships.spec.ts` | relationships an action manages: "Set labels" of `/tasks`, whose panel lists the task's labels in a named group, each with a button that takes it out, and where focus goes then; the picker for several on top of the panel, with a box per row, the rows of the task's labels selected and counted, a click and Space on a row, Enter and a double click that choose nothing, "Choose" that takes what is selected, a filter that keeps the selection, Escape; "Run", and the same on the selected rows; the member's refusal in the panel; a row that names no label the person may read; "Assignee" of `/deadlines`, a reference cell that is edited through an argument, with "None"; German; axe in both themes |
| `references.spec.ts` | reference cells: what they show against the related record itself, that they are cells for the arrow keys with nothing to sort or filter, and nothing to edit where no action accepts their key, that a row keeps them through a save, in a nested table, and as the viewer, who has none for people |
| `selection.spec.ts` | row selection and bulk actions: the boxes by pointer and by keyboard, Space on a cell, ranges with Shift, the box of the page and its mixed state; that selecting sends nothing and that the arrow keys still send nothing; the selection through a sort, a page and a filter change; "all that match"; the line above the grid and what is read out; the question, the panel of an action with inputs, and the result, as the admin and as the member, whose refused rows stay selected; where focus is afterwards; a nested table's own selection; a table told to let one row or several be selected with nothing to run on them; the height of a row with a box; axe with rows selected, with the question open and with a result, in the light and the dark theme |
| `actions.spec.ts` | row actions and row create: the actions cell by pointer and by keyboard; the question before a destroy; where focus is after an update, a destroy and a create; a failed actions cell; the action panel as a modal dialog, every kind of field, errors at fields and above them, the question on top of it; the create button and the new row; create on a relationship line, in the full view and in the dashboard; the look at 1500, 900 and 390 px |
| `table_actions.spec.ts` | table actions on `/labels`: their buttons on the line of the table's name, as tab stops before the grid, and what each actor has of them; an action that runs at once, by pointer and by keyboard, what the table says and reads out, and that focus stays on its button; one that asks first, with Cancel and Confirm; one with arguments, its panel opened from the keyboard, the action's message at a field, and focus back on the button; a generic action in a row, whose panel asks for what the row does not give; the buttons on the line of a nested table, with the keyboard, the nested table's own dialog and panel; axe-core in these states, in both themes |
| `action_references.spec.ts` | arguments whose records are chosen in the picker because the block says which resource they refer to (`reference`): "Merge" on `/labels`, with one key and a list of keys, by pointer and by keyboard, what "Run" does with them, and a key put into the field by hand; "Assign open tasks" in the rows of `/projects`, also on the selected rows; in German; axe-core in these states, in both themes |
| `counter.spec.ts` | the counter of a text with a `max_length`: in the editor of a cell (that it follows what is typed and sends nothing, is the editor's description and no live region, and leaves the row as high and the column as wide as before), counted as Ash counts (codepoints, trimmed, line breaks, with what Ash then takes and refuses), past the most; in an array of text, on a field of the action panel, where the server's answer does not set it back, and on the argument line, also after Back; axe-core in these states, in both themes |
| `sensitive.spec.ts` | the sensitive column "Budget" of `/projects`: the mask, showing and hiding a value, what is not in the page and not sent, the hidden editor; "Clear" in the editor (Tab to it and back, Enter, Space and a click, a column's question first) and in the panel of "Set budget" ("Will be cleared.", "Keep", "Run"); who has the column; in German; axe-core in these states, in both themes |
| `arrays.spec.ts` | the array columns of `/tasks`: that their cells are plain text, with no sort and no filter; the list of an array of text (a named control per value, adding and taking away from the keyboard and with the pointer, where focus goes, Tab through its controls and out of the grid, typing on the cell) and the multiple choice of an array of enum values (Space, the arrow keys, a letter); that nothing is sent until Enter or leaving, and one save then; Escape; a save the action refuses, and what the cell opens with afterwards; the member's refusal; both as fields of "New task"; both in a nested table; the list of an array of numbers on `/specimens`; axe with each editor open, with a failed cell, in the dark theme and in the panel |
| `maps.spec.ts` | the values made of fields: that their cells are one line of plain text, with no sort and no filter; the side panel of a project's client, opened by Enter, F2 and a double click, with focus in its first field and back on the cell when it closes; its groups, the address as a group in the group, and that a group is marked by nothing but its label; saving from the keyboard; what the embedded resources refuse, at their fields, with the other entries kept; taking a value away and adding it again, and where focus goes; a project without a client; "Save" without a change; the list of groups of the milestones (adding, typing, taking away from the keyboard, the last and the only value, a value that is refused); the map "Repeats" of a task, its column's question when "Save" is used and only for a change; both in "New project" and "New task"; the member's refusal in the panel; axe with the panel open, with errors shown and with the list of an array, in the light and the dark theme |
| `unions.spec.ts` | the union of `/specimens`: that its cell is the plain text of the value it holds, with no sort and no filter; the side panel, opened by Enter, F2 and a double click, with focus on the choice of the kind; choosing another kind, which puts its fields in place of the others; saving by keyboard alone, a kind made of fields, and no kind; what a refused save says at the value and at a field of a kind, with axe in both themes; and in German |
| `files.spec.ts` | "Import" on `/labels`: the file input of its panel, labelled, required and limited, as the first stop of the keyboard, with axe in both themes; a file that is sent and read when "Run" is used, and the bar that says how far it has come; what the action says of a file at the field, and that the input is empty again; a file the upload refuses, too large or of another kind, said as it is chosen and read out; and in German |
| `components.spec.ts` | the components of `/tasks`: the slider by keyboard (its keys are its own; a step is saved by Enter or by leaving) and by pointer (nothing sent while it is dragged, one save on letting go, the number beside it following, the slider staying open); Escape after a save; a save through it that fails; the question of a column before a change is saved; the demo's own component, whose editor saves on Enter or on leaving; the slider as a field of the action panel; the height of a row with and without components; components in a nested table |
| `arguments.spec.ts` | the argument line: its inputs as labelled tab stops before the grid; that typing sends nothing and Enter and leaving apply; the argument in the URL, reload, Back and Forward; a column's asked argument, its column sorted and filtered by with it; a value Ash refuses at its input, with the rows left as they are; `/deadlines` asking for its day in place of its rows; a box and a list from the keyboard; that the grid does not move; a nested table's line and a picker's; axe-core in each of these states, in both themes |
| `hiding.spec.ts` | hiding columns: the "Columns" button and its list, a box that hides its column and shows it again; that the label column and the columns of the boxes, the expanders and the actions have no box; a table without a label column, which keeps one column; Escape, a click elsewhere and focus that moves on; the keyboard through the list; that the arrow keys, Home and End pass over hidden columns and that focus and the tab stop leave a column that is hidden; that hidden columns outlive a sort, a filter, a page, a save, an expanded row and a patch that brings no row, and are shown again after a reload; a hidden column that is filtered or sorted by, said on the button and at its box, and "Clear filters"; widths kept while hidden; an editor, a shown sensitive value and the message of a failed cell in a column that is hidden; a nested table, a picker's table and two tables on `/dashboard`, each on its own; that nothing is sent; German; axe in both themes |
| `resizing.spec.ts` | column widths: dragging a column's handle narrower and wider with the mouse, that no other column moves and the handle stays under the pointer; that a drag and a click on it do not sort; a double click back to the width before; the narrowest and the widest; a narrow column cut off on one line with rows as high as before; F2 to the handle, the arrow keys, Home, End, Enter and Escape, and that the grid's keys are as they were; right-to-left; that the widths outlive a sort, a filter, a page, a save and an expanded row, and are gone after a reload and after leaving the page; a nested table, a picker's table and two tables on `/dashboard`, each on its own; that nothing is sent; German; axe in both themes |
| `scrolling.spec.ts` | every table scrolls sideways in its own area: a nested table as wide as what is seen of the table around it, at depth 1 and 2 and in another window size; Shift and the wheel; the scrollbar at the bottom edge of the window; the label column that stays with `sticky_label?`, and that nothing stays without it; focus that the keyboard moves is seen whole; what floats over a scrolled table; axe in both themes |
| `named_tables.spec.ts` | named tables: the compact comments and the board of the tasks as pages of their own, each under its own id and with its state in the URL; editing a cell of the board and choosing its assignee in the picker, which shows the people's default table; the compact comments nested under a task of the board, their link to the full view on the page of the same table, with the board named as the parent, the limit through a sort and a reload, and the way back; the short labels, mounted nowhere, without a link; that `/tasks` still nests the default tables; two tables of the comments on one page, each with its own ids, tab stop, sort and page in the one URL; axe-core in these states, in both themes |
| `long_text.spec.ts` | long text: a column with `max_lines 3` shows three lines of a comment with its line breaks and cuts off the rest, a row as high as its cell, a narrower column gives more lines; the whole text of a cell that cuts some off, under the cell on focus and when the pointer rests on it, not for a cell that shows everything and not while the arrow keys go through cells; Escape, the pointer on the text, scrolling; above the cell at the bottom of the window; in a nested table; a live update of the row; not while a cell is edited; none for a sensitive cell, masked or shown, and none for a field the person may not see; axe in both themes and forced colours |
| `a11y-tables.spec.ts`, `a11y-editing.spec.ts`, `a11y-nesting.spec.ts`, `a11y-actions.spec.ts` | axe-core, every rule, on every table and in every state, on the dashboard with its two tables, in German, with nested tables open at every depth, and with the components of `/tasks`: at rest, a slider open, a failed one, and in the panels; in four files, so that they run side by side: the tables, the dashboard, German, each actor and the states of reading; the states of editing, the components and what a person may not see; nested tables; row actions and the action panel |
| `zones.spec.ts` | the demo in a browser that is in Europe/Berlin: a time typed into a cell shown back as typed and stored as the instant it is (seen from a browser in UTC), a "between" filter on a datetime that means the times there and a URL that keeps them as typed; axe in both themes |
| `contrast.spec.ts` | what axe does not judge, measured from the colours the browser computed, in the light and the dark theme: the focus ring of every kind of cell; the ring and the "!" of a failed cell, that they move nothing, and both rings on a failed cell with focus; the text of a saving cell and of a table that is reading; the muted text of the header and the filters; the edges of inputs, and of invalid ones; the label and the edge of a badge, the filled part of a progress bar against its track, and the track, the filled part and the thumb of a slider, read from the pixels the browser painted. In forced colours: that the focus ring, the failed cell, the expander's triangle, the current page, the edges of the dialog and the panel, and a badge, a bar and a slider are still drawn |

How they are built (`e2e/support`):

- **Actors.** The setup project (`actors.setup.ts`) becomes each of the five
  actors once, through the actor switcher, and keeps the session cookie.
  Every worker's server takes it: they have one secret, and the seed gives
  the people the same ids in every database. A
  file or a test says who it is with `test.use({ actor: "member" })`; the
  admin is the default.
- **Data.** The tests run on the standard seed, whose records, ids and
  values are the same in every VM (`Demo.Generator` draws them in a fixed
  order), so tests name them (`support/data.ts`). A test that changes
  anything says `test.use({ writes: true })`, and the database is seeded
  again after it (half a second), so every test starts from the seed, in
  whatever order. Seeding goes through `POST /e2e/seed`, a route that exists
  in the `e2e` environment only (`e2e/server`, mounted by
  `config :demo, e2e_routes: true`), as do the one that deletes a task behind
  an open table's back, the two that make the reads of the comments fail
  and work again, and the page `/e2e/select`, whose tables let their rows be
  selected with nothing to run on them. A worker seeds its own database, so
  the tests of one file run one at a time, and the files side by side.
- **Language.** A test chooses German through the language switcher
  (`support/locale.ts`); the choice is in the session cookie, which every
  test has to itself.
- **The table.** `support/table.ts` is the one place that knows the ids of
  the library's markup and how to wait for a read or a save
  (`aria-busy`). Tests find controls by role and name where a person would,
  and cells by id.
- **Contrast.** `support/contrast.ts` gives the colour a text, an outline or
  a border has on the screen (painted by the browser over everything behind
  it), the colours at points of a picture of an element, for what no
  computed style tells (the filled part of a bar or of a slider), and the
  WCAG contrast ratio of two colours.
- **axe.** `support/a11y.ts` runs every rule axe has by default on the whole
  document. axe runs in the page and hands back the violations alone, in
  full; listing the ten thousand nodes that passed and carrying them out of
  the page took five seconds a check and more on `/tasks`.
- **Console.** Every test fails if the browser reported an error it did not
  expect.

A test marked `test.fail()` describes a defect that is known and not yet
fixed: it passes as long as the defect is there, and fails when it is gone,
which is the moment to remove the mark. No test is marked at present.

## Performance

`demo/perf` repeats the measurements of the prototype on the real demo: on
Postgres, with the large seed. The results of the last run that was committed
are in [`perf/RESULTS.md`](perf/RESULTS.md), with the machine, the versions,
the method and what the numbers say; every repetition is in
`perf/results.json`.

Nested tables were measured once, by `node nested.mjs`: what opening one
costs and what the server holds with 1, 10 and 50 open, in
[`perf/NESTED.md`](perf/NESTED.md).

```sh
docker compose up -d postgres   # in the repository root, if it is not running
cd demo && mix deps.get
cd perf
npm ci                          # Node 24, pinned in perf/.tool-versions
npm run browsers                # once: Playwright's Chromium
npm run setup                   # compiles; creates, migrates and seeds the two databases (about a minute)
npm run measure                 # starts the server itself; writes results.json and RESULTS.md (a few minutes)
```

- `npm run setup` fills **`demo_perf`** with the large seed (50,000 tasks)
  and **`demo_perf_standard`** with the standard one, and analyses both. It
  can be repeated.
- `npm run measure` starts the demo on port **4479** (`PERF_PORT`), once on
  each database, measures in headless Chromium, and stops it. `PERF_REPS`
  sets the repetitions (15). `npm run report` writes `RESULTS.md` again from
  `results.json` and `NOTES.md`, the findings written by hand.
- To see whether the scripts still run, without replacing the committed
  results: `PERF_REPS=1 PERF_RESULTS=/tmp/smoke.json node measure.mjs`. After
  a new migration the two databases want it first; `npm run setup` does that,
  and seeds them again.
- The server runs in the Mix environment `perf` (`config/perf.exs`): as
  production would, without code reloading, debug annotations or runtime
  checks, but started with `mix phx.server`, on plain HTTP, with assets that
  are not minified. `perf/server` is compiled in that environment only: the
  table of `/tasks` in pages of 100 at `/perf/tasks100`, and
  `Demo.Perf.Probe`, which collects the telemetry of LiveView, Ash and Ecto
  and reads the memory of the LiveView processes.

Measure on a machine that is doing nothing else; the load average is
recorded with the results.
