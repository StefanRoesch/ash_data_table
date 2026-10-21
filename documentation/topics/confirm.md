# Confirm

`confirm` makes an editable column ask a question before a cell is saved,
and a row action before it runs. This guide says when the question appears
and what each answer does. Read [Inline editing](inline-editing.md) first,
and [Row actions and create](row-actions-and-create.md) for actions.

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

(`component` only sets how the cells look: see
[Custom components](custom-components.md).)

**Try it:** `/tasks` in the demo, as Ada Admin. Press Enter on a "State"
cell and choose another state. A dialog asks "Change the state of this
task?" with Cancel and Confirm.

## A question is no safety check

A question guards a person against their own slip (a wrong row, a wrong
value). It does not guard your data against the person. The server does not
enforce it, not even in [controlled mode](controlled-mode.md): a forged
event sent to the LiveView runs without the question.

Put what must not happen on the resource, as a policy or a validation of the
action. A page that wants to refuse something itself has the
`before_action` veto (see [Events and commands](events-and-commands.md)).
Both run for every event, asked or not.

## When the dialog appears

The dialog opens when the edit would be saved, before the action runs and
before anything is sent to the server:

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
| Confirm | The value is saved as it would have been without the question. Focus returns to the cell, or stays where the person moved it by leaving the cell. |
| Cancel | Nothing is saved. The person is back in the editor, in edit mode, with what they typed or chose. Escape then gives the edit up; Enter asks again. |
| Escape, in the dialog | Same as Cancel. |

- **Boolean cell** (no edit mode): Cancel leaves the value as it was and
  puts focus on the cell.
- **[Component](custom-components.md) editor that saves on change**, such as
  a slider: it stays open after a save. Confirm leaves the person in it with
  the value saved; Cancel leaves them in it with the chosen value unsaved.

## Where the question opens

Over the page or in it, as the table's presentation says (see
[Kits](kits.md) and [Layout and embedding](layout-and-embedding.md)):

- **Over the page** (`:modal`, the default kit's): the rest of the page is
  out of reach and focus stays inside. When answered, focus goes back where
  it was.
- **In the page** (`:inline`, `presentation: [confirm: :inline]`): a region
  in the page. Focus moves into it, Escape is Cancel, Tab leaves it, nothing
  else is out of reach. When answered, focus goes back where it was. Asked
  from a panel or picker open over the page, it is shown inside that panel
  or picker.

Either way focus starts on Cancel, the safe answer, and the dialog is named
by its text.

**One question at a time per table.** A new question replaces an open one:
the first is given up as if cancelled, and what it was about does not run.

In controlled mode with `:confirm` the table does not ask: it hands the
question to your page, which asks it and answers with a command. See
[Controlled mode](controlled-mode.md).

## `confirm` on a row action

A row action takes the same option. The demo's tasks ask before a delete:

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# A destroy action asks first, or says that it does not (`confirm false`).
action :destroy do
  confirm "Delete this task? This cannot be undone."
end
```

**Try it:** `/tasks` as Ada Admin. Use "Destroy" at the end of a row: the
dialog asks "Delete this task? This cannot be undone." In the default kit
its Confirm button is in the error colour.

| The action | The question is asked | Cancel, or Escape |
| --- | --- | --- |
| Runs straight away | When its button is used, before anything is sent to the server. | Nothing runs. Focus is back on the button. |
| Opens the action panel | When "Run" is used, in the dialog on top of the panel. | Nothing runs. The person is back in the panel, with everything as typed. |

Confirm runs the action as it would have run without the question.

A [table action](table-actions.md) takes the option too and asks in the same
dialog: when its button on the line of the table's name is used, or, with a
panel, when "Run" is used. The server decides what that button does, so the
server has the dialog opened. Cancel and Escape put focus back on the button.

Differences from a column's `confirm`:

- **A destroy action's Confirm button is marked as deleting**: in the
  default kit, error colour. For an update action and for a cell, primary
  colour.
- **A destroy action without `confirm` is warned about** at compile time:
  one click would delete the record. See
  [Mistakes at compile time](mistakes-at-compile-time.md#a-destroy-action-without-confirm).
- **`confirm false`** says an action runs without a question on purpose and
  silences that warning. The demo's task labels use it
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

A column takes only a question; `confirm false` is for actions.

**On the selected rows** an action always asks, whatever its `confirm`: one
click must not change a page of records. The question names the number of
records. An action with a `confirm` asks its own question followed by the
number ("Delete this task? This cannot be undone. 3 records are
selected."); any other is asked by name ("Run “Archive” on 3 records?").
The question confirms exactly the selection it names: if the selection
changes while it is open, it is given up; if it changed before the answer
reached the server, nothing runs and the table says so. See
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md#the-question).

The demo has no action with both a question and a panel; every question
there belongs to a destroy action without inputs.

## Translating the question

The table looks the question up as a message in the host's Gettext backend,
for columns and actions alike, and shows it as written when there is no
translation. The demo translates into German
([`demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po)):

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po -->
```po
msgid "Change the state of this task?"
msgstr "Den Status dieser Aufgabe ändern?"
```

"Cancel" and "Confirm" are the table's own texts, translated in the same
file. See [Messages and translations](messages-and-translations.md).

## Edge cases

- **A cell's question is asked in the browser.** The server is involved only
  after Confirm; it then receives an ordinary save, or the ordinary event of
  a row action. See
  [A question is no safety check](#a-question-is-no-safety-check).
- **A reference cell asks the server first.** The server reads the chosen
  record and answers with the question when the choice would change the
  row. Nothing is saved before Confirm. On `/tasks`, "Project" asks "Move
  this task to another project?". See
  [Choosing a related record](choosing-a-related-record.md#what-a-choice-saves).
- **A save that fails after Confirm** looks like any failed save: the cell
  is marked and keeps what was chosen. Saving again asks again.
- **An action that fails after Confirm** looks like any failed action: its
  message is on the row's actions cell, or in the panel. Using the button
  again asks again.
- **No question for what the person cannot do.** A column whose action the
  person can never run is read-only for them, and its question is not in
  their page. An action they cannot run has no button.
- **A table without any `confirm`** asks nothing, except for an action on
  the selected rows, which always asks.
- **Leaving the cell and cancelling** pulls focus back into the editor: the
  one case where the table moves focus against the person's last gesture,
  because their edit is still open.

## Things people trip over

- **`confirm` on a column that can never be edited** has no effect, and the
  compiler reports it: no update action, `update_action false`, an attribute
  the table's action does not accept, a type without an editor, or an
  attribute that is not writable. See
  [Mistakes at compile time](mistakes-at-compile-time.md).
- **Expecting a question when nothing changed.** An unchanged value is not
  saved, so not asked about.
- **Writing the question as a statement.** The buttons say Cancel and
  Confirm, so write a question that "Confirm" answers.
- **Using `confirm` as protection.** See
  [A question is no safety check](#a-question-is-no-safety-check).

## Not in the first version

No own wording for an action on several rows (the number is added to the
action's `confirm`), no question that depends on the value or the record, no
confirm for a whole table, and no type-to-confirm (typing a word before a
delete). See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
