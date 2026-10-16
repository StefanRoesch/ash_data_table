# Stage 6: design note (events, commands, page values, veto, selection, controlled mode)

Status: **accepted by the owner, 2026-10-16, all as recommended (D1–D19).** Code references are of `4fe1001`. LiveView references are of the installed `phoenix_live_view` 1.2.12 under `demo/deps/phoenix_live_view/` (written `LV lib/…`); Ash 3.36.1 and AshPhoenix 2.3.25 under `demo/deps/` (`Ash lib/…`, `AshPhoenix lib/…`). Names follow [target.md](target.md); words follow `CONTEXT.md`. The model for this note is [stage4-design.md](stage4-design.md).

Stage 6 adds the first new abilities of the refactor. Until now every stage was a move. This one gives the host a way to hear what the table did (events), to tell it things (commands), to add server values to every Ash call (page values), to say no before a write (veto), and to draw what opens itself (controlled mode). It also moves the selection to the server (RQ1).

## 0. The decisions at a glance

Answer "as recommended", or per number.

| # | Question | Recommendation |
| --- | --- | --- |
| D1 | How events reach the host, in each of the three ways | `send(self(), {:ash_data_table, id, {event, details}})`, opt-in with `notify`. The tag's host gets them in its own `handle_info/2` (a component runs in its LiveView's process). On the router page the host hears them through an `on_mount` hook of its `live_session` that attaches a `:handle_info` hook. The table's own hooks never halt them |
| D2 | Which id the message carries; nested tables; pickers | The id of the table on the page. A nested table's event says its own `table` id and its `path`. A picker's table sends no events |
| D3 | The events and their details | Eleven events (2.2). `:read` says the state as URL params, the count and the total, never rows. Keys are primary-key maps. The record is scrubbed (`Sensitive.scrub/1`). Only after success |
| D4 | Where the details are made | In 2a: a new `AshDataTable.Event` builds them from what `Operation` did (`Outcome.event`, a field that waits for this) and from a read. `Live.Core.Notify` filters by `notify` and sends |
| D5 | Page values: when they are called, with which assigns | `context`, `private_arguments`, `page_arguments`: a map, or a function of arity 1 or 2 (`assigns`, `table_ref`). Called by 2b in the LiveView process before every read and every write (before any `start_async`). A change of their value does not by itself read again; `refresh/2` does. The assigns are `socket.assigns` as LiveView gives them, with nothing dropped (no use of `__changed__`) |
| D6 | `context` beside the table's own context and the scope's | The page's map is given as Ash's `context`; Ash deep-merges the scope's (Ash `lib/ash/scope.ex:49`). The table's own key (`ash_data_table_origin`) is put last, so a page cannot set it. Summaries get the page's context too |
| D7 | Private arguments | Per action, only the names the action declares `public?: false`; other names are ignored (one function serves many tables). Writes through Ash's `private_arguments:` option; reads through `Ash.Query.set_argument/3` |
| D8 | `page_argument` | An entity inside a table's `action` (`page_argument :assignee_id`), for row and table actions only. A verifier checks it. The panel never asks it. A page that gives no value raises when the action opens or runs |
| D9 | The veto | `before_action`, arity 1 or 2. `Operation` builds the `AshDataTable.Request` after its checks and calls a closure 2b made; answers are `:cont` or `{:halt, message}`; anything else raises. It only halts; "changing" an action is what page values are for |
| D10 | Selection on the server | The hook sends `select` on every change; the entry holds the keys (claims) and `all?`. The server decides when a selection ends (filters change, a row goes, a run is done) and tells the hook (`ash_data_table:select`). `bulk` and `bulk_run` take the selection from the entry |
| D11 | Commands | `refresh/2`, `put_state/3`, `clear_selection/2`, `selected_records/2`, plus `detach/2`. For the table on the page, by attach name. `put_state` goes through `State.from_params/2`; with `url: true` it patches the URL |
| D12 | What a host may read of a `Table` | Functions, not fields: `AshDataTable.status/1` (id, state as params, count, total, loading?, error, selected) and `AshDataTable.request/1` (controlled mode). `Table` stays opaque |
| D13 | "Open" | `open: "Open"` at attach, on the tag, on the router line: a button in the actions cell of each row of the table on the page. It sends `:row_opened` with the key, whether or not `notify` lists it |
| D14 | Controlled mode | With `attach` only: `controlled: [:confirm, :panel]`. The table holds the request, the host draws it and answers with commands; every answer goes through `Operation`. v1: the questions before an action, and the panels of row, table, create and selection actions with plain fields. Not in v1: the picker, a map cell's panel, panels with files, groups or chosen records (attach raises) |
| D15 | Order of work | Page values and veto; events; selection; commands; "open"; controlled mode; the router line last |
| D16 | Browser runs and the ten-runs rule | Ten runs in a row for the specs of selection, the picker, bulk, live updates and the new ones; the whole suite once |
| D17 | Fallback | Per step. Selection: two fixes, then the server keeps a copy the hook sends and the hook still decides. Controlled mode: moved to stage 7 |
| D18 | Performance | `baseline.mjs` at the start and the end, plus "select a row" and "a cell save with `notify` and page values on" |
| D19 | Internals of dependencies the code uses today (owner's rule, 2026-10-16) | Section 11: the one stage 6 builds on (`__changed__` in `page_assigns/1`) goes in step 1; the four others (three more `__changed__`, the portal's markup in tests) in a step 0b of their own, before step 1 |

## 1. What stage 6 changes, and what it does not

**Changes.** New options: `notify`, `context`, `private_arguments`, `page_arguments`, `before_action`, `open` (tag, attach, router line); `controlled` (attach only). New public functions in `AshDataTable`: `refresh/2`, `put_state/3`, `clear_selection/2`, `selected_records/2`, `status/1`, and for controlled mode `request/1`, `validate_request/4`, `submit_request/4`, `confirm_request/3`, `cancel_request/3`. New modules: `AshDataTable.Event` and `AshDataTable.Request` (2a, public types), `Live.Core.Notify` (2b). DSL: `page_argument` inside a table's `action`. The selection moves from the hook to the entry.

**Stays the same.** With none of the new options, a table behaves as today, apart from the selection's new event (`select`), which the person does not notice. The safety order stays in `Operation`: checks → veto → files → re-read → action (`operation.ex:3-18`). No command writes. The markup snapshots change only where "open" is drawn (a new snapshot state, not a rewrite of the others).

## 2. The shape

### 2.1 One host, all of it

```elixir
def mount(_params, _session, socket) do
  {:ok,
   AshDataTable.attach(socket, :tasks, MyApp.Tracker.Task,
     scope: socket.assigns.current_scope,
     notify: [:row_saved, :selection_changed],
     context: fn assigns, _table_ref -> %{shared: %{project_id: assigns.project.id}} end,
     before_action: &MyAppWeb.Guard.before_action/2,
     open: "Open"
   )}
end

def handle_info({:ash_data_table, "task", {:row_opened, %{key: %{id: id}}}}, socket),
  do: {:noreply, push_navigate(socket, to: ~p"/tasks/#{id}")}

def handle_info({:ash_data_table, "task", {:row_saved, _details}}, socket),
  do: {:noreply, AshDataTable.refresh(socket, :summary_table)}
```

### 2.2 The events

Every event's details have `table` (the id of the table it is of), `resource`, and for a nested table `path` (the ids from the table on the page down to it). Keys are primary-key maps (`%{id: "…"}`). A record is the one the action returned to the person, scrubbed with `Sensitive.scrub/1` (`sensitive.ex:46-78`): a sensitive value is `%Sensitive.Masked{}`. `arguments` leave out sensitive arguments and name a file argument without its content (D-events, "to settle when built").

| Event | When | Details besides the common ones |
| --- | --- | --- |
| `:read` | a read of a page is shown (not a live update's read of a few rows) | `state` (the URL params, `State.to_params/2`), `count` (rows shown), `total` (nil where the action does not count) |
| `:read_failed` | a read failed or was refused | `message` (the text the person reads), `forbidden?` |
| `:row_saved` | a cell, a reference cell, "Clear", a map cell's panel | `action`, `key`, `changed` (the columns the person edited), `record` (nil when it is no longer the person's to read) |
| `:row_created` | a create | `action`, `key`, `arguments`, `record` |
| `:row_destroyed` | a destroy action on one row | `action`, `key`, `arguments` |
| `:action_ran` | an update or a generic action on a row, a table action | `action`, `key` (nil for a table action), `arguments`, `record` or `result` |
| `:bulk_ran` | a run on a selection is done | `action`, `arguments`, `all?`, `succeeded` and `failed` (keys) |
| `:selection_changed` | the selection changed (D10) | `selected` (keys, **claims**: what the browser said, not read again), `all?` |
| `:row_expanded`, `:row_collapsed` | a relationship line under a row opened or closed | `key`, `relationship` |
| `:row_opened` | "Open" on a row (D13) | `key` |
| `:requested` | controlled mode: a request is waiting (D14) | `ref`, `kind` |

The list only grows; an event keeps its name and what it carries (D-events).

## 3. Decisions for the owner

**D1. How events reach the host.**

Public API used: the moduledoc of `Phoenix.LiveComponent` says a component runs in its LiveView's process and shows `send(self(), …)` to the parent (`LV lib/phoenix_live_component.ex:324, 426, 492`), so `send(self(), …)` from the tag reaches the host's `handle_info/2`. With `attach` the core runs in the host's process anyway. The router page is the library's LiveView (`live/page.ex`): no host code runs there but the host's `on_mount` hooks, which LiveView documents as the way to "add custom behaviour to other callbacks via `attach_hook/4`" (`LV lib/phoenix_live_view.ex:541-542`, `attach_hook/4` and `{:cont, socket}` `:1655-1670`). A host LiveView whose `handle_info/2` has no clause for a message raises `FunctionClauseError` (plain Elixir). So events must be opt-in.

| Option | For | Against |
| --- | --- | --- |
| a. `send(self(), {:ash_data_table, id, {event, details}})`, opt-in: `notify: true` (all) or a list of event names; an unknown name raises. On the router line `notify:` too; the host hears them in an `on_mount` hook that attaches a `:handle_info` hook. The table's `:handle_info` hook halts only `{:ash_data_table_heard, …}` (`hooks.ex:270-277`), so events pass | the shape agreed in D-events; one way in all three modes; nothing reaches a host that did not ask | on the router page the host needs an `on_mount` hook to hear anything |
| b. A callback option (`notify: {M, :f}`) called in place | no message | the host's code runs inside the table's callback, with the table's socket half done; not what D-events agreed |

**Recommendation: a.** The guide shows the `on_mount` hook for the router page. That hook is also where a router page gives commands (D11), which RQ4 allows there.

**D2. Which id the message carries; nested tables; pickers.**

A nested table's id is made by the table (`ID-row-KEY-t-NAME`, `live/core/nesting.ex:369-373`); the host never wrote it.

| Option | For | Against |
| --- | --- | --- |
| a. The id of the table on the page (the one the host gave, or its default); the details say `table` (the entry's own id) and `path` for a nested one. A picker's table sends nothing: what is chosen becomes a `:row_saved` or a panel's value | the host matches one id per table it placed; S7's "nested tables add their path" | a host that wants only the top's events checks `path` |
| b. The entry's own id | exact | the host matches ids it never wrote |

**Recommendation: a.**

**D3. The events and their details.** As 2.2. Three points need a yes:

- `:read` (F19): state as URL params, count and total, no rows. The rows are in the stream, not on the server (D-nested); sending them would copy a page of records into a message on every read.
- `:read` is not sent for a live update's re-read of a few rows (`Query.rows/4`); `:row_saved` is not sent for what a live update brings (it is someone else's write).
- The record is scrubbed, as the owner decided (target-questions, "The record in an event"). `selected_records/2` (D11) gives scrubbed records too, for the same reason.

**Recommendation: as 2.2.**

**D4. Where the details are made.**

`Operation.Outcome` has an `event` field, "filled in stage 6" (`operation.ex:98-105`). `Operation` knows the action, the row's primary key and the arguments it gave; the live layer knows only the intent.

| Option | For | Against |
| --- | --- | --- |
| a. `AshDataTable.Event` (2a) builds the details; `Operation` puts them into `Outcome.event`; the live core adds `table`, `path` and sends through `Live.Core.Notify` after the reply is built. A read's details come from `Event.read/…` in `Core.Reading.show` | one place per event; scrubbing in 2a, next to `Present` (F1); any later adapter gets the same details (§7.3 point 9) | `Operation` grows a little |
| b. The live core builds them from intent and outcome | `Operation` untouched | the key and arguments rebuilt in 2b; two places that must agree |

**Recommendation: a.** `:bulk_ran` is built in `Core.Bulk.handle_async` from the run's outcome, which already carries the keys done and failed (`live/core/bulk.ex:23-48`).

**D5. Page values: when they are called, with which assigns.**

Shapes are decided (Q5, Q7): a map, or `(assigns, table_ref) -> map`, arity 1 accepted; `table_ref = %{table: id, path: path, resource: resource}`. Open: when, with which assigns, and what a change does. Today a read runs only when `{model, state, opts, key, arguments}` changes (`live/core/reading.ex:63-64, 89-90`).

**When.**

| Option | For | Against |
| --- | --- | --- |
| a. Called before every read and every write, in the LiveView process, before any `start_async` (F8, F9). The values go into the read's `opts` but not into the key that decides whether to read; a host whose values changed calls `refresh/2` | predictable: one call per read or write; a function that returns a new value each time (`DateTime.utc_now/0`) does not make every event read again | a tag cannot `refresh` (RQ4): its new values count from its next read |
| b. Also part of that key | a tag reads again by itself when its values change | a careless function reads on every event and every render of the parent |

**Recommendation: a.** A function that raises, or returns no map, raises with a message that names the option.

**Which assigns (a finding under the rule "no internals of a dependency").** With `attach` the default of an asked argument is given `Core.page_assigns/1`, which drops `:__changed__` by name (`core.ex:558-568`, stage 4 D9). `__changed__` is LiveView's private change-tracking key, not documented as part of the assigns. The page values would inherit that. The tag gives its `assigns` attribute; the router page its socket's assigns.

| Option | For | Against |
| --- | --- | --- |
| a. The function gets `socket.assigns` as LiveView gives it (the `assigns` field of the documented type `Phoenix.LiveView.Socket.t`, `LV lib/phoenix_live_view/socket.ex:77-91`), dropped of nothing. The same for an asked argument's default: `page_assigns/1` loses its drop list | public; the host reads what it wants by name, as it does in its own callbacks | the map holds keys the host did not set (LiveView's, the `Table`s); harmless in one process, no copy |
| b. An option `assigns: [:project, :current_user]` naming what the function gets (`Map.take/2`) | public; the function sees only what the host chose | one more option, and a host must keep it in step |

**Recommendation: a.** It changes stage 4's `page_assigns/1` in step 1 (D19).

**D6. `context` beside the table's own and the scope's.**

The table already uses Ash's `context` option: a table that follows live updates puts `%{ash_data_table_origin: pid}` there with `Keyword.put` (`query.ex:722-723`), and the summaries drop `:context` altogether (`query.ex:464-466`). Ash deep-merges the context of a `scope` with the `context` option (`Ash lib/ash/scope.ex:45-49`).

| Option | For | Against |
| --- | --- | --- |
| a. `Query.reader_opts/1` merges: the page's map, then the table's own key last. Summaries keep the page's context and drop only the origin key | the page cannot fake the origin; the scope's context (for example `shared.locale`) still arrives; a summary sees what the rows see | `reader_opts/1` and `aggregate/4` change |
| b. The page's context under a key of its own (`%{ash_data_table_page: …}`) | no clash at all | not how Ash's own extensions pass context; a policy would have to look in a place only this library uses |

**Recommendation: a.** "Every call": every `Ash.*` and `AshPhoenix.Form.*` call of `Query`, `Record`, `Pick`, `Act`, `Edit`, `Bulk` (§9 stage 6, item 2).

**D7. Private arguments.**

Public API used: the documented option `private_arguments:` of `Ash.Changeset.for_*` (`Ash lib/ash/changeset/changeset.ex:2036-2039`, its doc `:2271`), of `Ash.ActionInput.for_action/4` (`Ash lib/ash/action_input.ex:190`) and of `Ash.bulk_update/4` and `Ash.bulk_destroy/4` (`Ash lib/ash.ex:462-467`); AshPhoenix documents that "any additional options will be passed to the underlying call to build the source … and provided again when `Form.submit/3` is called" (`AshPhoenix lib/ash_phoenix/form/form.ex:527-530`); `Ash.Query.set_argument/3` (`Ash lib/ash/query/query.ex:2971`, public). A read has no `private_arguments:` option (`for_read/4`'s documented options, `query.ex:806-852`), and `set_argument/3` sets a public argument as readily as a private one, so the table must filter.

| Option | For | Against |
| --- | --- | --- |
| a. Per action, take only the names the action declares `public?: false`; ignore the rest. Writes: `private_arguments:`. Reads (the table's read action, a nested table's, a picker's, the re-read before a write): `set_argument/3` for those names only | one function can serve every table of a page; "same-named arguments of two resources" (D-before 5) are told apart by `table_ref`; the filter is what keeps `set_argument/3` from setting a public argument | a misspelt name is silently ignored |
| b. Raise on a name the action does not have | catches typos | one function for several resources raises for the other resources |

**Recommendation: a.** The guide says so in one line.

**D8. `page_argument`.**

Decided: a public argument filled by the page, declared in the `action`, never asked by the panel (D-before 3, Q7, S11). Open: the DSL form, which actions, and a missing value. `create_action` and a column's `update_action` are options, not `action` entities (`resource/table.ex:26-27, 77-82`), so they have no place to declare it.

| Option | For | Against |
| --- | --- | --- |
| a. An entity `page_argument :name` inside `action` (as `reference` is, `resource.ex:747`); row and table actions, also on a selection; create and inline edits take page values through `private_arguments` (make that argument private). Verifier (a clause of `VerifyActions`): a public argument of that action, not its `record_argument`, not twice. A value the page does not give (no key) raises when the panel opens or the action runs, naming the action and `page_arguments` | as decided; room for options later; a missing value is a developer's mistake, found on first use | nothing for create |
| b. A list option `page_arguments [:a, :b]` on `action` | shorter | the same name as the page option |
| c. Also a `create` entity | covers create | new DSL for one case |

**Recommendation: a.** The value is merged over the params as `record_argument`'s is (`act.ex:184-191`); on a selection the same value goes to every record.

**D9. The veto.**

Decided: `before_action` is asked after the table's checks and before the re-read, can only halt, sees no typed value and no record (D-before 2, S10); bulk: once, before the run (D-before 4). Today `Operation.Input.veto` is a function of no arguments that answers `:cont` (`operation.ex:82, 91-92`), called after the checks of each write (`:145, 158, 175, 235, 244, 270, 285, 300, 315, 344, 379`). Two things are open:

1. The request needs what the checks found (the action, the column), so the host's function cannot be called before `Operation` runs. 
2. Today any answer but `:cont` and `{:halt, _}` becomes `:refused` (`operation.ex:469-470`): nothing runs and nothing is said. A host function that returns `:ok` would silently refuse every write.

| Option | For | Against |
| --- | --- | --- |
| a. `Input.veto` becomes a closure of one argument that 2b makes (it holds the assigns and the host's function); `Operation` builds the `AshDataTable.Request` after its checks and calls it, in the LiveView process. 2b checks the answer: `:cont`, `{:halt, message}` with a string; anything else raises. Arity 1 (`request`) and 2 (`request, assigns`) | the order stays in `Operation`; 2a never sees assigns (F8); a wrong answer is found at once | — |
| b. 2b asks the veto before `Operation` | the input holds a plain answer, as target §4.3 sketched | the veto would be asked for claims the checks refuse, and before the action is known |

**Recommendation: a.** The request: `table`, `path`, `resource`, `action`, `type` (`:update`, `:create`, `:destroy`, `:action`), `from` (`:cell`, `:clear`, `:reference`, `:map_cell`, `:row`, `:table`, `:create`, `:bulk`), `column`, `key` and `selection` (claims). A halt is said where a refused save is said, the typed value stays (today's `saved/5`, `cells.ex:180-188`; a panel stays open, `panel.ex:575-576`). "Show" and opening a panel are reads and are not asked (D-before 6).

The brief asked whether the veto may also change an action. The owner decided it cannot (D-before 2, target §1.5); what a page adds to an action goes through `context`, `private_arguments` and `page_arguments`, which Ash checks as it checks anything else. A veto that could add a value would be a second, unchecked way in. Not proposed.

**D10. Selection on the server (RQ1).**

Today the hook alone knows what is selected (`assets/js/grid/selecting.js:56-81`). The server hears it only with `bulk` (`:276-291`) and a picker's choice (`:17-21`, `assets/js/picker.js:35-36`). The hook gives a selection up when the filters change (`data-scope`, `parts/selection.ex:71`, `selecting.js:171-177`); the server tells it of a row that went (`ash_data_table:unselect`, `live/core/reading.ex:540-548`) and of the rows a run did not do (`ash_data_table:bulk`, `live/core/bulk.ex:44`). The entry's `selected` is empty (`live/entry.ex:149-157`).

| Option | For | Against |
| --- | --- | --- |
| a. The hook sends `select` (`rows` as it names them today, or `all`) on every change, no reply. The entry keeps `selected` and `all?`. The server decides when a selection ends: filters, arguments or the `of` limit changed, a row went, a run left only its failed rows, `clear_selection/2`; it tells the hook with one `push_event`, `ash_data_table:select` (LiveView dispatches it after the patch, `LV lib/phoenix_live_view.ex:866`). `bulk` and `bulk_run` carry the action only; `unselect` and `data-scope` go | one truth; commands and `:selection_changed` need it; no adapter needs selection logic (§7.4) | one push per change (a Shift+Down held down sends many; each is small) |
| b. The hook keeps deciding; the server keeps a copy | smallest change | two places that can disagree; `clear_selection` would need the hook's say |
| c. The server renders the selection (`aria-selected`, the boxes) | the hook paints nothing | every row in the stream inserted again on every click |

**Recommendation: a.** The keys are claims until read (`selected_records/2`, `Bulk.run/5`). A picker's table keeps its own flow (`picked`); its `select` events only keep its entry right. `DemoWeb.TablePage.bulk/4` (`demo/test/support/table_page.ex:496-497`) sends `select` before `bulk`: one helper, the test bodies stay (group R).

**D11. Commands.**

Decided: with `attach` and on the router page only (RQ4); no command writes (D-events); `put_state` takes the whole URL vocabulary (Q18). S8 lists `selected_records(socket, table, selection)` and says "each returns the socket": that cannot hold for a function that returns records, and with the selection on the server the third argument has nothing to say.

| Command | What it does |
| --- | --- |
| `refresh(socket, name)` | reads the table on the page again, as `read_again` does (`Reading.reread/1`, `reading.ex:552`), and its summaries; nested tables close as on any read |
| `put_state(socket, name, params)` | `params` as the URL holds them under the table's id (`%{"sort" => "-title", "f" => …, "page" => "2"}`), through `State.from_params/2` and `State.fit/2` (`state.ex:59-69`): what the model does not allow is dropped, as in a URL. With `url: true`, a `push_patch` to the new URL, so the URL stays the truth; else the entry's state, and a read |
| `clear_selection(socket, name)` | empties the selection and tells the hook |
| `selected_records(socket, name)` | `{:ok, records} \| {:error, message}`: the selected keys read again as the person through the table's read action with its arguments and page values (`Query.records/3`; `all?`: everything that matches, read in batches, `Query.matching/3`), scrubbed |

| Option | For | Against |
| --- | --- | --- |
| a. The table on the page only, by attach name (`:table` on the router page); an unknown name raises. `selected_records/2` as above | the host addresses what it placed; nested tables change by the person's hand | a host cannot refresh a nested table alone |
| b. Also a nested table, by its id | complete | the host must learn generated ids (D2) |

**Recommendation: a.** A command runs inside `Live.Hooks.within/3` and ends in `tidy/1`, as the hooks do (`hooks.ex:206-218`). In tag mode no table is attached under any name, so every command raises: that is RQ4, with no extra check.

**D12. What a host may read of a `Table`.**

Stage 4 left the read-only fields (`id`, `state`, `count`, `total`, `loading?`, `error`) to this stage (stage4-design D14). `Table` says it is opaque and "what it holds may change" (`live/table.ex:9-10`).

| Option | For | Against |
| --- | --- | --- |
| a. `AshDataTable.status(table)` returns a documented map: `id`, `state` (URL params), `count`, `total`, `loading?`, `error` (text), `selected`, `all?` | `Table` stays free to change; one documented shape | one function call in a template |
| b. Documented fields of `Table` | `@tasks.count` | the struct's layout becomes a promise; most fields are the entry's |

**Recommendation: a.**

**D13. "Open".**

Decided: offered by the page (`open: label` at attach, on the tag, on the router line), event `:row_opened` with the key (Q8, D-nolinks). Open: where it is drawn, which tables, and its relation to `notify`.

| Option | For | Against |
| --- | --- | --- |
| a. A button with the label in the actions cell of each row of the table on the page, first among the row's buttons; the hook sends `open` with the row's key; the key is looked up in the entry's `rows` (a claim) and `:row_opened` goes out with the primary key. `open:` sends `:row_opened` whatever `notify` says. No veto, no re-read: nothing is written or shown | keyboard and screen readers as for row actions; the event is pointless without the option and the option without the event | one more button per row |
| b. The whole row (click, Enter) | fewer buttons | Enter already starts editing a cell; a click already moves focus |

**Recommendation: a.** Nested tables: not in v1 (one label per page does not fit tables of other resources). The look is stage 7's.

**D14. Controlled mode.**

Decided (2026-10-15): the table reports the request with its data; the developer decides what is shown and hands the inputs back with commands; the default stays the table's own drawing; safety stays in `Operation`; it needs `attach`. Stage 7 shapes how the table's own drawing opens (modal or inline). Stage 6 is the data and the protocol only.

What opens today: the action panel (row action, table action, create, a selection, a map cell; `live/core/panel.ex:32-227`, `bulk.ex:141-170`, `cells.ex:83-130`), the picker (`live/core/picker.ex`), and the questions before an action, asked by the hook from a reply or a push (`panel.ex:70-76`, `bulk.ex:91-93`; a reference cell's question, `cells.ex:199-200`). The panel's form already lives in the entry and is drawn from `Present.panel/2`.

| Option | For | Against |
| --- | --- | --- |
| a. v1: `:confirm` (every question before an action) and `:panel` (row, table, create and selection panels with plain fields). The table opens the request as today (the form in the entry) but does not draw it; `AshDataTable.request(@tasks)` gives `%{ref, kind, action, key, question, fields}`, each field `name`, `label`, `type`, `required?`, `value` (nil for a sensitive one), `values`, `errors`, in words; `:requested` goes out. The host answers with `validate_request/4`, `submit_request/4` (params as the panel's form sends them), `confirm_request/3`, `cancel_request/3`; each goes through `Operation` (claims, page arguments not overridable, veto, re-read), a stale `ref` is refused. Turned on per table and kind: `controlled: [:confirm, :panel]`. A table whose actions include a panel v1 cannot hand out (a file, a group or union, a chosen record) raises at attach and names the action | the protocol on the kinds that are plain data; `Present` stays internal (Q14): the request is a small documented projection made by `AshDataTable.Event` | the picker and the richer panels wait |
| b. Everything, the picker included | complete | a controlled picker is a whole table drawn by the host; files need the table's upload names on the host's form; groups need the panel's add and remove protocol. Each is a design of its own |
| c. Nothing in stage 6; all in stage 7 | one design for look and behaviour | stage 7 grows; the events and commands of this stage are not tried on it |
| d. Per action instead of per kind (`controlled: [panel: [:assign]]`) | finer | more to document; can come later on top of a |

**Recommendation: a.** One request per `Table` at a time; a new one cancels the old. The line to stage 7: stage 6 holds the request, its data, its commands and the check of what may be controlled. Stage 7 decides how the table's own panel, picker and dialog open, and widens controlled mode to the picker and the richer panels.

**D15. Order of work.** Q19 says: page values and veto, then events, then commands, then "open".

| Option | For | Against |
| --- | --- | --- |
| a. Page values and veto → events → selection → commands → "open" → controlled mode → the router line | events report what the pipeline did, so it comes first (Q19); `:selection_changed` and two commands need the server's selection, so it comes after the other events and before the commands; controlled mode uses events and commands; Q6 puts the router line last | the selection, the riskiest step, is in the middle |
| b. Selection first | the risky step early | its event and commands are built steps later, and it is tested twice |

**Recommendation: a.**

**D16. Browser runs and the ten-runs rule.**

| Option | For | Against |
| --- | --- | --- |
| a. After step 3 (selection): `selection`, `picker`, `task_labels`, `actions`, `live_updates`, `files`, `attached` ten times in a row (`--repeat-each=10`), the whole suite once. After step 5 ("open") and step 6 (controlled): their new specs ten times. The rest once | the selection changes the hook; the rest is mostly server work | about 900 test runs for the ten |
| b. The whole suite once after each step | quicker | a race in the hook shows only in repeats (stage 5) |

**Recommendation: a.** A failure caused by the new mechanism gets two fixes, then D17.

**D17. Fallback.**

| Option | For | Against |
| --- | --- | --- |
| a. Per step. Selection: two fixes or one failure in ten runs, then option b of D10 (the server keeps the hook's copy; the hook decides; `clear_selection/2` sends `ash_data_table:select`). Controlled mode: moved to stage 7 as it is. The router line: dropped from v1 (the `on_mount` hook still hears and commands). You are told | each step stands alone | — |
| b. You decide each case | judgement | the build waits |

**Recommendation: a.**

**D18. Performance.**

New costs: a page-value function per read and write; a message per event (a scrubbed record copied into the mailbox of the same process); a `select` event per selection change.

| Option | For | Against |
| --- | --- | --- |
| a. `demo/perf/baseline.mjs` at the start (tag `stage6-start`) and the end on `/tasks`, plus two actions: "select a row" (bytes and time of `select`), and a cell save on a support page with `notify: true`, `context` and `before_action` set. Times within 20 %, Ash reads and statements the same | the new paths measured where they run | one more support page in the perf environment |
| b. The old actions only | nothing new | the new costs unmeasured |

**Recommendation: a.**

## 4. Order of work

Each step: each suite once (root, demo, browser), its own commits on `main`, `docs/agents/architecture.md` corrected where the step made it false.

0. Tag `stage6-start`. Perf run (D18).
0b. **No internals of dependencies** (D19): the four items of section 11 but the first, each with the public way it names. No behaviour change; snapshots identical.
1. **Page values and veto** (D5–D9). `Caller` holds the four functions (Q5, F8); 2b evaluates the page values and makes the veto closure; `Query.reader_opts/1` merges context (D6); private arguments per action (D7); `page_argument` entity, verifier, model, panel (D8); `AshDataTable.Request`. Options on attach and the tag. Groups P, Q.
2. **Events** (D1–D4). `AshDataTable.Event`, `Outcome.event`, `Live.Core.Notify`, `notify` on attach and the tag, all events but `:selection_changed`, `:row_opened`, `:requested`. Group S.
3. **Selection on the server** (D10). `select` in `Intent`, the hook's `select`, `ash_data_table:select`; `bulk` from the entry; `:selection_changed`. Group R; the browser runs of D16.
4. **Commands** (D11, D12). Group T.
5. **"Open"** (D13). A snapshot state with `open`. Group U.
6. **Controlled mode** (D14). Group V.
7. **The router line** (Q6): `notify`, `context`, `private_arguments`, `page_arguments`, `before_action`, `open` as `{Module, :function}` or a literal map in `__live_opts__` (`router.ex:128`). Group W.
8. Moduledocs of the new public functions and modules, `docs/agents/architecture.md`, the perf comparison, the as-built section of this note.

## 5. Gate

- After each step: the three suites green.
- After step 3: the ten runs of D16 and the whole browser suite once.
- After steps 5 and 6: their specs ten times.
- Perf (D18) at the end. No-go: D17.

## 6. Tests

**Group P (new, root): page values and veto in 2a.** `context` reaches a read, a nested read, a picker's read, the re-read before a write, a save, an action, a create, a run on a selection and a summary (a resource whose preparation or change records `context`); the origin key cannot be set by the page; private arguments reach a read (`set_argument/3`) and a write; a public name given as private is not set; a name another action has is ignored. The veto: asked after the checks (a claim the model refuses never reaches it), before the files and the re-read (a halt reads nothing: count the reads); a run on a selection asks once; an answer other than `:cont` or `{:halt, string}` raises. Mutation checks here (build rules: what gets written).

**Group Q (new, root and demo): `page_argument`.** The verifier's messages (`documentation/topics/mistakes-at-compile-time.md`); the panel without the field; the value given; on a selection, to every record; a missing value raises.

**Group R (changed and new): selection.** Changed: `DemoWeb.TablePage.bulk/4` sends `select` first (one helper; no test body changes). New, demo: the entry follows `select`; a filter, a gone row and a run's failed rows end or narrow it; `:selection_changed`. New, browser: what is selected survives a page change and comes back after a reload of a patch; Clear and "all that match" as before; a picker's choice as before.

**Group S (new, demo): events.** A support host LiveView that forwards every `{:ash_data_table, …}` message to the test process (its pid in the session). Each event of 2.2, its details, scrubbed records on `sensitive_table`'s resource, `notify` lists, no event without `notify`, a nested table's `path`, nothing from a picker, the tag's host receives them too.

**Group T (new, demo): commands.** `refresh` reads once; `put_state` with params the model refuses keeps only what it allows; with `url: true` it patches (`assert_patch`); `clear_selection`; `selected_records` as the person, scrubbed, with `all?`; a command on a tag-only page raises; `status/1`.

**Group U (new): "open".** Demo: the button, the event with the key, a forged key gets nothing. Browser: keyboard to the button and Enter. A new markup snapshot state.

**Group V (new, demo and browser): controlled mode.** `request/1` for a row action's panel and a question; `submit_request` with errors keeps the request with the errors; a stale `ref` is refused; the veto and the re-read apply; a sensitive field's value is nil; attach raises for an action with a file field. Browser: one controlled panel on a support page.

**Group W (new, demo): the router line.** The options of step 7, heard through an `on_mount` hook; a command from that hook.

**Group O2 (changed, step 0b): public API only** (D19 item 5). `AshDataTable.Test`'s portal reading, `DemoWeb.TablePage.query/2` and the snapshot normaliser find a portal's content by the table's own marker. No assertion changes; the snapshots stay identical or the rewrite is reviewed with you first.

**Unchanged on purpose.** Every other test, and the markup snapshots but the new state of group U. Without the new options a table must behave as at `4fe1001`.

## 7. Risks

| Risk | Check |
| --- | --- |
| A host crashes on an event it did not expect | opt-in `notify` (D1); group S "no event without `notify`" |
| A sensitive value in an event or in `selected_records` | `Sensitive.scrub/1` in `Event` (D4); group S on the sensitive resource; mutation check |
| Page values make the table read on every event | D5 a |
| A page sets what only the table may set | D6 a (origin key last), D7 a (private names only), D8 (page arguments not in the form) |
| A veto function that answers wrongly refuses silently | D9 a: it raises |
| Selection out of step between hook and server | D10 a: one truth, the server; D16 ten runs |
| A controlled host bypasses checks | every answer through `Operation` (D14); group V |

## 8. What the owner said that this note keeps

- D-events: one message shape, opt-in; events after success; no command writes.
- D-before: the order of a write; the veto only halts; page values are Ash's own channels; nested tables and pickers get them, told which table asks; reads get them and are not vetoed.
- F1 and "the record in an event": scrubbed; "Show" stays the one way to a sensitive value.
- RQ1: selection on the server, keys as claims. RQ4: commands with `attach` and on the router page; the tag sends events only.
- Q5–Q8, Q18, Q19 as decided; D-nolinks: the table knows no route of the host.
- Controlled mode (2026-10-15): needs `attach`; default uncontrolled; safety in `Operation`.
- Greenfield: `bulk`'s rows, `unselect` and `data-scope` go, not kept beside the new way.

## 9. Done-check

- The three suites green; changed tests only in group R's helper, group O2 and the new snapshot state.
- Every write's `Operation.Input` holds a veto closure and page values from 2b (no default left in `Core.operation/3`, `core.ex:595-598`).
- `grep -rn "ash_data_table:unselect\|data-scope" lib assets` finds nothing.
- `grep -rn "__changed__\|_lv_portal_wrap_\|data-phx-portal" lib demo/test` finds nothing (D19).
- `AshDataTable.Event` and `AshDataTable.Request` documented, with types; `Present` still `@moduledoc false`.
- The dependency test passes; `Event` and `Request` are 2a, `Notify` is 2b.
- Target §9 stage 6 ticked, or the fallback of D17 recorded.
- **The drift check**, as for every stage.

## 10. Where target.md and the code differ

For the drift check and your yes; target.md is not changed by this note.

1. S8 lists `selected_records(socket, table, selection)` and says each command "returns the socket". A command that returns records cannot; with the selection on the server the third argument says nothing (D11).
2. §9 stage 6 and §4.3 say 2b hands `Operation` the veto's *result*. The request needs what `Operation`'s checks find, and the code already passes a function (`operation.ex:82`); 2b must hand a closure (D9).
3. §9 stage 6 adds context "as a new key of `opts`". `opts` already carries `:context` for the table's own origin, set with `Keyword.put`, and the summaries drop it (`query.ex:464-466, 722-723`); the page's context must be merged, not added (D6).
4. §4.4 and stage 4 D14 speak of documented read-only *fields* of `Table`; its moduledoc says what it holds may change (`live/table.ex:9-10`). Functions keep that true (D12).
5. RQ4 and S8 allow commands "on the router page", and S7 `notify` on the router line. The router page runs no host code but the host's `on_mount` hooks; that is how it hears and commands (D1), which target.md does not say.
6. S11 and Q7 say `page_argument` is declared "inside a table's `action`". Create (`create_action`) and inline edits (`update_action`) are options, not `action` entities (`resource/table.ex:26-27`), so they cannot have one (D8).
7. §1.4 says the hook keeps the selected keys at `table_component.ex:7497`, which no longer exists; it is `assets/js/grid/selecting.js` now (and goes in D10).
8. The brief for this note says the veto may "change" an action; target §1.5 and D-before say it only halts. This note follows the owner's decision (D9).

## 11. Public API only (owner's rule, 2026-10-16)

The design relies on no internal of LiveView, Phoenix, Ash or Spark: nothing `@moduledoc false` or `@doc false`, no undocumented field, no private assign. Lib and tests alike.

**What each decision uses.**

| Decision | Public API, with where it is documented |
| --- | --- |
| D1 events | `send/2`; `Phoenix.LiveComponent` moduledoc (`LV lib/phoenix_live_component.ex:324, 426, 492`); `on_mount` and `attach_hook/4` with `:handle_info` (`LV lib/phoenix_live_view.ex:518-542, 1655-1670`) |
| D5 page values | `socket.assigns`, a field of the documented type `Phoenix.LiveView.Socket.t` (`LV lib/phoenix_live_view/socket.ex:77-91`) |
| D6 context | the `context` option of Ash's calls; `Ash.Scope`'s moduledoc: context deep-merged (`Ash lib/ash/scope.ex:45-49`); AshPhoenix passes options on (`AshPhoenix lib/ash_phoenix/form/form.ex:527-530`) |
| D7 private arguments | `private_arguments:` (`Ash lib/ash/changeset/changeset.ex:2036-2039`, `action_input.ex:190`, `ash.ex:462-467`); `Ash.Query.set_argument/3` (`query.ex:2971`); AshPhoenix as above |
| D8 `page_argument` | `Spark.Dsl.Entity` (as every entity of `resource.ex`); `Ash.Resource.Info.action/2` and its arguments' `public?` |
| D9 veto | none of a dependency |
| D10 selection | `push_event/3`, dispatched after the patch (`LV lib/phoenix_live_view.ex:866-874`); `handle_event` through the existing hook |
| D11 commands | `push_patch/2` (`LV lib/phoenix_live_view.ex:1197`); `put_private/3` and `socket.private[key]`, as documented (`:715-733`) |
| D12, D13, D14 | none of a dependency beyond the above; D14's forms are `AshPhoenix.Form.for_*`, `validate/3`, `submit/2` |
| Tests | `Phoenix.LiveViewTest` (`live_isolated/3` with `session:`, `render_hook/3`, `assert_patch/2`); Playwright as today |

**D19. Internals the code uses today.** Found while reading for this note. None is new in stage 6; one is on its path.

| # | Where | The internal | Public way |
| --- | --- | --- | --- |
| 1 | `live/core.ex:562` (`page_assigns/1`) | drops the private assign `__changed__` by name | D5 a: give `socket.assigns` whole (or D5 b) |
| 2 | `parts/grid.ex:186, 588` | calls a column component's `cell/1` and `editor/1` as a function with `__changed__: nil` | render it from HEEx with `apply/3` inside a function component, the pattern LiveView documents as "Dynamic Component Rendering" (`LV lib/phoenix_component.ex:566-600`): LiveView then gives the assigns itself |
| 3 | `parts/panel.ex:877` | the same for a component's editor in the panel | as 2 |
| 4 | `live/page.ex:337-341` (`in_layout/1`) | reads and sets `__changed__` to make the layout render | as 2: a function component that takes the layout's assigns as one attribute and `apply/3`s the layout |
| 5 | `lib/ash_data_table/test.ex:115, 317-322`, `demo/test/support/table_page.ex:1261`, `demo/test/demo_web/markup_snapshot_test.exs:178-212` | read the markup `<.portal>` renders (`data-phx-portal`, the wrapper id `_lv_portal_wrap_…`), which `portal/1`'s docs do not promise (`LV lib/phoenix_component.ex:3603-3610`) | a: the table marks the content of each portal itself (an attribute of its own on the element it draws, naming the target cell); the helpers find that element by the table's own marker and move it, whatever LiveView wraps around it; the snapshots compare the table's elements only. b: wait for `Phoenix.LiveViewTest` to resolve portals (not announced). Recommended: a |

**Recommendation:** item 1 in step 1, where D5 changes that function anyway; items 2–5 in step 0b, before anything new, so that the first new ability is built on public ground. Items 2–4 must keep the markup snapshots identical; item 5 changes the test helpers and the normaliser only (an agreed group, like stage 4's group L). If item 5 a cannot keep a snapshot byte for byte, you are told before the snapshots are rewritten.

## 12. As built

Commits on `main` after `stage6-start`: `310ef07` (step 0: status, target.md), `5fe8e87` (a step 0b leftover: the helpers' portal fixture), `749cf61` (`url: true` without `handle_params/3`), `e336120` (the router page attaches again before an event that waits), `5b4b32a` (`__metadata__` of a keyset record), `25876e2` (step 1), `bb90f95` (step 2), `a150604` and `49f449a` (step 3), `6f55732` (step 4), `fc58e7a` (step 5), `5200783` (step 6), `18a032c` (step 7), `e761b4f` (the perf actions of D18), `23b8e86` and `b6333d0` (two test races the final runs showed).

**The shape.** As sections 1–4, with these details:

- Page values travel in `opts` as `page_values`; every function of 2a reduces them where it calls Ash (`Query.reader_opts/1`, idempotent; `Query.action_opts/3` adds an action's private arguments; `Query.privately/3` sets them on a read before `for_read/4`). `Live.Core.reader/1` adds them for the entry the callback works on (`Live.Core.values/1`), and the key that decides whether to read again leaves them out. `page_assigns/1` gives `socket.assigns` whole.
- The veto is `Live.Core.veto/1`, a closure of the `AshDataTable.Request`; `Operation` fills in what its checks found, the closure the table and path.
- The selection lives in `Live.Core.Selection` (a module of its own beside `Core.Bulk`): `select` from the hook, `ash_data_table:select` from the server, `selected`, `all?` and `selected_under` in the entry. `bulk_seen` stays.
- Controlled mode lives in `Live.Core.Requests`. Questions held: those of row actions, table actions and actions on the selection. A column's question before a save and a reference cell's are not in v1, nor a map cell's panel.
- "Open" is `entry.open_label` (the entry's `open` already holds the expanded rows).

**Not done as written.**

- Steps 1 and 2, and 6 and 7, were built in one working tree; each was committed alone. The browser suite of step 2 ran twice: the first run took up the hook of step 3 half way (the dev server's asset watcher rebuilt the shared bundle; it was stopped for the rest of the stage) and was void. Browser runs then ran from a worktree at the commit under test. From step 5 on, on the owner's order, the browser suite and the gate ran once at the end of the stage, not per step; steps 6 and 7 ran their own test files and the library and demo suites.
- The ten-runs gate ran after step 3 (2424 passed, `picker.spec.ts:593` failed twice) and at the end, where the owner stopped it (2195 passed, the same test failed once, 6 interrupted, 244 not run). Its cause was the test: it used a second cell while the first picker was still closing, and the picker gave the focus back to its own cell (`b6333d0`). No fallback of D17 was taken.
- Tests changed beyond group R's helper: the tests that sent a selection with `bulk`/`bulk_run` or asserted `ash_data_table:bulk`, `ash_data_table:unselect` or `data-scope` (`task_bulk_test`, `bulk_elsewhere_test`, `attach_test`, `argument_line_test`, `live_updates_test`, `intent_test`, `operation_test`) now select first and assert `ash_data_table:select`; thirteen browser checks that selecting sends nothing allow `select` (`frames.besides`). The veto helper of `operation_test` takes the request. Fifteen snapshots lose `data-scope` and nothing else; state 11 is new.

**Performance (D18).** `demo/perf/baseline.mjs` on `/tasks`, `stage6-start` in a worktree and `b6333d0`, back to back on the standard seed, 15 runs each, at the same load: 6.4 and 6.6 at the start of each run (another project's Docker VM held it there, so the times are relative). Median ms, start → end; bytes; Ash reads and statements:

| Action | Median ms | Bytes | Reads, statements |
| --- | --- | --- | --- |
| Cell save | 95.8 → 94.8 (−1 %) | 7,302 → 7,312 | 4, 7 |
| Expanding a row | 33.8 → 21.1 | 3,294 → 3,294 | 0, 0 |
| Opening a nested table | 102.7 → 91.1 | 37,190 → 37,165 | 2, 2 |
| Opening the picker | 107.9 → 123.1 (+14 %) | 31,915 → 31,915 | 2, 4 |
| Cell save in a nested table | 51.9 → 55.2 (+6 %) | 3,484 → 3,494 | 1, 2 |
| Cell save with a nested table open | 114.7 → 79.7 | 6,857 → 7,547 | 4, 7 |
| Selecting a row | 6.1 → 6.1 | 0 → 198 (the `select` round trip) | 0, 0 |
| Page change | 226.3 → 142.0 | 149,601 → 149,779 | 4, 7 |
| Cell save, notified (`/perf/notified`, end only) | 83.2 | 7,312 | 4, 7 |

Times within 20 %, reads and statements the same. A save on a page told every event, with a context function and a veto, costs what a save on `/tasks` does.
