# ash_table

An Ash extension that presents a resource to people as a table in Phoenix
LiveView. It is an interface to Ash resources in the way `ash_json_api` and
`ash_graphql` are, for humans.

Add the extension to a resource, optionally describe the table in a
`table do … end` block, and mount it with one line in the router. You write
no HEEx.

> **This is an early version.** It reads, sorts, filters, pages and edits
> cells in place, and adapts its columns and its editing to who is looking.
> Nested tables and row actions are not built yet, and the package is not on
> Hex.

## Install

Requires Elixir 1.17, Ash 3.34, `ash_phoenix` 2.3, Phoenix 1.8 and LiveView
1.2. There is no installer yet; the steps are manual.

1. Add the dependency in `mix.exs`:

   ```elixir
   {:ash_table, "~> 0.1"}
   ```

2. Register the table's JavaScript hook in `assets/js/app.js`. The hook ships
   with the library as a colocated hook; there is nothing to install from npm.

   ```js
   import {hooks as ashTableHooks} from "phoenix-colocated/ash_table"

   const liveSocket = new LiveSocket("/live", Socket, {
     hooks: {...colocatedHooks, ...ashTableHooks},
     // …
   })
   ```

3. Let Tailwind see the classes the table uses, in `assets/css/app.css`:

   ```css
   @source "../../deps/ash_table";
   ```

4. Add the DSL to the formatter in `.formatter.exs`:

   ```elixir
   import_deps: [:ash, :ash_table, …]
   ```

5. Name the layout the mounted tables are rendered in, in `config/config.exs`.
   A LiveView mounted from the router gets the root layout only; since
   Phoenix 1.8 the app layout is a function component each page calls itself,
   so the table's page has to be told which one:

   ```elixir
   config :ash_table, layout: {MyAppWeb.Layouts, :app}
   ```

   The component is called with the table as its inner block and the assigns
   `flash`, `current_scope` (nil when the socket has none) and, when the
   socket has it, `current_user`. Without this setting the tables are
   rendered bare in the root layout. One table can differ:
   `ash_table "/tasks", MyApp.Tracker.Task, layout: false`, or
   `layout: {Module, :function}`.

The table uses the Tailwind and daisyUI classes of a default new Phoenix app.

Notes on the steps:

- The hook is written into the host's build directory when the dependency is
  compiled, so `mix compile` has to run before the assets are built. The
  `assets.build` alias of a new Phoenix app already does that.
- The `@source` path is the dependency's directory relative to
  `assets/css`. For a path dependency (`{:ash_table, path: "../ash_table"}`)
  point it at that checkout's `lib` instead.

## A first table

List the extension on a resource:

```elixir
defmodule MyApp.Tracker.Task do
  use Ash.Resource,
    domain: MyApp.Tracker,
    extensions: [AshTable.Resource]

  # …
end
```

and mount it in the router:

```elixir
import AshTable.Router

scope "/", MyAppWeb do
  pipe_through :browser

  live_session :default, on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}] do
    ash_table "/tasks", MyApp.Tracker.Task
  end
end
```

`/tasks` now shows the resource's public attributes as a table, read through
its primary read action. Headers sort on click or Enter, the row under them
filters, and the arrow keys move through the cells. Nothing can be edited
until the block says so (see [Inline editing](#inline-editing)).

### Describing the table

```elixir
table do
  read_action :open        # default: the primary read action
  paginate_with :keyset    # default: offset if the action supports it, else keyset
  update_action :update    # default: none, and the table is read-only

  column :title

  column :status do
    label "State"
    sortable? false
    filterable? false
  end

  column :comment_count    # an aggregate
end
```

- With no `column`, the table shows the resource's public attributes. Once one
  `column` is declared, the table is exactly the declared columns in the
  declared order.
- Calculations and aggregates appear only when named, and are read-only. A
  calculation with a required argument cannot be a column.
- Only `public?` fields and actions can appear.
- `sortable?` can only switch sorting off. Whether a column can be sorted is
  the resource's decision; under keyset pagination, calculations and
  aggregates cannot.
- `filterable?` can only switch a column's filter off. Whether a column can
  be filtered is the resource's decision too (see [Filtering](#filtering)).

Mistakes in the block are reported when the resource is compiled. As with
every Ash extension's verifiers, they surface as compile warnings; they fail
the build under `mix compile --warnings-as-errors`.

### Page size and default sort live on the read action

They are not part of the `table` block:

```elixir
read :open do
  pagination offset?: true, default_limit: 25, countable: true
  prepare build(sort: [inserted_at: :desc])
end
```

The page size is the action's `default_limit`, or 25 when it has none, and
never above the action's `max_page_size`. A read action without pagination
loads every record.

### Filtering

Under the header is a filter row with one filter per column. A filter applies
on Enter or when its input is left; a choice applies when it is picked.
Filters combine with AND, and with the sort. Every filter runs on the server,
through the read action, as `Ash.Query.filter_input/2`; nothing is filtered in
the browser.

| Column type | Filter | Operators (the first applies when a value is simply typed) |
| --- | --- | --- |
| `:string`, `:ci_string` | text input | contains, equals, starts with, is empty |
| `:integer`, `:float`, `:decimal` | number input | equals, greater than, less than, at least, at most, is empty |
| `:date` | date input | on, before, after, is empty |
| `:datetime`, `:utc_datetime`, `:utc_datetime_usec`, `:naive_datetime` | datetime input | before, after, is empty |
| `:boolean` | choice | any, yes, no |
| an `Ash.Type.Enum`, an `:atom` with `one_of` | choice | any, or one of the values |

A NewType filters as the type it is made of. "Is empty" is offered only for a
field that can be nil.

A column has no filter when

- its type is shown as read-only text (arrays, maps, embedded resources,
  uuids, times and so on);
- the resource declares the field `filterable?: false`; with
  `filterable?: :simple_equality` only "equals" is offered;
- it is a calculation computed in Elixir, without an expression: the data
  layer cannot filter by it;
- the block says `filterable? false`.

**What a text filter matches is the resource's decision, not the table's.**
The table passes on what was typed, unchanged. So a filter on a `:string`
attribute is case-sensitive: "report" does not find "Report". A filter on a
`:ci_string` attribute is not. If people should find text whatever its case,
make the attribute a `:ci_string`.

A datetime is filtered in the same terms as it is shown: UTC, to the second.

A value that is not one of the column's type (a number with decimals in an
integer column, say) is not applied; its filter is marked as invalid and says
so. The native inputs keep most such values from being typed at all.

After each filter change the result is announced to screen readers: the
number of records when the read action is `countable`, otherwise only that the
results have changed.

### Who is reading, and what they may see and do

The table has no authorization rules of its own. It passes actor and tenant
into ordinary Ash calls, asks Ash what the person may see and do, and shows
the answer. Authorization is on by default.

**Where actor and tenant come from.** The mounted page takes them from the
socket assigns your `on_mount` hooks set: `current_scope` if it is assigned
and not nil (it must implement `Ash.Scope.ToOpts`), otherwise `current_user`
and `current_tenant`. With none of them assigned nobody is logged in, which
is fine: the table shows what the resource leaves to an anonymous visitor.
Who may open the page at all is your router's and live session's business.

The names can be changed per domain, with the extension `AshTable.Domain`:

```elixir
defmodule MyApp.Tracker do
  use Ash.Domain, extensions: [AshTable.Domain]

  table do
    scope_assign :scope                    # default :current_scope
    actor_assign :current_account          # default :current_user
    tenant_assign :current_organization    # default :current_tenant
    authorize? true                        # the default
  end
end
```

A domain without the extension behaves as one with these defaults. Add
`import_deps: [:ash_table]` to `.formatter.exs` for the options.

> **`authorize? false` removes every check.** The tables of that domain's
> resources then read and save with no policy and no field policy applied,
> whoever is asking and even when nobody is logged in: every record the read
> reaches, every column, every declared edit. Use it only for a domain whose
> tables sit behind a gate of your own, such as an admin area.

**What each restriction looks like.**

| The resource says | The table shows |
| --- | --- |
| The person may not see some **records** (a policy that filters) | Those rows are not there, and are not counted. Nothing indicates them. |
| The read is **refused outright** (a `Forbidden` error, as from an `access_type :strict` policy) | The page answers as if it did not exist: status 404 and your "not found" page. With `on_forbidden :message`, the page stays and says "You are not allowed to see these records." |
| The person can **never see a field** (a field policy that depends on the actor only) | The column is left out for that person: no header, no filter, no cells. A URL that sorts or filters by it is ignored. |
| The person sees a field on **some records only** (a field policy with a check on the record) | The column stays. Hidden cells are empty, announced as "Not available", and cannot be edited. |
| The person can **never run an update action** | The columns it saves are read-only for that person. If that is every editable column, the table offers them no editing at all. |
| The person may run an update action on **some records only** | Cells look editable. On a record the action refuses, the cell says "You are not allowed to change this." when it is saved. |

"No records" is only ever shown for a read that succeeded and found nothing.

```elixir
table do
  on_forbidden :message     # default :not_found
end
```

The 404 is the exception `AshTable.NotFoundError`, which Phoenix renders as
it renders a missing route. On a live navigation to the page LiveView makes
the browser ask for the page afresh, and a read that comes to be refused
while the page is open redirects to the page's own URL; both end at the 404.

Whether a person can never see a field, or never run an action, is asked of
Ash each time the table reads: when the page is opened, and at every sort,
filter and page change. Neither question reads a record or runs a query
(`Ash.can_see_fields/4` and `Ash.can/3`, once per update action). When who is
logged in changes, mount the page again, as a login or logout does.

**Filtering and sorting by a field that is hidden on some records** stays
possible, and gives nothing away: Ash treats a hidden value as empty in
filters and sorts. A filter by a value finds only records whose value the
person sees; "is empty" also finds every record whose value is hidden; a sort
puts the hidden ones together with the empty ones.

> **The table refusing to edit a hidden field protects the table only.** A
> field policy is about reading. When a person is not shown a field on a
> record, the table does not let them change it there either, but the update
> action itself would: the same action called through `ash_json_api`,
> `ash_graphql` or your own code accepts the field from anyone its *policy*
> allows. If a field must not be changed by people who cannot see it, say so
> in the resource: an action that does not accept the field, or a policy or
> validation on the one that does.

### The URL

Sort, filters and page are kept in the URL, under the table's id, so reload,
the back button and shared links work:

```
/tasks?task[sort]=-title&task[page]=2
/tasks?task[f][title]=report&task[f][progress][at_least]=50&task[f][due_on][is_empty]=&task[f][billable%3F]=yes
```

Filters are under `f`, by column. A filter with its column's first operator
is the value alone (`task[f][title]=report`); another operator is named
(`task[f][progress][at_least]=50`), with nothing after it when it takes no
value (`task[f][due_on][is_empty]=`); a yes-or-no choice is `yes` or `no`.
The operators are named `contains`, `equals`, `starts_with`, `is_empty`,
`greater_than`, `less_than`, `at_least`, `at_most`, `on`, `before` and
`after`. Parameters that mean nothing to the table are ignored.

The id defaults to the last part of the resource's module name, underscored;
`ash_table "/tasks", MyApp.Tracker.Task, id: "tasks"` sets another.

### Inside an existing LiveView

```heex
<AshTable.table id="tasks" resource={MyApp.Tracker.Task} scope={@current_scope} />
```

It accepts `scope`, or `actor` and `tenant`; the assign names of the domain
are for mounted tables only. An embedded table keeps its sort, filters and
page itself; pass the page's current URL as `url` to keep them in the URL.

It authorizes as its resource's domain says (`authorize?` in `AshTable.Domain`,
`true` by default); `authorize?={false}` or `authorize?={true}` on the table
itself wins. Everything in the table above holds for it, with one difference:
it cannot turn your page into a 404. A read refused outright makes it render
nothing at all, unless the resource says `on_forbidden :message`.

### Inline editing

A person changes a cell's value in place, and it is saved for that cell
alone: the table runs one of the resource's update actions with exactly one
input, the cell's field, and shows what the action returns. It adds no logic
of its own: no validation, no conversion of values, no undo.

```elixir
table do
  update_action :update            # every column this action accepts becomes editable

  column :title

  column :price do
    update_action :reprice         # this column's own action
    confirm "Change the price?"    # asked before the cell is saved
  end

  column :slug do
    update_action false            # read-only
  end
end
```

Editing is opt-in: with no `update_action`, at the table or at a column, the
table is read-only.

**A cell can be edited when all of this holds:**

- its column is an attribute, and the attribute is writable. Calculations and
  aggregates are never editable;
- an update action accepts the attribute: the column's own `update_action`,
  else the table's. The action is `public?` and needs nothing but the cell's
  value: an action with a required argument without a default cannot save a
  cell, since the argument is not on the record. (Attributes the action
  requires are no obstacle; the record has them.);
- its type has an editor:

  | Column type | Editor |
  | --- | --- |
  | `:string`, `:ci_string` | text, in a field that grows with its lines |
  | `:integer`, `:float`, `:decimal` | number input |
  | `:boolean` | toggled in place |
  | `:date` | date input |
  | `:datetime`, `:utc_datetime`, `:utc_datetime_usec`, `:naive_datetime` | datetime input, UTC, to the second |
  | an `Ash.Type.Enum`, an `:atom` with `one_of` | choice of the values, and of none when the attribute can be nil |

  Everything else (arrays, maps, embedded resources, uuids, times and so on)
  is read-only. A NewType is edited as the type it is made of;
- the field is not hidden from the person on that row by a field policy;
- the person is not someone who can never run the action (see "Who is
  reading, and what they may see and do").

Under a table-level `update_action`, the columns it cannot save are simply
read-only. A column's own `update_action` that cannot save its column is a
mistake, reported when the resource is compiled, as is `confirm` on a column
that can never be edited. When the table offers editing, the cells that
cannot be edited are marked `aria-readonly`.

**Saving.** Enter saves and keeps focus on the cell; leaving the cell (a
click elsewhere, Tab) saves too; Escape gives the edit up. A boolean is
saved when it is toggled, a choice when it is made. A value that is the one
the cell already shows runs nothing. Empty input is sent as it is: Ash's type
casting decides what it becomes, usually nil, and the action whether nil is
allowed.

On the server the record is read again by its primary key, as the person
saving, so policies and field policies apply as they did when the page was
read. Then the column's action runs through `AshPhoenix.Form`. The row is
shown from what the action returns, with the table's calculations and
aggregates loaded on it; the table's read action is not run again. The row
stays where it is even if it no longer matches the filters or the sort, until
the next change of page, sort or filter. While a save is on its way its cell
is dimmed and `aria-busy`.

A table with editable columns and calculation or aggregate columns needs a
primary read action, which is what Ash loads them through.

**When a save fails,** nothing is saved and the table shows what the action
returned:

- the cell keeps what was typed and is marked (`aria-invalid`, a ring in the
  error colour);
- the action's message is the cell's description (`aria-describedby`). It
  appears under the cell while the cell has focus or the pointer, so the row
  keeps its height, and it is announced to screen readers when it arrives;
- focus is not pulled back to the cell;
- an error that is not about the edited field is shown on the same cell: a
  validation on another field with that field's name in front, a refusal by
  a policy as "You are not allowed to change this.", a record that has been
  deleted or can no longer be read as "This record is no longer available.";
- going back to the cell and pressing Escape restores the saved value and
  clears the mark. So does saving a value the action accepts.

A person who can never run a column's action does not get this far: the
column is read-only for them, and a `save` event sent all the same is not
run. The refusal on the cell is for an action that depends on the record.

**Confirm.** A column with `confirm` asks its question in a dialog at the
moment of saving, before the action runs. Confirm saves. Cancel, or Escape,
returns to the cell, still in edit mode with what was typed.

### The keyboard

The grid is one tab stop: Tab enters and leaves it, the arrow keys move
within it. Up Arrow from the first row of records reaches the filter row and
then the header. On a header, Enter sorts. On a filter cell, Enter or F2 goes
into the filter; there the arrow keys belong to the input, Enter applies what
was typed and stays, Escape gives up what was typed and not applied and
returns to the cell, and Tab moves through the filter's controls and from the
last one out of the grid.

On a cell that can be edited:

| Key | Effect |
| --- | --- |
| Enter, F2 | Start editing; on a boolean, toggle it and save |
| A character | Start editing with it: text and numbers are replaced by what is typed; a date keeps its value and takes a digit into its first part; a choice opens at the first value starting with the character |
| Escape | While editing, give the edit up; on a cell whose save failed, restore the saved value |
| Enter, while editing | Save; focus stays on the cell. In text, Shift+Enter makes a new line |
| Tab, Shift+Tab, while editing | Save and leave the grid, forwards or backwards |
| Arrow keys, Home, End, while editing | Belong to the editor |
| Space | Nothing; reserved for row selection |

A double click starts editing too. In a choice, the menu opens at once;
Enter or a click chooses and saves, and Escape closes the menu before it
gives the edit up. A character the editor of a number does not take (a
letter, say) starts editing without replacing the number.

## Licence

MIT
