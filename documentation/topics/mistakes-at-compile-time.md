# Mistakes at compile time

A `table` block is checked against its resource when the resource is
compiled. After reading this guide you can read each diagnostic, you know its
cause and its fix, and you know how to make a build fail on them, which a
plain `mix compile` does not.

## The smallest example

The demo app compiles without a finding, and has to. So the example here is
a sketch, not demo code: a cut-down copy of the demo's task with one mistake
in it. The column names an update action that needs an argument.

<!-- sketch -->
```elixir
defmodule Sketch.Task do
  use Ash.Resource,
    domain: Sketch.Tracker,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  table do
    column :title

    column :assignee_id do
      update_action :reassign
    end
  end

  actions do
    defaults [:read]

    update :reassign do
      accept [:assignee_id]

      argument :reason, :string do
        allow_nil? false
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, public?: true
    attribute :assignee_id, :uuid, public?: true
  end
end
```

Compiling it prints this (the output of the compiler for exactly this file,
with the stack trace that follows the message left out):

<!-- sketch -->
```text
warning: ** (Spark.Error.DslError) [Sketch.Task]
table -> column -> assignee_id -> update_action defined in lib/sketch/task.ex:19::
  The update action `reassign` requires the argument `reason`. An inline edit supplies only the cell's value, so the action behind a column must not need anything else.

    │
 19 │       update_action :reassign
    │       ~~~~~~~~~~~~~~~~~~~~~~~
    │
    └─ lib/sketch/task.ex:19: (file)
```

The first line names the resource. The second is the path to the option in
the block, with the file and the line. Then comes the message.

The action is the demo's own. The demo's tasks keep `reassign` to show what
cannot be behind a column, and its table does not name it
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# An action with a required argument: it cannot serve inline editing.
update :reassign do
  accept [:assignee_id]

  argument :reason, :string do
    allow_nil? false
    constraints min_length: 3, max_length: 200
  end

  change set_attribute(:internal_note, arg(:reason))
end
```

**Try it:** in a checkout of the demo, add `column :due_within?` to the
`table` block of `Demo.Tracker.Task` and run `mix compile` in `demo/`. The
calculation needs the argument `days`, and the compiler says so. Take the
line out again.

## Findings are warnings

A finding does not stop a plain `mix compile`. It is printed as a warning,
the build succeeds, and the app starts.

This is not a choice of this library. The checks are Spark verifiers, like
the ones of Ash itself and of every Ash extension. Spark runs verifiers after
a module has been compiled, in the phase in which Elixir checks a module
against the rest of the project, and reports whatever they return as
warnings.

So a mistake in a `table` block is easy to miss in a terminal that scrolls.
Make the build fail on warnings where it counts:

<!-- sketch -->
```sh
mix compile --warnings-as-errors
```

Run this in CI. With it, every message in the tables below fails the build.

### What is an error all the same

A block that is malformed, as opposed to wrong about its resource, is
rejected by Spark while the module is being compiled. That stops any build:

| Mistake | What the compiler says |
| --- | --- |
| A value an option does not take, such as `on_forbidden :hide` | `invalid value for :on_forbidden option: expected one of [:not_found, :message], got: :hide` |
| An option that does not exist, such as `component` on a column | `undefined function component/1 (there is no such import)` |
| An option of the wrong type, such as `label :title` | An "invalid value" error of the same kind. |

## The read action

The path of these findings is `table -> read_action` or
`table -> paginate_with`. In the messages, capitals stand for a name from
your block.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no action named \`NAME\`. | `read_action` names an action the resource does not have. | Correct the name, or define the action. |
| \`NAME\` is an update action, not a read action. | `read_action` names an action of another type (create, update, destroy or generic). | Name a read action. |
| The read action \`NAME\` is not public. Only \`public?\` actions can be behind a table. | The action is declared `public? false`. | Make it public, or name another. |
| The resource has no primary read action. Name the read action behind the table with \`read_action\`. | The block names no read action and the resource has no primary one. This is reported for a resource with no `table` block as well. | Add `read_action`, or mark a read action `primary? true`. |
| The read action \`NAME\` does not support keyset pagination. It supports: offset. | `paginate_with` names a strategy the action's `pagination` does not switch on. The end of the message says what the action supports, or "It has no pagination." | Change `paginate_with`, or add `keyset?: true` (or `offset?: true`) to the action's `pagination`. |

## The table's update action

The path is `table -> update_action`, or `table` for the last one.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no action named \`NAME\`. | The table's `update_action` names an action the resource does not have. | Correct the name, or define the action. |
| \`NAME\` is a destroy action, not an update action. | It names an action of another type. | Name an update action. |
| The update action \`NAME\` is not public. Only \`public?\` actions can be behind a table. | The action is declared `public? false`. | Make it public, or name another. |
| The table has editable columns and shows calculations or aggregates (\`NAME\`), but the resource has no primary read action. After a save the row is refreshed with those fields, which Ash loads through the primary read action. Mark a read action \`primary? true\`. | The table reads through a non-primary action named with `read_action`, at least one column can be edited, and at least one column is a calculation or an aggregate. | Mark a read action `primary? true`. |

## Columns

The path is `table -> column -> NAME`, followed by the option when the
finding is about one.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no attribute, calculation or aggregate named \`NAME\`. | A `column` names something that is not a field: a typo, or a relationship. | Correct the name. A relationship cannot be a column. |
| \`NAME\` is not public. Only \`public?\` fields can be columns of a table. | The field is private. | Make the field `public? true` if it may be shown, or leave the column out. |
| The calculation \`NAME\` requires the argument \`ARG\`. A table cannot supply arguments, so a column can only show a calculation whose arguments are optional or have defaults. | The calculation has an argument with `allow_nil? false` and no default. | Give the argument a default, or define a calculation without the argument for the table. |
| \`NAME\` cannot be sorted, so \`sortable? true\` has no effect. \`sortable?\` can only switch sorting off; remove it or set it to \`false\`. | `sortable? true` on a field the resource does not allow to be sorted. Under keyset pagination the message says "cannot be sorted with keyset pagination". | Remove the option. To sort by a calculation or an aggregate, page by offset. |
| \`NAME\` cannot be filtered, so \`filterable? true\` has no effect. \`filterable?\` can only switch filtering off; remove it or set it to \`false\`. | `filterable? true` on a field no filter is offered for. | Remove the option. |
| \`NAME\` is a calculation. Only an attribute can be edited, so a calculation column cannot have an \`update_action\`. | `update_action` on a calculation column. The same message exists for an aggregate. | Remove the option. |
| The resource has no action named \`ACTION\`. | The column's `update_action` names an action the resource does not have. The "not an update action" and "not public" messages of the table's action apply to a column's as well. | Correct the name. |
| The update action \`ACTION\` does not accept \`NAME\`, so it cannot save an edit of this column. | The column's action does not have the column's attribute in its `accept`. | Add the attribute to the action's `accept`, or name an action that has it. |
| The update action \`ACTION\` requires the argument \`ARG\`. An inline edit supplies only the cell's value, so the action behind a column must not need anything else. | The column's action has an argument with `allow_nil? false` and no default. | Use an action without such an argument for the cell. |
| \`NAME\` can never be edited, so \`confirm\` has no effect. A column is edited through an \`update_action\`, its own or the table's, that accepts its attribute. | `confirm` on a column that has no working update action: none at either level, `update_action false`, or a table action that does not accept the attribute. | Remove `confirm`, or make the column editable. |

Each finding is a warning of its own, so a block with three mistakes prints
three.

## What is not a mistake

Some things look like they should be reported and are not, on purpose:

| In the block | What happens |
| --- | --- |
| A table-level `update_action` that does not accept some columns' attributes | Those columns are read-only. |
| A table-level `update_action` with a required argument | No column is edited through it. |
| A column with an `update_action`, its own or the table's, whose type has no editor (a UUID, say) or whose attribute is not writable | The column is read-only. Nothing reports it, even for a column's own action. |
| `sortable? false` or `filterable? false` on a column that could not be sorted or filtered anyway | Nothing. |
| No `table` block | The default table. |

The table-level action is a blanket statement, "edit what this action can
edit", so what it cannot edit is not an error. A column's own action is a
statement about that column, so the action is held to it: it has to exist,
accept the attribute and need no argument. See
[Inline editing](inline-editing.md).

## If a finding is ignored

Because a finding is a warning, a resource with a mistake can be compiled
and its table opened. What happens then depends on the mistake:

| The mistake | At runtime |
| --- | --- |
| A wrong `read_action`, no primary read action, an unsupported `paginate_with` | The table raises `ArgumentError` when it is rendered: "cannot build the table of …". |
| A column that does not exist or is not public | The same. |
| A calculation column that requires an argument | The table is rendered, and every read fails with an error in place of the rows. |
| A wrong `update_action`, at the table or at a column | The columns concerned are read-only. |
| `sortable? true`, `filterable? true` or `confirm` without effect | Nothing. The option has no effect, as the message says. |

A table is also refused at runtime for a resource that does not list the
extension at all: "… does not list \`AshTable.Resource\` in its extensions,
so it has no table."

## Edge cases

- **A resource with the extension and no primary read action** is reported
  even though it has no `table` block. The extension alone gives the resource
  a table, and that table needs an action to read through.
- **A mistake in `read_action` hides findings that depend on it.** Whether
  `sortable? true` has an effect depends on the pagination strategy, so it is
  only checked once the read action and `paginate_with` are right.
- **`filterable? true` on a column whose type has no filter** is reported
  with the same message as on a field the resource declares unfilterable.
- **A private field that exists** gets the "is not public" message, and a
  name that is no field at all gets "has no attribute, calculation or
  aggregate". A relationship's name falls under the second.
- **The checks know nothing of people.** That a person can never see a
  column or never run an action is a matter of policies and is found out per
  request. See [Authorization](authorization.md).

## Things people trip over

- **"It compiled, so the block is right."** Look for warnings, or use
  `--warnings-as-errors`.
- **`mix format` adds parentheses to the block.** The formatter does not
  know the DSL: add `:ash_table` to `import_deps` in `.formatter.exs`. This
  is not a compile-time finding, but it shows up at the same moment.
- **Reading the message without the path.** The line above the message says
  which column and which option it is about.

## Not in the first version

The option `component`, for a column's own cell component, is planned and
not built; using it today is the "undefined function" error above. A warning
for a destroy action without `confirm` comes with row actions. See the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
