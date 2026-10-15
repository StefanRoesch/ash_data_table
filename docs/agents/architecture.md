# Architecture map

Read this file before a build. It says where things are, so that you do not have to read every guide and the whole table component first. Paths are from the repository root. Line numbers are of stage 3a of the refactor (drawing data and intents): each section says how to get them again.

The words used here (table, column, cell, picker, action panel, …) are defined in `CONTEXT.md`.

## The four parts

The extension has four parts. This is the target structure agreed with the owner; `docs/architecture/target.md` describes it, and its section 9 says which stages of the refactor are done. A file's directory says its part (target.md 5.5), and `test/architecture_test.exs` checks the direction of every dependency from it: it prints what breaks the rules and fails from the end of stage 3c.

| Part | What it is | Where it is today |
| --- | --- | --- |
| 1. Table declaration | The `table` and `tables` blocks of a resource, the `table` block of a domain, the checks at compile time, and the notifier of live updates. | `lib/ash_data_table/resource.ex`, `lib/ash_data_table/resource/**`, `lib/ash_data_table/domain.ex`, `lib/ash_data_table/domain/**` |
| 2a. Table internals, data | Logic and state, no markup, no socket. This part keeps the table safe. | `lib/ash_data_table/model.ex`, `lib/ash_data_table/model/**`, and the other files at the top of `lib/ash_data_table/`: `caller.ex` (who asks, `AshDataTable.Caller`), `state.ex`, `query.ex`, `record.ex`, `related.ex`, `routes.ex`, `pick.ex`, `edit.ex`, `act.ex`, `bulk.ex`, `errors.ex`, `sensitive.ex`, `zone.ex`, `present.ex` (what a part draws), `intent.ex` (what an event asks for) |
| 2b. Table internals, live | The core over a LiveView socket. | `lib/ash_data_table/live/**` but the page: `listener.ex`, `table.ex` and `entry.ex` (the state of a table), and `mount/1`, `update/2`, `handle_event/3`, `handle_async/3` and their helpers in `live/table_component.ex` |
| 3. Table UI components | Markup and the browser hooks. | `lib/ash_data_table/parts/*.ex` (`AshDataTable.Parts.*`), the four hooks in `assets/js/` (JS files of the package; the table component imports them), the behaviour `lib/ash_data_table/component.ex` and the shipped components in `lib/ash_data_table/components/` |
| 3w. The words | What turns values and messages into text. | `text.ex`, `format.ex`, `gettext.ex` in `lib/ash_data_table/` |
| 4. Ready-made wiring | The router line, the page and the live component that connect 2 and 3. | `lib/ash_data_table/router.ex`, `lib/ash_data_table/live/page.ex`, `AshDataTable.table/1` in `lib/ash_data_table.ex`, `not_found_error.ex`, and `render/1` of the table component, which composes the parts |

`lib/ash_data_table/live/table_component.ex` still holds 2b and the composition of the parts in one file, and imports the hooks. The stages of the refactor take it apart further; do not start one inside a feature build.

## Module map

One line per module. The functions named are the ones other modules call.

### Part 1: declaration

- `AshDataTable.Resource` (`resource.ex`): the Spark extension. Defines the entities (`@column`, `@ask`, `@relationship`, `@argument`, `@reference`, `@action`, `@upload`), the sections `@table` and `@tables`, the named table entity `@named_table`, and the list of verifiers at the end.
- `AshDataTable.Resource.Table` (`resource/table.ex`): one table as written. `options/0` is the option schema that the `table` block and a named table share. `path/1`, `anno/2`, `option_anno/3` find where an error points to. `in_words/1` names the table in a message.
- `AshDataTable.Resource.Column`, `.Ask`, `.Relationship`, `.Action`, `.Reference`, `.Argument`, `.Upload` (`resource/*.ex`): the structs of the entities, each with `schema/0`.
- `AshDataTable.Resource.Info` (`resource/info.ex`): read a declaration. `tables/1`, `table/2`, `table!/2`, `no_table/2`; for the default table `columns/1`, `relationships/1`, `actions/1`, `arguments/1`, `uploads/1` and the generated `table_*` functions.
- `AshDataTable.Domain` and `AshDataTable.Domain.Info`: the domain's `table` block (`authorize?`, `scope_assign`, `actor_assign`, `tenant_assign`, `time_zone_assign`, `pub_sub`). `Info.authorize?/1`, `Info.reader/2`, `Info.assign_names/1`, `Info.time_zone/2`, `Info.time_zone_assign/1`, `Info.pub_sub/1`. Its one verifier, `Domain.Verifiers.VerifyPubSub` (`domain/verifiers/`), reports a domain that names no `pub_sub` and has a resource that says `live? true`.
- `AshDataTable.Resource.Transformers.Announce` (`resource/transformers/announce.ex`): the extension's one transformer. It gives a resource that says `live? true` the notifier `AshDataTable.Resource.Notifier`, named as an atom.
- `AshDataTable.Resource.Notifier` (`resource/notifier.ex`): the notifier of live updates (see "Live updates" below). `AshDataTable.Notifier` (`notifier.ex`) keeps only `topic/2`, as a facade for the tests, until they may ask the declaration.
- `AshDataTable.Resource.CellType` (`resource/cell_type.ex`): Ash type to cell type. `of/2`, `classify/2`.
- `AshDataTable.Resource.Operator` (`resource/operator.ex`): filter operators per cell type. `available/2`, `to_ash/2`; `takes/1` (no value, one, several, a range), `predicates/2`, `negated?/1`. `AshDataTable.Model.Operator` is a facade of it for the tests.
- `AshDataTable.Resource.Words` (`resource/words.ex`): `humanize/1`, a name in words.
- `Mix.Tasks.AshDataTable.Install` (`lib/mix/tasks/ash_data_table.install.ex`): the Igniter installer.

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
- `Resource.Exposing`: columns that show a field a field policy protects. `exposures/2`. Also whether a field is `sensitive?`: `sensitive?/1`, `typed?/1`, `empty?/1`.
- `Resource.Summarising`: the `summary` of a column (footer summaries). `kinds/0`, `column/2` (an attribute, not sensitive, a kind that fits the type), `action/1` (not a manual read action), `data_layer/2`, `fits?/2`.
- `Resource.Listening`: live updates. `announces?/1` (the resource says `live? true`), `follows?/2` (a table of it listens), `pub_sub/1`. Its findings are reported by the domain's verifier, not by a resource's.

Verifiers (`lib/ash_data_table/resource/verifiers/`), in the order `resource.ex` lists them: `VerifyTables` (names and duplicates in named tables), `VerifyReadAction`, `VerifyUpdateAction`, `VerifyLabelField` (also `sticky_label?`), `VerifyColumns`, `VerifyComponents`, `VerifyRelationships`, `VerifyActions`, `VerifyUploads`, `VerifyExposure` (warnings only), `VerifySummaries`.

A new diagnostic goes in two places. Put the rule and its `message/1` clause into the topic module above. Raise it from the verifier of that topic as a `Spark.Error.DslError`, with `Table.path/1` and `Table.anno/2` or `Table.option_anno/3` so that it points at the right line. A verifier checks every table of the resource: loop over `AshDataTable.Resource.Info.tables/1`. Then add it to `documentation/topics/mistakes-at-compile-time.md`.

### Part 2: internals

The model (2a):

- `AshDataTable.Model` (`model.ex`): everything a table is rendered from, built at runtime from `Ash.Resource.Info` and the declaration (ADR `docs/adr/0001-table-model-from-resource-info-not-manifest.md`). `build/2` builds it for a resource and a table name, the same for everybody. `for_actor/2` takes out the columns and actions this person can never see or use. `defaults/2` and `supply/2` fill in arguments. `bulk_actions/1`, `loads/1`, `relationship/2`, `nested_create/2`, `summarised/1` (the columns with a `summary`), `label_column/1`, `keeps_one?/1`, `label/1` (what a resource's table is called, before it is translated). `group?/1` (a column or input edited as groups of fields, or a union). `hideable/1` is a copy of `Parts.Grid.hideable/1` for the tests, without a call into part 3, until they may ask the part. Its `sticky_label?` is the table's option of that name. `zoned/2` puts the page's time zone into the model (`time_zone`) and its arguments.
- `Model.Column`, `Model.Field`, `Model.Input`, `Model.Action`, `Model.Argument`, `Model.Relationship`, `Model.Pagination`: structs. Each file starts with a comment that explains every key. `Pagination.size/2` is how many records a page holds for the size a person asked for: one of `page_sizes`, else `page_size`. `Field.from/1` makes fields of what `Resource.Embedding` gives, which are maps. `Column.value/2` is what a record holds for a column. `Argument.argument_id/1` is what an argument is called in the page, `Argument.shown/3` what its input shows.
- `Model.Limits`: `min`, `max`, `step` and the text counter. `of/2`, `counted/2`.
- `Model.Access`: what Ash says the person may see and do, before any read. `hidden_fields/4`, `partly_hidden_fields/4`, `forbidden_actions/3`.

State and URL:

- `AshDataTable.Caller` (`caller.ex`, 2a): who is asking and what the page adds: `scope`, `actor`, `tenant`, `authorize?` (as told, else the domain's) and `time_zone`. No assigns. `new/1`; `reader_opts/1` is the keyword list the functions of 2a take as `opts` (`actor`, `authorize?`, `scope`, `tenant`); the table component's `reader/1` puts its listener (`origin`) in front.
- `AshDataTable.State` (`state.ex`): sort, filters, arguments, page position, chosen page size (`per`). `from_params/2` and `to_params/2` are the URL format. `fit/2` drops what the model does not allow. `cycle_sort/3`, `filter/3`, `pending/2` (what the filter row was sent, an operator without its value among it), `value?/2`, `clear_filter/2`, `clear_filters/1`, `argue/3`, `put_argument/4`, `to_page/2`, `resize/3`.
- `AshDataTable.Related` (`related.ex`): the URL parameter `of` that limits a table to the records of one row (the full view). `from_params/5`, `to_param/2`, `path/5`.
- `AshDataTable.Routes` (`routes.ex`): where the host's router mounts a table. `default_id/2`, `table/4`.

Reads:

- `AshDataTable.Query` (`query.ex`): every read through the table's read action. `read/3` (one page), `read_related/4` (a nested table), `get/5` (one record by key), `matching/3` and `records/3` (a selection), `related_records/5`, `load/3`, `arguments/2`, `rows/4` and `any?/5` (live updates), `summaries/4` (footer summaries: one `Ash.aggregate/3` over everything that matches). Returns `%Query.Page{}`.
- `AshDataTable.Record` (`record.ex`): the record of one row, read again as the person. `fetch/3`, `key/2`, `load/3`.
- `AshDataTable.Pick` (`pick.ex`): the record a person chose in the picker. `chosen/3`, `current/3`, `value/2`, `reader/2`.

The state of a table (2b):

- `AshDataTable.Table` (`live/table.ex`): the one value a table is held in, the assign `table` of the table component: `options` (what it was told about how it is placed: `url`, `label`, `heading`, `mounted?`, `page_assigns`, `select`, `live_given`, `authorize_given`, `labelledby`, `lineage`), `caller` and `entry`. `new/0`; `put/2` puts fields where each lives and raises on a name none has. The process dictionary `@tables` stays beside it until stage 5.
- `AshDataTable.Live.Entry` (`live/entry.ex`): one table: everything else it holds, each field with its comment (see "The state of a table" below). `selected` is empty until stage 6. `new/0`.

Live updates:

- `AshDataTable.Resource.Notifier` (`resource/notifier.ex`, part 1): the Ash notifier of a resource that says `live? true`. Broadcasts `{:ash_data_table_changed, resource, action_type, primary_key, tenant}` and nothing else. `topic/2` is the topic of a resource and a tenant.
- `AshDataTable.Listener` (`live/listener.ex`, 2b): the process through which one table hears. `start/3` subscribes and hands batches (100 ms) to the table with `send_update`; `stop/1`; `flush/1` and `of/1` for tests. It ends with the LiveView.
- `AshDataTable.Test` (`test.ex`): public help for a host's tests. `flush/1` hands a page what was announced so far.
- In `AshDataTable.Query`: `rows/4` reads announced keys again as rows are read, `any?/5` asks whether one of them is the person's to see under their filters. `reader_opts/1` passes a table's own listener on as `context` (`origin`), so that the notifier leaves it out.

Writes:

- `AshDataTable.Edit` (`edit.ex`): save one cell. `save/5`, `refer/5` (reference cell), `clear/4`, `open/5` and `put/7` (map cell in the panel).
- `AshDataTable.Act` (`act.ex`): row actions, table actions and create, through `AshPhoenix.Form`. `open/5`, `validate/4`, `submit_row/6`, `run/4`; `open_create/4`, `submit_create/6`; `open_generic/4`, `run_generic/4`, `submit_generic/6`; `open_bulk/4`.
- `AshDataTable.Bulk` (`bulk.ex`): a row action on a selection. `run/5`.
- Files have no module of their own: the limits are in `Resource.Uploading` and the upload handling is in the table component (see "Files" there).

Texts and values:

- `AshDataTable.Format` (`format.ex`, 3w): what a cell shows. `format/3`, `input/3` (with the page's zone; `/2` is UTC); `summary/3` for a footer summary.
- `AshDataTable.Zone` (`zone.ex`): the time zone of the page. `check/1`, `check!/2` (the zone a page gives), `local/2` (shown), `zoned?/1` (a type whose values are instants), `given/3` (what a write is given for a wall time typed there: the UTC instant), `gaps/3` (wall times the zone skips), `read/3` (the same for a filter or an argument). Used by `Format`, `Edit.save/5`, `Act` (`taken`, `gaps/3`), `Model.supply/2`, `Query` (filters).
- `AshDataTable.Text` (`text.ex`, 3w): every text a person reads. `t/2` and `n/3` for the table's own messages, by key; `label/1` for the resource's wording; `error/1` for an action's message.
- `AshDataTable.Gettext` (`gettext.ex`): the default backend, without translations. The template is `priv/gettext/ash_data_table.pot`.
- `AshDataTable.Errors` (`errors.ex`): what an error says to a person and at which field. `of_read/2`, `of_action/3`, `of_form/4`, `at_field/4`.
- `AshDataTable.Sensitive` (`sensitive.ex`): `sensitive?` fields. `scrub/2` replaces every sensitive value of a record before a row is rendered; `mask/0`. Whether a field is sensitive is `Resource.Exposing.sensitive?/1`.

Drawing data and intents (2a, stage 3a):

- `AshDataTable.Present` (`present.ex`): what a part draws, made of what the core holds; a part is never given a record, an `AshPhoenix.Form` or a changeset. Values, not texts: a part formats a value with `Format`; the texts the core makes (titles, messages) are passed on as they are until stage 3b. `row/3` gives a `Present.Row` for the stream (the record scrubbed first with `Sensitive.scrub/2`; a `Present.Cell` per column with `state` `:value`, `:empty`, `:masked` or `:forbidden`, `value` only for `:value`, `editable?`, and `failure`, whose `typed` is `""` for a sensitive cell). `panel/2` gives a `Present.Panel` with a `Present.Field` per input (`form_name`, `value`, shown `errors`, `places`, `chosen`, `clear`; a sensitive field holds only what was typed in this panel). `picker/1` gives a `Present.Picker`. `label/3` is what a record is called, as a value with its column (scrubbed), which `chosen` holds. `field_value/4`, `in_union?/2`. It calls `Format.input/3` for the text of a control until `Typed` takes it (stage 3b, D4): one finding of the dependency test.
- `AshDataTable.Intent` (`intent.ex`): `parse(event, params)` gives `{:ok, intent}` (one tagged value per event, see "Events" below) or `:malformed`. It checks the shape only; names stay text, every value stays a claim, nothing is looked up.

### Part 3: UI components

- `AshDataTable.Component` (`component.ex`): the behaviour of a column's `component` (`cell/1`, `editor/1`, `verify/1`, `commit/0`). `AshDataTable.Component.Column` is what a component is told about its column. `shown_as/1` (`@doc false`) is a cell type in words, for the shipped components.
- `AshDataTable.Components.Badge`, `.Image`, `.Progress`, `.Slider` (`components/`): the shipped components.
- `AshDataTable.Parts.*` (`parts/`): the markup of the table, function components that draw from the table's entry and options, which `render/1` of the table component passes to each as attributes (`model={@table.entry.model}`). A part is never given the whole `@table`: it holds the caller. The rows of the grid, the action panel and the picker are drawn from what `AshDataTable.Present` gives (`panel={Present.panel(@table.entry.panel, …)}`, `picker={Present.picker(@table.entry.picker)}`; the rows come through the stream). Per part: its public functions, then the function components it keeps to itself:

| Module | What it draws | Functions |
| --- | --- | --- |
| `Parts.Heading` | The line of the table's name, create, table actions | `heading/1`; `create`, `table_actions` |
| `Parts.Related` | What a table limited to related records says above its grid; the lines under an expanded row and the nested table in each; the link to the full view | `related/1`, `lines/1`, `full_view/1`, `full_view?/2` |
| `Parts.Arguments` | The argument line | `argument_line/1`; `argument` |
| `Parts.Filter` | The filter row's form; one column's filter, "is any of" | `filter_form/1`, `filter/1`, `shown_filter/4`; `choices` |
| `Parts.Selection` | The line above the grid: selection, notice, "Clear filters", "Columns" | `selection_line/1`; `selection` |
| `Parts.Grid` | The grid: header, filter row, rows and cells (from `Present.Row`), footer, editor templates, the scrollbar; "Columns"; the view helpers | `grid/1`, `columns/1`, `hideable/1`, `first_row/1`, `held/1`; `resizer`, `editor`; the helpers of a cell (`cell_attributes`, `cell_content`, `shown`, `cell`) |
| `Parts.Summary` | The footer row of summaries | `summaries/1`; `summary` |
| `Parts.Pagination` | Pages, "Rows per page" | `pagination/1`, `pages?/2`; `pages` |
| `Parts.Panel` | The action panel (from `Present.Panel`), its fields, groups, unions, chosen records (it formats their label values); the upload of each file field, from the `files` the component gives it | `panel/1`; `field`, `group`, `groups`, `union`, `members`, `field_editor`, `called` |
| `Parts.Picker` | The picker dialog (from `Present.Picker`) | `picker/1` |
| `Parts.Messages` | The live region and a run's result, the notice of changes, the failure template, the whole-text popover, the question dialog, error, loading, fill and "No records" | `status/1`, `notice/1`, `failure/1`, `whole/1`, `dialog/1`, `messages/1` |
| `Parts.Editors` | The counter of a text, the list editor; the edge and type of a control | `count/1`, `list/1`, `described/1`, `control_edge/0`, `box_edge/0`, `input_type/1`, `input_step/1` |
| `Parts.Common` | Nothing of its own: the helpers several parts draw with. A leaf, so that the parts call each other in no circle | `failure_message/2`, `colindex/2`, `trail/1`, `summary_rowindex/1`, `header_rows/0` |

The table component's code calls few of these: `first_row/1` and `header_rows/0` (geometry, until `Attrs`). What its events and the markup both mean is in part 2a (`Model.group?/1`, `Model.Column.value/2`, `Model.Argument.argument_id/1` and `shown/3`). The upload helpers (`upload_name/2`, `upload_of/3`, `upload_errors_of/1`, `file_errors/3`, `entry/1`, `entry_ref/1`) are the component's own, beside `said_of/4`; `panel_files/1` gives the panel what they say. A part never calls the table component; the live component of a nested table or a picker is given to it as `component`.

The pieces that were `render/1` keep the indentation they had there, held by `phx-no-format` on their outermost elements: the text in an element keeps its whitespace, and the markup snapshots compare it byte for byte. Do not take the attribute away or reindent them.

- The four hooks are JS files in `assets/js/` ("The four hooks", below). The table component keeps one colocated hook per hook, which imports it, so a part names one in full (`phx-hook="AshDataTable.Live.TableComponent.Grid"`), as the component's `.Grid` renders.

### Part 4: wiring

- `AshDataTable.Router` (`router.ex`): the macro `ash_data_table/3`. It mounts `AshDataTable.Live.Page` and puts resource, table name and id into the route.
- `AshDataTable.Live.Page` (`live/page.ex`): the LiveView behind a router line. Finds actor and tenant in the socket assigns, hands the URL to the table.
- `AshDataTable.table/1` (`lib/ash_data_table.ex`): the function component that places a table in a host's LiveView. `AshDataTable.label/1` (`Model.label/1`, translated).
- `AshDataTable.NotFoundError`: raised by a mounted table whose read is refused; Phoenix answers 404.

## The table component

`lib/ash_data_table/live/table_component.ex` is about 4,700 lines. It is a `Phoenix.LiveComponent`. Its markup is in `AshDataTable.Parts` (part 3, above); `render/1` composes the parts and ends with the four colocated hooks, each an import of `assets/js/`. The line ranges below come from this command:

```sh
grep -n '^  def \(mount\|update\|handle_async\|handle_event\|render\)\|ColocatedHook\|// ---- \|^  defp [a-z_?]*(assigns)' lib/ash_data_table/live/table_component.ex
```

| Lines | What |
| --- | --- |
| 1–518 | Comment: the markup contract (ids, `aria-colindex`, components) and one section per feature. Read the section of the feature you touch. |
| 519–555 | `use`, aliases, `@tables`. |
| 556–575 | `mount/1`, which assigns `table: Table.new()`, and `put/2`, which every change of the table goes through. |
| 576–1208 | `update/2` and what it calls: `selecting`, `relate`, `build`, `in_words`, `settle`, `read`, footer summaries, `reader`. Its first clause takes what a listener hands over (`live`). |
| 1209–1529 | Live updates: `listen`, `listener`, `tidy`, `close`, `follow`, `working`, `refresh`, `leave`, `redetail`, `put_fresh`, `notice`. |
| 1530–1614 | `handle_async/3`: `:read`, `:summary` and `:bulk`. |
| 1615–2039 | Showing a read: `unfilled`, `show`, `not_found`, `put_row` (rows through `Present.row/3`), `put_failure`, `remove_row`, `announce`, `title_of`, `label`. |
| 2040–2794 | `handle_event/3`: `Intent.parse/2`, then one `on/2` clause per intent; `malformed/2`, the answer to a payload of another shape. |
| 2795–2823 | `defoverridable`, and `update/2`, `handle_event/3` and `handle_async/3` once more: each calls the clauses above and ends in `tidy/1`. |
| 2824–4457 | Helpers behind the events: cells (`revealed`, `save`, `refer`), picker and chosen inputs (from 2934), panel (from 3201), bulk (from 3528), `submit` (from 3639), files (from 3831), after a create or a run (from 4093), arguments (from 4351), `go` and the URL (from 4417). |
| 4458–4636 | `render/1`: the parts of one table, in their order; at the end the four colocated hooks (from 4613), four lines each, which import the hooks of `assets/js/`. |
| 4637–4685 | What a picker and a nested table are given (`picker_reader`, `nested_reader`), and `lead/2`. |

### Events

All arrive in `handle_event/3`, which parses each once with `AshDataTable.Intent.parse/2` and hands the intent to `on/2` (`{:sort, column}`, `{:save, row, column, typed}`, `{:bulk, action, selection}`, …). A payload of another shape gets the answer `malformed/2` gives for that event, the one the table always gave it (`{ok: false}`, `{open: false}`, `{}` or none); an event the table does not know has no clause. A name from the browser is looked up as text (`column/2`, `action/2`); it is never turned into an atom.

- Reading: `sort`, `filter`, `clear_filter`, `clear_filters`, `page`, `page_size`.
- Argument line: `arguments`, `argument_add`, `argument_remove`.
- Nested tables: `expand`, `toggle`.
- Cells: `save`, `clear`, `discard`, `dismiss`, `reveal` (sensitive), `edit` (map cell, opens the panel).
- Row actions and create: `act`, `create`.
- Table actions: `table_act`, `table_run`.
- Selection: `bulk`, `bulk_run`, `bulk_seen`.
- Action panel: `panel_validate`, `panel_submit`, `panel_add`, `panel_remove`, `panel_unpick`, `panel_clear`, `panel_cancel`.
- Picker: `pick` (from a cell), `pick_input` (from the panel), `picked`, `picker_cancel`.
- Live updates: `read_again` (the button beside the notice), `left` (the hook's answer to `ash_data_table:leaving`: no cell of that row is being edited, it can go). No event says which cell is edited: the hook alone knows, and it leaves that cell alone when a live update puts its row back.

`handle_event/3`, `update/2` and `handle_async/3` are each defined twice: the clauses, then `defoverridable`, then one definition that calls them (`super`) and ends in `tidy/1`. A new event is a clause of `Intent.parse/2`, an `on/2` clause above `defoverridable`, and its name in `malformed/2`. `tidy/1` looks at what was announced, forgets the nested tables and pickers that are no longer rendered and stops their listeners, notes in `@tables` whether the table has a panel or picker open, and tells the tables around it that hold a row back for it when it has none any more.

Each event's payload and answer are listed in "Events" in the comment at the top of the component. The server tells the hooks with `push_event`: `ash_data_table:focus`, `ash_data_table:ask`, `ash_data_table:bulk`, `ash_data_table:unselect`, `ash_data_table:leaving` (a row whose record a live update found gone). The hooks tell each other with DOM events on the grid: `ash_data_table:selection`, `ash_data_table:choose`.

### The state of a table

The component has one assign of its own, `table` (`AshDataTable.Table`), beside LiveView's (`myself`, `streams`, `uploads`). Code reads `socket.assigns.table.entry.model` (or `.options.url`, `.caller.time_zone`) and changes it with `put(socket, field: value)`; a function head matches `%{assigns: %{table: %{entry: %{panel: %{} = panel}}}}`. `render/1` passes each part the fields it draws from, one attribute each, so LiveView's change tracking compares each field on its own: a change of one field renders again only what uses it (measured in stage 2: the bytes per action of `demo/perf/baseline.mjs` did not change). What lives where:

- Given by the caller (`update/2`): `id`, `resource`, `table`, `scope`, `actor`, `tenant`, `authorize?`, `live?` (kept as `live_given`), `url`, `label`, `heading`, `mounted?`, `select`, `choose`, `page_assigns`, `time_zone` (checked, nil is `"Etc/UTC"`; passed on to nested tables and pickers, and kept in an open panel); for a nested table `via`, `parent_key`, `parent_authorize?`, `parent_arguments`, `depth`, `depth_limit`, and for a nested table and a picker `lineage`. `scope`, `actor`, `tenant`, `authorize?` and `time_zone` go into `caller`; `url`, `label`, `heading`, `mounted?`, `page_assigns`, `select`, `live_given`, `authorize_given`, `labelledby` and `lineage` into `options`; everything else, here and below, is a field of `entry`.
- `live`, `waiting`, `held`, `notice?`: live updates. `live` is the table's listener and topic, nil for a table that does not follow. `leaving` are the rows that go once the hook answers. Every table of a page is also noted in the process dictionary of the LiveView (`@tables`): the ids of the tables around it, its listener, whether a panel or picker is open in it, whether it holds rows back. A table reads it to know what is open under its rows; nothing is told by `send_update`, which would render the table around again.
- `built`: the models as `Model.build/2` gives them, kept for the life of the component. `model`: the model for this person, made on every update.
- `state`: the `%AshDataTable.State{}`. `read`: what the last read was of; a read runs only when this changes.
- `page`, `row_count`, `busy?`, `loading?`, `error`, `gone?`.
- `rows`: by the key in a row's DOM id, the primary key and row index. An event names a row by that key, and it is looked up here.
- `failed`: edits that failed, by row. `open`: expanded rows.
- `missing`, `fill`, `refused`, `lines`: the argument line.
- `rejected`, `pending`: what the filter row shows beside the filters of the state: a value that was typed and is none, and the operators that were chosen without a value yet (`shown_filter/4`).
- `panel`, `picker`: the open action panel and picker, or nil.
- `selecting`, `bulk`, `lead`, `running`, `result`: selection and its actions. Which rows are selected is known to the hook only; `selected` is there for their keys and stays empty until stage 6.
- `spent`, `running_files`: uploads.
- `summarised?`, `summary`, `summing?`, `summed`, `summary_due`: footer summaries. `summary` holds by column `{:ok, value}` or `:unavailable`; `summary_due` (`:changed` after a read, `:force` after a write or a live batch) is answered in `tidy/1` by `summarise/1`.

### Async reads and the stream

- `start_async(:read, …)` in `read/1`. The first read of a table on the page runs in place, so the first render has rows. Later reads, and every read of a nested table, run async with `busy?` set.
- `start_async(:bulk, …)` in `run_bulk`, which calls `AshDataTable.Bulk.run/5`.
- `start_async(:summary, …)` in `summarise/1`, which calls `AshDataTable.Query.summaries/4`: beside the read of the rows, never before them. `read/1`, `put_row`, `remove_row`, `add_row` and `follow` say that it is due (`due/2`); `tidy/1` starts it once. Its answer also runs `redetail/1`, for the page as a LiveView test holds it.
- One stream, `:rows`, configured with `dom_id`. An item is a row (`Present.row/3`, a `Present.Row`) or the detail under an expanded row (`detail`, a map with `detail?`). A new read resets it. `put_row` and `put_detail` insert one item; `remove_row` deletes a row and its detail. The server does not keep the records.

### The four hooks

They are JS files of the package, in `assets/js/`. The table component keeps four colocated hooks of four lines, `import {Grid} from "../node_modules/js/index.js"` and the like, so the rendered names stay and a LiveView host gets them from `phoenix-colocated/ash_data_table` and sets up nothing more. The path works because `mix.exs` sets `phoenix_live_view: [colocated_assets: [node_modules_path: "assets"]]`: LiveView puts a link named `node_modules` beside the extracted hooks, in `_build/ENV/phoenix-colocated/ash_data_table/`, and points it at the package's `assets/`, wherever the package is (the parent directory for the demo, `deps/` in a host).

- `assets/js/index.js`: the four hooks as LiveView hooks (`Grid`, `Pagination`, `Panel`, `Picker`) and `hooks`, the same by the names the table renders. `package.json` in the root names it, for a custom build or another UI technology (`import {hooks} from "ash_data_table"`, from `deps/`).
- `assets/js/transport/live_view.js`: the transport (target.md S20). A hook never calls LiveView: it has `this.transport`, with `push(event, payload)` (a Promise of the reply; a push that fails gives a Promise that never settles, so no reply handler runs), `on(event, handler)` and `off(event)`. `hook(behaviour)` gives a hook its transport before `mounted`. Internal.
- `assets/js/markers.js`: the marker names that several modules use (`GRID`, `HANDLE`). The other selectors are still written where they are used (stage 7 moves them).
- `assets/js/pagination.js` (`.Pagination`): keeps focus on the pagination control that was used, the "Rows per page" menu among them.
- `assets/js/panel.js` (`.Panel`): the action panel as a modal dialog. Focus in and back, Escape and Cancel, holding back a form with an unreadable control, adding and removing groups and chosen records (`snapshot`, `into`, `mark`).
- `assets/js/picker.js` (`.Picker`): the picker dialog. Hears the selection of the table inside it and sends `picked`.
- `assets/js/grid/` (`.Grid`): everything in the grid. `index.js` starts with a long comment, then `mounted`, `beforeUpdate`, `updated`, `destroyed`, and puts the hook together from the modules below into one object. `shared.js` holds the constants and helpers that need no hook, `PLACE` (which places the scrollbars at the bottom edge of the window for all grids of a page at once) and `page.tabbing`. One module per section:

| Module | Section | Owns |
| --- | --- | --- |
| `counter.js` | the counter of a text | the count beside a text with `max_length` |
| `tree.js` | the tree of grids | one tab stop for nested grids, arrow keys, focus, clicks, `onKeydown` |
| `expanding.js` | expanding | opening a row and going into a nested table |
| `widths.js` | the widths of the columns | resizing; the server never hears of widths |
| `hiding.js` | hiding columns | the "Columns" list; the server never hears of it |
| `scrolling.js` | scrolling sideways | each grid is its own scroll area; a style sheet of its own (`pins`) with how wide the area is (`--ash-data-table-view`, for the nested tables in it) and the cells that stay with `sticky_label?`; `intoView` after a keyboard move; the scrollbar at the bottom edge of the window (`barWanted`, `placeBar`, `toBar`, `fromBar`) |
| `choices.js` | several values of a filter | the list of "is any of" and "is none of": `openChoices`, `closeChoices` (which applies), `onChoicesKeydown` |
| `selecting.js` | selecting | which rows are selected, `selected()`, `bulk` |
| `actions.js` | row actions | `act`, the question of an action, refocus |
| `editing.js` | editing | `startEdit`, `pick`, `editInPanel`, `startList` |
| `arrays.js` | the values of an array | the values of the list editor; then the editor of a component, `commit`, `finish`, `close`, `detach`, `released` (live updates), `save` |
| `sensitive.js` | sensitive cells | `reveal`, `hide` |
| `dialog.js` | the dialog | `ask`: the table's question dialog |
| `failure.js` | the message of a failed cell | `showMessage` |
| `whole_text.js` | the whole text of a cell | the popover `ID-whole` with the text of a cell that cuts some off, on focus and on the pointer: `cutIn`, `seenIn`, `showWhole`, `placeWhole`, `freshWhole`, `hideWhole`; `textFor` (what the hook puts into a cell with `max_lines`) |

The methods of all these modules are one object and share its state through `this` (set in `mounted`). A method needs a name no other has: `grid/index.js` throws when two modules name one alike, and esbuild warns of two in one module ("Duplicate key") when the demo's assets are built.

`npm run check` in the root (with the Node version of `demo/e2e/.tool-versions`, after `npm install`) runs TypeScript over `assets/js/` (`assets/tsconfig.json`): a name that no module defines or imports, an unused import. It is not part of the suites.

### The footer row

A table with a `summary` on one of its columns has a `<tfoot>` whose first row, `ID-summaries`, holds a `gridcell` per column (`ID-summary-FIELD`); a nested table's pages and its link to the full view are the rows after it. The row is counted in `aria-rowcount`. The hook's style rules for hidden and resized columns cover `tbody` and `tfoot` cells alike (`restyle`), and Page Down and Ctrl+End end at the last record (`onKeydown`). See "Footer summaries" in the comment at the top of the component.

## Safety rules

Every change must keep these. They are what part 2 is for.

- **Read again as the person before any write.** The table keeps keys, not records. Before a save, an action, a reveal or a pick, the record is read again by its key through the table's read action, with the person's actor, tenant and arguments (`AshDataTable.Record.fetch/3`, `AshDataTable.Pick.chosen/3`). A record that read does not return is not there.
- **Every action a table runs is `public?`.** Read, update, create, destroy and generic actions, and the read action of a nested table or a picker. The verifiers refuse a private one (`Reading.read_action/2`, `Reading.private_read/2`, `Relating.public_read/2`, `Acting.unusable/4`; the sentence they share is `Reading.private_action/0`).
- **`authorize?`.** Every call to Ash passes the reader options (`scope`, `actor`, `tenant`, `authorize?`; `AshDataTable.Caller`, `reader/1` in the component, `Query.reader_opts/1`). `authorize?` comes from the domain unless the table is told otherwise. The table adds no rule of its own and hides nothing by itself: it asks Ash (`Model.Access`).
- **Nothing sensitive reaches the browser before "Show".** A part draws only from what `AshDataTable.Present` gives: a row from a record that went through `AshDataTable.Sensitive.scrub/2`, a sensitive cell as `:masked` with no value, a sensitive field of the panel with only what was typed in it, the label of a chosen record scrubbed. `test/present_test.exs` checks it for every function. The value is sent only as the reply to `reveal`, after the record was read again. An editor of a sensitive column opens empty.
- **An announcement is a claim too.** A live update names a primary key and nothing else. The table shows only what its own read returns for that key, as the person (`Query.rows/4`), and says that there are new or changed records only after asking, as the person and with their filters, whether one is theirs to see (`Query.any?/5`). The notifier never sends a record.
- **A summary says no more than the rows.** `Query.summaries/4` asks `Ash.aggregate/3` with `authorize_fields?: true` and with the table's read action as each aggregate's `read_action` (Ash would otherwise judge field policies as the primary read action meets them), and asks for nothing over a column that is `partly_hidden?` for the person: its footer cell is a dash. `summary` is refused on a `sensitive?` column.
- **Values from the browser are claims.** A row key, a column name, an action name, a picked record and a selection are looked up or read again before they are used. A page size from a URL or an event is taken only when it is one of the table's `page_sizes` (`State`, and once more where the query is built: `Model.Pagination.size/2`). Sort and filter go through `Ash.Query.sort_input/2` and `Ash.Query.filter_input/2`. What a person typed goes to the action as typed (but a wall time of a datetime, which goes as the UTC instant it is in the page's zone: `AshDataTable.Zone`); Ash casts and validates it. Text from outside never becomes an atom.

## Adding a feature

1. **DSL option.** A table option goes into `@options` in `lib/ash_data_table/resource/table.ex` (one that means something else in a named table also into `@follows` there). A domain option goes into `lib/ash_data_table/domain.ex`. An option of a column, action or other entity goes into that entity in `lib/ash_data_table/resource.ex` and its struct in `lib/ash_data_table/resource/`.
2. **Regenerate**, in the repository root: `mix spark.formatter` (writes `.formatter.exs`) and `mix spark.cheat_sheets` (writes `documentation/dsls/`).
3. **Verifier.** See "A new diagnostic" above.
4. **Model.** Put the answer into `AshDataTable.Model` or one of its structs. What depends on the person belongs in `for_actor/2`.
5. **Component.** A field of `AshDataTable.Live.Entry` with its comment (or an option of `AshDataTable.Table`), changed with `put/2`; an event in `AshDataTable.Intent` and an `on/2` clause (see "Events"), what a part draws of a record in `AshDataTable.Present`, markup in the part of `AshDataTable.Parts` it belongs to (a field it needs is passed to the part as an attribute from `render/1`, `x={@table.entry.x}`), browser behaviour in a module of `assets/js/grid/` (a new module is added to the list in `grid/index.js`). Add what the markup promises to the comment at the top.
6. **Texts.** Add the key to `@type key` and a `msgid/1` clause in `lib/ash_data_table/text.ex`. Run `mix gettext.extract` in the root to update `priv/gettext/ash_data_table.pot`. Add the German text to `demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po`.
7. **Demo.** Resources are in `demo/lib/demo/tracker/` and `demo/lib/demo/kitchen_sink/`, routes in `demo/lib/demo_web/router.ex`, seeds in `demo/priv/repo/seeds.exs`. A resource that exists for tests only goes into `demo/test/support/*_tables.ex` and under `/support` in the router. Describe a new page in `demo/README.md`.
8. **Tests**, at three boundaries:
   - `test/` in the root: declaration, verifiers, model and the modules of part 2, against the resources in `test/support/`. `test/architecture_test.exs` places each file of `lib/` in a part by its directory: a new file goes into the directory of its part.
   - `demo/test/demo_web/tables/`: the rendered table through LiveView tests, with the helpers of `DemoWeb.TablePage` (`demo/test/support/table_page.ex`). A test that changes a record of a live resource and then looks at an open page calls `AshDataTable.Test.flush(view)`; it never sleeps for the 100 ms. The helpers have three seams, which the refactor changes in one place: every event goes through `send_event` (tests send what a browser never sends with `forge/5`, never with `render_hook`); every reader goes through `query/2`, which reads a portal's content where it is shown (use `click/2` and `has?/3` for controls of nested tables and pickers); and `ran/1` waits until nothing says `aria-busy`. A count of listeners is `AshDataTable.Test.listening/2`. The ids, attributes and events the helpers rely on are written down at the top of the table component ("What the tests rely on besides", "Events").
   - `demo/test/demo_web/markup_snapshot_test.exs`: the markup in sixteen states, compared with `demo/test/snapshots/`. A change of the markup on purpose: `MIX_SNAPSHOT_UPDATE=1 mix test test/demo_web/markup_snapshot_test.exs`, and look at the diff.
   - `demo/e2e/*.spec.ts`: the browser, with the `Table` class of `demo/e2e/support/table.ts` and `demo/e2e/support/actors.ts`. A spec never reaches into the hook: `Table.forge` sends an event by hand, `Table.ask` opens the question dialog.
   - `demo/perf/baseline.mjs`: the performance baseline of the refactor (`docs/architecture/baseline.md`).
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

# the hooks' JS (TypeScript over assets/js; `npm install` once)
ASDF_NODEJS_VERSION=$(awk '/nodejs/{print $2}' demo/e2e/.tool-versions) npm run check

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
- LiveView makes the `node_modules` link beside the extracted hooks once and keeps it. A `_build` from before the hooks moved has it pointing at `assets/node_modules`, and esbuild cannot resolve `../node_modules/js/index.js`: delete `_build/*/phoenix-colocated/ash_data_table/node_modules` (or `mix clean`), and the next compile makes it again.
- Tailwind scans `lib/` (the host's `@source` line), not `assets/js/`. A class the hooks set must also be written in the markup of `lib/`.

## Build rules (agreed 2026-10-13)

- Mutation checks only where a missed bug is dangerous: authorization, what is sent to the browser, and what gets written. Not for looks and convenience.
- Each suite runs once: root, demo, browser. A failure that passes on a second run is still looked into.
- A build writes only its own guide section. README, changelog and the other guides are caught up once per milestone.

## Where decisions live

- The specification is issue #21 of `StefanRoesch/ash_data_table` on GitHub.
- Its comment "Built in the owner's absence" holds every decision since 2026-10-09.
- The glossary is `CONTEXT.md`. Architecture decisions are in `docs/adr/`.
- The other agent documents are in `docs/agents/`.
