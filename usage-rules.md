# Rules for working with AshDataTable

AshDataTable presents an Ash resource as an editable table in Phoenix
LiveView. It is an **interface** to the resource, as `ash_json_api` is: it
runs the resource's public actions as the logged-in person, and Ash's
policies decide what that person sees and does. The guides ship with the
package in `documentation/`; the index is
[documentation/README.md](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/README.md).

## Give a resource a table

1. Install with `mix igniter.install ash_data_table`. It adds the
   dependency, the formatter entry, the hooks in `assets/js/app.js`, the
   Tailwind `@source` line and the configuration
   ([Installation](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/installation.md)
   has the same steps by hand).
2. List the extension on the resource:

   <!-- source: demo/lib/demo/tracker/project.ex -->
   ```elixir
   use Ash.Resource,
     otp_app: :demo,
     domain: Demo.Tracker,
     data_layer: AshPostgres.DataLayer,
     authorizers: [Ash.Policy.Authorizer],
     extensions: [AshDataTable.Resource],
   ```

3. Mount it with one router line, inside the `live_session` whose
   `on_mount` hooks assign `current_user` and `current_tenant` (or
   `current_scope`). Write the resource's module in full: the `scope`'s
   alias is not applied to it.

   <!-- source: demo/lib/demo_web/router.ex -->
   ```elixir
   live_session :default, on_mount: [DemoWeb.Actor, DemoWeb.Locale, DemoWeb.Zone] do
     # ...
     ash_data_table "/tasks", Demo.Tracker.Task, layout: {DemoWeb.Layouts, :tasks}
     ash_data_table "/projects", Demo.Tracker.Project
     # ...
   end
   ```

A table that is part of a page of your own is **embedded**
(`<AshDataTable.table>`, the page hears its events) or **attached**
(`AshDataTable.attach/4`, the page also gives it commands or draws its
questions, panels and pickers):
[Layout and embedding](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/layout-and-embedding.md).

## The `table` block

The extension alone gives a read-only table of the public attributes, read
through the primary read action. The `table` block says more:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
table do
  # ...
  # text
  column :title

  # enums, each shown as a badge. A change of state asks first.
  column :status do
    label "State"
    confirm "Change the state of this task?"
    component AshDataTable.Components.Badge
  end
  # ...
  # an aggregate: sortable and filterable, never editable
  column :comment_count do
    label "Comments"
  end
  # ...
end
```

- Once one `column` is declared, the table has the declared columns only.
  A calculation or aggregate is a column only when the block names it, and
  it must be `public?`.
- `update_action :update` makes editable every column whose attribute that
  action accepts. A column can name its own `update_action`, which must
  accept the attribute and need no other argument.
- `action :name` is a button in every row; `create_action :create` a button
  above the table
  ([Row actions and create](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/row-actions-and-create.md)).
  An `action` that names a generic action is a button above the table, a
  row's with `record_argument`, and one that runs once on the selected rows
  with `selection_argument` (their keys, a list; `sort_argument` gives it
  the table's sort)
  ([Table actions](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/table-actions.md)).
- Every option is in the DSL reference:
  [`AshDataTable.Resource`](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/dsls/DSL-AshDataTable.Resource.md)
  and
  [`AshDataTable.Domain`](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/dsls/DSL-AshDataTable.Domain.md).

## Change the resource, not the table

The table offers only what the resource's actions and policies allow. A
behaviour the table lacks is a change to the resource:

- **Page size and default order** are the read action's
  `pagination default_limit:` and `prepare build(sort: …)`; the block has
  neither option. A table with its own page size or order gets its own read
  action, named with `read_action`. `page_sizes` only offers a choice among
  sizes the action allows.

  <!-- source: demo/lib/demo/tracker/task.ex -->
  ```elixir
  read :open do
    filter expr(status in ^TaskStatus.open())

    pagination offset?: true,
               keyset?: true,
               countable: true,
               default_limit: 10,
               max_page_size: 100

    prepare build(sort: [due_on: :asc_nils_last, id: :asc])
  end
  ```

- **Who may see and do what** is the resource's policies and field
  policies; the block has no authorization option. A person who can never
  run an update action gets no editor; a record-dependent refusal shows
  when the cell is saved
  ([Authorization](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/authorization.md)).
- **Only `public?` actions** run behind a table, the primary read action
  included when the block names no `read_action`.
- **A cell made of two fields** is a calculation of the resource, with a
  column of it.
- **An export of the selected rows** is a generic action of the resource
  that takes their keys (`selection_argument`) and `returns Ash.Type.File`:
  the table runs it once, and the person's browser saves the file it
  returns. Write the file in the action (an Ash extension such as
  ash_csv_interchange), not in the page.

  <!-- source: demo/lib/demo/tracker/task.ex -->
  ```elixir
  action :export_csv, Ash.Type.File do
    argument :ids, {:array, :uuid}, allow_nil?: false
    argument :sort, :string

    run Demo.Tracker.Task.ExportCsv
  end
  ```
- **Rules about values** belong in validations and policies. A `confirm`
  question, the page's `before_action` veto and its `context` are no
  authorization: a hand-made event can skip a question.
- **`authorize? false`** in the domain's `table` section removes every check
  from every table of the domain, for everybody.

## The most common mistakes

- **A finding is a warning**, and a plain `mix compile` passes. In CI run
  `mix compile --force --warnings-as-errors`; `--force` makes a cached
  `_build` report it again. The line above a message names the column and
  option it is about.
- **A custom read action without a `pagination` line** loads every record.
- **A table mounted outside the `live_session` that assigns the user** reads
  as nobody: with a filtering policy, an empty table.
- **`mix format` puts parentheses into the block** until `:ash_data_table` is
  in `import_deps` of `.formatter.exs`.
- **An unstyled table, or Enter that does nothing**: the `@source` line is
  missing, the hooks are not spread into the `LiveSocket`'s `hooks`, or the
  assets were built before `mix compile`.
- **A returned file that is said as text, or "done", and not saved**: the
  generic action does not declare `returns Ash.Type.File`.

Every diagnostic, with its cause and fix:
[Mistakes at compile time](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/mistakes-at-compile-time.md).

## Sub-rules

Read the sub-rule before working on its topic:

- [`custom_components`](https://github.com/StefanRoesch/ash_data_table/blob/main/usage-rules/custom_components.md):
  a column's `component`, how its cells look or are edited.
- [`kits`](https://github.com/StefanRoesch/ash_data_table/blob/main/usage-rules/kits.md):
  how the whole table looks, a kit of your own, a kit drawn in React.
- [`controlled_mode`](https://github.com/StefanRoesch/ash_data_table/blob/main/usage-rules/controlled_mode.md):
  a page that draws the table's questions, panels and pickers itself.
- [`events_and_commands`](https://github.com/StefanRoesch/ash_data_table/blob/main/usage-rules/events_and_commands.md):
  what the page hears, page values, the veto, commands.
- [`testing`](https://github.com/StefanRoesch/ash_data_table/blob/main/usage-rules/testing.md):
  tests of a page with a table, and of a kit.
