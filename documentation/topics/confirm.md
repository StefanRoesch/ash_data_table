# Confirm

After reading this guide you can make a column ask a question before a cell
is saved, and a row action before it runs, and you know exactly when the
question appears and what each answer does.

`confirm` is an option of an editable column and of a row action, so read
[Inline editing](inline-editing.md) first, and
[Row actions and create](row-actions-and-create.md) for the second half.

## The smallest example

`confirm` takes the question as a string. On the demo's tasks a change of
state asks first
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

(`component` is how the cells of the column look, here as badges: see
[Custom components](custom-components.md). It has nothing to do with the
question.)

**Try it:** `/tasks` in the demo, as Ada Admin. Move to a cell of the
"State" column, press Enter and choose another state. A dialog asks "Change
the state of this task?" with the buttons Cancel and Confirm.

## A question is no safety check

A question guards a person against a slip of their own: a click on the
wrong row, a value chosen by mistake. It does not guard your data against
the person. The server does not enforce it, not even in
[controlled mode](controlled-mode.md): an event sent to the LiveView by
other means than the table's page (a forged one) runs what the question is
about without the question.

What must not happen belongs on the resource, as a policy or a validation
of the action. A page that wants to refuse something itself has the
`before_action` veto (see [Events and commands](events-and-commands.md)).
Both run for every event, asked or not.

## When the dialog appears

The dialog opens at the moment the edit would be saved, before the action
runs and before anything is sent to the server:

| The person | Dialog? |
| --- | --- |
| Presses Enter in the editor, with a changed value | Yes |
| Leaves the cell (a click elsewhere, Tab), with a changed value | Yes |
| Chooses a value from a menu | Yes |
| Toggles a boolean | Yes |
| Lets go of a slider, or changes any other editor of a component that saves on change | Yes |
| Chooses another related record in the picker of a reference cell | Yes, on top of the picker. Cancel returns to the picker, with the row still selected. |
| Uses Save in the side panel of an array, map or union cell, with a changed value | Yes, on top of the panel. Cancel returns to the panel, with everything as it was typed. |
| Presses Escape in the editor | No: the edit is given up |
| Saves the value the cell already had | No: nothing would be saved |

The question is asked once per save, for that cell. There is no confirm for
a whole table and none that depends on the value or on the record.

## Confirm, Cancel and Escape

| Answer | Effect |
| --- | --- |
| Confirm | The value is saved, as it would have been without the question. Focus returns to the cell, or stays where the person had moved it by leaving the cell. |
| Cancel | Nothing is saved. The person is back in the editor, still in edit mode, with what they typed or chose. From there, Escape gives the edit up and Enter asks again. |
| Escape, in the dialog | The same as Cancel. |

For a boolean cell, which has no edit mode, Cancel leaves the value as it
was and puts focus on the cell.

The editor of a column's [component](custom-components.md) that saves when
its value changes, such as a slider, stays open after a save. So Confirm
leaves the person in it, with the value saved, and Cancel leaves them in it
with the value they chose and nothing saved.

## Where the question opens

The question opens over the page or in it, as the table's
presentation says (see [Kits](kits.md) and
[Layout and embedding](layout-and-embedding.md)):

- **Over the page** (`:modal`, the default kit's): the rest of the page
  cannot be reached while it is open, and focus stays inside it. When it is
  answered, focus goes back where it was.
- **In the page** (`:inline`, `presentation: [confirm: :inline]`): a region
  in the page. Focus moves into it, Escape inside it is Cancel, Tab leaves
  it, and nothing else is out of reach. When it is answered, focus goes back
  to where it was before. Asked from a panel or a picker that is open over
  the page, it is shown inside that panel or picker, where it can be
  answered.

Either way focus starts on Cancel, the safe answer, and the question is
named by its text.

**One question at a time per table.** A question asked while another is
open takes its place: the first is given up, as if Cancel had been used,
and what it was about does not run.

In controlled mode with `:confirm` the table does not ask: it hands the
question to your page, which asks it as it likes and answers with a
command. See [Controlled mode](controlled-mode.md).

## `confirm` on a row action

A row action takes the same option. The demo's tasks ask before a task is
deleted:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# A destroy action asks first, or says that it does not (`confirm false`).
action :destroy do
  confirm "Delete this task? This cannot be undone."
end
```

**Try it:** `/tasks` as Ada Admin. Use "Destroy" at the end of a row: the
same dialog asks "Delete this task? This cannot be undone." In the default
kit its Confirm button is in the error colour.

| The action | The question is asked | Cancel, or Escape |
| --- | --- | --- |
| Runs straight away | When its button is used, before anything is sent to the server. | Nothing runs. Focus is back on the button. |
| Opens the action panel | When "Run" is used in the panel, in the same dialog on top of the panel. | Nothing runs. The person is back in the panel, with everything as they typed it. |

Confirm runs the action as it would have run without the question.

A [table action](table-actions.md) takes the option too, and asks in the
same dialog: when its button on the line of the table's name is used, or,
for one with a panel, when "Run" is used. The server decides what such a
button does, so it is the server that has the dialog opened; Cancel and
Escape put focus back on the button.

Three things differ from a column's `confirm`:

- **The Confirm button of a destroy action is marked as one that deletes**,
  so the answer that deletes looks like one: in the default kit, in the
  error colour. For an update action, and for a cell, it is in the primary
  colour.
- **A destroy action without `confirm` is warned about** when the resource
  is compiled: one click on its button would delete the record. See
  [Mistakes at compile time](mistakes-at-compile-time.md#a-destroy-action-without-confirm).
- **`confirm false`** says that an action runs without a question on
  purpose, which silences that warning. The demo's task labels do so
  ([`demo/lib/demo/tracker/task_label.ex`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/lib/demo/tracker/task_label.ex)):

<!-- source: demo/lib/demo/tracker/task_label.ex -->
```elixir
# Taking a label off a task deletes nothing but the link: it runs at one
# click, and `confirm false` says that this is meant. Without it the
# compiler warns about a destroy action that asks nothing.
action :destroy do
  label "Remove"
  confirm false
end
```

A column takes a question only; `confirm false` is for actions.

**On the selected rows** an action always asks, whatever it says about
`confirm`: one click must not change a page of records. The question says
how many records it is about. An action with a `confirm` asks its own
question and the number follows it ("Delete this task? This cannot be
undone. 3 records are selected."); any other is asked for by its name
("Run “Archive” on 3 records?"). The question confirms exactly the
selection it names: if the selection changes while it is open, it is given
up, and if it changed before the answer reached the server, nothing runs
and the table says so. See
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#the-question).

The demo has no action with both a question and a panel. Every question
there belongs to a destroy action without inputs.

## Translating the question

The question is the resource's wording, so the table looks it up as a
message in the host's Gettext backend and shows it as written when there is
no translation. This holds for a column's question and for an action's. The
demo translates them into German
([`demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po)):

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "Change the state of this task?"
msgstr "Den Status dieser Aufgabe ändern?"
```

"Cancel" and "Confirm" are the table's own texts and are translated in the
same file. See [Messages and translations](messages-and-translations.md).

## Edge cases

- **The question is asked in the browser.** The server is not involved until
  the person has confirmed; it then receives an ordinary save, or the
  ordinary event of a row action. See
  [A question is no safety check](#a-question-is-no-safety-check).
- **A reference cell asks the server first.** Whether a choice in the
  picker changes the row is for the server to say: it reads the chosen
  record, and answers with the question when the choice would change the
  row. Nothing is saved before Confirm. On `/tasks`, "Project" asks "Move
  this task to another project?". See
  [Choosing a related record](choosing-a-related-record.md#what-a-choice-saves).
- **A save that fails after Confirm** looks like any failed save: the cell
  is marked and keeps what was chosen. Saving it again asks again.
- **A column the person cannot edit asks nothing.** If the person can never
  run the column's action, the column is read-only for them and its question
  is not in their page.
- **An action the person cannot run asks nothing either.** It has no button
  for them.
- **A table without any `confirm`**, on a column or on an action, has no
  question to ask, unless it offers an action for the selected rows: that
  one always asks.
- **An action that fails after Confirm** looks like any failed action: its
  message is on the row's actions cell, or in the panel. Using the button
  again asks again.
- **Leaving the cell and cancelling** pulls focus back into the editor. This
  is the one case in which the table moves focus against the person's last
  gesture, because their edit is still open.

## Things people trip over

- **`confirm` on a column that can never be edited** has no effect, and the
  compiler reports it: a column without an update action, one switched off
  with `update_action false`, one the table's action does not accept, one
  whose type has no editor or whose attribute is not writable. See
  [Mistakes at compile time](mistakes-at-compile-time.md).
- **Expecting a question when nothing changed.** An unchanged value is not
  saved, so it is not asked about.
- **Writing the question as a statement.** The buttons say Cancel and
  Confirm, so the text should be a question that "Confirm" answers.
- **Using `confirm` as protection.** It is not a check: see
  [A question is no safety check](#a-question-is-no-safety-check).

## Not in the first version

No question of your own wording for an action on several rows (the number
is added to the action's `confirm`), no question that depends on the value
or on the record, no confirm for a whole table, and no type-to-confirm, where a person has to type a word
before a delete. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
