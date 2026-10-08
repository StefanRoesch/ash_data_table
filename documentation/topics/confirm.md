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
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# enums, each shown as a badge. A change of state asks first.
column :status do
  label "State"
  confirm "Change the state of this task?"
  component AshTable.Components.Badge
end
```

(`component` is how the cells of the column look, here as badges: see
[Custom components](custom-components.md). It has nothing to do with the
question.)

**Try it:** `/tasks` in the demo, as Ada Admin. Move to a cell of the
"State" column, press Enter and choose another state. A dialog asks "Change
the state of this task?" with the buttons Cancel and Confirm.

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

The dialog is a native `<dialog>` opened with `showModal()`: the rest of the
page cannot be reached while it is open, and the browser keeps focus inside
it.
Focus starts on Cancel, the safe answer. The dialog is labelled by the
question.

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
same dialog asks "Delete this task? This cannot be undone." Its Confirm
button is in the error colour.

| The action | The question is asked | Cancel, or Escape |
| --- | --- | --- |
| Runs straight away | When its button is used, before anything is sent to the server. | Nothing runs. Focus is back on the button. |
| Opens the action panel | When "Run" is used in the panel, in the same dialog on top of the panel. | Nothing runs. The person is back in the panel, with everything as they typed it. |

Confirm runs the action as it would have run without the question.

Three things differ from a column's `confirm`:

- **The Confirm button of a destroy action is in the error colour**, so the
  answer that deletes looks like one. For an update action, and for a cell,
  it is in the primary colour.
- **A destroy action without `confirm` is warned about** when the resource
  is compiled: one click on its button would delete the record. See
  [Mistakes at compile time](mistakes-at-compile-time.md#a-destroy-action-without-confirm).
- **`confirm false`** says that an action runs without a question on
  purpose, which silences that warning. The demo's task labels do so
  ([`demo/lib/demo/tracker/task_label.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task_label.ex)):

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

The demo has no action with both a question and a panel. Every question
there belongs to a destroy action without inputs.

## Translating the question

The question is the resource's wording, so the table looks it up as a
message in the host's Gettext backend and shows it as written when there is
no translation. This holds for a column's question and for an action's. The
demo translates them into German
([`demo/priv/gettext/de/LC_MESSAGES/ash_table.po`](https://github.com/StefanRoesch/ash_table/blob/main/demo/priv/gettext/de/LC_MESSAGES/ash_table.po)):

<!-- source: demo/priv/gettext/de/LC_MESSAGES/ash_table.po -->
```po
msgid "Change the state of this task?"
msgstr "Den Status dieser Aufgabe ändern?"
```

"Cancel" and "Confirm" are the table's own texts and are translated in the
same file. See [Messages and translations](messages-and-translations.md).

## Edge cases

- **The question is asked in the browser.** The server is not involved until
  the person has confirmed; it then receives an ordinary save, or the
  ordinary event of a row action. An event sent to the LiveView by other
  means is not asked anything. `confirm` guards against slips, not against
  misuse. What must not happen belongs in the action, as a policy or a
  validation.
- **A save that fails after Confirm** looks like any failed save: the cell
  is marked and keeps what was chosen. Saving it again asks again.
- **A column the person cannot edit asks nothing.** If the person can never
  run the column's action, the column is read-only for them and its question
  is not in their page.
- **An action the person cannot run asks nothing either.** It has no button
  for them.
- **A table without any `confirm`**, on a column or on an action, has no
  dialog in its markup.
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
- **Using `confirm` as protection.** It is not a check.

## Not in the first version

No question that depends on the value or on the record, no confirm for a
whole table, and no type-to-confirm, where a person has to type a word
before a delete. See the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
