# Unions

A union is a value that is one of several kinds: a number or a text, a card
or a bank transfer. On the resource it is a `:union` attribute
(`Ash.Type.Union`) that names its kinds as `types`. A table shows the value it
holds and edits it in the side panel: first the kind, then that kind's value.

Related: [Maps and embedded resources](maps-and-embedded-resources.md) for
kinds made of fields, [Inline editing](inline-editing.md) for the rules of
every editable cell, [Row actions and create](row-actions-and-create.md) for
the action panel.

## The smallest example

A demo specimen has a union
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

Nothing is declared for it in the `table` block. The table shows the public
attributes, `a_union` among them, and its `update_action` accepts `a_union`,
so the cell is editable:

<!-- source: demo/lib/demo/kitchen_sink/specimen.ex -->
```elixir
table do
  update_action :update
end
```

**Try it:** open `/specimens` in the demo, column "A union". The first rows
show `969`, then `Street: Unionsweg 559, City: Leipzig, Primary?: No`. Move to
the first and press Enter. The side panel opens with "Kind" set to "Number"
and the number below. Choose "Address": the number goes and an address's
fields appear. Fill in street and city and use "Save".

## What a cell shows

The value the union holds, as a cell of that kind's type shows it. Nothing
says which kind it is.

| The kind | What the cell shows |
| --- | --- |
| A number, a text, a date, a datetime | The value as it is written |
| A boolean | The check mark of a boolean cell, with "Yes" or "No" for a screen reader |
| An enum, an atom with `one_of` | The label of the value |
| An embedded resource, a map | Its one line: `Street: Unionsweg 559, City: Leipzig` |
| Anything else | The value as text |

No value, or a kind that holds nothing, is an empty cell.

An array of unions shows its values separated by `; `. A union inside an
embedded resource or a map follows its field's label, like every field:
`Label: Box, Either: 5`.

## Editing in the side panel

Enter, Space or a double click opens the side panel: the
[action panel](row-actions-and-create.md#the-fields-of-the-panel), headed by
the column and the record, with "Save" and "Cancel". A character key does
nothing on such a cell: there is nothing in it to type into. When the panel
closes, focus returns to the cell. The panel opens over the page or in it, as
for [a map cell](maps-and-embedded-resources.md#editing-in-the-side-panel).

The union is a group named by the column's label, holding:

1. **"Kind"**: a choice of the union's kinds, each by its name in words
   (`number` is "Number"). It has the focus when the panel opens.
2. **The kind's value**, below:
   - a kind holding one value has its type's one control, named like the kind:
     a number input "Number", a choice "Shade";
   - a kind made of fields has its fields, each with its own label and
     control, as in
     [the group of a map cell](maps-and-embedded-resources.md#editing-in-the-side-panel).

| In the panel | Effect |
| --- | --- |
| Choosing another kind | That kind's fields replace the others, empty. Nothing is saved. What was typed for the other kind is gone. |
| Choosing the empty entry of "Kind" | No fields: the union has no value. |
| Typing, ticking, choosing | Changes the panel only. |
| "Save" | Saves the value: see [Saving](#saving). |
| "Cancel", Escape | Closes the panel. Nothing is saved. |

"Kind" has an empty entry where the attribute may be empty, and until a kind
is chosen. A union that cannot be empty (`allow_nil? false`) is marked
required and offers no empty entry once it has a kind.

The server renders a kind's fields when the kind is chosen. What was typed for
one kind is never taken as another's value: a text typed under "Text" is not
saved as a number because "Number" was chosen just before "Save".

## Saving

"Save" follows the rule of every cell
([What a save does](inline-editing.md#what-a-save-does)): the column's
`update_action` runs with the column's attribute as its only input, through
`AshPhoenix.Form`, as the person. A panel unchanged from the record closes
without running an action, and the column's `confirm` asks only when
something changed.

The action gets the kind and its value in the shape Ash takes a union from
outside (`Ash.Type.Union`, `AshPhoenix.Form`), with the value as typed. A
sketch for an address:

<!-- sketch -->
```elixir
%{
  "a_union" => %{
    "_union_type" => "address",
    "_union_value" => %{"street" => "Kai 1", "city" => "Kiel", "postcode" => "", "primary?" => "true"}
  }
}
```

No kind is sent as no value (`nil`). Ash casts the value as the named kind: a
table never lets Ash try the kinds one by one, so the order of an untagged
union's `types` does not affect what is saved.

## When a save fails

The panel stays open with everything as typed:

- **An error on the value of a single-value kind** shows at that control,
  marked `aria-invalid`: "must be greater than or equal to 0" under the
  number.
- **An error on a field of a kind made of fields** shows at that field.
- **An error on the union with no control to show it at** (no kind chosen, or
  a kind made of fields) shows under the union's label.
- **Anything else** shows above the fields, as in every panel.

All of it is read out. Before "Save", a field's errors show once the person
has been in it.

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

All or nothing: a union with one kind lacking a control is read-only, still
shown. The panel lets a person choose any kind, so a table must be able to
take each one.

An **array of unions** is shown, not edited.

A NewType of a union is a union. A union inside an embedded resource or a map
is one of its fields: the group holds the kind choice and the kind's value,
and the embedded resource stays editable.

A column's own `update_action` on a union that cannot be edited is reported at
compile time, naming the kind in the way
([Mistakes at compile time](mistakes-at-compile-time.md#columns)).

## What Ash does with the value

- **An embedded kind is cast through its create action, every time.**
  `Ash.Type.Union` casts the given value as a new value of the kind, whatever
  kind the record held; it never runs the embedded resource's update action.
  So the panel asks for the public attributes the **create** action accepts,
  and a private attribute of the old value is not carried over. (For an
  embedded resource that is an attribute of its own, both actions count:
  [What Ash does with the value](maps-and-embedded-resources.md#what-ash-does-with-the-value).)
- **A tagged union gets its tag from the table.** Where the union tells kinds
  apart by a key of the value (`tag` and `tag_value`), the panel does not ask
  for that key; the table adds it. An embedded resource with an attribute for
  it shows it, like every public attribute.
- **The embedded resource's actions are not held to "only `public?`
  actions"**, as for embedded resources: Ash runs them while casting the
  attribute
  ([Private actions](maps-and-embedded-resources.md#what-ash-does-with-the-value)).

## In the action panel

A union input of a row action, a table action, an action on the selected rows
or the create action is the same group, under the input's label, among the
other fields. An argument is treated like an attribute.

- **Row action:** an attribute starts with what the record holds, an argument
  without a kind.
- **Create action:** starts with the attribute's default if that is a value,
  else without a kind.
- **Action on the selected rows:** starts without a kind; no kind is given to
  every record as no value.

A union argument with a kind the table has no control for is left out of the
panel when the action runs without it; an action that requires one cannot run
from a table, which the compiler reports. A union is no input of the
[argument line](arguments.md).

## Sorting and filtering

A union is neither sorted nor filtered by. Ash stores it as a map of kind and
value, and `ash_json_api` and `ash_graphql` both leave unions out of sorting
and filtering. `sortable? true` or `filterable? true` on such a column is
reported at compile time.

## Translating the kinds

A kind's name is your resource's wording, looked up in the Gettext domain
`ash_data_table` of your backend, like a column's label and an enum value's
label ([Messages and translations](messages-and-translations.md#your-resources-wording)).
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

**Try it:** on `/specimens`, choose "Deutsch" in the page header and open the
panel of "A union": "Art" offers "Zahl", "Text", "Farbton" and "Adresse".

## Edge cases

- **Ash keeps the kind of a removed value.** Saving "no kind" over a number
  gives the action no value, and Ash stores a number that holds nothing. The
  table treats that as no value: empty cell, panel opens without a kind.
- **So an `allow_nil? false` union can be emptied through Ash**: Ash does not
  refuse "no value" for one that had a value, since it stores a kind holding
  nothing. The panel offers no empty entry for it once it has a kind.
- **A single-value kind left empty.** "Number" with nothing typed is saved as a
  number holding nothing, shown as no value.
- **An error on a field two values share.** For some errors inside a nested
  value Ash names the outer value
  ([When a save fails](maps-and-embedded-resources.md#when-a-save-fails)).
  Where an embedded resource has a field named like a field of the kind in its
  union, the error shows at the outer field.
- **A map kind says "is invalid" about itself** when one of its fields could
  not be cast, as a map does anywhere. It shows under the union's label.
- **An embedded kind's create action runs while a person types**, as for
  every embedded resource: the panel gives it the fields' contents to show
  its errors.
- **Two people edit the same value:** the last save wins, as for every cell.

## Things people trip over

- **The update action may need `require_atomic? false`.** Ash cannot update a
  union in a single statement. The compiler says so; it is not about tables.
- **The cell is read-only though the action accepts the attribute.** A kind
  has no control: an array, a map without `fields`, a tuple. A column-level
  `update_action` makes the compiler name it.
- **A private attribute of an embedded kind is empty after a save.** The value
  was created anew: see
  [What Ash does with the value](#what-ash-does-with-the-value).
- **The kind is not in the cell.** Where it matters, give the kinds values
  that tell them apart, or show the kind in a calculation column.
- **"Kind" is in English in a translated table.** It is one of the table's own
  texts: add it to your `ash_data_table.po`.

## Not in the first version

- **Editing an array of unions.**
- **A kind that is an array**, or a union among a union's kinds (Ash flattens
  those itself).
- **Filtering by kind or value**, and sorting.
- **A mark of the kind in the cell.**
- **The update action of an embedded kind**, which `Ash.Type.Union` does not
  run.
- **Showing constraints before saving**, as for every editor; a later slice
  in the [specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
