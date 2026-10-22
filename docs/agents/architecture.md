# Architecture map

Read this before a build: where every module is, the safety rules, the recipe for a feature and the commands. Paths are from the repository root, `lib/` means `lib/ash_data_table/`. The words (table, column, cell, picker, action panel, kit, part, projection, …) are defined in `CONTEXT.md`; the decisions behind the shape are in `docs/adr/`.

## Parts

Each part may depend only on the parts below it. A file's directory says its part; `test/architecture_test.exs` checks every dependency edge (`mix xref`) and fails on a forbidden edge or on a cycle inside 2a.

| Part | What | Where |
| --- | --- | --- |
| 1 Declaration | The `table`/`tables` blocks of a resource, a domain's `table` block, the verifiers, the notifier | `resource.ex`, `resource/**`, `domain.ex`, `domain/**` |
| 2a Data | Logic and state, every call to Ash; no LiveView, no socket, no words. Keeps the table safe | `model.ex`, `model/**` and the other files at the top of `lib/` |
| 2b Live | The core: the step over a table, and the adapter that applies its effects to the socket | `live/**` but `page.ex`, `embedded.ex`, `drawing.ex` |
| 3 UI | The kit, its parts, the bundles, the column components, the browser hooks | `kit.ex`, `kit/**`, `parts/**`, `attrs.ex`, `component*`, `components/**`, `assets/js/` |
| 3w Words | Values and message terms to text | `text.ex`, `format.ex`, `gettext.ex`, `messages.ex`, `item.ex` |
| 4 Wiring | The public entry, router line, page, tag | `lib/ash_data_table.ex`, `router.ex`, `live/page.ex`, `live/embedded.ex`, `live/drawing.ex`, `not_found_error.ex` |

A table reaches a page in three ways, all on one core and one drawing: the router line (`Live.Page`), the tag `<AshDataTable.table>` (`Live.Embedded`, the only `live_component` in `lib/`), and `AshDataTable.attach/4` with `AshDataTable.attached/1`. Nested tables and pickers are entries of one registry, drawn through portals (ADR 0006).

## Module map

### 1 Declaration

- `AshDataTable.Resource` (`resource.ex`): the Spark extension: entities, sections, verifier list.
- `Resource.Table` (`resource/table.ex`): one table as written; `options/0`, the option schema; `path/1`, `anno/2` for errors.
- `Resource.Column`, `.Ask`, `.Relationship`, `.Action`, `.Reference`, `.PageArgument`, `.Argument`, `.Upload` (`resource/*.ex`): entity structs.
- `Resource.Info` (`resource/info.ex`): reads a declaration.
- `AshDataTable.Domain`, `Domain.Info`, `Domain.Verifiers.VerifyPubSub`: the domain's `table` block (`authorize?`, assign names, `pub_sub`).
- `Resource.Transformers.Announce`: gives a `live? true` resource the notifier.
- `Resource.Notifier` (`resource/notifier.ex`): broadcasts a changed primary key, never a record.
- `Resource.CellType`, `.Operator`, `.Words`: cell type of an Ash type, filter operators, a name in words.
- Topic modules, one rule set each, shared by the verifiers and the model: `Reading`, `Editing`, `Acting`, `Arguing`, `Relating`, `Referencing`, `Managing`, `Embedding`, `Presenting`, `Uploading`, `Exposing`, `Summarising`, `Listening` (`resource/*.ex`).
- Verifiers (`resource/verifiers/`): one per topic, raising `Spark.Error.DslError`.
- `Mix.Tasks.AshDataTable.Install` (`lib/mix/tasks/`): the Igniter installer.

### 2a Data

- `AshDataTable.Model` (`model.ex`), `Model.*` (`model/`): what a table is drawn from, built from `Ash.Resource.Info` (ADR 0001); `for_actor/2` per person. `Model.Access`: what Ash says the person may see and do.
- `Caller` (`caller.ex`): who asks and what the page adds (actor, scope, tenant, zone, context, page values, veto).
- `State` (`state.ex`): sort, filters, arguments, page; the URL format.
- `Related` (`related.ex`), `Routes` (`routes.ex`): the full view's `of` parameter; where a router mounts a table.
- `Query` (`query.ex`): every read through the table's read action, nested reads (ADR 0005), summaries, announced rows.
- `Record` (`record.ex`), `Pick` (`pick.ex`): a row's record and a picked record, read again as the person.
- `Operation` (`operation.ex`): the one way a table writes: checks, veto, the panel's files, re-read, action.
- `Edit` (`edit.ex`), `Act` (`act.ex`), `Bulk` (`bulk.ex`): a cell's save; row/table actions and create through `AshPhoenix.Form`; actions on a selection.
- `Panel` (`panel.ex`): the action panel as one value. `GroupValue` (`group_value.ex`): a value made of fields in the panel's form.
- `Download` (`download.ex`): a file a generic action returned.
- `Request` (`request.ex`), `Event` (`event.ex`): public types of what the veto and the page are told.
- `Errors` (`errors.ex`): errors as message terms. `Sensitive` (`sensitive.ex`): scrubbing and the mask. `Zone` (`zone.ex`): the page's time zone. `Typed` (`typed.ex`): the text a control holds.
- `Present` (`present.ex`): what a part draws of what the core holds; never a record, form or changeset.
- `Geometry` (`geometry.ex`): where columns and rows stand. `Ids` (`ids.ex`): every DOM id both sides name.
- `Intent` (`intent.ex`): parses an event into one tagged value, or `:malformed`.

### 2b Live

- `Live.Core` (`live/core.ex`): the adapter on the socket and `step/3`, `(table, intent, context) -> {table, effects, reply}`.
- `live/core/*.ex`, one topic each, over the table, no socket: `Told`, `Reading`, `Url`, `Nesting`, `Updates`, `Cells`, `Picker`, `Panel`, `Bulk`, `Selection`, `Files`, `Notify`.
- `Core.Opener` (`live/core/opener.ex`) with `Opener.Table` and `Opener.Host`: who draws a question, panel or picker (the table, or the page in controlled mode).
- `AshDataTable.Table` (`live/table.ex`): the one value a table is held in; opaque. `Live.Entry` (`live/entry.ex`): one table's fields, grouped by topic (`arguments`, `selection`, `updates`, `footer`). `Live.Registry` (`live/registry.ex`): the tables of one `Table`.
- `Live.Hooks` (`live/hooks.ex`): a table attached to a LiveView. `Listener` (`live/listener.ex`): hears live updates, in batches.

### 3 UI and 3w words

- `Kit` (`kit.ex`): the behaviour, one function component per part. `Kit.Default` (`kit/default.ex`): the daisyUI kit. `Parts.*` (`parts/`): its markup.
- `Kit.Projection` (`kit/projection.ex`, `kit/projection/*.ex`): what each part is given (ADR 0004).
- `Attrs` (`attrs.ex`): the bundles and the events list; the markup contract.
- `Component`, `Component.Column` (`component*`), `Components.*` (`components/`): the column component behaviour and the shipped ones.
- `Item` (`item.ex`): a stream item with finished texts (ADR 0002). `Text`, `Format`, `Messages`, `Gettext`: texts, cell formatting, the list of message keys, the backend.
- `assets/js/`: `index.js` (the hooks), `mount.js` (for a kit drawing in the browser), `grid/` (the grid hook, one file per concern), `panel.js`, `picker.js`, `pagination.js`, `sender.js`, `download.js`, `markers.js`, `owned.js`, `ids.js`, `geometry.js`, `check.js` (dev check), `transport/live_view.js`.

### 4 Wiring and test support

- `AshDataTable` (`lib/ash_data_table.ex`): `table/1`, `attach/4`, `detach/2`, `attached/1`, the commands, the colocated hooks.
- `Router` (`router.ex`), `Live.Page` (`live/page.ex`), `Live.Embedded` (`live/embedded.ex`), `Live.Drawing` (`live/drawing.ex`): the router macro, its page, the tag's component, the drawing that calls the kit.
- `KitCase` (`kit_case.ex`), `Test.Resource` (`test/resource.ex`), `Test` (`test.ex`): public test help for a kit and a host.

## Safety rules

Every change keeps these; part 2a is where they live.

- **Read again as the person before every write.** The table keeps keys, not records (`Record.fetch/3`, `Pick.chosen/3`, inside `Operation`, after its checks and the veto).
- **Only `public?` actions run**, nested tables' and pickers' read actions included; the verifiers refuse others.
- **The reader options on every Ash call** (`scope`, `actor`, `tenant`, `authorize?`, via `Caller`). The table adds no rule of its own: it asks Ash.
- **Nothing sensitive reaches the browser before "Show".** A part draws only from `Present`; `reveal` sends one value, after a re-read.
- **Values from the browser are claims**: keys, names, page sizes and selections are looked up or read again; sort and filter go through `sort_input`/`filter_input`; no text becomes an atom.
- **An announcement is a claim**: a live update names a key only; the table reads it as the person (`Query.rows/4`, `Query.any?/5`).
- **A summary says no more than the rows** (`Query.summaries/4`).
- **No check can be skipped** by anything from the browser or any documented option. Order of a write: question → the table's checks → veto → the panel's files → re-read → action.

## Adding a feature

1. **DSL option**: in `resource/table.ex` (`@options`), `domain.ex`, or the entity in `resource.ex` and its struct. Then `mix spark.formatter` and `mix spark.cheat_sheets`.
2. **Diagnostic**: the rule and its `message/1` in the topic module; raised by that topic's verifier; listed in `documentation/topics/mistakes-at-compile-time.md`.
3. **Model**: into `Model` or a struct; what depends on the person in `for_actor/2`.
4. **Core**: a field of `Live.Entry` (in its topic's group, if it has one); an event in `Intent` and `@events` of `attrs.ex`; a `step` clause in its topic; socket work as an effect.
5. **Drawing**: what a part draws in its `Kit.Projection` key and moduledoc; markup in `Parts.*`; a new part is a `Kit` callback with its default in `Kit.Default`. Every kit (Default, the demo's DivKit and ReactKit) behaves the same; nested tables as top tables.
6. **Texts**: the key in `messages.ex`; the data layer says `{:text, key, bindings}`; `mix gettext.extract`; German in `demo/priv/gettext/de/`.
7. **Demo**: resources in `demo/lib/demo/`, routes in `demo/lib/demo_web/router.ex`, test-only tables in `demo/test/support/*_tables.ex`; a new page in `demo/README.md`.
8. **Tests**: root `test/` (model, 2a, `step_test.exs` per topic, `KitCase`); `demo/test/demo_web/tables/` through `DemoWeb.TablePage`; markup snapshots (`MIX_SNAPSHOT_UPDATE=1`); browser specs in `demo/e2e/` with the `Table` helper (Tab only, never a sleep).
9. **Guide**: one file in `documentation/topics/` (listed in `test/documentation_test.exs` and `mix.exs` extras; every code block has a `<!-- source: -->` or `<!-- sketch -->`); a rule for agents in `usage-rules.md` or `usage-rules/`.

## Commands

```sh
# root
mix format --check-formatted
mix compile --force --warnings-as-errors
mix test

# demo (Postgres: `docker compose up -d postgres` in the root)
cd demo
mix compile --force --warnings-as-errors
MIX_ENV=e2e mix compile --warnings-as-errors
mix test
mix phx.server                    # http://127.0.0.1:4478

# the hooks' JS
ASDF_NODEJS_VERSION=$(awk '/nodejs/{print $2}' demo/e2e/.tool-versions) npm run check

# browser tests (a server and database per worker, each test in its own transaction)
cd demo/e2e
ASDF_NODEJS_VERSION=$(awk '/nodejs/{print $2}' .tool-versions) npm test
./server.sh                       # single server on 4479; `npm run test:server -- editing`
```

The React islands use npm in `demo/assets` only (`mix assets.setup`); the library itself is npm-free.

Known traps:

- A file restored with the same modification time leaves a stale beam: `mix compile --force`.
- Never `pkill -f`/`pgrep -f` with a pattern matching your own command; stop servers by pid.
- The dev and e2e servers share `demo/priv/static/assets/`.
- A stale `_build/*/phoenix-colocated/ash_data_table/node_modules` link breaks esbuild: delete it or `mix clean`.
- Tailwind scans `lib/`, not `assets/js/`: a class the hooks set must also appear in `lib/` markup.
- shadcn's variables are renamed `--sh-*` (daisyUI's `--border` is a width).

## Where decisions live

- The specification: issue #21 of `StefanRoesch/ash_data_table`.
- The glossary: `CONTEXT.md`. Architecture decisions: `docs/adr/`.
- The screen-reader checklist: `docs/agents/tab-model-expert-check.md`.
