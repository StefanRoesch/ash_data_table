# Stage 3: design note (3a, 3b, 3c)

Status: **for the owner to decide.** Nothing of it is built. Code references are of `d8e8c6e` (the end of stage 2). Names follow [target.md](target.md); words follow `CONTEXT.md`. The decisions are in section 7.

## 1. What stage 3 changes, and what it does not

Stages 0–2 moved code. Stage 3 changes how the code works inside, in three steps. 3a puts everything a part draws into data (`Present`) and parses every browser event in one place (`Intent`). 3b sends every write through one pipeline (`Operation`) and makes the data layer (2a) return message terms instead of words. 3c moves the component's logic into `Live.Core.*`, puts the table id into every event name, and makes the dependency test fail on a broken rule.

What stays the same: no new ability for a person or a developer. Every event, payload, reply and `push_event` means what it means today. Every text a person reads stays word for word, in English and in German. The markup snapshots stay byte for byte identical in 3a and 3b. In 3c the event names in the markup change (`phx-click="sort"` becomes `phx-click="ash_data_table:tasks:sort"`); with decision D7 the snapshot test strips that prefix, as it already strips hook names, and the snapshots stay identical apart from it. The veto, page values, events to the host and selection on the server stay in stage 6; stage 3 only leaves the place for them.

## 2. 3a: `Present` and `Intent`

### 2.1 What `Present` gives

`AshDataTable.Present` (2a, `@moduledoc false`, Q14) turns what the core holds into what a part draws. It holds the record; a part never does again. It gives values, not texts (RQ6): a part formats a value with `Format` and translates a message with the translation step. Four kinds of data, each a small struct:

**A row.** One stream item. The core builds it where it builds `item/8` today (`show/3`, `put_row/3`, `add_row/2`; `table_component.ex:1640`, `:1836`, `:4172`).

```elixir
%Present.Row{
  key: "3f2a9c",                    # the key in the DOM id; a claim when it comes back
  dom_id: "tasks-row-3f2a9c",
  rowindex: 4, names: nil, open?: false, current?: false,
  action_failure: nil,              # a message once a row action failed
  cells: %{
    title:    %Present.Cell{value: "Write the note", state: :value, editable?: true, failure: nil},
    due_on:   %Present.Cell{value: ~D[2026-10-20], state: :value, editable?: true, failure: nil},
    assignee: %Present.Cell{value: "Ada", state: :value, editable?: true, failure: nil},
    # sensitive, holds a value: neither the value nor its mask struct
    salary:   %Present.Cell{value: nil, state: :masked, editable?: true, failure: nil},
    # a field policy hides it on this row
    rating:   %Present.Cell{value: nil, state: :forbidden, editable?: false, failure: nil}
  }
}
```

- `state` is `:value`, `:empty` (nil or not loaded), `:masked` or `:forbidden`. A part draws from `state` and `value` only.
- `value` is what `Model.Column.value/2` gives today, after `Sensitive.scrub/2`: a reference cell's label value, a map cell's embedded value (scrubbed inside, as `scrub/1` already does), an `Ash.Union`. Never a record of the table's resource.
- `editable?` is today's `editable?/3` (`parts/grid.ex:539-550`): it needs the record (the foreign key of a reference cell, `Embedding.hidden?/1` of a map cell). That is why it moves into `Present`.
- `failure` of a cell whose save failed: `%{typed: "abc", message: msg, places: [1]}`. For a sensitive cell `typed` is always `""`, as `saved/5` does today (`table_component.ex:2908`).

**A field of the action panel.** `Present.panel/2` gives the panel's title, kind, question and button, and one field per input:

```elixir
%Present.Field{
  name: :password, path: ["password"], form_name: "form[password]",
  input: %Model.Input{…},        # the declaration of the field: type, editor, limits
  value: "",                     # sensitive: "" or what was typed in this panel, never the record's
  errors: [],                    # shown errors only (today's field_errors/3), as messages
  places: [], chosen: nil, clear: :offered   # nil | :offered | :asked
}
```

`panel_value/3` (`parts/panel.ex:121-155`) moves into `Present` as it is. `Parts.Panel` stops calling `to_form/1` on the `AshPhoenix.Form` (`parts/panel.ex:33`); it gets `form_name` and the field map. The form stays in the entry (target §1.4). The form's own hidden inputs are written by the part already (`parts/panel.ex:280, 430, 726, 850, 911`), so the markup can stay identical; the snapshots 06a, 07a, 07b, 07c check it.

**The picker.** `Present.picker/1` gives the title, `several?`, `none?`, the question, the error and the current key. The rows of the table inside it are `Present.Row`s of that table, with `current?`. The records a panel field holds (`chosen`) come as `%{key => %{label: value, row: …}}`: the label value, which the part formats.

**Failed edits** are inside the row (`failure`, `action_failure`), as above.

### 2.2 Where the rules fold in

- `Sensitive.scrub/2` runs first in `Present.row/…`. The scrubs the core does today stay as a second guard (`put_failed`, `table_component.ex:1893`): the entry keeps a scrubbed record for "discard".
- After `Present`, a part needs no `Resource.Exposing`, `Resource.Embedding` or `Sensitive` any more: `state` and `editable?` say it. That removes three of the four "part 3 → part 1" findings of the dependency test (`parts/grid.ex:548, 572`, `parts/panel.ex:136, 230`).
- New root tests for `Present` (new tests are allowed): every function, given the records of the sensitive test resources, returns no sensitive value anywhere in its output. This is a safety check, so it gets a mutation check (build rules: "what is sent to the browser"): drop the scrub, and the test must fail.

### 2.3 What changes for the parts and the tests

- `Parts.Grid` reads `row.cells[column.name]` in `cell_attributes/5` and `cell_content/4` (`parts/grid.ex:400-441`, `480-502`). The text of a cell is still made there from the value (`Format.format/3`, `Format.input/3`), so the markup is the same.
- `Parts.Panel` and `Parts.Picker` draw from `Present`'s structs.
- When `Present` runs: rows when they go into the stream (they are not kept); the panel and the picker in `render/1`, as attributes (`panel={Present.panel(@table.entry.panel, …)}`). LiveView compares them field by field as today. Check: the bytes per action of `demo/perf/baseline.mjs` do not grow.
- Snapshots: byte for byte identical. Demo tests: unchanged (they read markup). Root tests: unchanged (no test calls a part).
- The note in `test/architecture_test.exs` "`Parts.Panel` draws from the `AshPhoenix.Form` … (until stage 3a)" goes.

### 2.4 `Intent`

`AshDataTable.Intent.parse(event, params) :: {:ok, t} | :malformed` (2a, `@moduledoc false`). One tagged tuple per event of the "Events" list (`docs/agents/architecture.md`). It checks the shape only: text where text is expected, a list of texts where a list is. Names stay text; nothing is looked up, nothing becomes an atom. The checks against the model and the page (is the column editable, is the row on the page) stay where they are, and move into `Operation` in 3b.

| Events | Intent |
| --- | --- |
| `sort`, `clear_filter` | `{:sort, column}`, `{:clear_filter, column}` |
| `filter`, `arguments` | `{:filter, form}`, `{:arguments, form}` (the form's map, `%{}` when missing, as today) |
| `clear_filters`, `create`, `bulk_seen`, `panel_cancel`, `picker_cancel`, `read_again` | the atom of the event |
| `page`, `page_size` | `{:page, to}`, `{:page_size, size}` |
| `argument_add`, `argument_remove` | `{:argument_add, argument}`, `{:argument_remove, argument, at}` (`at` an integer ≥ 0) |
| `expand`, `dismiss`, `left` | `{:expand, row}`, `{:dismiss, row}`, `{:left, row}` |
| `toggle` | `{:toggle, row, relationship}` |
| `save` | `{:save, row, column, typed}` (`typed`: text or list of texts) |
| `clear`, `reveal`, `edit`, `pick`, `discard` | `{:clear, row, column}` and so on |
| `act` | `{:act, row, action}` |
| `table_act`, `table_run` | `{:table_act, action}`, `{:table_run, action}` |
| `bulk`, `bulk_run` | `{:bulk, action, selection}`, `{:bulk_run, action, selection}`; `selection` is `:all` or `{:rows, [key]}`, each key a claim |
| `panel_validate`, `panel_submit` | `{:panel_validate, typed}`, `{:panel_submit, typed}` |
| `panel_add`, `panel_remove` | `{:panel_add, path}`, `{:panel_remove, path}` |
| `panel_unpick`, `panel_clear`, `pick_input` | `{:panel_unpick, input, key}`, `{:panel_clear, input}`, `{:pick_input, input}` |
| `picked` | `{:picked, %{row: key \| nil, rows: [key] \| nil, confirmed?: boolean, arguments: map}}` |

`:malformed` gets the answer today's catch-all clause gives for that event (`%{ok: false}`, `%{open: false}`, `%{}` or no reply; `table_component.ex:2054-2832`). That table of answers lives in the live layer, not in `Intent`. The rule for identical behaviour: `Intent` refuses no payload that today's clauses accept. In 3a the `handle_event/3` clauses call `Intent.parse/2` first and keep their bodies.

## 3. 3b: `Operation` and message terms

### 3.1 The input value (settles F9)

```elixir
%Operation.Input{
  intent: Intent.t(),            # what was asked; names still text
  model: Model.t(),              # the person's model
  state: State.t(),              # the page's state: the re-read runs the page's read
  parent: nil | %{key: map, authorize?: boolean, arguments: map},
  opts: keyword,                 # Caller.reader_opts/1 plus `origin`, as today (F7)
  rows: %{key => %{pk: map, rowindex: pos_integer}},  # the entry's rows index
  panel: nil | %{form: AshPhoenix.Form.t(), inputs: list, given: map, cleared: [atom]},
  with_files: (fun -> term),     # default: fn run -> run.(%{}) end
  veto: (-> :cont | {:halt, msg}),            # stage 6; default fn -> :cont end
  page_values: (-> %{context: map, private_arguments: map, page_arguments: map})  # stage 6; default empty maps
}
```

What changes against F9's sketch:

- `key_known?: fun` becomes `rows`, the index the entry already holds: a value, not a function, and testable without a socket. A bulk selection is not looked up in it: it outlives its page, and every key is read again (as today).
- `veto_result` and `page_values` become functions with no arguments (D6). The live layer builds them for each event, closing over the current assigns (F8: `Caller` still holds no assigns). `Operation` calls the veto after its own checks and before the re-read. So the order of D-before stays inside one function, and stage 6 only replaces the defaults. The veto still runs in the LiveView process: `Operation` runs there, but for the bulk run itself.

The functions, one per write: `save/1`, `clear/1`, `refer/1`, `reveal/1`, `run/1` (a row action or table action without a panel), `submit/1` (the panel: row, table, create, map cell, bulk), `bulk/1`. Opening a panel or a picker is a read, not a write: it stays in the live layer with `Act.open*`, `Edit.open/5` and `Record.fetch/3`.

### 3.2 The outcome

| Result | When | Today's result it replaces |
| --- | --- | --- |
| `{:ok, %Operation.Outcome{record, value, gone?, event: nil}}` | done; `value` is a generic action's return value; `gone?` for a record created and not readable | `{:ok, record}`, `{:done, value}`, `:gone` |
| `{:ask, question}` | a reference cell with a question: confirm first | `:changed` (`table_component.ex:2937`) |
| `{:halted, msg}` | the veto said no (stage 6) | — |
| `{:error, %Operation.Failure{record, message, places, form, unchosen}}` | the record is gone, the action refused, the form has errors, a chosen record is no longer there | `{:error, record, message, places}`, `{:error, nil, message}`, `{:error, form}`, `{:unchosen, inputs}`, `:unavailable` |
| `:refused` | a claim the model does not allow: nothing is said | the `else` branches that answer `%{ok: false}` |
| `{:start, run}` | `bulk/1` only: checks and veto passed; `run` goes into `start_async` | `run_bulk/4` (`:3640`) |

`event` stays nil until stage 6, when `Event.details/2` fills it. The record in an outcome is never drawn: the core puts it into the stream through `Present`. `reveal/1` returns the raw value (`{:ok, value} | :hidden | {:error, msg}`); the live layer formats it for the reply, as `revealed/4` does now (`:2871-2883`). It is still the only way to a sensitive value.

### 3.3 Files

`Live.Core.Files` keeps everything LiveView does: allow, refuse, wait, consume (`filed/3`, `attach/4`, `table_component.ex:3922-3977`). It hands `Operation` a `with_files` function that runs a given function inside `consume_uploaded_entry/3` with the files by argument name. `Operation.submit/1` calls it after the checks and the veto, so the re-read and the action run while LiveView holds the file, as today (§6). For a bulk run, the function makes the copies the run needs (`copies/1`, `:3981`); removing them stays in the live layer.

### 3.4 Message terms and the translation step

2a returns messages in three forms. A binding may itself be a message.

| Term | Means | Today |
| --- | --- | --- |
| `{:text, key, bindings}` | a text of the table's own. A plural key (`Text.plural`) needs `count` in `bindings` | `Text.t/2`, `Text.n/3` |
| `{:ash, message, vars}` | an action's message, as `AshPhoenix.Form` and Phoenix's `translate_error/1` take it | `Text.error/1` |
| `{:label, text}` | a name from the resource, translated if the backend has it | `Text.label/1` |

Example: `{:text, :not_saved, column: "Title", message: {:ash, "must be at least %{min}", [min: 3]}}`.

The third form is new against the target. `Errors` needs it for the name of a field inside a value (`errors.ex:173`, `act.ex:1073`). Labels in the model need no term: the live layer translates them once (`in_words/1`, `table_component.ex:870`).

This follows Ash: `AshPhoenix.Form` and `Ash.Error.to_error_class/1` give `{field, message, vars}`, and the host's `translate_error/1` makes words. `ash_graphql` and `ash_typescript` return `message` and `vars` apart for the same reason (`AshGraphql.Error`, `AshTypescript.Rpc.Error`).

**The translation step:** one function, `AshDataTable.Text.say/1`, term in, text out (D1). `Text` is already "every text a person reads" (3w), and it already has `t/2`, `n/3`, `label/1`, `error/1`, which `say/1` calls. No new module, so no second "Words" beside `Resource.Words`.

**Where terms become words (D5):** the entry keeps messages as terms (the status, the error, a failed cell's or row's message, a panel's errors and title, a run's result). `Present` passes them on. A part calls `Text.say/1` when it draws. A reply to the hook is made in the live layer, which calls `say/1` when it builds the map. All of it runs in the LiveView process. `in_locale/1` (`table_component.ex:3662`) goes: the bulk task returns terms, and `handle_async` makes the words. The German bulk test of `d1489d6` guards it.

**Wording does not change (D2).** The terms map to the same `msgid`s with the same bindings. Checked by the demo suite (it asserts texts), the German tests and the snapshots.

### 3.5 How far the terms reach

The dependency test fails from the end of 3c, and the rule says 2a makes no words. So by the end of 3b no file of 2a calls `Text` or `Format`. Today it lists 9 such lines and 7 edges (`act.ex`, `bulk.ex`, `edit.ex`, `errors.ex`, `query.ex` → `text.ex`; `act.ex`, `edit.ex`, `model/argument.ex` → `format.ex`). The terms therefore reach every outcome of 2a, not only `Operation`, `Bulk` and `Query`:

- `Errors`: where an error belongs stays in 2a; it returns terms. Its wording is `Text.say/1`.
- `Act`, `Edit`, `Bulk`, `Query`: their messages become terms.
- `Act`'s "what a generic action returned, as a person is told it" (`act.ex:256-292`, `Format.format`) moves to the drawing side: `Act` returns the value.
- **V9** (`model/argument.ex:79, 85` → `Format.input/3`): `Format.input/3` turns a value into the text a control holds. That text is locale-free: it is never a translation. `State` compares with it (`state.ex:295, 318, 366, 388, 519`), and so do `Act` and `Edit` (`act.ex:888-913`, `edit.ex:370`). D4: it moves into a new 2a module, `AshDataTable.Typed` (`of/3`). `Format.input/2,3` delegates to it, so the root tests of `Format` do not change. The copy leaves out the label translation that `members/1` does (`format.ex:282-284`), which `input` never uses.

### 3.6 The arguments of `Act`, `Edit`, `Pick`, `Bulk`, `Record` (F7)

Their arguments do not change: `Operation` calls them as the handlers do today, with the same keyword `opts`. Groups B and C of `test-coupling.md` (about 190 root tests that call them) keep their calls.

What does change is what some of them return: a term where a text was. About 20 root tests assert such a text, for example `model_test.exs:2889, 2946, 2965, 2973`, `sensitive_test.exs:366, 430, 437`, `unions_test.exs:494-538`, `managing_test.exs:554, 574, 576`, and the `Errors` tests at `model_test.exs:1266-1324`. In those tests the expected value changes from the text to the term (`"This record is no longer available."` becomes `{:text, :record_gone, []}`); the call does not. That is a new group of tests the owner has to agree to (D3). The exact list goes into the commit of 3b. The wording stays tested where a person reads it, in the demo suite.

## 4. 3c: `Live.Core`

### 4.1 The split

A move, like stage 1: one commit that only moves code, then commits that change it. All modules are `@moduledoc false` (F16).

| Module | From `table_component.ex` (lines of `d8e8c6e`) |
| --- | --- |
| `Live.Core` | `mount/1`, `update/2`, the wrappers that end in `tidy/1` (`548-1116`, `2839-2867`): init, the dispatch of an `Intent` to a topic module, `tidy/1`. Keeps `in_words/1` (labels, through `Text`) |
| `Live.Core.Reading` | `settle`, `read`, footer summaries (`1117-1196`); `handle_async` `:read`, `:summary` (`1522-1558`); showing a read (`1607-2047`); sort, filter, page, page size |
| `Live.Core.Cells` | `save`, `clear`, `reveal`, `refer`, `discard`, `dismiss`, `edit` (`2868-2980`) |
| `Live.Core.Picker` | picker and chosen inputs (`2981-3261`) |
| `Live.Core.Panel` | panel, `act`, `submit` (`3262-3569`, `3679-3866`); after a create or run, table actions (`4129-4395`) |
| `Live.Core.Bulk` | `3570-3678`; `handle_async(:bulk, …)` (`1559-1606`) |
| `Live.Core.Files` | `3867-4128` |
| `Live.Core.Nesting` | `relate`, `build`, `nested_model`, `creates`; `expand`, `toggle`; `picker_reader`, `nested_reader` (`4676-4724`) |
| `Live.Core.Updates` | `1197-1521`; `left`, `read_again` |
| `Live.Core.Url` | arguments, `go`, the URL (`4396-4497`) |

The component keeps its LiveView callbacks, each one line that calls the core, and `render/1`, which composes the parts. With that it is the wiring of target §4.6 (it becomes `Live.Embedded` in stage 4). The dependency test counts `live/table_component.ex` as part 4 from 3c. Then its edges to `Parts.*` and to `NotFoundError` are allowed. `Live.Core.Reading` no longer raises `NotFoundError` (`table_component.ex:1764`): it marks the entry `gone?`, and the component raises when the table is mounted and it was the first read.

### 4.2 Event names (Q4)

Every event from the browser is named `ash_data_table:TABLE_ID:event`; `TABLE_ID` is the table's id.

- **Markup.** The 22 places that name an event (`phx-click`, `phx-change`, `phx-submit`, `JS.push`, in `parts/*.ex`) use one helper, `Parts.Common.event(id, "sort")`.
- **Hooks.** The transport adds the prefix in `push/2` (`assets/js/transport/live_view.js`). `hook(behaviour)` gives it the table id from the element's id (`-grid`, `-panel`, `-picker`), as the grid does today (`grid/index.js:107`). No new marker in the markup. The hooks' own code keeps plain names.
- **Server.** `Live.Core` splits the name at the first and the last `:`. A name for another table or without the prefix gets the malformed answer. Then it calls `Intent.parse/2` with the plain event. The names of `push_event` (server to hook) do not change.
- **Test seams (group I, agreed).** `TablePage.send_event/5` adds the prefix to a plain name and leaves a prefixed name alone, because `click/2` reads it from the markup. `Table.forge` (`demo/e2e/support/table.ts:109-114`) adds it too. No test body changes.
- **Snapshots (D7).** The snapshot test strips `ash_data_table:ID:` from event attributes, as it strips hook names since stage 1b.

### 4.3 The dependency test in fail mode

`@report_only` (`test/architecture_test.exs:47`) becomes false at the end of 3c. The report of `d8e8c6e` lists 27 edges and 9 lines. Each goes as follows:

| Finding | Gone by | How |
| --- | --- | --- |
| 2a → `text.ex` (5), 2a → `format.ex` (3), 2a lines naming `Text`/`Format` (9) | 3b | message terms; `Typed` (3.5) |
| `parts/grid.ex`, `parts/panel.ex` → `Exposing`, `Embedding` (3) | 3a | `Present` flags |
| `parts/filter.ex` → `Resource.Operator` (`:36`, `takes/1`) | 3c | through `Model.Operator`, the 2a facade that exists (D8) |
| `format.ex` → `Embedding`, `Exposing`, `Words` (3) | 3c | through 2a: `Model.Field` for a type's fields and kinds, `Sensitive` for "empty", `Model` for the name in words (D8) |
| `live/table_component.ex` → `parts/*` (11), → `not_found_error.ex` | 3c | the component counts as part 4 (4.1) |

Still allowed after 3c: the couplings through data that xref cannot see and that the test's comment lists. The live component is given to `Parts.Grid` and `Parts.Picker` as `component` until stage 5. The presentation hints in `Model.Column` stay (F3). The S1 rule holds for the new modules: `Operation`, `Present` and `Live.Core.*` read only through `Query`, `Record`, `Pick` and `Bulk`.

## 5. Cross-cutting (§6a): what stage 3 decides

| Topic | Decision for stage 3 | Left to |
| --- | --- | --- |
| Telemetry | None of our own in v1 (D9). Ash already emits a span for every read and action (`[:ash, domain, :read \| :update \| :action]`), and LiveView one for every `handle_event` and `update`. The perf probe uses exactly these (`demo/perf/server/probe.ex:12-29`). `Operation` is the one place a span can be added later, without changing a shape | after v1, on demand |
| A raise in a write | Stage 3 keeps today's behaviour (D10). A generic action and a bulk run are rescued, logged and answered with "This could not be done." (`act.ex:246-253`, `bulk.ex:291-306`); a raise elsewhere ends the LiveView, as today. A log names the action, the resource and `Exception.message/1`, never a typed value. The rule of §6a (rescue every write in `Operation`, the entry left as before) is a change of behaviour | stage 6, with the veto |
| Reconnect | Nothing changes: `Live.Core` init does what `mount/1` and `update/2` do | stage 5 (the registry) |
| Tenant or actor change mid-page | Nothing changes (`update/2` rebuilds the model as today) | stage 4 (`attach` again), stage 5 (close all entries) |
| Language | Words only in the LiveView process; `in_locale/1` removed (3.4) | done in 3b |

## 6. Risks and how each is kept in check

| Risk | Check |
| --- | --- |
| The markup changes by accident when the parts read `Present` | snapshots byte for byte in 3a and 3b; panel snapshots 06a, 07a–c for the form |
| A sensitive value on a new path | `Present`'s sweep test with a mutation check; the browser suite's sensitive specs; the drift check reads every path to the drawing |
| Wording drifts in 3b | the demo suite asserts texts; German tests; snapshots |
| Root tests of groups B and C | arguments unchanged; only the agreed new group (D3) changes, and only the expected value |
| `Intent` stricter than today | it refuses no payload today's clauses accept; the demo tests that send odd payloads through `forge/5` must stay green unchanged |
| Change tracking: more bytes per action | `demo/perf/baseline.mjs` after 3a and 3c. The prefixed event names add a few bytes to a first render; the bytes of an event must not grow |
| The 3c move hides a change | move first, alone, like stage 1; then the namespacing, then fail mode, each its own commit |
| Diff size | 3a about 1,000 lines changed, 3b about 1,500 (2a and the handlers), 3c about 3,700 moved. Each sub-stage is its own green run and drift check (F6) |
| The order of a write changes with `Operation` | one function per write; root tests for `Operation` that drive each step (refused claim, veto, gone record), with a mutation check on the re-read |

## 7. Decisions for the owner

**D1. The name of the translation step.**

| Option | For | Against |
| --- | --- | --- |
| a. `AshDataTable.Text.say/1`, in the module that already makes every text | no new module; no second "Words"; `say/1` only calls `t/2`, `n/3`, `label/1`, `error/1` | `Text` grows by one function; the target's separate row merges into `Text` |
| b. A new `AshDataTable.Words` (the review's suggestion) | the name the review used | sits beside `AshDataTable.Resource.Words` (`humanize/1`): two "Words" for two things |
| c. A new `AshDataTable.Messages` | a name of its own | one more module that calls `Text` and does nothing else |

**Recommendation: a.** With it, the three term forms of 3.4, including the new `{:label, text}`.

**D2. May 3b change any wording?**

| Option | For | Against |
| --- | --- | --- |
| a. No: every text stays word for word | the refactor stays checkable by the demo suite and the snapshots | a clumsy text waits for a later build |
| b. Yes, where a term makes it easy | fewer odd texts | the demo suite and the snapshots no longer prove "no change" |

**Recommendation: a.**

**D3. How far the terms go in 3b, and the root tests that assert texts.**

| Option | For | Against |
| --- | --- | --- |
| a. All of 2a returns terms in 3b; about 20 root tests change their expected value from the text to the term (a new agreed group) | 2a word-free when the test starts failing; one change, done once | about 20 test bodies change (the expected value only) |
| b. Only `Operation`, `Bulk`, `Query` in 3b; `Act`, `Edit`, `Errors` keep their words, and the dependency test allows those edges until stage 6 | fewer tests change now (only the 2 `Bulk.run` tests) | the fail mode starts with exceptions; the same tests change in stage 6 anyway |

**Recommendation: a.**

**D4. V9: how `Model.Argument` gets the text of a control without `Format`.**

| Option | For | Against |
| --- | --- | --- |
| a. The locale-free part (`input/2,3`) moves into a new 2a module, `AshDataTable.Typed`; `Format.input` delegates | no rule bent; the root tests of `Format` stay; `State`, `Act`, `Edit` get it too | one more module (about 120 lines moved) |
| b. Allow 2a → `Format.input/3` as a named exception | no code moves | an exception in the rule that keeps section 7 possible |
| c. `State` compares cast values instead of texts | no text in 2a at all | a change of behaviour in how a default is told from a choice |

**Recommendation: a.** The name is open: `Typed` matches "what was typed" in `State` and `Act`.

**D5. Where terms become words.**

| Option | For | Against |
| --- | --- | --- |
| a. The entry and `Present` hold terms; the parts and the replies make the words | what section 7.2 asks ("messages and errors as terms"); a kit gets terms | the parts change in 3b as well (messages, panel errors, titles) |
| b. The live layer makes the words as it stores a message; the entry holds text | the parts do not change in 3b | `Present` gives text for messages; stage 7 has to change it again |

**Recommendation: a.**

**D6. The veto and the page values in `Operation.Input`.**

| Option | For | Against |
| --- | --- | --- |
| a. Functions with no arguments, built by the live layer per event; `Operation` calls the veto after its checks | the order "checks → veto → re-read" stays inside one function; stage 6 only changes the defaults | not literally F9's `veto_result` |
| b. Results, worked out before `Operation` is called (F9's sketch) | plain values | the veto runs before the table's own checks, or the checks move out of `Operation` |

**Recommendation: a.**

**D7. Event names in 3c, and the snapshots.**

| Option | For | Against |
| --- | --- | --- |
| a. The snapshot test strips `ash_data_table:ID:` from event attributes; the transport takes the id from the element's id | the snapshots stay identical apart from it; no new marker; the precedent of hook names (stage 1b) | the snapshots do not show the prefix |
| b. Snapshots updated once, with the diff read by hand | the files show the real markup | a large diff (every table, every control), easy to miss a real change in it |

**Recommendation: a.**

**D8. The last findings of the dependency test: part 3 and the words reading part 1.** Today `parts/filter.ex` calls `Resource.Operator`, and `format.ex` calls `Resource.Embedding`, `Exposing`, `Words`. §5.1 allows part 3 and the words only `Info` of part 1.

| Option | For | Against |
| --- | --- | --- |
| a. Through 2a: `Model.Operator.takes/1` (exists), `Model.Field` for a type's fields, `Sensitive` for "empty" | the agreed rule stays as it is | four thin functions in 2a |
| b. Amend §5.1: parts 3 and 3w may read the pure modules of part 1 that a verifier may read (5.3 rule 1) | no new functions | a kit part may then depend on the declaration; the rule gets weaker |

**Recommendation: a.**

**D9. Telemetry in v1.**

| Option | For | Against |
| --- | --- | --- |
| a. None of our own; Ash's and LiveView's spans cover every read, action and event | nothing to keep stable; the Ash way (AshPhoenix adds none either) | a host cannot tell a table's save from another update by the event name alone |
| b. Spans `[:ash_data_table, :operation, …]` and `[:ash_data_table, :read, …]` in 3b | one name per table step for a host's dashboards | event names and metadata become a public promise before v1 |

**Recommendation: a.** `Operation` keeps it easy to add later.

**D10. A raise inside a write.**

| Option | For | Against |
| --- | --- | --- |
| a. Stage 3 keeps today's behaviour; `Operation` rescues every write in stage 6 | stage 3 stays a refactor | a raise in a cell save still ends the LiveView until stage 6 |
| b. `Operation` rescues every write from 3b (§6a's rule) | the rule sooner | a change of behaviour inside a refactor stage; new tests |

**Recommendation: a.**

## 8. Order of work and the done-check of each sub-stage

Each sub-stage: each suite once (root, demo, browser), its own commit or commits on `main`, `docs/agents/architecture.md` updated, and then the drift check of target §9. It is done only after the drift check.

**3a**
1. `Present` structs and `Present.row/…`, with the sweep test and its mutation check.
2. The core puts `Present.Row`s into the stream; `Parts.Grid` reads the cells.
3. `Present.panel/2` (with `panel_value/3`); `Parts.Panel` without `to_form/1`.
4. `Present.picker/1` and the chosen labels.
5. `Intent` with its tests; the `handle_event/3` clauses call it first.

Done when: snapshots byte for byte; no test changed; the report has lost the grid and panel findings; the bytes of the baseline actions did not grow.

**3b**
1. The term types and `Text.say/1`, with tests.
2. `Typed`; `Format.input` delegates (V9).
3. `Errors`, `Act`, `Edit`, `Bulk`, `Query` return terms; the entry and `Present` hold terms; the parts and replies call `say/1`; `in_locale/1` removed.
4. `Operation` with `Input` and `Outcome`; the handlers call it for save, clear, refer, reveal, run, submit, bulk.

Done when: snapshots byte for byte; the demo suite and the German tests green with no change; only the agreed group of root tests changed, and only in its expected values; no 2a → `Text`/`Format` finding left.

**3c**
1. Move into `Live.Core` and `Live.Core.*`, nothing else (one commit).
2. The component delegates; it counts as part 4; `NotFoundError` is raised by the component.
3. The last findings (D8).
4. Event names: parts, transport, server, seams, snapshot normalising.
5. `@report_only false`.

Done when: the dependency test passes in fail mode; only the seams of group I changed (`send_event/5`, `Table.forge`, the snapshot normaliser); the browser suite green; the baseline bytes per action did not grow.
