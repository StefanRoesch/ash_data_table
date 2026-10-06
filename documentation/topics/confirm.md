# Confirm

After reading this guide you can make a column ask a question before a cell
is saved, and you know exactly when the question appears and what each answer
does.

`confirm` is an option of an editable column, so read
[Inline editing](inline-editing.md) first.

## The smallest example

`confirm` takes the question as a string. On the demo's tasks a change of
state asks first
([`demo/lib/demo/tracker/task.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/task.ex)):

<!-- source: demo/lib/demo/tracker/task.ex -->
```elixir
# enums. A change of state asks first.
column :status do
  label "State"
  confirm "Change the state of this task?"
end
```

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
| Presses Escape in the editor | No: the edit is given up |
| Saves the value the cell already had | No: nothing would be saved |

The question is asked once per save, for that cell. There is no confirm for
a whole table and none that depends on the value.

## Confirm, Cancel and Escape

| Answer | Effect |
| --- | --- |
| Confirm | The value is saved, as it would have been without the question. Focus returns to the cell, or stays where the person had moved it by leaving the cell. |
| Cancel | Nothing is saved. The person is back in the editor, still in edit mode, with what they typed or chose. From there, Escape gives the edit up and Enter asks again. |
| Escape, in the dialog | The same as Cancel. |

For a boolean cell, which has no edit mode, Cancel leaves the value as it
was and puts focus on the cell.

The dialog is a native `<dialog>` opened with `showModal()`: the rest of the
page cannot be reached while it is open, and the browser keeps focus inside
it.
Focus starts on Cancel, the safe answer. The dialog is labelled by the
question.

## Translating the question

The question is the resource's wording, so the table looks it up as a
message in the host's Gettext backend and shows it as written when there is
no translation. The demo translates it into German
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
  the person has confirmed; it then receives an ordinary save. A `save` event
  sent to the LiveView by other means is not asked anything. `confirm`
  guards against slips, not against misuse. What must not happen belongs in
  the action, as a policy or a validation.
- **A save that fails after Confirm** looks like any failed save: the cell
  is marked and keeps what was chosen. Saving it again asks again.
- **A column the person cannot edit asks nothing.** If the person can never
  run the column's action, the column is read-only for them and its question
  is not in their page.
- **A table without any `confirm`** has no dialog in its markup.
- **Leaving the cell and cancelling** pulls focus back into the editor. This
  is the one case in which the table moves focus against the person's last
  gesture, because their edit is still open.

## Things people trip over

- **`confirm` on a column that can never be edited** has no effect, and the
  compiler reports it: a column without an update action, one switched off
  with `update_action false`, one the table's action does not accept. See
  [Mistakes at compile time](mistakes-at-compile-time.md).
- **Expecting a question when nothing changed.** An unchanged value is not
  saved, so it is not asked about.
- **Writing the question as a statement.** The buttons say Cancel and
  Confirm, so the text should be a question that "Confirm" answers.
- **Using `confirm` as protection.** It is not a check.

## Not in the first version

`confirm` exists on columns only. Row actions with `confirm`, and the warning
for a destroy action without one, come with the row actions slice. The
dialog used here is the one the action panel will use later. See the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
