# Custom components

A column's `component` is a module that draws one column's cells (`cell/1`),
edits them (`editor/1`), or both. For the look of the whole table, use a kit
(`ash_data_table:kits`). Details:
[Custom components](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/custom-components.md).

## Name one

Reach for a shipped component first: `AshDataTable.Components.Badge` (an
enum, or an `:atom` with `one_of`), `Image` (text that holds an `http(s)://`
address or a path starting with `/`), `Progress` and `Slider` (a number
whose attribute has `min` and `max` constraints).

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
column :status do
  label "State"
  confirm "Change the state of this task?"
  component AshDataTable.Components.Badge
end
```

## Write one

<!-- source: demo/lib/demo_web/components/cells/hours.ex -->
```elixir
use AshDataTable.Component

# How a cell shows the value. `@text` is what the table itself would show.
# Written on one line: a template that ends in text keeps the line break
# after it, and a cell's markup is sent again with every row.
@impl true
def cell(assigns), do: ~H"{@text} h"
```

- **`cell/1`** is given `@value`, `@text` (what the table would show,
  translated) and `@column` (`AshDataTable.Component.Column`: `name`,
  `label`, `type`, `constraints`, `cell_type`, `values`, `editable?`). It is
  given one value, never the record, and is never called for nil or for a
  value hidden from the person: the table draws those cells itself. A
  component that decorates shows `@text`.
- **`editor/1`** renders one element containing, or being, one `<input>`,
  `<select>` or `<textarea>` that carries `{@control}` and `value={@value}`.
  That control's value is what is saved. In a cell the editor is one
  template per column and `@value` is `""`: build the control from
  `@column`, and the table sets its value. `@place` is `:grid` or `:panel`.
- **When it saves:** on Enter and on leaving the cell by default;
  `use AshDataTable.Component, commit: :change` saves on the control's
  `change` event (a slider, a menu).
- **A cell that needs two fields** is a calculation of the resource, with a
  component on that column.
- **One line high**, readable without colour, and what is said in text as
  well as drawn has the drawing `aria-hidden="true"`.
- **Two shipped parts on one column:** a module of its own `defdelegate`s
  `cell/1` to one and `editor/1` and `verify/1` to the other, as
  `demo/lib/demo_web/components/cells/progress.ex` does.

## What stays the table's

A save always runs the column's update action as the person, with the
control's value as its one input; sorting and filtering stay on the field;
the cell itself, its focus ring and its failed-save marks are the table's.
A reference cell has no component. An array, map, embedded resource or
union column takes a component's `cell/1` only: it is edited in the side
panel with the table's own fields.

After renaming a component a resource names, run `mix compile --force`: the
check of a column's component runs when the resource compiles, and a change
to the component alone does not run it again.
