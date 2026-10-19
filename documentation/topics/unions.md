# Unions

A union is a value that is one of several kinds: a number or a text, a card
or a bank transfer. On the resource it is an attribute of the type `:union`
(`Ash.Type.Union`), which names its kinds as `types`. A table shows such a
value as what it holds, and edits it in the side panel: first the kind,
then that kind's value. This guide covers what a cell shows, how the panel
works, what the action is given, which unions cannot be edited, and what Ash
does on the way.

Related: [Maps and embedded resources](maps-and-embedded-resources.md) for
the kinds that are made of fields, [Inline editing](inline-editing.md) for
the rules every editable cell follows, and
[Row actions and create](row-actions-and-create.md) for the action panel.

## The smallest example

A specimen of the demo has a union
([`demo/lib/demo/kitchen_sink/specimen.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/kitchen_sink/specimen.ex)):

<!-- source: demo/lib/demo/kitchen_sink/specimen.ex -->
```elixir
# A union: a value that is one of several kinds. Shown as the value it
# holds, and edited in the side panel, the kind first.
attribute :a_union, :union do
  public? true

  constraints types: [
                number: [type: :integer, constraints: [min: 0]],
                text: [type: :string],
                shade: [type: Shade],
                address: [type: Address]
              ]
end
```

Nothing is declared for it in a `table` block. The specimens' table shows
the public attributes, `a_union` among them, and its `update_action` accepts
`a_union`, so the cell is editable:

<!-- source: demo/lib/demo/kitchen_sink/specimen.ex -->
```elixir
table do
  update_action :update
end
```

**Try it:** open `/specimens` in the demo and go to the column "A union".
The first rows show `969`, then `Street: Unionsweg 559, City: Leipzig,
Primary?: No`. Move to the first of them and press Enter. The side panel
opens with "Kind", which says "Number", and under it the number. Choose
"Address": the number goes, and the fields of an address are there. Fill in
the street and the city and use "Save".

## What a cell shows

The value the union holds, shown as a cell of that kind's type shows it.
Nothing says which kind it is.

| The kind | What the cell shows |
| --- | --- |
| A number, a text, a date, a datetime | The value as it is written |
| A boolean | The check mark of a boolean cell, with "Yes" or "No" for a screen reader |
| An enum, an atom with `one_of` | The label of the value |
| An embedded resource, a map | Its one line: `Street: Unionsweg 559, City: Leipzig` |
| Anything else | The value as text |

No value is an empty cell, and so is a kind that holds nothing.

An array of unions shows its values one after the other, with `; ` between
them. A union inside an embedded resource or a map follows its field's
label, as every field does: `Label: Box, Either: 5`.

## Editing in the side panel

Enter or a double click on the cell opens the side panel: the
[action panel](row-actions-and-create.md#the-fields-of-the-panel), headed by
the column and the record, with "Save" and "Cancel". A key that types a
character does nothing on such a cell: there is nothing in the cell to type
into. When the panel closes, focus is on the cell again. The panel opens
over the page or in it, as for
[a map cell](maps-and-embedded-resources.md#editing-in-the-side-panel).

The union is a group, named by the column's label. In it:

1. **"Kind"**: a choice of the union's kinds, each called by its name in
   words (`number` is "Number"). It has the focus when the panel opens.
2. **The value of that kind**, under the choice:
   - a kind that holds one value has the one control of its type, called
     what the kind is called: a number input "Number", a choice "Shade";
   - a kind made of fields has its fields, each with its own label and
     control, as [the group of a map cell](maps-and-embedded-resources.md#editing-in-the-side-panel)
     has them.

| In the panel | Effect |
| --- | --- |
| Choosing another kind | The fields of that kind take the place of the others, empty. Nothing is saved. What was typed for the other kind is gone. |
| Choosing the empty entry of "Kind" | No fields: the union has no value. |
| Typing, ticking, choosing | Changes the panel only. |
| "Save" | Saves the value: see [Saving](#saving). |
| "Cancel", Escape | Closes the panel. Nothing is saved. |

"Kind" has an empty entry where the attribute may be empty, and until a
kind is chosen. A union that cannot be empty (`allow_nil? false`) is marked
as required, and offers no empty entry once it has a kind.

The fields of the kind are rendered by the server when the kind is chosen.
What was typed for one kind is never taken as the value of another: a text
that was typed while "Text" was chosen is not saved as a number because
"Number" was chosen a moment before "Save".

## Saving

"Save" follows the rule of every cell ([What a save does](inline-editing.md#what-a-save-does)):
the column's `update_action` runs with the column's attribute as its only
input, through `AshPhoenix.Form`, as the person. A panel that holds what the
record holds closes and runs no action, and `confirm` on the column asks
only when something was changed.

The action is given the kind and its value in the shape Ash takes a union
in from outside (`Ash.Type.Union`, and `AshPhoenix.Form`), with the value as
it was typed. This is a sketch of what the action receives for an address:

<!-- sketch -->
```elixir
%{
  "a_union" => %{
    "_union_type" => "address",
    "_union_value" => %{"street" => "Kai 1", "city" => "Kiel", "postcode" => "", "primary?" => "true"}
  }
}
```

No kind is given as no value (`nil`). Ash casts the value as the kind that
was named: a table does not leave it to Ash to try the kinds one after the
other, so the order of an untagged union's `types` makes no difference to
what is saved.

## When a save fails

The panel stays open, with everything as it was typed:

- **An error about the value of a kind that holds one value** is shown at
  that value's control, which is marked (`aria-invalid`): "must be greater
  than or equal to 0" under the number.
- **An error about a field of a kind made of fields** is shown at that
  field.
- **An error about the union where no control is to show it at** (no kind
  is chosen, or the kind is made of fields) is shown under the union's
  label.
- **Anything else** is shown above the fields, as in every panel.

All of it is read out. Before "Save" is used, the errors of a field are
shown once the person has been in it.

## What can be edited

A union's cell is editable on the conditions of every cell
([What makes a cell editable](inline-editing.md#what-makes-a-cell-editable)),
and when **every kind has a control**:

| The kind's type | Control |
| --- | --- |
| Text, a number, a boolean, a date, a datetime | That of a cell of the type |
| An enum, an atom with `one_of` | A choice of the values |
| A value written as one line of text (a key, a time) | A text input |
| An embedded resource, a map that declares its fields | Its fields, where [all of them can be given](maps-and-embedded-resources.md#what-can-be-edited) |
| An array, a map that declares no fields, a tuple, and so on | None |

It is all or nothing: a union with one kind that has no control is
read-only, and still shown. A person who opens the panel can choose any
kind, so a table that could not give one of them would offer a choice it
cannot keep.

An **array of unions** is shown and not edited.

A NewType of a union is a union. A union inside an embedded resource or a
map is one of that value's fields: the group has the choice of the kind and
the kind's value in it, and the embedded resource stays editable.

A column's own `update_action` on a union that cannot be edited is reported
when the resource is compiled, with the kind that stands in the way
([Mistakes at compile time](mistakes-at-compile-time.md#columns)).

## What Ash does with the value

- **An embedded resource among the kinds is cast through its create
  action, every time.** `Ash.Type.Union` casts the value it is given as a
  new value of the kind, whichever kind the record held; it does not run
  the embedded resource's update action. So the fields the panel asks for
  are the public attributes the **create** action accepts, and a private
  attribute of the old value is not carried over. (For an embedded resource
  that is an attribute of its own, both actions count:
  [What Ash does with the value](maps-and-embedded-resources.md#what-ash-does-with-the-value).)
- **A tagged union is given its tag by the table.** Where the union tells
  its kinds apart by a key of the value (`tag` and `tag_value`), the panel
  does not ask for that key, and the table gives it with the value. An
  embedded resource that has an attribute for it is shown with it, as with
  every public attribute.
- **The embedded resource's actions are not held to "only `public?`
  actions"**, for the reason given for embedded resources: Ash runs them
  while it casts the attribute
  ([Private actions](maps-and-embedded-resources.md#what-ash-does-with-the-value)).

## In the action panel

An input of a row action, of a table action, of an action on the selected
rows, or of the create action that is a union is the same group, under the
input's label, between the other fields. An argument is treated as an
attribute is.

- **Of a row action** an attribute starts with what the record holds, and
  an argument without a kind.
- **Of the create action** a union starts with its default, if the
  attribute has one that is a value, else without a kind.
- **Of an action on the selected rows** it starts without a kind, and no
  kind is given to every record as no value.

An argument that is a union with a kind a table has no control for is left
out of the panel when the action runs without it; an action that requires
one cannot be run from a table, which the compiler reports. A union is no
input of the [argument line](arguments.md).

## Sorting and filtering

A union is neither sorted nor filtered by. Ash stores it as a map of its
kind and its value, and `ash_json_api` and `ash_graphql` both leave unions
out of what they sort and filter by. `sortable? true` or `filterable? true`
on such a column is reported when the resource is compiled.

## Translating the kinds

What a kind is called is your resource's wording, looked up in the Gettext
domain `ash_data_table` of your backend, as a column's label and the label of an
enum's value are ([Messages and translations](messages-and-translations.md#your-resources-wording)).
"Kind" itself is one of the table's own texts. The demo translates both
([`demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po)):

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "Kind"
msgstr "Art"

# ...

msgid "Number"
msgstr "Zahl"

msgid "Text"
msgstr "Text"

msgid "Shade"
msgstr "Farbton"
```

**Try it:** on `/specimens`, choose "Deutsch" in the page header and open
the panel of "A union": "Art" offers "Zahl", "Text", "Farbton" and
"Adresse".

## Edge cases

- **Ash keeps the kind of a value that was taken away.** Saving "no kind"
  over a number gives the action no value, and Ash then stores the union as
  a number that holds nothing. A table treats that as no value: the cell is
  empty, and the panel opens without a kind.
- **A union that cannot be empty can be emptied through Ash.** For the same
  reason Ash does not refuse "no value" for an `allow_nil? false` union
  that had one: what it stores is a kind that holds nothing. The panel
  offers no empty entry for such a union once it has a kind.
- **A kind that holds one value, left empty.** "Number" with nothing typed
  is saved as a number that holds nothing, which a table shows as no value.
- **An error about a field that two values have.** For some errors of a
  value inside a value Ash names the value around it
  ([When a save fails](maps-and-embedded-resources.md#when-a-save-fails)).
  Where an embedded resource has a field of the same name as a field of the
  kind inside its union, the error is shown at the outer field.
- **A map among the kinds says "is invalid" about itself** when one of its
  fields could not be cast, as a map does anywhere. It is shown under the
  union's label.
- **The create action of an embedded kind runs while a person types**, as
  for every embedded resource: the panel gives the action what its fields
  hold, to show its errors.
- **Two people edit the same value.** As for every cell: the last save
  wins.

## Things people trip over

- **The update action may need `require_atomic? false`.** Ash cannot update
  a union in a single statement. The compiler says so; it is not about
  tables.
- **The cell is read-only though the action accepts the attribute.** One of
  the kinds has no control: an array, a map without `fields`, a tuple. A
  column-level `update_action` makes the compiler say which.
- **A private attribute of an embedded kind is empty after a save.** The
  value was created anew: see [What Ash does with the value](#what-ash-does-with-the-value).
- **The kind is not in the cell.** A table shows the value and no mark of
  the kind. Where the kind matters to a reader, give the kinds values that
  tell them apart, or show the kind in a calculation column.
- **"Kind" is in English in a translated table.** It is one of the table's
  own texts: add it to your `ash_data_table.po`.

## Not in the first version

- **Editing an array of unions.**
- **A kind that is an array**, or a union among the kinds of a union (Ash
  flattens those itself).
- **A filter by the kind or by the value**, and a sort.
- **A mark of the kind in the cell.**
- **The update action of an embedded kind**, which `Ash.Type.Union` does
  not run.
- **Showing constraints before saving**, as for every editor.

The display of constraints is a later slice in the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
