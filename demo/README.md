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
| http://localhost:4478/tasks | `Task` | a `table` block: chosen columns in a chosen order, a relabelled column, an aggregate, two calculations, and three reference cells ("Project", "Assignee", "Reported by": each shows a related record by its name, read-only, with no sort and no filter); offset pages of 25. Inline editing of every cell type (see below). Filters of every kind: text (`title`, `external_ref`), numbers (`progress`, `estimate_hours`), a date (`due_on`), datetimes (`completed_at`, `inserted_at`), booleans (`billable?` and the calculation `overdue?`), enums (`status`, `priority`), an aggregate (`comment_count`). No filter on `description` (`sortable? false` and `filterable? false`) and none on `headline` (computed in Elixir) |
| http://localhost:4478/projects | `Project` | no column declared: the public attributes. Its block says only what a project is called in other tables (`label_field :name`). Refused outright for nobody, who gets a 404: the page answers as if it did not exist |
| http://localhost:4478/comments | `Comment` | the public attributes again, the foreign keys among them: "Task ID" and "Author ID" are the raw keys, where `/tasks` shows names. Keyset pagination: next and previous only, and no page numbers. The action counts (Ash's `countable` is on unless an action says otherwise), so the line under the table gives the number of records without a range, and a filter change is announced with its count. Refused outright for nobody too, but declared with `on_forbidden :message`: nobody is told "You are not allowed to see these records." |
| http://localhost:4478/labels | `Label` | no pagination: every record. `label_field :name` and nothing else in its block |
| http://localhost:4478/bare/labels | `Label` | the same, mounted with `layout: false`: the heading and the table straight in the root layout. A bare table brings no landmark, so the demo's root layout has the `<main>` around every page, beside its header |
| http://localhost:4478/task_labels | `TaskLabel` | a primary key of two attributes: rows are named, found and saved by both parts together. `Note` is editable; offset pages of 25 |
| http://localhost:4478/specimens | `Specimen` | no columns declared: how every built-in type is shown, and the filter each gets by default. With `update_action :update`, every type with an editor is editable, beside the read-only ones. `A string` is case-sensitive, `A ci string` beside it is not; the `opt_*` columns offer "is empty" |

http://localhost:4478/dashboard is a LiveView of the demo's own
(`DemoWeb.DashboardLive`) with two tables placed in it with
`<AshTable.table … />`: the projects and the tasks, each given the actor and
the tenant as attributes. Each sorts, filters, pages and saves by itself, and
nothing of it is in the URL. As nobody, the projects' read is refused, and
that table renders nothing at all.

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

`User` has a table and no page: it is only ever seen nested, as the assignee
or the reporter of a task or the author of a comment. Its block says
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
- With the keyboard: Left Arrow from the first cell of a row reaches its
  expander; Right Arrow opens it and Left Arrow closes it; Down Arrow goes
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

### In German

The language switcher beside the actor switcher posts to `POST /locale`,
which stores `"en"` or `"de"` in the session under `"locale"`;
`DemoWeb.Locale` (a plug and an `on_mount` hook) puts it into the process
with `Gettext.put_locale/1`. The demo's own pages stay in English; the
tables follow:

- `config :ash_table, gettext_backend: DemoWeb.Gettext` and
  `priv/gettext/de/LC_MESSAGES/ash_table.po`: the table's own texts, and the
  wording of `/tasks` (its name, column labels, enum labels, the question
  before a change of state). The other tables' labels are not translated,
  and show as they are.
- `config :ash_table, translate_error: {DemoWeb.CoreComponents, :translate_error}`
  and `priv/gettext/de/LC_MESSAGES/errors.po`: the messages of the tasks'
  actions. Try a title of two characters, a progress of 150, or the state
  "Erledigt" on a task below 100.

The table tests are in `test/demo_web/tables/`: LiveView tests that open
these pages and click through them as each of the actors. Filtering is in
`task_filter_test.exs` and `specimen_filter_test.exs`, inline editing in
`task_edit_test.exs` and `specimen_edit_test.exs`, what each actor sees and
may edit in `task_authorization_test.exs` and `nobody_test.exs`.
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
| `progress` | a number | its own action, `set_progress`, which also starts a task that is still to do: its state changes in the same row |
| `estimate_hours` | a number | `update`. Empty it to see nil saved |
| `billable?` | a boolean: Enter toggles and saves | `update` |
| `due_on`, `completed_at` | a date, a datetime | `update` |
| `external_ref` | read-only | `update` accepts it, the column says `update_action false` |
| `overdue?`, `comment_count`, `headline`, `inserted_at` | read-only | a calculation, an aggregate, and an attribute no action accepts |

`reassign`, the action with a required argument, cannot be behind a column:
naming it as a column's `update_action` is reported when the resource is
compiled.

Saves that fail, to try:

- as anyone: a `title` shorter than 3 characters, or a `progress` above 100:
  the action's message on the cell, which keeps what was typed. Escape on the
  cell restores the saved value
- set the state of a task with progress below 100 to "Done": refused because
  of another field, shown on the state cell as "Progress: must be 100 when
  the task is done"
- as the member: an edit of a task they neither reported nor are assigned
  to is refused on the cell, "You are not allowed to change this."; their own
  tasks they can change. On rows where `estimate_hours` is hidden from them,
  its cell cannot be edited
- as the viewer there is nothing to try: the table offers them no editing

After a save the row is shown from the action's result: `headline` follows a
new title, `overdue?` a new due date, without the page being read again.

### `/tasks`, actor by actor

Switch the actor at the top right and the same page changes:

| Actor | Rows | Columns | Editing |
| --- | --- | --- | --- |
| admin | Acme's 320 tasks | all 17, `External ref` among them | every editable column, on every task |
| member | Acme's 320 tasks | 16: no `External ref`. `Estimate hours` is empty ("Not available") except on the tasks assigned to them | looks editable everywhere; a task that is not theirs refuses on the cell when it is saved |
| viewer | Acme's 320 tasks | 14: as the member, and no `Assignee` and no `Reported by`, as a viewer may not read people | none: no cell opens, nothing is marked read-only, there are no editors in the page |
| outsider | Globex's 80 tasks | 16, as the member | as the member, on Globex's tasks |
| nobody | none: "No records" | 14: no `External ref`, no `Estimate hours`, which nobody can ever see, and no `Project`, whose read is refused when nobody is logged in | none |

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
- aggregates: `comment_count`, `last_commented_at`, `label_count`
- calculations: `overdue?` (an expression), `headline` (a module, computed in
  Elixir), `due_within?` (needs the argument `days`)
- update actions accepting different fields: `update` (most), `reprioritise`
  (priority; it also leaves "Reprioritised" in the private `internal_note`),
  `set_progress` (progress; it also moves a task from "To do" to "In
  progress"), `reassign` (assignee, and a required argument `reason`),
  `archive` (nothing); plus `create` and `destroy`
- a validation that fails on another field: a task can only be `done` with
  progress 100

`Demo.KitchenSink.Specimen` has one public attribute per built-in Ash type:
string, ci_string, atom (`one_of`), integer (min and max), float, decimal,
boolean, date, time, time_usec, utc_datetime, utc_datetime_usec, datetime,
naive_datetime, duration, duration_name, uuid, uuid_v7, binary,
url_encoded_binary, map, map with fields, keyword, tuple, struct, term, module,
a date range, arrays of strings, integers and an enum, an embedded resource and
an array of it, a union, a NewType and an `Ash.Type.Enum`, plus `opt_*`
nil-able variants. It has no tenant, is open to anyone, and paginates by
offset (20). Its table is edited through `update`, which accepts all of them. Left out: `function`, `file` and `vector`, which have no sensible
column here (the last needs the pgvector extension).

## What is private or restricted, and why

So that the rule "only public things appear" and every authorization outcome
can be seen:

**Private fields** (never a column):

- `Task.internal_note`, `Task.updated_at`, the private calculation
  `Task.stale?`, and the relationship `Task.task_labels`
- `organization_id` on every tenant resource

`Task.inserted_at` is a timestamp made public. `Task.external_ref` is public
and `sensitive?`: sensitivity is not an exposure rule, so it is a column.

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

`npm test` does everything else by itself. It starts the demo through
`e2e/server.sh` in a Mix environment of its own, `e2e` (`config/e2e.exs`):
compiled once into `_build/e2e`, without code reloading or watchers, on port
**4479** and on its own database, **`demo_e2e`**, which it creates, migrates
and fills with the standard seed. A dev server on 4478 and `demo_dev` are not
touched. When the tests are done the server is stopped. The first run
compiles the demo for that environment, which takes a few minutes.

While writing tests, `./server.sh` in a second terminal keeps the server
running, and `npm test` uses it (`npx playwright test editing`,
`npm run test:ui`, `npm run report` for the HTML report of the last run).

| File | What it covers |
| --- | --- |
| `navigation.spec.ts` | the grid as one tab stop; arrow keys, Home, End, Page Up and Down; the header rows; that moving sends nothing; where focus is after the rows were replaced |
| `sorting.spec.ts` | the cycle by click and by Enter, `aria-sort`, what cannot be sorted, the sort in the URL |
| `pagination.spec.ts` | offset pages, keyset pages, no pages; the page in the URL, reload, a shared link, the back button; that focus stays on the control that was used, and where it goes when that control is disabled or gone |
| `filtering.spec.ts` | every kind of filter and operator; a printable key on a filter cell, for each kind of control; Enter, leaving and choosing; Escape; clearing; what is read out; a value that is none; filters in the URL |
| `editing.spec.ts` | starting, giving up and saving an edit in every editor; the question before saving; a save that fails; a save that returns while another cell is typed in; a record that is gone |
| `authorization.spec.ts` | `/tasks` as each of the five actors; the member's hidden cells and refused save; the viewer; switching; reads that are refused |
| `tables.spec.ts` | that each mounted table opens and works, with what makes it different |
| `task_labels.spec.ts` | the table of a resource with a primary key of two attributes: its order, sorting, paging, the filter and the editing of its note, on the row that was meant |
| `dashboard.spec.ts` | two tables embedded in one LiveView: each with its own sort, filters and page and none of it in the URL; two grids, each one tab stop with a keyboard of its own; editing; a table whose read is refused |
| `locale.spec.ts` | the language switcher: the tables in German (labels, operators, counts in singular and plural, the messages of failed saves and reads), and back in English |
| `nesting.spec.ts` | nested tables: the expander and the lines by pointer and by keyboard; Right and Left Arrow; into a nested table and back out; one tab stop for the whole tree at every depth, and Tab out of it; that moving sends nothing and opening sends one event; focus after a nested table's own sort, filter and page, after a line or a row is closed, and after a save in the row around it; editing and filtering in a nested table; three levels and the limit; fifty tables open on one page |
| `full_view.spec.ts` | the link of a nested table to the full view, by pointer and by keyboard, and where it is not there; the page it leads to: its heading, the limit in the address through sort, filter and page and after a reload, the way back to all records, editing and expanding under the limit; the browser's back button; the page as the member, the viewer and the outsider; axe on it |
| `references.spec.ts` | reference cells: what they show against the related record itself, that they are cells for the arrow keys with nothing to sort, filter or edit, that a row keeps them through a save, in a nested table, and as the viewer, who has none for people |
| `a11y.spec.ts` | axe-core, every rule, on every table and in every state, on the dashboard with its two tables, in German, and with nested tables open at every depth |

How they are built (`e2e/support`):

- **Actors.** The setup project (`actors.setup.ts`) becomes each of the five
  actors once, through the actor switcher, and keeps the session cookie. A
  file or a test says who it is with `test.use({ actor: "member" })`; the
  admin is the default.
- **Data.** The tests run on the standard seed, whose records, ids and
  values are the same in every VM (`Demo.Generator` draws them in a fixed
  order), so tests name them (`support/data.ts`). A test that changes
  anything says `test.use({ writes: true })`, and the database is seeded
  again after it (under a second), so every test starts from the seed, in
  whatever order. Seeding goes through `POST /e2e/seed`, a route that exists
  in the `e2e` environment only (`e2e/server`, mounted by
  `config :demo, e2e_routes: true`), as do the one that deletes a task behind
  an open table's back and the two that make the reads of the comments fail
  and work again. There is one database, so the tests run one at a time.
- **Language.** A test chooses German through the language switcher
  (`support/locale.ts`); the choice is in the session cookie, which every
  test has to itself.
- **The table.** `support/table.ts` is the one place that knows the ids of
  the library's markup and how to wait for a read or a save
  (`aria-busy`). Tests find controls by role and name where a person would,
  and cells by id.
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
