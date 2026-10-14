# Target architecture of `ash_data_table`

Status: proposal for review, 2026-10-14. Nothing in it is built. Main at `c787bb8`.

Names are the names after the rename (`AshDataTable.*`). Words are those of `CONTEXT.md`.

How to read the sources in this document:

| Mark | Means |
| --- | --- |
| `today: path` | Checked in the code at `c787bb8`. Paths are from the repository root. |
| **D-parts** | Issue #21, comment "Built in the owner's absence", section "Agreed by the owner, 2026-10-12: the four parts of the extension" |
| **D-headless** | same comment, "Decided by the owner, 2026-10-12: the headless step" |
| **D-nested** | same, "Decided by the owner, 2026-10-12: nested tables without live components" |
| **D-events** | same, "Agreed by the owner, 2026-10-12: events for the developer" |
| **D-before** | same, "Agreed by the owner, 2026-10-12: before an action runs" |
| **D-fragments** | same, "Asked for by the owner, 2026-10-12: a table declaration in its own file", and "Built 2026-10-13: named tables" |
| **D-rename** | same, "Decided by the owner, 2026-10-13: the new name is `ash_data_table`" |
| **D-nolinks** | same, "Decided by the owner, 2026-10-13: no links from the table into the host app" |
| **D-after-research** | same, "Decided by the owner, 2026-10-12 (after the research)": live updates, summaries, "replaceable parts … once feature complete" |
| **D-gaps** | same, "Decided by the owner, 2026-10-13: gaps found by comparing with other tables" (time zone from the page) |
| **D-next** | same, "Decided by the owner, 2026-10-12: the step after feature completeness" |
| **O-ui** | The owner's wish of 2026-10-14, passed on by the coordinator: React, Vue or Hologram components should work too "if possible". A goal to examine, not a requirement. |
| **R §n** | `ash_reference/headless-table-architecture.md`, section n (research, not a decision unless a D says so) |
| **Q n** | An open question in section 8 |

---

## 0. Summary

The extension becomes four parts with one direction of dependency: the
**declaration** (what a resource's `table` block says, checked at compile
time), the **internals** (logic, state and every call to Ash), the **UI
components** (function components, attribute bundles, the kit, the browser
hook), and the **ready-made wiring** (router line, page, tag). Each part may
depend only on the parts below it (D-parts).

The internals are split in two layers. The lower layer, **data**, knows
nothing of LiveView: it builds the model, reads, writes, checks the claims of
the browser, asks the veto, hands the page values to Ash, scrubs sensitive
values and says what happened. The upper layer, **live**, is the core over a
LiveView socket: one value under one assign holding a flat registry of
tables, one stream per table, async reads, uploads, events to the host
(D-headless, D-nested, R §10). There is no live component in the core.
Nested tables and pickers are registry entries shown through `<.portal>`.

All three ways of using a table (router line, `<AshDataTable.table>`,
`AshDataTable.attach/4`) run the same core and the same function components
(D-events). The developer reacts to events and may say "read again", "set
this state", "clear the selection". Nothing the developer writes can change,
skip or stop the safety checks of a write (D-events, D-before).

**The coupling principle.** Code is tightly coupled only where a change on
one side must always change the other: the hook and the markers it reads,
the core and the model, the URL format and the state module, the write
pipeline and the safety order. Everywhere else a part talks to another
through a named seam (a behaviour, an option with a type, a message shape,
an attribute bundle), and an automatic test checks the direction of every
dependency.

**Other UI technologies (O-ui).** The refactor should cut the internals'
data layer so that it has a documented data contract (rows as the person may
see them, the column model, the offered actions) and a typed set of intents
coming back. Then a React or Vue adapter inside LiveView, or a Hologram
adapter without LiveView, would sit on that layer without another refactor.
No such adapter is built. Section 7 says what it would cost.

---

## 1. Goal and principles

### 1.1 Goal

- A developer can use the table without any wiring (router line), place it
  in a page (tag), or wire it into their own LiveView (`attach`) (D-parts,
  D-headless).
- No live component in the core, nested tables included (D-headless,
  D-nested). See Q1 for what the tag becomes.
- Streams are a must: the server does not hold the rows (D-nested).
- A developer can replace the look against a defined and checkable contract
  (D-parts, D-headless "fully headless contract").
- The code is state of the art and Ash-conform (D-next).

### 1.2 Dependency direction

```
4 Wiring ─────────────► 3 UI components ─────┐
   │                                          ▼
   ├─────────────────► 2b Internals: live ──► 2a Internals: data ──► 1 Declaration ──► Ash, Spark
   └──────────────────────────────────────────────────────────────────┘ (4 may use any lower part)
```

- 3 and 2b do not depend on each other. The function components draw from
  the data the core holds (structs of 2a); the core never renders.
- 1 depends on Ash and Spark only, plus one leaf of 3: the column component
  contract (`AshDataTable.Component`, `.Component.Column`), see 5.2.
- Rules and checks are in section 5.

### 1.3 What "pure" means here

A module is **pure** when it takes values and returns values, and holds no
socket and no process state: no `Phoenix.LiveView.Socket`, no `send`, no
PubSub, no process dictionary of its own, no `Process.put`.

Two things are allowed and do not make a module impure:

- **Calls to Ash as the person.** Reads, `Ash.can/3`, `Ash.can_see_fields/4`,
  actions. They are the table's data. They take the reader options
  (`scope`, `actor`, `tenant`, `authorize?`) as arguments.
- **The Gettext locale of the calling process.** `Gettext` keeps it in the
  process dictionary; `AshDataTable.Text` reads it (today:
  `lib/ash_table/text.ex`). Same for the application config it reads.

So "pure" here is "LiveView-free and process-free", not "side-effect free".

### 1.4 Where state lives

| State | Lives in | Who changes it |
| --- | --- | --- |
| What a table is (columns, actions, options) | The resource, compiled by Spark | The developer, in code |
| The model, same for everybody | The registry entry of the table (today the `built` assign, `lib/ash_table/live/table_component.ex:482`) | Built once per entry |
| The model for this person | The registry entry (today `model`, rebuilt on every `update/2`) | Rebuilt when who is asking changes |
| Sort, filters, arguments, page, page size | The registry entry; and in the URL when the top table is told so (today `url` attr, `lib/ash_table.ex:154`) | Events, commands, `handle_params` |
| Nested tables' sort, filters, page | Their registry entries only, never the URL (today `lib/ash_table/live/page.ex:197-199`) | Events |
| Rows | The stream, that is the browser. The server keeps the keys of the page and the failed edits (today `rows`, `failed`) | Reads, writes, live updates |
| Selection | The browser (hook) only. Sent as a claim when needed | The person |
| Column widths, hidden columns, scroll | The browser only | The person |
| Open action panel (`AshPhoenix.Form`), open picker | The registry entry | Events |
| Uploads in flight | The LiveView socket (`allow_upload`) | LiveView |
| Listener of live updates | A process per table; its pid in the registry entry | Core |
| Page values, veto, notify target | The value under the host's assign, set at attach or by the tag | Server code only |

### 1.5 What must stay true (safety)

These are today's rules (`docs/agents/architecture.md`, "Safety rules"). The
target puts each in one place of part 2a, so that no adapter can wire it away.

| Rule | Where it lives in the target |
| --- | --- |
| Read again as the person before every write (save, action, reveal, pick, bulk) | `AshDataTable.Record`, `AshDataTable.Pick`, and the write pipeline `AshDataTable.Operation` (new) that every write goes through |
| Only `public?` actions run, the read actions of nested tables and pickers included | The verifiers (1) refuse others; the model (2a) offers nothing else |
| `authorize?` and the reader options on every Ash call | `AshDataTable.Caller` (new) holds them, built from server code only; every 2a function takes it |
| Nothing sensitive reaches the browser before "Show" | `AshDataTable.Sensitive.scrub/2` inside `AshDataTable.Present` (new): the only way from a record to what a part draws |
| Values from the browser are claims | `AshDataTable.Intent` (new) parses them; `State.from_params/2` and `State.fit/2` keep only what the model allows; every key is read again |
| An announcement is a claim | `AshDataTable.Query.rows/4` and `any?/5`, as today |
| A summary says no more than the rows | `AshDataTable.Query.summaries/4`, as today |
| Authorization cannot be wired away | The event handlers are the library's (R §2.4, R §9); the developer gets events and commands, never a handler in the path; `before_action` sees no record, no value, and can only halt (D-before) |
| Order of a write: confirm in the browser → the table's own checks → `before_action` → re-read as the person → the action with context and private arguments | `AshDataTable.Operation` (D-before) |

---

## 2. Moving parts

"Replaceable" means a developer can put their own implementation behind a
seam. "Configurable" means a developer chooses among values the library
offers. "Fixed" means neither.

| # | Moving part | What varies | Who decides | When | Replaceable or configurable | Now or later |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Source of rows and counts | Where the page, the count, one record and the selected records come from. Today an Ash read through the table's read action (`lib/ash_table/query.ex`) | Declaration (the read action) | Compile time | Fixed now. A seam to **keep possible** for a search engine later (D-after-research: "replaceable parts … once feature complete"). Not to build | Later |
| 2 | Source of summary numbers | Today `Ash.aggregate/3` in `Query.summaries/4` (`lib/ash_table/query.ex:405`); a manual read action is a compile error (`lib/ash_table/resource/summarising.ex:77`) | Declaration (`summary` on a column) | Compile time | Fixed now; replaceable later (D-after-research: "a replaceable source of the numbers comes later (agreed)") | Later |
| 3 | Writes | Which update, create, destroy and generic actions run | Declaration (`table` block) | Compile time | Fixed. No command makes the table write (D-events) | Now |
| 4 | Drawing of the table (kit) | Markup and classes of every part | Config, and per table | Mount | Replaceable (D-parts, D-headless) | Stage 7 |
| 5 | A column's cell and editor | Markup of one column's cells and its control | Declaration (`component` on a column) | Compile time | Replaceable, exists today (`lib/ash_table/component.ex`) | Now |
| 6 | Browser behaviour (keyboard, focus, editing, widths, scrolling) | Nothing for the developer; it reads markers | Library | — | Fixed. Configurable through CSS custom properties only (today `--ash-table-ground`, `--ash-table-bottom`) | Now |
| 7 | Where the table's state lives | URL or memory, per top-level table | Host page (`url` on the tag, `url: true` at attach); the router page always uses the URL | Mount | Configurable | Now (tag, page); stage 4 (attach) |
| 8 | Event receivers | Which events the host gets | Host page (`notify`) | Mount | Configurable | Stage 6 (D-events) |
| 9 | Commands in | Read again, set state, clear selection, read the selected records | Host page code | Per event | API, not replaceable | Stage 6 (D-events) |
| 10 | Page values | `context`, `private_arguments`: a map, or a function of the page's state that is told which table asks | Host page | Evaluated each time an action is built | Configurable | Stage 6 (D-before) |
| 11 | Veto | `before_action`: `:cont` or `{:halt, message}` before every write | Host page | Per write | Replaceable (a function) | Stage 6 (D-before) |
| 12 | Public argument filled by the page | `page_argument :name` inside a table's `action`; the value from the page | Declaration (which argument) and host page (its value) | Compile time and per action | Configurable | Stage 6 (D-before). Option name for the value: Q7 |
| 13 | Time zone of date-times | The zone a date-time is shown and typed in | Host page (D-gaps) | Mount | Configurable | Being built (`build/timezone`); its shape is that build's |
| 14 | Live updates | On or off; the PubSub server | Declaration (`live? true`), domain (`pub_sub`), host page (`live?`) | Compile time and mount | Configurable. Transport fixed: `Phoenix.PubSub` | Now |
| 15 | Texts and translations | The Gettext backend, the error translator | Config `:gettext_backend`, `:translate_error` (today `lib/ash_table.ex:31-34`) | Run time | Backend replaceable (any Gettext backend); texts configurable by translation | Now |
| 16 | Authorization inputs | `scope` or `actor` and `tenant`; `authorize?` | Host page (tag, attach), router line, domain defaults (`scope_assign`, `actor_assign`, `tenant_assign`, `authorize?`) | Mount; again when who asks changes | Configurable. Never from the browser | Now |
| 17 | The layout around a mounted table | Function component the page is rendered in | Config `:layout`, router option `layout:` | Render | Configurable | Now |
| 18 | Uploads | Accepted types, size per file argument | Declaration (`upload` in the `table` block) | Compile time | Configurable. Mechanism fixed: LiveView uploads | Now |
| 19 | Name, heading, id, label | How the table is named on the page | Host page (tag attrs, router `id:`) | Mount | Configurable | Now |
| 20 | Page sizes, depth, pinned label column | `page_sizes`, `max_depth`, `sticky_label?` | Declaration | Compile time | Configurable | Now |
| 21 | The "open" control of a row | Whether a row offers "open", and its label | Not decided: Q8 | Mount or compile time | Configurable | Stage 6 (D-nolinks) |
| 22 | UI technology | HEEx today; React or Vue in LiveView, or Hologram, later | The developer | — | Replaceable later, through the data contract of section 7 | Later (O-ui) |
| 23 | Who is asking changes | A login on the same page | Host page | Per event | `attach/4` again with the same name replaces the reader and reads again (R §5.2) | Stage 4 |
| 24 | Which of a resource's tables | Default or named table | Host page (`table:`), declaration (named tables, fragments) | Mount | Configurable | Now (D-fragments) |

---

## 3. Seams

"Exists" means it is in the code today. "New" means a refactor stage creates it.

| # | Moving part | Seam (exact interface) | Implemented by | What may cross | Status |
| --- | --- | --- | --- | --- | --- |
| S1 | Source of rows and counts | Today: the functions of `AshDataTable.Query` (`read/3`, `read_related/4`, `matching/3`, `records/3`, `related_records/5`, `rows/4`, `any?/5`, `get/5`), `Record.fetch/3`, `Pick.chosen/3`, `Pick.current/3`. Later, if wanted: a behaviour `AshDataTable.Source` with `read(Model.t, State.t, Caller.t) :: {:ok, Query.Page.t} \| {:error, term}`, `fetch(Model.t, [key], Caller.t) :: [record]`, `count(Model.t, State.t, Caller.t) :: {:ok, n} \| :unknown`. Q11 | Library (Ash read). Later a search-engine adapter | Records **as the person may see them** (Ash applied policies and field policies); keys; never what the person may not read | Exists as functions. Behaviour later. Rule to keep it possible: only `Query`, `Record`, `Pick`, `Bulk` call Ash reads (true today, see 5.4) |
| S2 | Source of summary numbers | Today `Query.summaries(Model.t, State.t, parent, opts) :: {:ok, %{column => value \| :unavailable}} \| {:error, term}`. Later the same signature as a callback | Library; later a developer | Numbers only, by column; `:unavailable` where a field is hidden on some records | Exists as a function. Seam later |
| S3 | Kit | Behaviour `AshDataTable.Kit`: one callback per replaceable part, `part(assigns) :: Phoenix.LiveView.Rendered.t()`, and `class(part :: atom, state :: map) :: String.t()`. `use AshDataTable.Kit, contract: 1` gives defaults. Named by `config :ash_data_table, kit:` and per table (`kit=` / `kit:`). Q12 | Library (`Kit.Default`), developer | Values and attribute bundles. Never a record, the actor, or another field of a row (R §4.4) | New, stage 7 |
| S4 | Column component | Behaviour `AshDataTable.Component`: `cell(assigns)`, `editor(assigns)`, `commit() :: :enter \| :change`, `verify(Component.Column.t) :: :ok \| {:error, String.t}` | Library (Badge, Image, Progress, Slider), developer | `value`, `text`, `column` (`Component.Column`), `control` bundle, `label`, `place`. Never the record | Exists (`lib/ash_table/component.ex:188-218`) |
| S5 | Attribute bundles | Functions of `AshDataTable.Attrs` that return an attribute map per element (ids, `role`, ARIA, `data-*`, `phx-*`, `phx-hook`). A part spreads it: `<nav {@root}>` | Library only | Markers. The hook reads nothing else (D-headless) | New, stage 7. Seed today: `@control` of an editor |
| S6 | Hook ↔ server | Events from the browser: one name per intent, namespaced by table id (R §10.8 decision 23 recommends `ash_table:ID:event`; prefix after the rename is Q3). Payload: row key as in the DOM id, column or action name as text, typed text, selection. Replies: maps. Server → hook: `push_event` names `ash_table:focus`, `:ask`, `:bulk`, `:unselect`, `:leaving` with `table: id` (today `lib/ash_table/live/table_component.ex:1400-2245`) | Library on both sides | Claims only. Text, never atoms (today `column/2`, `action/2` look names up as text) | Exists with plain names (`"sort"`, `"save"`); namespaced in stage 3 |
| S7 | Events out | `send(self(), {:ash_table, table_id, {event, details}})` to the LiveView process, opt-in with `notify` (`true` or a list of event names). Events: `:read`, `:read_failed`, `:row_saved`, `:row_created`, `:row_destroyed`, `:action_ran`, `:bulk_ran`, `:selection_changed`, `:row_expanded`, `:row_collapsed`, and the "open" event (D-nolinks). Nested tables and pickers add their `path` | Library sends; host receives in `handle_info/2` | Keys as maps; `record` as the action returned it to the person; `arguments` without `sensitive?` ones and without file contents; `changed`; `result`. An event only after success (D-events) | New, stage 6. Tag after the rename: Q3 |
| S8 | Commands in | `AshDataTable.refresh(socket, table)`, `put_state(socket, table, params)`, `clear_selection(socket, table)`, `selected_records(socket, table, selection)`, `detach(socket, table)`. `table` is the attach name or a tag id. Each returns the socket | Library; host calls | URL vocabulary (`%{"sort" => …, "f" => …, "a" => …}`), parsed by `State.from_params/2`. Nothing that writes | New, stage 6 (D-events lists "read again, set filters, clear the selection") |
| S9 | Page values | Options `context:` and `private_arguments:`, each `map \| (assigns, table_ref -> map)`. `table_ref` says which table asks (D-before 5: "told which table is asking"). Q5 | Host | Server values into Ash calls: `context:` on every call; private arguments only for names an action declares `public?: false`. Nothing from the browser | New, stage 6 |
| S10 | Veto | Option `before_action: (AshDataTable.Request.t, assigns) -> :cont \| {:halt, String.t}`. The request: table, path, resource, action, type, from, column, key (a claim), selection (a claim) | Host | No typed value, no inputs, no record, no changeset, no socket (D-before) | New, stage 6 |
| S11 | Public argument from the page | DSL: `page_argument :name` inside a table's `action`. Value: a page option (Q7) | Declaration + host | One value per declared name, merged over the params as `record_argument` is today (`lib/ash_table/act.ex:185-191`) | New, stage 6 |
| S12 | Live updates | Message `{:ash_table, resource, :create \| :update \| :destroy, primary_key, tenant}` on `Phoenix.PubSub` topic `Notifier.topic(resource, tenant)` (today `lib/ash_table/notifier.ex:17, 83`). Listener: `Listener.start(pub_sub, topic, relay :: ([announcement] -> term))` (`lib/ash_table/listener.ex:30`). Delivery: `relay` does `send_update` today; in a LiveView it can be a message to a `handle_info` hook (Q10) | Library both sides | A primary key and a tenant. Never a record | Exists |
| S13 | Texts | `config :ash_data_table, gettext_backend: Mod, translate_error: {m, f}`; Gettext domain (today `"ash_table"`, renamed by D-rename) | Host | Strings | Exists |
| S14 | Layout of a mounted table | `config :ash_data_table, layout: {m, f}`; router `layout: {m, f} \| false` (today `lib/ash_table/router.ex:53-56`) | Host | `flash`, `current_scope` and the assigns named by the domain (today `lib/ash_table/live/page.ex:285-291`) | Exists |
| S15 | Authorization inputs | Tag attrs and attach options `scope`, `actor`, `tenant`, `authorize?`; router `authorize?:`; domain DSL `scope_assign`, `actor_assign`, `tenant_assign`, `authorize?`, read by `Domain.Info.reader/2` | Host | Server values only. Kept in `AshDataTable.Caller` (new) | Exists (as assigns); struct new in stage 2 |
| S16 | Defaults of asked arguments | DSL `ask :name, default: &fun/1`, given the page's assigns (today `lib/ash_table.ex:168-171`) | Host | Page assigns into a default value | Exists |
| S17 | Time zone | A page option or page assign; read by `AshDataTable.Format` | Host | A zone name | Being built (`build/timezone`) |
| S18 | URL state | Parameters under the table id: `ID[sort]`, `ID[f]`, `ID[a]`, `ID[c]`, `ID[page]`, `ID[per]`, `ID[of]` (today `State.to_params/2`, `Related.to_param/2`). Tag: `url` attr; attach: `url: true` with a `handle_params` hook | Library | Claims, parsed by `State.from_params/2`, `Related.from_params/5` | Exists for page and tag; attach in stage 4 |
| S19 | Data contract for a UI technology | `AshDataTable.Present` (rows and cells as the person may see them) and `AshDataTable.Intent` (what comes back). Section 7 | Library; a later adapter | Scrubbed values, texts, flags; intents as claims | New, proposed (Q14) |
| S20 | Browser transport | The hook's code talks to the server through one object: `push(event, payload) -> Promise(reply)`, `on(event, handler)`. The LiveView hook is the first implementation | Library | Event names and payloads of S6 | New, proposed (Q15) |
| S21 | Test support | `AshDataTable.Test` (flush, nested tables through portals, events by name), `use AshDataTable.KitCase, kit: Mod` | Library; host's tests | — | `flush/1` exists (`lib/ash_table/test.ex`); rest new (D-nested: test helper "yes, if needed") |

---

## 4. Module matrix

### 4.1 Short names used in the matrix

| Short | Means |
| --- | --- |
| **1** | Part 1, declaration: `AshDataTable.Resource*`, `AshDataTable.Domain*` |
| **2a** | Part 2, internals, data layer: LiveView-free |
| **2b** | Part 2, internals, live layer: the core over a socket, `AshDataTable.Live.Core*`, `AshDataTable.Live.Registry` |
| **3** | Part 3, UI components: `AshDataTable.Parts*`, `Attrs`, `Kit*`, `Component*`, `Components.*`, the JS |
| **3c** | The column component contract alone: `AshDataTable.Component`, `AshDataTable.Component.Column` |
| **4** | Part 4, wiring: `AshDataTable` (the public entry), `Router`, `Live.Page`, the tag |
| **T** | Test support shipped in `lib/` |
| **LV** | `Phoenix.LiveView`, `Phoenix.Component`, `Phoenix.LiveView.JS` |
| Pure | LiveView-free and process-free in the sense of 1.3 |

"May depend on" lists parts and outside libraries. "Must not" lists what the
dependency test of section 5 forbids.

### 4.2 Part 1: declaration

All of part 1 is pure. It may depend on Ash, Spark, and 3c. It must not
depend on 2a, 2b, 3 (except 3c), 4, LV.

| Module | Responsibility | Public API | Notes on dependencies | Today's code |
| --- | --- | --- | --- | --- |
| `AshDataTable.Resource` | The Spark extension of a resource: sections `table` and `tables`, entities, the list of verifiers and the transformer | DSL; `use Ash.Resource, extensions: [AshDataTable.Resource]` | Compile-time dependencies: entity structs, verifiers, transformer (Spark requires it) | `lib/ash_table/resource.ex` |
| `AshDataTable.Resource.Info` | Read a declaration | `tables/1`, `table/2`, `table!/2`, `no_table/2`, generated `table_*` | 1 only | `lib/ash_table/resource/info.ex` |
| `AshDataTable.Resource.Table` | One table as written; the shared option schema | `options/0`, `path/1`, `anno/2`, `option_anno/3`, `in_words/1` | 1 only | `lib/ash_table/resource/table.ex` |
| `AshDataTable.Resource.Column`, `.Ask`, `.Relationship`, `.Action`, `.Reference`, `.Argument`, `.Upload` | Entity structs, each with `schema/0` | Struct types (documented for `Info`) | none | `lib/ash_table/resource/*.ex` |
| `.Action` gains `page_argument` | The argument a page fills (D-before 3) | DSL `page_argument :name` | — | New, stage 6 |
| `AshDataTable.Resource.Reading` | Read action, pagination, page sizes, what sorts | as today | 1 only | `lib/ash_table/resource/reading.ex` |
| `.Editing` | Update action of a column, inline edit | as today | 1 only | `resource/editing.ex` |
| `.Acting` | Row actions, table actions, create, inputs, `bulk?` | as today; plus the `page_argument` rule | 1 only | `resource/acting.ex` |
| `.Arguing` | Arguments of the read action and calculation columns | as today | 1 only | `resource/arguing.ex` |
| `.Relating` | Relationships a row offers, nested tables | as today | 1 only. Today it calls `AshTable.Resource` at run time (`table?/1`), which joins the compile cycle (5.4) | `resource/relating.ex` |
| `.Referencing` | Reference cells, `label_field`, picker, `sticky_label?` | as today | 1 only | `resource/referencing.ex` |
| `.Managing` | Arguments `manage_relationship` hands on | as today | none | `resource/managing.ex` |
| `.Embedding` | Fields of a map cell, kinds of a union | `of/2`, `union/2`, `kind/2`, returning its own answer, not `Model.Field` | 1 only. Today it builds `Model.Field` and calls `Model.humanize/1` (5.4) | `resource/embedding.ex` |
| `.Presenting` | A column's `component`, `max_lines`; the words of a cell type (`shown_as/1`) | as today | 1 and 3c | `resource/presenting.ex`; `shown_as/1` from `lib/ash_table/components.ex` |
| `.Uploading` | Limits of a file argument | as today | 1 only | `resource/uploading.ex` |
| `.Exposing` | Field-policy exposure; `sensitive?/1`, `typed?/1`, `empty?/1` of a field | as today plus the moved predicates | none | `resource/exposing.ex`; predicates from `lib/ash_table/sensitive.ex:36-61` |
| `.Summarising` | `summary` rules | as today | 1 only | `resource/summarising.ex` |
| `.Listening` | Live-update rules | as today | 1 only | `resource/listening.ex` |
| `AshDataTable.Resource.CellType` | Ash type → cell type | `of/2`, `classify/2` | none | `lib/ash_table/model/cell_type.ex` (moved, because 1 uses it) |
| `AshDataTable.Resource.Operator` | Filter operators per cell type | `available/2`, `to_ash/2`, `takes/1`, `predicates/2`, `negated?/1` | `CellType`, `Exposing` | `lib/ash_table/model/operator.ex` (moved, because `VerifyColumns` uses it) |
| `AshDataTable.Resource.Words` | A name in words | `humanize/1` | none | `Model.humanize/1`, `lib/ash_table/model.ex:2018` |
| `AshDataTable.Resource.Verifiers.*` (11) | Report mistakes at compile time | none (Spark) | Topic modules, `Info`, `Table` only (5.3) | `lib/ash_table/resource/verifiers/*.ex` |
| `AshDataTable.Resource.Verifiers.VerifyPageArguments` | `page_argument` names a public argument of that action, not one the panel also asks | none | as above | New, stage 6 (may be a clause of `VerifyActions`) |
| `AshDataTable.Resource.Transformers.Announce` | Gives a `live? true` resource the notifier | none | `Notifier` (see its row) | `resource/transformers/announce.ex` |
| `AshDataTable.Notifier` | The Ash notifier: broadcasts a key | `topic/2` | 1, `Phoenix.PubSub`. Not pure (broadcasts). Which part: Q9 | `lib/ash_table/notifier.ex` |
| `AshDataTable.Domain`, `.Domain.Info`, `.Domain.Verifiers.VerifyPubSub` | The domain's `table` block | DSL; `authorize?/1`, `reader/2`, `assign_names/1`, `pub_sub/1` | 1 only | `lib/ash_table/domain.ex`, `domain/**` |

### 4.3 Part 2a: internals, data layer

All pure in the sense of 1.3. May depend on 1, Ash, AshPhoenix (`AshPhoenix.Form`
works without LiveView), Gettext. Must not depend on 2b, 3, 4, LV, Phoenix.PubSub.

| Module | Responsibility | Public API | Today's code |
| --- | --- | --- | --- |
| `AshDataTable.Model` | Everything a table is drawn from, built from `Ash.Resource.Info` and the declaration (ADR 0001) | internal: `build/2`, `for_actor/2`, `defaults/2`, `supply/2`, `bulk_actions/1`, `loads/1`, `relationship/2`, `nested_create/2`, `hideable/1`, `summarised/1`, `label_column/1` | `lib/ash_table/model.ex` |
| `Model.Column`, `.Field`, `.Input`, `.Action`, `.Argument`, `.Relationship`, `.Pagination`, `.Limits` | Structs and small rules of the model | internal | `lib/ash_table/model/*.ex` |
| `Model.Access` | What Ash says the person may see and do, before any read | internal | `lib/ash_table/model/access.ex` |
| `AshDataTable.State` | Sort, filters, arguments, page, page size of one table; the URL vocabulary | internal: `from_params/2`, `to_params/2`, `fit/2`, `cycle_sort/3`, `filter/3`, `argue/3`, `to_page/2`, `resize/3`, … | `lib/ash_table/state.ex` |
| `AshDataTable.Related` | The `of` parameter of a full view | internal: `from_params/5`, `to_param/2`, `path/5` | `lib/ash_table/related.ex` |
| `AshDataTable.Routes` | Where a router mounts a table, read from the router's routes | internal: `default_id/2`, `table/4` | `lib/ash_table/routes.ex`. Moved from 4 to 2a because `Related` needs it and it is a pure function over a router module (Q13) |
| `AshDataTable.Caller` | Who asks and what the page adds: `scope`/`actor`/`tenant`, `authorize?`, `context`, `private_arguments`, page arguments, `before_action`, time zone, the page assigns. Built from server code only | internal: `new/1`, `reader_opts/1`, `context_for/2`, `private_arguments_for/3` | New, stage 2. Today: `reader/1` in the component (`table_component.ex:1122`), `Query.reader_opts/1` (`query.ex:725`). Name: Q16 |
| `AshDataTable.Query` | Every read through the table's read action; summaries; live-update reads | internal: as today, taking `Caller` | `lib/ash_table/query.ex` |
| `AshDataTable.Record` | One row's record, read again as the person | internal: `fetch/3`, `key/2`, `load/3` | `lib/ash_table/record.ex` |
| `AshDataTable.Pick` | The record chosen in a picker, read again | internal | `lib/ash_table/pick.ex` |
| `AshDataTable.Edit` | Save one cell; open and put a map cell | internal | `lib/ash_table/edit.ex` |
| `AshDataTable.Act` | Row actions, table actions, create, through `AshPhoenix.Form` | internal | `lib/ash_table/act.ex` |
| `AshDataTable.Bulk` | A row action on a selection | internal: `run/5` | `lib/ash_table/bulk.ex` |
| `AshDataTable.Operation` | The one pipeline every write goes through: checks the claim against the model, asks `before_action`, reads again as the person, builds the action with the page values, returns the outcome and the event details | internal: `save/3`, `clear/3`, `refer/3`, `run/3`, `submit/3`, `bulk/3`, `reveal/3`, each `(Caller.t, Model.t, Intent.t) -> {:ok, outcome} \| {:halted, message} \| {:error, errors}` | New, stage 3 (pipeline) and 6 (veto, page values). Today the steps are spread over `handle_event/3` clauses and helpers (`table_component.ex:1958-2713`, `2742-4197`) |
| `AshDataTable.Request` | What `before_action` is told | public struct (documented) | New, stage 6 (R §11.5) |
| `AshDataTable.Intent` | What a person asks for, parsed from any UI: `{:sort, column}`, `{:save, row, column, typed}`, … Names are text until looked up | internal; documented later if Q14 | New, stage 3. Today: the pattern heads of `handle_event/3` |
| `AshDataTable.Event` | The details of each event, built from an outcome; the typed list of events | public types; `details/2` internal | New, stage 6 |
| `AshDataTable.Present` | From a record and the person's model to what a row and its cells show: key, texts, input values, flags (`editable?`, `hidden?`, `masked?`, `invalid?`). Calls `Sensitive.scrub/2` first | internal; documented later if Q14 | New, stage 3. Today: `item/8`, `put_row`, `cell/…`, `cell_content`, `typed_value` in the component (`table_component.ex:1701-1830`, `11457-11730`) |
| `AshDataTable.Sensitive` | Scrub sensitive values before a row is drawn; the mask | internal: `scrub/2`, `mask/0` | `lib/ash_table/sensitive.ex` (predicates moved to `Resource.Exposing`) |
| `AshDataTable.Format` | What a cell shows; a summary's text | internal: `format/2`, `input/2`, `summary/2` | `lib/ash_table/format.ex` |
| `AshDataTable.Text` | Every text a person reads | internal: `t/2`, `n/3`, `label/1`, `error/1` | `lib/ash_table/text.ex` |
| `AshDataTable.Gettext` | The default backend without translations | public module (config default) | `lib/ash_table/gettext.ex` |
| `AshDataTable.Errors` | What an error says and where | internal | `lib/ash_table/errors.ex` |
| `AshDataTable.Source` | Behaviour for a replaceable source of rows | — | Later, not built (S1, Q11) |

### 4.4 Part 2b: internals, live layer

Needs the socket. May depend on 2a, 1, LV, Phoenix.PubSub. Must not depend on 3, 4.

| Module | Responsibility | Public API | Today's code |
| --- | --- | --- | --- |
| `AshDataTable.Table` | The one value the host holds under one assign: options, `Caller`, the flat registry of entries, the stream-name pool. Opaque; documented read-only fields (`id`, `state` as params, `count`, `total`, `loading?`, `error`) | public, opaque struct (R §5.1). Name: Q16 | New, stage 2. Today: about 55 assigns (`table_component.ex:416-530`) and the process dictionary `@tables` (`table_component.ex:413`) |
| `AshDataTable.Live.Entry` | One table of the registry (top, nested, picker): model, state, rows index, failed, open rows, panel, picker, selection mode, live, summary, path, parent key | internal struct | New, stage 2, from today's assigns |
| `AshDataTable.Live.Registry` | Add, find, close by id prefix; stream names from a pool; async keys `{:ash_data_table, id, :read}`; upload names `id <> "-file-" <> arg` | internal | New, stage 2/5. Today: `tables/0`, `close`, `tidy` (`table_component.ex:1198-1290`), `upload_name/2` (`:3699`) |
| `AshDataTable.Live.Core` | Socket in, socket out, for a table under a given assign: `init`, `handle_event`, `handle_async`, `handle_info`, `handle_params`. Parses the event into an `Intent`, finds the entry, calls `Operation`, applies the outcome to stream and entry, sends events | internal | New, stage 3. Today `mount/1`, `update/2`, `handle_event/3`, `handle_async/3` of the component |
| `Live.Core.Reading` | Read in place or async, show, put a row, remove a row, the fill and error messages, summaries beside the read | internal | `table_component.ex:941-1121`, `1454-1540`, `1541-1957` |
| `Live.Core.Cells` | Save, clear, reveal, refer, discard, dismiss | internal | `2742-2846` and their `handle_event` clauses |
| `Live.Core.Panel` | Row action, table action, create, panel events, submit, after a create or run | internal | `3121-3415`, `3507-3698`, `3950-4197` |
| `Live.Core.Picker` | Open, choose, cancel; inputs chosen in the panel | internal | `2847-3120` |
| `Live.Core.Bulk` | Selection actions and the bulk async run | internal | `3416-3506`, `handle_async(:bulk, …)` |
| `Live.Core.Files` | Allow, consume around the action, cancel, drop | internal | `3699-3949` |
| `Live.Core.Nesting` | Expand, toggle, open a nested entry, portal target, close by prefix | internal | `relate`, `nested_model` (`650-760`), `expand`/`toggle` clauses, `close` |
| `Live.Core.Updates` | Live updates: listen, hold, release, refresh, leave, notice | internal | `1131-1453` |
| `Live.Core.Url` | Patch the URL; `handle_params` hook | internal | `go`, `path`, `query_params` (`4265-4302`) |
| `Live.Core.Notify` | Send events to the host, opt-in | internal | New, stage 6 |
| `AshDataTable.Listener` | The process that subscribes and hands batches over | internal: `start/3`, `stop/1`, `flush/1`, `of/1` | `lib/ash_table/listener.ex` |

### 4.5 Part 3: UI components

May depend on 2a (structs, `Present`, `Format`, `Text`, `Intent` names), 1
(`Info` only where a part needs a declaration fact), LV. Must not depend on
2b, 4. Pure (function components).

| Module | Responsibility | Public API | Today's code (`lib/ash_table/live/table_component.ex` unless named) |
| --- | --- | --- | --- |
| `AshDataTable.Parts.Grid` | The grid skeleton: scroll area, `table`, header row, filter row, body rows, cells, footer, editor templates; the root that carries the `.Grid` hook | internal component; parts through the kit | `render/1` `4303-4996`; `columns` `10691`; `editor` `11157`; view helpers `11313-11762` |
| `Parts.Heading` | The line of the table's name; create; table actions | kit part `heading` | `4312-4358`; `create` `10402`; `table_actions` `10423` |
| `Parts.Arguments` | The argument line | kit part `argument_line` | `4359-4397`; `lines` `8769`; `argument` `8911` |
| `Parts.Filter` | One column's filter control; values of "is any of" | kit part `filter` | `filter` `10788`; `choices` `10936` |
| `Parts.Selection` | The selection line and bulk buttons | kit part `selection_line` | `4407-4466`; `selection` `10313` |
| `Parts.Pagination` | Pages, "Rows per page" | kit part `pagination` | `pagination` `10478`; `pages` `10502` |
| `Parts.Panel` | The action panel, fields, groups, unions, chosen records | kit parts `panel`, `field`, `control` | `panel` `9100`; `field` `9372`; `group` `9793`; `groups` `9862`; `union` `9960`; `members` `10057` |
| `Parts.Picker` | The picker dialog around a registry entry | kit part `picker` | `picker` `9196`; `picker_reader` `10194` |
| `Parts.Related` | Relationship lines, the portal of each open nested table, the full-view link | kit part `line` | `related` `10248`; `nested_reader` `10216`; `4843-4866` |
| `Parts.Summary` | The footer summaries row | kit part `footer` | `summary` `10634`; `4765-4842` |
| `Parts.Messages` | Status live region, notice of changes, fill, error, loading, confirm dialog, failure popover, whole-text popover | kit parts `message`, `confirm` | `4467-4477`, `4887-4945`, `4956-4996` |
| `Parts.Editors` | Built-in editors: text counter, list editor | kit parts `cell`, `editor` | `count` `11202`; `list` `11263`; `list_item` `11313` |
| `AshDataTable.Attrs` | Attribute bundles for every element (S5) | internal; their content is the contract | New, stage 7. Today written inline in HEEx |
| `AshDataTable.Kit` | Behaviour and `use` macro, contract version, `class/2` | public | New, stage 7 |
| `AshDataTable.Kit.Default` | The daisyUI kit | public module | New, stage 7, from today's markup |
| `AshDataTable.Component`, `.Component.Column` (3c) | The column component contract | public (exists) | `lib/ash_table/component.ex`, `component/column.ex` |
| `AshDataTable.Components.Badge`, `.Image`, `.Progress`, `.Slider` | Shipped column components | public | `lib/ash_table/components/*.ex` |
| Hooks: `Grid`, `Panel`, `Picker`, `Pagination` | Browser behaviour, on markers only (D-headless) | the event names and markers of S5, S6 | `4997-8768`; delivery: Q15 |

How the hook code is organised (proposed, Q15): one ES module per section of
today's `.Grid` hook, one object that holds the shared state, and one
transport object (S20). The four LiveView hooks are thin and only wire the
transport. Today's sections and their target files:

| Today's `.Grid` section (line) | Target JS module |
| --- | --- |
| constants, `mounted`, `beforeUpdate`, `destroyed` (5394–5840) | `grid/index.js` |
| the counter of a text (5841) | `grid/counter.js` |
| the tree of grids (5909) | `grid/tree.js` |
| expanding (6302) | `grid/expanding.js` |
| the widths of the columns (6481) | `grid/widths.js` |
| hiding columns (6726) | `grid/hiding.js` |
| scrolling sideways (6964) | `grid/scrolling.js` |
| several values of a filter (7191) | `grid/choices.js` |
| selecting (7289) | `grid/selecting.js` |
| row actions (7575) | `grid/actions.js` |
| editing (7635) | `grid/editing.js` |
| the values of an array (7970) | `grid/arrays.js` |
| sensitive cells (8388) | `grid/sensitive.js` |
| the dialog (8503) | `grid/dialog.js` |
| the message of a failed cell (8524) | `grid/failure.js` |
| the whole text of a cell (8552) | `grid/whole_text.js` |
| `.Panel` (5064), `.Picker` (5257), `.Pagination` (4997) | `panel.js`, `picker.js`, `pagination.js` |
| (new) | `transport/live_view.js`, `markers.js` (the names of S5 in one place) |

### 4.6 Part 4: ready-made wiring

May depend on everything below. Needs the socket.

| Module | Responsibility | Public API | Today's code |
| --- | --- | --- | --- |
| `AshDataTable` | The public entry | `table/1` (the tag), `attach/4`, `attached/1`, `detach/2`, `refresh/2`, `put_state/3`, `clear_selection/2`, `selected_records/3`, `label/1` | `lib/ash_table.ex` (`table/1`, `label/1`); the rest new in stages 4 and 6 |
| `AshDataTable.attached/1` | Function component: draws a `Table` with the streams the host passes (`<AshDataTable.attached table={@tasks} streams={@streams} />`); renders the top table and the portals of nested tables and pickers | public | New, stage 4 (R §5.2 corrected: `streams={@streams}`) |
| `AshDataTable.Router` | Macro `ash_data_table/3` | public | `lib/ash_table/router.ex` |
| `AshDataTable.Live.Page` | The LiveView behind a router line; uses `attach` itself | none (reached by the route) | `lib/ash_table/live/page.ex` (R §8 decision 8) |
| `AshDataTable.Live.Embedded` | What `<AshDataTable.table>` renders: see Q1. Recommended: one thin live component per tag, which attaches the same core to its own socket and renders `attached/1` | none | `lib/ash_table/live/table_component.ex` reduced to a wrapper |
| `AshDataTable.NotFoundError` | 404 for a mounted table whose read is refused | public exception | `lib/ash_table/not_found_error.ex` |
| `Mix.Tasks.AshDataTable.Install` | Igniter installer | `mix ash_data_table.install` | `lib/mix/tasks/ash_table.install.ex`. Tooling: depends on no part at run time |

### 4.7 Test support (T)

| Module | Responsibility | Public API | Today's code |
| --- | --- | --- | --- |
| `AshDataTable.Test` | Help for a host's tests: `flush/1`; read a nested table out of its portal and send its events by name | public | `lib/ash_table/test.ex` (`flush/1`); the rest new, stage 5 |
| `AshDataTable.KitCase` | Renders a fixed table through a kit in every state; asserts the markers | public | New, stage 7 (R §4.4) |
| `AshDataTable.Test.Resource` (and its domain) | An ETS resource shipped in `lib/` for `KitCase`; `test/support/` is not shipped | internal to T | New, stage 7 |

### 4.8 Where today's table component goes

`lib/ash_table/live/table_component.ex` has 11,762 lines today. The line
ranges in `docs/agents/architecture.md` are older (it says "about 10,900") and
do not match; the ranges below are of `c787bb8`.

| Lines | Today | Target |
| --- | --- | --- |
| 1–399 | Comment: markup contract, one section per feature | Contract → `Attrs` docs and the kit guide; features → moduledocs of `Live.Core.*` and `Parts.*` |
| 403–413 | `@header_rows`, `@tables` (process dictionary registry) | `Parts.Grid`; `Live.Registry` |
| 416–536 | `mount/1`, every assign | `Live.Entry` (fields with their comments) |
| 537–940 | `update/2`: listener batches, `selecting`, `relate`, `build`, `nested_model`, `creates`, `in_words` | `Live.Core` (init), `Live.Core.Nesting`, `Live.Core.Updates`; `in_words` → `Model` or `Text` |
| 941–1052 | `settle`, `read`, `reader` | `Live.Core.Reading`; reader → `Caller` |
| 1053–1121 | Footer summaries | `Live.Core.Reading` (async beside the read) |
| 1131–1453 | Live updates, `read_opts`, `refresh` | `Live.Core.Updates` |
| 1454–1540 | `handle_async/3` | `Live.Core` dispatch to `Reading`, `Bulk` |
| 1541–1957 | Showing a read: `show`, `item`, `put_row`, `put_detail`, `put_failure`, `remove_row`, `announce`, `row_key` | Data part → `Present`; stream part → `Live.Core.Reading` |
| 1958–2713 | `handle_event/3` clauses | Parsing → `Intent`; checks and writes → `Operation`; socket part → the `Live.Core.*` module of each topic |
| 2714–2741 | `defoverridable` and the wrappers ending in `tidy/1` | `Live.Core` (one dispatch, then `tidy`) |
| 2742–2846 | Cells: `revealed`, `save`, `refer` | `Operation` + `Live.Core.Cells` |
| 2847–3120 | Picker and chosen inputs | `Live.Core.Picker`; `Pick` |
| 3121–3415 | Panel, `act` | `Live.Core.Panel`; `Act` |
| 3416–3506 | Bulk | `Live.Core.Bulk`; `Operation.bulk` |
| 3507–3698 | `submit` | `Operation.submit` + `Live.Core.Panel` |
| 3699–3949 | Files | `Live.Core.Files` |
| 3950–4197 | After a create or run; table actions; lookups `action/2`, `column/2` | `Live.Core.Panel`; lookups → `Intent`/`Operation` |
| 4198–4302 | Arguments, `go`, URL | `Live.Core.Url`; `State` |
| 4303–4996 | `render/1` | `Parts.Grid`, `Parts.Heading`, `Parts.Arguments`, `Parts.Selection`, `Parts.Messages`, `Parts.Summary`; `attached/1` composes them |
| 4997–8768 | Four colocated hooks | JS modules of 4.5 |
| 8769–11312 | Private function components | `Parts.*` (4.5) |
| 11313–11762 | View helpers (`colindex`, `cell_attributes`, `cell`, `page_numbers`, …) | `Attrs` (attributes), `Present` (values, `typed_value`, `editable?`), `Parts.Grid` (the rest) |

---

## 5. Dependency rules

### 5.1 Allowed edges

| From \ To | 1 | 3c | 2a | 2b | 3 | 4 | Ash, Spark | AshPhoenix | LV | PubSub |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **1** (not verifiers) | yes | yes | no | no | no | no | yes | no | no | Notifier only (Q9) |
| **1 verifiers, transformers** | topic modules, `Info`, `Table`, entities | yes | no | no | no | no | yes | no | no | no |
| **2a** | yes | no | yes | no | no | no | yes | yes | no | no |
| **2b** | yes | no | yes | yes | no | no | yes | yes | yes | yes |
| **3** (incl. 3c) | `Info` only | yes | yes | no | yes | no | yes | no | yes | no |
| **4** | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| **T** | all | all | all | all | all | all | yes | yes | yes | yes |

3c depends on nothing of the library.

### 5.2 Forbidden edges, in words

- The declaration never calls the internals, the components or the wiring.
  The one exception is 3c: `Resource.Presenting` checks that a column's
  `component` implements the behaviour and calls its `verify/1` at compile
  time (today `lib/ash_table/resource/presenting.ex:63`). That needs the
  behaviour and the struct it is given, nothing else.
- The data layer never touches LiveView. That is what keeps section 7 possible.
- The live core never renders, and the components never touch a socket.
- Nothing below part 4 knows the wiring. No cycle between files of different
  parts, and no cycle that has a compile edge in it.

### 5.3 Compile time

Spark makes `AshDataTable.Resource` depend at compile time on every verifier
and transformer it lists (today `lib/ash_table/resource.ex`, and
`mix xref graph --label compile-connected` shows exactly these). Every file a
verifier reaches at run time is then compile-connected to every resource that
uses the extension: a change in it recompiles them, and a cycle through it can
deadlock the compiler. This is the known Spark/Ash pattern.

Rules:

1. A verifier or transformer depends only on part 1 modules that are pure
   functions over the DSL and Ash's info modules: the topic modules,
   `Resource.Info`, `Resource.Table`, the entities, `CellType`, `Operator`,
   `Words`, `Exposing`, and 3c.
2. Topic modules do not call `AshDataTable.Resource` itself (today
   `Relating.table?/1` does: `lib/ash_table/resource/relating.ex:141`). To ask
   whether a resource has the extension, use
   `Spark.Dsl.Extension.get_persisted/3` or `Ash.Resource.Info.extensions/1`.
3. `Resource.Info` depends on `AshDataTable.Resource` at compile time
   (Spark's `InfoGenerator`); that edge is required and allowed. No other
   module of part 1 is reached from a verifier and also reaches `Resource`.
4. A transformer names a module only as an atom in the DSL state
   (`Announce` puts the notifier into `:simple_notifiers`). If the notifier
   stays outside part 1, write it as a literal atom so that xref sees no
   call. Q9.

### 5.4 Today's violations (from `mix xref graph`, `c787bb8`)

`mix xref graph --format stats`: 80 files, 27 compile edges, 45 export edges,
184 runtime edges, 2 cycles.

Against the target classification (1 declaration, 2a, 2b, 3, 4):

| # | Edge (file → file) | Kind | Rule broken | Fix in the target |
| --- | --- | --- | --- | --- |
| V1 | `resource/embedding.ex` → `model.ex`, `model/field.ex` (export), `model/cell_type.ex` | runtime, export | 1 → 2a | Embedding returns its own answer; `CellType` moves to 1; `Model` builds `Field` |
| V2 | `resource/acting.ex`, `resource/editing.ex`, `resource/presenting.ex` → `model/cell_type.ex` | runtime | 1 → 2a | `CellType` moves to 1 |
| V3 | `resource/reading.ex`, `acting.ex`, `editing.ex`, `referencing.ex`, `summarising.ex`, `presenting.ex` → `sensitive.ex` | runtime | 1 → 2a | `sensitive?/1`, `typed?/1`, `empty?/1` move to `Resource.Exposing` |
| V4 | `resource/verifiers/verify_columns.ex` → `model/operator.ex` | runtime, verifier | 1 → 2a; 5.3 rule 1 | `Operator` moves to 1 |
| V5 | `resource/verifiers/verify_components.ex` → `model.ex` (`humanize/1`), `sensitive.ex` | runtime, verifier | 1 → 2a; 5.3 rule 1 | `Words.humanize/1`, `Exposing.sensitive?/1` |
| V6 | `resource/transformers/announce.ex` → `notifier.ex` | runtime, transformer | 1 → 2a if the notifier is internals (Q9) | Q9 |
| V7 | `resource/presenting.ex` → `component.ex`, `component/column.ex` (export) | runtime, export | 1 → 3 | Allowed as 1 → 3c |
| V8 | `resource/relating.ex` → `resource.ex` | runtime | 5.3 rule 2; closes the 30-file cycle | Ask Spark/Ash for the extension list |
| V9 | `model/argument.ex` → `format.ex` | runtime | none by part (both 2a), but it pulls `format.ex` into the compile-connected cycle through V1 | Gone once V1 is fixed |
| V10 | Cycle of 30 files with 4 compile edges: `domain.ex`, `domain/info.ex`, `domain/verifiers/verify_pub_sub.ex`, `format.ex`, `model.ex`, `model/argument.ex`, `notifier.ex`, `resource.ex`, `resource/info.ex`, 11 topic modules, `transformers/announce.ex`, 10 verifiers | cycle with compile edges | No compile-connected cycle; 2a files inside a declaration cycle | V1–V8. What remains is the Spark-required `resource.ex` ⇄ `resource/info.ex` and `domain.ex` ⇄ `domain/info.ex` loops, which hold no internals |
| V11 | `lib/ash_table.ex` ⇄ `live/table_component.ex` | cycle (runtime) | Cycle between 4 and the core | The core calls `AshTable.label/1` (`table_component.ex:9231`); `label/1` moves to 2a (`Model` or `Text`), `AshDataTable.label/1` delegates |
| V12 | `related.ex` → `routes.ex` | runtime | 2a → 4 if `Routes` is wiring | `Routes` is classified 2a (Q13) |
| V13 | `live/table_component.ex` → 28 files of all parts | — | One file holds 2b, 3 and 4 | The split of 4.8 |
| V14 | `lib/ash_table/live/table_component.ex` holds the registry in the process dictionary (`:413`) | — | Hidden shared state between tables | `Live.Registry` inside `Table` |

Not violations (allowed by the target): `model.ex` → 13 topic modules of part 1;
`lib/ash_table.ex`, `live/page.ex` → `resource/info.ex`, `resource/relating.ex`,
`domain/info.ex`; `router.ex` → `resource/verifiers/verify_tables.ex`
(`VerifyTables.name?/1`) and `routes.ex`; `domain/verifiers/verify_pub_sub.ex`
→ `resource/listening.ex`; `test.ex` → `listener.ex`; the shipped components →
`component.ex` (compile, through `use`).

### 5.5 How to check automatically

Recommended: one ExUnit test in the root, no new dependency (Q17).

- `Mix.Task.rerun("xref", ["graph", "--format", "json", "--output", path])`
  writes `%{file => %{file => "compile" | "export" | "runtime"}}`. (Checked:
  `mix xref graph --format json --output -` works with Elixir 1.19.4 here.)
  Decode with Elixir's `JSON`.
- Map each file to its part by directory. That needs a directory per part:
  `lib/ash_data_table/resource/**`, `domain/**` (1); `lib/ash_data_table/` top
  level and `model/**` (2a); `live/**` (2b); `parts/**`, `kit/**`,
  `component*`, `components/**` (3); `lib/ash_data_table.ex`, `router.ex`,
  `live/page.ex`, `live/embedded.ex` (4); `test/**`-like modules under
  `lib/ash_data_table/test*` (T). A file that matches no rule fails the test,
  so a new file must be placed on purpose.
- Assert the table of 5.1 for every edge.
- Run the same task with `--label compile-connected` and assert that every
  file it lists is in part 1.
- Run `--format cycles` and assert that no cycle has files of two parts and
  that no cycle has a compile edge, except the Spark-required pairs of 5.4 V10.
- For the "no LiveView in 2a" rule xref is not enough (it sees only our
  files). Add: no file of 2a mentions `Phoenix.LiveView`, `Phoenix.Component`
  or `Phoenix.PubSub` (a grep in the same test over the source).
- The test runs in report mode (prints, does not fail) from stage 1 and fails
  from the end of stage 3.

Alternative: the `boundary` library (a compiler that checks declared
boundaries on every compile). It gives better messages and checks calls into
dependencies too, but it adds a dependency and an annotation in each
top-level module. Not needed for four parts.

---

## 6. Where coupling stays strong on purpose

| Where | Why it is right |
| --- | --- |
| The hook and the attribute bundles (`Attrs`, `markers.js`) | They are two halves of one contract. A marker added to a bundle and not read, or read and not added, is a bug. One list of marker names on each side, kept next to each other; `KitCase` and the hook's development check test them together (R §4.4) |
| The hook and the event names, payloads and replies of the core (S6) | The keyboard grid answers a reply (`%{ok: false, error: …}`) in the same handler. Versioned with the contract |
| The live core and the model | The core checks every event against the person's model (names looked up as text). Indirection here would only hide the check |
| `State` and the URL format | The URL is the state's serialised form; `put_state/3` speaks the same vocabulary (R §5.4). One module owns both directions |
| `Operation` and the safety order | Confirm → checks → veto → re-read → action is one sequence. It lives in one function per write so that no adapter can reorder it (D-before) |
| `Present` and `Sensitive.scrub/2` | A row can be drawn only from what `Present` returns, and `Present` scrubs first. Not a seam: making it swappable would make the rule optional |
| `Model` and the topic modules of part 1 | The verifiers and the model use the same rules (`docs/agents/architecture.md`, "The rules of a declaration live in one module per topic"). Sharing them is the point: a declaration that compiles is one the model can build |
| `Query`, `Record` and the table's read action | The re-read before a write must run the same action, with the same arguments and page values, as the page read (R §11.5: "the re-read … runs the same action with the same arguments as the page read") |
| `Live.Registry`, streams, async keys, upload names | One id names all four. Cleanup by id prefix must remove them together, or a portal outlives its row (R §10.3 "the mistake") |
| `Live.Core.Files` and `Act`/`Edit` | LiveView consumes an upload around the action (`consume_uploaded_entry`); the action must run inside it (R §3.1). This keeps uploads in 2b |
| `Notifier` and `Listener` | The message shape is private between them; a host never matches on it |

---

## 7. Other UI technologies (O-ui)

### 7.1 What each would mean

| Technology | What it is | How it would sit on the table |
| --- | --- | --- |
| React or Vue inside LiveView (`live_react`, `live_vue`) | A LiveView renders `<.vue …>` / `<.react …>`; the client component gets props and sends events back | The LiveView path stays: same `Table`, same core, same streams. A kit whose parts are client components instead of HEEx. `live_vue` documents "Phoenix Streams Support with efficient patches", passes `items={@streams.items}`, sends prop changes as JSON Patch, and sends events back with `phx-click` or `useLiveVue().pushEvent()`; it has `useLiveUpload` for uploads. `live_react` lists "Phoenix Streams as props" and "Incremental Prop Updates". [docs, live_vue README and hexdocs `basic_usage`, `architecture`; live_react README; versions not pinned, not tried] |
| Hologram (hologram.page) | Elixir compiled to JavaScript. Page and component **state lives in the browser**. Actions run in the browser; commands run on the server over HTTP (`command(name, params, server) -> %Server{}`, results go back with `put_action/3`). Server push by channels (`put_subscription`, `Hologram.Realtime.broadcast_action/3`) over SSE. No LiveView. [docs: `/docs/architecture`, `/docs/commands`, `/docs/realtime`] | No socket, no stream, no `attach_hook`. A Hologram adapter would be Hologram components drawing rows held in client state, and Hologram commands that call the data layer (2a) directly. The server holds nothing between commands |

### 7.2 What this asks of our layering

The seam to a UI technology must be **data**, not HEEx:

- **Out:** the column model as the person sees it, the table state as URL
  params, the rows as `Present` gives them (key, texts, input values, flags;
  scrubbed, hidden fields absent), the offered actions and their inputs,
  messages and errors. All plain maps, all serialisable.
- **In:** intents (`Intent`): sort, filter, page, page size, arguments,
  expand, save cell with typed text, clear, reveal, pick, run action, submit
  panel, bulk with a selection, read again. Each is a claim.
- **Between:** everything that touches Ash stays in 2a: `Model.for_actor`,
  `State.from_params`/`fit`, `Query`, `Operation` (checks, veto, re-read,
  action, page values), `Event`.

This fits what was decided and researched, with one limit. R §3.1 and R §8
decision 1 rejected a pure reducer **for the LiveView path**: streams, async,
uploads and replies live on the socket, and an effect list would rewrite the
socket API. That still holds. The target does not build a reducer. It cuts
lower: the data layer is a set of plain functions over values
(`Caller`, `Model`, `State`, `Intent` → outcome), and the LiveView core is
the first caller of them. A Hologram adapter would be a second caller. It
needs no effect list, because it has no socket to apply effects to.

| Layer | LiveView path | React/Vue in LiveView | Hologram |
| --- | --- | --- | --- |
| 2a data (`Model`, `State`, `Query`, `Operation`, `Present`, `Intent`, `Event`) | used | used | used, directly from commands |
| 2b live core (registry, streams, async, uploads, portals, `push_event`, listener) | used | used | **not used**. Its own: client state, commands, channels |
| 3 HEEx parts and kit | used | replaced by client components; bundles become props | replaced by Hologram components |
| Hook (keyboard grid, editing, widths) | used | needs the framework-agnostic JS modules and transport (S20), or its own | same as React/Vue, through Hologram's JS interop [unverified] |

### 7.3 The costs, honestly

1. **Rows.** In LiveView, `live_vue` and `live_react` say they take streams as
   props, so "streams are a must" (D-nested) can hold [docs, not tried]. With
   Hologram the rows live in browser state; the server keeps nothing. That
   keeps the spirit of the rule, but the server then also has no
   `rows` index to check a key against: every key is a claim checked only by
   the re-read through the table's read action. That is enough for safety
   (the re-read is the rule; the index is a second guard), but it is a
   weaker guard than today.
2. **State is a claim on every request.** Without a socket, sort, filters,
   page, open rows and panel state come back from the client each time.
   `State.from_params/2` already treats the URL that way. A panel's
   `AshPhoenix.Form` would have to be rebuilt per command.
3. **Per-person model per request.** `Model.for_actor/2` asks Ash
   (`Model.Access`, no query, but work). A stateless adapter rebuilds it per
   command or caches it per session.
4. **Who is asking.** Rebuilt per command from the session (Hologram
   middleware). It must come from server code, never from the client.
5. **Uploads.** LiveView uploads are part of 2b. React/Vue in LiveView can use
   them (`useLiveUpload`). Hologram has its own forms; how it takes a file is
   unknown [unverified].
6. **Live updates.** `Notifier` broadcasts on `Phoenix.PubSub`. Hologram
   would need a bridge to `Hologram.Realtime.broadcast_action/3` per
   subscribed page, and the re-read as the person per client.
7. **Keyboard and ARIA.** Today about 3,800 lines of hook code own them (`table_component.ex:4997-8768`). A client
   framework either reuses our JS modules through the transport (S20) on the
   same markers, or rebuilds the grid behaviour. Rebuilding loses the
   accessibility promise that the browser suite checks today.
8. **Nested tables.** The portal and the registry are LiveView answers. A
   client framework nests by itself; the data layer only needs the parent
   key and path, which it has.
9. **Events and veto.** `before_action` and the events are evaluated in 2a
   (`Operation`, `Event`), so every adapter gets them. Delivery of events
   (`send(self(), …)`) is 2b; Hologram would deliver with `put_action`.

### 7.4 What to do in the refactor, and what not

Do (cheap, and good for the LiveView path on its own):

- Keep 2a free of LiveView, checked by the test of 5.5.
- `Intent` (stage 3): the parsing of browser params in one module. It is
  the list of everything a person can ask for.
- `Operation` (stage 3, 6): one function per write with the safety order
  inside. The veto and page values need this place anyway.
- `Present` (stage 3): rows and cells as data, scrubbed. The kit needs it
  anyway ("a part never receives a record", R §4.4).
- Hook code as modules with one transport object (Q15).

Do not:

- No reducer with an effect list for the LiveView path (R §3.1, R §9).
- No JSON encoding inside the LiveView path; HEEx draws Elixir values.
  Serialisation is an adapter's job.
- No rows in assigns to suit a prop-based component.
- No generic "UI adapter" behaviour now: two adapters are needed to know its
  shape.
- No public `Model`, `State`, `Query` yet (R §8 decision 9). Document
  `Present` and `Intent` only when a second adapter is built (Q14).

---

## 8. Open questions

Each has a recommendation. None is decided by this document.

1. **What does `<AshDataTable.table>` become, given "no live components
   anywhere" (D-headless) and "the tag stays unchanged" (D-headless)?** A
   function component holds no state and cannot attach hooks to the host's
   socket. Options: (a) one thin live component per tag that attaches the same
   core to its own socket and renders `attached/1`; nested tables and pickers
   still use the registry and portals; (b) the tag needs an `attach` call in
   the host's `mount` (a breaking change); (c) drop the tag.
   **Recommended: (a).** The developer never writes or addresses a live
   component, nested tables have none, and existing pages keep working; it is
   what R §10.8 decision 21 says ("the live component then only wraps the
   top-level table"). Cost: in that mode `handle_info` and `handle_params`
   hooks are not available on a component socket (R §1.4), so live updates
   keep the `send_update` relay and the URL keeps the `url` attribute.

2. **One message tag or two?** The notifier's PubSub message
   (`{:ash_table, resource, type, key, tenant}`) and the planned event
   (`{:ash_table, table_id, {event, details}}`) share the tag. If the core
   subscribes the LiveView directly (Q10), both reach the host's mailbox.
   **Recommended: give the notifier message its own tag** (e.g.
   `:ash_data_table_changed`) and keep it private; the host matches only on
   events.

3. **Prefixes after the rename.** D-rename renames modules, macro, tag,
   gettext domain. It does not say: the event message tag, the notifier
   topic (`"ash_table:" <> resource`), `push_event` names (`ash_table:focus`),
   DOM events (`ash_table:selection`), `data-ash-table`, CSS properties
   (`--ash-table-ground`), the colocated import path, the config key.
   **Recommended: `ash_data_table` everywhere** (`:ash_data_table` tag,
   `ash_data_table:` names, `--ash-data-table-*`), in stage 0, in one go. One
   name is easier to search and to explain.

4. **Event names on the wire.** R §10.8 decision 23 recommends
   `ash_table:TABLE_ID:event`; it is not recorded as agreed.
   **Recommended: `ash_data_table:TABLE_ID:event`**, the id being the
   registry key. One lookup guards every event, and a `handle_event` hook
   halts only on its own prefix.

5. **Signature of the page-value functions.** R §11 has `fn assigns -> map`;
   D-before 5 says the function "is told which table is asking".
   **Recommended: `(assigns, table_ref) -> map`, where `table_ref` is
   `%{table: id, path: path, resource: resource}`; also accept arity 1.**
   Matches the decision and keeps the simple case simple.

6. **Page values on a router line.** D-before does not say how a mounted
   page gives them. R §11.5 proposes literals and `{Module, :function}` in
   route metadata. **Recommended: support `{Module, :function}` and literal
   maps; build it last in stage 6.** A mounted page has no other state, so
   the use is small.

7. **Where the value of a `page_argument` comes from.** D-before 3 says "the
   page must supply it". R §11.5 proposes an option `arguments`, same shape as
   `private_arguments`. **Recommended: an option `page_arguments`**, same
   shape and same `table_ref`. `arguments` already means the read action's
   arguments in the table's own words (argument line, `ID[a]`).

8. **How a row offers "open" (D-nolinks).** Not decided: declared in the
   `table` block, or asked for by the page. **Recommended: by the page**
   (`open: label` at attach, on the tag, on the router line), because only
   the page knows what "open" means for it; the event is `:row_opened` with
   the key. A table placed on two pages may want it on one only.

9. **Which part is `AshDataTable.Notifier` in?** It is what a resource
   gets from its declaration and depends only on part 1 and `Phoenix.PubSub`,
   like `Ash.Notifier.PubSub` sits with the resource in Ash. **Recommended:
   part 1**, as `AshDataTable.Resource.Notifier`. Then the transformer edge
   (V6) is inside part 1.

10. **How live updates reach an attached table.** A LiveView can take PubSub
    messages in a `handle_info` hook; the listener process exists because a
    live component cannot (`lib/ash_table/listener.ex:4-8`). **Recommended:
    keep the listener in every mode, with the relay function as the only
    difference** (`send_update` for Q1(a), `send(view, …)` + `handle_info`
    hook for attached and the page). One mechanism, and the 100 ms batching
    stays where it is.

11. **The source seam for rows (S1).** Owner: look at replaceable parts once
    feature complete. **Recommended: do not create the behaviour in the
    refactor; keep the rule that only `Query`, `Record`, `Pick`, `Bulk` call
    Ash reads, enforced by the test of 5.5.** Then a later `Source` is a
    change in four modules.

12. **Where a kit is named.** R §8 decision 11 recommends `config
    :ash_data_table, kit:` plus `kit` per table and per router line; not
    recorded as agreed. **Recommended: as R says.** It is how `layout` and
    `gettext_backend` are named today.

13. **`AshDataTable.Routes` in 2a or 4?** It reads the router's routes to find
    where a table is mounted, for the full-view link (`Related.path/5`).
    **Recommended: 2a.** It is a pure function of a router module, and the
    alternative (the wiring passes a link function down) adds an option to
    every mode for one link.

14. **Document `Present` and `Intent` as public?** They are the data contract
    of section 7. **Recommended: build them in stage 3, keep them internal
    (`@moduledoc false`) until a second adapter exists.** R §8 decision 9 holds
    for the same reason: structs still change.

15. **How the hook code is shipped.** Today colocated hooks inside the
    component's HEEx (`phoenix-colocated/ash_table`). Options: (a) several
    colocated hooks, one per `Parts` module; (b) plain JS files in the package
    (`assets/js`, imported as `phoenix_live_view` is), with the transport
    object (S20). **Recommended: (b).** About 3,800 lines of JavaScript in HEEx
    strings cannot be linted or unit-tested, the grid hook is one object that
    cannot be split over colocated scripts, and (b) is what makes the hook
    usable by another UI technology. Cost: one more line in the host's
    `app.js` and an installer change.

16. **Names of the held value and the reader struct.** `AshDataTable.Table`
    (R §5.1) sits next to `AshDataTable.Resource.Table` (the declaration of a
    table). **Recommended: keep `AshDataTable.Table`** for the value the host
    holds (it is what people will call it), and `AshDataTable.Caller` for who
    asks plus page values. Alternatives: `Handle`, `Grid`; `Asker`, `Viewer`.

17. **How dependency rules are checked.** **Recommended: the ExUnit test of
    5.5, no new dependency.** `boundary` if the parts grow sub-boundaries.

18. **Is `put_state/3` allowed to set the page size and arguments?** D-events
    says "set filters"; R §5.4 says sort, filters, page, arguments.
    **Recommended: the whole URL vocabulary**, since it goes through
    `State.from_params/2` and is checked like a URL.

19. **Order inside stage 6.** **Recommended: page values and veto first**
    (they change `Operation`), then events, then commands, then the open
    event. Events depend on `Operation`'s outcomes.

20. **A React/Vue/Hologram adapter in v1?** **Recommended: no.** Keep it
    possible through 7.4. Build one only after the first release, and
    `live_vue` first: it keeps the LiveView path, streams and uploads.

---

## 9. Current → target checklist

Each item names the modules it creates or changes. Stages from the
coordinator's plan.

### Stage 0: rename (D-rename)

- [ ] Package and app `ash_data_table`; `mix.exs`; `AshTable.*` → `AshDataTable.*` in `lib/`, `test/`, `demo/`.
- [ ] Router macro `ash_data_table/3` (`AshDataTable.Router`); tag `<AshDataTable.table>`.
- [ ] Gettext domain and `priv/gettext/ash_data_table.pot`; `demo/priv/gettext/de/LC_MESSAGES/`.
- [ ] Config key `:ash_data_table` (`layout`, `gettext_backend`, `translate_error`).
- [ ] Installer `Mix.Tasks.AshDataTable.Install`; colocated import path.
- [ ] Prefixes per Q3 (message tag, topic, `push_event`, DOM events, `data-*`, CSS properties).
- [ ] Docs, guides, `CONTEXT.md` title, `docs/agents/architecture.md`, repository name.

### Stage 1: split

- [ ] Directories per part (5.5); the dependency test in report mode (`test/architecture_test.exs`).
- [ ] Move `Model.CellType` → `Resource.CellType`; `Model.Operator` → `Resource.Operator`; `Model.humanize/1` → `Resource.Words`; `Sensitive.sensitive?/typed?/empty?` → `Resource.Exposing` (V2–V5).
- [ ] `Resource.Embedding` stops building `Model.Field` (V1).
- [ ] `Resource.Relating.table?/1` stops calling `AshDataTable.Resource` (V8).
- [ ] `Notifier` placed per Q9 (V6).
- [ ] `label/1` out of the tag module into 2a (V11).
- [ ] Function components → `AshDataTable.Parts.*` (4.5), still reading today's assigns.
- [ ] `render/1` → `Parts.Grid`, `Parts.Heading`, `Parts.Arguments`, `Parts.Selection`, `Parts.Messages`, `Parts.Summary`.
- [ ] Hooks moved with the markup, or to JS files per Q15 (4.5 table).
- [ ] `shown_as/1` from `AshTable.Components` into `Resource.Presenting`.
- [ ] Update `docs/agents/architecture.md`.

### Stage 2: one state value

- [ ] `AshDataTable.Live.Entry`: today's ~55 assigns of `mount/1` with their comments.
- [ ] `AshDataTable.Table`: options, `Caller`, `tables` registry, stream-name pool; replaces the process dictionary `@tables` (V14).
- [ ] `AshDataTable.Caller`: reader options from `reader/1` and `Query.reader_opts/1`.
- [ ] `AshDataTable.Live.Registry`: stream names, async keys `{:ash_data_table, id, …}`, upload names, by id.
- [ ] `Parts.*` read `@table` / the entry, not loose assigns. Measure the `/tasks` diff before and after (R §6 stage 3).

### Stage 3: core

- [ ] `AshDataTable.Intent`: parse every event of `docs/agents/architecture.md` "Events".
- [ ] `AshDataTable.Operation`: one function per write; the checks of today's handlers; re-read; outcome.
- [ ] `AshDataTable.Present`: rows and cells from records; `Sensitive.scrub/2` inside.
- [ ] `AshDataTable.Live.Core` and `Live.Core.Reading`, `.Cells`, `.Panel`, `.Picker`, `.Bulk`, `.Files`, `.Nesting`, `.Updates`, `.Url` (4.8 table).
- [ ] Event names namespaced per Q4; hooks push with the table id.
- [ ] The component (`table_component.ex`) delegates to the core; nothing else left in it.
- [ ] Dependency test fails on violations from here on.

### Stage 4: attach, function component, wiring on top

- [ ] `AshDataTable.attach/4`, `detach/2`: hooks for `handle_event`, `handle_async`, `handle_info`, and `handle_params` with `url: true`; first read in place.
- [ ] `AshDataTable.attached/1` with `streams={@streams}`.
- [ ] `AshDataTable.Live.Page` uses `attach` (R §8 decision 8).
- [ ] `<AshDataTable.table>` per Q1 (`AshDataTable.Live.Embedded`).
- [ ] Listener relay per Q10.
- [ ] The mode-independent demo tests run three ways: mounted, embedded, attached (R §3.6).

### Stage 5: nesting through portals (D-nested, D-events "one mechanism")

- [ ] Nested tables and pickers as registry entries with their own streams (`Live.Core.Nesting`, `Live.Registry`).
- [ ] `Parts.Related` renders portals at the top level, parents first; `Parts.Picker` at page level.
- [ ] One `close(prefix)`: async cancel, uploads cancelled and disallowed, stream reset, entry removed, stream name back to the pool.
- [ ] Remove the nested `live_component`; same in all three modes.
- [ ] `AshDataTable.Test`: read a nested table from its portal; send its events by name. `DemoWeb.TablePage` uses it.
- [ ] Browser tests of the portal combination itself (R §10.7 point 2).

### Stage 6: events, commands, page values, veto (D-events, D-before, D-nolinks)

- [ ] `Caller` holds `context`, `private_arguments`, page arguments, `before_action` (Q5, Q6, Q7).
- [ ] `Query`, `Record`, `Act`, `Edit`, `Bulk`, `Pick`: context on every call; private arguments filtered per action; reads by `Ash.Query.set_argument/3` (R §11.5).
- [ ] `AshDataTable.Request`; `Operation` asks `before_action` after the checks and before the re-read; bulk asks once.
- [ ] DSL `page_argument` in `Resource.Action`; rule in `Resource.Acting`; verifier; panel never asks it.
- [ ] `AshDataTable.Event` and `Live.Core.Notify`: the events of D-events and the open event (Q8); `notify` on tag, attach, router line.
- [ ] Commands `refresh/2`, `put_state/3`, `clear_selection/2`, `selected_records/3` (Q18).
- [ ] Guide: the record in an event is not scrubbed of `sensitive?` values; it is server code's.

### Stage 7: component contract and kit (D-parts, D-headless)

- [ ] `AshDataTable.Attrs`: a bundle for every element, rows and cells included.
- [ ] Hooks find everything by markers; no tag selectors (R §10.3: about 75 statements in 25 functions); hooks stop toggling daisyUI classes.
- [ ] `AshDataTable.Kit` (behaviour, `use`, contract version, `class/2`); `AshDataTable.Kit.Default`.
- [ ] Kit named per Q12; resolution for a cell: column's component, kit's `cell/1`, default (R §4.7).
- [ ] `AshDataTable.KitCase` and `AshDataTable.Test.Resource`.
- [ ] Development-mode marker check in the hook.
