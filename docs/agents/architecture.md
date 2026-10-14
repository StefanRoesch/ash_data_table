# Architecture map

Read this file before a build. It says where things are, so that you do not have to read every guide and the whole table component first. Paths are from the repository root. Line numbers are of the commit that added scrolling sideways and drift: each section says how to get them again.

The words used here (table, column, cell, picker, action panel, …) are defined in `CONTEXT.md`.

## The four parts

The extension has four parts. This is the target structure agreed with the owner; the code is not split this way yet.

| Part | What it is | Where it is today |
| --- | --- | --- |
| 1. Table declaration | The `table` and `tables` blocks of a resource, the `table` block of a domain, and the checks at compile time. | `lib/ash_table/resource.ex`, `lib/ash_table/resource/**`, `lib/ash_table/domain.ex`, `lib/ash_table/domain/**` |
| 2. Table internals | Logic and state, no markup. This part keeps the table safe. | `lib/ash_table/model.ex`, `lib/ash_table/model/**`, `state.ex`, `query.ex`, `record.ex`, `related.ex`, `pick.ex`, `edit.ex`, `act.ex`, `bulk.ex`, `errors.ex`, `format.ex`, `text.ex`, `sensitive.ex`, `notifier.ex`, `listener.ex` (all in `lib/ash_table/`) |
| 3. Table UI components | Markup and the browser hooks. | `render/1`, the function components and the four hooks in `lib/ash_table/live/table_component.ex`; the behaviour `lib/ash_table/component.ex` and the shipped components in `lib/ash_table/components/` |
| 4. Ready-made wiring | The router line, the page and the live component that connect 2 and 3. | `lib/ash_table/router.ex`, `lib/ash_table/routes.ex`, `lib/ash_table/live/page.ex`, `AshTable.table/1` in `lib/ash_table.ex`, and `mount/1`, `update/2`, `handle_event/3`, `handle_async/3` of the table component |

`lib/ash_table/live/table_component.ex` holds parts of 2, 3 and 4 in one file. Splitting it is a planned refactor. Do not start it inside a feature build.

## Module map

One line per module. The functions named are the ones other modules call.

### Part 1: declaration

- `AshTable.Resource` (`resource.ex`): the Spark extension. Defines the entities (`@column`, `@ask`, `@relationship`, `@argument`, `@reference`, `@action`, `@upload`), the sections `@table` and `@tables`, the named table entity `@named_table`, and the list of verifiers at the end.
- `AshTable.Resource.Table` (`resource/table.ex`): one table as written. `options/0` is the option schema that the `table` block and a named table share. `path/1`, `anno/2`, `option_anno/3` find where an error points to. `in_words/1` names the table in a message.
- `AshTable.Resource.Column`, `.Ask`, `.Relationship`, `.Action`, `.Reference`, `.Argument`, `.Upload` (`resource/*.ex`): the structs of the entities, each with `schema/0`.
- `AshTable.Resource.Info` (`resource/info.ex`): read a declaration. `tables/1`, `table/2`, `table!/2`, `no_table/2`; for the default table `columns/1`, `relationships/1`, `actions/1`, `arguments/1`, `uploads/1` and the generated `table_*` functions.
- `AshTable.Domain` and `AshTable.Domain.Info`: the domain's `table` block (`authorize?`, `scope_assign`, `actor_assign`, `tenant_assign`, `pub_sub`). `Info.authorize?/1`, `Info.reader/2`, `Info.assign_names/1`, `Info.pub_sub/1`. Its one verifier, `Domain.Verifiers.VerifyPubSub` (`domain/verifiers/`), reports a domain that names no `pub_sub` and has a resource that says `live? true`.
- `AshTable.Resource.Transformers.Announce` (`resource/transformers/announce.ex`): the extension's one transformer. It gives a resource that says `live? true` the notifier `AshTable.Notifier`.
- `Mix.Tasks.AshTable.Install` (`lib/mix/tasks/ash_table.install.ex`): the Igniter installer.

The rules of a declaration live in one module per topic. Each is shared by the verifiers (which report a mistake) and the model (which builds on the answer). Most return `{:error, reason}` and turn the reason into text with `message/1`.

- `Resource.Reading`: read action, pagination strategy, page sizes, what can be sorted. `read_action/2`, `strategy/2`, `page_sizes/2`, `sortable?/3`, `private_read/2`, `apart/2`.
- `Resource.Editing`: the update action behind a column and whether it can serve an inline edit. `update_action/4`, `edit/4`, `editor/3`, `obstacle/2`.
- `Resource.Acting`: row actions, table actions, create, and their inputs. `offered/2`, `create_action/2`, `inputs/4`, `record_argument/3`, `bulk?/3`.
- `Resource.Arguing`: arguments of the read action and of calculation columns. `inputs/1`, `mistakes/3`, `declared_mistakes/2`.
- `Resource.Relating`: relationships a row offers and the nested table. `offered/2`, `declared/2`, `nested/1`, `read_action/2`, `public_read/2`, `page_sizes/2`.
- `Resource.Referencing`: reference cells, `label_field`, the picker, and `sticky_label?`. `label_field/1`, `sticky_label/2`, `reference/1`, `picking/2`, `declared/4`.
- `Resource.Managing`: arguments that a `manage_relationship` change hands to a relationship. `managed/3`, `handed/3`.
- `Resource.Embedding`: fields of a map cell, kinds of a union. `of/2`, `union/2`, `kind/2`.
- `Resource.Presenting`: the `component` of a column, and how many lines its cells show (`max_lines`). `column/4`, `component/2`, `max_lines/3`.
- `Resource.Uploading`: limits of a file argument. `limits/2`, `mistakes/3`.
- `Resource.Exposing`: columns that show a field a field policy protects. `exposures/2`.
- `Resource.Summarising`: the `summary` of a column (footer summaries). `kinds/0`, `column/2` (an attribute, not sensitive, a kind that fits the type), `action/1` (not a manual read action), `data_layer/2`, `fits?/2`.
- `Resource.Listening`: live updates. `announces?/1` (the resource says `live? true`), `follows?/2` (a table of it listens), `pub_sub/1`. Its findings are reported by the domain's verifier, not by a resource's.

Verifiers (`lib/ash_table/resource/verifiers/`), in the order `resource.ex` lists them: `VerifyTables` (names and duplicates in named tables), `VerifyReadAction`, `VerifyUpdateAction`, `VerifyLabelField` (also `sticky_label?`), `VerifyColumns`, `VerifyComponents`, `VerifyRelationships`, `VerifyActions`, `VerifyUploads`, `VerifyExposure` (warnings only), `VerifySummaries`.

A new diagnostic goes in two places. Put the rule and its `message/1` clause into the topic module above. Raise it from the verifier of that topic as a `Spark.Error.DslError`, with `Table.path/1` and `Table.anno/2` or `Table.option_anno/3` so that it points at the right line. A verifier checks every table of the resource: loop over `AshTable.Resource.Info.tables/1`. Then add it to `documentation/topics/mistakes-at-compile-time.md`.

### Part 2: internals

The model:

- `AshTable.Model` (`model.ex`): everything a table is rendered from, built at runtime from `Ash.Resource.Info` and the declaration (ADR `docs/adr/0001-table-model-from-resource-info-not-manifest.md`). `build/2` builds it for a resource and a table name, the same for everybody. `for_actor/2` takes out the columns and actions this person can never see or use. `defaults/2` and `supply/2` fill in arguments. `bulk_actions/1`, `loads/1`, `relationship/2`, `nested_create/2`, `hideable/1`, `summarised/1` (the columns with a `summary`), `label_column/1`, `humanize/1`. Its `sticky_label?` is the table's option of that name.
- `Model.Column`, `Model.Field`, `Model.Input`, `Model.Action`, `Model.Argument`, `Model.Relationship`, `Model.Pagination`: structs. Each file starts with a comment that explains every key. `Pagination.size/2` is how many records a page holds for the size a person asked for: one of `page_sizes`, else `page_size`.
- `Model.CellType`: Ash type to cell type. `of/2`, `classify/2`.
- `Model.Operator`: filter operators per cell type. `available/2`, `to_ash/2`; `takes/1` (no value, one, several, a range), `predicates/2`, `negated?/1`.
- `Model.Limits`: `min`, `max`, `step` and the text counter. `of/2`, `counted/2`.
- `Model.Access`: what Ash says the person may see and do, before any read. `hidden_fields/4`, `partly_hidden_fields/4`, `forbidden_actions/3`.

State and URL:

- `AshTable.State` (`state.ex`): sort, filters, arguments, page position, chosen page size (`per`). `from_params/2` and `to_params/2` are the URL format. `fit/2` drops what the model does not allow. `cycle_sort/3`, `filter/3`, `pending/2` (what the filter row was sent, an operator without its value among it), `value?/2`, `clear_filter/2`, `clear_filters/1`, `argue/3`, `put_argument/4`, `to_page/2`, `resize/3`.
- `AshTable.Related` (`related.ex`): the URL parameter `of` that limits a table to the records of one row (the full view). `from_params/5`, `to_param/2`, `path/5`.
- `AshTable.Routes` (`routes.ex`): where the host's router mounts a table. `default_id/2`, `table/4`.

Reads:

- `AshTable.Query` (`query.ex`): every read through the table's read action. `read/3` (one page), `read_related/4` (a nested table), `get/5` (one record by key), `matching/3` and `records/3` (a selection), `related_records/5`, `load/3`, `arguments/2`, `rows/4` and `any?/5` (live updates), `summaries/4` (footer summaries: one `Ash.aggregate/3` over everything that matches). Returns `%Query.Page{}`.
- `AshTable.Record` (`record.ex`): the record of one row, read again as the person. `fetch/3`, `key/2`, `load/3`.
- `AshTable.Pick` (`pick.ex`): the record a person chose in the picker. `chosen/3`, `current/3`, `value/2`, `reader/2`.

Live updates:

- `AshTable.Notifier` (`notifier.ex`): the Ash notifier of a resource that says `live? true`. Broadcasts `{:ash_table, resource, action_type, primary_key, tenant}` and nothing else. `topic/2` is the topic of a resource and a tenant.
- `AshTable.Listener` (`listener.ex`): the process through which one table hears. `start/3` subscribes and hands batches (100 ms) to the table with `send_update`; `stop/1`; `flush/1` and `of/1` for tests. It ends with the LiveView.
- `AshTable.Test` (`test.ex`): public help for a host's tests. `flush/1` hands a page what was announced so far.
- In `AshTable.Query`: `rows/4` reads announced keys again as rows are read, `any?/5` asks whether one of them is the person's to see under their filters. `reader_opts/1` passes a table's own listener on as `context` (`origin`), so that the notifier leaves it out.

Writes:

- `AshTable.Edit` (`edit.ex`): save one cell. `save/5`, `refer/5` (reference cell), `clear/4`, `open/5` and `put/7` (map cell in the panel).
- `AshTable.Act` (`act.ex`): row actions, table actions and create, through `AshPhoenix.Form`. `open/5`, `validate/4`, `submit_row/6`, `run/4`; `open_create/4`, `submit_create/6`; `open_generic/4`, `run_generic/4`, `submit_generic/6`; `open_bulk/4`.
- `AshTable.Bulk` (`bulk.ex`): a row action on a selection. `run/5`.
- Files have no module of their own: the limits are in `Resource.Uploading` and the upload handling is in the table component (see "Files" there).

Texts and values:

- `AshTable.Format` (`format.ex`): what a cell shows. `format/2`, `input/2`; `summary/2` for a footer summary.
- `AshTable.Text` (`text.ex`): every text a person reads. `t/2` and `n/3` for the table's own messages, by key; `label/1` for the resource's wording; `error/1` for an action's message.
- `AshTable.Gettext` (`gettext.ex`): the default backend, without translations. The template is `priv/gettext/ash_table.pot`.
- `AshTable.Errors` (`errors.ex`): what an error says to a person and at which field. `of_read/2`, `of_action/3`, `of_form/4`, `at_field/4`.
- `AshTable.Sensitive` (`sensitive.ex`): `sensitive?` fields. `scrub/2` replaces every sensitive value of a record before a row is rendered; `mask/0`, `sensitive?/1`.

### Part 3: UI components

- `AshTable.Component` (`component.ex`): the behaviour of a column's `component` (`cell/1`, `editor/1`, `verify/1`, `commit/0`). `AshTable.Component.Column` is what a component is told about its column.
- `AshTable.Components.Badge`, `.Image`, `.Progress`, `.Slider` (`components/`): the shipped components.
- Everything else of this part is in the table component, below.

### Part 4: wiring

- `AshTable.Router` (`router.ex`): the macro `ash_table/3`. It mounts `AshTable.Live.Page` and puts resource, table name and id into the route.
- `AshTable.Live.Page` (`live/page.ex`): the LiveView behind a router line. Finds actor and tenant in the socket assigns, hands the URL to the table.
- `AshTable.table/1` (`lib/ash_table.ex`): the function component that places a table in a host's LiveView. `AshTable.label/1`.
- `AshTable.NotFoundError`: raised by a mounted table whose read is refused; Phoenix answers 404.

## The table component

`lib/ash_table/live/table_component.ex` is about 10,900 lines. It is a `Phoenix.LiveComponent`. The line ranges below come from this command:

```sh
grep -n '^  def \(mount\|update\|handle_async\|handle_event\|render\)\|ColocatedHook\|// ---- \|^  defp [a-z_?]*(assigns)' lib/ash_table/live/table_component.ex
```

| Lines | What |
| --- | --- |
| 1–324 | Comment: the markup contract (ids, `aria-colindex`, components) and one section per feature. Read the section of the feature you touch. |
| 326–469 | Aliases and `mount/1`. Every assign is set here with a comment. |
| 470–976 | `update/2` and what it calls: `selecting`, `relate`, `build`, `in_words`, `settle`, `read`, `reader`. Its first clause takes what a listener hands over (`live`). |
| 977–1296 | Live updates: `listen`, `listener`, `tidy`, `close`, `follow`, `working`, `refresh`, `leave`, `redetail`, `put_fresh`, `notice`. |
| 1297–1369 | `handle_async/3`: `:read` and `:bulk`. |
| 1370–1783 | Showing a read: `unfilled`, `show`, `not_found`, `item`, `put_row`, `put_failure`, `remove_row`, `announce`. |
| 1784–2515 | `handle_event/3`, all clauses. |
| 2516–2542 | `defoverridable`, and `update/2`, `handle_event/3` and `handle_async/3` once more: each calls the clauses above and ends in `tidy/1`. |
| 2543–4102 | Helpers behind the events: cells (`revealed`, `save`, `refer`), picker and chosen inputs (from 2648), panel (from 2922), bulk (from 3217), `submit` (from 3308), files (from 3474), after a create or a run (from 3736), arguments, `go` and the URL (from 3998). |
| 4103–4720 | `render/1`: the markup of one table. |
| 4721–8115 | The four hooks, inside `render/1`. |
| 8116–10569 | Function components: `lines`, `argument`, `panel`, `picker`, `field`, `group`, `groups`, `union`, `members`, `related`, `selection`, `create`, `table_actions`, `pagination`, `pages`, `resizer`, `columns`, `filter`, `editor`, `count`, `list`. |
| 10570–10899 | Small view helpers: `colindex`, `cell_attributes`, `cell_content`, `cell`, `page_numbers`. |

### Events

All arrive in `handle_event/3`. A name from the browser is looked up as text (`column/2`, `action/2`); it is never turned into an atom.

- Reading: `sort`, `filter`, `clear_filter`, `clear_filters`, `page`, `page_size`.
- Argument line: `arguments`, `argument_add`, `argument_remove`.
- Nested tables: `expand`, `toggle`.
- Cells: `save`, `clear`, `discard`, `dismiss`, `reveal` (sensitive), `edit` (map cell, opens the panel).
- Row actions and create: `act`, `create`.
- Table actions: `table_act`, `table_run`.
- Selection: `bulk`, `bulk_run`, `bulk_seen`.
- Action panel: `panel_validate`, `panel_submit`, `panel_add`, `panel_remove`, `panel_unpick`, `panel_clear`, `panel_cancel`.
- Picker: `pick` (from a cell), `pick_input` (from the panel), `picked`, `picker_cancel`.
- Live updates: `read_again` (the button beside the notice), `left` (the hook's answer to `ash_table:leaving`: no cell of that row is being edited, it can go). No event says which cell is edited: the hook alone knows, and it leaves that cell alone when a live update puts its row back.

`handle_event/3`, `update/2` and `handle_async/3` are each defined twice: the clauses, then `defoverridable`, then one definition that calls them (`super`) and ends in `tidy/1`. A new clause goes above `defoverridable`. `tidy/1` looks at what was announced, forgets the nested tables and pickers that are no longer rendered and stops their listeners, notes in `@tables` whether the table has a panel or picker open, and tells the tables around it that hold a row back for it when it has none any more.

The server tells the hooks with `push_event`: `ash_table:focus`, `ash_table:ask`, `ash_table:bulk`, `ash_table:unselect`, `ash_table:leaving` (a row whose record a live update found gone). The hooks tell each other with DOM events on the grid: `ash_table:selection`, `ash_table:choose`.

### Assigns that matter

- Given by the caller (`update/2`): `id`, `resource`, `table`, `scope`, `actor`, `tenant`, `authorize?`, `live?` (kept as `live_given`), `url`, `label`, `heading`, `mounted?`, `select`, `choose`, `page_assigns`; for a nested table `via`, `parent_key`, `parent_authorize?`, `parent_arguments`, `depth`, `depth_limit`, and for a nested table and a picker `lineage`.
- `live`, `waiting`, `held`, `notice?`: live updates. `live` is the table's listener and topic, nil for a table that does not follow. `leaving` are the rows that go once the hook answers. Every table of a page is also noted in the process dictionary of the LiveView (`@tables`): the ids of the tables around it, its listener, whether a panel or picker is open in it, whether it holds rows back. A table reads it to know what is open under its rows; nothing is told by `send_update`, which would render the table around again.
- `built`: the models as `Model.build/2` gives them, kept for the life of the component. `model`: the model for this person, made on every update.
- `state`: the `%AshTable.State{}`. `read`: what the last read was of; a read runs only when this changes.
- `page`, `row_count`, `busy?`, `loading?`, `error`, `gone?`.
- `rows`: by the key in a row's DOM id, the primary key and row index. An event names a row by that key, and it is looked up here.
- `failed`: edits that failed, by row. `open`: expanded rows.
- `missing`, `fill`, `refused`, `lines`: the argument line.
- `rejected`, `pending`: what the filter row shows beside the filters of the state: a value that was typed and is none, and the operators that were chosen without a value yet (`shown_filter/4`).
- `panel`, `picker`: the open action panel and picker, or nil.
- `selecting`, `bulk`, `lead`, `running`, `result`: selection and its actions. Which rows are selected is known to the hook only.
- `spent`, `running_files`: uploads.
- `summarised?`, `summary`, `summing?`, `summed`, `summary_due`: footer summaries. `summary` holds by column `{:ok, value}` or `:unavailable`; `summary_due` (`:changed` after a read, `:force` after a write or a live batch) is answered in `tidy/1` by `summarise/1`.

### Async reads and the stream

- `start_async(:read, …)` in `read/1`. The first read of a table on the page runs in place, so the first render has rows. Later reads, and every read of a nested table, run async with `busy?` set.
- `start_async(:bulk, …)` in `run_bulk`, which calls `AshTable.Bulk.run/5`.
- `start_async(:summary, …)` in `summarise/1`, which calls `AshTable.Query.summaries/4`: beside the read of the rows, never before them. `read/1`, `put_row`, `remove_row`, `add_row` and `follow` say that it is due (`due/2`); `tidy/1` starts it once. Its answer also runs `redetail/1`, for the page as a LiveView test holds it.
- One stream, `:rows`, configured with `dom_id`. An item is a row (`item/8`) or the detail under an expanded row (`detail`). A new read resets it. `put_row` and `put_detail` insert one item; `remove_row` deletes a row and its detail. The server does not keep the records.

### The four hooks

They are colocated hooks. A host gets them from `phoenix-colocated/ash_table`.

- `.Pagination` (from 4721): keeps focus on the pagination control that was used, the "Rows per page" menu among them. No sections.
- `.Panel` (from 4788): the action panel as a modal dialog. Focus in and back, Escape and Cancel, holding back a form with an unreadable control, adding and removing groups and chosen records (`snapshot`, `into`, `mark`).
- `.Picker` (from 4981): the picker dialog. Hears the selection of the table inside it and sends `picked`.
- `.Grid` (from 5118): everything in the grid. It starts with a long comment and constants (among them `PLACE`, which places the scrollbars at the bottom edge of the window for all grids of a page at once), then `mounted`, `beforeUpdate`, `destroyed`. Its sections are marked `// ---- name ----`:

| Line | Section | Owns |
| --- | --- | --- |
| 5528 | the counter of a text | the count beside a text with `max_length` |
| 5596 | the tree of grids | one tab stop for nested grids, arrow keys, focus, clicks, `onKeydown` |
| 5959 | expanding | opening a row and going into a nested table |
| 6134 | the widths of the columns | resizing; the server never hears of widths |
| 6378 | hiding columns | the "Columns" list; the server never hears of it |
| 6616 | scrolling sideways | each grid is its own scroll area; a style sheet of its own (`pins`) with how wide the area is (`--ash-table-view`, for the nested tables in it) and the cells that stay with `sticky_label?`; `intoView` after a keyboard move; the scrollbar at the bottom edge of the window (`barWanted`, `placeBar`, `toBar`, `fromBar`) |
| after "scrolling sideways" | several values of a filter | the list of "is any of" and "is none of": `openChoices`, `closeChoices` (which applies), `onChoicesKeydown` |
| 6841 | selecting | which rows are selected, `selected()`, `bulk` |
| 7127 | row actions | `act`, the question of an action, refocus |
| 7187 | editing | `startEdit`, `pick`, `editInPanel`, `startList` |
| 7520 | the values of an array | the values of the list editor; then the editor of a component, `commit`, `finish`, `close`, `detach`, `released` (live updates), `save` |
| 7938 | sensitive cells | `reveal`, `hide` |
| 8053 | the dialog | `ask`: the table's question dialog |
| 8074 | the message of a failed cell | `showMessage` |
| after it | the whole text of a cell | the popover `ID-whole` with the text of a cell that cuts some off, on focus and on the pointer: `cutIn`, `seenIn`, `showWhole`, `placeWhole`, `freshWhole`, `hideWhole`; `textFor` (what the hook puts into a cell with `max_lines`) |

A method of the `.Grid` hook has to have a name no other has: the hook is one object, and a second `fit` or `reveal` silently takes the place of the first. esbuild warns of it ("Duplicate key") when the demo's assets are built.

### The footer row

A table with a `summary` on one of its columns has a `<tfoot>` whose first row, `ID-summaries`, holds a `gridcell` per column (`ID-summary-FIELD`); a nested table's pages and its link to the full view are the rows after it. The row is counted in `aria-rowcount`. The hook's style rules for hidden and resized columns cover `tbody` and `tfoot` cells alike (`restyle`), and Page Down and Ctrl+End end at the last record (`onKeydown`). See "Footer summaries" in the comment at the top of the component.

## Safety rules

Every change must keep these. They are what part 2 is for.

- **Read again as the person before any write.** The table keeps keys, not records. Before a save, an action, a reveal or a pick, the record is read again by its key through the table's read action, with the person's actor, tenant and arguments (`AshTable.Record.fetch/3`, `AshTable.Pick.chosen/3`). A record that read does not return is not there.
- **Every action a table runs is `public?`.** Read, update, create, destroy and generic actions, and the read action of a nested table or a picker. The verifiers refuse a private one (`Reading.read_action/2`, `Reading.private_read/2`, `Relating.public_read/2`, `Acting.unusable/4`; the sentence they share is `Reading.private_action/0`).
- **`authorize?`.** Every call to Ash passes the reader options (`scope`, `actor`, `tenant`, `authorize?`; `reader/1` in the component, `Query.reader_opts/1`). `authorize?` comes from the domain unless the table is told otherwise. The table adds no rule of its own and hides nothing by itself: it asks Ash (`Model.Access`).
- **Nothing sensitive reaches the browser before "Show".** A row is rendered from a record that went through `AshTable.Sensitive.scrub/2`. The value is sent only as the reply to `reveal`, after the record was read again. An editor of a sensitive column opens empty.
- **An announcement is a claim too.** A live update names a primary key and nothing else. The table shows only what its own read returns for that key, as the person (`Query.rows/4`), and says that there are new or changed records only after asking, as the person and with their filters, whether one is theirs to see (`Query.any?/5`). The notifier never sends a record.
- **A summary says no more than the rows.** `Query.summaries/4` asks `Ash.aggregate/3` with `authorize_fields?: true` and with the table's read action as each aggregate's `read_action` (Ash would otherwise judge field policies as the primary read action meets them), and asks for nothing over a column that is `partly_hidden?` for the person: its footer cell is a dash. `summary` is refused on a `sensitive?` column.
- **Values from the browser are claims.** A row key, a column name, an action name, a picked record and a selection are looked up or read again before they are used. A page size from a URL or an event is taken only when it is one of the table's `page_sizes` (`State`, and once more where the query is built: `Model.Pagination.size/2`). Sort and filter go through `Ash.Query.sort_input/2` and `Ash.Query.filter_input/2`. What a person typed goes to the action as typed; Ash casts and validates it. Text from outside never becomes an atom.

## Adding a feature

1. **DSL option.** A table option goes into `@options` in `lib/ash_table/resource/table.ex` (one that means something else in a named table also into `@follows` there). A domain option goes into `lib/ash_table/domain.ex`. An option of a column, action or other entity goes into that entity in `lib/ash_table/resource.ex` and its struct in `lib/ash_table/resource/`.
2. **Regenerate**, in the repository root: `mix spark.formatter` (writes `.formatter.exs`) and `mix spark.cheat_sheets` (writes `documentation/dsls/`).
3. **Verifier.** See "A new diagnostic" above.
4. **Model.** Put the answer into `AshTable.Model` or one of its structs. What depends on the person belongs in `for_actor/2`.
5. **Component.** Assign in `mount/1`, event in `handle_event/3`, markup in `render/1` or a function component, browser behaviour in a section of the `.Grid` hook. Add what the markup promises to the comment at the top.
6. **Texts.** Add the key to `@type key` and a `msgid/1` clause in `lib/ash_table/text.ex`. Run `mix gettext.extract` in the root to update `priv/gettext/ash_table.pot`. Add the German text to `demo/priv/gettext/de/LC_MESSAGES/ash_table.po`.
7. **Demo.** Resources are in `demo/lib/demo/tracker/` and `demo/lib/demo/kitchen_sink/`, routes in `demo/lib/demo_web/router.ex`, seeds in `demo/priv/repo/seeds.exs`. A resource that exists for tests only goes into `demo/test/support/*_tables.ex` and under `/support` in the router. Describe a new page in `demo/README.md`.
8. **Tests**, at three boundaries:
   - `test/` in the root: declaration, verifiers, model and the modules of part 2, against the resources in `test/support/`.
   - `demo/test/demo_web/tables/`: the rendered table through LiveView tests, with the helpers of `DemoWeb.TablePage` (`demo/test/support/table_page.ex`). A test that changes a record of a live resource and then looks at an open page calls `AshTable.Test.flush(view)`; it never sleeps for the 100 ms.
   - `demo/e2e/*.spec.ts`: the browser, with the `Table` class of `demo/e2e/support/table.ts` and `demo/e2e/support/actors.ts`.
9. **Guide.** One file in `documentation/topics/`. A new guide is added to the list in `test/documentation_test.exs` and to `extras` in `mix.exs`. Every code block needs `<!-- source: path/from/root -->` on the line above it, or `<!-- sketch -->`. The test checks that the block is in that file, that links resolve, and that a guide ends with its three closing sections.

## Running things

```sh
# root (the library)
mix format --check-formatted
mix compile --force --warnings-as-errors
mix test

# demo (needs Postgres: `docker compose up -d postgres` in the root)
cd demo
mix format --check-formatted
mix compile --force --warnings-as-errors
mix test
MIX_ENV=e2e mix compile --warnings-as-errors
mix phx.server                    # the dev server, http://127.0.0.1:4478

# browser tests
cd demo/e2e
ASDF_NODEJS_VERSION=$(awk '/nodejs/{print $2}' .tool-versions) npm test
```

- `npm test` starts a server and a database per worker (ports 4480 and up) and takes about 9 minutes. `E2E_WORKERS=4 npm test` sets the number of workers.
- Single-server mode, for writing a test: `./server.sh` in `demo/e2e` serves the e2e environment on 4479, and `npm run test:server -- editing` runs against it, one test at a time.
- The Node version is the `nodejs` line of `demo/e2e/.tool-versions`.
- In development the demo has Tidewave, an MCP endpoint into the running app, at `http://127.0.0.1:4478/tidewave/mcp` (see `demo/README.md`).

Known traps:

- A file restored with the same modification time leaves a stale beam. After restoring a file, run `mix compile --force`.
- Never use `pkill -f` or `pgrep -f` with a pattern that matches your own command line. Stop a server by its process id.
- The dev server and the e2e servers write the asset bundle to the same path, `demo/priv/static/assets/`. A browser run rebuilds it.

## Build rules (agreed 2026-10-13)

- Mutation checks only where a missed bug is dangerous: authorization, what is sent to the browser, and what gets written. Not for looks and convenience.
- Each suite runs once: root, demo, browser. A failure that passes on a second run is still looked into.
- A build writes only its own guide section. README, changelog and the other guides are caught up once per milestone.

## Where decisions live

- The specification is issue #21 of `StefanRoesch/ash_table` on GitHub.
- Its comment "Built in the owner's absence" holds every decision since 2026-10-09.
- The glossary is `CONTEXT.md`. Architecture decisions are in `docs/adr/`.
- The other agent documents are in `docs/agents/`.
