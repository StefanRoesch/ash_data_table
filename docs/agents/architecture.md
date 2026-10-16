# Architecture map

Read this file before a build. It says where things are, so that you do not have to read every guide and the whole drawing first. Paths are from the repository root. Line numbers are of stage 3c of the refactor (the live core); stage 4 moved the drawing into `lib/ash_data_table.ex`: each section says how to get them again.

The words used here (table, column, cell, picker, action panel, …) are defined in `CONTEXT.md`.

## The four parts

The extension has four parts. This is the target structure agreed with the owner; `docs/architecture/target.md` describes it, and its section 9 says which stages of the refactor are done. A file's directory says its part (target.md 5.5), and `test/architecture_test.exs` checks the direction of every dependency from it: it fails on what breaks the rules.

| Part | What it is | Where it is today |
| --- | --- | --- |
| 1. Table declaration | The `table` and `tables` blocks of a resource, the `table` block of a domain, the checks at compile time, and the notifier of live updates. | `lib/ash_data_table/resource.ex`, `lib/ash_data_table/resource/**`, `lib/ash_data_table/domain.ex`, `lib/ash_data_table/domain/**` |
| 2a. Table internals, data | Logic and state, no markup, no socket. This part keeps the table safe. | `lib/ash_data_table/model.ex`, `lib/ash_data_table/model/**`, and the other files at the top of `lib/ash_data_table/`: `caller.ex` (who asks, `AshDataTable.Caller`), `state.ex`, `query.ex`, `record.ex`, `related.ex`, `routes.ex`, `pick.ex`, `edit.ex`, `act.ex`, `bulk.ex`, `errors.ex`, `sensitive.ex`, `zone.ex`, `present.ex` (what a part draws), `intent.ex` (what an event asks for), `operation.ex` (every write), `request.ex` (what the veto is told, public), `event.ex` (what the page is told, public), `typed.ex` (the text a control holds) |
| 2b. Table internals, live | The core over a LiveView socket. | `lib/ash_data_table/live/**` but the page and `embedded.ex`: `core.ex` and `core/*.ex` (`AshDataTable.Live.Core` and its modules, `Core.Notify` the events to the host), `current.ex` (the guards over the table a callback works on), `hooks.ex` (`AshDataTable.Live.Hooks`: a table attached to a LiveView), `registry.ex` (`AshDataTable.Live.Registry`, the tables of one `Table`), `listener.ex`, `table.ex` and `entry.ex` (the state of a table) |
| 3. Table UI components | Markup and the browser hooks. | `lib/ash_data_table/parts/*.ex` (`AshDataTable.Parts.*`), the four hooks in `assets/js/` (JS files of the package; the colocated hooks of `AshDataTable` import them), the behaviour `lib/ash_data_table/component.ex` and the shipped components in `lib/ash_data_table/components/` |
| 3w. The words | What turns values and messages into text. | `text.ex`, `format.ex`, `gettext.ex` in `lib/ash_data_table/` |
| 4. Ready-made wiring | The public entry, the router line, the page and the tag's live component that connect 2 and 3. | `lib/ash_data_table.ex` (`table/1`, `attach/4`, `detach/2`, `attached/1` and the drawing), `lib/ash_data_table/router.ex`, `lib/ash_data_table/live/page.ex`, `not_found_error.ex`, and `live/embedded.ex` (`AshDataTable.Live.Embedded`, what the tag renders: its callbacks hand the socket to `Live.Core`, it draws with `attached/1`) |

A table reaches a page in three ways, all on one live core and one drawing (stage 4): the router line (`Live.Page`, which attaches its table), the tag (`<AshDataTable.table>`, one live component, `Live.Embedded`), and `AshDataTable.attach/4` in a host's LiveView, drawn with `AshDataTable.attached/1`. `attached/1` draws every table of the page, nested tables and pickers' tables included, from one registry (`Live.Registry`). There is exactly one `live_component` in `lib/`: the tag's.

## Module map

One line per module. The functions named are the ones other modules call.

### Part 1: declaration

- `AshDataTable.Resource` (`resource.ex`): the Spark extension. Defines the entities (`@column`, `@ask`, `@relationship`, `@argument`, `@reference`, `@action`, `@upload`), the sections `@table` and `@tables`, the named table entity `@named_table`, and the list of verifiers at the end.
- `AshDataTable.Resource.Table` (`resource/table.ex`): one table as written. `options/0` is the option schema that the `table` block and a named table share. `path/1`, `anno/2`, `option_anno/3` find where an error points to. `in_words/1` names the table in a message.
- `AshDataTable.Resource.Column`, `.Ask`, `.Relationship`, `.Action`, `.Reference`, `.PageArgument`, `.Argument`, `.Upload` (`resource/*.ex`): the structs of the entities, each with `schema/0`. `page_argument` (inside `action`) names a public argument the page fills.
- `AshDataTable.Resource.Info` (`resource/info.ex`): read a declaration. `tables/1`, `table/2`, `table!/2`, `no_table/2`; for the default table `columns/1`, `relationships/1`, `actions/1`, `arguments/1`, `uploads/1` and the generated `table_*` functions.
- `AshDataTable.Domain` and `AshDataTable.Domain.Info`: the domain's `table` block (`authorize?`, `scope_assign`, `actor_assign`, `tenant_assign`, `time_zone_assign`, `pub_sub`). `Info.authorize?/1`, `Info.reader/2`, `Info.assign_names/1`, `Info.time_zone/2`, `Info.time_zone_assign/1`, `Info.pub_sub/1`. Its one verifier, `Domain.Verifiers.VerifyPubSub` (`domain/verifiers/`), reports a domain that names no `pub_sub` and has a resource that says `live? true`.
- `AshDataTable.Resource.Transformers.Announce` (`resource/transformers/announce.ex`): the extension's one transformer. It gives a resource that says `live? true` the notifier `AshDataTable.Resource.Notifier`, named as an atom.
- `AshDataTable.Resource.Notifier` (`resource/notifier.ex`): the notifier of live updates (see "Live updates" below). `topic/2`.
- `AshDataTable.Resource.CellType` (`resource/cell_type.ex`): Ash type to cell type. `of/2`, `classify/2`.
- `AshDataTable.Resource.Operator` (`resource/operator.ex`): filter operators per cell type. `available/2`, `to_ash/2`; `takes/1` (no value, one, several, a range), `predicates/2`, `negated?/1`.
- `AshDataTable.Resource.Words` (`resource/words.ex`): `humanize/1`, a name in words.
- `Mix.Tasks.AshDataTable.Install` (`lib/mix/tasks/ash_data_table.install.ex`): the Igniter installer.

The rules of a declaration live in one module per topic. Each is shared by the verifiers (which report a mistake) and the model (which builds on the answer). Most return `{:error, reason}` and turn the reason into text with `message/1`.

- `Resource.Reading`: read action, pagination strategy, page sizes, what can be sorted. `read_action/2`, `strategy/2`, `page_sizes/2`, `sortable?/3`, `private_read/2`.
- `Resource.Editing`: the update action behind a column and whether it can serve an inline edit. `update_action/4`, `edit/4`, `editor/3`, `obstacle/2`.
- `Resource.Acting`: row actions, table actions, create, and their inputs. `offered/2` (also checks the `page_argument`s), `create_action/2`, `inputs/5` (without `record_argument` and the page arguments), `page_names/1`, `record_argument/3`, `bulk?/3`.
- `Resource.Arguing`: arguments of the read action and of calculation columns. `inputs/1`, `mistakes/3`, `declared_mistakes/2`.
- `Resource.Relating`: relationships a row offers and the nested table. `offered/2`, `declared/2`, `nested/1`, `read_action/2`, `public_read/2`, `page_sizes/2`.
- `Resource.Referencing`: reference cells, `label_field`, the picker, and `sticky_label?`. `label_field/1`, `sticky_label/2`, `reference/1`, `picking/2`, `declared/4`.
- `Resource.Managing`: arguments that a `manage_relationship` change hands to a relationship. `managed/3`, `handed/3`.
- `Resource.Embedding`: fields of a map cell, kinds of a union. `of/2`, `union/2`, `kind/2`. A value with a sensitive input, or a sensitive primary key, is read-only (its `obstacle`).
- `Resource.Presenting`: the `component` of a column, and how many lines its cells show (`max_lines`). `column/4`, `component/2`, `max_lines/3`.
- `Resource.Uploading`: limits of a file argument. `limits/2`, `mistakes/3`.
- `Resource.Exposing`: columns that show a field a field policy protects. `exposures/2`. Also whether a field is `sensitive?`: `sensitive?/1`, `typed?/1`, `empty?/1`.
- `Resource.Summarising`: the `summary` of a column (footer summaries). `kinds/0`, `column/2` (an attribute, not sensitive, a kind that fits the type), `action/1` (not a manual read action), `data_layer/2`, `fits?/2`.
- `Resource.Listening`: live updates. `announces?/1` (the resource says `live? true`), `follows?/2` (a table of it listens), `pub_sub/1`. Its findings are reported by the domain's verifier, not by a resource's.

Verifiers (`lib/ash_data_table/resource/verifiers/`), in the order `resource.ex` lists them: `VerifyTables` (names and duplicates in named tables), `VerifyReadAction`, `VerifyUpdateAction`, `VerifyLabelField` (also `sticky_label?`), `VerifyColumns`, `VerifyComponents`, `VerifyRelationships`, `VerifyActions`, `VerifyUploads`, `VerifyExposure` (warnings only), `VerifySummaries`.

A new diagnostic goes in two places. Put the rule and its `message/1` clause into the topic module above. Raise it from the verifier of that topic as a `Spark.Error.DslError`, with `Table.path/1` and `Table.anno/2` or `Table.option_anno/3` so that it points at the right line. A verifier checks every table of the resource: loop over `AshDataTable.Resource.Info.tables/1`. Then add it to `documentation/topics/mistakes-at-compile-time.md`.

### Part 2: internals

The model (2a):

- `AshDataTable.Model` (`model.ex`): everything a table is rendered from, built at runtime from `Ash.Resource.Info` and the declaration (ADR `docs/adr/0001-table-model-from-resource-info-not-manifest.md`). `build/2` builds it for a resource and a table name, the same for everybody. `for_actor/2` takes out the columns and actions this person can never see or use. `defaults/2` and `supply/2` fill in arguments. `bulk_actions/1`, `loads/1`, `relationship/2`, `nested_create/2`, `summarised/1` (the columns with a `summary`), `label_column/1`, `keeps_one?/1`, `label/1` (what a resource's table is called, before it is translated). `group?/1` (a column or input edited as groups of fields, or a union). Its `sticky_label?` is the table's option of that name. `zoned/2` puts the page's time zone into the model (`time_zone`) and its arguments.
- `Model.Column`, `Model.Field`, `Model.Input`, `Model.Action`, `Model.Argument`, `Model.Relationship`, `Model.Pagination`: structs. Each file starts with a comment that explains every key. `Pagination.size/2` is how many records a page holds for the size a person asked for: one of `page_sizes`, else `page_size`. `Field.from/1` makes fields of what `Resource.Embedding` gives, which are maps; `Field.of/2` the fields and kinds of a type, `Field.undeclared/1` what a map that declares none holds, by its keys in words. A column's `takes` says what each of its `operators` takes. `Column.value/2` is what a record holds for a column. `Argument.argument_id/1` is what an argument is called in the page, `Argument.shown/3` what its input shows.
- `Model.Limits`: `min`, `max`, `step` and the text counter. `of/2`, `counted/2`.
- `Model.Access`: what Ash says the person may see and do, before any read. `hidden_fields/4`, `partly_hidden_fields/4`, `forbidden_actions/3`.

State and URL:

- `AshDataTable.Caller` (`caller.ex`, 2a): who is asking and what the page adds: `scope`, `actor`, `tenant`, `time_zone`, and the page's `context`, `private_arguments`, `page_arguments` (maps or functions), `before_action` and `notify` (which events the page is told) (stage 6). No assigns. `new/1`; `reader_opts/1` is the keyword list the functions of 2a take as `opts` (`actor`, `scope`, `tenant`); `Live.Core.reader/1` adds the entry's `authorize?` (as told, else the domain's), puts the table's listener (`origin`) in front and, given the socket, `page_values` (`Live.Core.values/1`).
- `AshDataTable.State` (`state.ex`): sort, filters, arguments, page position, chosen page size (`per`). `from_params/2` and `to_params/2` are the URL format. `fit/2` drops what the model does not allow. `cycle_sort/3`, `filter/3`, `pending/2` (what the filter row was sent, an operator without its value among it), `value?/2`, `clear_filter/2`, `clear_filters/1`, `argue/3`, `put_argument/4`, `to_page/2`, `resize/3`.
- `AshDataTable.Related` (`related.ex`): the URL parameter `of` that limits a table to the records of one row (the full view). `from_params/5`, `to_param/2`, `path/5`.
- `AshDataTable.Routes` (`routes.ex`): where the host's router mounts a table. `default_id/2`, `table/4`.

Reads:

- `AshDataTable.Query` (`query.ex`): every read through the table's read action. `read/3` (one page), `read_related/4` (a nested table), `get/5` (one record by key), `matching/3` and `records/3` (a selection), `related_records/5`, `load/3`, `arguments/2`, `rows/4` and `any?/5` (live updates), `summaries/4` (footer summaries: one `Ash.aggregate/3` over everything that matches). Returns `%Query.Page{}`. `reader_opts/1` makes the Ash options of `opts` (idempotent): who asks, `authorize?`, and the `context` of `page_values` with the table's own key (`ash_data_table_origin`) last. `private/3` and `action_opts/3` are the private arguments an action declares, of `page_values`; `privately/3` sets them on a read. Every function of 2a takes `opts` with `page_values` and reduces them where it calls Ash.
- `AshDataTable.Record` (`record.ex`): the record of one row, read again as the person. `fetch/3`, `key/2`, `load/3`.
- `AshDataTable.Pick` (`pick.ex`): the record a person chose in the picker. `chosen/3`, `current/3`, `value/2`, `reader/2`.

The live core (2b):

- `AshDataTable.Live.Core` (`live/core.ex`) and its modules `Core.Reading`, `.Url`, `.Nesting`, `.Updates`, `.Cells`, `.Picker`, `.Panel`, `.Bulk`, `.Files` (`live/core/`): socket in, socket out; what the callbacks of the tag's component and the hooks of an attached table do. See "The wiring and the live core" below.

The state of a table (2b):

- `AshDataTable.Table` (`live/table.ex`): the one value a table is held in, under the attach name (the tag's component and the page use `table`); public, opaque (moduledoc only; a host reads it with `AshDataTable.status/1`): `options` (what the table on the page was told about how it is placed: `url`, `heading`, `mounted?`, `page_assigns` (a map, or `:socket` for an attached table: `Live.Core.page_assigns/1` gives the host's assigns), `target` (the tag's `@myself`, nil when attached: the parts' `phx-target`, and how a listener relays), `router`, `controlled` (what the host draws itself, `attach/4` only; `[]` for every table but the one on the page)), `caller`, `entry` (the table on the page), `entries` (every other table it shows, by id: nested tables at every depth and the tables of open pickers) and `pool` (stream names, `ID:rows`, `ID:rows_1`, … after the id of the table on the page). `new/0`; `put/2` puts fields where each lives and raises on a name none has.
- `AshDataTable.Live.Registry` (`live/registry.ex`): the tables of one `Table`. `within/3` checks an entry out into `table.entry` for the live core and puts the table on the page back (outside it, `table.entry` is always the top's; a table other than the top is shown the options of a placed table: no URL, heading or page of its own); `known?/2`; `async/2` (the task keys `{:ash_data_table, id, {:read | :summary | :bulk, token}}`, the token the entry's own) and `current?/2` (an answer of a closed entry, cancelled, is dropped, also when an entry of the same id opened since); `take_stream/1` and `give_back/2` (the pool: `"ID:rows"`, `"ID:rows_1"`, …, each configured once); `add/3`, `close/2`, `close_all/1` (`detach/2`: every entry and the top's own) (listener, tasks, copies of a run's files, uploads cancelled and disallowed (one whose file is on its way stays allowed until a table of the same id takes it again: LiveView refuses to give it up), stream emptied and back in the pool, entry gone); `portals/1` (the nested entries, parents first).
- `AshDataTable.Live.Entry` (`live/entry.ex`): one table: everything else it holds, each field with its comment (see "The state of a table" below). `new/0`.

Live updates:

- `AshDataTable.Resource.Notifier` (`resource/notifier.ex`, part 1): the Ash notifier of a resource that says `live? true`. Broadcasts `{:ash_data_table_changed, resource, action_type, primary_key, tenant}` and nothing else. `topic/2` is the topic of a resource and a tenant.
- `AshDataTable.Listener` (`live/listener.ex`, 2b): the process through which one table hears. `start/3` subscribes and hands batches (100 ms) to the table: `send_update` to the tag's component, or `{:ash_data_table_heard, id, batch}` to the LiveView of an attached table; `stop/1`; `flush/1` and `of/1` for tests. It ends with the LiveView.
- `AshDataTable.Test` (`test.ex`): public help for a host's tests. `flush/1` hands a page what was announced so far; `listening/2` counts listeners. For nested tables and pickers, which `Phoenix.LiveViewTest` does not see inside a portal: `page/1` (the page as the browser shows it, a `LazyHTML`), `send_event/5` (a table's event by its name, through the component that draws it, or the LiveView it is attached to), `send_form/5` (a form as the browser sends it, inside a portal too), `table_named/1` (the table an event's name is for). `DemoWeb.TablePage` calls them.
- In `AshDataTable.Query`: `rows/4` reads announced keys again as rows are read, `any?/5` asks whether one of them is the person's to see under their filters. `reader_opts/1` passes a table's own listener on as `context` (`origin`), so that the notifier leaves it out.

Writes:

- `AshDataTable.Operation` (`operation.ex`): the one way a table writes. `save/1`, `clear/1`, `refer/1`, `reveal/1` (the one way to a sensitive value), `run/1` (a row or table action without a panel), `submit/1` (the open panel: map cell, row, table, create, selection), `bulk/1` (a selection without a panel), `link/2` (what a nested table's create is given of its row). What the browser names is looked up here only, by its name as text: `column/2`, `action/2`, `table_action/2`, `bulk_action/2`; the live core asks these too. Each takes an `Operation.Input` (the intent, model, state, `parent`, `opts`, `picking`, `rows`, `panel`, `selection`, `read?`, `offered`, `with_files`, `veto`, `page_values`) and runs, in this order, the checks of what the browser named, the veto (a function of an `AshDataTable.Request`, made by `Live.Core.veto/1`), the files, the re-read and the action, given `page_values`. It returns `{:ok, %Operation.Outcome{}}` (its `event` what the page is told, made by `AshDataTable.Event`), `{:error, %Operation.Failure{}}`, `{:ask, question}`, `{:halted, message}`, `:refused` (a claim the model does not allow: nothing is said), or for a selection `{:start, run, files}`, which the live core starts with `start_async`.
- `AshDataTable.Edit` (`edit.ex`): save one cell. `save/5`, `refer/5` (reference cell), `clear/4`, `open/5` and `put/7` (map cell in the panel).
- `AshDataTable.Act` (`act.ex`): row actions, table actions and create, through `AshPhoenix.Form`. `open/5`, `validate/4`, `submit_row/6`, `run/4`; `open_create/4`, `submit_create/6`; `open_generic/4`, `run_generic/4`, `submit_generic/6`; `open_bulk/4`; `from_page/2` (the page arguments of an action, merged over its params; raises for one the page does not give).
- `AshDataTable.Bulk` (`bulk.ex`): a row action on a selection. `run/5`; its outcome has `done`, `succeeded` and `failed` (keys) and `failures`, and from `Operation` the `event`.
- `AshDataTable.Event` (`event.ex`, public types): the events a table tells the page (`names/0`: `:read`, `:read_failed`, `:row_saved`, `:row_created`, `:row_destroyed`, `:action_ran`, `:bulk_ran`, `:selection_changed`, `:row_opened`, `:requested`, `:row_expanded`, `:row_collapsed`) and their details, records scrubbed (`Sensitive.scrub/2`), `arguments/3` without sensitive ones and files by name. `Live.Core.Notify.told/2` adds `table`, `resource` and a nested table's `path`, filters by `notify`, leaves out a picker's tables, and sends `{:ash_data_table, top_id, {event, details}}` to `self()`: from `Core.Cells`, `Core.Panel`, `Core.Bulk.handle_async`, `Core.Reading.show` and `Core.Nesting` (`toggle`) and `Core.Selection`.
- What these say is a message term (`AshDataTable.Errors.message/0`), never words: see "Texts and values".
- Files have no module of their own in 2a: the limits are in `Resource.Uploading` and the upload handling is `AshDataTable.Live.Core.Files`.

Texts and values:

- `AshDataTable.Format` (`format.ex`, 3w): what a cell shows. `format/3` (with the page's zone; `/2` is UTC); `summary/3` for a footer summary; `said/3`, what a generic action returned as a person is told it.
- `AshDataTable.Typed` (`typed.ex`, 2a): the text a control holds for a value, the same in every locale: `of/3` (`/2` is UTC). `State`, `Act`, `Edit`, `Model.Argument` and `Present` compare and fill controls with it; the grid's editors too.
- `AshDataTable.Zone` (`zone.ex`): the time zone of the page. `check/1`, `check!/2` (the zone a page gives), `local/2` (shown), `zoned?/1` (a type whose values are instants), `given/3` (what a write is given for a wall time typed there: the UTC instant), `gaps/3` (wall times the zone skips), `read/3` (the same for a filter or an argument). Used by `Format`, `Edit.save/5`, `Act` (`taken`, `gaps/3`), `Model.supply/2`, `Query` (filters).
- `AshDataTable.Text` (`text.ex`, 3w): every text a person reads. `say/1` turns a message term into text: `{:text, key, bindings}` (a plural key has `count` among the bindings), `{:ash, message, vars}` (an action's message), `{:label, text}` (the resource's wording), `{:join, separator, messages}`, `{:once, separator, messages}` (each text once: an action's messages, `Errors.joined/1`); a binding may be a message, and a text that is words already (a model's label) stays as it is. `once/1` (a list each text once: a panel field's errors) and `counted/1` (a run's failures, each text once with the counts added up) make the words unique where they are made. Under it `t/2` and `n/3` for the table's own messages, by key, and `label/1` for the resource's wording. The data layer never calls it: a part says a message as it draws it (`Parts.Common.said/1`), the live core as it builds a reply, both in the LiveView's process.
- `AshDataTable.Gettext` (`gettext.ex`): the default backend, without translations. The template is `priv/gettext/ash_data_table.pot`.
- `AshDataTable.Errors` (`errors.ex`): what an error says to a person and at which field, as message terms (`@type message`). `of_read/2`, `of_action/3`, `of_form/4`, `at_field/4`; `ash/1` (an action's message as a term, with only the variables it names and `count`), `joined/1` (several as one, each text once).
- `AshDataTable.Sensitive` (`sensitive.ex`): `sensitive?` fields. `scrub/2` replaces every sensitive value of a record before a row is rendered; `masked/1` is what one value is kept as. Whether a field is sensitive is `Resource.Exposing.sensitive?/1`; what is drawn in its place is `Present.mask/0`.

Drawing data and intents (2a, stage 3a):

- `AshDataTable.Present` (`present.ex`): what a part draws, made of what the core holds; a part is never given a record, an `AshPhoenix.Form` or a changeset. Values, not texts: a part formats a value with `Format`; the messages the core holds (titles, errors, a failed edit's message) are message terms, passed on as they are. `row/3` gives a `Present.Row` for the stream (the record scrubbed first with `Sensitive.scrub/2`; a `Present.Cell` per column with `state` `:value`, `:empty`, `:masked` or `:forbidden`, `value` only for `:value`, `editable?`, and `failure`, whose `typed` is `""` for a sensitive cell). `panel/2` gives a `Present.Panel` with a `Present.Field` per input (`form_name`, `value`, shown `errors`, `places`, `chosen`, `clear`; a sensitive field holds only what was typed in this panel); it reads the control names, the method and the values from the `AshPhoenix.Form` itself (no `Phoenix.HTML` in 2a), and is given only what is said at each file field (`Live.Core.Files.files_said/2`). `picker/1` gives a `Present.Picker`. `label/3` is what a record is called, as a value with its column (scrubbed), which `chosen` holds. `field_value/4` (through `Typed.of/3`), `in_union?/2`, `mask/0` (what a part draws in place of a sensitive value); `header_rows/0` and `first_row/1`, the grid's geometry the core and the parts both count with.
- `AshDataTable.Intent` (`intent.ex`): `parse(event, params)` gives `{:ok, intent}` (one tagged value per event, see "Events" below) or `:malformed`. It checks the shape only; names stay text, every value stays a claim, nothing is looked up.

### Part 3: UI components

- `AshDataTable.Component` (`component.ex`): the behaviour of a column's `component` (`cell/1`, `editor/1`, `verify/1`, `commit/0`). `AshDataTable.Component.Column` is what a component is told about its column. `shown_as/1` (`@doc false`) is a cell type in words, for the shipped components.
- `AshDataTable.Components.Badge`, `.Image`, `.Progress`, `.Slider` (`components/`): the shipped components.
- `AshDataTable.Attrs` (`attrs.ex`, part 3, internal): the attribute bundles (target S5), one function per element drawn once per table (the grid's hook element and grid, the dialogs, the pagination, the selection line, the popovers, the roots): id, role, ARIA, `data-*`, `phx-*`. A part spreads it (`<div {Attrs.grid(…)}>`). What is drawn per row or per column (a record's row group, row and cells, the header and filter cells, the action buttons, the lines, the summaries, the resizers, the editor templates) writes its constant attributes in the part and spreads only what varies (`Attrs.rowgroup/2`, `Attrs.cell/5`, `Attrs.actions/2`, `Attrs.action/2`, `Attrs.column_header/5`, `Attrs.summary/2`): stage 7a's fallback D3 b, as a spread sends the attribute names with every row. `markers/0` names every marker (`assets/js/markers.js`).
- `AshDataTable.Parts.*` (`parts/`): the markup of the table, function components that draw from the table's entry and options, which `body/1` in `lib/ash_data_table.ex` passes to each as attributes (`model={@entry.model}`). A part is never given the whole `@table`: it holds the caller. The rows of the grid, the action panel and the picker are drawn from what `AshDataTable.Present` gives (`panel={Present.panel(@table.entry.panel, …)}`, `picker={Present.picker(@table.entry.picker)}`; the rows come through the stream). Per part: its public functions, then the function components it keeps to itself:

| Module | What it draws | Functions |
| --- | --- | --- |
| `Parts.Heading` | The line of the table's name, create, table actions | `heading/1`; `create`, `table_actions` |
| `Parts.Related` | What a table limited to related records says above its grid; the lines under an expanded row and the nested table in each; the link to the full view | `related/1`, `lines/1`, `full_view/1`, `full_view?/2` |
| `Parts.Arguments` | The argument line | `argument_line/1`; `argument` |
| `Parts.Filter` | The filter row's form; one column's filter, "is any of" | `filter_form/1`, `filter/1`, `shown_filter/4`; `choices` |
| `Parts.Selection` | The line above the grid: selection, notice, "Clear filters", "Columns" | `selection_line/1`; `selection` |
| `Parts.Grid` | The grid: header, filter row, rows and cells (from `Present.Row`), footer, editor templates, the scrollbar; "Columns"; the view helpers; the look of the root of the table on the page (`root/0`: the theme's colours for the hooks and the grids' structural style, written on markers once per page, D6) | `grid/1`, `columns/1`, `hideable/1`, `root/0`; `resizer`, `editor`; the helpers of a cell (`cell_content`, `shown`, `cell`) |
| `Parts.Summary` | The footer row of summaries | `summaries/1`; `summary` |
| `Parts.Pagination` | Pages, "Rows per page" | `pagination/1`, `pages?/2`; `pages` |
| `Parts.Panel` | The action panel (from `Present.Panel`), its fields, groups, unions, chosen records (it formats their label values); the upload of each file field, from the `files` `body/1` gives it | `panel/1`; `field`, `group`, `groups`, `union`, `members`, `field_editor`, `called` |
| `Parts.Picker` | The picker dialog (from `Present.Picker`), its table as the slot | `picker/1` |
| `Parts.Messages` | The live region and a run's result, the notice of changes, the failure template, the whole-text popover, the question dialog, error, loading, fill and "No records" | `status/1`, `notice/1`, `failure/1`, `whole/1`, `dialog/1`, `messages/1` |
| `Parts.Editors` | The counter of a text, the list editor; the edge and type of a control | `count/1`, `list/1`, `described/1`, `control_edge/0`, `box_edge/0`, `input_type/1`, `input_step/1` |
| `Parts.Common` | Nothing of its own: the helpers several parts draw with. A leaf, so that the parts call each other in no circle | `said/1` (a message term in words; the parts import it), `event/2` (the name of an event of a table, `ash_data_table:ID:event`), `failure_message/2`, `colindex/2`, `trail/1`, `summary_rowindex/1` |

The live core calls none of these. What its events and the markup both mean is in part 2a (`Model.group?/1`, `Model.Column.value/2`, `Model.Argument.argument_id/1` and `shown/3`, `Present.header_rows/0` and `first_row/1`). The upload helpers (`upload_name/2`, `upload_of/3`, `upload_errors_of/1`, `file_errors/3`, `entry/1`, `entry_ref/1`) are `Live.Core.Files`'s, beside `said_of/4`; `panel_files/2` gives the panel what they say, through `body/1`. A part never calls the wiring. A nested table and a picker's table are no part's: `attached/1` draws them (see "Nested tables through portals"); `Parts.Picker.picker/1` takes the picker's table as its slot.

`phx-no-format` stays only where whitespace is what is drawn: the rows of the grid (written without whitespace, as every byte of a row is sent again), a header's label, the live region, the failure template, the whole-text popover and the heading of a table of related records. Elsewhere the markup is formatted as any HEEx (stage 7a dropped the indentation kept from `render/1`: an opened nested table sends its statics again, D18 c).

- The four hooks are JS files in `assets/js/` ("The four hooks", below). `AshDataTable` keeps one colocated hook per hook, which imports it, so a part names one in full (`phx-hook="AshDataTable.Grid"`), as `AshDataTable`'s `.Grid` renders.

### Part 4: wiring

- `AshDataTable.Router` (`router.ex`): the macro `ash_data_table/3`. It mounts `AshDataTable.Live.Page` and puts resource, table name and id into the route, and what the route gives the table (stage 6: `notify`, `open`, `context`, `private_arguments`, `page_arguments`, `before_action`, a function as `{module, function}`), which the page hands `attach/4`. The host hears the events and gives commands in its `on_mount` hooks.
- `AshDataTable.Live.Page` (`live/page.ex`): the LiveView behind a router line. In its first `handle_params/3` it finds its route, attaches the table under `table` with `url: true`, `heading: 1` and the internal `mounted?: true`, tells it the URL once itself (`Live.Hooks.told_url/2`), and raises `NotFoundError` when that first read is `gone?`. Its hooks of `handle_event`, `handle_async`, `handle_info` and `handle_params`, attached ahead of the table's, see when the reader or zone assigns changed and attach again under `table` first (`asking/1`), so that what waits in the mailbox runs as the person asking now; an `after_render` hook (`asked/1`) sends the page a message for a change that nothing follows. Its assigns are `table`, `route`, `layout_assigns` (put into the layout's assigns with `assign/2` when they changed) and `page_title`.
- `AshDataTable` (`lib/ash_data_table.ex`): `table/1`, the tag, which renders `Live.Embedded`; `attach/4` and `detach/2` (`Live.Hooks`); the commands `refresh/2`, `put_state/3` (`Core.Url.put_state/2`), `clear_selection/2`, `selected_records/2` (`Core.Selection.records/1`), each through `Live.Hooks.command/4` (an unknown name raises: the tag has none) and `Live.Core.command/2` (which ends in `tidy/1`); `status/1` (what a host reads of a `Table`); controlled mode (`attach(…, controlled: [:confirm, :panel])`, refused for a panel with a file, group, union or chosen records): `request/1`, `confirm_request/3`, `validate_request/4`, `submit_request/4`, `cancel_request/3`; `attached/1`, the drawing of a table (with an internal `root`; private `drawn/1`, `body/1`, the four colocated hooks and the markup contract comment); `label/1` (`Model.label/1`, translated).
- `AshDataTable.Live.Embedded` (`live/embedded.ex`): the live component of the tag. Its callbacks hand the socket to `Live.Core`; it draws the root element and `attached/1` in it with `root={false}`.
- `AshDataTable.Live.Hooks` (`live/hooks.ex`, 2b): a table attached to a LiveView. The socket's private data under `:ash_data_table` (`current`, the attached `tables` with what each was told, the stream names each id configured, the `url` of the last `handle_params`, the `hooks`); `attach/4`, `detach/2`, `told_url/2`; the four hooks (the only `attach_hook` calls of `lib/`), which halt every `ash_data_table:` event, `{:ash_data_table, id, {kind, token}}` result and relayed batch, known or not, and let the rest through. `url: true` needs a routed root LiveView; the hook of `handle_params` halts where the LiveView has no `handle_params/3` (LiveView would call it all the same).
- `AshDataTable.NotFoundError`: raised by a mounted table whose read is refused; Phoenix answers 404.

## The wiring and the live core

The drawing is in `lib/ash_data_table.ex`: `attached/1` and its private `drawn/1` (the table on the page, then one portal per nested table) and `body/1` (the parts of one table, in their order), and the four colocated hooks, four lines each, which import the hooks of `assets/js/`. Before them a long comment: the markup contract (ids, `aria-colindex`, components) and one section per feature; read the section of the feature you touch. The callbacks are `Live.Embedded`'s (the tag) and the hooks of `Live.Hooks` (an attached table, the page); each hands the socket to the live core.

The logic is `AshDataTable.Live.Core` (2b), one module per topic (`lib/ash_data_table/live/core.ex`, `core/*.ex`). Each topic module has `on/2`, one clause per intent of its topic. Find a function with:

```sh
grep -n '^  def\|^  defp' lib/ash_data_table/live/core.ex lib/ash_data_table/live/core/*.ex
```

| Module | What |
| --- | --- |
| `Live.Core` (`core.ex`) | `mount/1`; `values/1` (the page values for the current entry, called with `page_assigns/1` and its `table_ref`, once per callback and table: `callback/1` keeps them in the process dictionary while a callback runs) and `veto/1` (the closure `Operation` asks); `update/2` (`told/2`: what a listener hands over, and every assign the table is given: `selecting`, `in_words`, `current_state`, `awaited`, `lines`, `lead`); `handle_event/3` (`addressed/2`, `Intent.parse/2`, `topic/1`, `malformed/2`); `handle_async/3`. Each ends in `tidy/1`. `tell/2` (what the top is told, then `tidy/1`), `heard/3` (a listener's batch), `unknown/2` (the answer to an event of a table that is gone), `page_assigns/1`. Besides: `table/1` and `put/2` (the table the callback works on, under the name in the socket's private data: `current`), `reader/1`, `say/2` (the live region), `operation/3` (an `Operation.Input`), `in_words/1`, `told/2` (what a table is told, by the host or by the table it is in), `asker/2` (who is asking changed: what is open closes first) |
| `Core.Reading` | `settle`, `read`, footer summaries (`due`, `summarise`, `unsummed`), `read_opts`; `handle_async/3` of `:read` and `:summary`; showing a read (`unfilled`, `show`, `not_found`, `put_row`, rows through `Present.row/3`, `put_detail`, `put_failure`, `remove_row`, `announce`, `title_of`, `label`, `row_key`); `on/2` of `sort`, `filter`, `clear_filter`, `clear_filters`, `page`, `page_size` |
| `Core.Url` | `on/2` of `arguments`, `argument_add`, `argument_remove`; `reargue`, `refilter`, `go` and the URL (`path`, `query_params`) |
| `Core.Nesting` | `relate`, `build`, `nested_model`, `creates`; what a nested table and a picker's table are given (`nested_reader`, `picker_reader`); `on/2` of `expand`, `toggle`; `reconcile/1` (opens the nested tables and pickers' tables that are rendered, tells one again what changed, closes those no longer reached) and `children/2` |
| `Core.Updates` | live updates: `listen`, `follow`, `working`, `refresh`, `leave`, `notice`; `on/2` of `left`, `read_again` |
| `Core.Cells` | `on/2` of `save`, `clear`, `reveal`, `edit` (a map cell's panel), `discard`, `dismiss`; what came of a save or a reference cell's choice (`saved`, `referred`) |
| `Core.Picker` | `on/2` of `pick`, `pick_input`, `picked`, `picker_cancel`, `panel_unpick`; the fields of the panel given by choosing (`choose_input`, `choose_inputs`, `entry`, `hold`), `picked_with` |
| `Core.Panel` | `on/2` of `act`, `table_act`, `table_run`, `create` and the panel's events; `panel/3`, `open_act`, `errors`, `submit`/`submitted`, after a create or a run (`add_row`, `failed_panel`, `ran`, `run_table`, `done`) |
| `Core.Bulk` | `on/2` of `bulk`, `bulk_run`, `bulk_seen`; `open_bulk`, `start_bulk`; `handle_async/3` of `:bulk` (the outcome of a run, said in this process) |
| `Core.Requests` | controlled mode (stage 6), for the table on the page only: `controlled?/2`, `ask/4` (a question held in place of the hook's; it ends a panel held), `follow/1` (in `tidy/1`: a panel of a row, table, create or selection action held as a request, a new one with a new `ref` and `:requested` when another panel opens; a map cell's panel ends the panel's request, and is the table's to draw; a question held stays), `answer/4` (a stale `ref` does nothing), `confirmed/2`, `panel/2`; `entry.request` holds `ref`, `kind` and `for`, `Event.request/1` the projection `AshDataTable.request/1` says in words |
| `Core.Selection` | what is selected (stage 6): `on/2` of `select`; `put/3` (and tells the hook with `ash_data_table:select` where the server decided it, and the host `:selection_changed`), `scoped/1` (in `tidy/1`: a selection under other filters, arguments or `of` ends), `gone/2` (a row that went), `named/2` |
| `Core.Files` | the uploads of the panel: `opened`, `filed`, `attach` (`with_files` of `Operation.Input`), `spend`, the copies of a run, what is said of a file (`upload_errors_of`, `said_of`, `panel_files`) |

### Events

Every event is named with the table it is for: `ash_data_table:ID:event` (target.md Q4). The markup names it with `Parts.Common.event/2`; a hook sends the plain name, and its transport (`assets/js/transport/live_view.js`) names it with the id of the hook's element. All arrive in `Live.Core.handle_event/3`, which splits the name at its first and last `:` (`addressed/2`), parses the event once with `AshDataTable.Intent.parse/2` and hands the intent to `on/2` of its topic's module (`topic/1`): `{:sort, column}`, `{:save, row, column, typed}`, `{:bulk, action}` (the selection is the entry's), …. A payload of another shape, and an event named for another table or without the prefix, gets the answer `malformed/2` gives for that event, the one the table always gave it (`{ok: false}`, `{open: false}`, `{}` or none); an event the table does not know has no clause. A name from the browser is looked up as text (`Operation.column/2`, `Operation.action/2`, …); it is never turned into an atom. Every write (`save`, `clear`, `reveal`, `act` without a panel, `table_act`/`table_run` without a panel, `bulk_run`, `panel_submit`, and `picked` for a reference cell) goes through `AshDataTable.Operation`, which checks the claims; opening a panel or a picker is a read and stays in the live core.

- Reading: `sort`, `filter`, `clear_filter`, `clear_filters`, `page`, `page_size`.
- Argument line: `arguments`, `argument_add`, `argument_remove`.
- Nested tables: `expand`, `toggle`.
- Cells: `save`, `clear`, `discard`, `dismiss`, `reveal` (sensitive), `edit` (map cell, opens the panel).
- Row actions and create: `act`, `create`; `open` (the page's "Open" of a row: `Core.Panel` tells the page `:row_opened`, whatever `notify` says).
- Table actions: `table_act`, `table_run`.
- Selection: `select` (every change of what is selected), `bulk`, `bulk_run` (the action only: the selection is the entry's), `bulk_seen`.
- Action panel: `panel_validate`, `panel_submit`, `panel_add`, `panel_remove`, `panel_unpick`, `panel_clear`, `panel_cancel`.
- Picker: `pick` (from a cell), `pick_input` (from the panel), `picked`, `picker_cancel`.
- Live updates: `read_again` (the button beside the notice), `left` (the hook's answer to `ash_data_table:leaving`: no cell of that row is being edited, it can go). No event says which cell is edited: the hook alone knows, and it leaves that cell alone when a live update puts its row back.

A new event is a clause of `Intent.parse/2`, an `on/2` clause in the module of its topic, its tag in `Live.Core.topic/1`, and its name in `malformed/2`. The id in an event's name is looked up among the tables of the `Table` (`Registry.known?/2`; for an attached table first among the tables of the socket, `Live.Hooks`) and the intent runs within that entry (`Registry.within/3`); an unknown id gets `malformed/2`'s answer. `tidy/1` runs over every table shown: it reconciles (`Nesting.reconcile/1`), follows what was announced and the held rows of every table, parents first, reconciles again, and asks for the summaries that are due.

Each event's payload and answer are listed in "Events" in the markup contract in `lib/ash_data_table.ex`. The server tells the hooks with `push_event`, whose names carry no table id: `ash_data_table:focus`, `ash_data_table:ask`, `ash_data_table:select` (what is selected, where the server decided it), `ash_data_table:leaving` (a row whose record a live update found gone), each with `table: id`. The hooks tell each other with DOM events on the grid: `ash_data_table:selection`, `ash_data_table:choose`.

### The state of a table

The table is one assign (`AshDataTable.Table`): `table` in the tag's component and the page, the attach name otherwise, beside LiveView's (`streams`, `uploads`). The live core reads it with `Core.table(socket).entry.model` (or `.options.url`, `.caller.time_zone`) and changes it with `Core.put(socket, field: value)`; a function head says what it is for with the guards of `AshDataTable.Live.Current` (`when is_map(Current.entry(socket, :panel))`). `body/1` passes each part the fields it draws from, one attribute each, so LiveView's change tracking compares each field on its own: a change of one field renders again only what uses it (measured in stage 2: the bytes per action of `demo/perf/baseline.mjs` did not change). What lives where:

- Given by the caller (`update/2`): `id`, `resource`, `table`, `scope`, `actor`, `tenant`, `authorize?`, `live?` (kept as `live_given`), `url`, `label`, `heading`, `mounted?`, `select`, `choose`, `page_assigns`, `context`, `private_arguments`, `page_arguments`, `before_action`, `notify`, `open` (kept as `open_label`, the table on the page's only), `controlled`, `time_zone` (checked, nil is `"Etc/UTC"`; passed on to nested tables and pickers, and kept in an open panel); for a nested table `via`, `parent_key`, `parent_authorize?`, `parent_arguments`, `depth`, `depth_limit`, and for a nested table and a picker `path` (the path of the table it is in; the entry's `path` is it with its own id last). `scope`, `actor`, `tenant`, `time_zone`, `context`, `private_arguments`, `page_arguments`, `before_action` and `notify` go into `caller`; `url`, `heading`, `mounted?`, `page_assigns` and `controlled` into `options`; everything else, here and below, is a field of `entry` (`label`, `labelledby`, `select`, `live_given`, `authorize_given`, the resolved `authorize?`, `stream`, `uploads`, `target`, `given` among them). A nested table is told this by the table it is in, as `Nesting.reconcile/1` opens it, and again only when it changes (`given`).
- `live`, `waiting`, `held`, `notice?`: live updates. `live` is the table's listener and topic, nil for a table that does not follow. `leaving` are the rows that go once the hook answers. What is open under a table's rows is read from the registry (`Updates.working/1`, by `path`); the held rows of every table are looked at again after every callback (`tidy/1`). The listener relays `{:heard, id, batch}` to the tag's component, or `{:ash_data_table_heard, id, batch}` to the LiveView, which hands it to the entry `id`.
- `built`: the models as `Model.build/2` gives them, kept for the life of the table. `model`: the model for this person, made on every update.
- `state`: the `%AshDataTable.State{}`. `read`: what the last read was of; a read runs only when this changes.
- `page`, `row_count`, `busy?`, `loading?`, `error`, `gone?`. Every message the entry holds is a message term (`error`, `fill`, `announcement`, a failed cell's or row's message in `failed`, the panel's `title`, `submit`, `question` and `errors`, the picker's `title` and `error`, a run's `result`): the parts say it as they draw it.
- `rows`: by the key in a row's DOM id, the primary key and row index. An event names a row by that key, and it is looked up here.
- `failed`: edits that failed, by row. `open`: expanded rows.
- `missing`, `fill`, `refused`, `lines`: the argument line.
- `rejected`, `pending`: what the filter row shows beside the filters of the state: a value that was typed and is none, and the operators that were chosen without a value yet (`shown_filter/4`).
- `panel`, `picker`: the open action panel and picker, or nil. `request`: in controlled mode, the question or panel the host draws (`ref`, `kind`, `for`: what it was made for), nil for none (`Core.Requests`).
- `selecting`, `selected`, `all?`, `selected_under`, `bulk`, `lead`, `running`, `result`: selection and its actions. `selected` are the rows as the hook names them (primary keys, claims) or `all?`, held on the server (`Core.Selection`); `selected_under` what they were selected under. `Operation.Input.selection` is made of them.
- `spent`, `running_files`: uploads.
- `summarised?`, `summary`, `summing?`, `summed`, `summary_due`: footer summaries. `summary` holds by column `{:ok, value}` or `:unavailable`; `summary_due` (`:changed` after a read, `:force` after a write or a live batch) is answered in `tidy/1` by `summarise/1`.

### Async reads and the stream

- `start_async(:read, …)` in `Core.Reading.read/1`. The first read of a table on the page runs in place, so the first render has rows. Later reads, and every read of a nested table, run async with `busy?` set.
- `start_async(:bulk, …)` in `Core.Bulk.start_bulk`, with the run `Operation.bulk/1` or `Operation.submit/1` hands back (`AshDataTable.Bulk.run/5`). Its outcome holds message terms; `Core.Bulk.handle_async(:bulk, …)` keeps them, each text once (`Text.counted/1`), and the part says them in this process.
- `start_async(:summary, …)` in `Core.Reading.summarise/1`, which calls `AshDataTable.Query.summaries/4`: beside the read of the rows, never before them. `read/1`, `put_row`, `remove_row`, `add_row` and `follow` say that it is due (`due/2`); `tidy/1` starts it once.
- One stream per table, its name from the pool (`entry.stream`, `ID:rows`…), configured with `dom_id`. The names an id configured are kept on the socket across `detach/2`. An item is a row (`Present.row/3`, a `Present.Row`) or the detail under an expanded row (`detail`, a map with `detail?`). A new read resets it. `put_row` and `put_detail` insert one item; `remove_row` deletes a row and its detail. The server does not keep the records.

### Nested tables through portals

Every table a table on the page shows is in its one `Table` (stage 5); there is no live component but the tag's. `attached/1` draws the table on the page (`body/1`, the markup of a table, given its entry; the table of an open picker is drawn by `body/1` in the picker's dialog, which needs no portal) and after it, inside its root, one `<.portal>` per nested table (`Registry.portals/1`, parents first), each with the two elements that pin and size it and the nested table's `body/1`. LiveView moves each portal's content to the end of its target, the cell `ID-row-KEY-n-NAME-c` that `Parts.Related.lines` draws empty, in a wrapper of its own that the table relies on in no way. The rule that shows a line's buttons once its nested table has read (on the root, `Parts.Grid.root/0`) finds the nested table by the table's own marker (`[data-nested] [data-ash-data-table-portal] [data-read]`). A portal must never outlive its cell: every change of `open`, `rows` or `picker` is reconciled in the same callback (`tidy/1`). `Phoenix.LiveViewTest` does not look into a portal: the outer pinning element names its cell (`data-ash-data-table-portal`), and `AshDataTable.Test.page/1` (with it `DemoWeb.TablePage`) and the markup snapshots put what it marks into that cell (the snapshots drop the emptied template, `ID-portal`).

### The four hooks

They are JS files of the package, in `assets/js/`. `AshDataTable` keeps four colocated hooks of four lines, `import {Grid} from "../node_modules/js/index.js"` and the like, so the rendered names stay and a LiveView host gets them from `phoenix-colocated/ash_data_table` and sets up nothing more. The path works because `mix.exs` sets `phoenix_live_view: [colocated_assets: [node_modules_path: "assets"]]`: LiveView puts a link named `node_modules` beside the extracted hooks, in `_build/ENV/phoenix-colocated/ash_data_table/`, and points it at the package's `assets/`, wherever the package is (the parent directory for the demo, `deps/` in a host).

- `assets/js/index.js`: the four hooks as LiveView hooks (`Grid`, `Pagination`, `Panel`, `Picker`) and `hooks`, the same by the names the table renders. `package.json` in the root names it, for a custom build or another UI technology (`import {hooks} from "ash_data_table"`, from `deps/`).
- `assets/js/transport/live_view.js`: the transport (target.md S20). A hook never calls LiveView: it has `this.transport`, with `push(event, payload)` (a Promise of the reply; a push that fails gives a Promise that never settles, so no reply handler runs), `on(event, handler)` and `off(event)`. `hook(behaviour)` gives a hook its transport before `mounted`. Internal.
- `assets/js/markers.js`: every marker the hooks find an element by (stage 7a): the ARIA roles of the grid's structure (`TABLE`, `ROWGROUP`, `ROW`, `GRIDCELL`, `HEADER`, `DIALOG`) and the `data-*` attributes, besides the native controls the hooks ask for by kind (`input`, `button`, `form`, …). No hook names a structural tag (`table`, `tr`, `td`, `tbody`, `dialog`, `p`, `span`). `AshDataTable.Attrs.markers/0` names the same list (`test/markers_test.exs`). A position is by `aria-colindex` and by a row's place among the grid's rows (`grid/shared.js`: `cellsOf`, `place`, `rowsOf`, `groupsOf`, `firstRow`; `tree.js`: `rows()` puts the header's rows first, as the stream may put the records before it). The element of each hook names its table in `data-table`, which the transport, the panel, the picker and the pagination read (no id is cut).
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
| `actions.js` and `tree.js` | the page's "Open" | `openRow` (a click on `button[data-open]`, first in the actions cell) |
| `selecting.js` | selecting | painting what is selected, telling the server every change (`select`), `selected()`, `bulk` |
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

A table with a `summary` on one of its columns has a `<tfoot>` whose first row, `ID-summaries`, holds a `gridcell` per column (`ID-summary-FIELD`); a nested table's pages and its link to the full view are the rows after it. The row is counted in `aria-rowcount`. The hook's style rules for hidden and resized columns cover `tbody` and `tfoot` cells alike (`restyle`), and Page Down and Ctrl+End end at the last record (`onKeydown`). See "Footer summaries" in the markup contract in `lib/ash_data_table.ex`.

## Safety rules

Every change must keep these. They are what part 2 is for.

- **Read again as the person before any write.** The table keeps keys, not records. Before a save, an action, a reveal or a pick, the record is read again by its key through the table's read action, with the person's actor, tenant and arguments (`AshDataTable.Record.fetch/3`, `AshDataTable.Pick.chosen/3`), inside `AshDataTable.Operation`, after its checks and the veto. A record that read does not return is not there.
- **Every action a table runs is `public?`.** Read, update, create, destroy and generic actions, and the read action of a nested table or a picker. The verifiers refuse a private one (`Reading.read_action/2`, `Reading.private_read/2`, `Relating.public_read/2`, `Acting.unusable/4`; the sentence they share is `Reading.private_action/0`).
- **`authorize?`.** Every call to Ash passes the reader options (`scope`, `actor`, `tenant`, `authorize?`; `AshDataTable.Caller`, `Live.Core.reader/1`, `Query.reader_opts/1`). `authorize?` comes from the domain unless the table is told otherwise. The table adds no rule of its own and hides nothing by itself: it asks Ash (`Model.Access`).
- **Nothing sensitive reaches the browser before "Show".** A part draws only from what `AshDataTable.Present` gives: a row from a record that went through `AshDataTable.Sensitive.scrub/2`, a sensitive cell as `:masked` with no value, a sensitive field of the panel with only what was typed in it, the label of a chosen record scrubbed. `test/present_test.exs` checks it for every function. The value is sent only as the reply to `reveal`, after the record was read again (`Operation.reveal/1`). An editor of a sensitive column opens empty.
- **An announcement is a claim too.** A live update names a primary key and nothing else. The table shows only what its own read returns for that key, as the person (`Query.rows/4`), and says that there are new or changed records only after asking, as the person and with their filters, whether one is theirs to see (`Query.any?/5`). The notifier never sends a record.
- **A summary says no more than the rows.** `Query.summaries/4` asks `Ash.aggregate/3` with `authorize_fields?: true` and with the table's read action as each aggregate's `read_action` (Ash would otherwise judge field policies as the primary read action meets them), and asks for nothing over a column that is `partly_hidden?` for the person: its footer cell is a dash. `summary` is refused on a `sensitive?` column.
- **Values from the browser are claims.** A row key, a column name, an action name, a picked record and a selection are looked up or read again before they are used. A page size from a URL or an event is taken only when it is one of the table's `page_sizes` (`State`, and once more where the query is built: `Model.Pagination.size/2`). Sort and filter go through `Ash.Query.sort_input/2` and `Ash.Query.filter_input/2`. What a person typed goes to the action as typed (but a wall time of a datetime, which goes as the UTC instant it is in the page's zone: `AshDataTable.Zone`); Ash casts and validates it. Text from outside never becomes an atom.

## Adding a feature

1. **DSL option.** A table option goes into `@options` in `lib/ash_data_table/resource/table.ex` (one that means something else in a named table also into `@follows` there). A domain option goes into `lib/ash_data_table/domain.ex`. An option of a column, action or other entity goes into that entity in `lib/ash_data_table/resource.ex` and its struct in `lib/ash_data_table/resource/`.
2. **Regenerate**, in the repository root: `mix spark.formatter` (writes `.formatter.exs`) and `mix spark.cheat_sheets` (writes `documentation/dsls/`).
3. **Verifier.** See "A new diagnostic" above.
4. **Model.** Put the answer into `AshDataTable.Model` or one of its structs. What depends on the person belongs in `for_actor/2`.
5. **Component.** A field of `AshDataTable.Live.Entry` with its comment (or an option of `AshDataTable.Table`), changed with `Live.Core.put/2`; an event in `AshDataTable.Intent` and an `on/2` clause in the `Live.Core` module of its topic (see "Events"; the markup names it with `Parts.Common.event/2`), what a part draws of a record in `AshDataTable.Present`, markup in the part of `AshDataTable.Parts` it belongs to (a field it needs is passed to the part as an attribute from `body/1`, `x={@entry.x}`), browser behaviour in a module of `assets/js/grid/` (a new module is added to the list in `grid/index.js`). Add what the markup promises to the comment at the top.
6. **Texts.** Add the key to `@type key` and a `msgid/1` clause in `lib/ash_data_table/text.ex`. The data layer says it as `{:text, key, bindings}` and never calls `Text`; a part says it with `said/1`, a reply with `Text.say/1`. Run `mix gettext.extract` in the root to update `priv/gettext/ash_data_table.pot`. Add the German text to `demo/priv/gettext/de/LC_MESSAGES/ash_data_table.po`.
7. **Demo.** Resources are in `demo/lib/demo/tracker/` and `demo/lib/demo/kitchen_sink/`, routes in `demo/lib/demo_web/router.ex`, seeds in `demo/priv/repo/seeds.exs`. A resource that exists for tests only goes into `demo/test/support/*_tables.ex` and under `/support` in the router. Describe a new page in `demo/README.md`.
8. **Tests**, at three boundaries:
   - `test/` in the root: declaration, verifiers, model and the modules of part 2, against the resources in `test/support/`. `test/architecture_test.exs` places each file of `lib/` in a part by its directory: a new file goes into the directory of its part.
   - `demo/test/demo_web/tables/`: the rendered table through LiveView tests, with the helpers of `DemoWeb.TablePage` (`demo/test/support/table_page.ex`). A test that changes a record of a live resource and then looks at an open page calls `AshDataTable.Test.flush(view)`; it never sleeps for the 100 ms. The helpers have three seams, which the refactor changes in one place: every event goes through `send_event`, which names it with its table (tests send what a browser never sends with `forge/5`, never with `render_hook`); every reader goes through `query/2`, which reads a portal's content where it is shown, without the portal's wrapper (use `click/2` and `has?/3` for controls of nested tables and pickers; `seen/1` is that page for a test's own reader); the form helpers send a form inside a portal by its event's name (`send_form`); and `ran/1` waits until nothing says `aria-busy`. A count of listeners is `AshDataTable.Test.listening/2`. The ids, attributes and events the helpers rely on are written down in the markup contract in `lib/ash_data_table.ex` ("What the tests rely on besides", "Events"). The tests that run three ways (mounted, embedded, attached) use `DemoWeb.ModeCase` (`demo/test/support/mode_case.ex`): each mode is a host of its own (`embedded.example.com`, `attached.example.com`) whose routes place the router line's table of a path (`DemoWeb.Support.ModesLive`). Tables attached to a host page: `attach_test.exs` (`/support/attached`) and `demo/e2e/attached.spec.ts` (`/e2e/attached`).
   - `demo/test/demo_web/markup_snapshot_test.exs`: the markup in sixteen states, compared with `demo/test/snapshots/`, in three modes (`phx-target` and the target of a `JS.push` are dropped). A change of the markup on purpose: `MIX_SNAPSHOT_UPDATE=1 mix test test/demo_web/markup_snapshot_test.exs`, and look at the diff.
   - `demo/e2e/*.spec.ts`: the browser, with the `Table` class of `demo/e2e/support/table.ts` and `demo/e2e/support/actors.ts`. Each test runs in a database transaction of its own, rolled back when it ends (see "Running things"): it may write whatever it likes and says nothing of it, and a second person is a `browser.newContext()` of the same test, in the same transaction. A spec never reaches into the hook: `Table.forge` sends an event by hand, `Table.ask` opens the question dialog. What the page pushed to its LiveViews is the fixture `pushed` (`Sent` in `demo/e2e/support/fixtures.ts`: `all`, `count`, `besides`, `selected`, `expectSelected`), read from `DemoWeb.E2E.Recorder` (`demo/e2e/server/recorder.ex`), which hears LiveView's documented telemetry of `handle_event` in the e2e environment, by the test the page's session names, not from the WebSocket's frames. A spec finds a nested table's portal by the table's own marker (`data-ash-data-table-portal`), never by LiveView's markup (`data-phx-*`, a portal's wrapper).
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

A step of a build runs only what it changed, each once:

```sh
mix test --stale                  # root, and the same in demo: the test files that depend on a changed module
cd demo/e2e
ASDF_NODEJS_VERSION=$(awk '/nodejs/{print $2}' .tool-versions) npx playwright test --only-changed=main
                                  # the spec files changed since `main` (a commit or branch), and those that import a changed file
ASDF_NODEJS_VERSION=$(awk '/nodejs/{print $2}' .tool-versions) npx playwright test editing.spec.ts
                                  # the spec files a change of the server is about
```

`--stale` knows nothing of the browser and `--only-changed` nothing of Elixir: a change in `lib/` or `demo/lib/` names its spec files by hand. The three full suites run once at the end of a stage.

- `npm test` starts a server and a database per worker (ports 4480 and up), half as many workers as the machine has threads (`E2E_WORKERS=4 npm test` sets the number), and spreads the tests of every file over them (`fullyParallel`).
- Every browser test runs in a database transaction of its own, rolled back when it ends: Ecto's SQL sandbox through `Phoenix.Ecto.SQL.Sandbox`, in the e2e environment only (`sql_sandbox: true` in `demo/config/e2e.exs`). The fixture `sandbox` (`demo/e2e/support/server.ts`, automatic) starts it with `POST /sandbox` and ends it with `DELETE /sandbox` once the test's browser contexts are closed; the fixture `userAgent` makes its metadata the user agent of every context and request of the test, `browser.newContext()` and `request` included, so the two people of a test share one transaction. The plug at the top of `DemoWeb.Endpoint` allows each request, and `DemoWeb.E2E.Sandbox` (`demo/e2e/server/sandbox.ex`, a child of the application) each connected LiveView, from the user agent of the socket's `connect_info`, as it hears LiveView's telemetry `[:phoenix, :live_view, :mount, :start]` (before the `on_mount` hooks; the router stays as a host writes it, which the guides quote); what a LiveView starts with `start_async` is allowed through `$callers`. Where the endpoint serves, the sandbox is in manual mode (also `DemoWeb.E2E.Sandbox`), so a process nobody allowed fails. Nothing is seeded after a test: a test that writes needs nothing said. `sandbox.spec.ts` checks that a write is its own test's and gone when it ends. A server per worker, not one for all: a transaction keeps a test's writes from the others, but not its row locks, the live updates its writes announce (PubSub is the server's), or the memos of `/e2e/controlled` (ETS); on a server of its own, a worker runs one test at a time.
- Single-server mode, for writing a test: `./server.sh` in `demo/e2e` serves the e2e environment on 4479, and `npm run test:server -- editing` runs against it, one test at a time, each in its own transaction as well.
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
- Each suite runs once: root, demo, browser; a step runs only what it changed (`mix test --stale`, `--only-changed`, see "Running things"). A failure that passes on a second run is still looked into.
- A build writes only its own guide section. README, changelog and the other guides are caught up once per milestone.

## Where decisions live

- The specification is issue #21 of `StefanRoesch/ash_data_table` on GitHub.
- Its comment "Built in the owner's absence" holds every decision since 2026-10-09.
- The glossary is `CONTEXT.md`. Architecture decisions are in `docs/adr/`.
- The other agent documents are in `docs/agents/`.
