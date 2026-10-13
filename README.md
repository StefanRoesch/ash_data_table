# ash_table

An Ash extension that presents a resource to people as a table in Phoenix
LiveView. It is an interface to Ash resources in the way `ash_json_api` and
`ash_graphql` are, for humans.

Add the extension to a resource, optionally describe the table in a
`table do … end` block, and mount it with one line in the router. You write
no HEEx.

> **This is the first version, 0.1.0, and it is not on Hex yet.** It reads,
> sorts, filters, pages and edits cells in place, adapts its columns, its
> editing and its buttons to who is looking, and speaks the host's language.
> A row expands into the tables of its related records, each of which opens
> on a page of its own, and a cell can show a related record by its label.
> A row has buttons for the update and destroy actions the table declares,
> and a button above the table creates a record; an action with inputs asks
> for them in a panel. Rows can be selected, and a row action runs on all
> the selected rows at once. A column can name a component of its own for
> how its cells look and what they are edited with; a badge, a progress bar
> and a slider are shipped. A cell that shows a related record is edited by
> choosing another one from the related resource's own table, and so are
> the records an action hands to a relationship. An embedded
> resource and a map are shown on one line and edited in the side panel,
> field by field. A union is shown as the value it holds and edited there
> too, its kind first. An action that takes a file has a file input in its
> panel. A read action's arguments, and those of a calculation
> column, are given in a line of inputs above the rows. A person can drag
> a column wider or narrower, and hide columns; both last until the page is
> reloaded.

- [Install](#install)
- [A first table](#a-first-table)
- [Describing the table](#describing-the-table): columns and defaults
- [Reading](#reading): page size and sort, [filtering](#filtering), [arguments](#arguments), [the URL](#the-url), [when a read fails](#when-a-read-fails)
- [Inline editing](#inline-editing)
- [Choosing a related record](#choosing-a-related-record)
- [Relationships an action manages](#relationships-an-action-manages)
- [Row actions and create](#row-actions-and-create)
- [Selecting rows and bulk actions](#selecting-rows-and-bulk-actions)
- [Table actions](#table-actions)
- [Files](#files)
- [Nested tables](#nested-tables)
- [Named tables](#named-tables)
- [Custom components](#custom-components)
- [Who is reading, and what they may see and do](#who-is-reading-and-what-they-may-see-and-do)
- [The keyboard](#the-keyboard)
- [Translations](#translations)
- [The layout](#the-layout)
- [Inside an existing LiveView](#inside-an-existing-liveview)
- [Things people trip over](#things-people-trip-over)

The options of the two extensions are listed in the DSL reference,
[`AshTable.Resource`](documentation/dsls/DSL-AshTable.Resource.md) and
[`AshTable.Domain`](documentation/dsls/DSL-AshTable.Domain.md).

## Guides

This README is the overview. The guides go deeper, one topic each, with
examples from the demo app and each topic's edge cases.

- Tutorial: [Get started with AshTable](documentation/tutorials/get-started-with-ash-table.md)
- [Columns and defaults](documentation/topics/columns-and-defaults.md)
- [Reading, sorting and pagination](documentation/topics/reading-sorting-and-pagination.md)
- [Filtering](documentation/topics/filtering.md)
- [Arguments](documentation/topics/arguments.md)
- [State in the URL](documentation/topics/state-in-the-url.md)
- [Inline editing](documentation/topics/inline-editing.md)
- [Confirm](documentation/topics/confirm.md)
- [Choosing a related record](documentation/topics/choosing-a-related-record.md)
- [Relationships an action manages](documentation/topics/managing-relationships.md)
- [Maps and embedded resources](documentation/topics/maps-and-embedded-resources.md)
- [Unions](documentation/topics/unions.md)
- [Row actions and create](documentation/topics/row-actions-and-create.md)
- [Selecting rows and bulk actions](documentation/topics/selecting-rows-and-bulk-actions.md)
- [Table actions](documentation/topics/table-actions.md)
- [Files](documentation/topics/files.md)
- [Nested tables](documentation/topics/nested-tables.md)
- [Named tables](documentation/topics/named-tables.md)
- [Live updates](documentation/topics/live-updates.md): `live? true` makes a table follow what other people change
- [Custom components](documentation/topics/custom-components.md)
- [Sensitive columns](documentation/topics/sensitive-columns.md)
- [Authorization](documentation/topics/authorization.md)
- [Keyboard and accessibility](documentation/topics/keyboard-and-accessibility.md)
- [Messages and translations](documentation/topics/messages-and-translations.md)
- [Layout and embedding](documentation/topics/layout-and-embedding.md)
- [Mistakes at compile time](documentation/topics/mistakes-at-compile-time.md)

## Install

Requires Elixir 1.17, Ash 3.34, `ash_phoenix` 2.3, Phoenix 1.8 and LiveView
1.2.10 or later. The table uses the Tailwind 4 and daisyUI classes of a default new
Phoenix app, and Gettext.

> An app generated by an older Phoenix 1.8 installer asks for
> `{:phoenix_live_view, "~> 1.1.0"}`. Change that to `"~> 1.2"` in its
> `mix.exs` first, or the dependencies do not resolve.

### With the installer

```sh
mix igniter.install ash_table
```

(Until the package is on Hex: `mix igniter.install ash_table@github:StefanRoesch/ash_table`,
or `ash_table@path:../ash_table` for a checkout.) With the dependency
already in `mix.exs` and [Igniter](https://hexdocs.pm/igniter) among your
dependencies, `mix ash_table.install` does the same. It takes the five steps
below, each only if it has not been taken, and tells you what is left: the
extension on a resource and a line in the router. A file that does not look
like the one of a new Phoenix 1.8 app is left as it is, and the step is
printed for you to take by hand.

### By hand

1. Add the dependency in `mix.exs`:

   ```elixir
   {:ash_table, "~> 0.1"}
   ```

2. Register the table's JavaScript hooks in `assets/js/app.js`. There are
   three, for the grid, the pagination and the action panel, and all ship
   with the library as colocated hooks behind this one import; there is
   nothing to install from npm.

   ```js
   import {hooks as ashTableHooks} from "phoenix-colocated/ash_table"

   const liveSocket = new LiveSocket("/live", Socket, {
     hooks: {...colocatedHooks, ...ashTableHooks},
     // …
   })
   ```

3. Let Tailwind see the classes the table uses, in `assets/css/app.css`:

   ```css
   @source "../../deps/ash_table/lib";
   ```

   The path is the dependency's `lib` directory, seen from `assets/css`.
   For a path dependency that is the checkout, not `deps`: with
   `{:ash_table, path: "../ash_table"}` it is
   `@source "../../../ash_table/lib";`. The installer writes the path of the
   dependency as it finds it.

4. Add the DSL to the formatter in `.formatter.exs`:

   ```elixir
   import_deps: [:ash_table, :ash, :phoenix]
   ```

5. Tell the table about your app, in `config/config.exs`:

   ```elixir
   config :ash_table,
     layout: {MyAppWeb.Layouts, :app},
     gettext_backend: MyAppWeb.Gettext,
     translate_error: {MyAppWeb.CoreComponents, :translate_error}
   ```

   All three are optional: see [The layout](#the-layout) and
   [Translations](#translations). They are read while the app runs, so
   changing them needs no recompilation of the dependency.

The hooks are written into the host's build directory when the dependency is
compiled, so `mix compile` has to run before the assets are built. The
`assets.build` alias of a new Phoenix app already does that.

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
until the block says so (see [Inline editing](#inline-editing)), and no
action is offered until the block names it (see
[Row actions and create](#row-actions-and-create)).

## Describing the table

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
  column :project          # a belongs-to: the related record's label

  column :progress do      # how its cells look and what they are edited with
    component AshTable.Components.Slider
  end

  action :archive          # a button in every row; default: none
  create_action :create    # the create button; default: none
end
```

- With no `column`, the table shows the resource's public attributes. Once one
  `column` is declared, the table is exactly the declared columns in the
  declared order.
- Calculations and aggregates appear only when named, and are read-only. A
  calculation with a required argument cannot be a column.
- A column that names a public belongs-to relationship is a reference cell:
  it shows the related record's label, the attribute that the destination's
  `table` block names with `label_field :name`. It is not sorted or
  filtered by, and is edited by
  [choosing another related record](#choosing-a-related-record) where an
  update action accepts the relationship's foreign key. The label is read as Ash loads the relationship, as
  the person, so a related record they may not read is an empty cell, and
  the column is left out for a person who can never read the destination.
- Only `public?` fields and actions can appear. That holds for every
  action a table runs, however it came by it: the primary read action it
  falls back to, the read actions behind a relationship, a reference cell,
  an aggregate column or a calculation column that holds an aggregate. See
  [Who is reading](#who-is-reading-and-what-they-may-see-and-do).
- `sortable?` can only switch sorting off. Whether a column can be sorted is
  the resource's decision; under keyset pagination, calculations and
  aggregates cannot.
- `filterable?` can only switch a column's filter off. Whether a column can
  be filtered is the resource's decision too (see [Filtering](#filtering)).

> #### Aggregates and calculations over protected fields {: .warning}
>
> Ash applies the related resource's read policy to an aggregate, and not its
> field policies; a calculation applies no policy to what it references. An
> aggregate over a field that a field policy protects, and a calculation that
> references one, need a field policy of their own on the resource that
> declares them. The compiler warns about a column that has none;
> `exposes_protected_field? true` on the column says that it is meant. See
> [Columns and defaults](documentation/topics/columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).

**Column widths** are not declared. A table lays its columns out by itself,
and the person using it can drag the edge of a column's header to make the
column narrower or wider, or do the same from the keyboard. The widths are
kept in the browser until the page is reloaded or left; nothing is stored.
See [Columns and defaults](documentation/topics/columns-and-defaults.md#column-widths).

**Hiding columns** is not declared either. The "Columns" button above a
table opens a list with a box per column; a person unticks the columns they
do not want to see. The label column always stays. A hidden column is still
read and keeps its filter and sort, which the button then says. It is a
convenience and not a permission, and it is forgotten when the page is
reloaded.
See [Columns and defaults](documentation/topics/columns-and-defaults.md#hiding-columns).

Mistakes in the block are reported when the resource is compiled. As with
every Ash extension's verifiers, they surface as compile warnings. They fail
a build under `mix compile --warnings-as-errors` only when the resource is
compiled in that run, so make it `mix compile --force --warnings-as-errors`
in CI (see [Things people trip over](#things-people-trip-over)).

## Reading

Sorting, filtering and pagination always run on the server, through the
table's read action; nothing is sorted or filtered in the browser. While a
read runs the grid is marked `aria-busy` and the previous rows stay in view,
dimmed. A read that finds nothing shows "No records".

Headers sort on a click or Enter: ascending, descending, then back to the
read action's own sort. One column at a time.

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
loads every record. Offset pagination shows page numbers, and where the page
lies in the total when the action is `countable` ("26–50 of 320"). Keyset
pagination shows previous and next only, and the total alone when the action
is `countable` ("320 records"): a keyset page does not know where it lies
among the others. A
table that needs its own page size or sort gets its own read action, named
in `read_action`. Pages of more than a hundred rows or so are slow in the
browser; there is no virtual scrolling yet.

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
field that can be nil, and never for a boolean or an enum column.

A column has no filter when

- its type is shown as read-only text (uuids, times and so on);
- it is an embedded resource or a map: Ash's interface extensions filter by
  neither, and neither is one sorted by;
- it is an array: Ash's interface extensions filter by none, and neither is
  an array sorted by;
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
number of records when the read action is `countable`, under offset and
under keyset pagination, otherwise only that the results have changed.

### Arguments

A read action that takes arguments needs nothing in the block. Every
`public?` argument of the table's read action has an input in the argument
line, above the rows, with the control of its type and its name as its
label; `argument :search do label "Search for" end` gives another label.

```elixir
read :search do
  argument :term, :string
  argument :due_by, :date, allow_nil?: false
  filter expr(due_on <= ^arg(:due_by) and (is_nil(^arg(:term)) or contains(title, ^arg(:term))))
end
```

An argument is applied as a filter is, when its input is left or Enter is
used, and is kept where the sort and the filters are. Whether it can be left
empty is the action's to say. While one the action requires is empty, the
action is not run, and the table says "Fill in Due by to see records." in
place of its rows. A value Ash refuses is shown at its input with the
action's message, and the rows stay.

A calculation with arguments is a column that says what they are: fixed in
the block, or asked from the person, who gives them in the same line.

```elixir
column :price_in do
  arguments currency: :eur
end

column :price_in do
  as :price_in_any
  ask :currency, default: :usd
end
```

`as` names the second column of a calculation, as a calculation that is
loaded twice is named in Ash. An asked argument starts with the `default`
of its `ask` (a value, or a function of the page's assigns), else with the
default it has in the resource. Each column is loaded, sorted and filtered
by with its own arguments. A nested table and a picker have the argument
line of the action they read through. See the guide,
[Arguments](documentation/topics/arguments.md).

### The URL

Sort, filters, arguments and page are kept in the URL, under the table's id,
so reload, the back button and shared links work:

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

An argument of the read action is under `a`, by name
(`task[a][search]=login`), and one a column asks for under `c`, by column
and name (`task[c][due_within][days]=14`).

One more parameter limits the table to the records related to one record,
`task[of][project][tasks]=KEY`: the [full view](#nested-tables) of a nested
table.

The id defaults to the last part of the resource's module name, underscored;
`ash_table "/tasks", MyApp.Tracker.Task, id: "tasks"` sets another.

### When a read fails

A read that is refused is a matter of authorization: see
[what each restriction looks like](#who-is-reading-and-what-they-may-see-and-do).
Any other failure takes the rows away and puts a message in their place:

- **An error the read action returned on purpose** is shown as it is: an
  error of Ash's "invalid" class, such as an argument or a filter the action
  does not accept, or one a preparation added. It names its field only if
  the person has a column for it, and it is translated like the message of a
  failed save (see [Translations](#translations)).
- **Anything else** (a database error, an exception in a preparation: Ash's
  "unknown" and "framework" classes) says only "The records could not be
  loaded." The error goes to the log, not to the person.

An exception raised by the very first read, while the page is being
mounted, is not caught: the page fails as any LiveView does that crashes in
`mount`. A keyset cursor that somebody altered in the URL shows "The
records could not be loaded."; a page number beyond the last shows "No
records", with the page numbers there are and a Previous that leads to the
last of them.

## Inline editing

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
  aggregates are never editable. A reference cell is edited through the
  foreign key of its relationship: see
  [Choosing a related record](#choosing-a-related-record);
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
  | an array of enum values | multiple choice: a list of boxes in the cell, one per value |
  | an array of any other type above | one control per value, with a button that takes the value away and one that adds a value |
  | an embedded resource, a map that declares its fields, and an array of either | not in the cell: the side panel, with a field for every field of the value (see below) |
  | a union whose every kind is one of the above, a single value or a value made of fields | not in the cell: the side panel, with the choice of the kind and that kind's value (see below) |

  Everything else (maps without fields, uuids, times and so on, arrays of
  those, and arrays of unions) is read-only. A NewType is edited as the type it is made
  of. An array is shown as its values, as plain text separated by commas,
  and saved as a whole: on Enter or on leaving its editor, with the values
  as they were typed;
- the field is not hidden from the person on that row by a field policy;
- the person is not someone who can never run the action (see "Who is
  reading, and what they may see and do").

Under a table-level `update_action`, the columns it cannot save are simply
read-only. A column's own `update_action` that cannot save its column is a
mistake, reported when the resource is compiled: an action that does not
exist or does not accept the attribute, and equally a column that no action
could make editable, because its type has no editor or its attribute is not
writable. So is `confirm` on a column that can never be edited. When the table offers editing, the cells that
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
is dimmed and `aria-busy`. A cell that is being edited is left alone when
another cell's save puts its row back, so what is typed survives; if that
edit is then given up, the cell shows what the server sent last.

A table with editable columns and calculation, aggregate or reference columns needs a
primary read action, which is what Ash loads them through. Without one the
resource is reported when it is compiled, and its table refuses to render.

Before a cell is saved the record is read again, as the person and through
the table's read action. What the update returns is loaded by Ash through
the primary read action, which therefore has to be `public?` for a table
that edits.

**When a save fails,** nothing is saved and the table shows what the action
returned:

- the cell keeps what was typed and is marked (`aria-invalid`, a ring in the
  error colour and a "!" at its end);
- the action's message is the cell's description (`aria-describedby`). It
  appears under the cell while the cell has focus or the pointer, so the row
  keeps its height, and it is announced to screen readers when it arrives;
- focus is not pulled back to the cell;
- an error that is not about the edited field is shown on the same cell: a
  validation on another field with that field's column label in front, a
  refusal by a policy as "You are not allowed to change this.", a record
  that has been deleted or can no longer be read as "This record is no
  longer available.";
- a field is only named if the person has a column for it. An error about a
  field whose column is left out for them, or which is no column of the
  table, is shown without the field's name;
- only what the action returned on purpose is shown (Ash's "invalid"
  class). A failure underneath says "This could not be saved.";
- going back to the cell and pressing Escape restores the saved value and
  clears the mark. So does saving a value the action accepts.

A person who can never run a column's action does not get this far: the
column is read-only for them, and a `save` event sent all the same is not
run. The refusal on the cell is for an action that depends on the record.

**Limits before saving.** A number's editor says the least and the most
the attribute's constraints allow (`min`, `max`, and `step`), so the arrows
stop there and assistive technology is told them; so do a number field of the
action panel and a number of the argument line. They describe and stop
nothing: a number past them is sent, and Ash's message is shown as above.
The length of text and its pattern are not put on the input. See
[Inline editing](documentation/topics/inline-editing.md#limits-an-editor-shows-before-saving).

**The counter of a text.** A text with a `max_length` has a counter beside
its editor, "12/30", which follows what is typed: in a cell, on a field of
the action panel and on the argument line. It counts as Ash counts (the
text trimmed, in the unit of `length_count`), and stops nothing: a longer
text is typed and sent, the counter says "34/30", and Ash refuses it. See
[Inline editing](documentation/topics/inline-editing.md#the-counter-of-a-text).

**Confirm.** A column with `confirm` asks its question in a dialog at the
moment of saving, before the action runs. Confirm saves. Cancel, or Escape,
returns to the cell, still in edit mode with what was typed.

**Maps and embedded resources.** A value made of fields is shown on one
line, as plain text: `Name: Lumen, Key account?: No, Address: Street: Ring
3, City: Bonn`. Each field is called by its name in words, as a column of
that name would be, and shown as a cell of its type shows it; a field that
holds nothing is left out; the values of an array have `; ` between them.
Of an embedded resource the fields are its public attributes; of a map,
the fields it declares (`fields`), or whatever it holds when it declares
none.

Enter, F2 or a double click on such a cell opens the side panel, headed by
the column and the record, with the value as a group of its fields: each
with the control of its type, a value inside the value as a group in the
group, and an array as one group per value, with a button that takes a
value away and one that adds a value. "Save" runs the column's update
action with the attribute as its one input, given as a map of its fields;
a panel that holds what the record holds saves nothing. What the action
says about a field is shown at that field, and the panel stays open.

- A value that may be empty is taken away with the button beside its
  label, and one that is not there is added with "Add value". A group that
  is there is a value, empty fields included: nothing is guessed.
- It is editable when the column's action accepts the attribute and a
  person can give every field of it: every field has a control, a map
  declares its fields, and an embedded resource's create and update
  actions accept the same public attributes. Otherwise the cell is
  read-only, as a map without fields always is.
- Ash casts the value through the embedded resource's own actions (create,
  update on a matching primary key, destroy), as for every interface. A
  table does not name them and does not check whether they are `public?`.
- It is neither sorted nor filtered by.

See [Maps and embedded resources](documentation/topics/maps-and-embedded-resources.md).

**Unions.** A union (`:union`, with its kinds as `types`) is shown as the
value it holds, as a cell of that kind's type shows it: a number as a
number, an embedded resource as its one line. Nothing in the cell says
which kind it is.

Enter, F2 or a double click opens the side panel with the union as a
group: "Kind", a choice of the union's kinds by their names in words, and
under it the value of that kind, with the one control of its type or, for
a kind made of fields, with its fields. Choosing another kind puts that
kind's fields in place of the others, empty. No kind is no value, where
the attribute may be empty. "Save" runs the column's update action with
the kind and its value, as Ash takes a union from outside
(`%{"_union_type" => …, "_union_value" => …}`), for tagged and untagged
unions alike.

- It is editable when every kind has a control. A union with a kind that
  has none (an array, a map without fields) is read-only, and so is an
  array of unions.
- What the action says of the value is shown at the value's control, and
  of a field of a kind at that field.
- An embedded resource among the kinds is cast through its create action
  every time: `Ash.Type.Union` does not run its update action.
- It is neither sorted nor filtered by, as in `ash_json_api` and
  `ash_graphql`.

See [Unions](documentation/topics/unions.md).

## Choosing a related record

A reference cell shows the record a belongs-to relationship points at. A
person changes which record that is by choosing one from the related
resource's own table, in a dialog at the right edge of the window: the
**picker**. Nothing is declared for it.

```elixir
table do
  update_action :update      # accepts :project_id and :assignee_id

  column :project do
    confirm "Move this task to another project?"
  end

  column :assignee
  column :reporter           # no action accepts :reporter_id: read-only
end
```

- **Which reference cells are edited.** Those whose update action, the
  column's own or the table's, accepts the relationship's foreign key (its
  `source_attribute`), under the rules of any editable cell. The key has to
  be a public, writable attribute, and the relationship must have no
  `filter`. And those whose action takes the related record through an
  argument that it hands to the relationship: see
  [Relationships an action manages](#relationships-an-action-manages).
  Every other reference cell is read-only.
- **Opening it.** Enter, F2 or a double click on the cell. The picker is a
  modal dialog, headed by the column and what is chosen ("Assignee: choose
  user"). Its table is rendered when it opens, and focus goes into it, to
  the row of the record the cell points at now when that row is on the page.
- **The table in it** is the destination's table as declared: its columns,
  its filter row, its sorting and its pages. It is for choosing only: no
  cell of it is edited, and it has no row actions, no create button and no
  expanders. Its rows have radio buttons: one row is selected at a time.
- **Which records are offered.** Those the destination's read action
  returns for this person, in their tenant: the relationship's own
  `read_action` when it names one, else the read action of the
  destination's table.
- **Choosing.** A click on a row, or Space, selects it, which changes
  nothing; "Choose" takes the selected row. Enter on a row and a double
  click choose it at once. "None" empties the key, where the key can be
  empty. "Cancel" and Escape close the picker.
- **Saving** is the save of a cell: the column's update action runs with
  exactly one input, the key, through `AshPhoenix.Form`; the record the cell
  points at already saves nothing; a column with `confirm` asks first, on
  top of the picker; the row is shown from what the action returns; and a
  save the action refuses is shown on the cell, with the action's message.
- **A key from the browser is a claim.** The row the picker sends is read
  again on the server, as the person and through the read action the picker
  shows its rows through, and it is that record's value that is saved. A
  key of a record they may not read there, or of another tenant, saves
  nothing, however it was sent.
- **In the action panel**, an input that is such a key is given the same
  way: its field says what the record is called and has a button, "Choose",
  that opens the picker on top of the panel. See
  [Row actions and create](#row-actions-and-create).

The guide [Choosing a related record](documentation/topics/choosing-a-related-record.md)
has all of this in detail.

## Relationships an action manages

An action can take the records of a relationship as an argument and hand
them to the relationship. A table lets a person give such an argument by
choosing existing records in the picker: one, or several. Nothing is
declared for it.

```elixir
update :set_labels do
  require_atomic? false
  argument :labels, {:array, :uuid}, allow_nil?: false
  change manage_relationship(:labels, type: :append_and_remove)
end

table do
  action :set_labels           # the panel lists the labels; "Choose" opens their table
end
```

- **Which arguments.** One that a `manage_relationship` change of the
  action hands to a relationship, and that holds the key of a related
  record, or a list of such keys: the related resource's primary key,
  unless the change names another attribute (`value_is_key`). The
  relationship has to be public, without a `filter`, and its destination
  has to have a table. A change that would make a record for a key that
  names none (`type: :direct_control`) is not chosen.
- **Existing records only.** An argument that holds a map, or a list of
  maps, describes records to create or to change. A table has no form for
  that; a related record is created in its nested table.
- **The field.** For one key, what the record is called and a button
  "Choose", as for a key the action accepts. For a list, what each record
  is called, each with a button that takes it out of the list, and "Choose"
  under them. The picker then has a box per row, opens with the rows of the
  field's records selected, and "Choose" takes whatever is selected.
- **What the field starts with.** The records that are related now, where
  the argument is everything the relationship is to hold
  (`:append_and_remove`): they are read as Ash reads them when the action
  runs, for the same person. Nothing, where the change adds (`:append`) or
  takes away (`:remove`).
- **A reference cell** is edited through such an argument too: where its
  action does not accept the foreign key, and has an argument that hands
  one key to the column's relationship and relates the record it names. The
  key the action accepts comes first.
- **Keys are claims**, as for one record: every key that was not related
  already is read as the person before the action runs, and the action,
  with the policies of what it relates through, decides the rest. A related
  record the person may not read is neither shown nor taken away.
- **On the selected rows**, the chosen records are given to the action on
  every record.

The guide [Relationships an action manages](documentation/topics/managing-relationships.md)
has all of this in detail.

## Row actions and create

A row action is an update or destroy action of the resource that a person
runs on one record, from a button in the last column of its row. A table
can also offer one create action, behind a button on the line of its name.
Both are opt-in, and the table adds nothing to the action: it runs through
`AshPhoenix.Form` as the person, and the table shows what it returns.

```elixir
table do
  action :archive                  # buttons, in this order

  action :reassign do
    label "Hand over"              # default: the action's name in words
  end

  action :destroy do
    confirm "Delete this task? This cannot be undone."
  end

  create_action :create            # "New task"
end
```

- **Which actions.** Public update and destroy actions. A generic action
  takes no record: named with `action` it is a
  [table action](#table-actions), unless it says which argument takes the
  row's key. A create action is named with `create_action`. Anything else
  is reported when the resource is compiled.
- **Straight away, or the action panel.** An action without inputs, or with
  optional arguments only, runs when its button is used. One that accepts
  attributes, has a required argument without a default, or has an
  argument that is given by choosing related records opens the
  **action panel** first: a
  modal dialog at the right edge with one field per input, "Cancel" and
  "Run". A create always opens it.
- **The panel's fields** are the action's public inputs in its own order,
  accepted attributes first. A field is called what the table's column for
  that attribute is called, else by the input's name in words. Its control
  is the cell editor of its type, and a plain text field for a value
  written as one line that has no editor (a UUID, a time, an atom).
  Attributes start with the record's values, arguments with their
  defaults. A field is marked as required when the action requires it.
- **The key of a related record is chosen, not typed.** An input that is
  the foreign key of a public belongs-to relationship whose destination has
  a table is a field that says what the related record is called, with a
  button that opens the [picker](#choosing-a-related-record) on top of the
  panel. The panel keeps everything else that was typed. Before the action
  runs, a key that was put into such a field is looked up as the person: one
  that names no record they could have chosen runs nothing. A key whose
  destination has no table stays a plain text field. An argument that the
  action hands to a relationship is chosen the same way, one record or
  several: see
  [Relationships an action manages](#relationships-an-action-manages).
- **An array** is a field too: multiple choice for enum values, and a row
  per value for text, numbers, booleans, dates and datetimes. It gives the
  action a list, which is empty when there are no values.
- **An embedded resource or a map that declares its fields** is a group of
  its fields under the input's label, and an array of either a group per
  value: "New project" in the demo gives the client, its address and the
  milestones. See [Maps and embedded resources](documentation/topics/maps-and-embedded-resources.md#in-the-action-panel).
- **A union** is the choice of its kind and that kind's value, as in the
  side panel of a union's cell. See [Unions](documentation/topics/unions.md#in-the-action-panel).
- **An argument that takes a file** (`:file`) is a file input: see
  [Files](#files).
- **Inputs without a field** (maps without fields, unions with a kind
  that has no control, arrays of unions, several files): an
  optional one is left out of the panel; an action that requires one cannot
  be run from a table, which the compiler reports.
- **Errors.** The action's messages are shown at their fields as the person
  types and after "Run", and the panel stays open. What is about no field
  of the panel, a refusal among it, is above the fields. An action that ran
  straight away and failed marks the row's actions cell with its message,
  as a failed save marks its cell; nothing pops up over the page.
- **`confirm`** asks a question in the table's dialog before the action
  runs; with a panel, when "Run" is used. A destroy action without one is a
  compile warning, since one click would delete the record: give it a
  question, or say `confirm false`.
- **Afterwards.** An updated row is shown from the action's result and
  stays where it is. A destroyed row is taken away with everything open
  under it. A created record is the first row of the page. The total is
  changed by one; sort, filters and what other people did show at the next
  read.
- **In a nested table** the row actions are those of the destination's
  table. Create is offered only for a has-many joined by attributes whose
  destination's `create_action` accepts the joining attribute: the table
  fills that in from the row above, and the button is on the relationship
  line.

The guide [Row actions and create](documentation/topics/row-actions-and-create.md)
has all of this in detail.

## Selecting rows and bulk actions

A table with a row action has a box at the start of every row, and one in
the header for the rows of the page. A person selects rows and runs a row
action on all of them at once. There is nothing to declare: every row
action is offered for a selection unless it says otherwise.

```elixir
table do
  action :archive                  # in every row, and for the selected rows

  action :destroy do
    confirm "Delete this project, with all its tasks?"
    bulk? false                    # in the rows only
  end
end
```

- **Selecting.** A click on a box, Space on any cell of a row, Shift and a
  click or Shift with Down or Up Arrow for a range. It happens in the
  browser alone: nothing is sent, and no row comes back. A selection lasts
  through a sort and a change of page and is given up when a filter
  changes. It is not in the URL.
- **All that match.** Once the whole page is selected and the filters match
  more, "Select all 320 that match" selects every record the read action
  returns for this person under the filters. That is "whatever matches",
  worked out on the server when an action runs, and no list of rows.
- **The line above the grid** says how many records are selected, which is
  read out when it changes, and has "Clear selection" and one button per
  bulk action.
- **Which actions.** The table's row actions that this person can ever run.
  Not one that says `bulk? false`, and not one that accepts a value only
  one record can hold: an attribute of the primary key, or an identity by
  itself.
- **A question, always**, with the number of records: "Run “Archive” on 3
  records?", or the action's own `confirm` with the number after it.
- **Inputs once.** An action with inputs opens the action panel once for
  the whole selection. Its fields start empty, and what they hold is given
  to the action on every record: an empty field is an empty value.
- **What runs.** Each selected record is read as the person, through the
  table's read action, and the action is run on it as the person, through
  `Ash.bulk_update/4` or `Ash.bulk_destroy/4` with `strategy: :stream`, one
  record and one transaction at a time, with notifications. It is what the
  row's button does, once per record: a policy or a validation that refuses
  one record does not stop the others, and nobody changes in bulk what
  they could not change from its row, or cannot read.
- **Afterwards** the table reads again and says "Archive: 2 done, 1 not
  done.", with each of the action's messages and the number of records it is
  about. The rows it did not run on stay selected. A record that is gone,
  or not the person's to read, counts as not done.
- **A nested table** has its own boxes and its own selection, and an action
  on it runs on the records under its row.

The guide
[Selecting rows and bulk actions](documentation/topics/selecting-rows-and-bulk-actions.md)
has all of this in detail.

## Table actions

A table action is an action a person runs on the table as a whole and not
on one record. On the resource it is a generic action: it takes arguments
and returns a value, and is given no record. It is declared like a row
action, and is a button on the line of the table's name, after "New …".

```elixir
actions do
  action :count_unused, :integer do
    run fn _input, context -> MyApp.Labels.count_unused(context) end
  end

  action :recolour, :integer do
    argument :from, :string, allow_nil?: false
    argument :to, :string, allow_nil?: false
    run MyApp.Labels.Recolour
  end

  action :copy do
    argument :label_id, :uuid, allow_nil?: false
    argument :name, :string, allow_nil?: false
    run MyApp.Labels.Copy
  end
end

table do
  action :count_unused             # runs at once: "Count unused: 3"

  action :recolour do              # two required arguments: the action panel
    confirm "Recolour these labels?"
  end

  action :copy do
    record_argument :label_id      # a row action: the table gives the row's key
  end

  action :merge do
    reference :into, MyApp.Label   # a key argument: chosen in the picker
    reference :labels, MyApp.Label # a list of keys: any number is chosen
  end
end
```

- **At once, after a question, or the action panel.** An action without
  arguments, or with optional ones only, runs when its button is used,
  after its `confirm` question if it has one. A required argument without
  a default opens the action panel, with a field per public argument, as
  for a row action.
- **Afterwards** the table says one line above the grid, which is read out:
  the action and what it returned when that is text, a number, yes or no,
  a date or a name ("Count unused: 3"), else that it is done ("Remove
  unused: done"). Then it reads its records again. Returned records are not
  shown as a table.
- **`record_argument`** names the argument of a generic action that takes
  a record's primary key. The action is then a row action: its button is in
  every row, the table fills that argument with the row's key and does not
  ask for it, and the other arguments are asked for in the panel. The
  argument has to be public and of the type of the primary key, which has
  to be one attribute. Such an action is offered for the selected rows like
  any row action, and runs once per record; `bulk? false` keeps it to one
  row.
- **`reference`** says which resource a key argument refers to
  (`argument :into, :uuid`): Ash does not say it, and without it the key is
  typed into a plain text field. With it the argument is chosen in the
  [picker](#choosing-a-related-record), from the table of that resource:
  one record for a key, any number for a list of keys. The chosen records
  are read again, as the person, before the action runs. It is for every
  `action` of the block, a row action too. An argument that a
  `manage_relationship` change hands to a relationship needs none, and
  takes none. See
  [Table actions](documentation/topics/table-actions.md#an-argument-that-holds-the-key-of-a-record).
- **It runs as the person**, in their tenant and with authorization,
  through `AshPhoenix.Form.for_action/3` and so `Ash.run_action/2`. A
  person who can never run it has no button. Ash is asked once per action
  and without arguments: a policy of a generic action can look at the
  actor and at the arguments, never at a record.
- **Failures** are shown as those of a row action: at the fields of the
  panel, above them, on the row's actions cell, and for a table action
  without a panel on the line above the grid.
- **In a nested table** the buttons are on its relationship line, after
  the create button. A table action is the same there as on the table's
  own page: it is not given the row the nested table is under.

The guide [Table actions](documentation/topics/table-actions.md) has all of
this in detail.

## Files

An action can take a file: an argument of the type `:file`
(`Ash.Type.File`). Ash stores no file, so a file is never a column; it is an
input of an action, and the action panel has a file input for it.

```elixir
actions do
  action :import, :integer do
    argument :file, :file, allow_nil?: false
    run MyApp.Labels.Import
  end
end

table do
  action :import

  upload :file do                  # optional: what the upload takes
    accept ~w(.csv)                # default: any kind of file
    max_file_size 100_000          # default: 8 MB, LiveView's own limit
  end
end
```

- **Where.** In the panel of a row action, of a table action, of the create
  action and of an action on the selected rows. An action with a file
  argument always opens its panel.
- **How it gets there.** The field is a LiveView upload. The file is sent
  when the panel's button is used, and the action runs while LiveView still
  holds it. The action is given a `Plug.Upload`, which Ash casts to an
  `Ash.Type.File`: `open/2`, `path/1`, the browser's `filename/1` and
  `content_type/1`. The file is gone when the action is done.
- **Limits.** `Ash.Type.File` has no constraints, so the `upload` of the
  block says what the upload takes, by the argument's name. A file outside
  it is refused as it is chosen, at the field: "The file is too large. The
  limit is 100 kB.", "This type of file is not accepted."
- **Errors.** What the action says of the file is shown at the field, and
  the panel stays open. A file is given once: after "Run" the input is
  empty again, and a person whose action did not run chooses the file
  again.
- **On the selected rows** every record is given the same file.
- **Not** several files for one argument, and no download.

The guide [Files](documentation/topics/files.md) has all of this in detail.

## Nested tables

A row expands into the tables of its related records. The first cell of a
row, after its box where rows can be selected, holds the expander; an
expanded row shows one line per relationship, and
a line opens the nested table: the table of the destination resource, as that
resource declares it, limited to the records related to the row. A nested
table sorts, filters, pages and edits by itself, and its rows expand again.

```elixir
table do
  max_depth 2              # default: 3

  relationship :comments

  relationship :author do
    label "Written by"
  end
end
```

- With no `relationship`, a row offers every public relationship whose
  destination resource has a table (lists `AshTable.Resource`), except manual
  relationships and those that are read through a private action. Once one
  `relationship` is declared, a row offers exactly
  the declared ones in the declared order. A table with nothing to offer has
  no expanders and no column for them.
- A nested table is read through Ash's own loader, so the relationship means
  what the resource says it means: its filter, its `read_action` if it has
  one (else the read action of the destination's table), and its own `sort`,
  which comes first while the person has chosen none. The read action has to
  be `public?`, and so has the one of a many-to-many's join resource. The
  row it belongs to is read again through the read action of the table that
  shows it.
- It has pages where Ash can page the relationship: one that holds many
  records, is joined by attributes, through an action that declares
  pagination. A relationship with `no_attributes?` and a manual one are shown
  in full. A relationship that holds one record (a belongs-to, a has-one) is
  a table of at most one row without sort, filters or pages, and so is a
  manual one.
- `max_depth` says how deep a person can expand, counted from the table on
  the page, and the tables at that depth have no expanders. The setting of
  the table on the page counts for everything beneath it. `max_depth 0` on a
  table means its rows never expand, wherever it is shown.
- The row a nested table belongs to is read again, as the person, every time
  the nested table reads. A nested table is fetched when its line is opened,
  and not before.
- Nothing of it is in the URL: which rows are expanded, and the sort, filters
  and page of the tables in them, last until the table around them reads
  again (a change of its sort, filters or page), which closes them. A save in
  a row leaves what is open under it open.
- The last row of a nested table is a link, "Open in full view", to the page
  the router mounts the destination's table at, when it mounts one. That
  page shows the same records, with the row and the relationship in the
  table's own parameter `of`:
  `/comments?comment[of][task][comments]=KEY`. Its state is in the address,
  a heading says whose records these are, and "Show all records" takes the
  limit away. The parent in the address is looked up among the resources
  whose table offers such a relationship, never trusted, and read again as
  the person on every read.

What a person may not see applies in a nested table as on a page of its
own: a line whose destination they can never read is not there, records they
may not read are not among the rows, a column they can never see is left
out, and a hidden field is "Not available".

> #### A nested table can lose its total {: .info}
>
> While a filter is set on a column the person sees on some records only, a
> nested table shows and announces no total, as a table does whose action
> does not count. Ash counts a page of related records with the filter as it
> is written, without the field policies, and the total would tell how many
> records match among those whose value is hidden.

The guide [Nested tables](documentation/topics/nested-tables.md) has all of
this in detail, with the full view, the reference cell and what a person
sees for each restriction.

## Named tables

A resource can have several tables. The `table` block is its **default
table**; the `tables` block declares **named tables** beside it:

```elixir
table do
  label_field :body
  update_action :update
  create_action :create
end

tables do
  table :compact do
    max_depth 0

    column :body
    column :author
  end
end
```

A named table has every option and declaration of the `table` block except
`label_field`, which says what a record is called and belongs to the
resource. It takes nothing over from the default table: its columns,
actions and settings are its own.

```elixir
# mounted
ash_table "/comments/compact", MyApp.Comment, table: :compact

# nested under another resource's rows
relationship :comments do
  table :compact
end
```

```heex
<AshTable.table resource={MyApp.Comment} table={:compact} scope={@current_scope} />
```

- The id of a named table defaults to the resource's, `_` and the table's
  name (`comment_compact`), so two tables of one resource share a page and a
  URL without an `id` being written.
- "Open in full view" on a nested named table leads to the mounted page of
  the same table, and is not there when that table is mounted nowhere.
- The picker shows the destination's default table.
- A table can be declared in a file of its own, as a Spark fragment of the
  resource (`use Spark.Dsl.Fragment, of: Ash.Resource, extensions:
  [AshTable.Resource]`, listed as `fragments:`). Every compile-time check
  holds, and a finding points at the fragment's file.

The guide [Named tables](documentation/topics/named-tables.md) has the
rules, the ids and the fragment pattern.

## Custom components

A column can name a module that says how its cells look, what they are
edited with, or both:

```elixir
table do
  update_action :update

  column :status do
    component AshTable.Components.Badge
  end

  column :progress do
    component MyAppWeb.Cells.Progress
  end
end
```

Four are shipped: `AshTable.Components.Badge` shows an enum's value as a
badge, `AshTable.Components.Image` shows the picture at the address a text
holds, `AshTable.Components.Progress` shows a number between its minimum and
maximum as a bar with the number beside it, and `AshTable.Components.Slider`
edits such a number with a slider. A component of your own is a module with
two function components, either of which can be left out:

```elixir
defmodule MyAppWeb.Cells.Hours do
  use AshTable.Component

  # how a cell shows the value
  def cell(assigns), do: ~H"{@text} h"

  # what it is edited with, in a cell and in the action panel
  def editor(assigns) do
    ~H"""
    <span class="flex items-center gap-1">
      <input type="number" min={@column.constraints[:min]} value={@value} {@control} />
      <span aria-hidden="true">h</span>
    </span>
    """
  end
end
```

- A component changes the look and the control, and nothing else. A value is
  saved through the column's `update_action`, as without one; sorting,
  filtering and authorization do not know that it is there.
- `cell/1` is given the value, the text the table itself would show, and
  what the resource knows about the field: its type and constraints, an
  enum's values with their labels, the column's label. It is not given the
  record, and it is not called for a value the person may not see, nor for a
  record without one: the table shows its own placeholder and its own empty
  cell.
- `editor/1` renders one element with one form control in it, which carries
  `{@control}`; the control's value is what is saved. The same editor is the
  field of that attribute in the action panel.
- An editor saves on Enter or on leaving the cell, as anything typed does.
  `use AshTable.Component, commit: :change` makes it save when its value
  changes instead: a slider when it is let go. Escape gives up what has not
  been saved.
- The resource does not depend on the component's module: there is no
  compile-time dependency from the data layer to the web layer. The module
  is checked once the application is compiled, and again when the table is
  built.

The guide [Custom components](documentation/topics/custom-components.md)
has the assigns, the control's contract, the keyboard, what a component owes
the people who use it, and what it costs.

## Who is reading, and what they may see and do

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

One page can be mounted without authorization, whatever its domain says:

    ash_table "/admin/tasks", MyApp.Tracker.Task, id: "admin-task", authorize?: false

> **This page shows everything to whoever can open it.** Every read and
> every action the table runs for it is given `authorize?: false`, the
> tables nested in it and its pickers included. Put it behind your own
> access control (a pipeline and an `on_mount` hook that let only
> administrators in), and nowhere else. The option is the router's: nothing
> a browser sends can set it.

**A `sensitive?` field is masked.** Its cells show `••••••` and a "Show"
button; the value is not sent to the browser until a person asks for that
one cell (the button, or Shift+Enter), and it is hidden again when focus
leaves the cell. The editor hides what is typed and starts empty, and an
editor left empty saves nothing. A value is emptied with the button
"Clear", in the editor and at the field of a row action's panel, where the
action takes the attribute without a value. A table neither sorts nor
filters by such a column. Sensitive is not hidden: who may read the field is said by a
field policy. See
[Sensitive columns](documentation/topics/sensitive-columns.md).

**Every action a table runs is `public?`,** however the table came by it.
Ash runs a private action for whoever its policies allow, and the policy
its documentation gives for a private action allows everybody
(`bypass private_action?() do authorize_if always() end`): what keeps such
an action from a person is that no interface runs it. `ash_json_api` and
`ash_typescript` refuse a public relationship whose read action is private
for the same reason. So a table is reported when its resource is compiled,
and refused when it is built, over a private

- read action: the one the block names, or the primary one it falls back
  to;
- read action of a relationship its rows offer (the relationship's own,
  else that of the destination's table; and that of the join resource of a
  many-to-many), of a reference cell (the relationship's own, else the
  destination's primary one), or of an aggregate column or a calculation
  column that holds an aggregate (along the whole path of the aggregate);
- update, destroy or create action that the block names;
- primary read action, where the table changes records: Ash loads what a
  create, an update or a destroy action returns through it.

Not checked is what a public action does while it runs. The actions of an
embedded resource are of that kind: Ash runs them while it casts the value
of an attribute the action accepts, whichever interface gave the value, and
does not ask whether they are `public?`.

A relationship of the default set that leads to a private read action is
quietly not offered. Make the action public, name a public one, or do not
offer what leads to it. The record of a row, and the row a nested table
belongs to, are read again through the read action of the table that shows
them, so a key reaches no record that the table would not show. The same
holds for the rows a person has selected: an action on them is one of the
block's public row actions, and each record is read through the table's
read action, as the person, before the action runs on it.

**What each restriction looks like.**

| The resource says | The table shows |
| --- | --- |
| The person may not see some **records** (a policy that filters) | Those rows are not there, and are not counted. Nothing indicates them. |
| The read is **refused outright** (a `Forbidden` error, as from an `access_type :strict` policy) | The page answers as if it did not exist: status 404 and your "not found" page. With `on_forbidden :message`, the page stays and says "You are not allowed to see these records." |
| The person can **never see a field** (a field policy that depends on the actor only) | The column is left out for that person: no header, no filter, no cells. A URL that sorts or filters by it is ignored. |
| The person sees a field on **some records only** (a field policy with a check on the record) | The column stays. Hidden cells are empty, announced as "Not available", and cannot be edited. |
| The person can **never read a related resource** | A reference cell of it has no column for them, and it has no line under an expanded row. |
| The person may **not read one related record** | It is not among the records to choose from in the picker, and its key cannot be saved by them, by whatever event. |
| The person can **never run an update action** | The columns it saves are read-only for that person. If that is every editable column, the table offers them no editing at all. |
| The person may run an update action on **some records only** | Cells look editable. On a record the action refuses, the cell says "You are not allowed to change this." when it is saved. |
| The person can **never run a row action**, a table action, or the create action | The action has no button for them; with no row action left, the table has no actions column. |
| The person may run a row action on **some records only** | The button is on every row. On a record the action refuses, the actions cell or the action panel says "You are not allowed to do this." |
| The person can **never run any row action** on several rows | The table has no boxes to select rows with. |
| The person may run a row action on **some of the selected records only** | It runs on those. The table says how many it did not run on and why, "You are not allowed to do this. (2)", and those rows stay selected. |

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
(`Ash.can_see_fields/4` and `Ash.can/3`, once per update action, row action
and create action). When who is logged in changes, mount the page again, as
a login or logout does.

**Filtering and sorting by a field that is hidden on some records** stays
possible, and gives nothing away: Ash treats a hidden value as empty in
filters and sorts. A filter by a value finds only records whose value the
person sees; "is empty" also finds every record whose value is hidden; a sort
puts the hidden ones together with the empty ones.

> **The table refusing to edit a hidden field protects the table only.** A
> field policy is about reading. When a person is not shown a field on a
> record, the table does not let them change it there either, in a cell or
> in the action panel, but the update
> action itself would: the same action called through `ash_json_api`,
> `ash_graphql` or your own code accepts the field from anyone its *policy*
> allows. If a field must not be changed by people who cannot see it, say so
> in the resource: an action that does not accept the field, or a policy or
> validation on the one that does.

## The keyboard

The grid is one tab stop: Tab enters and leaves it, the arrow keys move
within it. Up Arrow from the first row of records reaches the filter row and
then the header. Nothing of this talks to the server.

| Key | Effect |
| --- | --- |
| Arrow keys | Move one cell; they do not wrap |
| Home, End | First and last cell of the row |
| Ctrl+Home, Ctrl+End | First cell of the first row of records, last cell of the last row |
| Page Up, Page Down | Move by a screenful of rows |
| Tab, Shift+Tab | Leave the grid |
| Enter, on a header | Sort by the column |
| F2, on a header | Go to the handle of the column's width: Left and Right Arrow change it, Home and End go to the narrowest and widest, Enter undoes, Escape returns |
| Space, on a cell of a row | Where rows can be selected: select the row, or take it out. Nothing anywhere else |
| Shift+Down Arrow, Shift+Up Arrow | Where rows can be selected: move a row and select as they go |

Where rows can be selected, the first cell of a row holds its box, and the
box in the header stands for the rows of the page. While rows are selected,
the buttons of the line above the grid are ordinary tab stops before it.

Where rows expand, the expander is the next cell of a row, one cell to the
left of where Tab enters the grid. The lines under an expanded row, and the
cell that holds a nested table, are cells of the grid that the arrow keys
stop at:

| Key | Effect |
| --- | --- |
| Right Arrow, on an expander or a line that is closed | Open it |
| Left Arrow, on an expander or a line that is open | Close it |
| Enter, on an expander or a line | Open or close it |
| Enter, F2, on the cell that holds a nested table | Go into the nested table |
| Escape, in a nested table | Come back out, to the cell that holds it |
| Enter, F2, on the last row of a nested table, which holds its link | Follow "Open in full view" |

A nested table is a grid of its own, and inside it everything works as in a
table on a page. The whole tree of tables is one tab stop: Tab leaves all of
it. The pages of a nested table are a row at the end of its grid, reached
with the arrow keys and entered with Enter, where Left and Right Arrow move
between the buttons; its link to the full view is the row after them.

On a filter cell, Enter or F2 goes into the filter, and so does a character,
which is typed there: over the text or number the filter holds, into the
first part of a date, or to the first choice that starts with it, which
applies at once as any choice does. In the filter the arrow keys belong to
the input, Enter applies what was typed and stays, Escape gives up what was
typed and not applied and returns to the cell, and Tab moves through the
filter's controls and from the last one out of the grid.

On a cell that can be edited:

| Key | Effect |
| --- | --- |
| Enter, F2 | Start editing; on a boolean, toggle it and save; on a reference cell, open the picker |
| A character | Start editing with it: text and numbers are replaced by what is typed; a date keeps its value and takes a digit into its first part; a choice opens at the first value starting with the character |
| Escape | While editing, give the edit up; on a cell whose save failed, restore the saved value |
| Enter, while editing | Save; focus stays on the cell. In text, Shift+Enter makes a new line |
| Tab, Shift+Tab, while editing | Save and leave the grid, forwards or backwards |
| Arrow keys, Home, End, while editing | Belong to the editor |
| Space | Selects the row where rows can be selected; a boolean is toggled with Enter or F2 |

On the actions cell of a row, the last cell, Enter or F2 goes to its first
button. Left and Right Arrow move between the buttons, Enter or Space uses
one, Escape returns to the cell, and Tab moves on through the buttons and
out of the grid after the last. Space on the cell itself selects the row.
The action panel is a modal dialog: focus moves into it and stays, and
Escape is Cancel. The picker is one too, on top of the panel when a field
of the panel opened it: in its grid the keys are those of any grid, Space
selects a row, Enter on a row chooses it, and Escape closes the picker
alone. A relationship line with a create button is entered with
F2; Enter on the line opens and closes it as before.

A double click starts editing too. In a choice, the menu opens at once;
Enter or a click chooses and saves, and Escape closes the menu before it
gives the edit up. A character the editor of a number does not take (a
letter, say) starts editing without replacing the number.

## Translations

Two settings, for two kinds of text:

```elixir
config :ash_table,
  gettext_backend: MyAppWeb.Gettext,
  translate_error: {MyAppWeb.CoreComponents, :translate_error}
```

The table translates in the locale of the process it runs in: what your
plug and your `on_mount` hook put there with `Gettext.put_locale/1`. Dates
and numbers are not localized yet; they are shown as the native inputs
write them.

**The table's own texts** ("No records", "Clear filters", "1 result", the
operators of the filters, "You are not allowed to change this." and so on)
are messages of the Gettext domain `ash_table`, written in English. With
`gettext_backend` they are looked up in your backend. Copy the template
that ships with the package to one file per locale and fill in each
`msgstr`:

```sh
mkdir -p priv/gettext/de/LC_MESSAGES
cp deps/ash_table/priv/gettext/ash_table.pot priv/gettext/de/LC_MESSAGES/ash_table.po
```

A message without a translation is shown in English, as everything is
without `gettext_backend`. (Copy the template as a `.po` file, not as a
template of your own: `mix gettext.extract` removes from your templates the
messages it does not find in your code.)

**Your resources' wording that the table shows** goes through the same
domain: the labels of columns (declared with `label`, or the humanised field
names), the labels of the values of an `Ash.Type.Enum`, the questions of
`confirm`, the names of the tables, the labels of row actions and of the
fields of the action panel, and what one record is called in "New task"
(the resource's short name in words, as the message "task"). Each is looked
up as a message and shown as it is when there is no entry. To translate a column, add its label
to the same file:

```po
msgid "Due on"
msgstr "Fällig am"
```

**The messages of your actions** are yours, not the table's: "length must
be greater than or equal to %{min}", "is required", or the `message` of a
validation of your own. They are given to the function named by
`translate_error` as `{message, variables}`, which is exactly what the
`translate_error/1` of a Phoenix app's core components takes: it looks the
message up in your `errors` domain and fills in the variables. So a table
shows an action's message in the same words as your forms do:

```po
# priv/gettext/de/LC_MESSAGES/errors.po
msgid "length must be greater than or equal to %{min}"
msgstr "muss mindestens %{min} Zeichen lang sein"
```

A message is only translated if that domain has an entry for it; that holds
for a custom `message:` of a validation as for Ash's own. Without
`translate_error` the message is shown as the resource wrote it, with its
variables filled in. The words the table puts around a message ("Progress:
…" for an error about another field, "Title was not saved: …" in the
announcement) are the table's own and belong to the first kind.

## The layout

A LiveView mounted from the router gets the root layout only; since Phoenix
1.8 the app layout is a function component each page calls itself, so the
table's page has to be told which one:

```elixir
config :ash_table, layout: {MyAppWeb.Layouts, :app}
```

The component is called with the table as its inner block and the assigns
`flash`, `current_scope` (nil when the socket has none) and, when the socket
has them, `current_user` and `current_tenant`. A domain that names its own
assigns (`scope_assign`, `actor_assign`, `tenant_assign`) has its layout
given those too, under the names the domain gives them, each only when the
socket has it. Without this setting the tables are rendered bare in the root
layout. One table can differ:
`ash_table "/tasks", MyApp.Tracker.Task, layout: false`, or
`layout: {Module, :function}`. The router line also takes `id:` and
`authorize?:` (see "Who is reading, and what they may see and do").

A mounted table's first line is the page's heading: its name as an `h1`,
and its create button at the other end.

A bare table is its heading and the table, nothing around them: it brings no
landmark of its own, because it cannot know which ones the page already has.
The page's landmarks are the host's. Where `<main>` is in the app layout, as
Phoenix generates it, a bare page has none, and accessibility checkers say so
(axe: `landmark-one-main`, `region`). So either the root layout has the
`<main>` around `{@inner_content}`, or the table is given a layout that has
one.

## Inside an existing LiveView

```heex
<AshTable.table id="tasks" resource={MyApp.Tracker.Task} scope={@current_scope} />
```

It accepts `scope`, or `actor` and `tenant`; the assign names of the domain
are for mounted tables only. An embedded table keeps its sort, filters and
page itself; pass the page's current URL as `url` to keep them in the URL.
Several tables can share a page, each with an `id` of its own: they sort,
filter, page and save independently.

```heex
<AshTable.table
  id="open-tasks"
  resource={MyApp.Tracker.Task}
  actor={@current_user}
  tenant={@current_tenant}
  label="Open tasks"
/>
```

`label` is the table's name: the accessible name of the grid, and the text
on the line above it, where the create button is too. It defaults to the
resource's name. An embedded table cannot know the outline of your page, so
it shows that name as text that is no heading. `heading={2}` makes it a
heading of that level, and `heading={false}` leaves it out, for a page that
names the table itself.

It authorizes as its resource's domain says (`authorize?` in `AshTable.Domain`,
`true` by default); `authorize?={false}` or `authorize?={true}` on the table
itself wins. Everything in the table above holds for it, with one difference:
it cannot turn your page into a 404. A read refused outright makes it render
nothing at all, unless the resource says `on_forbidden :message`.

## Things people trip over

- **Text filters are case-sensitive for `:string`**, and not for
  `:ci_string`. The table passes on what was typed; what it matches is the
  resource's decision. See [Filtering](#filtering).
- **Page size and default sort live on the read action**, not in the `table`
  block: `pagination default_limit: 25` and `prepare build(sort: …)`.
- **Mistakes in the `table` block are compile warnings.** As with every Ash
  extension's verifiers, they do not stop a plain `mix compile`. They fail
  the build under `mix compile --warnings-as-errors`, but only in a run that
  compiles the resource: unlike an ordinary compiler warning, a verifier's
  finding is not remembered, so a later build that has nothing to recompile
  passes. Use `mix compile --force --warnings-as-errors` in CI, or build
  from clean there.
- **What a table does when a finding was ignored depends on the finding.**
  It refuses to render (`ArgumentError`, "cannot build the table of …") for
  a wrong `read_action`, a missing primary read action, an action it would
  run that is not `public?`, an unsupported
  `paginate_with`, a column that is no public field or is a calculation that
  needs an argument, a column that names a relationship whose label cannot
  be shown, a `relationship` that cannot be offered, an `update_action` that
  names no public update action, an `action` that names no public update or
  destroy action, a `create_action` that names no public create action,
  editing, row actions or create beside calculation, aggregate or reference
  columns without a primary read action, and a `component` that cannot be
  found, is no component, or says that it cannot serve its column. A
  column's own `update_action` that exists but cannot save the column leaves
  the column read-only, an action
  with a required input the panel has no field for has no button, and
  `sortable? true`, `filterable? true` and `confirm` without effect do
  nothing. See
  [Mistakes at compile time](documentation/topics/mistakes-at-compile-time.md#if-a-finding-is-ignored).
- **An aggregate does not apply the related resource's field policies, and
  a calculation applies none.** A column over a protected field needs a field
  policy of its own. The compiler warns; see
  [Columns and defaults](documentation/topics/columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).
- **An aggregate column that a person sees on some records only has no sort
  for them.** Ash cannot sort by it. In a nested table read in pages, a
  person who sees some field on some records only cannot sort by any
  aggregate column.
- **A hidden field cannot be edited through the table, but the table is not
  what protects it.** A field policy is about reading. The same update
  action called through `ash_json_api`, `ash_graphql` or your own code
  accepts the field from anyone its policy allows. See the note under
  [Who is reading](#who-is-reading-and-what-they-may-see-and-do).
- **Restart the server after changing a path dependency.** The Phoenix code
  reloader does not recompile `{:ash_table, path: "…"}`; neither does it
  rebuild the hooks. Stop the server, `mix assets.build`, start it again.
- **`mix compile` before the assets.** The hooks are generated when the
  dependency is compiled; an `esbuild` that runs first does not find
  `phoenix-colocated/ash_table`.
- **An older Phoenix 1.8 app pins LiveView 1.1.** `ash_table` needs 1.2.10
  or later (see [Install](#install)).
- **Nothing is editable until the block says so**, and then only what the
  action accepts: see [Inline editing](#inline-editing).
- **A row action's button is on every row**, also on the records its policy
  refuses. The table asks Ash once per action, not per record; the refusal
  shows when the action runs.
- **A new or changed row does not move.** A created record is the first row
  and a changed one stays in its place until the next sort, filter or page
  change reads the page again.
- **`action :destroy` warns when the resource is compiled.** A destroy
  action without `confirm` deletes at one click. Give it a question, or say
  `confirm false`.
- **A reference cell stays read-only.** No update action behind its column
  accepts the relationship's foreign key (`accept [:assignee_id]`, not
  `:assignee`) or takes the record through an argument, or the
  relationship has a `filter`.
- **A list of keys has no field.** Its relationship is not public
  (relationships are private unless they say `public? true`), or its
  destination has no table.
- **Space in the picker selects and does not choose.** "Choose", or Enter
  on the row, takes it.
- **A bulk action is one statement per record, not one for all.** That is
  what lets a policy or a validation refuse one record and not the others.
  A run on thousands of records takes as long as that many updates.
- **An empty field in the panel of a bulk action is an empty value** for
  every selected record, not "leave as it is". Its fields start empty.
- **A filter change gives the selection up.** A sort and a change of page
  keep it.
- **A component was renamed, and the table says it cannot be found.** The
  resource that names it was not compiled again, as it does not depend on
  the component. `mix compile --force` reports it; so does a build from
  clean.
- **A table in German with English messages** has `gettext_backend` but no
  `translate_error`, or no entry for that message in the `errors` domain.

## The demo

`demo/` is a Phoenix and Ash app on Postgres that shows all of this: an
issue tracker with one of everything a table has to cope with, five actors
to switch between, and German beside English. See `demo/README.md`.

## Licence

MIT
