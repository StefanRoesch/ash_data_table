# Files

An action can take a file: an argument of the type `:file`
(`Ash.Type.File`). A table gives such an argument a file input in the action
panel. The person chooses a file, uses the panel's button, and the action is
given the file and reads it. This guide covers where the input appears, how
the file reaches the action, what the upload is limited to, what a person
sees when a file is refused, and what becomes of the file afterwards.

Ash stores no file: `Ash.Type.File` is the type of an argument and never of
an attribute. So a file is never a column and never a cell. What an action
keeps of a file (where it put it, what it is called) is an attribute of
another type, and a column like any other.

Related: [Row actions and create](row-actions-and-create.md) for the action
panel, [Table actions](table-actions.md) for actions that run on the table
as a whole, and
[Selecting rows and bulk actions](selecting-rows-and-bulk-actions.md) for
actions on several rows.

## The smallest example

The demo's labels can be imported from a CSV file
([`demo/lib/demo/tracker/label.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/lib/demo/tracker/label.ex)).
The action is a generic action with one argument:

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
action :import, :integer do
  description "Makes a label of each line of a CSV file."
  transaction? true

  argument :file, :file, allow_nil?: false

  # ...
end
```

The `table` block names the action, as it names any action, and says what
the upload takes:

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
# An argument that takes a file: the panel has a file input for it. The
# upload takes what the block says here, one CSV file of 100 kB at most;
# without an `upload` it would take any file of up to 8 MB.
action :import

upload :file do
  accept ~w(.csv)
  max_file_size 100_000
end
```

The action reads the file through `Ash.Type.File`:

<!-- source: demo/lib/demo/tracker/label.ex -->
```elixir
defp lines(file) do
  with {:ok, device} <- Ash.Type.File.open(file, [:read, :utf8]) do
    # nothing at all is read as the end of the file
    text = with :eof <- IO.read(device, :eof), do: ""
    File.close(device)

    # ...
  else
    {:error, _reason} -> {:error, invalid("could not be read")}
  end
end
```

**Try it:** save two lines as `labels.csv`:

<!-- sketch -->
```text
zebra,#00aa00
yak
```

Open `/labels` in the demo as Ada Admin and use "Import" on the line of the
table's name. The panel has one field, "File". Choose the file and use
"Run": the table says "Import: 2", and the two labels are among its rows.
Then change the second line to `yak,red` and import again: the panel stays
open and says "line 2: colour must match the pattern …" at the field.

## Where the input appears

Wherever the action panel asks for an action's inputs, an argument that
takes a file is a field of it, between the other fields, in the action's
order:

| The action | The panel |
| --- | --- |
| A row action (an update or a destroy action) | Opens from the row's button |
| A generic action in a row (`record_argument`) | Opens from the row's button |
| A table action | Opens from the button on the line of the table's name |
| The create action | "New …" |
| A row action on the selected rows | Opens from the button above the grid |

An action with a file argument always opens its panel, also when the file
can be left out and the action has no other input: a file has no default to
run with.

An argument that takes **several** files (`{:array, :file}`) has no field.
It is left out of the panel when the action runs without it, and an action
that requires one cannot be run from a table. A file is no input of the
[argument line](arguments.md) either: a read action that requires one cannot
be behind a table.

## The field

The field is the browser's own file input, under the argument's label
("File"), marked as required where the argument cannot be empty. It takes
one file. It is an ordinary control of the panel: Tab reaches it, and Enter
or Space on it opens the browser's file dialog. The browser shows the name
of the chosen file in the input.

Nothing is sent when a file is chosen. **The file is sent when the panel's
button is used**, before the action runs, and a bar under the input says how
far it has come while that takes time.

## What the action is given

The table hands the action the file as a `Plug.Upload`, which is what Ash
takes for a file from a web request. In the action the argument is an
`Ash.Type.File`:

| | What it is |
| --- | --- |
| `Ash.Type.File.open/2` | The file, to read |
| `Ash.Type.File.path/1` | Where the uploaded file is, for as long as the action runs |
| `Ash.Type.File.filename/1` | The name the browser gave, without any directory |
| `Ash.Type.File.content_type/1` | The content type the browser gave |

Three things to know:

- **The file is there while the action runs, and gone afterwards.** It is a
  temporary file of LiveView's. An action that wants to keep it copies it,
  or stores its content, before it returns.
- **The name and the content type are the browser's claims.** Check what
  matters in the action.
- **A file is never taken from what the form sends.** A text sent under the
  argument's name is not given to the action.

## What the upload is limited to

`Ash.Type.File` has no constraints, so the resource cannot say how large a
file may be or of which kind. The upload has limits of its own:

| | Without an `upload` | With one |
| --- | --- | --- |
| How many files | One | One |
| Which kinds | Any | What `accept` lists |
| How large | 8 MB at most | `max_file_size`, in bytes |

An `upload` in the `table` block names an argument and sets its limits, for
every action of the table that has a file argument of that name:

- `accept` is a list of file name extensions (`".csv"`) and MIME types
  (`"text/csv"`, `"image/*"`), as `Phoenix.LiveView.allow_upload/3` takes
  them. The browser's file dialog offers these kinds, and a file of another
  kind is refused.
- `max_file_size` is the largest file in bytes.

These are the limits of the upload: a file outside them is refused before
the action runs. What the action makes of a file within them is the
action's to say.

The demo's test support has an upload that takes text files of 1 kB
([`demo/test/support/file_tables.ex`](https://github.com/StefanRoesch/ash_table/blob/main/demo/test/support/file_tables.ex)):

<!-- source: demo/test/support/file_tables.ex -->
```elixir
upload :file do
  accept ~w(.txt text/plain)
  max_file_size 1_000
end
```

## When a file is refused

**By the upload**, as it is chosen: the field says so under the input, the
input is marked (`aria-invalid`), and it is read out. "Run" then runs
nothing until another file is chosen.

| The file | The field says |
| --- | --- |
| Larger than the limit | "The file is too large. The limit is 100 kB." |
| Of a kind `accept` does not list | "This type of file is not accepted." |
| Did not arrive | "The file could not be uploaded." |

These are the table's own texts, and are translated as its other texts are
([Messages and translations](messages-and-translations.md)).

**By the action**, after "Run": the panel stays open, and the action's
message about the argument is shown at the field, as for every input. The
demo's import says which line it refused. An argument that cannot be empty
and was given no file gets the action's own "is required".

**A file is given once.** After "Run" the file input is empty again,
whatever came of the action: LiveView's client empties it once the file is
sent, and the server lets go of the file. A person whose action did not run
chooses the file again. What the action said of the file stays at the field
until they do.

## On the selected rows

A row action with a file argument is offered for the selected rows like any
other, unless it says `bulk? false`. Its panel asks for the file once, and
**every selected record is given the same file**: each run of the action
opens it again and reads it from the start.

The run on the selected rows goes on beside the page, which is longer than
LiveView keeps an uploaded file. So the table copies the file for the run,
and takes the copy away when the run is done, or when the page is closed.

## Mistakes the compiler reports

| Mistake | Where it is reported |
| --- | --- |
| An `upload` names an argument that no action of the table has, or one that takes no file | at the `upload` |
| `accept` lists something that is no extension with a known MIME type and no MIME type | at its `accept` |
| `accept []` | at its `accept` |
| An action requires an argument of several files | at the `action` |

See [Mistakes at compile time](mistakes-at-compile-time.md#uploads).

## Edge cases

- **Cancel and Escape give a chosen file up.** So does a new read of the
  table while the panel is open, which closes the panel.
- **Another file takes the place of the one that was chosen.** The field
  holds one file.
- **The action is not run to check a file as it is chosen.** While a person
  types into other fields, the action is told what they hold, to show its
  errors; it is not given the file then. What it makes of the file is known
  after "Run".
- **Two file arguments in one action** have a field each, and the action is
  given both.
- **A record that is gone when "Run" is used** runs nothing, and the file is
  given up all the same.
- **A file argument that is not public** has no field, as no private
  argument has.

## Things people trip over

- **The file is gone after the action.** `Ash.Type.File.path/1` names a
  temporary file. Copy it, or store its content, inside the action.
- **A larger file than 8 MB is refused though the action would take it.**
  That is LiveView's limit for an upload. Set `max_file_size` in an
  `upload`.
- **An extension is refused when the resource is compiled.** `accept` takes
  extensions the `mime` library knows. Another one is made known with
  `config :mime, :types`, as for every upload in Phoenix.
- **The file has to be chosen again after an error.** A file is given once:
  see [When a file is refused](#when-a-file-is-refused).
- **The column should show the file.** A table has no column for a file.
  Let the action store where it put the file, and show that attribute.

## Not in the first version

- **Several files for one argument.**
- **Dropping a file onto the panel**, and a preview of an image.
- **Uploads that go straight to a storage service** (`:external` in
  LiveView). The file comes to the server, and the action reads it there.
- **A file to download from an action**, and a link to a stored file in a
  cell.
- **Keeping the file when the action fails.**

Showing a stored picture in a cell is a later addition in the
[specification](https://github.com/StefanRoesch/ash_table/issues/21).
