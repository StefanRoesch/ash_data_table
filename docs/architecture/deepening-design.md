# Deepening the modules: design note

Status: **proposed, 2026-10-20.** It shapes stage 9 of [target.md](target.md): the six candidates of the architecture review of 2026-10-20 (the report `architecture-review-20261020.html`, kept outside the repository), which the owner decided to build, all six, in the order below. Nothing is built yet. The open questions of section 12 need the owner's answer before stage 9a starts; target.md is amended only after the owner's yes (section 11 has the text). Code references are of `f73a98e` (the other agent's Credo commit `0b80206` moved some lines in `act.ex`, `bulk.ex`, `attrs.ex`, `kit.ex`, `parts/*.ex` by a few). Words follow `CONTEXT.md`. The model for this note is [react-kit-design.md](react-kit-design.md).

## 0. In one paragraph

Six places in the library hold one piece of knowledge spread over many modules: how a value made of fields travels in a form, how the grid's columns and rows are numbered, what the action panel is and does, who draws what opens (the table or the host), what each part is given to draw, and how the live core is tested. Each stage gives that knowledge one deep module with a small interface, moves the callers onto it, and moves the tests onto its interface. The table does not change for a person: the markup, the events, the wire and the safety order stay as they are, and every stage keeps the byte budget. At the end every kit only draws (a finished projection per part, a new ADR 0004), `Live.Entry` and `ReactKit.Props` are small, and the live core is testable in the root suite.

## 1. The owner's decisions (2026-10-20)

| # | Decision |
| --- | --- |
| E1 | All six candidates are built, each its own stage, in this order: 9a = 6a, 9b = 3, 9c = 4, 9d = 2, 9e = 5, 9f = 1, 9g = 6b |
| E2 | Each stage R-style: build → the builder's check against this note → independent drift check → one fix-up → the full suites once. The quality gate (`mix check` root and demo, the npm tools) once, at the end of stage 9 |
| E3 | The kit contract goes to **6** once, for the whole refactor |
| E4 | 9f comes with ADR 0004 "every part gets a finished projection"; it is drafted here (section 9) and written as a file at build time, after the owner's yes |
| E5 | 9g is sized again after 9d and 9e; this note says how big it still is and what it would take |
| E6 | The deferred parts of #56 (the 79 fields of `Live.Entry`) and #57 (the 10–18 parameters of `ReactKit.Props`) are absorbed by these stages (section 10) |

## 2. Goal and non-goals

**Goal.** For each piece of knowledge: one module owns it, its interface is small, its callers ask it, its tests test it through that interface. Locality (a fix is made once) and leverage (every kit, the host and the tests get it).

**Non-goals.**

- No change a person sees: markup, keyboard, ARIA, texts, events, replies and pushes stay. The markup snapshots differ in nothing in every stage (a reviewed exception is a finding of the drift check).
- No change of the safety order (`Operation`: checks → veto → re-read → action), of `Present` as the one way from the core's data to a part (scrubbed first), or of "the server holds no rows".
- No new public extension point beyond the kit contract (no host-made opener, no host-made panel kind).
- No compat code: callers move, tests included; old functions are deleted in the same stage.
- No npm in the library; no dependency internals (no `__xxx__`, no `@doc false` functions of deps, no undocumented markup or wire protocol, no `Map.put` on assigns).

## 3. Words used here

As in the codebase-design vocabulary: a **module** has an **interface** (everything a caller must know: functions, shapes, invariants, errors) and an implementation. **Depth** is how much behaviour a caller gets per piece of interface. A **seam** is where an interface lives; an **adapter** fills a seam (two adapters make a real seam, one a hypothetical one). **Leverage** is what callers gain, **locality** what maintainers gain. Domain words (part, kit, bundle, action panel, request, controlled mode, group, projection) are `CONTEXT.md`'s.

## 4. What the review found, with evidence

| Stage | Knowledge | Where it is today (`f73a98e`) |
| --- | --- | --- |
| 9a | Testing the live core | `Live.*` is tested only by the demo (about 95 test files); root coverage 58.15 % (first quality run). `KitCase` is in `lib/` (1,415 lines) but runs only in the demo (`demo/test/demo_web/kits/default_kit_test.exs:6`, `DemoWeb.Endpoint`); the root has an endpoint already (`test/support/live_host.ex:13`) |
| 9b | The group value: `_present`, `_union_type`, `_union_value`, `_of`, item numbers, `phx-value-path`, `-f-NAME` ids | made in `act.ex:764-765`, `848`, `857`, `864-879`, `895` (`sent`, `blank`), read in `act.ex:791-794`, `832` (`kind`, `items`), `729-776` (`typed`); `typed.ex:68-69`; `zone.ex:174-184`; `present.ex:421-426` (`in_union?`); `live/core/panel.ex:458-518` (`regroup`, which also builds the focus id's `"f", name` segments that `kit.ex:1328` builds as `-f-NAME`); `kit.ex:1251-1343` (`within`, `members`, `"#{name}[_union_value]"`); `kit/words.ex:422-439` (`group_items`); `attrs.ex:1706` (`phx-value-path`), `intent.ex:172`; written by hand in `parts/panel.ex:668`, `767-773`, `807` and in the React kit's `Panel.tsx:449`, `528`, `572-576` |
| 9c | Grid geometry: `lead`, `colcount`, `colindex`, `rowindex`, header rows, the summary row | `live/core.ex:316-340`, `795` (`editing?`, `acting?`, `label_column`, `lead` put into the entry); `present.ex:172-191` (`filter_row?`, `header_rows`, `first_row`); `live/core/reading.ex:309`; `attrs.ex:1004-1028` (`table/8`, `colcount/3`), `1215`, `1414`; `parts/common.ex:58-67` (`trail`, `colindex`, `summary_rowindex`); `Attrs` ↔ `Parts.Common` call each other (`attrs.ex:887`, `common.ex:11`); `Attrs.colcount/3` is called in 11 places, 4 of them in `ReactKit.Props`, 3 in `DivKit`; the hooks read `data-lead` and renumber `aria-rowindex` (`assets/js/grid/focus.js:22`, `65`) |
| 9d | The action panel | 934 lines in `live/core/panel.ex` (16 `on/2` clauses, `submitted/3` per kind at `668-701`); the panel map is built in six places with its `kind`: `cells.ex:97` (`:cell`), `bulk.ex:224` (`:bulk`), `reading.ex:740` (`:filter`), `panel.ex:66` (`:table`), `243` (`:create`), `546` (`:row`); what is in it is worked out in `Act` (1,148 lines: `gaps` `672`, `typed` `729`, `errors` `940`, `places` `1135`); it is changed from `files.ex`, `picker.ex:48`, `370`, `439`; `Core.Panel`, `Cells`, `Bulk` and `Requests` call each other in a circle (`requests.ex:51-56`, `237-267`) |
| 9e | Who draws what opens | `controlled?`/`host?`/`ask`/`ask_cell` branches: `bulk.ex:135-137`, `cells.ex:28`, `44`, `172`, `panel.ex:78-79`, `276-277`, `picker.ex:301-304`, `nesting.ex:311`, `requests.ex:134-135`; in the drawing `hosted?`, `panel?`, `picker?` (`drawing.ex:606-643`); the review counted about 19 |
| 9f | What a part is given | put together in four places: `Live.Drawing` (`Kit.arguments` `133`, `Kit.editors` `338`, `Kit.fields` `481`, `open_panel/4` four times `479-490`, and Kit.Default internals: `Parts.Pagination.pages?` `328`, `359`, `Parts.Messages.messages` `347`, `Parts.Filter.shown_filter` `657`), `Kit.Words` (563 lines, 21 clauses), `Kit.fields/arguments/editors` (`kit.ex:1136-1367`), and the parts themselves (`parts/grid.ex` 16 `Words.` calls, `summary.ex` 10). The busy rule `busy? or not is_nil(running)` is written in three kits (`parts/grid.ex:829`, `div_kit.ex:35`, `props.ex:37-49`); the panel form's bundle has no `Attrs` function and is written by hand twice (`parts/panel.ex:51-52`, `props.ex:804-806`), as are `clear_filter`, `read_again`, `clear_filters`, `pick_input` (`props.ex:164-166`, `645-655`, `854-856`); `ReactKit.Props` is 977 lines with parameters of arity 10–18 (#57); `Event.request/1` makes a fourth projection of the panel for `requests/1` (`event.ex:201-264`) |
| 9g | The core over the socket | 5,486 lines in `live/core.ex` and `live/core/*.ex`, 48 `on/2` clauses, 901 lines that name `socket`; LiveView calls: `push_event` 8, `send` 8, `assign` 8, stream calls 7, `start_async` 5, uploads 4, `push_patch` 1, `send_update` 1, `cancel_async` 1 |

Looked at and not taken (the review): `Model` ↔ `Query` (deep already; ADR 0001 stands); the mirrored lists of JS and Elixir (markers, ids, owned, events), each guarded by a drift test.

## 5. How every stage is built

- **R-style** (E2): the builder builds, checks against this note, then an independent drift check (this note and target.md: modules, dependency rules of target §5.1, safety, only the agreed tests changed, nothing extra, nothing left out), one fix-up, then the three suites once (root, demo, browser with both Playwright projects). During a stage only `mix test --stale` and the named spec files.
- **Measurements**, each stage, as R3–R5 did: `demo/perf/baseline.mjs`, `PERF_WIRE=1`, 15 repetitions, two temporary worktrees (A the stage's start, B its end), run A, B, B, A per page, `/tasks` and `/react/tasks`, the mean of each pair's medians, the load written down. Gate: bytes per action within 2 % on `/tasks` (question 2), times within 20 %. Actions: page change, cell save, select a row, open a nested table, open the picker, open the panel (modal and inline).
- **Tests**: the new module's interface is the test surface. Root tests that tested the old pieces are **replaced** by tests of the new interface, not kept beside them. The demo's LiveView tests and the browser suite stay as they are: they are the behaviour net that tells the stage changed nothing (question 5).
- **Kit contract 6** (E3, question 1): opened in 9b, the first stage that changes a part's assigns; 9c and 9f add to it; no other number. `Kit.changed/1` says per step what changed.
- **Placement**: a new file goes in the directory of its part (target §5.5); `test/architecture_test.exs` places it. `docs/agents/architecture.md` is corrected where a stage made it false; guides only where a public shape changed (the kit guide in 9b, 9c, 9f; the controlled-mode guide not at all).
- **Greenfield**: no delegate, no alias module, no old function kept for a test.

## 6. Stages 9a to 9c

### 9a. `KitCase` with `Kit.Default` in the root suite

**Shape.** No new module. `KitCase` runs with `kit: AshDataTable.Kit.Default, endpoint: AshDataTable.Test.LiveHost.Endpoint` in `test/kit/default_kit_test.exs` (question 6). `LiveHost.start/0` already starts that endpoint; `KitCase.Live` is mounted with `live_isolated/3`, which needs no router; the state `links` uses `render_component/2`. `AshDataTable.Test.Resource` is in `lib/`, in ETS, so the root has all it needs.

**Tests.** Moved: `demo/test/demo_web/kits/default_kit_test.exs` → `test/kit/default_kit_test.exs`; `demo/test/demo_web/kits/kit_case_seeds_test.exs` → `test/kit/kit_case_seeds_test.exs` (it tests `KitCase.given/4` and `clean/1`, library code; question 7). Deleted from the demo, not kept twice. `DivKit` and `ReactKit` keep running `KitCase` in the demo (they live there).

**Kits.** None change.

**Risks.** Something of the demo was used without being named (an endpoint config, Gettext's backend, `pub_sub`): it shows as a failure on the first run and is put into `LiveHost.start/0`, nothing else. A slower root suite (20 states × 4 presentations): measured.

**Measurements.** Root suite time and coverage before and after (`mix test --cover`), once each. No perf run (no library change).

**Done when.** The root suite runs `KitCase` for `Kit.Default`, green; the demo no longer does; root coverage is reported (no threshold, question 8); `KitCase`'s moduledoc and the architecture map say where it runs.

### 9b. One owner of the group value

**Shape.** A new module `AshDataTable.GroupValue` (2a, `lib/ash_data_table/group_value.ex`, internal; question 9). It owns how a value made of fields (a map cell, a list of maps, a union, and every nesting of them) travels: into a form, back from it, and inside the panel's buttons and focus. Its interface, in words: give it an input (a `Model.Input` or `Model.Field`) and a value, or what a form sent, and it answers with the other side.

```elixir
held(input, value, zone)            :: map | nil        # what the form holds for a value (today Act.sent/blank, Typed's union part)
blank(input, zone)                  :: map              # a new, empty group
taken(input, sent, zone)            :: term             # what the action is given (today Act.typed/kind)
kind(input, sent, zone)             :: {Field.t(), term} | nil
items(held)                         :: [{key, item}]    # the list's items in their order, by number
change(input, held, path, :add | :remove, zone)
                                    :: {:ok, held, focus_path} | :error   # today Core.Panel.regroup
name(parent_name, step)             :: String.t()       # "x[_union_value]", "x[0]", "x[city]"
hidden(input, name, held)           :: [bundle]         # the hidden entries: _present, _of, …
path_value(path) / path(sent)       :: String.t() / {:ok, [String.t()]} | :error   # phx-value-path both ways
touched?(touched, path)             :: boolean          # today Present.in_union?
walk(input, held, fun)              :: held             # for Zone's gaps in a union
```

Behind it: the four wire names (unchanged, question 10), the item numbering, the path of names a button sends, and the id segments of a field inside a group, which it turns into ids only through `Ids.field/2` (the one maker of that id, target §6). A path from the browser stays a claim: `change/5` follows it through the input's fields and nothing else, as `regroup` does.

Who loses what: `Act` loses `sent`, `blank`, `typed`, `kind`, `items`, `fresh` (it asks `GroupValue`); `Core.Panel` loses `regroup/5`; `Kit` loses the naming inside `within`/`members` (it asks `name/2` and `hidden/3`); `Kit.Words.group_items` asks `items/1`; `Present.in_union?/2` goes; `Typed` keeps the text of one value and asks `held/3` for a group; `Zone` keeps its time rule and asks `walk/3`; `Attrs.add_group/3`, `remove_group/3` ask `path_value/1`, `Intent` asks `path/1`.

**Kits.** A field's assigns gain `hidden` (a list of bundles, question 11); the kit spreads each on an `<input type="hidden">`. `parts/panel.ex` stops writing `_present` and `_union_type` names by hand (`668`, `773`, `807`); `Panel.tsx` the same (`449`, `528`, `576`), through `Attrs.props/1`'s rule; `ReactKit.Props.panel` passes them on. `DivKit` draws no panel: unchanged. Kit contract 6 opens (question 1).

**Tests.** New `test/group_value_test.exs`: round trips (`held` → what a browser sends → `taken`) for a map, a list of maps, a union of one value, a union of a map, a union inside a list of maps, a map inside a union; numbering after a remove and an add; `change/5` with a forged path (`:error`); `hidden/3` for each shape; `path_value`/`path` both ways. Replaced: the tests of `test/unions_test.exs` "what the editor of a union holds" and "what a union's field gives the action" become `GroupValue` tests; in `test/kit_test.exs` the assertions on `members` names (`590-604`) keep only what the part is given. The demo's `map_table_test.exs`, `union_table_test.exs`, `specimen_union_test.exs`, `tracker_maps_test.exs` and `maps.spec.ts`, `unions.spec.ts` stay unchanged and must pass.

**Risks.** A name or id built in one more place nobody listed: the drift check greps `lib/`, `demo/lib/`, `demo/assets/islands/` for the four names and `-f-`; only `GroupValue` and the moduledocs may hold them. A union inside a list behaves differently after the move: the round trips cover it.

**Measurements.** Snapshots identical (`07a-site-map-panel`, `07b-site-groups-panel`, `07c-specimen-union-panel` above all). Perf: the standard run; "open the panel" is the action that touches it.

**Done when.** The grep above finds the names only in `GroupValue` (and docs); the round-trip tests pass; snapshots unchanged; bytes within 2 %; the kit guide says what `hidden` is.

### 9c. One grid geometry value per table

**Shape.** A new struct and module `AshDataTable.Geometry` (2a, `lib/ash_data_table/geometry.ex`, public struct, functions internal; question 12). One value per table, made once where `lead` and `acting?` are made today (`Live.Core`, as the model or `select` changes) and kept in one entry field `geometry` (question 14).

```elixir
of(model, selecting, expandable?, open_label) :: Geometry.t()
# %Geometry{lead: 0..2, trail: 0 | 1, columns: n, colcount: n, header_rows: 1 | 2, summary?: boolean}
colindex(g, index)          :: pos_integer        # a data column's aria-colindex
first_row(g, page)          :: pos_integer        # aria-rowindex of the page's first record
rowindex(g, page, n)        :: pos_integer
rowcount(g, page)           :: pos_integer | nil  # aria-rowcount
summary_row(g, page)        :: pos_integer | nil
```

Behind it: what is before the first data column (box, expander), after the last (actions), how many header rows (filter row or not), where the footer row stands. `Attrs.table/8` and `Attrs.spanning/3` take the geometry instead of `model, lead, acting?`; `Attrs.colcount/3`, `Parts.Common.trail/1`, `colindex/2`, `summary_rowindex/2`, `Present.filter_row?/1`, `header_rows/1`, `first_row/2` and `Attrs.filter_row?/1` go. That removes the `Attrs` ↔ `Parts.Common` cycle (`Common` keeps `root`, `failure` and `dynamic_component`, and calls `Attrs` only). `Core.Reading` counts a row's index with `rowindex/3`.

`Live.Entry` loses `lead` and `acting?` (into `geometry`), `editing?` and `label_column` (into `Model`, set by `Model.for_actor/2`: facts of the person's model; question 13). Net: 4 fields out, 1 in.

**JS mirror.** `assets/js/geometry.js` (public, as `ids.js`): `lead(grid)`, `colindex(index, lead)`, `firstRow(grid)`, `rowindex(first, n)`, which `focus.js` and `shared.js` use instead of their own counting. The data attributes the hooks read stay as they are (`data-lead`, `data-first-row`, `aria-colindex`, `aria-rowindex`; question 15). Compared like `ids.js`: `/e2e/ids` gains a sample of each function, `contract.spec.ts` compares.

**Kits.** Contract 6: the parts `grid`, `row`, `actions_cell`, `footer`, `summary_cell`, `full_view`, `related` get `geometry` instead of `lead`, `acting?`; `label_column`, `editing?` are read from `model`. `Kit.Default`, `DivKit` (3 `colcount` calls), `ReactKit.Props` (`table`, `row`, `footer` lose 2–3 parameters each), `Grid.tsx` if it counts.

**Tests.** New `test/geometry_test.exs`: every combination of box, expander, actions, filter row and summary row, a page with and without an offset and a total. Replaced: the geometry assertions of `test/present_test.exs` and `test/attrs_test.exs`; `KitCase` already checks `aria-colindex` and `aria-rowindex` on every page and stays.

**Risks.** A number off by one in a rare shape (a picker's table with `choose` and no box, a nested table with a summary row): the test table covers each; `KitCase` and `tab_order.spec.ts` would see it.

**Measurements.** Snapshots identical. Standard perf run.

**Done when.** No module but `Geometry` (and `geometry.js`) counts a column or a row; `mix xref graph --format cycles` shows no `Attrs`/`Common` cycle; the four fields are gone from `Live.Entry`; the contract spec compares `geometry.js`.

## 7. Stages 9d and 9e

### 9d. The action panel as one module

**Shape.** A new module `AshDataTable.Panel` (2a, `lib/ash_data_table/panel.ex`; question 16): the open panel as one value with a closed set of kinds, and everything about its life. No socket; uploads stay in 2b (`Live.Core.Files`, target §6: the action runs inside the upload's consume).

```elixir
@type kind :: :cell | :bulk | :filter | :table | :create | :row
open(kind, for, model, opts)        :: {:ok, Panel.t()} | {:error, message} | :refused
validate(panel, typed)              :: Panel.t()      # values, typed, gaps, errors, places, used
change(panel, path, :add | :remove) :: {:ok, Panel.t(), focus_path} | :error   # through GroupValue
clear(panel, name) / keep(panel, name)
hold(panel, input, keys)            :: Panel.t()      # a choice made in the picker
submission(panel, typed, files_fun) :: Operation.Input.t()   # what Operation.submit/1 runs
outcome(panel, result)              :: {:closed, done} | {:open, Panel.t()}       # per kind
spend(panel, refs)                  :: Panel.t()
```

`%Panel{kind, for, form, inputs, values, typed, groups, used, cleared, errors, places, title, submit, time_zone, spent}`: `for` holds what the kind is about (a row's key, an action, a column, the selection's token). Function heads match on `kind` only inside `Panel` (question 17).

Behind it: building the form through `Act` (which keeps every call of AshPhoenix and Ash: `open_*`, `run*`, `submit_*`), what is in the form (`Act`'s `values`, `gaps`, `errors`, `places`, `unchosen`, `clearable`, `unchanged?` move here; question 18), the group changes (`GroupValue`), what a submission is per kind and what its outcome means. `Present.panel/2` is made from a `Panel.t()`.

Who loses what: `Core.Cells`, `Core.Bulk`, `Core.Reading` (filter values) and `Core.Panel` (table, create, row) only call `Panel.open/4` and put the result; `Core.Panel` shrinks to the 2b adapter: an intent of the panel's events → a `Panel` function → `Core.put/2`, `Files`, `Notify`, focus. `Core.Picker` calls `Panel.hold/3`. `Act` goes back to running actions. `Live.Entry` loses `spent` (into the open panel: the uploads given while it was open) and `running_files` (into the run, `entry.running.files`; question 19).

**The `Requests` cycle.** `Requests.answer/4` no longer calls `Panel.on`, `Bulk.on`, `Cells.write` (`requests.ex:237-267`): it gives back the intent the answer stands for, and `Live.Core` runs it through `topic/1` as it runs a browser's intent (question 20). One way for both; the cycle goes.

**Kits.** None (the part's assigns are made by `Present.panel/2` as before).

**Tests.** New `test/panel_test.exs`, per kind: open (refused, forbidden, with page arguments), validate (gaps of a wall time, errors at fields, places), a group add and remove, clear and keep of a sensitive field, a submission's `Operation.Input` (no sensitive value in it but what was typed in this panel), the outcome. Replaced: the `Act` tests of what is in a form (in `test/operation_test.exs`, `test/unions_test.exs`, `test/files_test.exs` where they call `Act.errors`, `places`, `gaps`); `test/present_test.exs` "the action panel" builds its panel with `Panel.open/4`. The demo's panel tests (`action_fields_test`, `validation_display_test`, `task_create_test`, `table_actions_test`, `task_bulk_test`, `filter_values_test`, `file_actions_test`, the controlled tests) and the browser specs stay unchanged.

**Risks.** The panel's life has many small rules (a new read closes it; a live update under it; a question asked from it; files given and then refused). Each rule gets a test in `panel_test.exs` or stays covered by its demo test; the drift check lists every `Core.put(panel: …)` left outside `Core.Panel` (none allowed). `spent` after the panel closes: the builder checks first whether LiveView still needs it; if so it stays with the run (question 19).

**Measurements.** Snapshots identical. Perf: standard run, "open the panel" both presentations. The time of `handle_event:panel_validate` from the probe (no more than 20 % slower).

**Done when.** The panel's kinds are matched only in `Panel`; `Act` has no function about what a form shows; `mix xref graph --format cycles` shows no cycle among `Core.Panel`, `Cells`, `Bulk`, `Requests`; `spent` and `running_files` are gone from `Live.Entry`; #56 closed (section 10).

### 9e. Controlled mode as the opener seam

**Shape.** A seam "who draws what opens", inside 2b: `AshDataTable.Live.Core.Opener` (an internal behaviour) with two adapters, `Opener.Table` (the table draws it: the default, uncontrolled) and `Opener.Host` (the page draws it: controlled mode, today's `Requests`). The adapter is chosen per kind from `options.controlled` (`:confirm`, `:panel`, `:picker`), once, by `Opener.for(table, kind)` (question 21).

```elixir
ask(socket, intent, question, for)  :: {:run, socket} | {:held, reply, socket}   # a question before a write
opened(socket, kind, value)         :: socket          # a panel or picker was opened
closed(socket, kind)                :: socket
answer(socket, ref, answer)         :: {:ok, intent, socket} | :none              # Host only; Table: :none
draws?(options, kind)               :: boolean         # what the drawing asks
```

Behind `Opener.Host`: the request (`entry.request`, which stays one field of the entry, owned by this adapter only; question 22), its `ref`, `follow/1` in `tidy/1`, `:requested` and `:request_ended`, `answered/5` (`ash_data_table:answered`), `projections/1` for `requests/1`. Behind `Opener.Table`: nothing is held; the question was asked by the hook before the event came (`confirmed?`), the panel and picker are drawn.

Who loses what: the about 19 branches of section 4 become one call each (`Opener.ask/4`, `Opener.opened/3`); `Live.Drawing` loses `hosted?/2`, `panel?/2`, `picker?/2` and asks `Opener.draws?/2`; `Nesting` asks it whether a picker's table is read. `Core.Requests` becomes `Opener.Host` (moved, not wrapped). The public API (`attach(…, controlled: …)`, `requests/1`, the `*_request` commands) does not change in this stage (question 23).

**Kits.** None.

**Tests.** New `test/opener_test.exs` on `LiveHost.run/1`: the same table of cases for both adapters (a cell's question, an action's, a bulk run's, a panel, a picker, nested and picker tables, a stale `ref`, a `ref` of another kind), each adapter giving its own answer. Replaced: none in the root (there were none); the demo's `controlled_test`, `controlled_widened_test`, `controlled_nested_test`, `controlled_policies_test` and `controlled.spec.ts` stay unchanged.

**Risks.** A branch that does more than ask "who draws": a few differ in what runs after (a cell's `{held: true, ref}` reply, the bulk token held in the request). `ask/4`'s answer carries that; the drift check reads every former branch.

**Measurements.** Snapshots identical. Perf standard run (the default kit is uncontrolled; nothing should move).

**Done when.** No module but `Opener` and its two adapters reads `options.controlled`; the drawing has no `hosted?`; both adapters pass the same case table.

## 8. Stages 9f and 9g

### 9f. A finished projection per part, for every kit

**Shape.** A new module `AshDataTable.Kit.Projection` (part 3, `lib/ash_data_table/kit/projection.ex`, with one module per outer part in `kit/projection/`; question 24): what each part is given to draw, as plain data, finished. One entry:

```elixir
Projection.of(part, inputs) :: map
# part: :heading | :selection_line | :status | :grid | :message | :pagination | :confirm
#       | :panel | :picker | :related | :full_view   (the outer parts; question 25)
# inputs: the entry fields that part depends on, given one by one by the drawing
```

A projection holds: **values** (already looked up: a column's label, type, whether it sorts, its filter's shown value), **texts** and **messages** (finished, the words of `Kit.Words` today), **bundles** (every element's, the panel form's and the hand-written ones of section 4 included, from `Attrs`), **derived facts** (`busy?` = `busy? or running`, `pages?`, the shown messages, the filter values, the geometry's numbers per column, `hidden` of 9b), and the projections of the parts inside it (a grid's header cells, filter cells, editors; a panel's fields; question 25). It never holds a record, a form, a `Model`, a `State` or a `Present` struct (question 26). Rows stay the stream of `AshDataTable.Item` (ADR 0002), handed on unchanged.

Behind it: `Kit.Words` (deleted, folded in), `Kit.fields/3`, `Kit.arguments/5`, `Kit.editors/1` (deleted, folded in), the derived rules that `Parts.Pagination.pages?/2`, `Parts.Messages.messages/4`, `Parts.Filter.shown_filter/4` hold today (moved out of `Kit.Default`), the `Words.` calls inside the parts. `Present` stays the one way from the core's data (it is called by the projection and scrubs first); `Item` stays 3w.

**Change tracking.** The drawing passes each projection's inputs field by field, as now, so LiveView re-renders a part only when something it depends on changes. Whether a part can then be given its projection as one assign (`projection={Projection.of(:pagination, …)}`) without sending more bytes, or needs one attribute per top-level key, is the first thing the stage tries, measured (question 27).

**Kits.** Every kit only draws.

- `Kit.Default`: each part reads its projection; no `Words.`, `Attrs.colcount`, `pages?`, busy rule left in `parts/`.
- `DivKit`: the same for its grid parts.
- `ReactKit`: `DemoWeb.ReactKit.Props` (977 lines) shrinks to the bundle → props rule (`Attrs.props/1`, without `phx-hook`, `phx-update`, `phx-mounted`) over a projection, one function per part of one parameter; folded into `ReactKit` if it is then small (question 28). The TSX reads the same shapes; the hand-written bundles and the busy rule go from the TSX too.
- The host in controlled mode: `requests/1` builds a panel request's fields from the same panel projection, without bundles, in its own envelope (`ref`, `kind`, `table`, `path`; question 29).

Kit contract 6 is completed here: the moduledoc of `Kit` lists each part's projection (the shapes, as `Item`'s moduledoc does); `use AshDataTable.Kit, contract: 6`; `Kit.changed/1` says what changed from 5.

**Tests.** New `test/kit/projection_test.exs`: per part, the keys of its projection against the moduledoc both ways (as `item_test.exs`), that it encodes to JSON, that it holds no `Test.Resource.secret/0`, and its derived facts (busy, pages, shown messages, filter values). Replaced: `test/kit_test.exs`'s comparison of the struct fields of contract 5 (`Present.Panel`, `.Field`, `.Picker`, `Model`, `State`, `Query.Page`) with the moduledoc; the `Kit.Words` tests (`names/1`, the texts of each part) become projection tests; `KitCase` checks a part's assigns against its projection's shape instead of `Kit.Words.names/1` (`given!/2`). Kept: `KitCase` for the three kits, the markup snapshots, `react_kit_test.exs` (rewritten to the new props, the same assertions), the browser suite both projects.

**Risks.** (1) Bytes: one projection per part may send more than single attributes; the spike decides (question 27). (2) A host's kit loses access to the raw model and state: the projection must hold every fact a part needs; a kit that needs more asks for a key, which is a contract change (section 9). (3) The grid's projection is large; its header and editor parts are drawn once per table, the rows are not in it. (4) The React kit's props change shape while #60 types them: #60's types are adapted in place here, not kept beside.

**Measurements.** Both pages, every action; the gate is `/tasks` within 2 %; `/react/tasks` reported and flagged above 5 % (question 2). M2 of the React note again: the JSON of one page's props, before and after (reported).

**Done when.** No kit computes a text, a bundle or a derived fact (grep: no `Words.`, `Text.`, `Format.`, `Attrs.colcount`, `busy? or`, `"phx-` literal in `parts/`, `div_kit.ex`, `react_kit*`; `Attrs.` only as the props rule); `Kit.Words` and `Kit.fields/arguments/editors` are gone; ADR 0004 is written; `Props` has no function of more than 2 parameters (#57 closed); snapshots identical; bytes within 2 %.

### 9g. The core's step as (Table, intent) → (Table, effects)

**Shape, if built.** `Live.Core.step(table, intent, context) :: {table, [effect], reply}` for every intent, a pure function over `AshDataTable.Table`; `context` holds what the socket gives today (the page values, the uploads LiveView knows, the stream names). The socket becomes a thin adapter (`Live.Core` applying effects): `{:push, event, payload}`, `{:async, key, fun}`, `{:cancel, key}`, `{:stream, op}` (insert, delete, reset), `{:uploads, op}` (allow, disallow, cancel), `{:tell, message}` (the events to `self()`), `{:relay, …}` (the listener), `{:patch, url}`. An upload's consume, inside which the action must run (target §6), is an effect whose result comes back as an internal intent (`{:consumed, result}`), the way an async result does today.

**How big it still is** (estimate now; measured again at the checkpoint, question 30). After 9d and 9e the panel's and the opener's logic are socket-free, so what is left is the topic modules' plumbing: about 48 `on/2` clauses and their helpers change their signature from socket to table; about 900 lines name `socket` today, of which perhaps a third go with 9d and 9e. What still needs work of its own: streams (7 calls), async reads, summaries and bulk runs (5), uploads (4 and the consume), the URL (`push_patch`), the listener's relay, `Registry.within/3` (which checks an entry out of the socket's table). Estimate: 8–12 days, against 5–6 for 9d and 2–3 for 9e.

**What it would take.** Every `Core.put/2` becomes a change of the `Table` value; `Core.table/1` goes; `Live.Entry`'s fields that are LiveView's (stream name, upload names) are read from `context`; `#55`'s opaque-`Table.t` warnings (`hooks.ex:109`, `core.ex:210`) go with it. Tests: a root test per topic over `step/3` with no LiveView (the interface is the test surface), replacing the `LiveHost.run/1` tests of 9e; the demo's tests stay.

**Done when (if built).** No topic module mentions `Phoenix.LiveView` or `socket`; every `on/2` is a clause of `step/3`; the root tests reach the topics without LiveView; times of the callbacks within 20 %.

## 9. ADR 0004 (draft)

> **Every part gets a finished projection, for every kit**
>
> A part of a table was given its inputs in four layers: the drawing picked entry fields, `Kit.Words` made the texts, `Kit.fields/arguments/editors` made some values, and each kit finished the rest itself (the busy rule in three kits, the panel form's bundle by hand twice, `ReactKit.Props` with 10 to 18 parameters per part). ADR 0002 had done the same step for the rows. We decided (owner, 2026-10-20) that every part is given one finished, plain-data projection, made by the library (`AshDataTable.Kit.Projection`): its values, its finished texts and messages, its bundles and the facts derived from them. Every kit only draws: `Kit.Default`, the demo's `DivKit` and `ReactKit`, and every host's kit.
>
> **Considered options.** *Keep the four layers and document them*: rejected, every kit keeps rebuilding the same facts and they drift. *A projection only for kits that draw in the browser*: rejected, two ways, and the HEEx kit keeps a way the others do not test (the reason of ADR 0002). *Send the model and state and let a JS library derive*: rejected, the words and the rules would live twice.
>
> **Consequences.** One place per text, bundle and rule. A kit no longer reads `Model`, `State` or `Present` structs: what a part may draw is the projection's keys, and a missing fact is a contract change. LiveView's change tracking stays per part: the drawing gives each projection's inputs one by one. Every projection is JSON-safe. Kit contract 6. `Kit.Words` and `Kit.fields/arguments/editors` are gone. Reversing it means giving kits the structs again.

## 10. Tickets

- **#56 (Credo; the 79 fields of `Live.Entry`).** 9c takes out 4 fields and puts in 1, 9d takes out 2 more: 74 are left, still above 32. **Closed by 9d**, as question 31 decides (➡️ the one-line reason in the module, the cost measured). The other agent's commit `0b80206` left this part open on purpose.
- **#57 (Credo, demo; `Props`' arity 10–18).** 9c shortens `table`, `row`, `footer`; **closed by 9f** (one projection per function).
- **#59 (jscpd).** The clone `Heading.tsx:170-178` / `Panel.tsx:321-327` is hand-written bundle code that 9f removes, if #59 has not already; `mounting.tsx` and `panel.js`/`picker.js` are #59's alone.
- **#60 (ESLint).** The `any`s and props types it fixes change shape in 9f: 9f adapts them in place.
- **#55 (Dialyzer).** The opaque `Table.t` findings are fixed by #55 now; 9g changes the same code again. The `Format.format/3` spec is not touched by this note.
- **#61 (unused code).** `Messages.key?/1` and the other two are #61's; 9f deletes `Kit.Words` and `Kit.fields/arguments/editors` itself, which must leave no caller.
- **#58, #63, #64.** Untouched by this note.

## 11. Proposed amendment to target.md

Added to target.md after the owner's yes (2026-10-20):

> ### Stage 9: deepening the modules (D-deepen)
>
> Shaped in [deepening-design.md](deepening-design.md) (the architecture review of 2026-10-20; owner, 2026-10-20: all six candidates, in this order). Each stage R-style with its own drift check and its own single run of the suites; bytes within 2 % on `/tasks`, times within 20 %; kit contract 6 once; the quality gate once at the end.
>
> - [ ] 9a, `KitCase` with `Kit.Default` in the root suite on `AshDataTable.Test.LiveHost`.
> - [ ] 9b, `AshDataTable.GroupValue`: the group value's encoding both ways, one owner; kits get the hidden entries as bundles; contract 6 opens.
> - [ ] 9c, `AshDataTable.Geometry` and `assets/js/geometry.js`: one grid geometry value per table; the `Attrs` ↔ `Parts.Common` cycle goes; `lead`, `acting?`, `editing?`, `label_column` leave `Live.Entry`.
> - [ ] 9d, `AshDataTable.Panel`: the action panel with a closed set of kinds; `Act` runs actions only; `spent`, `running_files` leave `Live.Entry`; the `Requests` cycle goes; #56 closed.
> - [ ] 9e, `Live.Core.Opener` with the table's and the host's adapters, replacing the inline `controlled?` branches and the drawing's `hosted?`.
> - [ ] 9f, `AshDataTable.Kit.Projection`: a finished projection per part, `Kit.Words` and `Kit.fields/arguments/editors` folded in; every kit only draws; ADR 0004; #57 closed.
> - [ ] 9g, the core's step as (Table, intent) → (Table, effects), as sized again at its checkpoint.

§4 (module matrix) and §6 (`Present` stays no seam; `GroupValue` ↔ the hidden inputs, `Geometry` ↔ `geometry.js` as kept couplings) are amended by each stage as it is built.

## 12. Open questions for the owner

**Answered by the owner 2026-10-20: all 33 as recommended** ("as recommended, proceed"). Stage 9 is in target.md.

Every decision a builder would otherwise take. ➡️ is the recommendation.

1. **When the kit contract becomes 6.** a) in 9b, the first stage that changes a part's assigns, 9c and 9f adding to it; b) only in 9f, with 9b and 9c changing contract 5 in place. ➡️ **a**: an old kit fails at `use` from the first change on; `Kit.changed/1` lists each stage's step.
2. **The byte gate.** a) 2 % on `/tasks` only, `/react/tasks` reported (flag above 5 %); b) 2 % on both pages; c) 2 % per stage and also 2 % from the start of 9a to the end. ➡️ **a**, with the sum from 9a's start reported after each stage and flagged above 4 %.
3. **The perf actions.** a) the six actions of R3–R5 as they are; b) add "add a group" and "validate the panel" to `baseline.mjs`. ➡️ **a**: the snapshots guard 9b's markup; 9d's validation time is read from the probe.
4. **Days.** 9a 0.5–1, 9b 3–4, 9c 2–3, 9d 3–4 (plus 2 for the tests), 9e 2–3, 9f 8–11, 9g 8–12 if built. a) accept; b) cut 9g now. ➡️ **a**, 9g decided at its checkpoint (question 30).
5. **Which tests are replaced.** a) root tests of the old pieces are replaced by tests of each new interface; the demo's LiveView tests and the browser suite stay unchanged as the behaviour net; b) also thin out demo tests that the new root tests now cover. ➡️ **a**: the demo tests are the proof that nothing changed; thinning them is a later decision.
6. **9a: where the default kit's `KitCase` runs.** a) only in the root (moved); b) in both. ➡️ **a**, greenfield: one place.
7. **9a: `kit_case_seeds_test.exs`.** a) moves to the root with it; b) stays in the demo. ➡️ **a**: it tests library code.
8. **9a: a coverage threshold.** a) none, the number reported; b) set one now. ➡️ **a**, until the end of stage 9.
9. **9b: name and place.** a) `AshDataTable.GroupValue`, 2a, internal (kits get its output as data, never call it); b) inside `Model` (`Model.GroupValue`); c) inside the panel module after 9d. ➡️ **a**: 2a is callable by 2b, 3 and 3w, and the panel needs it before 9d exists.
10. **9b: the wire names** `_present`, `_union_type`, `_union_value`, `_of`, `phx-value-path`, `-f-NAME`. a) unchanged; b) renamed while moving. ➡️ **a**: no wire change, snapshots identical.
11. **9b: hidden entries for kits.** a) bundles (attribute maps a kit spreads on `<input type="hidden">`); b) plain `%{name, value}` data. ➡️ **a**: the same rule as every other bundle, and the React kit's props rule applies.
12. **9c: `Geometry` public?** a) public struct with documented fields (a kit's own parts are given it), functions internal; b) all internal, kits get only numbers. ➡️ **a** until 9f, where the projection gives the numbers and the struct leaves the contract.
13. **9c: where `editing?` and `label_column` go.** a) fields of `Model`, set by `for_actor/2`; b) into `Geometry`; c) computed by each caller from the model. ➡️ **a**: they are facts of the person's model, not of the grid's shape.
14. **9c: geometry stored or computed.** a) one entry field `geometry`, made where `lead` is made today; b) computed in the drawing on each render. ➡️ **a**: change tracking compares one value.
15. **9c: the data attributes the hooks read.** a) unchanged (`data-lead`, `data-first-row`, the ARIA indexes); b) one `data-geometry` JSON attribute. ➡️ **a**: no markup change.
16. **9d: where the panel lives.** a) `AshDataTable.Panel` in 2a, `Live.Core.Panel` the thin 2b adapter; b) all in 2b, grown. ➡️ **a**: testable without LiveView, and the uploads stay in 2b.
17. **9d: one struct or one per kind.** a) one `%Panel{}` with a closed `kind` and a `for` map; b) one struct per kind. ➡️ **a**: one shape for `Present.panel/2` and the opener; the kind is matched only inside `Panel`.
18. **9d: what `Act` keeps.** a) every call of AshPhoenix and Ash (`open_*`, `run*`, `submit_*`, `from_page`, `given`); what a form shows (`values`, `gaps`, `errors`, `places`, `unchosen`, `clearable`, `unchanged?`) moves to `Panel`; b) `Act` keeps `errors` too. ➡️ **a**.
19. **9d: `spent` and `running_files`.** a) `spent` into the open panel, `running_files` into the run (`entry.running`); if `spent` is needed after the panel closes, it goes into the run too; b) both into one new uploads value of the entry. ➡️ **a**.
20. **9d: breaking the `Requests` cycle.** a) `Requests.answer/4` gives back the intent and `Live.Core` runs it through `topic/1`, as a browser's; b) a callback passed in. ➡️ **a**: one way for the browser and the host.
21. **9e: the seam.** a) an internal behaviour `Live.Core.Opener` with `Opener.Table` and `Opener.Host`, chosen per kind from `controlled`; b) one module with two clauses per function. ➡️ **a**: two real adapters, one shape, the same case table; no public extension point.
22. **9e: `entry.request`.** a) stays one entry field, owned by `Opener.Host` only; b) moves into the panel and picker values. ➡️ **a**.
23. **9e: the public controlled API.** a) unchanged in 9e (`requests/1`, the commands); b) reshaped now. ➡️ **a**; 9f changes only how a panel request's fields are made (question 29).
24. **9f: name and place.** a) `AshDataTable.Kit.Projection` in part 3 (`kit/`), one module per outer part behind `of/2`, public moduledoc with every shape; b) in 3w beside `Item`. ➡️ **a**: a projection holds bundles, which are `Attrs`' (part 3), and 3w may not call part 3.
25. **9f: projections of the inner parts.** a) inside the outer part's projection (a grid's holds its header cells', filter cells', editors'; a panel's its fields'), the kit hands them down; b) each inner part's caller asks `Projection.of/2` again. ➡️ **a**: one island per outer part already takes it whole; the rows stay in the stream.
26. **9f: the structs in the contract.** a) a part gets only its projection (plus `kit`, `id`, the stream, its slot); `Model`, `State`, `Present.*`, `Query.Page` leave the contract; b) keep `model` as a way out for custom parts. ➡️ **a**: a way out is how the four layers came about; a missing fact is added as a key.
27. **9f: one assign or one attribute per key.** a) try one `projection` assign per part first; keep it if bytes stay within 2 %, else one attribute per top-level key; b) attributes per key from the start. ➡️ **a**, decided by the measurement in the stage's first step and written in the note's as-built section.
28. **9f: `ReactKit.Props`.** a) shrinks to the props rule over projections, folded into `ReactKit` if under about 50 lines; b) stays a module of its own whatever its size. ➡️ **a**.
29. **9f: `requests/1`.** a) a panel request's fields come from the same panel projection, without bundles, in the request's own envelope; b) `Event.request/1` keeps its own projection. ➡️ **a**: one way; the shape change of `requests/1` is written in its moduledoc and the controlled guide.
30. **9g: checkpoint and shape.** a) the owner decides after 9f on the measured size (the numbers of section 8 counted again); if built, the full step (every intent, uploads through a feedback intent); b) build a part: the step only for the topics without a LiveView resource, streams, async and uploads staying socket-bound; c) do not build 9g, the root tests of 9a and 9e being enough. ➡️ **a**, and the full step if the re-sized estimate is 12 days or less, else **b**.
31. **#56: `Live.Entry` after 9d still has about 74 fields.** a) keep it flat, with a one-line reason in the module (one value per table, `Core.put/2` by field, change tracking per field) and a measured callback time; b) split it into sub-values by topic (selection, live updates, summaries, the argument line) in 9d; c) leave it to 9g, which reshapes the `Table`. ➡️ **a**, closing #56 in 9d; 9g may split it if it is built.
32. **The quality gate at the end.** a) once after 9g (or after 9f if 9g is not built): the whole `mix check` in root and demo, `npm run lint`, `knip`, `jscpd`, findings as tickets; b) also after 9f. ➡️ **a**, as E2 says.
33. **`CONTEXT.md`.** a) add **Projection** (what a part is given to draw); no other term (group value, geometry and opener are design names, not domain words); b) add none. ➡️ **a** (added with this note).
