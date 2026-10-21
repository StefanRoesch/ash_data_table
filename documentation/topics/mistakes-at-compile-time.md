# Mistakes at compile time

A `table` block is checked against its resource when the resource is
compiled. This guide lists each diagnostic with its cause and fix, and shows
how to make a build fail on them, which a plain `mix compile` does not.

In the tables, capitals stand for a name from your block. Where a message
column says "starts with", the rest of the message explains the cause and
the fix given beside it.

## The smallest example

The demo compiles without a finding, so this example is a sketch: a cut-down
copy of the demo's task whose column names an update action that needs an
argument.

<!-- sketch -->
```elixir
defmodule Sketch.Task do
  use Ash.Resource,
    domain: Sketch.Tracker,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

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

The compiler prints this (stack trace left out):

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

Line one names the resource; line two is the path to the option in the
block, with file and line; then the message.

The action is the demo's own. No column of the demo's task table names it;
the table offers it as a row action, whose panel asks for the reason
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

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

**Try it:** in the demo, add `column :due_within?` to the `table` block of
`Demo.Tracker.Task` and run `mix compile` in `demo/`. The calculation needs
the argument `days`, and the compiler says so. Take the line out again.

## Findings are warnings

A finding does not stop a plain `mix compile`: it is printed as a warning,
the build succeeds and the app starts.

That is how Spark works, not a choice of this library. The checks are Spark
verifiers, like those of Ash and every Ash extension. They run after the
module is compiled, in the phase where Elixir checks a module against the
rest of the project, and what they return is reported as warnings. In a
scrolling terminal they are easy to miss. In CI, fail the build on them:

<!-- sketch -->
```sh
mix compile --force --warnings-as-errors
```

With it, every message in this guide fails the build.

`--force` matters. A verifier's finding is printed, and counted as a
warning, only in the run that compiles the resource. Mix remembers an
ordinary compiler warning (an unused variable) and fails every later
`mix compile --warnings-as-errors` on it; it does not remember a verifier's
finding. Without `--force` (Elixir 1.19, Spark 2.7):

| Run | Result |
| --- | --- |
| `mix compile --warnings-as-errors` on a clean build, or after the resource's file changed | The finding is printed and the build fails. |
| The same command again, nothing changed | Nothing is printed; the build passes. |
| `mix compile`, then `mix compile --warnings-as-errors` | The first prints the finding and passes; the second prints nothing and passes. |

A CI job that builds from clean is safe either way; one that restores
`_build` from a cache is safe only with `--force`.

### What is an error all the same

A malformed block, as opposed to one that is wrong about its resource, is
rejected by Spark while the module compiles. That stops any build:

| Mistake | What the compiler says |
| --- | --- |
| A value an option does not take, such as `on_forbidden :hide` | `invalid value for :on_forbidden option: expected one of [:not_found, :message], got: :hide` |
| An option that does not exist, such as `width` on a column | `undefined function width/1 (there is no such import)` |
| An option of the wrong type, such as `label :title` | An "invalid value" error of the same kind. |

## The read action

Path: `table -> read_action`, `table -> paginate_with`, `table -> page_sizes`,
or `table -> argument -> NAME` for the last row.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no action named \`NAME\`. | `read_action` names an action the resource does not have. | Correct the name, or define the action. |
| \`NAME\` is an update action, not a read action. | `read_action` names a create, update, destroy or generic action. | Name a read action. |
| The read action \`NAME\` is not public. Only \`public?\` actions can be behind a table. | The action is `public? false`. | Make it public, or name another. |
| The resource has no primary read action. Name the read action behind the table with \`read_action\`. | No `read_action`, and no primary read action. Reported for a resource with no `table` block as well. | Add `read_action`, or mark a read action `primary? true`. |
| The read action \`NAME\` does not support keyset pagination. It supports: offset. | `paginate_with` names a strategy the action's `pagination` does not switch on. The message ends with what the action supports, or "It has no pagination." | Change `paginate_with`, or add `keyset?: true` (or `offset?: true`) to the action's `pagination`. |
| The read action \`NAME\` requires the argument \`ARG\`, and a table has no input for its type (TYPE), so it could never read. … | A public argument of the read action is `allow_nil? false`, has no default, and is a map, an embedded resource, a union or an array of such. | Give the argument a default, or put the table over another read action. |
| The read action \`NAME\` has no public argument named \`ARG\`. … | An `argument` of the block names no argument of the action, or a private one. | Correct the name, or remove the `argument`. |

An argument of the read action is on the [argument line](arguments.md)
without a declaration; an optional one without an input is left out, without
a finding.

### `page_sizes`

Path: `table -> page_sizes`. The read action sets what a page may hold and
the size a table opens with; `page_sizes` only says which sizes a person is
offered. See
[Reading, sorting and pagination](reading-sorting-and-pagination.md#letting-a-person-choose-the-page-size).

| Message starts with | Cause | Fix |
| --- | --- | --- |
| The read action \`NAME\` has no pagination, and a table without pages cannot offer page sizes. … | `page_sizes`, and the read action declares no `pagination`. | Add `pagination` to the action, or remove `page_sizes`. |
| 50 is more than \`max_page_size: 25\` of \`:NAME\`. A table offers no page that its read action does not allow. … | A size is above the action's `max_page_size` (Ash's default when none is named: 250). | Remove the size, or raise `max_page_size`. |
| The read action \`:NAME\` has \`default_limit: 25\`, and 25 is not one of the \`page_sizes\`. … | The action's `default_limit` is not in the list. A `default_limit` above `max_page_size` counts as the maximum, and the message says "capped at". | Add the size, or change `default_limit`. |
| \`page_sizes\` needs at least two sizes, got: [25]. One size is no choice. … | One size, or none. Without `page_sizes` the page size is the action's `default_limit`. | Add a size, or remove the option. |
| \`page_sizes\` names 10 more than once. | A size is listed twice. | Remove one. |
| invalid list in :page_sizes option: … expected positive integer, got: 0 | A size is no positive whole number. Spark's own error, whatever the warning setting. | Write positive whole numbers. |

An action without `default_limit` is no mistake: the table opens with the
first size as written.

## The table's update action

Path: `table -> update_action`, or `table` for the last row.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no action named \`NAME\`. | The table's `update_action` names no action of the resource. | Correct the name, or define the action. |
| \`NAME\` is a destroy action, not an update action. | It names an action of another type. | Name an update action. |
| The update action \`NAME\` is not public. Only \`public?\` actions can be behind a table. | The action is `public? false`. | Make it public, or name another. |
| The table has editable columns and shows calculations, aggregates or reference columns (\`NAME\`), but the resource has no primary read action. … | The table reads through a non-primary `read_action`, at least one column is editable, and at least one is a calculation, an aggregate or a reference cell. | Mark a read action `primary? true`. |

The last one is about Ash: `Ash.load/3`, and the load of an update action's
result, go through the primary read action even when another is named.
Without one, what a save did depended on the data layer and the field. With
the in-memory data layer, a table with an aggregate column saved nothing and
said "This could not be saved."; one with only an expression calculation
saved, but answered a save that changed nothing with "This record is no
longer available." So the table does not try: a resource compiled despite
this finding has no table (see [If a finding is ignored](#if-a-finding-is-ignored)).

## Columns

Path: `table -> column -> NAME`, then the option when the finding is about
one, or `ask -> ARG` for an `ask`. For a column with `as`, `NAME` is that
name.

| Message starts with | Cause | Fix |
| --- | --- | --- |
| The resource has no attribute, calculation, aggregate or belongs-to relationship named \`NAME\`. | Usually a typo. | Correct the name. |
| \`NAME\` is not public. Only \`public?\` fields can be columns of a table. | The field is private. | Make it `public? true` if it may be shown, or leave the column out. |
| The calculation \`NAME\` requires the argument \`ARG\`, and the column gives it neither way. … | An argument with `allow_nil? false` and no default, neither fixed nor asked. | Add `arguments ARG: …` or `ask :ARG, default: …`: see [Arguments](arguments.md#the-arguments-of-a-calculation). |
| The calculation \`NAME\` has no argument named \`ARG\`. | `arguments` or `ask` names an argument the calculation lacks. The path ends in `arguments` or `ask -> ARG`. | Correct the name. |
| \`VALUE\` is not a value of the argument \`ARG\` of the calculation \`NAME\`. | A value fixed with `arguments` is not of the argument's type, is refused by its constraints, or is `nil` where the argument cannot be empty. | Give a value the argument takes. |
| \`VALUE\`, the default of \`ask :ARG\`, is not a value of the argument … | The same for an `ask`'s `default` that is a value. A function is not looked at. | Give a value the argument takes. |
| The argument \`ARG\` of \`NAME\` is fixed with \`arguments\` and asked with \`ask\`. … | One argument is in both. To ask it with a starting value, use `ask :ARG, default: …`. | Keep one. |
| The argument \`ARG\` of \`NAME\` is asked more than once. | Two `ask` of one argument in one column. | Remove one. |
| The argument \`ARG\` of \`NAME\` is asked and cannot be empty, and has no default … | `ask` of an `allow_nil? false` argument with no `default` on the `ask` or in the resource. A column never starts without a value. | Give the `ask` a `default`: a value, or a function of the page's assigns. |
| The argument \`ARG\` of the calculation \`NAME\` cannot be asked: a table has no input for its type (TYPE). … | `ask` of a map, an embedded resource, a union, or an array of such. | Fix it with `arguments`. |
| \`NAME\` is not a calculation. Only a calculation takes arguments. | `arguments` on an attribute, aggregate or relationship column. For `ask` it ends "Only an argument of a calculation can be asked; an argument of the read action is on the argument line without a declaration."; for `as` it reads "\`NAME\` is not a calculation, so \`as\` has no effect. …" | Remove the option. |
| \`AS\` is a field of the resource, so the column of \`NAME\` cannot be called that. … | `as` is the name of an attribute, calculation, aggregate or relationship. | Choose another name. |
| Got duplicate AshDataTable.Resource.Column: NAME | Two columns of one field without `as`, or two with the same `as`. | Give the second column of a calculation its own name with `as`. |
| \`NAME\` cannot be sorted, so \`sortable? true\` has no effect. … | `sortable? true` on a field the resource does not allow to be sorted. Under keyset pagination: "cannot be sorted with keyset pagination". `sortable?` can only switch sorting off. | Remove the option. To sort by a calculation or an aggregate, page by offset. |
| \`NAME\` cannot be filtered, so \`filterable? true\` has no effect. … | `filterable? true` on a field no filter is offered for. `filterable?` can only switch filtering off. | Remove the option. |
| \`NAME\` is a calculation. Only an attribute can be edited, so a calculation column cannot have an \`update_action\`. | `update_action` on a calculation column; the same message exists for an aggregate. | Remove the option. |
| The resource has no action named \`ACTION\`. | The column's `update_action` names no action. The table's "not an update action" and "not public" messages apply to a column's action too. | Correct the name. |
| The update action \`ACTION\` does not accept \`NAME\`, so it cannot save an edit of this column. | The attribute is not in the action's `accept`. | Add it to `accept`, or name an action that has it. |
| The update action \`ACTION\` requires the argument \`ARG\`. An inline edit supplies only the cell's value, … | The column's action has an `allow_nil? false` argument with no default. | Use an action without such an argument. |
| \`NAME\` has the type \`TYPE\`, which a table has no editor for, so the column is read-only and its \`update_action\` has no effect. … | Its own `update_action` on a type shown as read-only text: a UUID, a time, a tuple, an array of such. `TYPE` is the Ash type (`Ash.Type.UUID`, `{:array, Ash.Type.UUID}`). A table edits text, numbers, booleans, dates, datetimes and enums, arrays of those, embedded resources and maps whose fields are of those, and unions whose kinds are. | Remove the option. |
| \`NAME\` has the type \`TYPE\`, which a table edits field by field, and here it cannot, … REASON … | Its own `update_action` on an embedded resource, a map, or an array of either that a table cannot edit. `REASON`: the map declares no `fields`; a field has a type without a control; the embedded resource's create and update actions accept different attributes; or one of them requires an argument or a private attribute. See [Maps and embedded resources](maps-and-embedded-resources.md#what-can-be-edited). | Remove the option, or change what stands in the way. |
| \`NAME\` has the type \`TYPE\`, a union, which a table edits kind by kind, and here it cannot, … REASON … | Its own `update_action` on a union a table cannot edit, or an array of unions. `REASON`: a kind has a type without a control in a union (an array, a tuple); a kind made of fields cannot be edited; the union declares no `types`; or it is an array of unions, which is shown, not edited. See [Unions](unions.md#what-can-be-edited). | Remove the option, or change what stands in the way. |
| \`NAME\` is declared \`writable?: false\`, so no action can save an edit of it: … | Its own `update_action` on an attribute that is `writable?: false`. | Remove the option, or make the attribute writable. |
| \`NAME\` can never be edited, so \`confirm\` has no effect. A column is edited through an \`update_action\`, its own or the table's, that accepts its attribute. | `confirm` on a column with no working update action: none at either level, `update_action false`, or one that does not accept the attribute or needs an argument. | Remove `confirm`, or make the column editable. |
| \`NAME\` can never be edited, so \`confirm\` has no effect. It has the type \`TYPE\`, which a table has no editor for. | `confirm` on a type with no editor, whatever the action. For an attribute that is not writable the second sentence is "Its attribute is declared \`writable?: false\`." | Remove `confirm`. |
| \`max_lines\` has no effect on \`NAME\`: it is shown as a number, which is always one line. … | `max_lines` of 2 or more on a column whose cells are always one line. The middle says why: "it is shown as a number" (or "a boolean", "a date", "a datetime", "an enum"); a related record's label; `sensitive?: true` (a mask and a button on one line); or a `component` that decides how cells look. `max_lines` is for text: a string, an array, a map, an embedded resource, a union, or read-only text. | Remove the option. See [Long text](columns-and-defaults.md#long-text). |
| invalid value for :max_lines option: expected one of 1..10, got: 11 | `max_lines` is not a whole number from 1 to 10. An error of the block itself: it stops the compile. | Give 1 to 10. |

A column whose type has no editor, or whose attribute is not writable, gets
one of those two messages and not the ones about what its action accepts or
needs: no action could save it.

### A column that names a relationship

A column naming a belongs-to relationship is a reference cell: it shows the
related record's label. Path as above; `NAME` is the relationship,
`DESTINATION` its destination resource.

| Message starts with | Cause | Fix |
| --- | --- | --- |
| \`NAME\` is a has-many relationship. Only a belongs-to relationship can be a column: … | A has-many, has-one or many-to-many; the message says which. | Remove the column; offer the related records under the row with `relationship :NAME`. |
| The destination of \`NAME\`, DESTINATION, has no table: it does not list \`AshDataTable.Resource\` in its extensions. … | The label comes from the destination's `label_field`. | Add the extension and a `label_field` to the destination, or show the foreign key attribute. |
| The destination of \`NAME\`, DESTINATION, declares no \`label_field\`. … | The destination has a table without `label_field`. | Add `label_field` there. |
| The destination of \`NAME\`, DESTINATION, has no primary read action, and the relationship names no \`read_action\`. … | The related record is read as Ash loads the relationship, which needs one of the two. | Mark a destination read action `primary? true`, or give the relationship a `read_action`. |
| \`NAME\` shows the label of a related record, which a table does not sort by, … | `sortable? true` on a reference cell. | Remove the option. |
| \`NAME\` shows the label of a related record, which a table does not filter by, … | `filterable? true` on a reference cell. | Remove the option. |
| The update action \`ACTION\` does not accept \`KEY\`, the foreign key of \`NAME\`, and has no argument that a \`manage_relationship\` change hands to \`NAME\`, … | A reference cell is edited by choosing another record, which the column's own action takes through the foreign key (`source_attribute`) in its `accept` or through such an argument. It has neither. | Add the key to `accept`, or name an action that takes the record. |
| The update action \`ACTION\` hands its argument \`ARG\` to \`NAME\` as a list of keys. … | The argument is an array; a cell holds one record and an edit gives one key. | Give the argument the key's type (`:uuid`), or name another action. |
| The update action \`ACTION\` hands its argument \`ARG\` to \`NAME\`, and does not relate the record the argument names: its \`manage_relationship\` change has no \`on_lookup\` … | The change is `type: :remove`, or has its own options without `on_lookup` (`:append` and `:append_and_remove` have one). | Use `type: :append_and_remove`, or `:append`. |
| The update action \`ACTION\` hands its argument \`ARG\` to \`NAME\`, and the argument does not hold the key of a related record: … | The argument is a map (a record to create or change), or not stored as the destination's key is; or the destination has a primary key of several attributes and the change has no `value_is_key`. The middle says which. A table gives the action the key of an existing record. | Give the argument the key's type; for a key of several attributes, name the attribute with `value_is_key`. |
| \`NAME\` is edited by choosing a record of the destination's table, and there is nothing to choose it with, … | Its own `update_action`, and the record cannot be chosen: the relationship has a `filter`; the records would be read through an action that is not a public read action; or the action accepts the foreign key, which is not public (`attribute_public? false`) or not writable (`attribute_writable? false`), and has no argument that takes the record. | Remove the option; for a key not set from outside, name an action that takes the record through an argument. |
| \`NAME\` can never be edited, so \`confirm\` has no effect. A column that names a relationship is edited through … | `confirm` on a reference cell no update action saves: none at either level, `update_action false`, or an action that takes the record neither way or needs another argument. | Remove `confirm`, or make the column editable. |
| \`NAME\` can never be edited, so \`confirm\` has no effect. The relationship \`NAME\` has a \`filter\`, … | `confirm` on a reference cell whose record cannot be chosen, whatever the action; the second sentence says why, as above. | Remove `confirm`. |

The column messages about the name of an `update_action` and a required
argument apply to a reference cell as they are; the argument that takes the
related record is the one an edit gives, so it does not count as missing.
Under the table's `update_action`, a reference cell whose record that action
does not take, or cannot be chosen, is read-only without a finding. See
[Choosing a related record](choosing-a-related-record.md#which-reference-cells-are-edited)
and
[Relationships an action manages](managing-relationships.md#a-reference-cell-that-is-edited-through-an-argument).

A private relationship gets the "is not public" message of a private field.

## A column's component

Path: `table -> column -> NAME -> component`; `MODULE` is the module named.
See [Custom components](custom-components.md).

| Message starts with | Cause | Fix |
| --- | --- | --- |
| The component \`MODULE\` cannot be found: there is no module of that name. | A typo, an alias not in scope in the resource, or a renamed module. | Write the whole name, or `alias` it in the resource. |
| \`MODULE\` is not a component: it does not implement the behaviour \`AshDataTable.Component\`. … | A LiveComponent, or function components without the behaviour. | Add `use AshDataTable.Component`, and define `cell/1`, `editor/1` or both. |
| The component \`MODULE\` defines neither \`cell/1\` nor \`editor/1\`, so it changes nothing. | The behaviour declared by hand (`@behaviour AshDataTable.Component`), with neither part. With `use AshDataTable.Component` this is an error of the module's own compile (below). | Define one of the two. |
| The component \`MODULE\` only edits (it has no \`cell/1\`), and \`NAME\` can never be edited, so the component is never used. … | An `editor/1`-only component, such as `AshDataTable.Components.Slider`, on a column nobody can edit. The last sentence says why, as for `confirm`. | Make the column editable, or remove `component`. |
| \`NAME\` shows the label of a related record. A reference cell has no component: … | `component` on a relationship column. | Remove the option. |
| The component \`AshDataTable.Components.Slider\` cannot be used on \`NAME\`: a slider needs a number with a minimum and a maximum. … | The slider on a number whose constraints lack `min`, `max` or both. `AshDataTable.Components.Progress` says the same of "a progress bar". | Add e.g. `constraints min: 0, max: 100` to the attribute. |
| The component \`AshDataTable.Components.Slider\` cannot be used on \`NAME\`: a slider needs a number with a minimum and a maximum, and this field is shown as text. | Slider or progress bar on a non-number. The end says what it is shown as: text, a boolean, a date, a date and time, a choice or read-only text. | Use it on a number, or remove `component`. |
| The component \`AshDataTable.Components.Badge\` cannot be used on \`NAME\`: a badge shows the label of a choice, … | The badge on a field that is no enum. It needs an `Ash.Type.Enum`, or an `:atom` with `constraints one_of: [...]`. | Use it on an enum, or remove `component`. |

The last three come from the shipped components themselves. Your own
component reports in the same place, as "The component \`MODULE\` cannot be
used on \`NAME\`: " followed by what its `verify/1` returned.

A component with both parts on a column that can never be edited is not
reported: its `cell/1` is used, and it may edit another column.

### The component's own compile

`use AshDataTable.Component` checks the module that uses it. These errors
stop the build:

| Message | Cause |
| --- | --- |
| MODULE uses AshDataTable.Component and defines neither \`cell/1\` nor \`editor/1\`. … | Neither function. |
| MODULE: \`commit\` says when the editor saves, and is \`:enter\` (on Enter or on leaving the cell, the default) or \`:change\` (when the value changes). Got: :blur | `commit:` with another value. |
| MODULE: \`commit: :change\` says when the editor saves, and the module defines no \`editor/1\`. | `commit: :change` on a component that only shows. |

### When a component changes after the resource was compiled

A resource has no compile-time dependency on its component (none from the
data layer to the web layer); the component is checked once the whole
application is compiled. So changing only the component neither recompiles
the resource nor re-runs these checks. A renamed component the resource
still names (Elixir 1.19, Spark 2.7):

| Run | Result |
| --- | --- |
| `mix compile`, after the component's file changed | Nothing printed: the resource is not recompiled. |
| Opening the table | It refuses to render: "cannot build the table of … the \`component\` of its column \`NAME\` cannot be used. The component \`MODULE\` cannot be found: there is no module of that name." |
| `mix compile --force`, or a clean build | The finding is printed, and fails the build with `--warnings-as-errors`. |

## `label_field`

Path: `table -> label_field`.

| Message | Cause | Fix |
| --- | --- | --- |
| The resource has no attribute named \`NAME\`. | No such field. | Correct the name. |
| \`NAME\` is not public. Only a \`public?\` attribute can be the label of a record. | Private attribute. | Name a public attribute. |
| \`NAME\` is a relationship. The label of a record is one of its own attributes: … | A relationship. | Name an attribute. |
| \`NAME\` is a calculation. The label of a record has to be an attribute: it is read with the record's key and nothing else. | A calculation, or an aggregate ("is an aggregate"). | Name an attribute. |

## `sticky_label?`

Path: `table -> sticky_label?`, or `tables -> table -> NAME -> sticky_label?`
for a named table. See
[Keeping the label column in view](columns-and-defaults.md#keeping-the-label-column-in-view).

| Message starts with | Cause | Fix |
| --- | --- | --- |
| The table says \`sticky_label? true\`, and the resource declares no \`label_field\`. … | No label, so no column to keep. | Add `label_field`, or remove the option. |
| The table says \`sticky_label? true\` and has no column of the label, \`NAME\`. … | The table declares its columns, without the `label_field`. | Add `column :NAME`, or remove the option. |

## Named tables

Every check runs for each table of a resource: the default table and every
[named table](named-tables.md). The message is the same; the path names the
table: `table -> column -> NAME` becomes
`tables -> table -> TABLE -> column -> NAME`.

<!-- sketch -->
```text
warning: ** (Spark.Error.DslError) [MyApp.Comment]
tables -> table -> compact -> column -> nothing defined in lib/my_app/comment.ex:41::
  The resource has no attribute, calculation, aggregate or belongs-to relationship named `nothing`.
```

A table declared in a file of its own (a fragment) is checked as part of its
resource: the module in brackets is the resource; file and line are the
fragment's.

Findings about the tables themselves have the path `tables -> table -> TABLE`:

| Message starts with | Cause | Fix |
| --- | --- | --- |
| \`:NAME\` cannot be the name of a table. … | A name is part of the table's id and URL parameters: lower-case letters, digits and `_`, starting with a letter (`:compact`). This one has a capital, a `-`, or a leading digit. | Rename the table. |
| \`:default\` is the name of the default table, … | A named table is called `:default`. | Move it into the `table` block, or rename it. |
| Got duplicate AshDataTable.Resource.Table: NAME | Two tables of one name, in one file or two fragments. Spark's, with the path `tables -> NAME`. | Rename one, or merge them. |
| The column \`NAME\` is declared more than once in the table \`:TABLE\`. | A named table declares a `column` twice; also said of `relationship`, `action`, `argument` and `upload`. In the `table` block Spark reports it ("Got duplicate …"). | Declare it once. A calculation shown twice needs `as` on the second column. |
| \`label_field\` says what a record of the resource is called, whichever of its tables shows it, so it is no option of a named table. … | `label_field` in a named table; the path ends in `-> label_field`. | Move it to the `table` block. |

A table that a router line, a tag (`<AshDataTable.table>`) or
`AshDataTable.attach/4` names and the resource lacks is not found at compile
time: the router does not look at the resource. It raises when the page is
opened, the tag rendered or `attach/4` called, listing the resource's
tables.

## Relationships

Path: `table -> relationship -> NAME`.

| Message starts with | Cause | Fix |
| --- | --- | --- |
| The resource has no relationship named \`NAME\`. | No such relationship. | Correct the name. |
| \`NAME\` is not public. Only \`public?\` relationships can be offered by a table. | Private relationship. | Make it `public? true` if its records may be shown, or leave it out. |
| The destination of \`NAME\`, DESTINATION, has no table: … | The destination does not list the extension; a row only expands into a resource's table. | Add the extension to the destination, or leave the relationship out. |
| Got duplicate AshDataTable.Resource.Relationship: NAME | The same `relationship` twice. Spark's, with the path `table -> NAME`. | Declare it once. |
| \`NAME\` is to show the table \`:TABLE\` of its destination, but DESTINATION has no table named \`:TABLE\`. Its tables: \`:A\`, \`:B\`, and the default table. | The relationship's `table` names a table the destination lacks. Without named tables the end is "It has the default table only." | Correct the name, or declare the table on the destination. |
| \`NAME\` shows the table of DESTINATION, which offers the page sizes [10, 25, 50], and reads it through \`:ACTION\`, the relationship's own \`read_action\`. … | The nested table offers [`page_sizes`](#page_sizes) that the relationship's own `read_action` does not allow (a size above `max_page_size`, or a `default_limit` not among them). Ends as for the table's own read action. | Change the sizes or the action, or drop the relationship's `read_action`. |

With no `relationship` declared, a relationship whose destination has no
table is not offered, without a finding. One whose own `read_action` does not
allow its nested table's `page_sizes` is offered without the menu, with that
action's page size. A nested table without pages has no menu and is not
reported.

## Row actions and the create action

Path: `table -> action -> NAME` for an `action` (row or table action),
`table -> create_action` for the create action, `table` for the last two.
`INPUT` is an attribute the action accepts or one of its arguments; `ARG` is
the argument `record_argument` names.

| Message starts with | Cause | Fix |
| --- | --- | --- |
| The resource has no action named \`NAME\`. | An `action` or `create_action` names no action. | Correct the name, or define the action. |
| The action \`NAME\` is not public. Only \`public?\` actions can be behind a table. | `public? false`. | Make it public, or leave it out. |
| \`NAME\` is a create action. An \`action\` of a table is an update or a destroy action, … | An `action` is an update or destroy (run on a row's record) or generic (run on the table). | Name it with `create_action :NAME`. |
| \`NAME\` is a read action. An \`action\` of a table is … | An `action` names a read action. | Remove it. |
| Got duplicate AshDataTable.Resource.Action: NAME | The same `action` twice. Spark's, with the path `table -> NAME`. | Declare it once. |
| The row action \`NAME\` cannot be run from a table: its input \`INPUT\` is required, and a table has no field for its type (TYPE). The action panel has fields for … | A required accepted attribute, or `allow_nil? false` argument, of a type without a field: a map without fields, an embedded resource or union a table cannot edit, a binary, several files, or an array of anything but text, numbers, booleans, dates, datetimes and choices. The panel has fields for those, arrays of them, values written as one line of text (a key), embedded resources, maps and unions made of them, and one file. `TYPE` is the Ash type (`Ash.Type.Map`, `{:array, Ash.Type.UUID}`). | Use an action that does not require the input, or leave the action out. |
| The row action \`NAME\` cannot be run from a table: its argument \`INPUT\` is required, and holds the keys of the records of \`RELATIONSHIP\`. … | A required argument a `manage_relationship` change hands to a relationship as a list of keys, whose records cannot be chosen. The last sentence says why: the relationship is not public, is manual or has a `filter`; its destination has no table; the records to choose from, or those related now, would be read through an action that is not a public read action; the change would make a record for a key that names none (`type: :direct_control`); or the relationship holds one record. The same message exists for the create action. | Make the relationship `public? true` and give its destination a table, or leave the action out. See [Relationships an action manages](managing-relationships.md#which-arguments-are-chosen). |
| The row action \`NAME\` says \`bulk? true\`, and cannot run on several records at once: … | `bulk? true` on an action that accepts a primary-key attribute or the only key of an identity: no two records can share its value, and a selection's inputs are given once for all. `bulk?` can only switch off. | Remove `bulk? true`; the action stays a row action, not offered for a selection. |
| The table action \`NAME\` cannot be run from a table: its input \`INPUT\` is required, … | As for a row action, for an `allow_nil? false` argument of a generic action. The `record_argument` is given by the table and needs no field. | Use an action that does not require the argument, or leave it out. |
| The table action \`NAME\` says \`bulk? true\`, and runs on the table as a whole: … | A generic action with `bulk? true` and no `record_argument`: it takes no record, so no selection. | Remove `bulk? true`, or add `record_argument` (it then is a row action). |
| The action \`NAME\` says \`record_argument :ARG\`, and is an update action, … | `record_argument` on an update or destroy action (the message says which), which runs on its row's record already. `record_argument` is for a generic action. | Remove `record_argument`. |
| The action \`NAME\` says \`record_argument :ARG\`, and has no argument named \`ARG\`. | No such argument. | Correct the name, or add the argument. |
| The action \`NAME\` says \`record_argument :ARG\`, and its argument \`ARG\` is not public. … | `public? false`: a private argument is not given from outside, and a table is outside. | Make the argument public. |
| The action \`NAME\` says \`record_argument :ARG\`, and that argument is of the type TYPE, which is not stored as the primary key \`KEY\` is (KEY_TYPE). … | The row's key is given as it is; the argument is stored differently (an integer for a UUID key, text, an array). Types stored alike (`:uuid`, `:uuid_v7`) are accepted. | Give the argument the key's type. |
| The action \`NAME\` says \`record_argument :ARG\`, and the primary key of the resource is \`A\`, \`B\`: several attributes. … | One argument takes a row's key only for a one-attribute key. | Leave the action out, or declare it without `record_argument`, as a table action whose panel asks for the keys. |
| The action \`NAME\` says \`record_argument :ARG\`, and the resource has no primary key: … | No primary key. | The same. |
| The action \`NAME\` says \`page_argument :ARG\`, and has no argument named \`ARG\`. … | No such argument; an accepted attribute does not count. | Correct the name, or add the argument. |
| The action \`NAME\` says \`page_argument :ARG\`, and its argument \`ARG\` is not public. … | `public? false`. A page gives a private argument through `private_arguments`, without a declaration; `page_argument` is for a public one the panel is not to ask for. | Remove the `page_argument`; give the value in `private_arguments`. |
| The action \`NAME\` says \`page_argument :ARG\`, and \`ARG\` is its \`record_argument\`, … | The argument that gets the row's key cannot be both. | Remove the `page_argument`. |
| The action \`NAME\` says \`page_argument :ARG\` more than once. | Named twice. | Remove one. |
| \`NAME\` is an update action, not a create action. | `create_action` names an update, destroy, read or generic action (the message says which). | Name a create action. |
| The create action \`NAME\` cannot be run from a table: its input \`INPUT\` is required, … | As for a row action. An attribute whose default is computed does not count as required in a create. | Name a create action that does not require the input. |
| The table changes records: it has editable columns, row actions or a create action. Ash loads what a create, an update or a destroy action returns through the primary read action, without arguments, and the primary read action \`NAME\` requires the argument \`ARG\`, … | The primary read action has an `allow_nil? false` argument with no default; the table edits, acts or creates; a column is a calculation, an aggregate or a reference cell. A row could not be shown again. | Put the argument on a read action of its own named with `read_action`, give it a default, or leave the table read-only. |
| The table has row actions or a create action and shows calculations, aggregates or reference columns (\`NAME\`), but the resource has no primary read action. … | A non-primary `read_action`, an `action` or `create_action`, and a calculation, aggregate or reference column. A table with editable columns as well gets the finding about those instead. | Mark a read action `primary? true`. |

A `reference` of an `action` says which resource an argument's keys belong
to. `REF` is the argument, `DESTINATION` the resource; the path is the
action's, `table -> action -> NAME`.

| Message starts with | Cause | Fix |
| --- | --- | --- |
| The action \`NAME\` says \`reference :REF\`, and has no argument named \`REF\`. | No such argument. | Correct the name. |
| The action \`NAME\` says \`reference :REF\`, and \`REF\` is an attribute the action accepts, not one of its arguments. … | A `reference` for an accepted attribute. | Remove it. A public belongs-to's foreign key is chosen in the picker without one. |
| The action \`NAME\` says \`reference :REF\`, and its argument \`REF\` is not public. … | `public? false`. | Make it public, or remove the `reference`. |
| The action \`NAME\` has more than one \`reference :REF\`. … | Named twice. | Declare it once. |
| The action \`NAME\` says \`reference :REF\`, and \`REF\` is its \`record_argument\` … | The table gives that argument the row's key. | Remove the `reference`. |
| The action \`NAME\` says \`reference :REF\`, and its argument \`REF\` is declared \`sensitive?: true\`. … | A picker shows what is chosen. | Remove the `reference`. |
| The action \`NAME\` says \`reference :REF\`, and a \`manage_relationship\` change of the action hands \`REF\` to the relationship \`RELATIONSHIP\`. … | The relationship already says which resource it refers to. | Remove the `reference`: the picker works without it. |
| The action \`NAME\` says \`reference :REF, DESTINATION\`, and DESTINATION has no table … | `DESTINATION` is no resource, or does not list `AshDataTable.Resource`. | Give it a table, or name another resource. |
| … and the table of DESTINATION has no public read action to read the records to choose from … | That table's read action is private, or missing. | Make it public, or name a public one with `read_action` in that block. |
| … and the primary key of DESTINATION is \`A\`, \`B\`: several attributes. … / … has no primary key … | One argument holds one value. | Remove the `reference`. |
| … and the argument is of the type TYPE, which is not stored as the primary key \`KEY\` of DESTINATION is (KEY_TYPE), nor a list of it. … | The argument cannot hold that key. Types stored alike (`:uuid`, `:uuid_v7`) are accepted. | Give the argument the key's type, or a list of it. |

See [Table actions](table-actions.md#an-argument-that-holds-the-key-of-a-record).

An input without a field that the action does **not** require is no
finding: it is left out of the panel. Which types have a field, and what
counts as required:
[Row actions and create](row-actions-and-create.md#the-fields-of-the-panel).

### A destroy action without `confirm`

A destroy action with no `confirm` deletes its record at one click, and the
block may mean that. So this is a plain warning, with the action's line and
no path. Output for a sketch whose block says `action :destroy` and nothing
more (file path shortened):

<!-- sketch -->
```text
warning: The row action `destroy` is a destroy action without `confirm`: one click on its button deletes the record, and nothing asks first. Give it a question (`confirm "Delete this record?"`), or say that a delete in one click is meant with `confirm false`.
    │
 18 │     action :destroy
    │     ~~~~~~~~~~~~~~~
    │
    └─ lib/sketch/task.ex:18: (file)
```

Answer it in the block, either way. The demo has both, so it compiles without
the warning: a question on the tasks' action, and `confirm false` on the task
labels'
([`demo/lib/demo/tracker/task_label.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task_label.ex)):

<!-- source: demo/lib/demo/tracker/task_label.ex -->
```elixir
action :destroy do
  label "Remove"
  confirm false
end
```

`--warnings-as-errors` fails on it like on every finding. An update action
is never warned about.

## Uploads

Path: `table -> upload -> NAME`, then `accept` for a finding about that
option. `NAME` is the argument the `upload` names.

| Message starts with | Cause | Fix |
| --- | --- | --- |
| No action of the table has a public argument named \`NAME\`. … | No `action` of the block and not its `create_action` has the argument, or it is `public? false`: usually a typo, or an action the block does not name. An `upload` names an `Ash.Type.File` argument of an action the table offers. | Correct the name, or name the action in the block. |
| The argument \`NAME\` of the action \`ACTION\` is of the type TYPE, and takes no file. … | The argument is of another type. | Remove the `upload`, or give the argument the type `:file`. |
| The upload of \`NAME\` accepts "KIND", which is no kind of file LiveView knows. … | An extension without its dot, an extension or MIME type `mime` does not know, or a wildcard other than "audio/\*", "image/\*", "video/\*". LiveView would raise when the panel opens. `accept` takes extensions with a known MIME type (".csv"), MIME types ("text/csv") and those three wildcards. | Correct the entry, or make it known with `config :mime, :types`. |
| The upload of \`NAME\` says \`accept []\`, which takes no file at all. … | An empty `accept`. | List the kinds, or remove the option: it then takes any file. |

A file argument needs no `upload`: without one it takes one file of any
kind, of 8 MB at most. See [Files](files.md#what-the-upload-is-limited-to).

## Sensitive fields

A field declared `sensitive? true` is masked in a table, and some options do
not go with that. See [Sensitive columns](sensitive-columns.md).

| Path | Message starts with | Cause | Fix |
| --- | --- | --- | --- |
| `table -> column -> NAME -> component` | \`NAME\` is declared \`sensitive?: true\`. A table masks the cells of a sensitive column … | A `component` would be given the value to show. | Remove `component`. |
| `table -> label_field` | \`NAME\` is declared \`sensitive?: true\`. The label of a record is shown wherever a table names the record … | The `label_field` is sensitive. | Name another attribute. |
| `table -> column -> NAME -> sortable?` and `filterable?` | \`NAME\` cannot be sorted … / cannot be filtered … | `sortable? true` or `filterable? true` on a sensitive column. | Remove the option. |
| `table -> column -> NAME -> update_action` | \`NAME\` is declared \`sensitive?: true\` and has the type \`TYPE\`. A table hides what is typed for a sensitive field, which it can do for text and for a number only … | The column's own `update_action` on a sensitive column that is not text or a number. | Remove it. A row action can still change the value. |
| `table -> action -> NAME` | The … action \`NAME\` cannot be run from a table: its input \`INPUT\` is required and declared \`sensitive?: true\` … | A required sensitive input that is not text or a number. | Give the input a default, or leave the action out. |
| `table -> read_action` | The read action \`NAME\` requires the argument \`ARGUMENT\`, which is declared \`sensitive?: true\` … | The argument line is kept in the URL, so it has no input for a sensitive argument. | Give the argument a default, or name another read action. |
| `table -> column -> NAME -> ask -> ARGUMENT` | The argument \`ARGUMENT\` of the calculation \`NAME\` cannot be asked: it is declared \`sensitive?: true\` … | An `ask` for a sensitive argument. | Fix its value with `arguments`. |

A table-level `update_action` leaves a sensitive column it cannot edit
read-only without a finding, as for every column it cannot save.

## Summaries

A column's `summary`: one number under it, in the footer row. See
[Footer summaries](footer-summaries.md). Path for all:
`table -> column -> NAME -> summary`.

| Message starts with | Cause | Fix |
| --- | --- | --- |
| \`NAME\` is a calculation. / is an aggregate. / names a relationship. A summary is computed over an attribute of the resource … | The column shows no attribute. | Remove `summary`. |
| \`summary :KIND\` does not fit \`NAME\`, which is of type \`TYPE\` … | A sum or average of a non-number, or a minimum or maximum of something that is not a number, date, datetime or time. | Use a kind that fits; `:count` fits every column. |
| \`NAME\` is declared \`sensitive?: true\`. A table masks the cells of a sensitive column, and a summary would say what they hold … | Any summary on a sensitive column. | Remove `summary`. |
| The table reads through \`ACTION\`, a manual read action … | The data layer computes the summary, and a manual read action is not read through it. | Remove this table's summaries, or read through an action that is not manual. |
| The data layer of the resource, \`LAYER\`, does not compute \`:KIND\` over the records of a query … | The data layer has no such aggregate. | Remove `summary`. |

A kind that is none of the five is rejected by Spark at compile, like every
value an option does not take.

Compiled despite one of the first three, the table refuses to be built. With
one of the last two it is built and shows "–" in place of the number.

## Live updates

Reported when the **domain** is compiled, at its `table` block: a resource
is compiled before its domain and cannot read the domain's block. See
[Live updates](live-updates.md).

| Path | Message starts with | Cause | Fix |
| --- | --- | --- | --- |
| `table -> pub_sub` (of the domain) | RESOURCE says \`live? true\`, but the \`table\` block of DOMAIN names no \`pub_sub\` … | A resource announces its changes, and the domain names no `Phoenix.PubSub` server. | Add `pub_sub MyApp.PubSub` to the domain's `table` block. |

A domain that does not list `AshDataTable.Domain` is not checked; the table
then refuses to open, with the same sentence. So does a router line, a tag
or an attached table that says `live?: true` for a resource that announces
nothing.

## A private action

A table runs only actions the resource declares `public?`, however it came
by them: why, and which actions a table runs, is in
[Authorization](authorization.md#every-action-a-table-runs-is-public). An
action the block names itself gets an "is not public" message from the
sections above. The findings here are about actions the block does not name
and a table would run anyway.

A sketch: a folder whose rows offer two relationships to its papers; the
second reads through a papers action that is `public? false`.

<!-- sketch -->
```elixir
defmodule Sketch.Folder do
  use Ash.Resource,
    domain: Sketch.Vault,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshDataTable.Resource]

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

The compiler prints (stack trace left out):

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

Every message here continues with the same sentence, "A table only runs
\`public?\` actions: a private action is not meant for interfaces, and may be
exempt from policies.", and then names the ways out, which the Fix column
repeats. `ACTION` is the private action; `DESTINATION` or `RESOURCE` the
resource it belongs to: the relationship's destination, or a resource Ash
reads on the way.

| Path | Message starts with | Cause | Fix |
| --- | --- | --- | --- |
| `table -> read_action` | The primary read action \`ACTION\` is not public, and the table names no \`read_action\`, so it would read through it. | No `read_action`, and the primary read action is `public? false`. Reported for a resource with no `table` block as well. | Make `ACTION` public, or name a public read action with `read_action`. |
| `table -> relationship -> NAME` | \`NAME\` points to DESTINATION, whose read action \`ACTION\`, the relationship's own \`read_action\`, is not public. | A declared `relationship` whose own `read_action` is private; a nested table runs it. | Make `ACTION` public, give the relationship a public `read_action`, or do not offer `NAME`. |
| `table -> relationship -> NAME` | \`NAME\` points to DESTINATION, whose read action \`ACTION\`, the one behind its table, is not public. | A declared `relationship` with no `read_action`, whose destination's table would read through a private action (that table has the first finding itself). | Make `ACTION` public, name a public `read_action` in DESTINATION's `table` block or on the relationship, or do not offer `NAME`. |
| `table -> column -> NAME` | \`NAME\` points to DESTINATION, whose read action \`ACTION\`, its primary read action, is not public. The related record of a column is read as Ash loads the relationship. | A reference cell whose relationship names no `read_action`, to a destination with a private primary read action; the read action of the destination's table does not matter. Where the relationship names a private action, the message says "the relationship's own \`read_action\`". | Make `ACTION` public, give the relationship a public `read_action`, or remove the column. |
| `table -> relationship -> NAME` | \`NAME\` is read through the join resource RESOURCE, whose read action \`ACTION\`, its primary read action, is not public. | A declared many-to-many. Ash reads the join resource through the join relationship's `read_action`, else its primary read action, and its policies decide which records are related. Where the join relationship names a private action, the message says "the \`read_action\` of the join relationship \`JOIN\`". | Make `ACTION` public, give the join relationship `JOIN` a public `read_action`, or do not offer `NAME`. |
| `table -> relationship -> NAME` | \`NAME\` is read through RESOURCE, a resource on its \`through\` path, whose read action \`ACTION\`, the one Ash reads it through there, is not public. | A declared relationship `through` others; Ash reads every resource on the path through its primary read action. | Make `ACTION` public, or do not offer `NAME`. |
| `table -> column -> NAME` | The aggregate \`NAME\` reads DESTINATION through \`ACTION\`, its primary read action, which is not public. | An aggregate column over a resource with a private primary read action, without its own `read_action`. If it names a private one: "the aggregate's own \`read_action\`". | Make `ACTION` public, give the aggregate a public `read_action`, or remove the column. |
| `table -> column -> NAME` | The aggregate \`NAME\` reads DESTINATION through \`ACTION\`, the \`read_action\` of the relationship \`RELATIONSHIP\`, which is not public. | The relationship names a private `read_action`: Ash filters the aggregate by that action's policies, even where the aggregate names a public action of its own. | Make `ACTION` public, give the relationship a public `read_action`, or remove the column. |
| `table -> column -> NAME` | The aggregate \`NAME\` reads RESOURCE through \`ACTION\`, its primary read action, which is not public. | An aggregate over a path of relationships (`[:boxes, :papers]`) where a resource in between has a private primary read action. Ash applies the policies of every resource on the path. | Make `ACTION` public, give the relationship `RELATIONSHIP` a public `read_action`, or remove the column. |
| `table -> column -> NAME` | The aggregate \`NAME\` reads RESOURCE through \`ACTION\`, its primary read action, as the join resource of \`RELATIONSHIP\`, which is not public. | An aggregate over a many-to-many whose join resource is read through a private action. | Make `ACTION` public, give the join relationship `JOIN` a public `read_action`, or remove the column. |
| `table -> column -> NAME` | The calculation \`NAME\` is computed from the aggregate \`AGGREGATE\`: it reads DESTINATION through \`ACTION\`, the aggregate's own \`read_action\`, which is not public. | A calculation column whose expression holds an aggregate Ash reads through a private action: one of the resource by name, one written out (`AGGREGATE` is then the expression, e.g. \`count(all_papers)\`), or one inside a referenced calculation. "through …" is worded as for an aggregate column. The same wording is used for an aggregate column over a field that is itself such an aggregate. | Settle the aggregate as the message says, or remove the column. |
| `table` | The table changes records: it has editable columns, row actions or a create action. Ash loads what a create, an update or a destroy action returns through the primary read action, and the primary read action \`ACTION\` is not public. | A public `read_action`, a private primary read action, and an editable column, an `action` or a `create_action`. | Make `ACTION` public, or leave the table read-only: without `update_action`, `action` and `create_action`. |

A relationship that leads to a private read action is reported only when the
block declares it; otherwise it is left out of the default set without a
finding, as one whose destination has no table. Reference cells, aggregate
columns and calculation columns are always declared, so always reported.

A calculation is looked into as far as it is an expression. One computed in
Elixir is not; what an expression references without an aggregate
(`exists(papers, …)`, `folder.name`) runs no action, and Ash applies no
policy to it. See [Authorization](authorization.md#what-it-does-not-reach).

The last finding is about Ash, like the missing primary read action: no
option of a create, update or destroy says through which read action its
result is loaded, so a table running one cannot keep Ash from the primary
one. In one of the demo's tests the private primary read action is also
exempt from the resource's field policies, and the update action changes a
field the page hides: without this finding, the saved row shows that field's
new value.

## Warnings about what a column shows

Two findings are not mistakes in the block: the resource may mean them. They
are plain warnings with the column's line, no path and no
`Spark.Error.DslError`. `--warnings-as-errors` fails on them too. Output for
a sketch:

<!-- sketch -->
```text
warning: The aggregate column `payroll` shows `salary` of Sketch.Member, which a field policy protects there, and Sketch.Team has no field policy for `payroll`. Ash applies the read policy of the related resource to an aggregate, and not its field policies: everyone who can read a row sees this column, and can sort and filter by it. Protect it with a field policy for `payroll` on Sketch.Team, which needs `Ash.Policy.Authorizer` among its authorizers and, if the resource has no policies yet, one that authorizes everything. If the column is meant to show this to everyone who reads a row, say so with `exposes_protected_field? true` on the column.
    │
 48 │     column :payroll
    │     ~~~~~~~~~~~~~~~
    │
    └─ lib/sketch/team.ex:48: (file)
```

| Message starts with | Cause | Answer |
| --- | --- | --- |
| The aggregate column \`NAME\` shows \`FIELD\` of DESTINATION, which a field policy protects there, and RESOURCE has no field policy for \`NAME\`. … (as above) | An aggregate over a field a field policy protects on the related resource. For a field in the aggregate's own `filter`: "counts by \`FIELD\` of DESTINATION in its \`filter\`". | A field policy for the aggregate, or `exposes_protected_field? true` on the column. |
| The calculation column \`NAME\` references \`FIELD\` of DESTINATION (through \`PATH\`), which a field policy protects there, and RESOURCE has no field policy for \`NAME\`. Ash applies no policy to what a calculation references: … | A calculation whose expression references a protected field of a related resource. For a field of the resource itself: "references \`FIELD\`, which a field policy protects on this resource". The rest is as above. | The same. |

Both rules, and what the warnings cannot see:
[Columns and defaults](columns-and-defaults.md#aggregates-and-calculations-over-protected-fields).

A resource with one finding prints it as in the first example, with the
block's line. Several print as one warning: "Multiple Errors Occurred", then
each finding with its own path, dashed lines between them, and no excerpt of
the block.

## What is not a mistake

Not reported, on purpose:

| In the block | What happens |
| --- | --- |
| A table-level `update_action` that does not accept some columns' attributes | Those columns are read-only. |
| A table-level `update_action` with a required argument | No column is edited through it. |
| A table-level `update_action` that accepts a column whose type has no editor (a UUID), an attribute that is not writable, an embedded resource or map a table cannot edit, or a union a table cannot edit or an array of unions | The column is read-only. For a column's own `update_action` this is reported. |
| `sortable? false` or `filterable? false` on a column that could not be sorted or filtered anyway | Nothing. |
| No `table` block | The default table. |
| A public relationship whose destination has no table, or whose (or whose join resource's) read action is private, in a block that declares no `relationship` | It is not offered. Declared, the private action is reported. |
| An update action run over a private read action of its own (`atomic_upgrade_with`) | Nothing: what a public action does while it runs is the action's. |
| An attribute whose embedded resource is cast through a private action of that resource | Nothing, for the same reason: Ash runs it while casting the value, whoever gave it. See [Maps and embedded resources](maps-and-embedded-resources.md#what-ash-does-with-the-value). |
| A file argument without an `upload` | Its upload has LiveView's own limits. |
| A row action with a file argument, offered for the selected rows | Every selected record gets the same file. See [Files](files.md#on-the-selected-rows). |
| A private action no table would run (no column, relationship or option leads to it) | Nothing. |
| `exposes_protected_field? true` on a column that exposes nothing | Nothing. |
| An action, or the create action, with an optional input of a type without a field | The input is left out of the panel. |
| A row action that accepts attributes that may all be empty | Its button opens the action panel. |
| `confirm false` on an update action | Nothing; update actions are not warned about. |
| A row action that accepts a primary-key attribute, or one that is an identity by itself, without `bulk? true` | A row action, not offered for the selected rows. |
| `bulk? false` on an action not offered for a selection anyway, `bulk? true` on one that is (the default), or `bulk? false` on a table action (it runs on no record) | Nothing. |
| A table whose only actions are generic, over a resource with a private primary read action, or none, beside loaded columns | Nothing. Ash loads no generic action's result through it, and the table reads again through its own read action. |
| A generic action under a policy with a check on a record | Nothing at compile. Ash cannot run it, and the table has no button for it. See [Table actions](table-actions.md#edge-cases). |
| A `create_action` that does not accept the attribute joining its records to a parent | The create button is on the table's own page, not where it is nested under that parent. |

The table-level action is a blanket statement, "edit what this action can
edit", so what it cannot edit is no error. A column's own action is a
statement about that column and is held to it: the action has to exist,
accept the attribute and need no argument, and the column has to be one a
table can edit. See [Inline editing](inline-editing.md).

## If a finding is ignored

A resource with a finding still compiles and its table opens. Where the
table would have nothing sound to do, it refuses: it raises `ArgumentError`
when rendered, with a message starting "cannot build the table of" that names
the resource and the cause. The router line's page, or the LiveView holding a
tag or attached table, then fails like any LiveView that raises.

| The mistake | At runtime |
| --- | --- |
| A wrong `read_action`: missing, not a read action, not public | Refuses to render. |
| No primary read action, and no `read_action` | Refuses. |
| A private primary read action, and no `read_action` | Refuses: "its read action cannot be used." |
| An unsupported `paginate_with` | Refuses. |
| Wrong `page_sizes` for the table's read action | Refuses. |
| A `relationship` whose own `read_action` does not allow its nested table's `page_sizes` | The nested table has that action's page size and no menu. |
| A column that does not exist or is not public | Refuses. |
| A relationship column whose label cannot be shown: not a belongs-to, a destination without a table or a usable `label_field` | Refuses. |
| A `relationship` that is no public relationship, or whose destination has no table | Refuses. |
| A `relationship` whose nested table would run a private read action | Refuses: "its relationship \`NAME\` cannot be offered." |
| A reference cell, an aggregate column, or a calculation column holding an aggregate, read through a private action | Refuses: "its column \`NAME\` cannot be shown." |
| Editable columns, row actions or a create action over a private primary read action | Refuses. |
| A calculation column whose arguments are unsound: a required one missing, an unknown one named, a value not of its type, fixed and asked, asked twice, or asked without a needed default | Refuses: "its column \`NAME\` cannot be shown." |
| `arguments`, `ask` or `as` on a column that is no calculation | Refuses. |
| A read action requiring an argument the argument line has no input for | Refuses: "its read action cannot be used." |
| An `argument` naming no public argument of the read action | Renders; the declaration has no effect. |
| A primary read action requiring an argument, under a table that changes records | Renders. After a save or an action the row cannot be loaded again, and is taken off the page as no longer the person's to read. |
| A wrong `update_action`, table or column: missing, not an update action, not public | Refuses. The block asked for editing through an action that cannot run; silently offering none would hide that. |
| Editable columns beside calculation, aggregate or reference columns, without a primary read action | Refuses. |
| An `action` naming no public update, destroy or generic action, or declared twice | Refuses: "its action \`NAME\` cannot be used." |
| A `record_argument` that cannot take a row's key, or one on an update or destroy action | Refuses. |
| `bulk? true` on a table action | Renders. It is a table action, not offered for the selected rows. |
| A `create_action` naming no public create action | Refuses: "its \`create_action\` cannot be used." |
| Row actions or a create action beside calculation, aggregate or reference columns, without a primary read action | Refuses. |
| A row or table action with a required input the panel has no field for | Renders, without that action's button. |
| A create action with a required input the panel has no field for | Renders, without a create button. |
| A destroy action without `confirm` | Renders; the button deletes at one click. |
| A `label_field` naming no public attribute | The table renders. A table showing this resource in a reference cell refuses, and a heading that would name a record by it uses a column instead. |
| A warning about what a column shows | Renders, with the column as Ash returns it. |
| A column's own `update_action` that exists but does not accept the attribute, or needs an argument | The column is read-only. |
| A column's own `update_action` on a calculation, an aggregate, a type without an editor or a non-writable attribute | The column is read-only. |
| A `component` that cannot be found, is not a component, has neither part, or says it cannot serve the column | Refuses: "the \`component\` of its column \`NAME\` cannot be used." |
| An edit-only `component` on a column that can never be edited | Renders; the component is not used. |
| A `component` on a relationship column | Renders, with the plain reference cell. |
| `sortable? true`, `filterable? true` or `confirm` without effect | Nothing; the option has no effect. |

The line between the two groups is the table-level action's: an action that
exists but cannot save a column leaves that column read-only, whoever named
it; an action that cannot run at all is refused.

A resource that does not list the extension is refused too: "… does not list
\`AshDataTable.Resource\` in its extensions, so it has no table."

A nested table is built from a relationship of the table around it and looks
up the relationship's read action again. A relationship no table built, or
one built before the resource was recompiled, is refused where its action is
private or not a read action: "cannot build the nested table of …". No other
action is read through in its place.

## Mistakes in how a table is placed

What the router line, the tag and `AshDataTable.attach/4` are given is
checked too. These are errors, not findings: an `ArgumentError` or
`CompileError` stops what was being done.

**The router line** is checked when the router compiles. Each of these
raises: an unknown option; a `:table` that is no table name; an `:id` that is
not lower-case letters, digits, `_` and `-` starting with a letter; a
`:layout`, `:authorize?` or `:live?` of the wrong kind; a `:notify` naming no
event; a `:context`, `:private_arguments`, `:page_arguments` or
`:before_action` that is no map or `{module, function}`. For example:

<!-- sketch -->
```text
** (ArgumentError) the :id of ash_data_table must be a string of lower-case letters, digits, `_` and `-` that starts with a letter, got: "Tasks"
```

**A tag and `attach/4`** check their options when the tag renders or
`attach/4` is called: `heading` not `true`, `false` or 1 to 6; `time_zone`
no zone (see [Time zones](time-zones.md)); `notify` naming no event; `open`
not text; `presentation` not a list of `panel:`, `picker:` and `confirm:`,
each `:modal` or `:inline`; `context`, `private_arguments`, `page_arguments`
or `before_action` no map or function of the right arity. `attach/4` also
refuses an unknown option, a `controlled` that is not a list of `:confirm`,
`:panel` and `:picker`, `url: true` in a LiveView the router did not mount,
and another resource, table or id under an already attached name. The router
line's `:kit` and `:presentation` are checked this way when its page opens.

**A kit** is checked twice. `use AshDataTable.Kit, contract: 6` is checked
when the kit compiles: another contract number, a public one-argument
function that is no kit part, or a `class` or `presentation` of another arity
is a `CompileError`. Where the kit is named (the tag's `kit`, the option of
`attach/4` or the router line, or `config :ash_data_table, kit: …`), a module
that does not `use AshDataTable.Kit`, or whose `presentation/1` answers
neither `:modal` nor `:inline`, is an `ArgumentError`:

<!-- sketch -->
```text
** (ArgumentError) AshDataTable.attach/4 was given `kit: MyAppWeb.Table`, which is no kit: a kit is a module that says `use AshDataTable.Kit, contract: 6` (see AshDataTable.Kit)
```

See [Kits](kits.md).

## Edge cases

- **A resource with the extension and no primary read action** is reported
  without a `table` block: the extension alone gives it a table, which needs
  an action to read through.
- **A mistake in `read_action` hides findings that depend on it.** Whether
  `sortable? true` has an effect depends on the pagination strategy, so it is
  checked only once `read_action` and `paginate_with` are right.
- **`filterable? true` on a type with no filter** gets the same message as
  on a field the resource declares unfilterable.
- **A private field that exists** gets "is not public"; a name that is
  nothing gets "has no attribute, calculation, aggregate or belongs-to
  relationship"; a relationship of another kind gets the message naming its
  kind.
- **A finding about another resource can go stale.** Whether a destination
  has a table, a `label_field` or a field policy is looked up when the
  resource naming it compiles. A later change to the destination does not
  recompile that resource, so the finding appears or disappears at the next
  full build: one more reason for `--force`. At runtime the table checks
  again.
- **The destroy warning is not printed beside an error about the actions.**
  The row-action verifier reports errors first: a wrong `action` plus a
  destroy action without `confirm` shows the error, and the warning once the
  error is fixed.
- **The checks know nothing of people.** Whether a person can see a column or
  run an action is a matter of policies, decided per request. See
  [Authorization](authorization.md).

## Things people trip over

- **"It compiled, so the block is right."** Look for warnings, or use
  `--force --warnings-as-errors`.
- **"CI is green with `--warnings-as-errors`."** Not if CI reuses a `_build`
  in which the resource was already compiled. Add `--force`.
- **`mix format` adds parentheses to the block.** The formatter does not know
  the DSL: add `:ash_data_table` to `import_deps` in `.formatter.exs`. Not a
  compile-time finding, but it shows up at the same moment.
- **Reading the message without the path.** The line above the message says
  which column and option it is about.

## Not in the first version

Nothing checks what a component renders: that its editor holds a control
with `{@control}` on it, or that its cell stays one line high. See
[Custom components](custom-components.md). Later slices are listed in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
