# Maps and embedded resources

Some values are made of fields: an embedded resource, a map, or an array of
either. A table shows such a value on one line, `field: value, field:
value`, and edits it in the side panel, where each field has the control of
its own type.

Related: [Inline editing](inline-editing.md) for the rules every editable
cell follows, [Row actions and create](row-actions-and-create.md) for the
action panel, and [Authorization](authorization.md) for who may do what.

## The smallest example

A project of the demo has a client
([`demo/lib/demo/tracker/project.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/project.ex)):

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
# An embedded resource, with another one inside it: shown on one line,
# edited in the side panel.
attribute :client, Demo.Tracker.Client, public?: true
```

The client is an embedded resource
([`demo/lib/demo/tracker/embedded/client.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/embedded/client.ex)):

<!-- source: demo/lib/demo/tracker/embedded/client.ex -->
```elixir
attributes do
  attribute :name, :string do
    allow_nil? false
    public? true
    constraints min_length: 2, max_length: 60
  end

  attribute :email, :string, public?: true

  attribute :key_account?, :boolean do
    allow_nil? false
    default false
    public? true
  end

  # An embedded resource inside an embedded resource.
  attribute :address, Demo.Tracker.Address, public?: true

  # Private on purpose: never shown, never asked for.
  attribute :credit_note, :string
end
```

Nothing is declared in a `table` block. The projects' table shows the public
attributes, `client` among them, and its `update_action` accepts `client`,
so the cell is editable. One cell of the demo shows:

<!-- sketch -->
```text
Name: Hafen & Söhne, Email: office@hafensohne.test, Key account?: Yes, Address: Street: Ernstweg 48, City: München, Postcode: 60948
```

**Try it:** open `/projects` in the demo as Ada Admin, move to a "Client"
cell and press Enter. The side panel opens with the client's fields, the
address as a group among them. Change the city and use "Save".

## What counts as a value made of fields

| The attribute's type | In a table |
| --- | --- |
| An embedded resource | Shown by its public attributes; edited in the side panel |
| A map that declares its fields (`:map` with the `fields` constraint) | Shown by its declared fields; edited in the side panel |
| A map that declares none | Shown by whatever keys it holds; read-only |
| An array of any of these | Shown as its values, with `; ` between them; edited as a list of groups, or read-only for maps without fields |
| A NewType of any of these | As what it is made of |

The demo has one of each. A task's "Repeats" is a map that declares its
fields
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# A map that declares its fields: how often a task comes round again.
attribute :recurrence, :map do
  public? true

  constraints fields: [
                every: [type: :integer, allow_nil?: false, constraints: [min: 1, max: 365]],
                unit: [
                  type: :atom,
                  allow_nil?: false,
                  constraints: [one_of: [:day, :week, :month]]
                ],
                until: [type: :date]
              ]
end
```

A project's milestones are an array of embedded resources:

<!-- source: demo/lib/demo/tracker/project.ex -->
```elixir
# An array of embedded resources.
attribute :milestones, {:array, Demo.Tracker.Milestone} do
  allow_nil? false
  default []
  public? true
end
```

`/specimens` has the rest: "An address" and "Addresses" (an array of
embedded resources without a primary key), "A typed map", and "A map",
which declares no fields.

Types that only look like these are read-only text: an `Ash.Type.Struct`
(also one of a resource), an `Ash.TypedStruct`, a keyword list and a tuple.
See [Not in the first version](#not-in-the-first-version).

## What a cell shows

One line of plain text: each field that holds something, as `label: value`,
with `, ` between them, and no braces, quotes or marks.

- **The label** is the field's name in words, as a column of that name
  would be called: `key_account?` is "Key account?", `due_on` is "Due on".
  It goes through your Gettext backend as a column's label does
  ([Messages and translations](messages-and-translations.md#your-resources-wording)).
- **The value** is shown as a cell of its own type shows it: "Yes" and "No"
  for a boolean, the label of an enum's value, a date as written, an array's
  values with commas between them.
- **A field that holds nothing is left out.** A value none of whose fields
  holds anything is an empty cell, as no value is.
- **A value made of fields inside it** follows its label the same way:
  `Address: Street: Ernstweg 48, City: München`.
- **An array** is its values with `; ` between them:
  `Title: Kick-off, Reached?: Yes; Title: Review, Reached?: No`.
- **A map that declares no fields** shows its keys in alphabetical order,
  each in words, with its values as text.

### Which fields of an embedded resource

Its **public attributes**, in declaration order. A table shows only what is
`public?`, in an embedded resource as in a resource.

- A private attribute is never shown or asked for. The demo's client has
  one, `credit_note`.
- Calculations of an embedded resource are not shown. They are on a value
  only where the attribute's `load` constraint puts them, and an embedded
  resource has no aggregates.
- **The primary key is left out when nobody gives it.** A milestone's
  generated `id` says which milestone a value is, not what it holds, so the
  cell does not show it and the panel does not ask for it. A primary key the
  embedded resource's actions accept is a field like any other.
- A `sensitive?` attribute is shown as a mask (`••••••`), and a value with a
  sensitive attribute a person would give is not edited in a table. See
  [Sensitive columns](sensitive-columns.md#inside-a-value-made-of-fields).

## What can be edited

Such a cell is editable on the conditions of every cell
([What makes a cell editable](inline-editing.md#what-makes-a-cell-editable)):
an `update_action` of the column or the table accepts the attribute, the
attribute is writable, and the person may run the action. Besides, **a
person has to be able to give every input of the value**:

- **Every input has a control.** The controls are those of the action
  panel: text, number, boolean, date, datetime, a choice, an array of
  those, a value written as one line of text (a time, a key), a value made
  of fields (for which the same holds in turn), and a union whose every kind
  has a control ([Unions](unions.md)). A tuple, for one, has none.
- **A map declares its fields.** A map without `fields` could hold anything,
  so a table does not know what to ask for.
- **The embedded resource's create and update actions accept the same
  public attributes.** See [What Ash does with the value](#what-ash-does-with-the-value).
- **Its actions need nothing a table cannot give:** no argument they cannot
  run without, and no private attribute a new value has to have.

It is all or nothing: where one input cannot be given, the whole cell is
read-only (and still shown). What Ash creates in place of an existing value
holds what it was given and nothing else, so leaving one field out would
lose what it held.

A column's own `update_action` on a cell that cannot be edited is reported
at compile time, with what stands in the way
([Mistakes at compile time](mistakes-at-compile-time.md#columns)).

### Which fields are asked for

- Of a map: every field it declares.
- Of an embedded resource: the public attributes accepted by the actions Ash
  casts the value through. An attribute shown but not accepted (a
  timestamp, the generated primary key) is not in the panel; it keeps what
  it holds or the resource fills it in.

A field is marked required where the embedded resource's create action does
not take it empty (`allow_nil? false`, `require_attributes`,
`allow_nil_input`, as for any action's inputs), and for a map where the
field says `allow_nil?: false`. The mark is a hint; the action decides.

## Editing in the side panel

Enter, Space or a double click on the cell opens the side panel: the
[action panel](row-actions-and-create.md#the-fields-of-the-panel), headed by
the column and the record ("Client: Customer portal"), with "Save" and
"Cancel". A character key does nothing on such a cell: there is nothing in
it to type into.

The value is a **group** named by the column's label, holding the value's
inputs in field order, each with its own label and control. A value made of
fields inside it is a group in the group. A group is marked only by its
label and the indentation of what belongs to it.

| In the panel | Effect |
| --- | --- |
| Typing, ticking, choosing | Changes the panel only. Nothing is saved. |
| "Save" | Saves the value: see [Saving](#saving). |
| "Cancel", Escape | Closes the panel. Nothing is saved. |

Focus goes into the first field when the panel opens, and back to the cell
when it closes.

The panel opens over the page or in it, as the table's presentation says
([Layout and embedding](layout-and-embedding.md)). Over the page (the
default kit's), the rest of the page cannot be reached while it is open. In
the page nothing else is out of reach: Escape inside the panel is Cancel,
and Tab can leave it.

### A value that can be left out

A value that may be empty has a button beside its label that takes it away
("Remove Address"); a value that is not there has "Add value" in place of
its fields. A value that cannot be empty (`allow_nil? false` on the
attribute, or on a map's field) has no such button.

No group is no value; a group is the value its fields say. A table does not
guess: a group added and left empty is given as a value with empty fields,
which the embedded resource refuses if it requires one of them. To have no
address, take the address away.

### An array

An array of values made of fields is a **list of groups**, working as the
field of an array of plain values does:

- one group per value, named by the column's label and the value's place
  ("Milestones 2"), each with a button that takes it away ("Remove
  Milestones 2");
- under them, "Add value": a new value goes after the others, with focus in
  its first field;
- when a value is taken away, focus goes to the value after it, else the one
  before, else "Add value".

No values is the empty array, not nil.

## Saving

"Save" follows the rule of every cell ([What a save does](inline-editing.md#what-a-save-does)):

- **One input.** The column's `update_action` runs with the column's
  attribute as its only input, through `AshPhoenix.Form`, as the person.
  The value is a map of its fields, an array a list of such maps, as an API
  gives them. A field left empty is sent empty; what it becomes is Ash's
  casting.
- **Unchanged calls nothing.** "Save" on a panel that holds what the record
  holds closes the panel and runs no action.
- **`confirm`** on the column asks on "Save", only when something changed.
  Cancel there returns to the panel with everything as typed. The demo's
  "Repeats" asks.
- **The row is shown from what the action returns.**

The table checks nothing: constraints, the embedded resource's own
validations and the action decide.

## When a save fails

The panel stays open, with everything as typed, and shows what the action
returned:

- **An error about a field of the value** is shown at that field, in its
  group, and the field is marked (`aria-invalid`). In an array, at that
  field of that value.
- **An error about the value as a whole**, or about something in it the
  panel has no field for, is shown at the group, under its label.
- **Anything else** (a refusal, a validation about another field of the
  record) is shown above the fields: "You are not allowed to change this.",
  "Name: is locked".

All of it is read out. Before "Save", a field's errors are shown once the
person has been in it, as in every action panel.

Ash does not always say exactly where an error belongs. Two cases a table
makes the best of:

- For some errors of a value inside a value, Ash names the outer value.
  Where exactly one value in it has a field of that name, the error is shown
  there; otherwise at the group, after the field's name ("Postcode: must
  match …").
- A map says "is invalid" about itself, without naming the field, when one
  of its fields could not be cast at all (text where a number belongs). The
  message is shown at the map's group.

## In the action panel

An input that is a value made of fields, of a row action, an action on the
selected rows or the create action, is the same group under the input's
label, among the other fields. So "New project" can give the client, its
address, and the milestones.

- **Row action:** the group starts with what the record holds.
- **Create action:** a value the record cannot be without is there to fill
  in; one that can be left out is added with "Add value".
- **Action on the selected rows:** every group starts without a value and
  every list empty, as every field of that panel starts empty; what the
  panel holds is given to every record.

An argument is treated as an attribute is. Such an input that cannot be
edited is left out of the panel when the action runs without it; an action
that requires one cannot be run from a table
([Inputs the panel has no field for](row-actions-and-create.md#inputs-the-panel-has-no-field-for)).

## What Ash does with the value

A table gives the action a map. Ash casts it through the embedded
resource's own actions, which a table never names:

| The value | Ash runs |
| --- | --- |
| A value where there was none, and every value of an array that is new | the create action |
| A value in place of an existing one | the update action on the existing value. With a public primary key only when the key is the same; else the old value is destroyed and a new one created. With `on_update: :replace`, always a create. |
| A value of an array whose public primary key matches an existing one | the update action |
| A value of an array of a resource without a public primary key | the create action, for every value, and the destroy action for every old one |
| No value where there was one | the destroy action |

They are the actions the attribute's constraints name (`create_action`,
`update_action`, `destroy_action`; for an array under `items`), else the
embedded resource's primary ones. They run with the actor and tenant of the
action that accepted the attribute, and are authorized as that action is:
an embedded resource with its own policies can refuse.

Three things follow.

**Identity in an array.** A milestone has a public primary key
([`demo/lib/demo/tracker/embedded/milestone.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/embedded/milestone.ex)):

<!-- source: demo/lib/demo/tracker/embedded/milestone.ex -->
```elixir
attributes do
  uuid_primary_key :id

  attribute :title, :string do
    allow_nil? false
    public? true
    constraints min_length: 3, max_length: 60
  end

  attribute :due_on, :date, public?: true

  attribute :reached?, :boolean do
    allow_nil? false
    default false
    public? true
  end
end
```

The panel sends each milestone's `id` back in a hidden input, so Ash updates
the milestones still in the list, creates the added ones and destroys the
removed ones. An embedded resource without a public primary key has no
identity to keep: every save of the array destroys all its values and
creates the ones the panel holds.

**Why both actions have to accept the same.** Ash refuses an input the
action does not accept, and which of the two runs for a value is only known
when the action runs. So a table can ask for one set of fields only, and an
embedded resource whose create and update actions accept different public
attributes is read-only. With `on_update: :replace` only the create action
counts.

**Private actions.** A table runs only `public?` actions
([Every action a table runs is public](authorization.md#every-action-a-table-runs-is-public)),
but an embedded resource's actions are not run by the table and not among
those it checks. Ash runs them while it casts the value of an attribute a
public action of your resource accepts, whichever interface gave the value,
and does not look at `public?`. Neither do `ash_json_api` and
`ash_graphql`. A table offers the public attributes those actions accept; to
keep a field from a table, make the attribute private or leave it out of
the actions' `accept`.

## Sorting and filtering

A value made of fields is neither sorted nor filtered by.

- **Sorting.** Ash does not sort by a map
  (`Ash.Resource.Info.sortable?/3`), and `Ash.Query.sort_input/2`, through
  which a table sorts, refuses an embedded resource. An array is not sorted
  by either. `ash_json_api` and `ash_graphql` also leave embedded resources
  out of what they sort by.
- **Filtering.** Ash's interface extensions offer no filter for an embedded
  resource or a map. Ash can compare a field inside one (`at_path` in a
  filter given from outside), but compares the stored value with what was
  typed without casting it, so a number would be compared with text. A
  table offers no filter Ash does not stand behind.

`sortable? true` or `filterable? true` on such a column is reported at
compile time.

## Who may edit, and field policies

As for every cell, editing depends on the policy of the column's update
action. A person who can never run it is offered no editor; one who may run
it on some records is told on "Save", in the panel.

A field policy of your resource hides the whole attribute, on every record
or some, as for any field: the column is left out, or the cell says "Not
available" ([Authorization](authorization.md#what-each-restriction-looks-like)).
It cannot name a field inside the value.

An embedded resource can have its own field policies, which Ash applies when
your resource is read. A field they hide from the person is left out of the
cell like an empty field, and **the cell is then not theirs to edit**:
saving would overwrite what they cannot see.

## Custom components

A column of such a value can have a `component`
([Custom components](custom-components.md)). Its `cell/1` is given the value
as the record holds it (an embedded resource's struct, a map, or a list of
them), the table's own one-line text as `text`, and a column whose
`cell_type` is `:map` or `{:array, :map}`. Its `editor/1` is not used: the
value is edited in the side panel with the table's own fields.

## Translating the fields

A field's label is your resource's wording, looked up in the Gettext domain
`ash_data_table` of your backend, as a column's label is. The demo
translates the fields of a task's recurrence
([`demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po)):

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "Repeats"
msgstr "Wiederholung"

# ...

msgid "Every"
msgstr "Alle"

msgid "Unit"
msgstr "Einheit"

msgid "Until"
msgstr "Bis"
```

A text is looked up by what it says, not where it is used: "Name" is
translated once, for a column and a client's field alike.

## Edge cases

- **A value its fields no longer describe.** A map holding keys its `fields`
  do not declare shows the declared ones. Saving it through the panel stores
  only the declared fields: Ash drops the others when it casts the map.
- **A box that was never ticked.** A boolean field holding nothing is an
  unticked box, which a form sends as "false". "Save" without a change still
  calls nothing; once something else changes, the field is saved as false.
- **A map field that was never set.** Ash stores a map without its empty
  fields. The panel sends them empty, which Ash stores the same way.
- **The place Ash names for a value of an array can be wrong.** When an
  embedded resource has its own changes, validations or policies, Ash
  creates an array's new values together and counts a failing value's place
  among those, not among the whole list. The error then shows at another
  value's field; the message itself is right.
- **The embedded resource's actions run while a person types.** To show
  errors, the panel gives the action its fields as they change
  (`AshPhoenix.Form.validate/3`), and Ash casts the value through the
  embedded resource's actions, as a nested AshPhoenix form does. Nothing is
  stored, but actions that do more than build the value (a notifier, a call
  to another system) do it then too.
- **Two people edit the same value.** As for every cell: the last save wins,
  and the panel holds what the record held when it opened.
- **A value inside itself.** An embedded resource holding a value of its own
  type is read-only. (Ash 3.36.1 does not compile one.)
- **A long value** is cut off in the cell, as every cell's text is. The
  panel shows all of it, and so does "Show all" (or Shift+Enter) in the
  cell, in place: see [Long text](columns-and-defaults.md#long-text).

## Things people trip over

- **The update action may need `require_atomic? false`.** Ash cannot always
  update an embedded resource in a single statement; where it cannot, the
  compiler says so. It is not about tables.
- **"Add value" then "Save" fails with "is required".** A group that is
  there is a value. Take it away to have none.
- **A field is missing from the panel.** It is private, or the embedded
  resource's actions do not accept it.
- **The cell is read-only though the action accepts the attribute.** An
  input has no control, the map declares no `fields`, or the embedded
  resource's create and update actions accept different attributes. A
  column-level `update_action` makes the compiler say which.
- **An `id` shows up in the cell.** The embedded resource's actions accept
  its primary key, making it a field like any other.

## Not in the first version

- **Structs, typed structs, keyword lists and tuples** stay read-only text.
  An `Ash.Type.Struct` with `fields` and an `Ash.TypedStruct` are cast as a
  map with fields is and would be edited the same way; they are left for
  later. A keyword list would fit too. A tuple takes no map as input.
- **Arrays of unions**, also inside an embedded resource, which makes that
  resource read-only. A single union is a field like any other: see
  [Unions](unions.md).
- **Calculations of an embedded resource.**
- **A filter by a field of the value**, and a sort.
- **Editing a value that has a `sensitive?` input**, and a "Show" button for
  a sensitive field inside a value. The field is masked on the line.
- **Reordering the values of an array.** A value is added at the end.
- **Showing constraints before saving**, as for every editor.

The display of constraints is a later slice in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
