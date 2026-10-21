# Custom components

A column's `component` is a module that sets how the column's cells look,
what they are edited with, or both. This guide covers the shipped
components, writing your own, what a component is and is never given, and
what stays the table's whatever a component does.

A component is about one column's cells. To change how the whole table
looks, see [Kits](kits.md). Columns, sorting and filtering:
[Columns and defaults](columns-and-defaults.md). Saving a cell:
[Inline editing](inline-editing.md). The action panel's fields:
[Row actions and create](row-actions-and-create.md).

## The smallest example

The demo's tasks show their state as a badge
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# enums, each shown as a badge. A change of state asks first.
column :status do
  label "State"
  confirm "Change the state of this task?"
  component AshDataTable.Components.Badge
end
```

**Try it:** `/tasks` in the demo, as Ada Admin. "State" and "Priority" are
badges, "Progress" is a bar with its number, "Estimate hours" has its unit.
`/specimens` has no component on any column: it shows how the table itself
shows every type.

## What a component is

A module implementing the behaviour `AshDataTable.Component`, with two
parts, each a function component. Either can be left out:

| Part | What it is | Without it |
| --- | --- | --- |
| `cell/1` | How a value is shown in a cell. | The table shows the value as it shows any value of that type. |
| `editor/1` | What the value is edited with, in a cell and in the action panel. | The table's own editor of that type. |

The table is drawn by its [kit](kits.md). Where a column has a component,
its `cell/1` draws the value in place of the kit's cell, and its `editor/1`
replaces the kit's editor. Everything around them, the cell itself
included, is the kit's.

A component is only an interface. With one or without:

- **A save runs the column's update action**, as the person, with the
  control's value as its one input. A component cannot save any other way,
  and nothing it renders is trusted: the server reads the record again and
  lets the action decide.
- **Sorting and filtering** work on the field. A badge column's filter is
  still an enum's menu; a bar column's filter is still a number.
- **Authorization** is the resource's. A column the person can never see is
  not there, one they can never edit has no editor, and a value hidden from
  them on one record is not shown.

## The four that are shipped

| Component | Part | For | Looks like |
| --- | --- | --- | --- |
| `AshDataTable.Components.Badge` | `cell/1` | A choice: an `Ash.Type.Enum`, or an `:atom` with `one_of`. | The value's label in an outlined pill. Every value has the same badge: there is no colour per value. |
| `AshDataTable.Components.Image` | `cell/1` | Text that holds where a picture is: an `http://` or `https://` address, or a path that starts with `/`. | The picture, as high as a line of text. Any other text is shown as text: a `javascript:` or `data:` address is never asked for. The picture's text alternative is the column's label. The component is not given the record, so the column has to hold the address itself, or be a calculation that makes one from a stored key. |
| `AshDataTable.Components.Progress` | `cell/1` | A number with a minimum and a maximum. | A bar from the minimum to the maximum, filled up to the value, with the number beside it. |
| `AshDataTable.Components.Slider` | `editor/1` | A number with a minimum and a maximum. | A slider between the two, with the number that is being chosen beside it. It saves when it is let go. |

Each states its needs at compile time: a slider on a number without `min`
and `max`, or a badge on a field that is no choice, is a compiler warning,
and the table refuses to be built with it. The messages are in
[Mistakes at compile time](mistakes-at-compile-time.md#a-column-s-component).

The minimum and maximum are the attribute's constraints. A task's progress
has both:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
attribute :progress, :integer do
  allow_nil? false
  default 0
  public? true
  constraints min: 0, max: 100
end
```

### Two components on one column

A column names one module. To show a number as a bar and edit it with a
slider, a module takes one part from each
([`demo/lib/demo_web/components/cells/progress.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/components/cells/progress.ex)):

<!-- source: demo/lib/demo_web/components/cells/progress.ex -->
```elixir
use AshDataTable.Component, commit: :change

# a bar with the number beside it
defdelegate cell(assigns), to: AshDataTable.Components.Progress
# a slider, which saves when it is let go
defdelegate editor(assigns), to: AshDataTable.Components.Slider
# both need the same of a field: a number with a minimum and a maximum
defdelegate verify(column), to: AshDataTable.Components.Slider
```

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
column :progress do
  update_action :set_progress
  component DemoWeb.Cells.Progress
  # ...
end
```

The module says when its editor saves: `commit: :change` here, as the
slider says for itself.

**Try it:** on `/tasks`, double-click a "Progress" cell, or press Enter on
it. Drag the slider: the number follows while you drag, and the value is
saved when you let go. A "To do" task's state follows, because the column's
action, `set_progress`, starts such a task. Escape closes the slider; the
cell shows the saved value.

## Writing your own

The demo's "Estimate hours" has the demo's own component
([`demo/lib/demo_web/components/cells/hours.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/components/cells/hours.ex)).
It shows the number with its unit and edits it in a number input that knows
the attribute's minimum:

<!-- source: demo/lib/demo_web/components/cells/hours.ex -->
```elixir
use AshDataTable.Component

# How a cell shows the value. `@text` is what the table itself would show.
# Written on one line: a template that ends in text keeps the line break
# after it, and a cell's markup is sent again with every row.
@impl true
def cell(assigns), do: ~H"{@text} h"
```

<!-- source: demo/lib/demo_web/components/cells/hours.ex -->
```elixir
@impl true
def editor(assigns) do
  ~H"""
  <span class="flex items-center gap-1">
    <input
      type="number"
      min={@column.constraints[:min]}
      step="0.5"
      value={@value}
      class={
        if @place == :grid,
          do: "block h-5 w-20 bg-transparent p-0 text-sm outline-none",
          else:
            "input w-full not-focus:[--input-color:color-mix(in_oklab,var(--color-base-content)_50%,transparent)]"
      }
      {@control}
    />
    <span aria-hidden="true">h</span>
  </span>
  """
end
```

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# the demo's own component: the number with its unit
column :estimate_hours do
  component DemoWeb.Cells.Hours
  # ...
end
```

`use AshDataTable.Component` declares the behaviour, brings in
`Phoenix.Component`, and checks that the module defines `cell/1`, `editor/1`
or both. A web-layer module can `use MyAppWeb, :html` before it to have its
own components at hand.

**Try it:** on `/tasks`, as Ada Admin, press Enter on an "Estimate hours"
cell and type a number: Enter saves it. As Max Member, estimates of tasks
that are not his are empty cells that say "Not available" to a screen
reader, as before the column had a component.

### What `cell/1` is given

| Assign | |
| --- | --- |
| `@value` | The value as the record holds it: an integer, a `Decimal`, the atom of an enum's value, a `Date`. |
| `@text` | What the table itself would show, as text: a number written out, an enum's label in the language of the person reading. A component that decorates shows this. |
| `@column` | An `AshDataTable.Component.Column`: see below. |

### What `editor/1` is given

| Assign | |
| --- | --- |
| `@value` | What the control holds, as text: the number as it is written, the name of an enum's value, `""` for nothing. In a cell it is always `""`: see [The control](#the-control). |
| `@control` | The attributes the table needs on the control. They go on it as they are: `<input {@control} />`. |
| `@label` | The column's label, in the language of the person reading. `@control` makes it the control's accessible name where that is needed; it is here for a component that shows it. |
| `@column` | The `AshDataTable.Component.Column`. |
| `@place` | `:grid` in a cell, where the editor stands in the place of the cell's text; `:panel` in the action panel, where it is a field of a form. |

### What a component is told about the column

`@column` holds what the resource knows about the field, so a component
need not be told twice:

| Field | |
| --- | --- |
| `name` | The field's name: `:progress`. |
| `label` | The column's header, translated: "Progress". |
| `type` | The Ash type, as a module: `Ash.Type.Integer`, `Demo.Tracker.TaskStatus`. An array is `{:array, module}`. |
| `constraints` | The type's constraints as the resource declares them: `[min: 0, max: 100]`. |
| `cell_type` | What the table shows the field as: `:text`, `:number`, `:boolean`, `:date`, `:datetime`, `:enum`; `:map` for an embedded resource or a map; `:union` for a union; `{:array, :text}` and so on for an array of such values; or `:other`. |
| `values` | For an enum and for an array of enum values, each value with its label, translated, in declared order; else `nil`. |
| `editable?` | Whether this person can edit cells of the column at all. |

### The control

What `editor/1` renders must be **one element** containing, or being,
**one form control**: an `<input>`, `<select>` or `<textarea>` that carries
`{@control}` and `value={@value}`. That control's value, as the browser
gives it, is what is saved. Nothing else the editor renders is read.

- **In a cell the editor is rendered once per column**, in a `<template>`;
  the table copies it into the edited cell. `@value` is `""` there, and the
  table sets the control to the cell's value when it opens the editor. So
  an editor cannot depend on its starting value.
- **In the action panel** `@control` carries the `id` the field's label
  points at and the `name` the value is sent under; `@value` is the field's
  value.
- **A `<select>`** has no `value` attribute: in the panel it marks the
  chosen option itself (`selected={@value == to_string(choice)}`).
- **An element marked `data-value-text`** inside the editor is kept showing
  the control's current value by the table: the number beside the slider.
- **A checkbox** cannot be the control: its `value` does not say whether it
  is checked.
- **A `phx-hook`** inside the editor does not run in a cell, where the
  editor is a copy of a template.

## When an editor saves

| `use AshDataTable.Component` | The editor saves | For |
| --- | --- | --- |
| nothing, or `commit: :enter` | On Enter, and on leaving the cell. | Anything that is typed. |
| `commit: :change` | When the control's value changes: the browser's `change` event. It stays open, so that the value can be changed again. | A slider, a menu, a picker. |

With `commit: :change`:

- **Nothing is sent while a slider is dragged.** A range input fires
  `change` when it is let go.
- **A keyboard step is not yet a choice.** The control's own keys (Up and
  Down Arrow, Home, End, Page Up, Page Down) move a slider and change a
  closed menu at every press. Such a change is saved by Enter or by leaving
  the cell, as in the table's own menus.
- **Escape gives up what is unsaved, nothing that is saved.** After a save
  through the slider, Escape closes it and the cell shows the saved value.
- **A column with `confirm` asks when the slider is let go**, before
  anything is saved. See [Confirm](confirm.md).
- **A failed save closes the editor**, and the cell is marked like any
  failed save: what was chosen, the ring, the "!" and the action's message.

## What a component is never given

- **A value the person may not see.** Where a field policy hides a value on
  a record, the table shows its own placeholder ("Not available" for a
  screen reader, nothing for the eye), as in every column, and `cell/1` is
  not called. A component cannot leak what it never has.
- **Nothing.** A record without a value for the field has an empty cell, as
  in every column, and `cell/1` is not called. The table decides how empty
  looks, the same for all columns; a component needs no clause for `nil`.
- **The record.** A component gets the cell's value and the column, not the
  row: not the other fields, not the primary key, not who is asking. Other
  fields may be hidden from the person where this one is not, and a
  component that could read them could show them.
- **What was typed and refused.** A cell whose save failed shows what was
  typed as text. It is not a value of the field, so the component is not
  asked to show it.

## In the action panel

An attribute whose column has a component with `editor/1` has that editor as
its field in the action panel, of a row action and of a create.

| | In a cell | In the panel |
| --- | --- | --- |
| `@place` | `:grid` | `:panel` |
| `@value` | `""`; the table sets the control's value | The field's value |
| `@control` | The accessible name (`aria-label`), the mark the table finds the control by, and `aria-required` when the column's action cannot take the cell empty | `id`, `name`, the mark, and `aria-required`, `aria-invalid` and `aria-describedby` when they apply |
| Saving | As the component says: on Enter and leaving, or on change | With the form, when the person uses "Run" or "Create". A change saves nothing. |
| Around it | The table's cell | The table's label, the mark of a required field, and the action's messages |

An input without a column, an argument, and an attribute whose column's
component only shows have the control of their type.

**Try it:** on `/tasks`, "Set progress" at the end of a row opens the panel
with the slider. Move it: nothing is saved until "Run".

## The keyboard

The table's keys are in
[Keyboard and accessibility](keyboard-and-accessibility.md). A component's
editor is opened, left and given up like every editor:

| Key | On the cell | In the editor |
| --- | --- | --- |
| Enter | Opens the editor. | Saves what is not saved and closes it. |
| A character | With a control that is typed into (text, a number): opens the editor and replaces the value, as the table's own editors do. With any other control: opens the editor with its value; the key goes on to the control, and a slider takes no characters. | The control's. |
| Up and Down Arrow, Home, End, Page Up, Page Down | The browser's. | The control's: they move a slider. |
| Escape | | Closes the editor and gives up what is not saved. |
| Tab, Shift+Tab | To the next or the previous stop. | Save what is not saved, and go on to the next or the previous stop. |

## What stays the table's

`cell/1` renders inside the table's cell, never the cell itself. So these
work regardless of a component:

- the cell's id, its role and its place in the table;
- the focus ring, which the cell keeps while its editor has focus;
- a cell whose save is on its way, which is dimmed;
- a cell whose save failed: the ring, the "!", and the action's message
  under the value. Such a cell shows what was typed, as text, not the
  component's `cell/1`;
- one line per row: a cell, and a component's markup with it, is cut off
  at the column's maximum width. (`max_lines` is not for a column whose
  component shows the cell.)

## What a component owes the people who use it

The table keeps its own promises around a component; what the component
draws is the author's:

- **A name for the control.** `{@control}` gives the control its accessible
  name in a cell, and connects it to its label and messages in the panel.
  An editor that leaves it off its control has a control without a name.
- **Not colour alone.** A value must be readable without telling colours
  apart: the shipped bar has its number, the shipped badge is its label.
- **Contrast.** 4.5:1 for text, 3:1 for what shows a state or a control's
  edge. daisyUI's semantic colours are made for fills: in a new Phoenix
  application's themes, `success-content` on `success` is below what text
  needs. The demo's own component gives its panel input the edge the
  table's own fields have, because daisyUI's is too faint.
- **One line.** A row is one line of the table's text high (21px in the
  demo); a taller component makes every row taller. An element as high as
  the line and sitting on the text's baseline does too: the shipped badge
  is aligned to the top of the line for that reason.
- **Nothing said twice.** What is drawn for the eye and also said in text
  is hidden from screen readers (`aria-hidden="true"`), like the shipped
  bar and the unit of the demo's hours.

The demo's browser tests hold the three shipped components to this, in the
light and the dark theme and in forced colours
([`demo/e2e/contrast.spec.ts`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/e2e/contrast.spec.ts)
and
[`demo/e2e/components.spec.ts`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/e2e/components.spec.ts)).
The numbers are in
[Keyboard and accessibility](keyboard-and-accessibility.md#what-was-measured).

## Where the module lives, and when it is checked

A component is a web-layer module; the resource naming it is in the data
layer and does not depend on it:

- `mix xref graph` shows no edge from the resource's file to the
  component's. Changing a component compiles only the component.
- The component is checked once the whole application is compiled, by the
  check that reports a module that does not exist or cannot serve the
  column.

The price: a change to the component alone does not rerun that check. A
component renamed while a resource still names the old one is reported by
the next full compile and by the table when opened, not by the compile
after the change. See
[Mistakes at compile time](mistakes-at-compile-time.md#when-a-component-changes-after-the-resource-was-compiled).

## What it costs

What `cell/1` renders is in every row, and a row is sent again whole when
one of its cells is saved. On the demo's `/tasks` (17 columns, four with
components: two badges, a bar and a unit), measured with
`demo/perf/baseline.mjs` as the admin, 25 rows to a page:

| | Bytes the server sends | On the wire, compressed |
| --- | --- | --- |
| A change of page | 155.7 kB | 11.9 kB |
| One saved cell | 8.5 kB | 0.1 kB |

A component's fixed markup is sent once for all rows of a page; a row that
comes back after a save carries it in full.
[Installation](installation.md#compressing-the-websocket) says what
compression costs.

The shipped badge is one element and the shipped bar two, each with a
handful of classes. Keep yours that small: no wrapper the look does not
need, and `phx-no-format` or a one-line template where a line break would
end up in the cell.

## What cannot have a component

- **A reference cell** (a column naming a relationship): it shows the
  related record's label, and the compiler reports `component` on it.
- **The actions column and the expanders.** They are not columns.
- **The header and the filter row.** A component is about the cells.
- **The placeholder of a hidden value, and the empty cell.**
- **The editor of an array.** An array column can have a component whose
  `cell/1` shows the cells: `@value` is the list, `@text` its values as the
  table would show them, separated by commas. Its `editor/1` is not used,
  in a cell or the panel: an editor's control holds one value. An array is
  edited in the side panel with the table's own field: a box per value for
  a multiple choice, a list of values otherwise. See
  [Inline editing](inline-editing.md#arrays).
- **The editor of a value made of fields.** An embedded resource or map
  column, or an array of either, can have a component whose `cell/1` shows
  the cells: `@value` is the value as the record holds it (an embedded
  resource's struct, a map, a list of them), `@text` the one line the table
  would show. Its `editor/1` is not used: the value is edited in the side
  panel with the table's own fields. See
  [Maps and embedded resources](maps-and-embedded-resources.md#custom-components).
- **The editor of a union.** A union column can have a component whose
  `cell/1` shows the cells: `@value` is the record's `Ash.Union`, with its
  kind (`type`) and value, `@text` what the table would show. Its
  `editor/1` is not used: a union is edited in the side panel, kind first.
  See [Unions](unions.md).

## Edge cases

- **A component on a column nobody can edit.** One with both parts shows
  there and never edits. One that only edits does nothing there, and the
  compiler says so.
- **A person who can never edit the column** gets no editor for it,
  whatever the component. `@column.editable?` tells `cell/1`.
- **A nested table, a full view, a table placed in a LiveView** show the
  same table, with the same components.
- **A calculation or an aggregate** can have a component that shows. It is
  never edited.
- **A decimal or a float under the slider** moves in steps of a hundredth
  of the way from minimum to maximum. A whole number moves by one.
- **An enum with a component that edits.** The editor's control holds the
  value's name (`"in_progress"`); the labels are in `@column.values`.
- **A column the table shows as read-only text** (a UUID, a struct) is not
  made editable by a component: an editor is used only where the table
  would have one of its own.
- **Translations.** `@text`, `@label`, `@column.label` and the labels in
  `@column.values` are in the reader's language. Text a component writes
  itself is the component's to translate.

## Things people trip over

- **Reading `@value` in `editor/1` to build the control.** In a cell it is
  `""`: the template is one per column. Build the control from `@column`,
  and let the table set its value.
- **Forgetting `{@control}`.** The table then takes the editor's first form
  control, which has no accessible name in a cell and no `name` in the
  panel, so the panel sends nothing for it.
- **Two elements at the top of `editor/1`.** Only the first is put into the
  cell.
- **A `cell/1` that handles `nil`.** It is never called with it.
- **Expecting the record.** A component gets one value. A cell that depends
  on two fields is a calculation of the resource, with a component on that
  column.
- **A badge in `badge-success`.** Check the contrast of the theme's
  `success-content` on `success` first.
- **The component was changed, and the table says it cannot be found.** The
  resource was not compiled again. `mix compile --force`.
- **`mix format` puts parentheses around `component`.** Add
  `:ash_data_table` to `import_deps` in `.formatter.exs`; if it is already
  there, the formatter's cache predates the option: remove
  `_build/dev/lib/YOUR_APP/.mix/cached_dot_formatter`.

## Not in the first version

No options for a component (`component {Module, opts}`), so no colour per
value for the badge and no step for the slider; no component given the
record or other fields of the row; no checkbox or other control without a
value as an editor's control; no JavaScript hook of a component's own in a
cell; no component for a reference cell, the actions column, the header or
the filter row; no editor of a component for an array; and no editor for a
type the table shows as read-only text. The later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
