# Messages and translations

A table shows three kinds of text, each with a different owner. This guide
shows how to translate or reword each kind, which setting covers which, and
what a person reads when one is missing.

## The three kinds of text

| Kind | Examples | Owner | Translated by |
| --- | --- | --- | --- |
| The table's own texts | "No records", "Clear filters", "12 results", the operators of the filters, "You are not allowed to change this.", "Actions", "Run" | The library | `gettext_backend`: the Gettext domain `ash_data_table` in your backend |
| Your resources' wording, as the table shows it | Column labels, the labels of enum values, the questions of `confirm`, the names of the tables, the labels of row actions and table actions and of the fields of the action panel, what one record is called | Your resources | `gettext_backend`: the same domain of the same backend |
| The messages of your actions | "length must be greater than or equal to %{min}", "is required", the `message` of your own validation | Ash and your resources | `translate_error`: your app's error translator |

## The smallest example

Two keys under `config :ash_data_table`; the installer sets both for a new
Phoenix app. In the demo
([`demo/config/config.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/config/config.exs)):

<!-- source: demo/config/config.exs -->
```elixir
config :ash_data_table,
  layout: {DemoWeb.Layouts, :app},
  gettext_backend: DemoWeb.Gettext,
  translate_error: {DemoWeb.CoreComponents, :translate_error}
```

**Try it:** in the demo, choose "Deutsch" in the page header's "Language"
switcher and open `/tasks` as Ada Admin. Headings, filter row, pagination and
the tasks' states are German. Set a title to `ab`: the cell says "muss
mindestens 3 Zeichen lang sein".

Both keys are read at runtime, so changing them needs no recompilation of the
dependency.

## The locale

The table translates in the locale of its process: whatever your plug and
`on_mount` hook set with `Gettext.put_locale/1`. It has no locale setting of
its own. The demo's hook
([`demo/lib/demo_web/locale.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/locale.ex)):

<!-- source: demo/lib/demo_web/locale.ex -->
```elixir
def on_mount(:default, _params, session, socket) do
  put(session[@session_key])
  {:cont, socket}
end
# ...
defp put(locale) do
  Gettext.put_locale(if(known?(locale), do: locale, else: "en"))
end
```

(A line `# ...` in an excerpt stands for lines left out.) The hook must run
for the `live_session` the tables are mounted in, as in the demo's router
(`on_mount: [DemoWeb.Actor, DemoWeb.Locale, DemoWeb.Zone]`).

**Changing the locale needs a new mount.** The locale belongs to the LiveView
process and is set at mount, so a table already on screen does not change
language. The demo's language switcher posts to a controller and redirects,
which reloads the page.

## The table's own texts

Every text of the table's own is a message of the Gettext domain
`ash_data_table`, written in English. Without `gettext_backend` they are
shown in English; with it they are looked up in your backend.

Copy the template that ships with the package to one file per locale and fill
in each `msgstr` (a sketch; the demo's file is already in place):

<!-- sketch -->
```sh
mkdir -p priv/gettext/de/LC_MESSAGES
cp deps/ash_data_table/priv/gettext/ash_data_table.pot priv/gettext/de/LC_MESSAGES/ash_data_table.po
```

Copy it as a `.po` file, not as a template of your own: `mix gettext.extract`
removes from your templates the messages it does not find in your code.

A message without a translation is shown in English. From the demo's German
file
([`demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po)):

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "1 result"
msgid_plural "%{count} results"
msgstr[0] "1 Ergebnis"
msgstr[1] "%{count} Ergebnisse"

msgid "Any"
msgstr "Alle"

msgid "Cancel"
msgstr "Abbrechen"

msgid "Clear filters"
msgstr "Filter zurücksetzen"
```

### Counts: plural forms

A text with a number has a form per number: the result count, the total,
"1 selected" on the selection line and on the button of a filter for several
values, a question about the selected rows, and how many columns the Columns
button says are hidden, filtered or sorted. The table uses Gettext's plural
forms on the server, so the entry has a `msgid_plural` and one `msgstr[n]`
per form of the locale, as the file's `Plural-Forms` line says. From the
demo's German file:

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "1 selected"
msgid_plural "%{count} selected"
msgstr[0] "1 ausgewählt"
msgstr[1] "%{count} ausgewählt"
```

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "Run “%{action}” on 1 record?"
msgid_plural "Run “%{action}” on %{count} records?"
msgstr[0] "„%{action}“ für 1 Eintrag ausführen?"
msgstr[1] "„%{action}“ für %{count} Einträge ausführen?"
```

### Every message, by key

`AshDataTable.Messages` lists every text of the table's own. Its
documentation gives each key with the names of its values and its English
text (the msgid in the template); a key with a form per number also has its
plural msgid and `count` among its values. In code,
`AshDataTable.Messages.all/0` returns the same list as data (`values`,
`msgid`, `msgid_plural` per key), and `AshDataTable.Messages.key?/1` says
whether a key is in it. A table shows no text of its own outside this list.

### Rewording without translating

To say "Nothing to show" instead of "No records" in an English app, give
your backend an `ash_data_table.po` for `en` with that one entry (a sketch;
the demo has no such file):

<!-- sketch -->
```po
msgid "No records"
msgstr "Nothing to show"
```

## Your resources' wording

The table shows text your resources wrote. Each is looked up as a message in
the same `ash_data_table` domain, and shown as it is when the domain has no
entry:

- each column's label (declared with `label`, or the field's name in words);
- the labels of an enum's values;
- the question of a `confirm`;
- the table's name (the resource's `plural_name`, or its short name, in
  words);
- the label of each relationship line under an expanded row (declared with
  `label`, or the relationship's name in words);
- what the inputs of the [argument line](arguments.md) are called: the
  `label` of an `argument` or an `ask`, or the argument's name in words
  ("Search", "Days"), and the labels of the values of an argument that is a
  choice;
- the fields of an embedded resource and of a map, in a cell and in the side
  panel: each is called by its name in words, as a column of that name would
  be (see
  [Maps and embedded resources](maps-and-embedded-resources.md#translating-the-fields));
- the kinds of a union, in the side panel's choice: each is called by its
  name in words ("Number", "Address"; see
  [Unions](unions.md#translating-the-kinds)).

Row actions, table actions and create add five more of the same kind:

| Wording | The message id |
| --- | --- |
| What a row action's button says, and a table action's | Its `label`, or the action's name in words: "Archive", "Set progress", "Remove", "Count unused". |
| A value of an enum that a generic action returned | The label of the value, as in a cell. |
| The question of an action's `confirm` | The question as written: "Delete this task? This cannot be undone." |
| What a field of the action panel is called | The label of the column, for an attribute the table has a column for: the entry that translates the heading translates the field. Else the input's name in words: "Reason", "Assignee ID". |
| What one record is called | The resource's short name in words, in lower case: "task", "task label". It fills the table's own message "New %{name}". |

So the create button is translated in two places, as the demo does for
German: the table's message says where the name goes, and the name is your
resource's wording.

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "New %{name}"
msgstr "%{name} anlegen"
```

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "task"
msgstr "Aufgabe"
```

"New task" is "Aufgabe anlegen". The buttons and the fields of "Reassign"
are entries like a column's label:

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "Archive"
msgstr "Archivieren"

msgid "Reassign"
msgstr "Neu zuweisen"
```

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "Reason"
msgstr "Begründung"
```

The other field of "Reassign" holds the assignee's key and is called what the
column "Assignee" is called: it needs no entry of its own.

**Try it:** `/tasks` in German, as Ada Admin: the column "Aktionen" with
"Archivieren", "Neu zuweisen", "Fortschritt setzen" and "Löschen", and
"Aufgabe anlegen" above the table. "Neu zuweisen" opens a panel with the
fields "Zugewiesen an" and "Begründung" and the buttons "Abbrechen" and
"Ausführen"; "Auswählen" under "Zugewiesen an" opens the picker, "Zugewiesen
an: Person auswählen".

A reference cell shows a related record's label, which is data and is not
translated. The heading over a table limited to one parent's records is the
table's message "%{record}: %{relationship}", filled with that record's label
and the relationship's translated label; a translation can swap the two.

A column is translated by adding its label to the same file. The demo
translates the wording of `/tasks`:

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "Tasks"
msgstr "Aufgaben"

msgid "Title"
msgstr "Titel"

msgid "State"
msgstr "Status"
```

The message id is the English text exactly as the table would show it:
"State" for the column declared with `label "State"`, "Due on" for the field
`due_on`, "In progress" for the enum value's label. The tables mounted beside
`/tasks` have entries for their row actions, their questions and what one of
their records is called, but none for their columns: a heading there is
German only where it reads exactly like an existing entry, such as "Name".

## The messages of your actions

What an action says when it refuses a value is Ash's ("is required") or
yours, not the table's. The table hands each such message to the function
named by `translate_error` as `{message, variables}`. That is what a Phoenix
app's core components `translate_error/1` takes, so the table shows an
action's message in the same words as your forms. The demo's is the one the
Phoenix generator wrote
([`demo/lib/demo_web/components/core_components.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo_web/components/core_components.ex)):

<!-- source: demo/lib/demo_web/components/core_components.ex -->
```elixir
def translate_error({msg, opts}) do
  # ...
  if count = opts[:count] do
    Gettext.dngettext(DemoWeb.Gettext, "errors", msg, msg, count, opts)
  else
    Gettext.dgettext(DemoWeb.Gettext, "errors", msg, opts)
  end
end
```

It looks the message up in the domain `errors` and fills in the variables.
The key is the message as the action wrote it, placeholders included. From
the demo's
[`errors.po`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/priv/gettext/de/LC_MESSAGES/errors.po):

<!-- source: demo/priv/gettext/de/LC_MESSAGES/errors.po -->
```po
## Ash: a string shorter than its `min_length`
msgid "length must be greater than or equal to %{min}"
msgstr "muss mindestens %{min} Zeichen lang sein"
```

Without `translate_error`, a message is shown as the resource wrote it, with
its variables filled in.

### Custom validation messages

A `message` of your own is a translation key like any other. The demo's
tasks have a validation with one
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
validate compare(:progress, greater_than_or_equal_to: 100) do
  on [:create, :update]
  where attribute_equals(:status, :done)
  message "must be 100 when the task is done"
end
```

and its German text is an entry under exactly that message:

<!-- source: demo/priv/gettext/de/LC_MESSAGES/errors.po -->
```po
## Demo.Tracker.Task: the validation of `status` against `progress`
msgid "must be 100 when the task is done"
msgstr "muss 100 sein, wenn die Aufgabe erledigt ist"
```

A message, yours or Ash's, is translated only if the `errors` domain has an
entry for it.

### The field prefix

An inline edit sends one field, but the action may complain about another.
The validation above fails when a person sets the state to "Done" on a task
with progress 40: the error is about `progress`, the edited cell is the
state. The table shows the error on the edited cell, prefixed with the other
field's column label:

| Language | The state cell says |
| --- | --- |
| English | "Progress: must be 100 when the task is done" |
| German | "Fortschritt: muss 100 sein, wenn die Aufgabe erledigt ist" |

The sentence has three parts with three owners: the label ("Progress", your
resource's wording), the message (your action's, through `translate_error`),
and the frame "%{field}: %{message}" (the table's own). The screen reader
announcement is framed the same way: "%{column} was not saved: %{message}".

A row action uses the same frame. An error about a field shown on the row's
actions cell, or above the action panel's fields, has the field's column
label in front, by the two rules below. An error at a panel field has no
prefix there; in the announcement it has the field's label in front:
"Reassign failed: Reason: is required", in German "Neu zuweisen
fehlgeschlagen: Begründung: …".

The prefix follows two rules:

- An error about the edited field itself has no prefix.
- A field is named only if the person has a column for it. An error about a
  field whose column is left out for them, or that is no column of the
  table, has no name.

## In a kit of your own

The default kit shows the texts as the table translated them. A
[kit](kits.md) of your own gets both of these at each part that shows a
table text:

- `texts`: by name, the finished strings in the person's language;
- `messages`: the same names, each the message the text was made of, a map
  `%{key: key, values: values}` of a key of `AshDataTable.Messages` and its
  values (an action's own message is the key `:ash`, with Ash's `message`
  and its `vars`). It is plain data, so a kit hands it to a client as JSON
  unchanged.

A HEEx kit shows `texts`; a kit that translates for itself (a React or Vue
kit) takes `messages` and looks each key up in its own catalogue. Both are in
each part's projection (`AshDataTable.Kit.Projection`), whose documentation
says which names each part gets.

## What a person reads when something is missing

| `gettext_backend` | `translate_error` | The table's texts | Labels | Action messages |
| --- | --- | --- | --- | --- |
| set | set | translated | translated where there is an entry | translated where there is an entry |
| set | not set | translated | translated where there is an entry | as the resource wrote them |
| not set | set | English | as the resource wrote them | translated where there is an entry |
| not set | not set | English | as the resource wrote them | as the resource wrote them |

A locale your backend has no file for behaves as if there were no entries:
English and the resource's own wording.

## Edge cases

- **Only errors of Ash's "invalid" class reach `translate_error`.** A policy
  refusal, a record that is gone and a failure underneath are reported in the
  table's own texts ("You are not allowed to change this.", "You are not
  allowed to do this." and the others), which `gettext_backend` translates.
- **An action's label and a column's label can be one entry.** "Destroy" on
  every table of the demo is the one message "Destroy". A table that wants
  another word says so with `label`, as the task labels do with "Remove".
- **What a record is called is lower case.** The entry is "task", not
  "Task", so a translation can use it inside a sentence.
- **Failed reads are translated like failed saves.** An error the read
  action returned on purpose goes through `translate_error`, with its field's
  label in front when the person has a column for the field.
- **Labels share one domain, without context.** Two columns with the same
  label in different resources get the same translation, and a label that
  reads exactly like one of the table's own messages ("Next", "Yes") shares
  its entry.
- **Dates and numbers are not localized** by the default kit: they are shown
  as the native inputs write them, whatever the locale. A kit of your own is
  given the raw value and the locale, and may format it.
- **Plural forms** follow the locale's `Plural-Forms` rule in your `.po`
  file. One entry serves every place with the same English text: "1
  selected" is the selection line's and a filter's.
- **An error variable that is not text or a number** is written out with
  `inspect/1` before it is handed over.

## Things people trip over

- **A German table with English error messages.** `gettext_backend` is set
  but `translate_error` is not, or the `errors` domain has no entry for that
  message.
- **The entry is there and nothing changes.** The message id must match
  exactly, placeholders included: "length must be greater than or equal to
  %{min}", not the text with the number filled in.
- **Putting column labels into `errors.po`.** Labels belong to the domain
  `ash_data_table`; action messages belong to `errors`.
- **Copying the template as `ash_data_table.pot` into your app.**
  `mix gettext.extract` removes its messages. Copy it as a `.po` file.
- **Switching the language in a running LiveView.** Set the locale in
  `on_mount` and mount again.

## Not in the first version

No locale-aware formatting of numbers, dates and datetimes, and none of the
types `ash_localize` adds: that comes with the "remaining cell types" slice.
See the [specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
