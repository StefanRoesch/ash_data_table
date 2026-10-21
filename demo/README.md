# ash_data_table demo

A Phoenix and Ash host app for `ash_data_table`, where the library's tables
are shown and tested: an issue tracker with one of everything a table has to
cope with, and a kitchen-sink resource with one attribute per built-in Ash
type.

Phoenix 1.8, LiveView 1.2.12, Ash 3.36.1 (`~> 3.36 and >= 3.36.1`, as the
library asks), `ash_postgres`, `ash_phoenix`; Tailwind and daisyUI through the
`tailwind` and `esbuild` Hex packages. npm only for the React islands
(`assets/package.json`, see [React islands](#react-islands)), no Vite; the
library itself has no npm dependency.

## Start

From the repository root, start Postgres 18.6 (loopback only, port **5477**):

```sh
docker compose up -d postgres
```

Then, in `demo/`:

```sh
mix setup        # deps, create and migrate the database, npm packages, build assets, seed
mix phx.server   # http://localhost:4478
```

- `mix setup` runs `mix assets.setup`, which runs `npm install` for
  `assets/package.json`. It needs Node 20 or later (`assets/.tool-versions`
  pins 24 for asdf; the Dockerfile uses Debian's Node, 20). Run
  `mix assets.setup` again after a change of `assets/package.json` or
  `package-lock.json`.
- `npm install`, not `npm ci`: both install what `package-lock.json` pins,
  but `npm install` touches `node_modules` only where it differs, while
  `npm ci` deletes it on every run and so breaks the esbuild watcher of a dev
  server that is running meanwhile (the browser tests' setup runs
  `mix assets.setup`).
- `mix test` runs the tests against the database `demo_test` on the same
  Postgres, in the Ecto sandbox.

### Tidewave

In development the demo has [Tidewave](https://hexdocs.pm/tidewave), an MCP
endpoint for coding agents (logs, evaluating code, SQL, documentation) at
http://127.0.0.1:4478/tidewave/mcp, over streamable HTTP. It answers this
machine only, and no other environment has it. For Claude Code:
`claude mcp add --transport http tidewave http://127.0.0.1:4478/tidewave/mcp`.

### The development check in the browser

LiveView turns its client debug on by itself on `localhost` and
`*.localhost`, unless it was turned off. So at http://localhost:4478 the
table's development check runs: each hook says on the browser console which
marker its part of the table lacks, and it walks every cell of every grid
after every patch, which makes a large page slower. `liveSocket.disableDebug()`
in the console turns it off (`assets/js/app.js` puts `liveSocket` on
`window`). At http://127.0.0.1:4478 it is off.

The demo's LiveView socket compresses its frames (`compress: true` in
`lib/demo_web/endpoint.ex`), which the library's installer leaves to the host:
see [Installation](../documentation/topics/installation.md).

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
`POSTGRES_DB` in dev, `PORT`). The defaults need no `.env`.

| What | Where |
| --- | --- |
| Demo | http://localhost:4478 |
| Postgres | `localhost:5477`, user and password `ash_data_table`, databases `demo_dev` and `demo_test` |

## Who you are: the five actors

There is no login. The switcher at the top right of every page posts to
`POST /actor`, which stores the chosen user's id in the session under
`"actor_id"`; "Nobody" removes it. `DemoWeb.Actor` (a plug and an `on_mount`
hook) turns the session into two assigns, on the conn and on the socket. They
are the names `ash_data_table` reads by default, and `Demo.Tracker` writes
them out in its `table` block (the extension `AshDataTable.Domain`):

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
What each actor may do is in
[What is private or restricted, and why](#what-is-private-or-restricted-and-why).

## The pages

Every table page is one `ash_data_table` line in `DemoWeb.Router`, rendered in
the demo's app layout (`config :ash_data_table, layout: {DemoWeb.Layouts, :app}`).
The pages marked "own LiveView" are LiveViews of the demo's that place or
attach tables themselves.

| URL | Resource | In short |
| --- | --- | --- |
| [`/tasks`](#tasks) | `Task` | one of nearly everything a table does |
| [`/projects`](#projects) | `Project` | no columns declared; embedded resources; a sensitive column |
| [`/comments`](#comments) | `Comment` | raw foreign keys; keyset pages; `on_forbidden :message` |
| [`/labels`](#labels) | `Label` | no pagination; table actions; a file upload |
| [`/bare/labels`](#barelabels) | `Label` | `layout: false` |
| [`/task_labels`](#task_labels) | `TaskLabel` | a primary key of two attributes |
| [`/specimens`](#specimens) | `Specimen` | every built-in Ash type |
| [`/deadlines`](#deadlines) | `Deadline` | a read action with a required argument |
| [`/tasks/board`](#tasksboard) | `Task`, table `:board` | a named table |
| [`/comments/compact`](#commentscompact) | `Comment`, table `:compact` | a named table with `max_lines` |
| [`/named`](#named) | `Comment`, both tables | own LiveView: two tables, one URL |
| [`/tasks/planner`](#tasksplanner) | `Task` | own LiveView: the sprint planner |
| [`/projects/sticky`](#projectssticky) | `Project` | `look: [sticky_header: true]` |
| [`/tasks/striped`](#tasksstriped) | `Task` | `look: [density: :compact, stripes: true, column_lines: true]` |
| [`/dashboard`](#dashboard) | `Project`, `Task` | own LiveView: two tables, nothing in the URL |
| [`/react/tasks`](#react-islands) | `Task` | the table of `/tasks` drawn by the React kit |

### `/tasks`

The tasks' `table` block: chosen columns in a chosen order, a relabelled
column, an aggregate, two calculations; offset pages of 25.

- **Reference cells** "Project", "Assignee" and "Reported by" show a related
  record by its name, with no sort and no filter. The first two are edited by
  choosing a record in [the picker](#the-picker); "Reported by" is read-only.
- **Arrays** "Tags" (text) and "Checks" (enum values) and the **map**
  "Repeats" are shown on one line and edited as a whole in the side panel,
  with no sort and no filter: [Editing on `/tasks`](#editing-on-tasks),
  [Maps and embedded resources](#maps-and-embedded-resources).
- **Filters of every kind**: text (`title`, `external_ref`), numbers
  (`progress`, `estimate_hours`), a date (`due_on`), datetimes
  (`completed_at`, `inserted_at`), booleans (`billable?` and the calculation
  `overdue?`), enums (`status`, `priority`), an aggregate (`comment_count`).
  None on `description` (`sortable? false` and `filterable? false`) and none
  on `headline` (computed in Elixir).
- **Inline editing** of every cell type, and **components** on four columns:
  [Editing on `/tasks`](#editing-on-tasks),
  [Components on `/tasks`](#components-on-tasks).
- **Row actions**: a box at the start of every row selects it; five row
  actions in the last column, "Actions", which also run on the selected rows;
  "New task" on the line of the table's name:
  [Row actions and create](#row-actions-and-create),
  [Selecting rows and bulk actions](#selecting-rows-and-bulk-actions).
- **The argument line** above the grid: "Search" and "Due within: Days":
  [The argument line](#the-argument-line).
- **Footer summaries** and **live updates**:
  [Footer summaries](#footer-summaries), [Live updates](#live-updates).
- Rows expand into seven relationships: [nested tables](#rows-that-expand-nested-tables).
- Each actor sees a different page: [`/tasks`, actor by actor](#tasks-actor-by-actor).

Filters to try, as the admin:

- http://localhost:4478/tasks?task[f][title]=session: text. `Session` with a
  capital finds nothing, because `title` is a `:string`
- http://localhost:4478/tasks?task[f][progress][at_least]=50&task[f][billable%3F]=yes&task[sort]=progress:
  two filters and a sort
- http://localhost:4478/tasks?task[f][due_on][is_empty]=: tasks without a
  due date
- http://localhost:4478/tasks?task[f][overdue%3F]=yes&task[f][comment_count][greater_than]=2:
  a calculation and an aggregate

### `/projects`

No column declared: the public attributes, edited in place through
`update_action :update` (Name, Description, Status, Starts on, Budget) by an
admin or a member. `label_field :name` says what a project is called in
other tables. Rows expand into "Tasks".

- "Client" (an embedded resource with an address inside it) and
  "Milestones" (an array of embedded resources) are edited in the side
  panel: [Maps and embedded resources](#maps-and-embedded-resources).
- "Budget" is sensitive: [Sensitive values](#sensitive-values).
- Four row actions: "Set status" (one input, a choice); "Set budget" (one
  sensitive input, typed hidden, which "Clear" can empty); "Destroy", which
  asks first; "Assign open tasks", a generic action that the table gives the
  row's key and that takes a person, chosen in the picker (`reference`).
  And "New project".
- For nobody the read is refused outright, and the page answers 404, as if
  it did not exist.

### `/comments`

The public attributes again, foreign keys among them: "Task ID" and
"Author ID" are the raw keys, where `/tasks` shows names.

- "Body" is edited in place by an admin and by the comment's own author;
  anyone else's save is refused on the cell.
- Keyset pagination: next and previous, no page numbers. The action counts
  (Ash's `countable` is on unless an action says otherwise), so the line
  under the table gives the number of records without a range, and a filter
  change is announced with its count.
- "Destroy" (asks first), and "New comment", whose field for the task opens
  the picker with the tasks' table, which can be searched.
- Refused outright for nobody, but declared with `on_forbidden :message`:
  nobody is told "You are not allowed to see these records."
- Live updates: [Live updates](#live-updates).

### `/labels`

No pagination: every record. `label_field :name` says what a label is called.

- "Name" and "Colour" are edited in place by an admin
  (`update_action :update`); a member and a viewer are offered no editing.
- "Destroy" (asks first) and "New label" (its colour starts with the
  attribute's default), for an admin: a member and a viewer have no actions
  column and no create button.
- Five table actions after "New label", and "Copy" in every row:
  [Table actions](#table-actions). "Import" takes a CSV file:
  [A file for an action](#a-file-for-an-action).

### `/bare/labels`

The labels mounted with `layout: false`: the heading and the table straight
in the root layout. A bare table brings no landmark, so the demo's root
layout has the `<main>` around every page, beside its header.

### `/task_labels`

A primary key of two attributes: rows are named, found and saved by both
parts together. "Note" is editable; offset pages of 25. One row action,
"Remove", a destroy that runs at one click (`confirm false`). "New task
label" has a field for the task and one for the label, each opening the
picker. Rows expand into Task and Label, with `max_depth 1`.

### `/specimens`

No columns declared: how every built-in type is shown, and the filter each
gets by default. Through `update_action :update`, every type with an editor
is editable; anyone may edit a specimen. No column names a component, so the
table's own look of every type stays visible beside `/tasks`. No row action,
so no boxes.

- The arrays "Strings" and "Integers" are edited value by value, and
  "Shades", a multiple choice, each in the side panel.
- Values made of fields, in the side panel: "An address" (an embedded
  resource), "Addresses" (an array of them, without a primary key) and "A
  typed map" (a map that declares its fields). "A map", which declares none,
  is shown from whatever it holds and is read-only; "A keyword", "A tuple"
  and "A struct" stay read-only text.
- "A union": [Unions](#unions).
- `A string` is case-sensitive, `A ci string` beside it is not:
  http://localhost:4478/specimens?specimen[f][a_ci_string]=ALPHA finds
  `Alpha`, `alpha` and `ALPHA`. The `opt_*` columns offer "is empty".

### `/deadlines`

The tasks once more, as a resource of its own over the same table, read
through an action that **requires** an argument, the day they are due by.

- Until "Due by" is given the table reads nothing and says "Fill in Due by
  to see records." "Include done?" is an argument with a default; "Tags" a
  list given value by value.
- "Due on" is edited in place: a task put off beyond the day stays in its
  row until the table reads again.
- "Assignee" is a reference cell edited through an argument: its action,
  `hand_over`, does not accept `assignee_id`; it takes the person as an
  argument and hands it to the relationship, and the cell opens the picker
  all the same.
- A row expands into its comments.

Try:

- Give a day; tick "Include done?"; "Add value" beside "Tags", type `api`,
  Enter. Empty "Due by" again.
- Change a row's "Due on" to a day after it. The row stays; press Enter on it
  again and change something else: "This record is no longer available.", as
  the action no longer returns it.
- With a day given, Enter on an "Assignee" cell opens the picker on that
  person. Choose another: the cell shows the new name. "None" takes the
  assignee away. No update action of `Deadline` accepts `assignee_id`. The
  action takes `argument :assignee, :uuid` and
  `manage_relationship(:assignee, type: :append_and_remove)`.
- As **Max Member**, on a task neither assigned to him nor reported by him:
  the cell is marked, "You are not allowed to change this."

### `/tasks/board`

A second table of the tasks, `:board`, declared in a file of its own
(`lib/demo/tracker/task/board_table.ex`, a fragment of the resource). Id
`task_board`.

- Four columns, "Title" and "State" edited in place; one row action,
  "Archive"; no "New task". The assignee is chosen in the picker, which shows
  the people's default table.
- A row expands into "Comments", which nests the compact table of the
  comments and links to its full view at `/comments/compact`, and into
  "Labels", which nests the short table of the labels (`:short`, declared in
  `label.ex`). That table is mounted nowhere, so it has no "Open in full
  view", although `/labels` exists.

### `/comments/compact`

A second table of the comments, `:compact`, in a file of its own
(`lib/demo/tracker/comment/compact_table.ex`). Id `comment_compact`.

- "Body", "Author" (the author's name, where `/comments` shows the key) and
  "Inserted at". Nothing is edited, no row action, no "New comment", rows do
  not expand.
- "Body" shows up to three lines (`max_lines 3`). "Show all", a Tab stop in
  every comment that is cut off, shows the whole comment in the row; "Show
  less" cuts it off again.
- For nobody: "You are not allowed to see these records." The named table
  says `on_forbidden :message` itself: it takes nothing over from the default
  table.

### `/named`

Own LiveView (`DemoWeb.NamedLive`) with the default and the compact table of
the comments, placed with `<AshDataTable.table>` and no `id`.

- Sort both: the address holds `comment[sort]=…` and
  `comment_compact[sort]=…` side by side.
- The comments have live updates, so the two tables follow each other:
  change a comment's text in the first and the row changes in the second;
  create one in the first and the second says "There are new or changed
  records." with "Read again"; delete one and its row goes from both.

### `/tasks/planner`

The sprint planner, own LiveView (`DemoWeb.PlannerLive`), with the table of
`/tasks` attached under two cards (`AshDataTable.attach/4` with `notify`).
In English and German (its texts in `priv/gettext/de/LC_MESSAGES/default.po`).

- Tick rows: "Selected for the sprint" reads them back as the person
  (`AshDataTable.selected_records/2`) and says how many, the sum of their
  estimates and how many are billable. An estimate the person may not see
  counts as unknown ("0 h + 2 unknown" for Max Member on tasks not his).
- Change the estimate of a selected row: the card follows.
- "Last changes" lists the last five saves, creates, deletes and actions on
  the selection, from the events' details, as a polite live region.
- "Clear selection" is the command `AshDataTable.clear_selection/2`.

### `/projects/sticky`

The projects with `look: [sticky_header: true]`, id `project-sticky`. The
table has a height of its own and only its rows scroll inside it, both ways,
with its header and filter row at its top. Expand a project, open "Tasks"
and a task's "Comments": each nested table is about ten rows high, scrolls
by itself and keeps its own header in view, under the projects' header.

### `/tasks/striped`

The tasks with `look: [density: :compact, stripes: true, column_lines: true]`,
id `task-striped`: compact rows, faint stripes over the records only, lines
between the columns. `/tasks` keeps the default look.

### `/dashboard`

Own LiveView (`DemoWeb.DashboardLive`) with the projects and the tasks placed
with `<AshDataTable.table … />`, each given the actor and the tenant as
attributes.

- Each table sorts, filters, pages, saves and runs its actions by itself, and
  nothing of it is in the URL.
- Each renders the line above it, its name and its create button;
  `heading={2}` makes the name an `h2` of the page, which labels its section.
- As nobody, the projects' read is refused and that table renders nothing at
  all, its name included.

### React islands

http://localhost:4478/react/tasks (linked from the front page) is the table
of `/tasks` drawn with the demo's React kit (`DemoWeb.ReactKit`, stage 8 of
the refactor, `docs/architecture/react-kit-design.md`; the guide
`documentation/topics/react-kit.md`), attached to a LiveView of the demo's
own (`DemoWeb.ReactTasksLive`).

- Every part is a React island drawn with shadcn/ui: the heading line (name,
  "Columns", argument line, create, table actions), grid, line above the
  grid, live region, pagination, what a table limited to related records
  says, the messages in place of the rows, the question, the action panel
  and the picker (`AshHeading`, `AshGrid`, `AshSelectionLine`, `AshStatus`,
  `AshPagination`, `AshRelated`, `AshMessage`, `AshConfirm`, `AshPanel`,
  `AshPicker`), on the table's own hooks (`mountGrid`, `mountPagination`,
  `mountPanel`, `mountPicker`). Nested tables alike.
- The panel and the picker are native `<dialog>`s (or regions in the page),
  drawn closed too, with the places what opens in them is moved into. A file
  field hands its files to LiveView's own file input beside the island
  (`uploadTo`).
- Every part an island draws is replaceable by name
  (`reactKit({Cell: …})`, `assets/islands/table/parts.tsx`). Only the root,
  an element that draws nothing to be seen, is the default kit's.
- `DemoWeb.ReactKit.Props` picks what each island is given, plain data only
  (`test/demo_web/react_kit_test.exs` encodes it to JSON;
  `test/demo_web/kits/react_kit_case_test.exs` runs `AshDataTable.KitCase`
  with `client: true` over it). The islands are in `assets/islands/table/`,
  their look in `assets/css/react_kit.css`.
- `e2e/react.spec.ts` checks what only the React kit has. The browser tests'
  project `react` runs the whole suite with every table drawn by it
  (`e2e/playwright.config.ts`, `x-demo-kit`, `DemoWeb.E2E.ChosenKit`),
  `e2e/kit_check.spec.ts` among it, which drives `KitCase`'s states in the
  browser and checks what was drawn.

How it is put together:

- **live_react 2.0** (`mix.exs`) renders a component with
  `<LiveReact.react name="AshGrid" rows={@rows} grid={…} />`: every other
  attribute becomes a prop, and a stream goes as a stream.
  `config :live_react, ssr: false`: the component renders in the browser
  only, so there is no Node at runtime, and the first render of a page shows
  nothing in its place until the socket connects. `assets/js/app.js` adds
  the React kit's `reactKitHooks(islands)` to the LiveSocket's hooks:
  live_react's `getHooks`, which commits each update at once and destroys the
  table's hooks in an island as the island goes.
- **npm** in `assets/` only: `react`, `react-dom` and the packages the shadcn
  sources import (`@radix-ui/react-slot`, `class-variance-authority`, `clsx`,
  `tailwind-merge`). live_react's own JS is no npm package here: esbuild
  finds it in `deps/`, as it finds `phoenix_live_view`.
- **esbuild** (the Hex package, `config/config.exs`): `--jsx=automatic`, and
  `NODE_PATH` holds `deps/`, the build's colocated hooks and
  `assets/node_modules`, where live_react's files in `deps/` find `react`.
- **The folder is `assets/islands/`**, the components by name in
  `islands/index.ts`. Not `assets/react/`: `assets/tsconfig.json` has
  `baseUrl: "."`, which esbuild honours, so that folder would be what
  `import … from "react"` finds.
- **Tailwind** (the Hex package) scans the TSX: `@source "../islands"` in
  `assets/css/app.css`.
- **shadcn/ui** components are copied in as source (`islands/ui/`, from
  shadcn's new-york style for Tailwind 4), not with its CLI, which rewrites
  the CSS entry. A new component brings its Radix package into
  `assets/package.json`.
- **shadcn beside daisyUI**, in `assets/css/app.css`: shadcn's colour names
  (`background`, `foreground`, `muted`, `border`, `input`, `ring`, …) are
  theme colours pointing at variables renamed `--sh-*`, set only under the
  class `shadcn`; outside it nothing of daisyUI changes. `primary`,
  `secondary` and `accent`, names of both, are shadcn's inside `.shadcn`
  only. The rename is needed: daisyUI's `--border` is a width, shadcn's a
  colour. Dark mode follows daisyUI's (`data-theme="dark"`, or the system's
  while no theme is chosen). A Radix primitive that portals its content to
  `document.body` (Dialog, Popover, Select, Tooltip) leaves the scope: its
  portalled element carries `shadcn` itself.
- **The library's JS** by its package name: the demo's test hook
  (`assets/js/mounted_grid.js`) imports `mountGrid` from `"ash_data_table"`,
  which `assets/package.json` links to the repository root (`"file:../.."`);
  a host has it in `deps/`.

All pages load one bundle, React included (+81 KB of JS gzipped).

## What to try, by feature

### Editing on `/tasks`

Enter or Space on a cell starts editing, as does typing or a double click;
Enter, Tab or leaving the cell saves, Escape gives up. After a save the row is
shown from the action's result: `headline` follows a new title, `overdue?` a
new due date, without the page being read again.

| Column | Edited as | Through |
| --- | --- | --- |
| `title`, `description` | text; Shift+Enter makes a new line | the table's `update_action :update` |
| `status` ("State") | a choice | `update`, after its `confirm`: "Change the state of this task?" |
| `priority` | a choice | its own action, `reprioritise` |
| `progress` | a slider with the number beside it (its column's component). It saves when let go and stays open; a step with Up or Down Arrow is saved by Enter or by leaving | its own action, `set_progress`, which also starts a task still to do: its state changes in the same row |
| `estimate_hours` | a number with its unit beside it (the demo's own component) | `update`. Empty it to see nil saved |
| `billable?` | a boolean: Enter toggles and saves | `update` |
| `due_on`, `completed_at` | a date, a datetime | `update` |
| `tags` | an array of text, in the side panel: Enter, a double click or a typed key opens it with one field per tag, each with a button that takes it away, and "Add value" under them. "Save" saves the list; Escape and "Cancel" give it up, and focus is back on the cell | `update`, with the whole list. At most five tags, of two to twenty characters each |
| `checks` | an array of enum values, as multiple choice, in the side panel: a box per value, Space ticks, Tab goes from box to box, "Save" saves | `update`, with the ticked values |
| `project` | a related record, chosen in the picker: Enter opens the projects' own table in a dialog at the right edge; a row is selected and "Choose" takes it | `update`, with `project_id` alone, after its `confirm`: "Move this task to another project?". A task must have a project: the picker has no "None" |
| `assignee` | a related record, chosen in the picker from the people's table | `update`, with `assignee_id` alone. "None" takes the assignee off |
| `reporter` ("Reported by") | read-only | no update action accepts `reporter_id` |
| `external_ref` | read-only | `update` accepts it; the column says `update_action false` |
| `overdue?`, `comment_count`, `headline`, `inserted_at` | read-only | a calculation, an aggregate, and an attribute no action accepts |

`reassign`, which has a required argument, cannot be behind a column: naming
it as a column's `update_action` is reported when the resource is compiled.
It is a row action instead, whose panel asks for the reason.

Saves that fail:

- As anyone: a `title` shorter than 3 characters, or an estimate below 0: the
  action's message in the cell, under the value (the row grows), and the cell
  keeps what was typed. Escape restores the saved value.
- A tag of one character, or a sixth tag: refused with the action's message
  ("Tags 2: length must be greater than or equal to 2", "must have 5 or fewer
  items"); the panel stays open with the list as typed, the message at the
  field and the refused tag marked.
- Progress of a "Done" task below 100: refused ("must be 100 when the task
  is done"), the slider closes and the cell is marked.
- State "Done" on a task with progress below 100: refused because of another
  field, shown on the state cell as "Progress: must be 100 when the task is
  done".
- As the member, on a task they neither reported nor are assigned to: an edit
  is refused on the cell, "You are not allowed to change this."; a chosen
  assignee shows the chosen name, marked, with the same message. Their own
  tasks they can change. Where `estimate_hours` is hidden from them, its cell
  cannot be edited.
- As the viewer: nothing; the table offers no editing.

### The picker

As Ada Admin, on `/tasks`:

- Enter on an "Assignee" cell: the people's table in a dialog at the right
  edge, with the row of the task's assignee selected and its radio button
  focused. Down Arrow (the radio group's own key), then "Choose"; or Enter on
  a row's radio button; or a double click on a row. Focus is back on the
  cell.
- "None" takes the assignee off. Escape and "Cancel" change nothing.
- Shift+Tab from the rows reaches the filters of the people's table: type a
  name, Enter. Escape there gives up what was typed; Escape anywhere else
  closes the picker.
- Enter on a "Project" cell, choose another project: "Move this task to
  another project?" is asked on top of the picker.
- "Reported by" does not open: no action accepts its key.
- As Olga Outsider, the pickers offer Globex's people and projects.

### Maps and embedded resources

A value made of fields is shown on one line, `field: value, field: value`,
and edited in the side panel: Enter or a double click on its cell.

| Where | What it is | In the panel |
| --- | --- | --- |
| `/projects`, "Client" | an embedded resource, `Demo.Tracker.Client`, with another inside it, `Demo.Tracker.Address`; its private attribute is never shown | a group "Client" with Name \*, Email, Key account? and, in it, a group "Address" with Street \*, City \* and Postcode |
| `/projects`, "Milestones" | an array of embedded resources, `Demo.Tracker.Milestone`, with a generated primary key, not shown | a group per milestone, "Milestones 1", "Milestones 2", each with Title \*, Due on and Reached?, a button that takes it away, and "Add value" |
| `/tasks`, "Repeats" | a map that declares its fields (`recurrence`): every, unit, until. Its column asks "Change how often this task comes round?" | a group "Repeats" with Every \* (a number), Unit \* (a choice) and Until (a date) |
| `/specimens` | "An address", "Addresses", "A typed map", and "A map", which is read-only | as above |

As Ada Admin:

- `/projects`: Enter on the "Client" of "Customer portal"; focus is in
  "Name". Change the city, "Save": the cell shows the new value and has the
  focus again. Open it again and "Save" at once: nothing is saved.
- Empty "Name", or type `nobody` into "Email", and "Save": "is required" and
  "must be an email address" at the fields; the panel stays open with
  everything else as typed.
- The button beside "Address" ("Remove Address"): the address is gone and
  "Add value" stands in its place. "Save": the client has no address.
- The "Client" of "Data warehouse" is empty: the panel has "Add value" alone.
  Add it, give a name, save.
- "Milestones" of "Internal tools": change a title, take the second away,
  "Add value" and fill it in, save. Empty a title and save: the message is at
  that milestone's "Title".
- "New project": add the client, its address and a milestone, and create.
- `/tasks`: "Repeats" of the second row ("Every: 4, Unit: Week"). Change
  "Every", "Save": the column's question is asked; Cancel comes back to the
  panel. "Every" 0: "must be greater than or equal to 1". "Save" without a
  change asks nothing.
- As Max Member, "Repeats" on a task not his: "You are not allowed to change
  this." above the fields. As Vera Viewer nothing opens.
- In German: "Wiederholung", "Alle: 4, Einheit: Woche", "Speichern".

### Unions

"A union" on `/specimens` is a number, a text, a shade or an address (an
embedded resource). Its cell shows the value and nothing of the kind: `969`,
`chore`, `Light`, `Street: Unionsweg 559, City: Leipzig, Primary?: No`.

- Enter on the first row's "A union": the side panel has "Kind", saying
  "Number" and focused, and under it "Number" with 969.
- Choose "Text" under "Kind": the number goes and an empty text field is
  there. "Address": the fields of an address. Nothing is saved yet; Escape
  leaves the cell as it was.
- `-3` in "Number", "Save": "must be greater than or equal to 0" at the
  number. "Address" with "Street" empty, save: "is required" at "Street".
- The empty entry of "Kind", save: the cell is empty, and the panel then
  opens without a kind.
- Keyboard alone: Enter on the cell, Down Arrow for the next kind, Tab into
  its field, type, Tab to "Save", Enter.
- In German: "Art", with "Zahl", "Text", "Farbton" and "Adresse".

### Components on `/tasks`

Four columns name a `component`, a module that says how their cells look and
what they are edited with. They are saved through the same actions, sorted
and filtered as before, and hidden from the same people.

| Column | Component | Shows | Edits |
| --- | --- | --- | --- |
| `status` ("State"), `priority` | `AshDataTable.Components.Badge`, shipped | the value's label in a badge | with the table's own menu |
| `progress` | `DemoWeb.Cells.Progress`, which takes its two parts from the shipped `AshDataTable.Components.Progress` and `AshDataTable.Components.Slider` | a bar with the number beside it | with a slider |
| `estimate_hours` | `DemoWeb.Cells.Hours`, the demo's own (`lib/demo_web/components/cells/hours.ex`) | the number with "h" | in a number input with "h" beside it |

- "Set progress" and "New task" have the slider and the hours input as
  fields of their panel. There a change saves nothing: it goes with the form.
- As Max Member, estimates of tasks not his say "Not available": the
  component is not asked to show a hidden value.
- `Demo.Tracker.Task` names `DemoWeb.Cells.Progress`, a module of the web
  layer, without depending on it: `mix xref graph --source
  lib/demo/tracker/task.ex` lists no file of `lib/demo_web`.

### Row actions and create

A button in a row's last column runs an update or destroy action on that
record; the button on the line of a table's name creates one. An action with
inputs first opens the action panel at the right edge of the window. Each
page's actions are listed under [The pages](#the-pages); `/tasks` has:

- "Archive": no inputs, runs at once.
- "Reassign": the assignee (chosen in the picker) and a required reason, in
  the panel.
- "Set progress": one number, with the task's progress in it.
- "Destroy": asks "Delete this task? This cannot be undone."
- "Set labels": the task's labels, any number chosen in the picker.
- "New task": thirteen fields, among them "Project" and "Assignee", each with
  a button that opens the picker, "Tags" as a list of values and "Checks" as
  a multiple choice.

On `/tasks`:

- "Archive": the row's "State" changes at once, and the row stays where it
  is.
- "Reassign": the panel is headed "Reassign:" and the task's title. A reason
  of two characters: the action's message at the field. "Run" with the reason
  empty: "is required", and the panel stays open.
- "Destroy": Cancel changes nothing; Confirm, in the error colour, takes the
  row away, and the range under the table counts one less.
- "New task": give a title, "Choose" under "Project" and choose in the
  picker, which opens on top of the panel; the title is still there. The task
  is the first row of the page, whatever the sort, until you sort, filter or
  change page.
- "Set labels": the panel lists the task's labels under "Labels", each with
  a "✕" that takes it out of the list. "Choose" opens the labels' table on
  top of the panel, a box in every row, the task's labels ticked; tick
  another, "Choose", and it is in the list. Nothing is saved until "Run". The
  action takes `argument :labels, {:array, :uuid}` and hands it to
  `manage_relationship(:labels, type: :append_and_remove)`: these labels and
  no others.
- As **Max Member**, "Archive" a task neither assigned to him nor reported
  by him: the row's last cell is marked, "You are not allowed to do this.";
  Escape on its button clears it. His "New task" has no "External ref".
  "Set labels" on such a task shows its labels, and "Run" is refused in the
  panel.
- Keyboard: each action button is a Tab stop at the end of its row; Enter or
  Space uses it.

What each actor has:

| Actor | Row actions | Create |
| --- | --- | --- |
| admin | every button on every table, and each runs | every "New …" button |
| member | on `/tasks` and `/comments` the buttons are on every row, and a record not theirs refuses when the action runs; "Set status" and "Set budget", and no "Destroy" and no "Assign open tasks", on `/projects`; "Remove" on `/task_labels`; no actions column on `/labels` | "New task", "New comment" and "New task label"; no "New project" and no "New label" |
| viewer | no actions column on any table | no create button |
| outsider | as the member, on Globex's records | as the member; the records are Globex's |
| nobody | none | none |

### Table actions

A table action runs on the table as a whole: a generic action of the
resource, named with `action` like a row action. Its button is on the line
of the table's name, after the create button. `/labels` has five, and one
generic action in the rows.

| On `/labels` | The action | Its button |
| --- | --- | --- |
| "Count unused" | no argument, returns a number | runs at once; the table says "Count unused: 0" above the grid |
| "Recolour" | two required arguments, returns how many labels it changed | opens the panel with "From" and "To" |
| "Remove unused" | no argument, returns nothing, declared with `confirm` | asks "Delete every label that no task carries?", then says "Remove unused: done" |
| "Merge" | a label's key and a list of such keys (`reference :into, …` and `reference :labels, …` in the block), returns how many labels it deleted | opens the panel with "Into" and "Labels": each says what is chosen and has "Choose", which opens the picker with the labels |
| "Import" | one required argument that takes a file (`:file`), returns how many labels it made | opens the panel with a file input, "File" |
| "Copy", in every row | takes the label's key (`record_argument :label_id`) and a name | opens the panel with "Name" alone; the table gives the key |

As **Ada Admin**:

- "Count unused": "Count unused: 0" (in the seed every label is on some
  task). Make one with "New label" and count again: 1.
- "Remove unused": Cancel changes nothing; Confirm deletes that label, and
  the table reads again.
- "Recolour": `red` in "From", "Run": the action's message at the field.
  With a label's colour and `#123456`, the table says how many labels it
  changed, and shows them.
- "Merge": one label for "Into", two others for "Labels", "Run": "Merge: 2",
  and every task that carried one of the two carries the first. No key is
  typed anywhere.
- "Copy" on a row: the panel is headed "Copy:" and the label's name. Another
  label's name is refused at the field, "has already been taken"; a new name
  makes a label of the same colour.
- As **Max Member** or **Vera Viewer**: "Count unused" alone, and no "Copy".
  The actions that change labels are for admins.
- As **Olga Outsider**: the buttons her role in Globex has, and every action
  counts and changes Globex's labels alone.
- On `/tasks`, expand a row and open "Labels": the five buttons are on that
  line, after "Labels". The action is not told which task the line is under,
  so "Count unused" still counts the labels of the whole organization.
- Keyboard: Tab reaches the buttons on the heading line; on a task's
  "Labels" line they are Tab stops after the line's button.
- In German: "Unbenutzte zählen", "Umfärben", "Unbenutzte entfernen",
  "Importieren", "Kopieren".

### A file for an action

"Import" on `/labels` takes a CSV with a label on each line: its name and,
after a comma, its colour (`#rrggbb`), which may be left out. The `table`
block limits the upload to one `.csv` file of 100 kB. As **Ada Admin**:

- Save `zebra,#00aa00` and `yak` as `labels.csv`. "Import", choose it, "Run":
  "Import: 2", and the labels are in the table.
- Change the second line to `yak,red`, import again: the panel stays open
  with "line 2: colour must match the pattern …" at "File", and no label was
  made. The file input is empty again (a file is given once): choose a
  corrected file and "Run".
- "Run" without a file: "is required" at "File".
- A file over 100 kB: "The file is too large. The limit is 100 kB." at once,
  and "Run" runs nothing. A file that is no `.csv` is not offered by the file
  dialog, and refused if given all the same: "This type of file is not
  accepted."
- As **Max Member**: no "Import".
- In German: "Importieren", "Datei", "Die Datei ist zu groß. …".

### Selecting rows and bulk actions

A table with a row action has a box at the start of every row and one in its
header. A line above the grid counts the selected rows and has a button per
action that runs on several rows: the table's row actions, unless one says
`bulk? false`.

| Table | For the selected rows | Kept to one row |
| --- | --- | --- |
| `/tasks` | "Archive", "Reassign", "Set progress", "Destroy", "Set labels" | |
| `/projects` | "Set status", "Set budget", "Assign open tasks" | "Destroy" (`bulk? false`) |
| `/comments` | "Destroy" | |
| `/labels` | "Destroy" | "Copy" (`bulk? false`: a name can be given to one label only) |
| `/task_labels` | "Remove", which asks here though not in a row | |
| `/specimens` | no boxes: the table has no row action | |

On `/tasks`:

- **All rows succeed.** As Ada Admin, tick three boxes, "Archive": "Run
  “Archive” on 3 records?"; Confirm: "Archive: 3 done." above the grid.
- **Some refused by a policy.** As Max Member, tick the header box,
  "Archive". He may change the tasks he is assigned to or reported: "Archive:
  … done, … not done.", "You are not allowed to do this. (…)", and the
  refused rows stay selected.
- **Some refused by a validation.** As Ada Admin, select a "Done" task and
  one that is not, "Set progress". The panel asks once, empty: there is no
  one task to take it from. 50: "Set progress: 1 done, 1 not done.",
  "Progress: must be 100 when the task is done (1)".
- **An action with inputs.** Select two, "Reassign": the panel is headed
  "Reassign: 2 records". A two-character reason is refused at the field
  before anything runs; with a reason, "Run" asks "Run “Reassign” on 2
  records?" and both get it. "Assignee ID" left empty unassigns both: an
  empty field is an empty value.
- **A question of its own.** "Destroy" asks "Delete this task? This cannot
  be undone. 3 records are selected."
- **Related records for all.** Select two, "Set labels": headed "Set labels:
  2 records", no label listed (no one task to take them from). Choose a
  label, "Run": both carry that label and no other.
- **All that match.** The header box: "25 selected", and "Select all 320
  that match". Use it, then filter "Title" by `email`: the selection is given
  up, made under other filters. Sorting and paging keep it.
- **Keyboard.** Space on a row's box selects the row. The line's buttons are
  Tab stops before "Skip table".
- **A nested table has its own.** Expand a task, open "Comments", tick two,
  "Destroy" on the line above them. The tasks around them are not selected.
- As **Vera Viewer** there are no boxes: she can run no action.

### The argument line

A table whose read action takes arguments, or whose columns ask for the
arguments of their calculations, has a line of inputs above its grid.

- `/tasks`: "Search", an argument of the read action that may be left
  empty, finds tasks by a text in their title or description. Type `login`,
  Enter or leave: the rows, the count and the address follow
  (`/tasks?task[a][search]=login`); reload, or send the address to yourself
  as another actor. Nothing is sent while you type.
- `/tasks`: "Due within 7 days" and "Due within" are one calculation,
  `due_within?`, twice: `arguments days: 7` fixes the first; `ask :days,
  default: 30` asks for the second, named with `as :due_within`. Set "Due
  within: Days" to `365`: the second column follows, the first not. Sort by
  either, and filter "Due within" "Yes" and "Due within 7 days" "No" at once.
- `/tasks`: `-1` in "Due within: Days". The argument has `min: 0`: the input
  is marked, "must be greater than or equal to 0", and the rows stay.
- `/deadlines`: see [`/deadlines`](#deadlines).
- `/projects`: expand a project, open "Tasks": the nested table has the
  tasks' line, and what is typed there narrows that table alone, with nothing
  in the address.
- `/comments`: "New comment", then "Choose" beside "Task": the tasks to
  choose from can be searched.

### Rows that expand: nested tables

The mark at the start of a row expands it into one line per relationship; a
line opens the related records' own table inside the row, with its own sort,
filters, pages and editing. Nothing of it is in the URL.

| Table | A row expands into | Declared how |
| --- | --- | --- |
| `/tasks` | Comments (has-many, keyset pages), First comment and Newest comment (has-ones that each pick one of many by their own sort; the first sorts against the comments' read action), Labels (many-to-many, not paginated), Project, Assignee and "Reported by" (belongs-tos: a table of one row) | seven `relationship` lines in the `table` block, two relabelled; `max_depth` is the default, 3 |
| `/projects` | Tasks (has-many, offset pages of 25) | nothing: every public relationship whose destination has a table |
| `/comments` | Task, Author | nothing |
| `/labels` | Tasks (many-to-many, offset pages) | nothing |
| `/task_labels` | Task, Label, from a row with a key of two attributes | nothing; `max_depth 1`: the nested task has no expanders |

`User` has a table and no page: it is seen nested (assignee or reporter of a
task, author of a comment) and in the picker, where a task's assignee is
chosen from it. Its block says `max_depth 0`,
so a person's row never expands, though their assigned and reported tasks
would be offered. Its last column, "Assigned hours", adds up the estimates of
a person's tasks, which a field policy protects; the aggregate has a field
policy of its own (admins), because Ash does not apply the tasks' one to it.

To try:

- `/tasks`: expand a row, open "Comments" and "Project"; in the project's
  row expand again and open "Tasks": three levels, and at the third the rows
  have no expander. Task → Comments → Task → Comments ends the same way.
- `/projects`: expand "Mobile app", open its tasks. Sort, filter, go to
  their second page, edit a title: the projects around them and the URL
  stay as they are.
- `/tasks` as Ada Admin: under a task, edit a comment's body, a label's
  colour and the project's name: a nested table edits what its own page
  edits. Under "Assignee" and "Reported by" no cell opens: the people's
  table, the demo's one read-only table, names no `update_action`.
- Keyboard: Tab reaches a row's expander after its box; Enter opens and
  closes it. Tab goes on to each line's button, Enter opens the line, Tab
  goes into its nested table, then to the next line and row. "Skip table
  Comments" jumps past a nested table.
- Create in a nested table, as Ada Admin or Max Member: under a task, open
  "Comments", "New comment" on the line. The panel asks for the body alone;
  the task is the row above. The comment is the nested table's first row,
  and the task's "Comments" cell shows the old count until the page is read
  again. On `/projects`, a project's "Tasks" line has "New task", without
  "Project ID". "Labels", "Project" and the other lines have no such button:
  a nested table creates only under a has-many whose create action takes the
  joining key. The create button is a Tab stop after the line's button.
- As **Vera Viewer**: no "Assignee" and "Reported by" lines under a task, no
  "Author" under a comment (her read of people is refused outright), and the
  tasks under a project have no editors.
- As **Max Member**: the tasks under a project have no "External ref", and
  "Estimate hours" is "Not available" except on his own tasks. Filter them
  by "Estimate hours" greater than 10: the total under the nested table goes
  away while the filter is set (see the README's "Nested tables").
- As **Olga Outsider**: everything nested is Globex's.

### The full view of a nested table

A nested table's last row is a link, "Open in full view", to the page of the
destination's own table, limited to the same records: from a task's
comments to `/comments?comment[of][task][comments]=THE-TASK'S-ID`, under a
heading naming the task ("…: Comments") with "Show all records" beside it.
There the table keeps its state in the address.

The link is there where the router mounts the destination: comments, labels,
projects, tasks and task labels. Not for people ("Assignee", "Reported by",
"Author"): `User` is left unmounted as the example.

- Open the tasks of "Mobile app" from `/projects` in the full view, sort and
  page them, reload, and send the address to yourself as another actor.
- Change the key in the address: "This record is no longer available.", and
  no record is named. Change `task` to `nothing`: the plain table.
- Go back with the browser: the page you came from, with its sort and page,
  and its rows closed again.

### Footer summaries

Under the last row of `/tasks`: the average progress, the sum of the
estimates, the latest due date and the number of completed tasks, each over
every task that matches, not only the page (`summary` on four columns of
`lib/demo/tracker/task.ex`). Max Member sees the estimate of his own tasks
only, and has "Sum –" under that column. The tasks nested under a project end
with the same row.

### Live updates

The tasks and the comments have `live? true` in their `table` blocks and
`pub_sub Demo.PubSub` in the domain's (`lib/demo/tracker.ex`). Open `/tasks`
in two windows, one private, as Ada Admin and as Max Member. Change a title
as Ada: Max sees it without a reload. Create a task as Ada: Max's table says
"There are new or changed records." and offers "Read again". `/named` shows
the same between two tables of the comments in one window. Projects and labels announce
nothing; their tables stay as read.

### Sensitive values

`Project.budget` is public and `sensitive?`. Sensitive is not hidden, so it
is a column, its cells masked: `••••••` and a "Show" button. On `/projects`
as Max Member, "Show" on a row (or Shift+Enter on the cell), then click
elsewhere: the number is gone again. Enter on the cell opens an editor that
hides what is typed; left empty it saves nothing, and "Clear" beside it (Tab,
then Enter) empties the budget. "Set budget" has the same button in its
panel. As Vera Viewer the column is not there: a field policy keeps the
budget to admins and members.

### `/tasks`, actor by actor

Switch the actor at the top right and the same page changes:

| Actor | Rows | Columns | Editing | Row actions and "New task" |
| --- | --- | --- | --- | --- |
| admin | Acme's 320 tasks | all 17, `External ref` among them | every editable column, on every task | five buttons on every row, and each runs; "New task" |
| member | Acme's 320 tasks | 16: no `External ref`. `Estimate hours` is empty ("Not available") except on the tasks assigned to them | looks editable everywhere; a task not theirs refuses on the cell when saved | five buttons on every row; a task not theirs refuses on the actions cell or in the panel; "New task" |
| viewer | Acme's 320 tasks | 14: as the member, and no `Assignee` and no `Reported by`, as a viewer may not read people | none: no cell opens, nothing is marked read-only, no editors in the page | no actions column, no "New task" |
| outsider | Globex's 80 tasks | 16, as the member | as the member, on Globex's tasks | as the member, on Globex's tasks |
| nobody | none: "No records" | 14: no `External ref`, no `Estimate hours`, which nobody can ever see, and no `Project`, whose read is refused when nobody is logged in | none | none |

A column the actor can never see is left out of the page altogether, and
http://localhost:4478/tasks?task[sort]=external_ref or
http://localhost:4478/tasks?task[f][external_ref]=EXT shows them the plain
page. As the member, filter `Estimate hours` by "greater than 10": only their
own tasks are found; by "is empty": every task whose estimate is hidden from
them comes back too, whatever it holds.

### In your time zone

The tables show, take and filter datetimes ("Completed at" of `/tasks`) in
the browser's time zone, which `assets/js/app.js` sends when the page
connects. `DemoWeb.Zone` (an `on_mount` hook) checks it against the time zone
database (`tz`) and assigns it as `time_zone`, UTC for a zone it does not
know. Where it is not UTC, a line above the tables names it: "Times in
Europe/Berlin". To see another zone, start the browser in one
(`TZ=America/New_York chromium`, or the "Sensors" panel of Chrome's
developer tools) and open `/tasks` again. The browser tests run in UTC,
`zones.spec.ts` in Europe/Berlin.

### In German

The language switcher beside the actor switcher posts to `POST /locale`,
which stores `"en"` or `"de"` in the session under `"locale"`;
`DemoWeb.Locale` (a plug and an `on_mount` hook) puts it into the process
with `Gettext.put_locale/1`. The demo's own pages stay in English, all but
the sprint planner; the tables follow:

- `config :ash_data_table, gettext_backend: DemoWeb.Gettext` and
  `priv/gettext/de/LC_MESSAGES/ash_data_table.po`: the table's own texts, and
  the wording of `/tasks` (its name, column labels, enum labels, the question
  before a change of state, the labels of its row actions and of their
  panels' fields). For every table: the row actions, their questions, and
  what one record is called, so "New task" is "Aufgabe anlegen". The other
  tables' column labels are not translated and show as they are.
- `config :ash_data_table, translate_error: {DemoWeb.CoreComponents, :translate_error}`
  and `priv/gettext/de/LC_MESSAGES/errors.po`: the messages of the tasks'
  actions. Try a title of two characters, a progress of 150, or the state
  "Erledigt" on a task below 100.

## Seed data

`Demo.Seeds` empties the database and fills it again, so seeding can be
repeated. With the same profile it always produces the same records with the
same ids; only dates move, as they are relative to today.

```sh
mix run priv/repo/seeds.exs              # standard (also run by mix setup)
SEED=large mix run priv/repo/seeds.exs   # large
```

| Profile | Tasks | Also | Takes about |
| --- | --- | --- | --- |
| standard | 400 (Acme 320, Globex 80) | 2 organizations, 14 users, 10 projects, 16 labels, 480 comments, 36 specimens | 1 s |
| large | 50,000 (Acme 45,000, Globex 5,000) | the same, with 60,000 comments | 25 s |

Seeds write straight to the data layer (`Ash.Seed` and bulk `insert_all`):
no actor, tenant check or policy is involved.

`Demo.Generator` holds the generators, built on `Ash.Generator`. It keeps its
own random state, seeded with `Demo.Generator.reseed/1`, and draws a record's
values in the order they are written in (a map of generators would be walked
in an order that changes from one VM start to the next): that makes the data
repeatable. Tests get a small data set from the same generators:

```elixir
use DemoWeb.ConnCase, async: true

setup %{conn: conn} do
  world = world(tasks: 30)                      # Demo.Fixtures.world/1
  %{world: world, conn: log_in(conn, world.member)}
end
```

`world/1` returns the two organizations, the actors (`admin`, `member`,
`viewer`, `outsider`, and `nobody`, which is `nil`), projects, labels and
tasks. In tests the ids are fresh, not the fixed ones above.

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

- `Deadline` is a second resource over the tasks' table (`migrate? false`):
  the tasks due by a day. It has no records of its own, so the seed is the
  tasks'. Its `hand_over` takes the assignee as an argument and hands it to
  the relationship; its table edits "Assignee" through it.
- Every primary read action carries its default sort (`prepare build(sort: …)`).
- Multitenancy is Ash's attribute strategy on `organization_id`, with
  `global? true`: a read without a tenant is no error, and the policies then
  decide (nobody sees nothing).

`Task` has, on purpose:

- every relationship kind: `belongs_to` project, assignee and reporter;
  `has_many` comments; `has_one` latest_comment and first_comment (each picks
  one of many by its own sort); `many_to_many` labels
- enums with labels (`status`, `priority`), a 0 to 100 `progress`, a decimal,
  a boolean (`billable?`), a date, a datetime, long text
- two arrays: `tags`, text, at most five values of two to twenty characters,
  and `checks`, values of the enum `TaskCheck`
- a map that declares its fields: `recurrence` (every, unit, until)
- aggregates: `comment_count`, `last_commented_at`, `label_count`
- calculations: `overdue?` (an expression), `headline` (a module, computed in
  Elixir), `due_within?` (needs the argument `days`: a column twice, once
  with seven days fixed and once asking the person)
- a read action with an argument that may be left empty: `read` takes
  `search`, a text looked for in the title and the description
- update actions accepting different fields: `update` (most), `reprioritise`
  (priority; it also leaves "Reprioritised" in the private `internal_note`),
  `set_progress` (progress; it also moves a task from "To do" to "In
  progress"), `reassign` (assignee, and a required argument `reason`),
  `archive` (nothing), `set_labels` (nothing; it takes the labels as an
  argument, a list of keys, and hands them to the relationship with
  `manage_relationship`); plus `create` and `destroy`. Five are row actions
  of its table (`archive`, `reassign`, `set_progress`, `destroy`,
  `set_labels`), and `create` is its create action
- a validation that fails on another field: a task can only be `done` with
  progress 100

`Project` has two values made of fields: `client`, an embedded resource
(`Demo.Tracker.Client`: name, email, key_account?, an `address` that is an
embedded resource itself, and a private `credit_note`), and `milestones`, an
array of embedded resources (`Demo.Tracker.Milestone`: a generated primary
key, title, due_on, reached?). `create` and `update` accept both.

`Demo.KitchenSink.Specimen` has one public attribute per built-in Ash type:
string, ci_string, atom (`one_of`), integer (min and max), float, decimal,
boolean, date, time, time_usec, utc_datetime, utc_datetime_usec, datetime,
naive_datetime, duration, duration_name, uuid, uuid_v7, binary,
url_encoded_binary, map, map with fields, keyword, tuple, struct, term,
module, a date range, arrays of strings, integers and an enum, an embedded
resource and an array of it, a union (of a number, a text, an enum and that
embedded resource), a NewType and an `Ash.Type.Enum`, plus `opt_*` nil-able
variants. It has no tenant, is open to anyone, and paginates by offset (20).
Its table is edited through `update`, which accepts all of them. Left out:
`function`, `file` and `vector`, which have no sensible column here (the last
needs the pgvector extension). A file is no attribute at all: Ash stores
none. The labels' "Import" takes one as an argument.

## What is private or restricted, and why

So that the rule "only public things appear" and every authorization outcome
can be seen.

**Private fields** (never a column):

- `Task.internal_note`, `Task.updated_at`, the private calculation
  `Task.stale?`, and the relationship `Task.task_labels`
- `organization_id` on every tenant resource

`Task.inserted_at` is a timestamp made public. `Task.external_ref` is public
and an admin's alone by its field policy. `Project.budget` is public and
sensitive: [Sensitive values](#sensitive-values).

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
  member sees it on some rows and not others; the column stays, with "Not
  available" in the hidden cells. Nobody is no task's assignee, so for nobody
  the column is left out as well.

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
  applies the tasks' read policy to an aggregate but not their field
  policies, so each aggregate has a field policy of its own: admins. The
  first is a column of the people's table; the second is no column anywhere,
  and is protected for the resource's other interfaces.
- `Label`, `User`, `Organization`: only admins write.

## LiveView tests

`test/demo_web/tables/` holds LiveView tests that open the pages and click
through them as each actor. Resources made for tests only are in
`test/support/*_tables.ex`.

| File | Covers |
| --- | --- |
| `task_filter_test.exs`, `specimen_filter_test.exs` | filtering |
| `task_edit_test.exs`, `specimen_edit_test.exs` | inline editing |
| `task_authorization_test.exs`, `nobody_test.exs` | what each actor sees and may edit |
| `task_actions_test.exs`, `task_create_test.exs` | row actions; row create |
| `nested_create_test.exs` | create in a nested table |
| `actions_elsewhere_test.exs` | row actions and create on the other pages, in the dashboard and in German |
| `action_fields_test.exs` | what the action panel does with hidden fields and with every kind of failure, on a resource of `test/support/plain_tables.ex` |
| `task_bulk_test.exs`, `bulk_elsewhere_test.exs` | row selection and bulk actions; the second for the other tables, a nested table and the resources of `test/support/bulk_tables.ex` |
| `label_actions_test.exs`, `table_actions_test.exs` | table actions on `/labels`; on the resources of `test/support/action_tables.ex`: every kind of generic action, in a row, on the selected rows and in a nested table |
| `specimen_union_test.exs` | "A union" on `/specimens`: its cell, the side panel, the kinds one after the other, saving and what a refused save says |
| `union_table_test.exs` | on `test/support/union_tables.ex`: a union that cannot be empty, a tagged one, a kind with a value in it that can be left out, a union inside an embedded resource, unions that cannot be edited, and a union among the inputs of a row action, the create action and an action on the selected rows |
| `label_import_test.exs` | "Import" on `/labels`: the file input, the upload and its limits, what the action reads and what it refuses |
| `file_actions_test.exs` | on `test/support/file_tables.ex`: a file for a row action, a generic action, the create action and the selected rows, two files in one action, a file that can be left out, and what becomes of the file afterwards |
| `task_labels_action_test.exs` | "Set labels" on `/tasks`: its field, the picker for several, what a hand-made form cannot do, the action's policies, the selected rows, a nested table, German |
| `deadline_assignee_test.exs` | the "Assignee" cell of `/deadlines`, edited through an argument |
| `managed_relationships_test.exs` | on `test/support/relation_tables.ex`: an argument that adds, one that takes away, one key for a relationship of many, keys that are not the primary key, a destination whose rows are named by two attributes, a picker in pages and with an argument line, records a person may not read, and an action that is refused |
| `translation_test.exs`, `translation_settings_test.exs` | languages |
| `embedded_table_test.exs` | tables placed in a LiveView |
| `embedded_url_table_test.exs` | tables placed in a LiveView with their state in its URL (`test/support/plain_tables.ex`) |
| `task_label_table_test.exs` | the key of two attributes |
| `failed_read_test.exs`, `save_error_fields_test.exs` | a read that fails; what a failed save says about other fields (`test/support/plain_tables.ex`) |
| `uncounted_table_test.exs` | a keyset table whose action does not count (`test/support/plain_tables.ex`) |
| `domain_settings_test.exs` | the `table` block of a domain, and what a layout is told about who is asking. The demo's domains keep the defaults, so it uses two small domains of its own (`test/support/guarded_tables.ex`), mounted under `/support` in the test environment only |

## Browser tests

`demo/e2e` holds the tests that need a real browser: the keyboard and the Tab
order, focus after a patch, the editors, the panel and the picker, what each
actor's page contains, the React kit, contrast in both themes and forced
colours, and axe-core on every table in every state. Playwright and
`@axe-core/playwright`, in headless Chromium. Each spec file in `demo/e2e/`
says at its top what it tests; the helpers are in `e2e/support`.

Node is a tool for developing `ash_data_table` here: the library puts no npm
package into a host app. The browser tests' global setup also installs the
demo's own npm packages, those of its React islands (`mix assets.setup`).

```sh
docker compose up -d postgres   # in the repository root, if it is not running
cd demo && mix deps.get
cd e2e
npm ci                          # Node 24, pinned in e2e/.tool-versions
npm run browsers                # once: Playwright's Chromium
npm test
```

- `npm test` does the rest by itself in a Mix environment of its own, `e2e`
  (`config/e2e.exs`, compiled into `_build/e2e`; the first run takes a few
  minutes). A dev server on 4478 and `demo_dev` are not touched.
- Every test runs in a database transaction of its own, rolled back when it
  ends, so the files run side by side in any order. Each Playwright worker has
  its own server and database, copied from `demo_e2e_template`: worker 0 on
  port **4480** with `demo_e2e_0`, worker 1 on 4481, and so on. The servers'
  warnings and errors go to `e2e/.servers/<port>.log`.
- `E2E_WORKERS` sets the number of workers (default: half the machine's
  threads; about 0.7 GB each). `E2E_FIRST_PORT` moves the ports, and
  `E2E_NAME` puts a name into the databases', for a second working copy.
- A failed test leaves a screenshot. For its steps, run it again with
  `npm test -- editing.spec.ts:765 --trace on` and open the trace with
  `npx playwright show-trace …`.
- While writing tests, `./server.sh` keeps one server on port **4479** with
  `demo_e2e`, and `npm run test:server -- editing` runs against it.
  `npm run test:ui` starts its own servers; `npm run report` shows the last
  run's report.

## Performance

`demo/perf` repeats the prototype's measurements on the real demo: on
Postgres, with the large seed. The last committed run is in
[`perf/RESULTS.md`](perf/RESULTS.md), with the machine, the versions, the
method and what the numbers say; every repetition is in `perf/results.json`.
Nested tables were measured once, by `node nested.mjs` (the cost of opening
one, and what the server holds with 1, 10 and 50 open), in
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
  can be repeated; after a new migration it is needed, and seeds both again.
- `npm run measure` starts the demo on port **4479** (`PERF_PORT`), once on
  each database, measures in headless Chromium, and stops it. `PERF_REPS`
  sets the repetitions (15). `npm run report` writes `RESULTS.md` again from
  `results.json` and `NOTES.md`, the findings written by hand.
- To check that the scripts still run, without replacing the committed
  results: `PERF_REPS=1 PERF_RESULTS=/tmp/smoke.json node measure.mjs`.
- The server runs in the Mix environment `perf` (`config/perf.exs`): as
  production would, without code reloading, debug annotations or runtime
  checks, but started with `mix phx.server`, on plain HTTP, with assets not
  minified. `perf/server` is compiled in that environment only: the table of
  `/tasks` in pages of 100 at `/perf/tasks100`, and `Demo.Perf.Probe`, which
  collects the telemetry of LiveView, Ash and Ecto and reads the memory of
  the LiveView processes.

Measure on a machine doing nothing else; the load average is recorded with
the results.
