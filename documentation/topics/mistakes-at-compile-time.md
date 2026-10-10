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
cannot be behind a column, and no column of its table names it. The table
offers it as a row action instead, where the action panel asks for the
reason
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
mix compile --force --warnings-as-errors
```

Run this in CI. With it, every message in the tables below fails the build.

`--force` is part of it. A verifier's finding is printed, and counted as a
warning, only in the run that compiles the resource. Mix remembers an
ordinary compiler warning, such as an unused variable, and fails every later
`mix compile --warnings-as-errors` on it; it does not remember a verifier's
finding. This is what happens without `--force` (Elixir 1.19, Spark 2.7):

| Run | Result |
| --- | --- |
| `mix compile --warnings-as-errors` on a clean build, or after the resource's file changed | The finding is printed and the build fails. |
| The same command again, with nothing changed | Nothing is printed and the build passes. |
| `mix compile`, then `mix compile --warnings-as-errors` | The first prints the finding and passes. The second prints nothing and passes. |

So a CI job that builds from clean is safe with or without `--force`, and
one that restores `_build` from a cache is safe only with it.

### What is an error all the same

A block that is malformed, as opposed to wrong about its resource, is
rejected by Spark while the module is being compiled. That stops any build:

| Mistake | What the compiler says |
| --- | --- |
| A value an option does not take, such as `on_forbidden :hide` | `invalid value for :on_forbidden option: expected one of [:not_found, :message], got: :hide` |
| An option that does not exist, such as `width` on a column | `undefined function width/1 (there is no such import)` |
| An option of the wrong type, such as `label :title` | An "invalid value" error of the same kind. |

## The read action

The path of these findings is `table -> read_action`,
`table -> paginate_with`, or `table -> argument -> NAME` for the last one.
In the messages, capitals stand for a name from your block.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no action named \`NAME\`. | `read_action` names an action the resource does not have. | Correct the name, or define the action. |
| \`NAME\` is an update action, not a read action. | `read_action` names an action of another type (create, update, destroy or generic). | Name a read action. |
| The read action \`NAME\` is not public. Only \`public?\` actions can be behind a table. | The action is declared `public? false`. | Make it public, or name another. |
| The resource has no primary read action. Name the read action behind the table with \`read_action\`. | The block names no read action and the resource has no primary one. This is reported for a resource with no `table` block as well. | Add `read_action`, or mark a read action `primary? true`. |
| The read action \`NAME\` does not support keyset pagination. It supports: offset. | `paginate_with` names a strategy the action's `pagination` does not switch on. The end of the message says what the action supports, or "It has no pagination." | Change `paginate_with`, or add `keyset?: true` (or `offset?: true`) to the action's `pagination`. |
| The read action \`NAME\` requires the argument \`ARG\`, and a table has no input for its type (TYPE), so it could never read. The argument line has inputs for … Give the argument a default, or name another read action with \`read_action\`. | A public argument of the read action is `allow_nil? false`, has no default, and is a map, an embedded resource, a union or an array of such: nothing a person could give it with. | Give the argument a default, or put the table over another read action. |
| The read action \`NAME\` has no public argument named \`ARG\`. An \`argument\` says what an argument of the read action behind the table is called. | An `argument` of the block names something the read action does not take from the outside: no argument of it, or a private one. | Correct the name, or remove the `argument`. |

An argument of the read action needs no declaration to be on the
[argument line](arguments.md), and an optional one without an input is left
out without a finding.

## The table's update action

The path is `table -> update_action`, or `table` for the last one.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no action named \`NAME\`. | The table's `update_action` names an action the resource does not have. | Correct the name, or define the action. |
| \`NAME\` is a destroy action, not an update action. | It names an action of another type. | Name an update action. |
| The update action \`NAME\` is not public. Only \`public?\` actions can be behind a table. | The action is declared `public? false`. | Make it public, or name another. |
| The table has editable columns and shows calculations, aggregates or reference columns (\`NAME\`), but the resource has no primary read action. After a save the row is refreshed with those fields, which Ash loads through the primary read action. Mark a read action \`primary? true\`. | The table reads through a non-primary action named with `read_action`, at least one column can be edited, and at least one column is a calculation, an aggregate or a reference cell. | Mark a read action `primary? true`. |

The last one is about Ash and not about the table: `Ash.load/3`, and the
load of an update action's result, go through the primary read action, also
when another action is named. Without one, what a save did depended on the
data layer and on the field: with the in-memory data layer, a table with an
aggregate column saved nothing and said "This could not be saved.", and a
table with only an expression calculation saved, but answered a save that
changed nothing with "This record is no longer available." So the table does
not try: a resource compiled despite this finding has no table (see
[If a finding is ignored](#if-a-finding-is-ignored)).

## Columns

The path is `table -> column -> NAME`, followed by the option when the
finding is about one, and by `ask -> ARG` when it is about an `ask`. For a
column with `as`, `NAME` is that name.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no attribute, calculation, aggregate or belongs-to relationship named \`NAME\`. | A `column` names something the resource does not have: usually a typo. | Correct the name. |
| \`NAME\` is not public. Only \`public?\` fields can be columns of a table. | The field is private. | Make the field `public? true` if it may be shown, or leave the column out. |
| The calculation \`NAME\` requires the argument \`ARG\`, and the column gives it neither way. Fix it with \`arguments ARG: …\`, or let the person give it with \`ask :ARG, default: …\`. | The calculation has an argument with `allow_nil? false` and no default, and the column neither fixes nor asks for it. | Add `arguments` or `ask` to the column: see [Arguments](arguments.md#the-arguments-of-a-calculation). |
| The calculation \`NAME\` has no argument named \`ARG\`. | `arguments` or `ask` names an argument the calculation does not have. The path ends in `arguments`, or in `ask -> ARG`. | Correct the name. |
| \`VALUE\` is not a value of the argument \`ARG\` of the calculation \`NAME\`. | A value fixed with `arguments` is none of the argument's type, is refused by its constraints, or is `nil` for an argument that cannot be empty. | Give a value the argument takes. |
| \`VALUE\`, the default of \`ask :ARG\`, is not a value of the argument \`ARG\` of the calculation \`NAME\`. | The same for the `default` of an `ask`, when it is a value. A function is not looked at. | Give a value the argument takes. |
| The argument \`ARG\` of \`NAME\` is fixed with \`arguments\` and asked with \`ask\`. It is one or the other: to ask it and start with a value, say \`ask :ARG, default: …\`. | One argument is in both. | Keep one. |
| The argument \`ARG\` of \`NAME\` is asked more than once. | Two `ask` of one argument in one column. | Remove one. |
| The argument \`ARG\` of \`NAME\` is asked and cannot be empty, and has no default: neither on its \`ask\` nor in the resource. A column never starts without a value: say \`ask :ARG, default: …\`. | `ask` of an argument with `allow_nil? false` that has no `default`, on the `ask` or in the resource. | Give the `ask` a `default`: a value, or a function of the page's assigns. |
| The argument \`ARG\` of the calculation \`NAME\` cannot be asked: a table has no input for its type (TYPE). … Fix its value with \`arguments\` instead. | `ask` of an argument that is a map, an embedded resource, a union, or an array of such. | Fix it with `arguments`. |
| \`NAME\` is not a calculation. Only a calculation takes arguments. | `arguments` on a column of an attribute, an aggregate or a relationship. For `ask` the message ends "Only an argument of a calculation can be asked; an argument of the read action is on the argument line without a declaration.", and for `as` it reads "\`NAME\` is not a calculation, so \`as\` has no effect. …" | Remove the option. |
| \`AS\` is a field of the resource, so the column of \`NAME\` cannot be called that. \`as\` gives a column a name that nothing else has. | `as` is the name of an attribute, a calculation, an aggregate or a relationship of the resource. | Choose another name. |
| Got duplicate AshTable.Resource.Column: NAME | Two columns of one field without `as`, or two columns with the same `as`. | Give the second column of a calculation a name of its own with `as`. |
| \`NAME\` cannot be sorted, so \`sortable? true\` has no effect. \`sortable?\` can only switch sorting off; remove it or set it to \`false\`. | `sortable? true` on a field the resource does not allow to be sorted. Under keyset pagination the message says "cannot be sorted with keyset pagination". | Remove the option. To sort by a calculation or an aggregate, page by offset. |
| \`NAME\` cannot be filtered, so \`filterable? true\` has no effect. \`filterable?\` can only switch filtering off; remove it or set it to \`false\`. | `filterable? true` on a field no filter is offered for. | Remove the option. |
| \`NAME\` is a calculation. Only an attribute can be edited, so a calculation column cannot have an \`update_action\`. | `update_action` on a calculation column. The same message exists for an aggregate. | Remove the option. |
| The resource has no action named \`ACTION\`. | The column's `update_action` names an action the resource does not have. The "not an update action" and "not public" messages of the table's action apply to a column's as well. | Correct the name. |
| The update action \`ACTION\` does not accept \`NAME\`, so it cannot save an edit of this column. | The column's action does not have the column's attribute in its `accept`. | Add the attribute to the action's `accept`, or name an action that has it. |
| The update action \`ACTION\` requires the argument \`ARG\`. An inline edit supplies only the cell's value, so the action behind a column must not need anything else. | The column's action has an argument with `allow_nil? false` and no default. | Use an action without such an argument for the cell. |
| \`NAME\` has the type \`TYPE\`, which a table has no editor for, so the column is read-only and its \`update_action\` has no effect. A table edits text, numbers, booleans, dates, datetimes and enums, arrays of those, and embedded resources and maps whose fields are of those. Remove \`update_action\` from this column. | The column has its own `update_action`, and its type is one a table shows as read-only text: a UUID, a time, a union, an array of such values and so on. `TYPE` is the Ash type, such as `Ash.Type.UUID` or `{:array, Ash.Type.UUID}`. | Remove the option. |
| \`NAME\` has the type \`TYPE\`, which a table edits field by field, and here it cannot, so the column is read-only and its \`update_action\` has no effect. REASON Remove \`update_action\` from this column. | The column has its own `update_action`, and is an embedded resource, a map, or an array of either that a table cannot edit. `REASON` says what stands in the way: the map declares no `fields`; a field has a type a table has no control for; the embedded resource's create and update actions accept different attributes; or one of them requires an argument or a private attribute. See [Maps and embedded resources](maps-and-embedded-resources.md#what-can-be-edited). | Remove the option, or change what stands in the way. |
| \`NAME\` is declared \`writable?: false\`, so no action can save an edit of it: the column is read-only and its \`update_action\` has no effect. Remove \`update_action\` from this column, or make the attribute writable. | The column has its own `update_action`, and its attribute is `writable?: false`. | Remove the option, or make the attribute writable. |
| \`NAME\` can never be edited, so \`confirm\` has no effect. A column is edited through an \`update_action\`, its own or the table's, that accepts its attribute. | `confirm` on a column that has no working update action: none at either level, `update_action false`, or an action that does not accept the attribute or needs an argument. | Remove `confirm`, or make the column editable. |
| \`NAME\` can never be edited, so \`confirm\` has no effect. It has the type \`TYPE\`, which a table has no editor for. | `confirm` on a column whose type has no editor, whichever action is behind it. For an attribute that is not writable the second sentence is "Its attribute is declared \`writable?: false\`." | Remove `confirm`. |

A column whose type has no editor or whose attribute is not writable gets
one of the two messages about that, and not the ones about what its action
accepts or needs: no action could save it.

### A column that names a relationship

A column that names a belongs-to relationship is a reference cell: it shows
the related record's label. The path is the column's, as above. `NAME` is
the relationship and `DESTINATION` its destination resource.

| Message | Cause | Fix |
| --- | --- | --- |
| \`NAME\` is a has-many relationship. Only a belongs-to relationship can be a column: its cell shows the label of the one related record. Offer this one under the row with \`relationship :NAME\`. | The column names a has-many, a has-one or a many-to-many; the message says which. | Remove the column. The related records are a nested table under the row. |
| The destination of \`NAME\`, DESTINATION, has no table: it does not list \`AshTable.Resource\` in its extensions. A column that names a relationship shows the related record's label, which the destination's table declares with \`label_field\`. | The destination resource does not list the extension. | Add the extension and a `label_field` to the destination, or show the foreign key attribute. |
| The destination of \`NAME\`, DESTINATION, declares no \`label_field\`. A column that names a relationship shows the related record's label: add \`label_field\` to the \`table\` block of DESTINATION. | The destination has a table, and its block names no `label_field`. | Add `label_field` there. |
| The destination of \`NAME\`, DESTINATION, has no primary read action, and the relationship names no \`read_action\`. The related record of a column is read as Ash loads the relationship, which needs one of the two. | Neither is there. | Mark a read action of the destination `primary? true`, or give the relationship a `read_action`. |
| \`NAME\` shows the label of a related record, which a table does not sort by, so \`sortable? true\` has no effect. \`sortable?\` can only switch sorting off; remove it or set it to \`false\`. | `sortable? true` on a reference cell. | Remove the option. |
| \`NAME\` shows the label of a related record, which a table does not filter by, so \`filterable? true\` has no effect. \`filterable?\` can only switch filtering off; remove it or set it to \`false\`. | `filterable? true` on a reference cell. | Remove the option. |
| The update action \`ACTION\` does not accept \`KEY\`, the foreign key of \`NAME\`, and has no argument that a \`manage_relationship\` change hands to \`NAME\`, so it cannot save an edit of this column. | The column's own `update_action` neither has the relationship's foreign key (its `source_attribute`) in its `accept`, nor an argument that it hands to the relationship. A reference cell is edited by choosing another related record, which the action takes one of the two ways. | Add the key to the action's `accept`, or name an action that takes the record. |
| The update action \`ACTION\` hands its argument \`ARG\` to \`NAME\` as a list of keys. A cell holds one related record, and an edit of this column gives the action one key: the argument has to hold one key, not a list. | The column's own `update_action` takes the related record through an argument of an array type. | Give the argument the key's type (`:uuid`), or name another action. |
| The update action \`ACTION\` hands its argument \`ARG\` to \`NAME\`, and does not relate the record the argument names: its \`manage_relationship\` change has no \`on_lookup\` (\`type: :append\` and \`type: :append_and_remove\` have one). An edit of this column chooses another record, which the action has to relate. | The change is `type: :remove`, or names options of its own without `on_lookup`. | Use `type: :append_and_remove`, or `:append`. |
| The update action \`ACTION\` hands its argument \`ARG\` to \`NAME\`, and the argument does not hold the key of a related record: … A table edits a relationship by choosing an existing record, whose key it gives the action, so it cannot save an edit of this column. | The argument is a map (a record to create or to change), or of a type that is not stored as the destination's key is; or the destination has no one attribute to name a record by: a primary key of several attributes, and no `value_is_key` on the change. The part in between says which. | Give the argument the key's type; for a destination with a key of several attributes, name the attribute with `value_is_key`. |
| \`NAME\` is edited by choosing a record of the destination's table, and there is nothing to choose it with, so the column is read-only and its \`update_action\` has no effect. … Remove \`update_action\` from this column. | The column has its own `update_action`, and its related record cannot be chosen. The sentence in between says why: the relationship has a `filter`; the records to choose from would be read through an action that is not a public read action; or the action accepts the foreign key, which is not public (`attribute_public? false`) or not writable (`attribute_writable? false`), and has no argument that takes the record. | Remove the option; for a key that is not set from the outside, name an action that takes the record through an argument. |
| \`NAME\` can never be edited, so \`confirm\` has no effect. A column that names a relationship is edited through an \`update_action\`, its own or the table's, that accepts the relationship's foreign key, \`KEY\`, or has an argument that a \`manage_relationship\` change hands to the relationship. | `confirm` on a reference cell that no update action saves: none at either level, `update_action false`, or an action that takes the record neither way or needs another argument. | Remove `confirm`, or make the column editable. |
| \`NAME\` can never be edited, so \`confirm\` has no effect. The relationship \`NAME\` has a \`filter\`, so a table cannot say which records it can hold, and offers none to choose from. | `confirm` on a reference cell whose related record cannot be chosen, whichever action is behind it. The second sentence says why, as above. | Remove `confirm`. |

The messages about the name of a column's `update_action` and about an
argument it requires, in the table above, apply to a reference cell as they
are. The argument through which the action takes the related record is the
one an edit gives, and is no argument it lacks. Under the table's
`update_action`, a reference cell whose related record that action does not
take, or whose related record cannot be chosen, is read-only without a
finding. See
[Choosing a related record](choosing-a-related-record.md#which-reference-cells-are-edited)
and
[Relationships an action manages](managing-relationships.md#a-reference-cell-that-is-edited-through-an-argument).

A private relationship gets the "is not public" message of a private field.

## A column's component

The path is `table -> column -> NAME -> component`. `MODULE` is the module
the option names. See [Custom components](custom-components.md).

| Message | Cause | Fix |
| --- | --- | --- |
| The component \`MODULE\` cannot be found: there is no module of that name. | `component` names a module that does not exist: a typo, an alias that is not in scope in the resource, or a module that was renamed. | Correct the name. Write the module's whole name, or `alias` it in the resource. |
| \`MODULE\` is not a component: it does not implement the behaviour \`AshTable.Component\`. Add \`use AshTable.Component\` to it and define \`cell/1\`, \`editor/1\` or both. | The module exists and is something else: a LiveComponent, a module of function components without the behaviour. | Add `use AshTable.Component` to it. |
| The component \`MODULE\` defines neither \`cell/1\` nor \`editor/1\`, so it changes nothing. | A module that declares the behaviour by hand (`@behaviour AshTable.Component`) and has neither part. With `use AshTable.Component` this is an error of that module's own compile: see below. | Define one of the two. |
| The component \`MODULE\` only edits (it has no \`cell/1\`), and \`NAME\` can never be edited, so the component is never used. A column is edited through an \`update_action\`, its own or the table's, that accepts its attribute. | A component with `editor/1` alone, such as `AshTable.Components.Slider`, on a column nobody can edit. The last sentence says why, as for `confirm`: no action, a type without an editor, or "Its attribute is declared \`writable?: false\`." | Make the column editable, or remove `component`. |
| \`NAME\` shows the label of a related record. A reference cell has no component: remove \`component\` from this column. | `component` on a column that names a relationship. | Remove the option. |
| The component \`AshTable.Components.Slider\` cannot be used on \`NAME\`: a slider needs a number with a minimum and a maximum. Declare both on the attribute: \`constraints min: 0, max: 100\`. | The slider on a number whose constraints lack `min`, `max` or both. `AshTable.Components.Progress` says the same of "a progress bar". | Add the constraints to the attribute. |
| The component \`AshTable.Components.Slider\` cannot be used on \`NAME\`: a slider needs a number with a minimum and a maximum, and this field is shown as text. | The slider, or the progress bar, on a field that is no number. The end of the message says what the field is shown as: text, a boolean, a date, a date and time, a choice or read-only text. | Use it on a number, or remove `component`. |
| The component \`AshTable.Components.Badge\` cannot be used on \`NAME\`: a badge shows the label of a choice, and this field is shown as a number. It needs an \`Ash.Type.Enum\`, or an \`:atom\` with \`constraints one_of: [...]\`. | The badge on a field that is no enum. | Use it on an enum, or remove `component`. |

The last three are what the three shipped components say of themselves. A
component of your own says what it needs in the same place, with the same
first half of the message: "The component \`MODULE\` cannot be used on
\`NAME\`: " and then what its `verify/1` returned.

A component with both parts on a column that can never be edited is not
reported: its `cell/1` is used there, and the same module may edit another
column.

### The component's own compile

`use AshTable.Component` checks the module that uses it, and these are
errors of that module, which stop the build:

| Message | Cause |
| --- | --- |
| MODULE uses AshTable.Component and defines neither \`cell/1\` nor \`editor/1\`. A component shows a cell's value (\`cell/1\`), edits it (\`editor/1\`), or both. | The module has neither function. |
| MODULE: \`commit\` says when the editor saves, and is \`:enter\` (on Enter or on leaving the cell, the default) or \`:change\` (when the value changes). Got: :blur | `use AshTable.Component, commit:` with another value. |
| MODULE: \`commit: :change\` says when the editor saves, and the module defines no \`editor/1\`. | `commit: :change` on a component that only shows. |

### When a component changes after the resource was compiled

A resource does not depend on the component it names: the option is read
without a compile-time dependency from the data layer to the web layer, and
the component is looked at once the whole application is compiled. So a
change to the component alone does not compile the resource again, and the
findings above are not looked for again either. This is what happens when a
component is renamed and the resource still names the old one (Elixir 1.19,
Spark 2.7):

| Run | Result |
| --- | --- |
| `mix compile`, after the component's file changed | Nothing is printed: the resource is not compiled again. |
| Opening the table | It refuses to render: "cannot build the table of … the \`component\` of its column \`NAME\` cannot be used. The component \`MODULE\` cannot be found: there is no module of that name." |
| `mix compile --force`, or a build from clean | The finding is printed, and fails the build with `--warnings-as-errors`. |

## `label_field`

The path is `table -> label_field`.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no attribute named \`NAME\`. | `label_field` names something the resource does not have. | Correct the name. |
| \`NAME\` is not public. Only a \`public?\` attribute can be the label of a record. | The attribute is private. | Name a public attribute. |
| \`NAME\` is a relationship. The label of a record is one of its own attributes: name an attribute of this resource. | `label_field` names a relationship. | Name an attribute. |
| \`NAME\` is a calculation. The label of a record has to be an attribute: it is read with the record's key and nothing else. | `label_field` names a calculation, or an aggregate ("is an aggregate"). | Name an attribute. |

## Relationships

The path is `table -> relationship -> NAME`.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no relationship named \`NAME\`. | A `relationship` names something that is no relationship of the resource. | Correct the name. |
| \`NAME\` is not public. Only \`public?\` relationships can be offered by a table. | The relationship is private. | Make it `public? true` if its records may be shown, or leave it out. |
| The destination of \`NAME\`, DESTINATION, has no table: it does not list \`AshTable.Resource\` in its extensions. A row can only be expanded into the table of a resource that has one. | The destination resource does not list the extension. | Add the extension to the destination, or leave the relationship out. |
| Got duplicate AshTable.Resource.Relationship: NAME | The block declares the same `relationship` twice. This one is Spark's, with the path `table -> NAME`. | Declare it once. |

With no `relationship` declared, a relationship whose destination has no
table is simply not offered: nothing is reported.

## Row actions and the create action

The path is `table -> action -> NAME` for an `action`, which is a row
action or a table action, `table -> create_action` for the create action,
and `table` for the last two. `INPUT` is an attribute the action accepts
or one of its arguments, and `ARG` the argument `record_argument` names.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no action named \`NAME\`. | An `action`, or `create_action`, names an action the resource does not have. | Correct the name, or define the action. |
| The action \`NAME\` is not public. Only \`public?\` actions can be behind a table. | The action is declared `public? false`. | Make it public, or leave it out. |
| \`NAME\` is a create action. An \`action\` of a table is an update or a destroy action, which runs on the record of a row, or a generic action, which runs on the table as a whole. A create action is offered with \`create_action :NAME\` in the \`table\` block. | An `action` names a create action. | Name it with `create_action`. |
| \`NAME\` is a read action. An \`action\` of a table is an update or a destroy action, which runs on the record of a row, or a generic action, which runs on the table as a whole. | An `action` names a read action. | Remove it. |
| Got duplicate AshTable.Resource.Action: NAME | The block declares the same `action` twice. This one is Spark's, with the path `table -> NAME`. | Declare it once. |
| The row action \`NAME\` cannot be run from a table: its input \`INPUT\` is required, and a table has no field for its type (TYPE). The action panel has fields for text, numbers, booleans, dates, datetimes, choices, arrays of those, values written as one line of text, such as a key, and for embedded resources and maps whose every field is one of these. | The action accepts an attribute it requires, or has an argument with `allow_nil? false`, of a type the action panel has no field for: a map that declares no fields, an embedded resource a table cannot edit, a union, a binary, or an array of anything but text, numbers, booleans, dates, datetimes and choices. `TYPE` is the Ash type, such as `Ash.Type.Map` or `{:array, Ash.Type.UUID}`. | Use an action that does not require the input, or leave the action out. |
| The row action \`NAME\` cannot be run from a table: its argument \`INPUT\` is required, and holds the keys of the records of \`RELATIONSHIP\`. A table has a field for a list of keys only where the records can be chosen from the related resource's own table, and here they cannot. … | The action has a required argument that a `manage_relationship` change hands to a relationship as a list of keys, and the records of that relationship cannot be chosen. The last sentence says why: the relationship is not public, is manual, or has a `filter`; its destination has no table; the records to choose from, or those that are related now, would be read through an action that is not a public read action; the change would make a record for a key that names none (`type: :direct_control`); or the relationship holds one record. The same message exists for the create action. | Make the relationship `public? true` and give its destination a table, or leave the action out. See [Relationships an action manages](managing-relationships.md#which-arguments-are-chosen). |
| The row action \`NAME\` says \`bulk? true\`, and cannot run on several records at once: it accepts \`INPUT\`, of which no two records can hold the same value (an attribute of the primary key, or an identity by itself), and the inputs of an action that runs on the selected rows are given once for all of them. Leave \`bulk?\` out: the action stays an action of one row. | An `action` says `bulk? true` and accepts an attribute of the primary key, or one that is the only key of an identity. `bulk?` can only switch off. | Remove `bulk? true`. The action is a row action, and is not offered for a selection. |
| The table action \`NAME\` cannot be run from a table: its input \`INPUT\` is required, and a table has no field for its type (TYPE). The action panel has fields for … | As for a row action, for a generic action: one of its arguments is `allow_nil? false` and of a type without a field. The argument `record_argument` names is given by the table and needs none. | Use an action that does not require the argument, or leave the action out. |
| The table action \`NAME\` says \`bulk? true\`, and runs on the table as a whole: a generic action takes no record, so there are no selected rows to run it on. Leave \`bulk?\` out, or name the argument that takes a row's primary key with \`record_argument\`: the action is then a row action. | An `action` that names a generic action says `bulk? true` and no `record_argument`. | Remove `bulk? true`, or add `record_argument`. |
| The action \`NAME\` says \`record_argument :ARG\`, and is an update action, which runs on the record of its row already. \`record_argument\` is for a generic action, which takes no record: it names the argument that is given the row's primary key. Leave it out. | `record_argument` on an update or a destroy action: the message says "an update" or "a destroy". | Remove `record_argument`. |
| The action \`NAME\` says \`record_argument :ARG\`, and has no argument named \`ARG\`. | The generic action has no such argument. | Correct the name, or give the action the argument. |
| The action \`NAME\` says \`record_argument :ARG\`, and its argument \`ARG\` is not public. A private argument is not given from the outside, and a table is the outside. | The argument is declared `public? false`. | Make the argument public. |
| The action \`NAME\` says \`record_argument :ARG\`, and that argument is of the type TYPE, which is not stored as the primary key \`KEY\` is (KEY_TYPE). The argument is given the primary key of the row as it is, so it has to be of the key's type. | The argument's type is stored differently from the primary key: an integer for a UUID key, text, an array. Two types that are stored alike (`:uuid` and `:uuid_v7`) are accepted. | Give the argument the key's type. |
| The action \`NAME\` says \`record_argument :ARG\`, and the primary key of the resource is \`A\`, \`B\`: several attributes. One argument takes the primary key of a row only where that is one attribute. | The resource has a primary key of several attributes. | Leave the action out of the table, or declare it without `record_argument`, as a table action whose panel asks for the keys. |
| The action \`NAME\` says \`record_argument :ARG\`, and the resource has no primary key: there is nothing of a row to give the argument. | The resource has no primary key. | The same. |
| \`NAME\` is an update action, not a create action. | `create_action` names an action of another type: the message says "an update", "a destroy", "a read" or "a generic". | Name a create action. |
| The create action \`NAME\` cannot be run from a table: its input \`INPUT\` is required, and a table has no field for its type (TYPE). The action panel has fields for … | As for a row action. An attribute whose default is computed does not count as required in a create. | Name a create action that does not require the input. |
| The table changes records: it has editable columns, row actions or a create action. Ash loads what a create, an update or a destroy action returns through the primary read action, without arguments, and the primary read action \`NAME\` requires the argument \`ARG\`, so a row could not be shown again after one. Give the argument a default, make another read action the primary one, or leave the table read-only. | The primary read action has an argument with `allow_nil? false` and no default, the table edits, acts or creates, and one of its columns is a calculation, an aggregate or a reference cell. | Put the argument on a read action of its own and name it with `read_action`, or give it a default. |
| The table has row actions or a create action and shows calculations, aggregates or reference columns (\`NAME\`), but the resource has no primary read action. After an action the row is shown with those fields, which Ash loads through the primary read action. Mark a read action \`primary? true\`. | The table reads through a non-primary action named with `read_action`, has an `action` or a `create_action`, and at least one column is a calculation, an aggregate or a reference cell. A table that has editable columns as well gets the finding about those instead. | Mark a read action `primary? true`. |

An input of a type without a field that the action does **not** require is
no finding: it is left out of the panel. Which types have a field, and what
counts as required, is in
[Row actions and create](row-actions-and-create.md#the-fields-of-the-panel).

### A destroy action without `confirm`

One finding about a row action is not a mistake. A destroy action that
names no `confirm` deletes its record at one click, and the block may mean
that. So it is a plain warning, with the line of the action and without the
path. This is the output of the compiler for a sketch, a resource whose
block says `action :destroy` and nothing more about it (the path of the
file is shortened):

<!-- sketch -->
```text
warning: The row action `destroy` is a destroy action without `confirm`: one click on its button deletes the record, and nothing asks first. Give it a question (`confirm "Delete this record?"`), or say that a delete in one click is meant with `confirm false`.
    │
 18 │     action :destroy
    │     ~~~~~~~~~~~~~~~
    │
    └─ lib/sketch/task.ex:18: (file)
```

It is answered in the block, in one of two ways. Both are in the demo, which
therefore compiles without it: a question on the tasks' action, and
`confirm false` on the task labels'
([`demo/lib/demo/tracker/task_label.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task_label.ex)):

<!-- source: demo/lib/demo/tracker/task_label.ex -->
```elixir
action :destroy do
  label "Remove"
  confirm false
end
```

`--warnings-as-errors` fails on this warning like on every other finding.
An update action is never warned about.

## A private action

A table runs only actions that the resource declares `public?`, however it
came by them. The reason, and the list of the actions a table runs, are in
[Authorization](authorization.md#every-action-a-table-runs-is-public). An
action that the block names itself gets one of the "is not public" messages
of the sections above. The findings here are about an action that the
block does not name, and that a table would run all the same.

The example is a sketch again: a folder whose rows offer two relationships
to its papers. The second reads through an action of the papers that is
`public? false`.

<!-- sketch -->
```elixir
defmodule Sketch.Folder do
  use Ash.Resource,
    domain: Sketch.Vault,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTable.Resource]

  table do
    column :name

    relationship :papers
    relationship :all_papers
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    has_many :papers, Sketch.Paper, public?: true

    has_many :all_papers, Sketch.Paper do
      read_action :internal
      public? true
    end
  end
end
```

Compiling it prints this (the output of the compiler for exactly this file,
with the stack trace that follows the message left out):

<!-- sketch -->
```text
warning: ** (Spark.Error.DslError) [Sketch.Folder]
table -> relationship -> all_papers defined in lib/sketch/folder.ex:11::
  `all_papers` points to Sketch.Paper, whose read action `internal`, the relationship's own `read_action`, is not public. A table only runs `public?` actions: a private action is not meant for interfaces, and may be exempt from policies. Make `internal` public, give the relationship a public `read_action`, or do not offer `all_papers` in this table.

    │
 11 │     relationship :all_papers
    │     ~~~~~~~~~~~~~~~~~~~~~~~~
    │
    └─ lib/sketch/folder.ex:11: (file)
```

Every message of this section says in one sentence why, and then the ways
out. `ACTION` is the private action and `DESTINATION` or `RESOURCE` the
resource it is an action of: the destination of the relationship, or a
resource Ash reads on the way to it.

| Path | Message | Cause | Fix |
| --- | --- | --- | --- |
| `table -> read_action` | The primary read action \`ACTION\` is not public, and the table names no \`read_action\`, so it would read through it. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, or name a public read action with \`read_action\`. | The block names no read action, and the primary read action of the resource is `public? false`. This is reported for a resource with no `table` block as well. | Add `read_action` with a public read action, or make the primary one public. |
| `table -> relationship -> NAME` | \`NAME\` points to DESTINATION, whose read action \`ACTION\`, the relationship's own \`read_action\`, is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, give the relationship a public \`read_action\`, or do not offer \`NAME\` in this table. | A declared `relationship` whose `read_action` on the resource is private. A nested table runs that action. | One of the three the message names. |
| `table -> relationship -> NAME` | \`NAME\` points to DESTINATION, whose read action \`ACTION\`, the one behind its table, is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, name a public \`read_action\` in the \`table\` block of DESTINATION or on the relationship, or do not offer \`NAME\` in this table. | A declared `relationship` that names no `read_action`, to a destination whose own table would read through a private action. That table has the first finding of this section itself. | Settle the destination's finding, or one of the others the message names. |
| `table -> column -> NAME` | \`NAME\` points to DESTINATION, whose read action \`ACTION\`, its primary read action, is not public. The related record of a column is read as Ash loads the relationship. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, give the relationship a public \`read_action\`, or do not show \`NAME\` as a column. | A reference cell whose relationship names no `read_action`, to a destination whose primary read action is private. The read action of the destination's table does not come into it. Where the relationship names a private action itself, the message says "the relationship's own \`read_action\`". | Give the relationship a `read_action` that is public, make the action public, or remove the column. |
| `table -> relationship -> NAME` | \`NAME\` is read through the join resource RESOURCE, whose read action \`ACTION\`, its primary read action, is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, give the join relationship \`JOIN\` a public \`read_action\`, or do not offer \`NAME\` in this table. | A declared many-to-many. Ash reads the join resource on the way to the related records, through the `read_action` of the join relationship, else the join resource's primary read action, and its policies say which records are related at all. Where the join relationship names a private action itself, the message says "the \`read_action\` of the join relationship \`JOIN\`". | Give the join relationship a public `read_action`, make the action public, or leave the relationship out. |
| `table -> relationship -> NAME` | \`NAME\` is read through RESOURCE, a resource on its \`through\` path, whose read action \`ACTION\`, the one Ash reads it through there, is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, or do not offer \`NAME\` in this table. | A declared relationship `through` a path of others. Ash reads every resource the path passes through its primary read action. | Make the action public, or leave the relationship out. |
| `table -> column -> NAME` | The aggregate \`NAME\` reads DESTINATION through \`ACTION\`, its primary read action, which is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, give the aggregate a public \`read_action\`, or do not show \`NAME\` as a column. | An aggregate column over a resource whose primary read action is private, without a `read_action` of its own. For one that names a private action itself the message says "the aggregate's own \`read_action\`". | Give the aggregate a public `read_action`, make the action public, or remove the column. |
| `table -> column -> NAME` | The aggregate \`NAME\` reads DESTINATION through \`ACTION\`, the \`read_action\` of the relationship \`RELATIONSHIP\`, which is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, give the relationship a public \`read_action\`, or do not show \`NAME\` as a column. | An aggregate column over a relationship that names a private `read_action`: Ash filters what the aggregate reads by that action's policies, also where the aggregate names a public action of its own. | Give the relationship a public `read_action`, make the action public, or remove the column. |
| `table -> column -> NAME` | The aggregate \`NAME\` reads RESOURCE through \`ACTION\`, its primary read action, which is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, give the relationship \`RELATIONSHIP\` a public \`read_action\`, or do not show \`NAME\` as a column. | An aggregate column over a path of several relationships (`[:boxes, :papers]`), where a resource in between is read through its private primary read action. Ash applies the policies of every resource of the path. | Give that relationship a public `read_action`, make the action public, or remove the column. |
| `table -> column -> NAME` | The aggregate \`NAME\` reads RESOURCE through \`ACTION\`, its primary read action, as the join resource of \`RELATIONSHIP\`, which is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, give the join relationship \`JOIN\` a public \`read_action\`, or do not show \`NAME\` as a column. | An aggregate column over a many-to-many whose join resource Ash reads through a private action. | Give the join relationship a public `read_action`, make the action public, or remove the column. |
| `table -> column -> NAME` | The calculation \`NAME\` is computed from the aggregate \`AGGREGATE\`: it reads DESTINATION through \`ACTION\`, the aggregate's own \`read_action\`, which is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, give the aggregate a public \`read_action\`, or do not show \`NAME\` as a column. | A calculation column whose expression holds an aggregate that Ash reads through a private action: one of the resource by its name, one written out (`AGGREGATE` is then the expression, such as \`count(all_papers)\`), or one inside a calculation the expression references. What follows "through" is worded as for an aggregate column. The same wording is used for an aggregate column over a field that is itself such an aggregate. | Settle the aggregate as its part of the message says, or remove the column. |
| `table` | The table changes records: it has editable columns, row actions or a create action. Ash loads what a create, an update or a destroy action returns through the primary read action, and the primary read action \`ACTION\` is not public. A table only runs \`public?\` actions: a private action is not meant for interfaces, and may be exempt from policies. Make \`ACTION\` public, or leave the table read-only: without \`update_action\`, \`action\` and \`create_action\`. | The table names a public `read_action`, the primary read action of the resource is private, and the table has an editable column, an `action` or a `create_action`. | Make the primary read action public, or take the three options out of the block. |

A relationship that leads to a private read action is only reported when
the block declares it. With no `relationship` in the block it is left out
of the default set and nothing is reported, as for a relationship whose
destination has no table. A reference cell, an aggregate column and a
calculation column are always declared, and so always reported.

A calculation is looked into as far as it is an expression. One computed in
Elixir is not, and what an expression references without an aggregate
(`exists(papers, …)`, `folder.name`) runs no action: Ash applies no policy
to it. See
[Authorization](authorization.md#what-it-does-not-reach).

The last finding is about Ash and not about the table, as the one about a
missing primary read action is. No option of a create, an update or a
destroy says through which read action its result is loaded, so a table
that runs such an action cannot keep Ash from the primary one. In one of
the demo's tests the private primary read action is exempt from the
resource's field policies as well, and its update action changes a field
that the page hides: without this finding, the row that was saved shows
that field's new value.

## Warnings about what a column shows

Two more findings are not mistakes in the block. The resource may mean what
it says, so they are plain warnings: the text below with the line of the
column, without the path and without the `Spark.Error.DslError` in front.
`--warnings-as-errors` fails on them like on the others. This is the output
of the compiler for a sketch:

<!-- sketch -->
```text
warning: The aggregate column `payroll` shows `salary` of Sketch.Member, which a field policy protects there, and Sketch.Team has no field policy for `payroll`. Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. Protect it with a field policy for `payroll` on Sketch.Team, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column.
    │
 48 │     column :payroll
    │     ~~~~~~~~~~~~~~~
    │
    └─ lib/sketch/team.ex:48: (file)
```

| Message | Cause | Answer |
| --- | --- | --- |
| The aggregate column \`NAME\` shows \`FIELD\` of DESTINATION, which a field policy protects there, and RESOURCE has no field policy for \`NAME\`. Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. Protect it with a field policy for \`NAME\` on RESOURCE, which needs \`Ash.Policy.Authorizer\` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with \`exposes_protected_field? true\` on the column. | An aggregate column over a field that a field policy protects on the related resource. For a field in the aggregate's own `filter` the first sentence says "counts by \`FIELD\` of DESTINATION in its \`filter\`". | A field policy for the aggregate, or `exposes_protected_field? true` on the column. |
| The calculation column \`NAME\` references \`FIELD\` of DESTINATION (through \`PATH\`), which a field policy protects there, and RESOURCE has no field policy for \`NAME\`. Ash applies no policy to what a calculation references: everyone who can read a row sees this column, and can sort and filter by it. Protect it … | A calculation column whose expression references a protected field of a related resource. For a field of the resource itself the first sentence says "references \`FIELD\`, which a field policy protects on this resource". The rest is as above. | The same. |
| The aggregate column \`NAME\` is a \`first\` aggregate over the one record of \`RELATIONSHIP\`, and the calculation column \`OTHER\` reaches through the same relationship. Read together through a SQL data layer, such an aggregate returns the value of a related record that the reader may not read (ash_table issue #32). The table therefore reads \`NAME\` apart from the rest of the row, and does not sort or filter by it. To have it read with the row again, and sorted and filtered by, take the aggregate out of the join the two share: give it a \`join_filter\` or a \`read_action\` of its own. To leave it at that, say \`sortable? false\` and \`filterable? false\` on the column. | A `first` aggregate column over a belongs-to, or over a has-one on a key of the destination, without `join_filter` and without `read_action`, beside an expression calculation column over the same relationship. | A `join_filter` or a `read_action` on the aggregate; or `sortable? false` and `filterable? false` on the column, which accepts what the table does. |

Both rules, and what the warnings cannot see, are in
[Columns and defaults](columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).

A resource with one finding prints it as in the example at the top, with the
line of the block. A resource with several prints them as one warning: the
line "Multiple Errors Occurred", then each finding with its own path, a line
of dashes between them, and no excerpt of the block.

## What is not a mistake

Some things look like they should be reported and are not, on purpose:

| In the block | What happens |
| --- | --- |
| A table-level `update_action` that does not accept some columns' attributes | Those columns are read-only. |
| A table-level `update_action` with a required argument | No column is edited through it. |
| A table-level `update_action` that accepts a column whose type has no editor (a UUID, say), or a table whose column is an attribute that is not writable | The column is read-only. For a column's own `update_action` the same is reported. |
| `sortable? false` or `filterable? false` on a column that could not be sorted or filtered anyway | Nothing. |
| No `table` block | The default table. |
| A public relationship whose destination has no table, in a block that declares no `relationship` | It is not offered. |
| A public relationship whose read action is private, or whose join resource's is, in a block that declares no `relationship` | It is not offered. Declared, it is reported. |
| An update action that is run over a private read action of its own (`atomic_upgrade_with`) | Nothing: what a public action does while it runs is the action's. |
| An attribute whose embedded resource is cast through a private action of that resource | Nothing, for the same reason: Ash runs it while it casts the value an action was given, whoever gave it. See [Maps and embedded resources](maps-and-embedded-resources.md#what-ash-does-with-the-value). |
| A table-level `update_action` that accepts an embedded resource or a map a table cannot edit | The column is read-only. For a column's own `update_action` the same is reported. |
| A private action that no table would run: no column, relationship or option of the block leads to it | Nothing. A resource may have as many as it likes. |
| `exposes_protected_field? true` on a column that exposes nothing | Nothing. |
| An action, or the create action, with an optional input of a type the panel has no field for | The input is left out of the panel. |
| A row action that accepts attributes that may all be empty | Its button opens the action panel. |
| `confirm false` on an update action | Nothing. An update action is not warned about in the first place. |
| A row action that accepts an attribute of the primary key, or one that is an identity by itself, without `bulk? true` | It is a row action, and is not offered for the selected rows. |
| `bulk? false` on an action that would not be offered for the selected rows anyway | Nothing. |
| `bulk? true` on an action that is offered anyway | Nothing: it is the default. |
| `bulk? false` on a table action | Nothing. A table action runs on no record. |
| A table whose only actions are generic, over a resource with a private primary read action, or with none beside loaded columns | Nothing. Ash loads no result of a generic action through it, and the table reads again through its own read action. |
| A generic action under a policy that has a check on a record | Nothing when the resource is compiled. Ash cannot run such an action, and the table has no button for it. See [Table actions](table-actions.md#edge-cases). |
| A `create_action` that does not accept the attribute joining its records to a parent | The table has its create button on a page of its own, and none where it is nested under that parent. |

The table-level action is a blanket statement, "edit what this action can
edit", so what it cannot edit is not an error. A column's own action is a
statement about that column, so it is held to it: the action has to exist,
accept the attribute and need no argument, and the column has to be one a
table can edit at all. See
[Inline editing](inline-editing.md).

## If a finding is ignored

Because a finding is a warning, a resource with a mistake can be compiled
and its table opened. What happens then depends on the mistake. Where the
table would have nothing sound to do, it refuses: it raises `ArgumentError`
when it is rendered, with a message that starts "cannot build the table of"
and names the resource and the cause. A mounted table's page then fails as
any LiveView does that raises in its first render.

| The mistake | At runtime |
| --- | --- |
| A wrong `read_action`: not there, not a read action, not public | The table refuses to render. |
| No primary read action, and no `read_action` | The same. |
| A private primary read action, and no `read_action` | The same: "its read action cannot be used." |
| An unsupported `paginate_with` | The same. |
| A column that does not exist or is not public | The same. |
| A column that names a relationship whose label cannot be shown: not a belongs-to, a destination without a table or without a usable `label_field` | The same. |
| A `relationship` that is no public relationship, or whose destination has no table | The same. |
| A `relationship` whose nested table would run a private read action | The same: "its relationship \`NAME\` cannot be offered." |
| A reference cell, an aggregate column, or a calculation column that holds an aggregate, that Ash reads through a private action | The same: "its column \`NAME\` cannot be shown." |
| Editable columns, row actions or a create action, over a private primary read action | The same. |
| A calculation column whose arguments are not given soundly: one it requires is missing, one is named that it does not have, a value is none of its type, one is fixed and asked, asked twice, or asked without a default it needs | The same: "its column \`NAME\` cannot be shown." |
| `arguments`, `ask` or `as` on a column that is no calculation | The same. |
| A read action that requires an argument the argument line has no input for | The same: "its read action cannot be used." |
| An `argument` that names no public argument of the read action | The table renders; the declaration has no effect. |
| A primary read action that requires an argument, under a table that changes records | The table renders. After a save or an action the row cannot be loaded again, and is taken out of the page as a record that is no longer the person's to read. |
| A wrong `update_action`, at the table or at a column: not there, not an update action, not public | The same. The block asked for editing through an action that cannot be run, and a table that silently offered none would hide that. |
| Editable columns beside calculation, aggregate or reference columns, without a primary read action | The same. |
| An `action` that names no public update, destroy or generic action, or one that is declared twice | The same: "its action \`NAME\` cannot be used." |
| A `record_argument` that cannot take a row's key, or one on an update or a destroy action | The same. |
| `bulk? true` on a table action | The table renders. The action is a table action, and is not offered for the selected rows. |
| A `create_action` that names no public create action | The same: "its \`create_action\` cannot be used." |
| Row actions or a create action beside calculation, aggregate or reference columns, without a primary read action | The same. |
| A row action or a table action with a required input the panel has no field for | The table renders, and has no button for that action. |
| A create action with a required input the panel has no field for | The table renders, and has no create button. |
| A destroy action without `confirm` | The table renders, and the button deletes at one click. |
| A `label_field` that names no public attribute | The table itself renders. A table that shows this resource in a reference cell refuses, and a heading that would call a record by it calls it by a column instead. |
| A warning about what a column shows | The table renders and shows the column: the first kind as Ash returns it, the second read apart and without its sort and filter. |
| A column's own `update_action` that exists but does not accept the attribute, or needs an argument | The column is read-only. |
| A column's own `update_action` on a calculation, an aggregate, a type without an editor or an attribute that is not writable | The column is read-only. |
| A `component` that cannot be found, is not a component, has neither part, or says that it cannot serve the column | The table refuses to render: "the \`component\` of its column \`NAME\` cannot be used." |
| A `component` that only edits, on a column that can never be edited | The table renders, and the component is not used. |
| A `component` on a column that names a relationship | The table renders, with the reference cell as it is without the option. |
| `sortable? true`, `filterable? true` or `confirm` without effect | Nothing. The option has no effect, as the message says. |

The line between the two groups is the one the table-level action draws
anyway: an action that exists and cannot save a column leaves that column
read-only, whoever named it. An action that cannot be run at all is refused.

A table is also refused at runtime for a resource that does not list the
extension at all: "… does not list \`AshTable.Resource\` in its extensions,
so it has no table."

A nested table is built from a relationship of the table around it, and
looks the relationship's read action up once more. A relationship that no
table built, or one built before the resource was compiled again, is
refused where its action is private or no read action at all: "cannot
build the nested table of …". No other action is read through in its
place.

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
  name that is nothing at all gets "has no attribute, calculation, aggregate
  or belongs-to relationship". A relationship of another kind gets the
  message that says which kind it is.
- **A finding about another resource can go stale.** Whether a destination
  has a table, a `label_field` or a field policy is looked up when the
  resource that names it is compiled. A later change to the destination does
  not compile that resource again, so its finding appears, or goes away, at
  the next full build: one more reason for `--force`. At runtime the table
  checks again.
- **The warning about a destroy action is not printed beside an error
  about the actions.** The verifier of the row actions reports its errors
  first: a block with a wrong `action` and a destroy action without
  `confirm` shows the error, and the warning once the error is gone.
- **The checks know nothing of people.** That a person can never see a
  column or never run an action is a matter of policies and is found out per
  request. See [Authorization](authorization.md).

## Things people trip over

- **"It compiled, so the block is right."** Look for warnings, or use
  `--force --warnings-as-errors`.
- **"CI is green with `--warnings-as-errors`, so there is no finding."** Not
  if CI reuses a `_build` in which the resource was already compiled. Add
  `--force`.
- **`mix format` adds parentheses to the block.** The formatter does not
  know the DSL: add `:ash_table` to `import_deps` in `.formatter.exs`. This
  is not a compile-time finding, but it shows up at the same moment.
- **Reading the message without the path.** The line above the message says
  which column and which option it is about.

## Not in the first version

Nothing checks what a component renders: that its editor holds a control
with `{@control}` on it, or that its cell stays one line high. Those are in
[Custom components](custom-components.md). The later slices are listed in
the [specification](https://github.com/StefanRoesch/ash_table/issues/21).
