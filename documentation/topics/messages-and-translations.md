# Messages and translations

A table shows three kinds of text, and each has a different owner. After
reading this guide you can translate or reword each kind, you know which
setting covers which, and you can predict what a person reads when one of
them is missing.

## The three kinds of text

| Kind | Examples | Owner | Translated by |
| --- | --- | --- | --- |
| The table's own texts | "No records", "Clear filters", "12 results", the operators of the filters, "You are not allowed to change this.", "Actions", "Run" | The library | `gettext_backend`: the Gettext domain `ash_table` in your backend |
| Your resources' wording, as the table shows it | Column labels, the labels of enum values, the questions of `confirm`, the names of the tables, the labels of row actions and of the fields of the action panel, what one record is called | Your resources | `gettext_backend`: the same domain of the same backend |
| The messages of your actions | "length must be greater than or equal to %{min}", "is required", the `message` of your own validation | Ash and your resources | `translate_error`: your app's error translator |

## The smallest example

Two keys under `config :ash_table`. The installer sets both for a new Phoenix
app. In the demo
([`demo/config/config.exs`](https://github.com/StefanRoesch/ash_table/blob/main/demo/config/config.exs)):

<!-- source: demo/config/config.exs -->
```elixir
config :ash_table,
  layout: {DemoWeb.Layouts, :app},
  gettext_backend: DemoWeb.Gettext,
  translate_error: {DemoWeb.CoreComponents, :translate_error}
```

**Try it:** in the demo, choose "Deutsch" in the "Language" switcher of the
page header and open `/tasks` as Ada Admin. The headings, the filter row, the
pagination and the states of the tasks are German. Set a title to `ab`: the
cell says "muss mindestens 3 Zeichen lang sein".

Both keys are read while the app runs, so changing them needs no
recompilation of the dependency.

## The locale

The table translates in the locale of the process it runs in: whatever your
plug and your `on_mount` hook put there with `Gettext.put_locale/1`. It has
no locale setting of its own. The demo's hook
([`demo/lib/demo_web/locale.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/locale.ex)):

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

(A line `# ...` in an excerpt stands for lines that are left out.) The hook
has to run for the `live_session` the tables are mounted in, as it
does in the demo's router (`on_mount: [DemoWeb.Actor, DemoWeb.Locale]`).

**Changing the locale needs a new mount.** The locale belongs to the
LiveView process and is set when the LiveView mounts. A table that is already
on screen does not change language. The demo's language switcher posts to a
controller and redirects, which loads the page again.

## The table's own texts

Every text that is the table's is a message of the Gettext domain
`ash_table`, written in English. Without `gettext_backend` they are shown in
English. With it they are looked up in your backend.

Copy the template that ships with the package to one file per locale and
fill in each `msgstr` (a sketch of the commands; the demo's file is already
in place):

<!-- sketch -->
```sh
mkdir -p priv/gettext/de/LC_MESSAGES
cp deps/ash_table/priv/gettext/ash_table.pot priv/gettext/de/LC_MESSAGES/ash_table.po
```

Copy it as a `.po` file, not as a template of your own: `mix gettext.extract`
removes from your templates the messages it does not find in your code.

A message without a translation is shown in English. From the demo's German
file
([`demo/priv/gettext/de/LC_MESSAGES/ash_table.po`](https://github.com/StefanRoesch/ash_table/blob/main/demo/priv/gettext/de/LC_MESSAGES/ash_table.po)):

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_table.po -->
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

These are all the messages of the template
([`priv/gettext/ash_table.pot`](https://github.com/StefanRoesch/ash_table/blob/main/priv/gettext/ash_table.pot)):

| Where | Messages |
| --- | --- |
| States | "No records", "The records could not be loaded.", "You are not allowed to see these records." |
| Pagination | "Pagination: %{table}", "Previous", "Next", "Page %{page}", "Go to page %{page}", "%{from}–%{to}", "%{from}–%{to} of %{total}", "1 record" with the plural "%{count} records" |
| Cells | "Yes", "No", "Not available" |
| Filter operators | "contains", "equals", "starts with", "is empty", "greater than", "less than", "at least", "at most", "on", "before", "after", "is" |
| Filter row | "Any", "Filter %{column}", "How to filter %{column}", "Not a valid value", "Clear the %{column} filter", "Clear filters" |
| Announcements | "1 result" with the plural "%{count} results", "Results updated", "%{column} was not saved: %{message}" |
| Saving | "You are not allowed to change this.", "This record is no longer available.", "This could not be saved.", "%{field}: %{message}" |
| The editor of an array | "Add value" (the button that adds one), "%{column} %{position}" (what the control of a value is called: "Tags 2"; a message about one value has it in front, through "%{field}: %{message}"), "Remove %{column} %{position}" (what its button is called) |
| Dialog | "Cancel", "Confirm" |
| Row actions | "Actions" (the heading of their column), "You are not allowed to do this.", "This could not be done.", and what is read out: "%{action}: done", "%{action} failed: %{message}" |
| The action panel | "%{action}: %{record}" (the heading of a row action's panel), "Run", "Create"; "Cancel" is the dialog's |
| Create | "New %{name}" (the create button and the heading of its panel), "%{name} created" (read out; `name` is what one record is called: "Task created") |
| Nested tables | "Related records" (the expanders and the heading of their column), "Loading…", "These records are not available." |
| The full view | "Open in full view", "Open in full view: %{table}" (the link's accessible name), "%{record}: %{relationship}" (the heading over a table limited to the records of one parent), "Show all records" |

**Rewording without translating.** To say "Nothing to show" in place of "No
records" in an English app, give your backend an `ash_table.po` for `en` with
that one entry. This is a sketch; the demo has no such file:

<!-- sketch -->
```po
msgid "No records"
msgstr "Nothing to show"
```

## Your resources' wording

The table shows text that your resources wrote: the label of each column
(declared with `label`, or the field's name in words), the labels of the
values of an enum, the question of a `confirm`, and the name of the table
(the resource's `plural_name`, or its short name, in words), and the label
of each relationship line under an expanded row (declared with `label`, or
the relationship's name in words). Each of them is looked up as a message in
the same `ash_table` domain and shown as it is when the domain has no entry.

Row actions and create add four more of the same kind:

| Wording | The message id |
| --- | --- |
| What a row action's button says | Its `label`, or the action's name in words: "Archive", "Set progress", "Remove". |
| The question of an action's `confirm` | The question as written: "Delete this task? This cannot be undone." |
| What a field of the action panel is called | The label of the column, for an attribute the table has a column for: the entry that translates the heading translates the field. Else the input's name in words: "Reason", "Assignee ID". |
| What one record is called | The resource's short name in words, in lower case: "task", "task label". It fills the table's own message "New %{name}". |

The create button is therefore translated in two places, as the demo does
for German: the table's message says where the name goes, and the name is
your resource's wording.

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_table.po -->
```po
msgid "New %{name}"
msgstr "%{name} anlegen"
```

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_table.po -->
```po
msgid "task"
msgstr "Aufgabe"
```

"New task" is "Aufgabe anlegen". The buttons and the fields of "Reassign"
are entries like a column's label:

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_table.po -->
```po
msgid "Archive"
msgstr "Archivieren"

msgid "Reassign"
msgstr "Neu zuweisen"
```

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_table.po -->
```po
msgid "Reason"
msgstr "Begründung"

msgid "Assignee ID"
msgstr "Zugewiesen an (ID)"
```

**Try it:** `/tasks` in German, as Ada Admin: the column "Aktionen" with
"Archivieren", "Neu zuweisen", "Fortschritt setzen" and "Löschen", and
"Aufgabe anlegen" above the table. "Neu zuweisen" opens a panel with the
fields "Zugewiesen an (ID)" and "Begründung" and the buttons "Abbrechen" and
"Ausführen".

A reference cell shows a value of a related record, its label, which is data
and is not translated. The heading over a table limited to the records of
one parent is the table's message "%{record}: %{relationship}", filled with
that record's label and the translated label of the relationship; a
translation can put the two in another order.

So a column is translated by adding its label to the same file. The demo
translates the wording of `/tasks`:

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_table.po -->
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
`due_on`, "In progress" for the enum value's label. The tables
mounted beside `/tasks` have entries for their row actions, their questions
and what one of their records is called. Their columns have none of their
own, so a heading there is German only where it reads exactly like an entry
that is there, such as "Name".

## The messages of your actions

What an action says when it refuses a value is not the table's text. It is
Ash's ("is required"), or yours. The table hands each such message to the
function named by `translate_error` as `{message, variables}`. That is what
the `translate_error/1` of a Phoenix app's core components takes, so a table
shows an action's message in the same words as your forms do. The demo's is
the one the Phoenix generator wrote
([`demo/lib/demo_web/components/core_components.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo_web/components/core_components.ex)):

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
The translation key is the message as the action wrote it, with its
placeholders. From the demo's
[`errors.po`](https://github.com/StefanRoesch/ash_table/blob/main/demo/priv/gettext/de/LC_MESSAGES/errors.po):

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
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

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

A message is only translated if the `errors` domain has an entry for it.
That holds for your own messages as for Ash's.

### The field prefix

An inline edit sends one field, but the action may complain about another.
The validation above fails when a person sets the state to "Done" on a task
whose progress is 40. The error is about `progress`; the cell that was
edited is the state. The table shows the error on the edited cell and puts
the other field's column label in front:

| Language | The state cell says |
| --- | --- |
| English | "Progress: must be 100 when the task is done" |
| German | "Fortschritt: muss 100 sein, wenn die Aufgabe erledigt ist" |

The sentence is put together from three parts with three owners: the label
("Progress", your resource's wording), the message (your action's, through
`translate_error`), and the frame "%{field}: %{message}" (the table's own).
The announcement to screen readers is framed the same way: "%{column} was
not saved: %{message}".

A row action uses the same frame. An error about a field that is shown on
the row's actions cell, or above the fields of the action panel, has the
field's column label in front, by the two rules below. An error at a field
of the panel has no prefix there; in the announcement it has the field's
label in front: "Reassign failed: Reason: is required", in German "Neu
zuweisen fehlgeschlagen: Begründung: …".

The prefix follows two rules:

- An error about the edited field itself has no prefix.
- A field is named only if the person has a column for it. An error about a
  field whose column is left out for them, or which is no column of the
  table, is shown without a name.

## What a person reads when something is missing

| `gettext_backend` | `translate_error` | The table's texts | Labels | Action messages |
| --- | --- | --- | --- | --- |
| set | set | translated | translated where there is an entry | translated where there is an entry |
| set | not set | translated | translated where there is an entry | as the resource wrote them |
| not set | set | English | as the resource wrote them | translated where there is an entry |
| not set | not set | English | as the resource wrote them | as the resource wrote them |

A locale your backend has no file for behaves as if there were no entries:
English, and the resource's own wording.

## Edge cases

- **Only errors of Ash's "invalid" class reach `translate_error`.** A refusal
  by a policy, a record that is gone and a failure underneath are reported
  in the table's own texts ("You are not allowed to change this.", "You are
  not allowed to do this." and the others), which `gettext_backend`
  translates.
- **An action's label and a column's label can be one entry.** "Destroy" on
  every table of the demo is the one message "Destroy". A table that wants
  another word says so with `label`, as the task labels do with "Remove".
- **What a record is called is in lower case.** The entry is "task", not
  "Task", so that a translation can use it inside a sentence.
- **Failed reads are translated like failed saves.** An error the read
  action returned on purpose goes through `translate_error`, with its field's
  label in front when the person has a column for the field.
- **Labels share one domain, without context.** Two columns with the same
  label in different resources get the same translation, and a label that
  reads exactly like one of the table's own messages ("Next", "Yes") shares
  its entry.
- **Dates and numbers are not localized.** They are shown as the native
  inputs write them, whatever the locale.
- **Plural forms** follow the locale's rule in your `.po` file. Only the
  result count has one.
- **A variable of an error that is not text or a number** is written out
  with `inspect/1` before it is handed over.

## Things people trip over

- **A German table with English error messages.** `gettext_backend` is set
  and `translate_error` is not, or the `errors` domain has no entry for that
  message.
- **The entry is there and nothing changes.** The message id has to match
  exactly, placeholders included: "length must be greater than or equal to
  %{min}", not the text with the number filled in.
- **Putting column labels into `errors.po`.** Labels belong to the domain
  `ash_table`; action messages belong to `errors`.
- **Copying the template as `ash_table.pot` into your app.**
  `mix gettext.extract` removes its messages. Copy it as a `.po` file.
- **Switching the language in a running LiveView.** Set the locale in
  `on_mount` and mount again.

## Not in the first version

No locale-aware formatting of numbers, dates and datetimes, and none of the
types `ash_localize` adds: that comes with the "remaining cell types" slice.
See the [specification](https://github.com/StefanRoesch/ash_table/issues/21).
