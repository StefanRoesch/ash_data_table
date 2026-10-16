# Target architecture of `ash_data_table`

Status: **agreed with the owner on 2026-10-14**; amended after an adversarial
critique and its review ([target-review.md](target-review.md)); answers in
[target-questions.md](target-questions.md). Nothing in it is built yet, except
where a line says "done". Code references are of `6e60fad`.

Names are the names after the rename (`AshDataTable.*`). Words are those of `CONTEXT.md`.

How to read the sources in this document:

| Mark | Means |
| --- | --- |
| `today: path` | Checked in the code at `6e60fad`. Paths are from the repository root. |
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
| **D-1014** | The owner's decisions of 2026-10-14 on the review: F1 (sensitive values) and review questions RQ1–RQ6 |
| **O-ui** | The owner's wish of 2026-10-14: React, Vue or Hologram components should work too "if possible". A goal to keep possible; no adapter in v1 (Q20) |
| **R §n** | `ash_reference/headless-table-architecture.md`, section n (research, not a decision unless a D says so) |
| **Q n** | A question of section 8. All are answered |
| **F n**, **RQ n** | Finding n (section 3) and question n (section 5) of `target-review.md` |

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
the browser, takes the veto's answer, hands the page values to Ash, scrubs
sensitive values and says what happened, as data: values and message terms,
never words (F2, RQ6). The words are made by a translation step beside the
drawing. The upper layer, **live**, is the core over a LiveView socket: one
value under one assign holding a flat registry of tables, one stream per
table, async reads, uploads, events to the host (D-headless, D-nested,
R §10). There is no live component in the core. Nested tables and pickers are
registry entries shown through `<.portal>`.

There are three ways of using a table: the router line, `attach` with the
plain function component, and the tag `<AshDataTable.table>`. `attach` and
the plain component have no live component at all. The tag is a ready-made
default wiring: one live component that holds the same core and renders the
same plain component (Q1). All three run the same core and the same function
components (D-events). The developer reacts to events. With `attach` and on
the router page, the developer may also give commands: "read again", "set
this state", "clear the selection". A table placed with the tag sends events
only (RQ4). No value from the browser and no documented option can skip a
safety check of a write (D-events, D-before, F20).

The core hands the drawing no sensitive value, by construction. The one way
to such a value is the "Show" command for one cell (D-1014, F1).

**The coupling principle.** Code is tightly coupled only where a change on
one side must always change the other: the hook and the markers it reads,
the core and the model, the URL format and the state module, the write
pipeline and the safety order. Everywhere else a part talks to another
through a named seam (a behaviour, an option with a type, a message shape,
an attribute bundle), and an automatic test checks the direction of every
dependency. Each feature has one findable place per part (F13).

**Other UI technologies (O-ui).** The refactor cuts the internals' data layer
so that it has a data contract (rows as the person may see them, the column
model, the offered actions) and a typed set of intents coming back. Then a
React or Vue adapter inside LiveView, or a Hologram adapter without LiveView,
could sit on that layer without another refactor. The contract stays internal
until a second adapter exists (Q14). No adapter is built in v1; `live_vue`
comes first afterwards (Q20). Section 7 says what it would cost.

---

## 1. Goal and principles

### 1.1 Goal

- A developer can use the table without any wiring (router line), place it
  in a page (tag), or wire it into their own LiveView (`attach`) (D-parts,
  D-headless).
- No live component in the core, nested tables included (D-headless,
  D-nested). The tag is one live component at the top that holds the same
  core; nested tables get their state from the top in every mode (Q1).
- Streams are a must: the server does not hold the rows (D-nested).
- A developer can replace the look against a defined and checkable contract
  (D-parts, D-headless "fully headless contract").
- Each feature has one findable place per part (F13).
- The code is state of the art and Ash-conform (D-next).

### 1.2 Dependency direction

```
4 Wiring ─────────────► 3 UI components ─────┐
   │                      │                   ▼
   │                      └──► 3w Words ───► 2a
   ├─────────────────► 2b Internals: live ──► 2a Internals: data ──► 1 Declaration ──► Ash, Spark
   └──────────────────────────────────────────────────────────────────┘ (4 may use any lower part)
```

- 3 and 2b do not depend on each other. The function components draw from
  the data the core holds (structs of 2a, given through `Present`); the core
  never renders.
- **3w, the words**, is the translation step beside part 3: it turns the
  values and message terms of 2a into text in the person's language (F2,
  RQ6). 2b and 3 call it; 2a never does.
- 1 depends on Ash and Spark only, plus one leaf of 3: the column component
  contract (`AshDataTable.Component`, `.Component.Column`), see 5.2.
- Rules and checks are in section 5.

### 1.3 What "pure" means here

A module is **pure** when it takes values and returns values, and holds no
socket and no process state: no `Phoenix.LiveView.Socket`, no `send`, no
PubSub, no process dictionary of its own, no `Process.put`.

One thing is allowed and does not make a module impure:

- **Calls to Ash as the person.** Reads, `Ash.can/3`, `Ash.can_see_fields/4`,
  actions. They are the table's data. They take the reader options
  (`scope`, `actor`, `tenant`, `authorize?`) as arguments.

2a returns messages as terms; it makes no words (F2). So "pure" here is
"LiveView-free, process-free and word-free", not "side-effect free".

### 1.4 Where state lives

| State | Lives in | Who changes it |
| --- | --- | --- |
| What a table is (columns, actions, options) | The resource, compiled by Spark | The developer, in code |
| The model, same for everybody | The registry entry of the table (today the `built` assign, `lib/ash_table/live/table_component.ex:623`, `build/1` `:851`) | Built once per entry |
| The model for this person | The registry entry (today `model`, rebuilt on every `update/2`) | Rebuilt when who is asking changes |
| Sort, filters, arguments, page, page size | The registry entry; and in the URL when the top table is told so (today `url` attr, `lib/ash_table.ex:166`) | Events, commands, `handle_params` |
| Nested tables' sort, filters, page | Their registry entries only, never the URL (today `lib/ash_table/live/page.ex:209-211`) | Events |
| Rows | The stream, that is the browser. The server keeps the keys of the page and the failed edits (today `rows`, `failed`) | Reads, writes, live updates |
| Selection | The registry entry holds the selected keys, as claims: read again before use. The browser mirrors them (RQ1). The entry gets the field in stage 2; it is used from stage 6. Today the hook keeps the keys (section "selecting" of `.Grid`, `table_component.ex:7497`) and the server only the mode (`selecting/2`, `:792`) | The person; commands |
| Column widths, hidden columns, scroll | The browser only | The person |
| Open action panel (`AshPhoenix.Form`), open picker | The registry entry. The form stays in the entry; the drawing gets `Present`'s field map (F1) | Events |
| Uploads in flight | The LiveView socket (`allow_upload`) | LiveView |
| Listener of live updates | A process per table; its pid in the registry entry | Core |
| Page values, veto, notify target, time zone | The value under the host's assign (`Caller`), set at attach or by the tag. Page values and veto are functions; the live layer calls them with the current assigns (F8) | Server code only |

### 1.5 What must stay true (safety)

These are today's rules (`docs/agents/architecture.md`, "Safety rules"). The
target puts each in one place of part 2a, so that no adapter can wire it away.

| Rule | Where it lives in the target |
| --- | --- |
| Read again as the person before every write (save, action, reveal, pick, bulk) | `AshDataTable.Record`, `AshDataTable.Pick`, and the write pipeline `AshDataTable.Operation` (new) that every write goes through |
| Only `public?` actions run, the read actions of nested tables and pickers included | The verifiers (1) refuse others; the model (2a) offers nothing else |
| `authorize?` and the reader options on every Ash call | `AshDataTable.Caller` (new) holds them, built from server code only; 2b passes `Caller.reader_opts/1` to every 2a function, which keep their keyword `opts` (F7) |
| Nothing sensitive reaches the browser before "Show" | **By construction** (D-1014). Every path from the core to the drawing goes through `AshDataTable.Present`, which drops or masks sensitive values first: rows, cells, the action panel's fields, picker rows and labels, failed edits, messages. No part gets a record, an `AshPhoenix.Form` or a changeset. Events to the host carry the record with sensitive values masked. The one way to a sensitive value is the reveal command (`Operation.reveal`): one cell, read again as the person, field policy checked, the value returned in the reply only. A sensitive panel field starts empty; "Clear" sends only the instruction |
| Values from the browser are claims | `AshDataTable.Intent` (new) parses them; `State.from_params/2` and `State.fit/2` keep only what the model allows; every key is read again. Selected keys are claims too (RQ1) |
| An announcement is a claim | `AshDataTable.Query.rows/4` and `any?/5`, as today |
| A summary says no more than the rows | `AshDataTable.Query.summaries/4`, as today |
| No check can be skipped | Nothing from the browser and no documented option can skip a check. Server code of the host is trusted; it can stop an event from reaching the table, but it cannot make the table write without the checks (F20). The event handlers are the library's (R §2.4, R §9); the developer gets events and commands, never a handler in the path; `before_action` sees no record, no value, and can only halt (D-before) |
| Order of a write: confirm in the browser → the table's own checks → `before_action` → re-read as the person → the action with context and private arguments | `AshDataTable.Operation` (D-before). The checks and the veto run in the LiveView process, before any async start (F9) |

---

## 2. Moving parts

"Replaceable" means a developer can put their own implementation behind a
seam. "Configurable" means a developer chooses among values the library
offers. "Fixed" means neither.

| # | Moving part | What varies | Who decides | When | Replaceable or configurable | Now or later |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Source of rows and counts | Where the page, the count, one record and the selected records come from. Today an Ash read through the table's read action (`lib/ash_table/query.ex`) | Declaration (the read action) | Compile time | Fixed. No `Source` behaviour now; a checked rule keeps it possible: only `Query`, `Record`, `Pick`, `Bulk` read from Ash (Q11, D-after-research) | Later |
| 2 | Source of summary numbers | Today `Ash.aggregate/3` in `Query.summaries/4` (`lib/ash_table/query.ex:406`); a manual read action is a compile error (`lib/ash_table/resource/summarising.ex:77`) | Declaration (`summary` on a column) | Compile time | Fixed now; replaceable later (D-after-research: "a replaceable source of the numbers comes later (agreed)") | Later |
| 3 | Writes | Which update, create, destroy and generic actions run | Declaration (`table` block) | Compile time | Fixed. No command makes the table write (D-events) | Now |
| 4 | Drawing of the table (kit) | Markup and classes of every part | Config, per table, and on the router line (Q12) | Mount | Replaceable (D-parts, D-headless) | Stage 7 |
| 5 | A column's cell and editor | Markup of one column's cells and its control | Declaration (`component` on a column) | Compile time | Replaceable, exists today (`lib/ash_table/component.ex`) | Now |
| 6 | Browser behaviour (keyboard, focus, editing, widths, scrolling) | Nothing for the developer; it reads markers | Library | — | Fixed. Configurable through CSS custom properties only (today `--ash-table-ground`, `--ash-table-bottom`; `--ash-data-table-*` from stage 0) | Now |
| 7 | Where the table's state lives | URL or memory, per top-level table | Host page (`url` on the tag, `url: true` at attach); the router page always uses the URL | Mount | Configurable | Now (tag, page); stage 4 (attach) |
| 8 | Event receivers | Which events the host gets | Host page (`notify`) | Mount | Configurable | Stage 6 (D-events) |
| 9 | Commands in | Read again, set state, clear selection, read the selected records | Host page code, with `attach` and on the router page only; a tag sends events only (RQ4) | Per event | API, not replaceable | Stage 6 (D-events) |
| 10 | Page values | `context`, `private_arguments`: a map, or a function of the page's state that is told which table asks | Host page | Called by the live layer with the current assigns each time an action is built; 2a gets the result (F8) | Configurable | Stage 6 (D-before) |
| 11 | Veto | `before_action`: `:cont` or `{:halt, message}` before every write | Host page | Per write, in the LiveView process | Replaceable (a function) | Stage 6 (D-before) |
| 12 | Public argument filled by the page | `page_argument :name` inside a table's `action`; the value from the page option `page_arguments` (Q7) | Declaration (which argument) and host page (its value) | Compile time and per action | Configurable | Stage 6 (D-before) |
| 13 | Time zone of date-times | The zone a date-time is shown, typed and filtered in | Host page (D-gaps): `time_zone` attr of the tag (`lib/ash_table.ex:180`); for a mounted table the socket assign the domain names as `time_zone_assign` (`lib/ash_table/domain/info.ex:62-77`) | Mount | Configurable. Checked and applied by `AshDataTable.Zone` (`lib/ash_table/zone.ex`) | Now |
| 14 | Live updates | On or off; the PubSub server | Declaration (`live? true`), domain (`pub_sub`), host page (`live?`) | Compile time and mount | Configurable. Transport fixed: `Phoenix.PubSub` | Now |
| 15 | Texts and translations | The Gettext backend, the error translator | Config `:gettext_backend`, `:translate_error` (today `lib/ash_table.ex:31-43`) | Run time | Backend replaceable (any Gettext backend); texts configurable by translation | Now |
| 16 | Authorization inputs | `scope` or `actor` and `tenant`; `authorize?` | Host page (tag, attach), router line, domain defaults (`scope_assign`, `actor_assign`, `tenant_assign`, `authorize?`) | Mount; again when who asks changes | Configurable. Never from the browser | Now |
| 17 | The layout around a mounted table | Function component the page is rendered in | Config `:layout`, router option `layout:` | Render | Configurable | Now |
| 18 | Uploads | Accepted types, size per file argument | Declaration (`upload` in the `table` block) | Compile time | Configurable. Mechanism fixed: LiveView uploads | Now |
| 19 | Name, heading, id, label | How the table is named on the page | Host page (tag attrs, router `id:`) | Mount | Configurable | Now |
| 20 | Page sizes, depth, pinned label column | `page_sizes`, `max_depth`, `sticky_label?` | Declaration | Compile time | Configurable | Now |
| 21 | The "open" control of a row | Whether a row offers "open", and its label | Host page (Q8): `open:` at attach, on the tag, on the router line | Mount | Configurable | Stage 6 (D-nolinks) |
| 22 | UI technology | HEEx today; React or Vue in LiveView, or Hologram, later | The developer | — | Replaceable later, through the data contract of section 7. None in v1 (Q20) | Later (O-ui) |
| 23 | Who is asking changes | A login on the same page | Host page | Per event | `attach/4` again with the same name replaces the reader and reads again (R §5.2) | Stage 4 |
| 24 | Which of a resource's tables | Default or named table | Host page (`table:`), declaration (named tables, fragments) | Mount | Configurable | Now (D-fragments) |

---

> **Paths after the rename (stage 0, done 2026-10-14):** where this document points at today's code as `lib/ash_table/…` or `AshTable.*`, read `lib/ash_data_table/…` and `AshDataTable.*`.

## 3. Seams

"Exists" means it is in the code today. "New" means a refactor stage creates it.

| # | Moving part | Seam (exact interface) | Implemented by | What may cross | Status |
| --- | --- | --- | --- | --- | --- |
| S1 | Source of rows and counts | The functions of `AshDataTable.Query` (`read/3`, `read_related/4`, `matching/3`, `records/3`, `related_records/5`, `rows/4`, `any?/5`, `get/5`), `Record.fetch/3`, `Pick.chosen/3`, `Pick.current/3`. No `Source` behaviour now (Q11) | Library (Ash read) | Records **as the person may see them** (Ash applied policies and field policies); keys; never what the person may not read | Exists as functions. Rule to keep a later source possible: only `Query`, `Record`, `Pick`, `Bulk` call Ash reads (true today, see 5.4), checked by the test of 5.5 |
| S2 | Source of summary numbers | Today `Query.summaries(Model.t, State.t, parent, opts) :: {:ok, %{column => value \| :unavailable}} \| {:error, term}`. Later the same signature as a callback | Library; later a developer | Numbers only, by column; `:unavailable` where a field is hidden on some records | Exists as a function. Seam later |
| S3 | Kit | Behaviour `AshDataTable.Kit`: one callback per replaceable part, `part(assigns) :: Phoenix.LiveView.Rendered.t()`, and `class(part :: atom, state :: map) :: String.t()`. `use AshDataTable.Kit, contract: 1` gives defaults. Named by `config :ash_data_table, kit:`, per table (`kit=` / `kit:`) and on the router line (Q12). A new part is added with a default in `use AshDataTable.Kit`, so an existing kit keeps working; `contract:` goes up only when a part's assigns change incompatibly (F13) | Library (`Kit.Default`), developer | Values from `Present` and attribute bundles. Never a record, an `AshPhoenix.Form`, a changeset, a sensitive value, the actor, or another field of a row (R §4.4, F1) | New, stage 7 |
| S4 | Column component | Behaviour `AshDataTable.Component`: `cell(assigns)`, `editor(assigns)`, `commit() :: :enter \| :change`, `verify(Component.Column.t) :: :ok \| {:error, String.t}` | Library (Badge, Image, Progress, Slider), developer | `value`, `text`, `column` (`Component.Column`), `control` bundle, `label`, `place`. Never the record. A sensitive column has no component (today `lib/ash_table/model/column.ex:101`) | Exists (`lib/ash_table/component.ex:188-218`) |
| S5 | Attribute bundles | Functions of `AshDataTable.Attrs` that return an attribute map per element (ids, `role`, ARIA, `data-*`, `phx-*`, `phx-hook`). A part spreads it: `<nav {@root}>` | Library only | Markers. The hook reads nothing else (D-headless) | New, stage 7. Seed today: `@control` of an editor |
| S6 | Hook ↔ server | Events from the browser: one name per intent, namespaced by table id: `ash_data_table:TABLE_ID:event` (Q4). Payload: row key as in the DOM id, column or action name as text, typed text, selection. Replies: maps. Server → hook: `push_event` names `ash_data_table:focus`, `:ask`, `:bulk`, `:unselect`, `:leaving` with `table: id` (today `ash_table:…`, `lib/ash_table/live/table_component.ex:1551-4220`). `reveal` is the only reply that carries a sensitive value, for one cell; `clear` carries no value (F1) | Library on both sides | Claims only. Text, never atoms (today `column/2`, `action/2` look names up as text, `:4375-4383`) | Exists with plain names (`"sort"`, `"save"`); prefixes renamed in stage 0, events namespaced in stage 3c |
| S7 | Events out | `send(self(), {:ash_data_table, table_id, {event, details}})` to the LiveView process, opt-in with `notify` (`true` or a list of event names). Events: `:read`, `:read_failed`, `:row_saved`, `:row_created`, `:row_destroyed`, `:action_ran`, `:bulk_ran`, `:selection_changed`, `:row_expanded`, `:row_collapsed`, `:row_opened` (D-nolinks, Q8). Nested tables and pickers add their `path`. `:selection_changed` carries the selected keys the entry holds (RQ1); they are claims. The details of `:read` are to settle in the design note of stage 6 (F19) | Library sends; host receives in `handle_info/2` | Keys as maps; `record` as the action returned it to the person, with `sensitive?` values masked (`Sensitive.scrub/2`), as a row (D-1014): the host reads the record itself if it needs a sensitive field; `arguments` without `sensitive?` ones and without file contents; `changed`; `result`. An event only after success (D-events) | New, stage 6 |
| S8 | Commands in | `AshDataTable.refresh(socket, table)`, `put_state(socket, table, params)`, `clear_selection(socket, table)`, `selected_records(socket, table, selection)`; `detach(socket, table)`, built in stage 4. `table` is the attach name. Each returns the socket. Only with `attach` and on the router page; a table placed with the tag has no commands (RQ4). Reveal is a browser command (S6) through `Operation.reveal`; a host command for it, if wanted later, goes through the same function and checks (not a public command now) | Library; host calls | The whole URL vocabulary (`%{"sort" => …, "f" => …, "a" => …}`, Q18), parsed by `State.from_params/2`. Nothing that writes | New, stage 6 (D-events lists "read again, set filters, clear the selection"); `detach` in stage 4 |
| S9 | Page values | Options `context:` and `private_arguments:`, each `map \| (assigns, table_ref -> map)`, arity 1 accepted (Q5). `table_ref` is `%{table: id, path: path, resource: resource}` (D-before 5: "told which table is asking"). Called by the live layer with the current assigns; 2a receives the result (F8). On a router line: `{Module, :function}` or a literal map (Q6) | Host | Server values into Ash calls: `context:` on every call; private arguments only for names an action declares `public?: false`. Nothing from the browser | New, stage 6 |
| S10 | Veto | Option `before_action: (AshDataTable.Request.t, assigns) -> :cont \| {:halt, String.t}`. The request: table, path, resource, action, type, from, column, key (a claim), selection (a claim). Called by the live layer with the current assigns, in the LiveView process, before any async start; 2a receives the result (F8, F9) | Host | No typed value, no inputs, no record, no changeset, no socket (D-before) | New, stage 6 |
| S11 | Public argument from the page | DSL: `page_argument :name` inside a table's `action`. Value: the page option `page_arguments`, same shape as `private_arguments` (Q7) | Declaration + host | One value per declared name, merged over the params as `record_argument` is today (`lib/ash_table/act.ex:185-191`) | New, stage 6 |
| S12 | Live updates | Message `{:ash_table, resource, :create \| :update \| :destroy, primary_key, tenant}` on `Phoenix.PubSub` topic `Notifier.topic(resource, tenant)` (today `lib/ash_table/notifier.ex:17, 83`). From stage 0 the tag is the private `:ash_data_table_changed` (Q2). Listener: `Listener.start(pub_sub, topic, relay :: ([announcement] -> term))` (`lib/ash_table/listener.ex:31`). The listener stays in every mode; only the relay differs: `send_update` for the tag, `send(view, …)` and a `handle_info` hook for `attach` and the page (Q10) | Library both sides | A primary key and a tenant. Never a record | Exists |
| S13 | Texts | `config :ash_data_table, gettext_backend: Mod, translate_error: {m, f}`; Gettext domain (today `"ash_table"`, `"ash_data_table"` from stage 0). 2a returns message terms (`{:text, key, bindings}`, `{:ash, message, vars}`); the words (3w) make the text in the LiveView process or in the parts (F2) | Host | Strings | Exists; terms from stage 3b |
| S14 | Layout of a mounted table | `config :ash_data_table, layout: {m, f}`; router `layout: {m, f} \| false` (today `lib/ash_table/router.ex:53-56`) | Host | `flash`, `current_scope`, the time zone assign and the assigns named by the domain (today `lib/ash_table/live/page.ex:298-306`) | Exists |
| S15 | Authorization inputs | Tag attrs and attach options `scope`, `actor`, `tenant`, `authorize?`; router `authorize?:`; domain DSL `scope_assign`, `actor_assign`, `tenant_assign`, `authorize?`, read by `Domain.Info.reader/2` | Host | Server values only. Kept in `AshDataTable.Caller` (new) | Exists (as assigns); struct new in stage 2 |
| S16 | Defaults of asked arguments | DSL `ask :name, default: &fun/1`, given the page's assigns (today the `assigns` attr, `lib/ash_table.ex:185-188`) | Host | Page assigns into a default value | Exists |
| S17 | Time zone | The tag's `time_zone` attr; the domain's `time_zone_assign` for a mounted table (`lib/ash_table/live/page.ex:329`). Checked by `Zone.check!/2`; `Format.format/3`, `input/3`, `summary/3` and `Model.zoned/2` take it. Kept in `Caller` from stage 2 | Host | A zone name | Exists |
| S18 | URL state | Parameters under the table id: `ID[sort]`, `ID[f]`, `ID[a]`, `ID[c]`, `ID[page]`, `ID[per]`, `ID[of]` (today `State.to_params/2`, `Related.to_param/2`). Tag: `url` attr; attach: `url: true` with a `handle_params` hook | Library | Claims, parsed by `State.from_params/2`, `Related.from_params/5` | Exists for page and tag; attach in stage 4 |
| S19 | Data contract for a UI technology | `AshDataTable.Present` (rows, cells, panel fields, picker rows as the person may see them) and `AshDataTable.Intent` (what comes back). Section 7 | Library; a later adapter | Values (not texts, RQ6), flags; no sensitive value; intents as claims | New, stage 3a. Internal until a second adapter exists (Q14) |
| S20 | Browser transport | The hook's code talks to the server through one object: `push(event, payload) -> Promise(reply)`, `on(event, handler)`, `off(event)`. The LiveView hook is the first implementation. The other half of this seam is the hook's life cycle (`el`, `mounted`, `beforeUpdate(toEl)`, `updated`, `destroyed`): a second UI technology needs both (stage 1b drift check, finding 7) | Library | Event names and payloads of S6 | Built in stage 1b. An internal JS module, not a documented seam, until a second transport exists (F16). The package's `exports` expose only the hooks wrapped for LiveView until then |
| S21 | Test support | `AshDataTable.Test` (flush, nested tables through portals, events by name), `use AshDataTable.KitCase, kit: Mod` | Library; host's tests | — | `flush/1` exists (`lib/ash_table/test.ex`); rest new (D-nested: test helper "yes, if needed") |

---

## 4. Module matrix

### 4.1 Short names used in the matrix

| Short | Means |
| --- | --- |
| **1** | Part 1, declaration: `AshDataTable.Resource*`, `AshDataTable.Domain*` |
| **2a** | Part 2, internals, data layer: LiveView-free, makes no words |
| **2b** | Part 2, internals, live layer: the core over a socket, `AshDataTable.Live.Core*`, `AshDataTable.Live.Registry` |
| **3** | Part 3, UI components: `AshDataTable.Parts*`, `Attrs`, `Kit*`, `Component*`, `Components.*`, the JS |
| **3c** | The column component contract alone: `AshDataTable.Component`, `AshDataTable.Component.Column` |
| **3w** | The words, beside part 3: the translation step from values and message terms to text (`Text`, `Format`, the wording of `Errors`, `Gettext`) |
| **4** | Part 4, wiring: `AshDataTable` (the public entry), `Router`, `Live.Page`, the tag |
| **T** | Test support shipped in `lib/` |
| **LV** | `Phoenix.LiveView`, `Phoenix.Component`, `Phoenix.LiveView.JS` |
| Pure | In the sense of 1.3 |

"May depend on" lists parts and outside libraries. "Must not" lists what the
dependency test of section 5 forbids.

### 4.2 Part 1: declaration

All of part 1 is pure. It may depend on Ash, Spark, and 3c. It must not
depend on 2a, 2b, 3 (except 3c), 3w, 4, LV. The one exception is
`Resource.Notifier`, which broadcasts on `Phoenix.PubSub` (Q9).

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
| `.Presenting` | A column's `component`, `max_lines` | as today | 1 and 3c | `resource/presenting.ex` (`shown_as/1`, the words of a cell type, lives in `AshDataTable.Component`, which parts 1 and 3 may both call: owner, 2026-10-14, stage 1 drift check F7) |
| `.Uploading` | Limits of a file argument | as today | 1 only | `resource/uploading.ex` |
| `.Exposing` | Field-policy exposure; `sensitive?/1`, `typed?/1`, `empty?/1` of a field | as today plus the moved predicates | none | `resource/exposing.ex`; predicates from `lib/ash_table/sensitive.ex:41-61` |
| `.Summarising` | `summary` rules | as today | 1 only | `resource/summarising.ex` |
| `.Listening` | Live-update rules | as today | 1 only | `resource/listening.ex` |
| `AshDataTable.Resource.CellType` | Ash type → cell type | `of/2`, `classify/2` | none | `lib/ash_table/model/cell_type.ex` (moved, because 1 uses it) |
| `AshDataTable.Resource.Operator` | Filter operators per cell type | `available/2`, `to_ash/2`, `takes/1`, `predicates/2`, `negated?/1` | `CellType`, `Exposing` | `lib/ash_table/model/operator.ex` (moved, because `VerifyColumns` uses it) |
| `AshDataTable.Resource.Words` | A name in words | `humanize/1` | none | `Model.humanize/1`, `lib/ash_table/model.ex:2035` |
| `AshDataTable.Resource.Verifiers.*` (11) | Report mistakes at compile time | none (Spark) | Topic modules, `Info`, `Table` only (5.3) | `lib/ash_table/resource/verifiers/*.ex` |
| `AshDataTable.Resource.Verifiers.VerifyPageArguments` | `page_argument` names a public argument of that action, not one the panel also asks | none | as above | New, stage 6 (may be a clause of `VerifyActions`) |
| `AshDataTable.Resource.Transformers.Announce` | Gives a `live? true` resource the notifier | none | `Resource.Notifier`, inside part 1 | `resource/transformers/announce.ex` |
| `AshDataTable.Resource.Notifier` | The Ash notifier: broadcasts a key, with its own private message tag `:ash_data_table_changed` (Q2) | `topic/2` | 1, `Phoenix.PubSub`. Not pure (broadcasts). Part 1, as `Ash.Notifier.PubSub` sits with the resource in Ash (Q9) | `lib/ash_table/notifier.ex` |
| `AshDataTable.Domain`, `.Domain.Info`, `.Domain.Verifiers.VerifyPubSub` | The domain's `table` block | DSL; `authorize?/1`, `reader/2`, `assign_names/1`, `pub_sub/1`, `time_zone/2`, `time_zone_assign/1` | 1 only | `lib/ash_table/domain.ex`, `domain/**` |

### 4.3 Part 2a: internals, data layer

All pure in the sense of 1.3. May depend on 1, Ash, AshPhoenix (`AshPhoenix.Form`
works without LiveView). Must not depend on 2b, 3, 3w, 4, LV, Phoenix.PubSub,
Gettext. `Phoenix.Router` is the one Phoenix module allowed, on purpose, for
`Routes` (F15).

| Module | Responsibility | Public API | Today's code |
| --- | --- | --- | --- |
| `AshDataTable.Model` | Everything a table is drawn from, built from `Ash.Resource.Info` and the declaration (ADR 0001). The presentation hints (`component`, `max_lines`, `sticky_label?`, `editor`) are passed through: the core never branches on them (F3) | internal: `build/2`, `for_actor/2`, `zoned/2`, `defaults/2`, `supply/2`, `bulk_actions/1`, `loads/1`, `relationship/2`, `nested_create/2`, `summarised/1`, `label_column/1` (`hideable/1` moves to part 3, F3) | `lib/ash_table/model.ex` |
| `Model.Column`, `.Field`, `.Input`, `.Action`, `.Argument`, `.Relationship`, `.Pagination`, `.Limits` | Structs and small rules of the model | internal | `lib/ash_table/model/*.ex` |
| `Model.Access` | What Ash says the person may see and do, before any read | internal | `lib/ash_table/model/access.ex` |
| `AshDataTable.State` | Sort, filters, arguments, page, page size of one table; the URL vocabulary | internal: `from_params/2`, `to_params/2`, `fit/2`, `cycle_sort/3`, `filter/3`, `argue/3`, `to_page/2`, `resize/3`, … | `lib/ash_table/state.ex` |
| `AshDataTable.Related` | The `of` parameter of a full view | internal: `from_params/5`, `to_param/2`, `path/5` | `lib/ash_table/related.ex` |
| `AshDataTable.Routes` | Where a router mounts a table, read from the router's routes | internal: `default_id/2`, `table/4` | `lib/ash_table/routes.ex`. In 2a because `Related` needs it and it is a pure function over a router module (Q13). Its coupling to the router's metadata is named in §6 (F15) |
| `AshDataTable.Zone` | The page's time zone: checks a zone, says which values have one, turns a typed wall time into the instant Ash is given, an instant into the zone | internal: `utc/0`, `check/1`, `check!/2`, `local/2`, `zoned?/1`, `given/3`, `gaps/3`, `read/3`, `instant/2` | `lib/ash_table/zone.ex`. Its value lives in `Caller` from stage 2 (F17) |
| `AshDataTable.Caller` | Who asks and what the page adds: `scope`/`actor`/`tenant`, the time zone (`authorize?` as told and as resolved lives in each entry, `authorize_given` and `authorize?`; `Caller.authorize?` is removed in stage 4, D10), and the page-value and veto functions. Built from server code only. Holds no assigns (F8) | internal: `new/1`, `reader_opts/1` (the keyword `opts` the 2a functions take today, F7) | New, stage 2. Today: `reader/1` in the component (`table_component.ex:1273`), `Query.reader_opts/1` (`query.ex:726`) |
| `AshDataTable.Query` | Every read through the table's read action; summaries; live-update reads | internal: as today (keyword `opts`, F7); outcomes as message terms from stage 3b | `lib/ash_table/query.ex` |
| `AshDataTable.Record` | One row's record, read again as the person | internal: `fetch/3`, `key/2`, `load/3` | `lib/ash_table/record.ex` |
| `AshDataTable.Pick` | The record chosen in a picker, read again | internal | `lib/ash_table/pick.ex` |
| `AshDataTable.Edit` | Save one cell; open and put a map cell | internal | `lib/ash_table/edit.ex` |
| `AshDataTable.Act` | Row actions, table actions, create, through `AshPhoenix.Form` | internal | `lib/ash_table/act.ex` |
| `AshDataTable.Bulk` | A row action on a selection | internal: `run/5`; outcomes as message terms from stage 3b (F2) | `lib/ash_table/bulk.ex` |
| `AshDataTable.Operation` | The one pipeline every write goes through: checks the claim against the model, takes the veto's answer, reads again as the person, builds the action with the page values, returns the outcome and the event details. `reveal`: re-read as the person, field policy checked, returns one value; nothing else returns a sensitive value (F1) | internal: `save`, `clear`, `refer`, `run`, `submit`, `bulk`, `reveal`, each taking one 2a input value per write, for example `%Operation.Input{model, state, parent, caller_opts, key_known?: fun, form_values, page_values, veto_result}`; files through a `with_files(fn files -> … end)` function from 2b that wraps `consume_uploaded_entry`. Returns `{:ok, outcome} \| {:halted, message} \| {:error, errors}`, messages as terms. Exact shape: to settle in the design note of stage 3b (F9) | New, stage 3b (pipeline) and 6 (veto, page values). Today the steps are spread over `handle_event/3` clauses and helpers (`table_component.ex:2114-2873`, `2905-4384`) |
| `AshDataTable.Request` | What `before_action` is told | public struct (documented) | New, stage 6 (R §11.5) |
| `AshDataTable.Intent` | What a person asks for, parsed from any UI: `{:sort, column}`, `{:save, row, column, typed}`, … Names are text until looked up | internal until a second adapter exists (Q14) | New, stage 3a. Today: the pattern heads of `handle_event/3` |
| `AshDataTable.Event` | The details of each event, built from an outcome; the typed list of events. The record is scrubbed of sensitive values (D-1014) | public types; `details/2` internal | New, stage 6 |
| `AshDataTable.Present` | From the core's data to everything a part draws: rows and cells (key, values, input values, flags `editable?`, `hidden?`, `masked?`, `invalid?`); the open action panel's fields (value, errors, flags; a sensitive field is always empty, or holds what was typed in this panel); picker rows and the chosen labels; failed edits. Values, not texts: formatting is the drawing side's (RQ6). Calls `Sensitive.scrub/2` first (F1) | internal until a second adapter exists (Q14) | New, stage 3a. Today: `item/8` (`table_component.ex:1852`), `put_row/3` (`:1910`), `cell_content/4` (`:11788`), `typed_value/3` (`:11845`), `cell/3` (`:11872`) and `panel_value/3` (`:9485`) |
| `AshDataTable.Sensitive` | Scrub sensitive values before anything is drawn; the mask | internal: `scrub/1`, `scrub/2`, `mask/0` | `lib/ash_table/sensitive.ex` (predicates moved to `Resource.Exposing`) |
| `AshDataTable.Errors` | Where an error belongs (field, row, panel), as terms. Its wording moves to 3w (F2) | internal | `lib/ash_table/errors.ex` |

Today `Act`, `Bulk`, `Edit`, `Query`, `Model.Argument` and `Model.Input` make
words (`Text`, `Format`, `Errors`). Stage 3b turns the outcomes of
`Operation`, `Bulk` and `Query` into terms (F2). How far the rest goes, and
what `Model.Argument` gets in place of `Format` (V9), is to settle in the
design note of stage 3b.

### 4.4 Part 2b: internals, live layer

Needs the socket. May depend on 2a, 1, 3w, LV, Phoenix.PubSub. Must not depend on 3, 4.
The `Live.Core.*` modules are private file splits (`@moduledoc false`, no promise, F16).

| Module | Responsibility | Public API | Today's code |
| --- | --- | --- | --- |
| `AshDataTable.Table` | The one value the host holds under one assign: options, `Caller`, the flat registry of entries, the stream-name pool. Opaque; from stage 4 a public moduledoc ("pass it to `attached/1`"); the documented read-only fields (`id`, `state` as params, `count`, `total`, `loading?`, `error`) come in stage 6 (stage 4 D14) | public, opaque struct (R §5.1, Q16) | New, stage 2: one value per live component, holding the entry of that table; the registry of all tables in stage 5 (F5). Today: the assigns of `mount/1` (`table_component.ex:553-677`) and the process dictionary `@tables` (`:550`) |
| `AshDataTable.Live.Entry` | One table of the registry (top, nested, picker): model, state, rows index, failed, open rows, panel (with its `AshPhoenix.Form`), picker, selection mode, selected keys (claims, RQ1), live, summary, path, parent key | internal struct | New, stage 2, from today's assigns; the selected keys field in stage 2, used from stage 6 |
| `AshDataTable.Live.Registry` | Add, find, close by path (never by id prefix: closing `comments` must not close `comments_archive`); reconcile against what is rendered; stream names from a pool, prefixed with the top table's id (`"tasks:rows"`, `"tasks:rows_1"`); the names an id has configured are remembered on the socket across `detach` and given back to a table of that id attached again (stage 4 D4); async keys `{:ash_data_table, id, :read}`. Upload names stay in `Files.upload_name/2` | internal | New, stage 5. Today: `tidy/1`, `tables/0`, `close/1`, `rendered/1` (`table_component.ex:1349-1437`), `upload_name/2` (`:3907`) |
| `AshDataTable.Live.Core` | Socket in, socket out, for a table under a given assign: `init`, `handle_event`, `handle_async`, `handle_info`, `handle_params`. It reads and writes the `Table` through `Core.table/1` and `Core.put/2`, under the attach name kept in the socket's private data (stage 4 D1). Parses the event into an `Intent`, finds the entry, calls the page-value and veto functions with the current assigns, calls `Operation`, applies the outcome to stream and entry, makes the words, sends events | internal | New, stage 3c. Today `mount/1`, `update/2`, `handle_event/3`, `handle_async/3` of the component |
| `Live.Core.Reading` | Read in place or async, show, put a row, remove a row, the fill and error messages, summaries beside the read | internal | `table_component.ex:1092-1281`, `1605-1691`, `1692-2113` |
| `Live.Core.Cells` | Save, clear, reveal, refer, discard, dismiss | internal | `2905-3014` and their `handle_event` clauses |
| `Live.Core.Panel` | Row action, table action, create, panel events, submit, after a create or run | internal | `3295-3605`, `3715-3906`, `4150-4384` |
| `Live.Core.Picker` | Open, choose, cancel; inputs chosen in the panel | internal | `3015-3294` |
| `Live.Core.Bulk` | Selection actions and the bulk async run; the veto is asked before `start_async` (F9) | internal | `3606-3714`, `handle_async(:bulk, …)` (`:1634-1691`). `in_locale/1` (`:3698`, the locale fix of `d1489d6`) stays until stage 3b makes the run return terms |
| `Live.Core.Files` | Allow, consume around the action, cancel, drop | internal | `3907-4149` |
| `Live.Core.Nesting` | Expand, toggle, open a nested entry, portal target, close by path | internal | `relate/1`, `build/1`, `nested_model/2`, `creates/1` (`801-953`), `expand`/`toggle` clauses, `close/1` |
| `Live.Core.Updates` | Live updates: listen, hold, release, refresh, leave, notice | internal | `1282-1604` |
| `Live.Core.Url` | Patch the URL; `handle_params` hook | internal | `go/2`, `path/3`, `query_params/1` (`4473-4510`) |
| `Live.Core.Notify` | Send events to the host, opt-in | internal | New, stage 6 |
| `AshDataTable.Listener` | The process that subscribes and hands batches over; kept in every mode (Q10) | internal: `start/3`, `stop/1`, `flush/1`, `of/1` | `lib/ash_table/listener.ex` |

### 4.5 Part 3: UI components

May depend on 2a (structs, `Present`, `Intent` names), 3w, 1 (`Info` only
where a part needs a declaration fact), LV. Must not depend on 2b, 4. Pure
(function components). A part draws only from what `Present` gives it (F1).

| Module | Responsibility | Public API | Today's code (`lib/ash_table/live/table_component.ex` unless named) |
| --- | --- | --- | --- |
| `AshDataTable.Parts.Grid` | The grid skeleton: scroll area, `table`, header row, filter row, body rows, cells, footer, editor templates; the root that carries the `.Grid` hook. Gets `Model.hideable/1` with the markup that uses it (F3, stage 1) | internal component; parts through the kit | `render/1` `4511-5204` (grid `4686-4981`, editors `5075-5094`, scrollbar `5100`); `columns` `10916`; `resizer` `10828`; `editor` `11382`; view helpers `11607-11991`; `hideable/1` `model.ex:1011` |
| `Parts.Heading` | The line of the table's name; create; table actions | kit part `heading` | `4520-4548`; `create` `10626`; `table_actions` `10647` |
| `Parts.Arguments` | The argument line | kit part `argument_line` | `4567-4605`; `argument` `9119` |
| `Parts.Filter` | One column's filter control; values of "is any of" | kit part `filter` | filter form `4606`; `filter` `11013`; `choices` `11161` |
| `Parts.Selection` | The selection line and bulk buttons | kit part `selection_line` | `4615-4674`; `selection` `10537` |
| `Parts.Pagination` | Pages, "Rows per page" | kit part `pagination` | `pagination` `10702`; `pages` `10726` |
| `Parts.Panel` | The action panel, fields, groups, unions, chosen records; draws from `Present`'s field map, never from an `AshPhoenix.Form` (F1) | kit parts `panel`, `field`, `control` | `panel` `9308`; `field` `9587`; `group` `10008`; `groups` `10077`; `union` `10175`; `members` `10277` |
| `Parts.Picker` | The picker dialog around a registry entry | kit part `picker` | `picker` `9405` (`picker_reader` stays in the live layer: it builds who is asking — Caller / `Live.Core.Nesting`; stage 1 drift check F6) |
| `Parts.Related` | Relationship lines, the empty target cell of each open nested table (the wiring draws the portals), the full-view link | kit part `line` | `lines` `8977` (stage 1 drift check F5); `related` `10472`; `4549`, `5051-5074` (`nested_reader` stays in the live layer, as `picker_reader`; F6) |
| `Parts.Summary` | The footer summaries row | kit part `footer` | `summary` `10859`; `4982-5038` |
| `Parts.Messages` | Status live region, notice of changes, fill, error, loading, confirm dialog, failure popover, whole-text popover | kit parts `message`, `confirm` | `4633-4651`, `4675-4685`, `5095-5099`, `5116-5153`, `5164-5193` |
| `Parts.Editors` | Built-in editors: text counter, list editor | kit parts `cell`, `editor` | `count` `11427`; `list` `11488`; `list_item` `11538` |
| `AshDataTable.Attrs` | Attribute bundles for every element (S5) | internal; their content is the contract | New, stage 7. Today written inline in HEEx |
| `AshDataTable.Kit` | Behaviour and `use` macro, contract version, `class/2`; new parts get defaults (F13) | public | New, stage 7 |
| `AshDataTable.Kit.Default` | The daisyUI kit | public module | New, stage 7, from today's markup |
| `AshDataTable.Component`, `.Component.Column` (3c) | The column component contract | public (exists) | `lib/ash_table/component.ex`, `component/column.ex` |
| `AshDataTable.Components.Badge`, `.Image`, `.Progress`, `.Slider` | Shipped column components | public | `lib/ash_table/components/*.ex` |
| Hooks: `Grid`, `Panel`, `Picker`, `Pagination` | Browser behaviour, on markers only (D-headless) | the event names and markers of S5, S6 | `5205-8956`; shipped per Q15, below |

**The words (3w)**, beside part 3. Called by 2b and 3, never by 2a (F2, RQ6).

| Module | Responsibility | Public API | Today's code |
| --- | --- | --- | --- |
| The translation step | Turns message terms (`{:text, key, bindings}`, `{:ash, message, vars}`) into words in the LiveView process or in the parts. Name to settle in the design note of stage 3b (the review suggests `AshDataTable.Words`; `Resource.Words` already names `humanize/1`) | internal | New, stage 3b |
| `AshDataTable.Text` | Every text a person reads | internal: `t/2`, `n/3`, `label/1`, `error/1` | `lib/ash_table/text.ex` |
| `AshDataTable.Format` | What a cell or a summary shows, from a value; the text a control starts with. A helper of the drawing side that a later adapter can reuse (RQ6) | `format/2`, `format/3`, `input/2`, `input/3`, `summary/2`, `summary/3` (the `/3` take the zone; the `/2` use UTC) | `lib/ash_table/format.ex` |
| The wording of `AshDataTable.Errors` | What an error says | internal | `lib/ash_table/errors.ex` |
| `AshDataTable.Gettext` | The default backend without translations | public module (config default) | `lib/ash_table/gettext.ex` |

**How the hook code is shipped (Q15).** The hooks are real JS files in the
package. For LiveView, colocated hooks stay (zero setup) and are thin imports
of those files. Other UI technologies and custom builds import the same files
through `app.js` or npm. In stage 1 the hooks stay in the component module,
so the rendered `phx-hook` names do not change (M2). Stage 1b moves them; its
first step checks that a colocated hook that imports from the package works
in a release build.

How the hook code is organised: one ES module per section of today's `.Grid`
hook, one object that holds the shared state, and one internal transport
object (S20). The four LiveView hooks are thin and only wire the transport.
Today's sections and their target files:

| Today's `.Grid` section (line) | Target JS module |
| --- | --- |
| constants, `mounted`, `beforeUpdate`, `destroyed` (5602–6048) | `grid/index.js` |
| the counter of a text (6049) | `grid/counter.js` |
| the tree of grids (6117) | `grid/tree.js` |
| expanding (6510) | `grid/expanding.js` |
| the widths of the columns (6689) | `grid/widths.js` |
| hiding columns (6934) | `grid/hiding.js` |
| scrolling sideways (7172) | `grid/scrolling.js` |
| several values of a filter (7399) | `grid/choices.js` |
| selecting (7497) | `grid/selecting.js` |
| row actions (7783) | `grid/actions.js` |
| editing (7843) | `grid/editing.js` |
| the values of an array (8178) | `grid/arrays.js` |
| sensitive cells (8596) | `grid/sensitive.js` |
| the dialog (8711) | `grid/dialog.js` |
| the message of a failed cell (8732) | `grid/failure.js` |
| the whole text of a cell (8760) | `grid/whole_text.js` |
| `.Panel` (5272), `.Picker` (5465), `.Pagination` (5205) | `panel.js`, `picker.js`, `pagination.js` |
| (new) | `transport/live_view.js`; `markers.js` (the names of S5 in one place: started in stage 1b with `GRID` and `HANDLE`, filled in stage 7); `grid/shared.js` (constants, `PLACE`, page-wide state `page`; it keeps the grid's sections free of circular imports). The "shared-state object" is the merged hook `this`, plus `page` for what is shared across tables (stage 1b drift check, findings 5–6) |

### 4.6 Part 4: ready-made wiring

May depend on everything below. Needs the socket.

| Module | Responsibility | Public API | Today's code |
| --- | --- | --- | --- |
| `AshDataTable` | The public entry | `table/1` (the tag), `attach/4`, `attached/1`, `detach/2`, `refresh/2`, `put_state/3`, `clear_selection/2`, `selected_records/3`, `label/1`. The commands work with `attach` and on the router page only (RQ4) | `lib/ash_table.ex` (`table/1`, `label/1`; the internal attr `select`, `:193`, used by a picker's table); the rest new in stages 4 and 6 |
| `AshDataTable.attached/1` | Function component: draws a `Table` with the streams and uploads the host passes (`<AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />`: a function component cannot reach `@uploads`, and a library cannot assign it; stage 4 D5); renders the top table and the portals of nested tables and pickers. Must not be placed inside a stream item of the host's own (R §10.7, F11) | public | New, stage 4 (R §5.2 corrected: `streams={@streams}`) |
| `AshDataTable.Router` | Macro `ash_data_table/3` | public | `lib/ash_table/router.ex` |
| `AshDataTable.Live.Page` | The LiveView behind a router line; uses `attach` itself, in its first `handle_params` (`mount/3` has no URL and `live/4` no per-route session), and runs the params step once itself there (stage 4 D7) | none (reached by the route) | `lib/ash_table/live/page.ex` (R §8 decision 8) |
| `AshDataTable.Live.Embedded` | What `<AshDataTable.table>` renders: one live component per tag, a ready-made default wiring that holds the same core and renders the same plain component (`attached/1`) (Q1). In this mode live updates keep the `send_update` relay and the URL comes from the `url` attribute (R §1.4) | none | `lib/ash_table/live/table_component.ex` reduced to a wrapper |
| `AshDataTable.NotFoundError` | 404 for a mounted table whose read is refused | public exception | `lib/ash_table/not_found_error.ex` |
| `Mix.Tasks.AshDataTable.Install` | Igniter installer; from stage 1b also the hooks' `app.js` line where a host needs it | `mix ash_data_table.install` | `lib/mix/tasks/ash_table.install.ex`. Tooling: depends on no part at run time |

### 4.7 Test support (T)

| Module | Responsibility | Public API | Today's code |
| --- | --- | --- | --- |
| `AshDataTable.Test` | Help for a host's tests: `flush/1`; read a nested table out of its portal and send its events by name | public | `lib/ash_table/test.ex` (`flush/1`); the rest new, stage 5 |
| `AshDataTable.KitCase` | Renders a fixed table through a kit in every state; asserts the markers, and that no rendered state of any part holds a sensitive value of the test resource (F1) | public | New, stage 7 (R §4.4) |
| `AshDataTable.Test.Resource` (and its domain) | An ETS resource shipped in `lib/` for `KitCase`; `test/support/` is not shipped | internal to T | New, stage 7 |

### 4.8 Where today's table component goes

`lib/ash_table/live/table_component.ex` has 11,991 lines at `6e60fad`. The
ranges below come from the command in `docs/agents/architecture.md` ("The
table component") and the heads of the functions around them. The ranges in
`docs/agents/architecture.md` itself are older and do not match.

| Lines | Today | Target |
| --- | --- | --- |
| 1–512 | Comment: markup contract, one section per feature | Contract → `Attrs` docs and the kit guide; features → moduledocs of `Live.Core.*` and `Parts.*` |
| 513–552 | `use`, aliases, `@header_rows` (`:541`), `@tables` (process dictionary registry, `:550`) | `Parts.Grid`; `Live.Registry` (stage 5) |
| 553–677 | `mount/1`, every assign | `Live.Entry` (fields with their comments) |
| 678–1091 | `update/2`: listener batches, `selecting`, `relate`, `build`, `nested_model`, `creates`, `in_words`, `current_state` | `Live.Core` (init), `Live.Core.Nesting`, `Live.Core.Updates`; `in_words` → `Model` or the words |
| 1092–1203 | `settle`, `read` | `Live.Core.Reading` |
| 1204–1281 | Footer summaries; `reader` (`:1273`) | `Live.Core.Reading` (async beside the read); reader → `Caller` |
| 1282–1604 | Live updates: `listen`, `tidy`, `tables`, `close`, `rendered`, `follow`, `working`, `read_opts`, `refresh`, `leave`, `notice` | `Live.Core.Updates`; `tidy`, `close`, `rendered` → `Live.Registry` |
| 1605–1691 | `handle_async/3`: `:read`, `:summary`, `:bulk` | `Live.Core` dispatch to `Reading`, `Bulk` |
| 1692–2113 | Showing a read: `unfilled`, `show`, `item`, `put_row`, `put_detail`, `put_failure`, `remove_row`, `unselect`, `announce`, `row_key` | Data part → `Present`; stream part → `Live.Core.Reading` |
| 2114–2873 | `handle_event/3` clauses | Parsing → `Intent`; checks and writes → `Operation`; socket part → the `Live.Core.*` module of each topic |
| 2874–2904 | `defoverridable` and the wrappers ending in `tidy/1` | `Live.Core` (one dispatch, then `tidy`) |
| 2905–3014 | Cells: `revealed`, `save`, `refer` | `Operation` + `Live.Core.Cells` |
| 3015–3294 | Picker and chosen inputs | `Live.Core.Picker`; `Pick` |
| 3295–3605 | Panel, `act` | `Live.Core.Panel`; `Act` |
| 3606–3714 | Bulk; `in_locale/1` (`:3698`) | `Live.Core.Bulk`; `Operation.bulk` |
| 3715–3906 | `submit` | `Operation.submit` + `Live.Core.Panel` |
| 3907–4149 | Files | `Live.Core.Files` |
| 4150–4384 | After a create or run; table actions; lookups `action/2`, `column/2` (`:4375-4383`) | `Live.Core.Panel`; lookups → `Intent`/`Operation` |
| 4385–4510 | Arguments, `go`, URL | `Live.Core.Url`; `State` |
| 4511–5204 | `render/1` | `Parts.Grid`, `Parts.Heading`, `Parts.Arguments`, `Parts.Selection`, `Parts.Messages`, `Parts.Summary`; `attached/1` composes them |
| 5205–8956 | Four colocated hooks | JS modules of 4.5 (stage 1b) |
| 8957–11606 | Private function components (`panel_value/3` at `:9485`) | `Parts.*` (4.5); `panel_value/3` → `Present` (stage 3a) |
| 11607–11991 | View helpers (`colindex`, `cell_attributes`, `cell_content`, `typed_value`, `editable?`, `cell`, `page_numbers`, …) | `Attrs` (attributes), `Present` (values, `typed_value`, `editable?`), `Parts.Grid` (the rest) |

---

## 5. Dependency rules

### 5.1 Allowed edges

| From \ To | 1 | 3c | 2a | 2b | 3 | 3w | 4 | Ash, Spark | AshPhoenix | LV | PubSub |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **1** (not verifiers) | yes | yes | no | no | no | no | no | yes | no | no | `Resource.Notifier` only (Q9) |
| **1 verifiers, transformers** | topic modules, `Info`, `Table`, entities | yes | no | no | no | no | no | yes | no | no | no |
| **2a** | yes | no | yes | no | no | no | no | yes | yes | no | no |
| **2b** | yes | no | yes | yes | no | yes | no | yes | yes | yes | yes |
| **3** (incl. 3c) | `Info` only | yes | yes | no | yes | yes | no | yes | no | yes | no |
| **3w** | `Info` only | no | yes | no | no | yes | no | yes | no | no | no |
| **4** | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes | yes |
| **T** | all | all | all | all | all | all | all | yes | yes | yes | yes |

3c depends on nothing of the library. Gettext is used by 3w only.

### 5.2 Forbidden edges, in words

- The declaration never calls the internals, the components or the wiring.
  The one exception is 3c: `Resource.Presenting` checks that a column's
  `component` implements the behaviour and calls its `verify/1` at compile
  time (today `lib/ash_table/resource/presenting.ex:63, 89-90`). That needs
  the behaviour and the struct it is given, nothing else.
- The data layer never touches LiveView and makes no words. That is what
  keeps section 7 possible.
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
   `Relating.table?/1` does: `lib/ash_table/resource/relating.ex:143-145`). To
   ask whether a resource has the extension, use
   `Spark.Dsl.Extension.get_persisted/3` or `Ash.Resource.Info.extensions/1`.
3. `Resource.Info` depends on `AshDataTable.Resource` at compile time
   (Spark's `InfoGenerator`); that edge is required and allowed. No other
   module of part 1 is reached from a verifier and also reaches `Resource`.
4. A transformer names a module only as an atom in the DSL state
   (`Announce` puts the notifier into `:simple_notifiers`). The notifier is
   `Resource.Notifier`, in part 1 (Q9); write it as a literal atom so that
   xref sees no call.

### 5.4 Today's violations (from `mix xref graph`, `6e60fad`)

`mix xref graph --format stats`: 81 files, 28 compile edges, 45 export edges,
193 runtime edges, 2 cycles.

Against the target classification (1 declaration, 2a, 2b, 3, 3w, 4):

| # | Edge (file → file) | Kind | Rule broken | Fix in the target |
| --- | --- | --- | --- | --- |
| V1 | `resource/embedding.ex` → `model.ex`, `model/field.ex` (export), `model/cell_type.ex` | runtime, export | 1 → 2a | Embedding returns its own answer; `CellType` moves to 1; `Model` builds `Field` |
| V2 | `resource/acting.ex`, `resource/editing.ex`, `resource/presenting.ex` → `model/cell_type.ex` | runtime | 1 → 2a | `CellType` moves to 1 |
| V3 | `resource/reading.ex`, `acting.ex`, `editing.ex`, `referencing.ex`, `summarising.ex`, `presenting.ex` → `sensitive.ex` | runtime | 1 → 2a | `sensitive?/1`, `typed?/1`, `empty?/1` move to `Resource.Exposing` |
| V4 | `resource/verifiers/verify_columns.ex` → `model/operator.ex` | runtime, verifier | 1 → 2a; 5.3 rule 1 | `Operator` moves to 1 |
| V5 | `resource/verifiers/verify_components.ex` → `model.ex` (`humanize/1`), `sensitive.ex` | runtime, verifier | 1 → 2a; 5.3 rule 1 | `Words.humanize/1`, `Exposing.sensitive?/1` |
| V6 | `resource/transformers/announce.ex` → `notifier.ex` | runtime, transformer | 1 → 2a while the notifier is outside part 1 | The notifier moves to part 1 as `Resource.Notifier` (Q9), stage 1 |
| V7 | `resource/presenting.ex` → `component.ex`, `component/column.ex` (export) | runtime, export | 1 → 3 | Allowed as 1 → 3c |
| V8 | `resource/relating.ex` → `resource.ex` | runtime | 5.3 rule 2; closes the 30-file cycle | Ask Spark/Ash for the extension list |
| V9 | `model/argument.ex` → `format.ex` | runtime | 2a → 3w once `Format` is in the words; today it also pulls `format.ex` into the compile-connected cycle through V1 | The cycle goes with V1. The 2a → 3w edge: to settle in the design note of stage 3b (4.3) |
| V10 | Cycle of 30 files with 4 compile edges: `domain.ex`, `domain/info.ex`, `domain/verifiers/verify_pub_sub.ex`, `format.ex`, `model.ex`, `model/argument.ex`, `notifier.ex`, `resource.ex`, `resource/info.ex`, 11 topic modules, `transformers/announce.ex`, 10 verifiers | cycle with compile edges | No compile-connected cycle; 2a files inside a declaration cycle | V1–V8. What remains, and is allowed: one cycle per extension inside part 1, if only Spark's compile edges are in it (the extension compiles against its entities, verifiers and transformers; verifiers read `Info`; `Info` compiles against the extension). After stage 1: 21 files for the resource extension, 4 for the domain extension; nothing outside part 1 is compile-connected (stage 1 drift check F7) |
| V11 | `lib/ash_table.ex` ⇄ `live/table_component.ex` | cycle (runtime) | Cycle between 4 and the core | The core calls `AshTable.label/1` (`table_component.ex:9440`); `label/1` moves to 2a (`Model` or `Text`), `AshDataTable.label/1` delegates |
| V12 | `related.ex` → `routes.ex` | runtime | 2a → 4 if `Routes` were wiring | `Routes` is 2a (Q13); its coupling to the router's metadata is named in §6 |
| V13 | `live/table_component.ex` → 29 files of all parts | — | One file holds 2b, 3 and 4 | The split of 4.8 |
| V14 | `lib/ash_table/live/table_component.ex` holds the registry in the process dictionary (`:550`) | — | Hidden shared state between tables | `Live.Registry` inside `Table`, in stage 5: it needs one socket for all tables (F5) |

Not violations (allowed by the target): `model.ex` → 13 topic modules of part 1;
`lib/ash_table.ex`, `live/page.ex` → `resource/info.ex`, `resource/relating.ex`,
`domain/info.ex`; `router.ex` → `resource/verifiers/verify_tables.ex`
(`VerifyTables.name?/1`) and `routes.ex`; `domain/verifiers/verify_pub_sub.ex`
→ `resource/listening.ex`; `test.ex` → `listener.ex`; the shipped components →
`component.ex` (compile, through `use`). `zone.ex` (new since the first
draft) depends on `resource/reading.ex` only and is used by `act.ex`,
`edit.ex`, `query.ex`, `model.ex`, `format.ex`, `live/page.ex`, `lib/ash_table.ex`
and the component: 2a used by 2a, 3w and 4. It is in no cycle.

### 5.5 How to check automatically

One ExUnit test in the root, no new dependency (Q17).

- `Mix.Task.rerun("xref", ["graph", "--format", "json", "--output", path])`
  writes `%{file => %{file => "compile" | "export" | "runtime"}}`. (Checked:
  `mix xref graph --format json --output -` works with Elixir 1.19.4 here.)
  Decode with Elixir's `JSON`.
- Map each file to its part by directory. That needs a directory per part:
  `lib/ash_data_table/resource/**`, `domain/**` (1); `lib/ash_data_table/` top
  level and `model/**` (2a); `live/**` (2b); `parts/**`, `kit/**`,
  `component*`, `components/**` (3); the files of the words, listed by name
  in the test (3w); `lib/ash_data_table.ex`, `router.ex`, `live/page.ex`,
  `live/embedded.ex` (4); `test/**`-like modules under
  `lib/ash_data_table/test*` (T). A file that matches no rule fails the test,
  so a new file must be placed on purpose.
- Assert the table of 5.1 for every edge.
- Run the same task with `--label compile-connected` and assert that every
  file it lists is in part 1.
- Run `--format cycles` and assert that no cycle has files of two parts and
  that no cycle has a compile edge, except one cycle per extension inside part 1 made only of Spark's compile edges (5.4 V10).
- For the "no LiveView and no words in 2a" rules xref is not enough (it sees
  only our files). Add: no file of 2a mentions `Phoenix.LiveView`,
  `Phoenix.Component`, `Phoenix.PubSub`, `Gettext.` or a module of 3w (a grep
  in the same test over the source). `Phoenix.Router` is on the allow-list
  on purpose, for `Routes` (F15).
- Rule of S1: only `Query`, `Record`, `Pick`, `Bulk` call Ash reads (Q11).
- The test runs in report mode (prints, does not fail) from stage 1 and fails
  from the end of stage 3c.

xref sees calls, not data. A 2a struct that holds a 3c value (a column's
`component`) is not reported. Such fields are listed in §6 (F3).

The `boundary` library (a compiler that checks declared boundaries on every
compile) was the alternative. It gives better messages but adds a dependency
and an annotation in each top-level module. Not needed for four parts.

---

## 6. Where coupling stays strong on purpose

| Where | Why it is right |
| --- | --- |
| The hook and the attribute bundles (`Attrs`, `markers.js`) | They are two halves of one contract. A marker added to a bundle and not read, or read and not added, is a bug. One list of marker names on each side, kept next to each other; `KitCase` and the hook's development check test them together (R §4.4) |
| The hook and the event names, payloads and replies of the core (S6) | The keyboard grid answers a reply (`%{ok: false, error: …}`) in the same handler. Versioned with the contract |
| The live core and the model | The core checks every event against the person's model (names looked up as text). Indirection here would only hide the check |
| `State` and the URL format | The URL is the state's serialised form; `put_state/3` speaks the same vocabulary (R §5.4). One module owns both directions |
| `Operation` and the safety order | Confirm → checks → veto → re-read → action is one sequence. It lives in one function per write so that no adapter can reorder it (D-before). The checks and the veto run in the LiveView process, before any async start (F9) |
| `Present` and `Sensitive.scrub/2` | `Present` is the only way from the core's data to a part, panel and picker included, and it scrubs first. Not a seam: making it swappable would make the rule optional (F1) |
| `Model.Column` presentation hints (`component`, `max_lines`, `sticky_label?`, `editor`) | Carried for the drawing; the core never reads them. xref does not see this coupling (5.5, F3) |
| `Model` and the topic modules of part 1 | The verifiers and the model use the same rules (`docs/agents/architecture.md`, "The rules of a declaration live in one module per topic"). Sharing them is the point: a declaration that compiles is one the model can build |
| `Query`, `Record` and the table's read action | The re-read before a write must run the same action, with the same arguments and page values, as the page read (R §11.5: "the re-read … runs the same action with the same arguments as the page read") |
| `Routes` and the router's metadata format | `Routes` matches the route metadata that `AshDataTable.Router` writes (today `routes.ex:46`, `Phoenix.Router.routes/1`) (F15) |
| `Live.Registry`, streams, async keys, upload names | One entry owns all four: its id names the async keys and the upload names, its stream name comes from the pool. Closing by path must remove them together, or a portal outlives its row (R §10.3 "the mistake"). Entries are reconciled after every event against the open rows in the page; anything else is closed in the same render, as `close/1` does today (`table_component.ex:1392-1437`) (F11) |
| `Live.Core.Files` and `Act`/`Edit` | LiveView consumes an upload around the action (`consume_uploaded_entry`); the action must run inside it (R §3.1). This keeps uploads in 2b; `Operation` gets a `with_files` function (F9) |
| `Resource.Notifier` and `Listener` | The message shape and its tag `:ash_data_table_changed` are private between them; a host never matches on them (Q2) |

## 6a. Cross-cutting

One line each (F18). Details go into the design note before stage 3.

| Topic | Rule |
| --- | --- |
| Telemetry | None today (no `:telemetry` in `lib/`). Whether v1 adds spans around `Operation` and reads: to settle in the design note of stage 3 |
| A raise in `Operation` | Logged; the person sees the generic failure text; the entry is left as before |
| Reconnect | Nested tables close; open rows come from the URL only for the top table: as today |
| Tenant or actor change | All entries closed, listeners stopped, read again (R §5.2) |
| Language | 2a returns terms; words are made in the LiveView process or in the parts, never in a Task (F2). The bulk run's locale is fixed already (`d1489d6`, RQ5) |

---

## 7. Other UI technologies (O-ui)

No adapter in v1; `live_vue` first afterwards (Q20). This section says what
the refactor keeps possible.

### 7.1 What each would mean

| Technology | What it is | How it would sit on the table |
| --- | --- | --- |
| React or Vue inside LiveView (`live_react`, `live_vue`) | A LiveView renders `<.vue …>` / `<.react …>`; the client component gets props and sends events back | The LiveView path stays: same `Table`, same core, same streams. A kit whose parts are client components instead of HEEx. `live_vue` documents "Phoenix Streams Support with efficient patches", passes `items={@streams.items}`, sends prop changes as JSON Patch, and sends events back with `phx-click` or `useLiveVue().pushEvent()`; it has `useLiveUpload` for uploads. `live_react` lists "Phoenix Streams as props" and "Incremental Prop Updates". [docs, live_vue README and hexdocs `basic_usage`, `architecture`; live_react README; versions not pinned, not tried] |
| Hologram (hologram.page) | Elixir compiled to JavaScript. Page and component **state lives in the browser**. Actions run in the browser; commands run on the server over HTTP (`command(name, params, server) -> %Server{}`, results go back with `put_action/3`). Server push by channels (`put_subscription`, `Hologram.Realtime.broadcast_action/3`) over SSE. No LiveView. [docs: `/docs/architecture`, `/docs/commands`, `/docs/realtime`] | No socket, no stream, no `attach_hook`. A Hologram adapter would be Hologram components drawing rows held in client state, and Hologram commands that call the data layer (2a) directly. The server holds nothing between commands |

### 7.2 What this asks of our layering

The seam to a UI technology must be **data**, not HEEx:

- **Out:** the column model as the person sees it, the table state as URL
  params, the rows, panel fields and picker rows as `Present` gives them
  (key, values, input values, flags; scrubbed, hidden fields absent), the
  offered actions and their inputs, messages and errors as terms. All plain
  maps, all serialisable. The words come from the drawing side's helpers
  (`Format`, the translation step), which an adapter can reuse (RQ6).
- **In:** intents (`Intent`): sort, filter, page, page size, arguments,
  expand, save cell with typed text, clear, reveal, pick, run action, submit
  panel, select, bulk with a selection, read again. Each is a claim.
- **Between:** everything that touches Ash stays in 2a: `Model.for_actor`,
  `State.from_params`/`fit`, `Query`, `Operation` (checks, veto's answer,
  re-read, action, page values), `Event`.

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
| 3w words (`Format`, translation step) | used | used, server side | used, from commands |
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
6. **Live updates.** `Resource.Notifier` broadcasts on `Phoenix.PubSub`.
   Hologram would need a bridge to `Hologram.Realtime.broadcast_action/3` per
   subscribed page, and the re-read as the person per client.
7. **Keyboard and ARIA.** Today about 3,750 lines of hook code own them
   (`table_component.ex:5205-8956`), with about 60 direct DOM writes. The hook
   can be reused only on DOM it owns. A client framework that renders the grid
   itself must leave those attributes to the hook, or rebuild keyboard, ARIA,
   widths and selection (F12). Rebuilding loses the accessibility promise that
   the browser suite checks today.
8. **Nested tables.** The portal and the registry are LiveView answers. A
   client framework nests by itself; the data layer only needs the parent
   key and path, which it has.
9. **Events and veto.** The page-value and veto functions are evaluated in
   2b and their results handed to `Operation`; Hologram's adapter would
   evaluate them per command (F8). The event details are built in 2a
   (`Event`), so every adapter gets them. Delivery of events
   (`send(self(), …)`) is 2b; Hologram would deliver with `put_action`.

### 7.4 What to do in the refactor, and what not

Do (cheap, and good for the LiveView path on its own):

- Keep 2a free of LiveView and of words, checked by the test of 5.5.
- `Intent` (stage 3a): the parsing of browser params in one module. It is
  the list of everything a person can ask for.
- `Operation` (stages 3b, 6): one function per write with the safety order
  inside. The veto and page values need this place anyway.
- `Present` (stage 3a): rows, cells, panel fields and picker rows as data,
  scrubbed. The kit needs it anyway ("a part never receives a record", R §4.4).
- Selection on the server (stage 6, RQ1): no adapter needs selection logic
  of its own.
- Hook code as real JS files with one internal transport object (Q15,
  stage 1b).

Known remaining work for an adapter (F12): the hook only on DOM it owns
(7.3 point 7); the cell of a column whose resource names a HEEx `component`
(F3); submit intents not shaped by `AshPhoenix.Form`; `Present` and `Intent`
made public (Q14).

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

### 7.5 Later ideas, after the first release (owner, 2026-10-15)

Not built and not planned for v1; noted so they are not lost. Each is a "second user" of the data contract of 2a, which stays internal until one of them is real (Q14).

| Idea | How | Cost |
| --- | --- | --- |
| A table in the terminal (CLI) | An Elixir terminal app calls 2a directly: the model for the person, `Query` for rows, `Present` for drawing data, `Operation` for writes, `Text.say/1` for words | Small: 2a is LiveView-free; live updates and uploads need small adapters |
| An in-game UI (e.g. Unity) | A Phoenix Channel adapter: the core runs on the server per player; the client sends commands and draws the state it receives | Large: a server-side transport (the counterpart of S20) and a wire format |
| **The table's capabilities as an API, through Ash's own interfaces** | The extension adds generic actions to a resource (e.g. "read the table": state in, columns + rows + offered actions + summaries out; "run a table command"). The developer exposes them as with any action, in the resource's existing `json_api` / `graphql` block (e.g. `graphql do queries do action :task_table, :read_table end end`); ash_json_api, ash_graphql and ash_typescript serve them — no API layer of our own. Live updates as a GraphQL subscription | Medium: the return types as Ash types with named fields (ash_graphql needs them for a typed schema); stateless requests carry the state, every value a claim |
| Rows that scroll under fixed headers, as in Airtable (owner, 2026-10-16) | Each table, nested ones too, scrolls its rows vertically in an area of its own, below its column headers: the top table's rows fill the window, a nested table gets a maximum height. A kit option, per table (drawing only, the core is not touched); it may come with stage 7's kit. Points to watch: scroll inside scroll (the wheel scrolls the table under the pointer first, as Shift and the wheel do sideways today), keyboard moves scroll the cell into view in its own area, printing and the browser's find | Small to medium: CSS and the grid hook's scrolling into view |

## 8. Questions, all answered

The options, pros and cons are in [target-questions.md](target-questions.md).
Q1, Q8, Q11, Q14, Q15 and Q20 were answered by the owner on 2026-10-14; the
others were taken as recommended (owner, 2026-10-14). RQ1–RQ6 are the
review's questions, decided by the owner the same day.

| Q | Question | Answer |
| --- | --- | --- |
| Q1 | What `<AshDataTable.table>` becomes | A ready-made default wiring: one live component that holds the same core and renders the same plain component. `attach` + the plain component have no live component at all. Nested tables get their state from the top in every mode; never a live component per nested table |
| Q2 | One message tag or two | Two. The notifier gets its own private tag `:ash_data_table_changed`, in stage 0 |
| Q3 | Prefixes after the rename | `ash_data_table` everywhere (`:ash_data_table` tag, `ash_data_table:` names, `--ash-data-table-*`), in stage 0, in one go |
| Q4 | Event names on the wire | `ash_data_table:TABLE_ID:event`, the id being the registry key; from stage 3c |
| Q5 | Signature of the page-value functions | `(assigns, table_ref) -> map`, `table_ref` = `%{table: id, path: path, resource: resource}`; arity 1 accepted. Called by 2b with the current assigns (F8) |
| Q6 | Page values on a router line | `{Module, :function}` or a literal map; built last in stage 6 |
| Q7 | Where a `page_argument`'s value comes from | The page option `page_arguments`, same shape and `table_ref` as `private_arguments` |
| Q8 | How a row offers "open" | By the page: `open: label` at attach, on the tag, on the router line; the event is `:row_opened` with the key |
| Q9 | Which part the notifier is in | Part 1, as `AshDataTable.Resource.Notifier` |
| Q10 | How live updates reach an attached table | The listener in every mode; only the relay differs (`send_update` for the tag; `send(view, …)` + `handle_info` hook for `attach` and the page) |
| Q11 | A source seam for rows | No `Source` behaviour now; the checked rule that only `Query`, `Record`, `Pick`, `Bulk` read from Ash |
| Q12 | Where a kit is named | In config, per table, and on the router line |
| Q13 | `Routes` in 2a or 4 | 2a |
| Q14 | `Present` and `Intent` public? | Internal (`@moduledoc false`) until a second adapter exists |
| Q15 | How the hook code is shipped | Real JS files in the package; for LiveView, colocated hooks stay as thin imports of them; others import them through `app.js`/npm. First step of stage 1b: check that a colocated hook importing from the package works in a release build |
| Q16 | Names of the held value and the reader struct | `AshDataTable.Table` and `AshDataTable.Caller` |
| Q17 | How dependency rules are checked | The ExUnit test of 5.5, no new dependency |
| Q18 | What `put_state/3` may set | The whole URL vocabulary |
| Q19 | Order inside stage 6 | Page values and veto, then events, then commands, then "open" |
| Q20 | An adapter in v1 | None; `live_vue` first afterwards |
| RQ1 | Where selection lives | On the server: the entry holds the selected keys as claims; the browser mirrors them. Built in stage 6; the entry gets the field in stage 2 |
| RQ2 | Order of stages 4 and 5 | Swapped: stage 5 (flat registry and portals, inside today's component) runs first, then stage 4 (`attach` on the final shape) |
| RQ3 | Keep "no live component per nested table" | Kept, with the owner's fallback and its trigger in stage 5 |
| RQ4 | Commands in tag mode | No. Commands only with `attach` and on the router page; the tag sends events only |
| RQ5 | When to fix the bulk locale bug | Done (`d1489d6`: the bulk task is handed the page's Gettext locales). The message terms of stage 3b still apply |
| RQ6 | Values or texts for a cell | Values. Formatting and translation sit next to the drawing; `Format` is a helper of the drawing side that a later adapter can reuse |

---

## 9. Current → target checklist

Each item names the modules it creates or changes. Stage 5 runs before
stage 4 (RQ2); the numbers are kept because other documents use them. Before
stage 3, a short design note settles what this document leaves to it (the
owner asked for one before stages 3–7).

**Checked against this document (owner, 2026-10-14).** So that the stages do
not stray from the target:

- **After every stage, a drift check.** An independent reviewer that did not
  build the stage compares what was built with this document: the modules,
  their responsibilities and parts; the dependency rules, including what the
  dependency test cannot see (data coupling, presentation hints carried as
  data); the safety rules (no sensitive value on any path to the drawing but
  "Show", the re-read before a write, values from the browser as claims);
  that only the agreed tests changed; nothing built that this document does
  not ask for, nothing left out that it does. It reports, it does not fix. A
  stage is done only after this check. Where the code is right and this
  document is wrong, the document is amended, with the owner's yes for a
  change of design.
- **After stage 7, a final conformance review**, adversarial: it assumes the
  result has strayed from this document and tries to prove where, across all
  stages together. A judge weighs its findings; the owner gets what holds.

### Preparation (before stage 0)

- [ ] Test seams of `test-coupling.md` (in part done, see its "Done" section).
- [x] Markup snapshots and the performance baseline (`baseline.md`, `142c393`).
- [x] Bulk locale fix (`d1489d6`, RQ5).
- [x] The target refreshed against the code and amended after the review (this version).
- [x] Tag the commit before stage 0.

### Stage 0: rename (D-rename)

- [x] Package and app `ash_data_table`; `mix.exs`; `AshTable.*` → `AshDataTable.*` in `lib/`, `test/`, `demo/`.
- [x] Router macro `ash_data_table/3` (`AshDataTable.Router`); tag `<AshDataTable.table>`.
- [x] Gettext domain and `priv/gettext/ash_data_table.pot`; `demo/priv/gettext/de/LC_MESSAGES/`.
- [x] Config key `:ash_data_table` (`layout`, `gettext_backend`, `translate_error`).
- [x] Installer `Mix.Tasks.AshDataTable.Install`; colocated import path.
- [x] Prefixes per Q3: message tag, topic, `push_event` names, DOM events, `data-*`, CSS properties.
- [x] The notifier's own private tag `:ash_data_table_changed` (Q2), so no message name changes after stage 0 (M1).
- [x] Docs, guides, `CONTEXT.md` title, `docs/agents/architecture.md`, repository name.

### Stage 1: split

- [ ] Cut by the line ranges of 4.8, refreshed against the code at the start of the stage.
- [ ] Directories per part (5.5); the dependency test in report mode (`test/architecture_test.exs`).
- [ ] Move `Model.CellType` → `Resource.CellType`; `Model.Operator` → `Resource.Operator`; `Model.humanize/1` → `Resource.Words`; `Sensitive.sensitive?/typed?/empty?` → `Resource.Exposing` (V2–V5).
- [ ] `Resource.Embedding` stops building `Model.Field` (V1).
- [ ] `Resource.Relating.table?/1` stops calling `AshDataTable.Resource` (V8).
- [ ] `Notifier` → `Resource.Notifier`, part 1 (Q9, V6).
- [ ] `label/1` out of the tag module into 2a (V11).
- [ ] Function components → `AshDataTable.Parts.*` (4.5), still reading today's assigns.
- [ ] `render/1` → `Parts.Grid`, `Parts.Heading`, `Parts.Arguments`, `Parts.Selection`, `Parts.Messages`, `Parts.Summary`.
- [ ] `Model.hideable/1` moves to part 3 with the markup that uses it (F3).
- [ ] Hooks stay in the component module, so the rendered `phx-hook` names stay (M2).
- [ ] `shown_as/1` from `AshTable.Components` into `AshDataTable.Component` (owner, 2026-10-14; first moved into `Resource.Presenting`, which broke §5.1).
- [ ] Update `docs/agents/architecture.md`.

### Stage 1b: hooks to JS files (Q15)

- [ ] First: check that a colocated hook that imports from the package works in a release build.
- [ ] The hooks as real JS files in the package (4.5 table), with the internal transport object (S20); the colocated hooks become thin imports.
- [ ] The `app.js`/npm path for other UI technologies and custom builds; the installer.
- [ ] Snapshots normalise hook names.

### Stage 2: one state value

- [ ] `AshDataTable.Live.Entry`: today's assigns of `mount/1` with their comments, plus the selected keys field (empty until stage 6, RQ1).
- [ ] `AshDataTable.Table` per live component: options, `Caller`, the entry of this table. `@tables` stays until stage 5 (F5).
- [ ] `AshDataTable.Caller`: reader values from `reader/1` and `Query.reader_opts/1`, the time zone, and the functions; no assigns (F8). `Caller.reader_opts/1` produces today's `opts`; no 2a signature changes (F7).
- [ ] `State` is wrapped, not replaced.
- [ ] `Parts.*` read `@table` / the entry, not loose assigns. Measure the `/tasks` diff before and after (R §6 stage 3).

Notes from the drift check of stage 2 (2026-10-15):
- Functions join `Caller` in stage 6 (none exist before). Parts get single fields of the entry, never `@table` (it holds the caller and actor).
- `Caller.reader_opts/1` builds the `opts`; `Query.reader_opts/1` stays as the data layer's filter of them.
- Stage 5: `authorize?` is resolved per table from its resource's domain, so once one `Table` holds nested entries from other domains, the resolved value lives in the entry and `Caller` keeps only what it was told. The same for today's per-table options (`label`, `labelledby`, `lineage`, `select`, `live_given`, `authorize_given`); `lineage` is the entry's path.
- Stage 4: `options.page_assigns` (a copy of the host's assigns) stays an option of the tag's live component only; with `attach`, the live layer gives the current assigns (a copy would contain the `Table` itself).

### Stage 3a: drawing data and intents

- [ ] `AshDataTable.Present`: rows, cells, the panel's fields, picker rows and labels, failed edits; values, not texts (RQ6); no sensitive value on any path (F1). `panel_value/3` moves into it. `Sensitive.scrub/2` inside.
- [ ] `AshDataTable.Intent`: parse every event of `docs/agents/architecture.md` "Events".
- [ ] No behaviour change; the markup snapshots stay identical.

### Stage 3b: the write pipeline

- [ ] `AshDataTable.Operation`: one function per write, with its input value (F9); the checks of today's handlers; re-read; outcome. `reveal` is the only way to a sensitive value.
- [ ] Outcomes of `Operation`, `Bulk` and `Query` as message terms; words made in the LiveView process by the translation step (F2). `Text`, `Format`, the wording of `Errors` and `Gettext` become 3w; `Format` a helper of the drawing side (RQ6).
- [ ] `Act`, `Edit`, `Pick`, `Bulk`, `Record` keep their arguments.

### Stage 3c: the live core

- [ ] `AshDataTable.Live.Core` and `Live.Core.Reading`, `.Cells`, `.Panel`, `.Picker`, `.Bulk`, `.Files`, `.Nesting`, `.Updates`, `.Url` (4.8 table), as private file splits.
- [ ] Event names namespaced per Q4 through the test seam `send_event/4`; hooks push with the table id.
- [ ] The component (`table_component.ex`) delegates to the core; nothing else left in it.
- [ ] Dependency test fails on violations from here on.

### Stage 5: nesting through portals (D-nested, D-events "one mechanism"). Runs before stage 4

- [ ] Prove it on one nested table first (task → comments), browser and demo suites green; then the rest.
- [ ] Fallback (D-events): nested live components inside the library, as today. Use it if a LiveView release breaks portals inside streams, or if the browser tests of the combination cannot be made stable (RQ3).
- [ ] Nested tables and pickers as registry entries with their own streams, inside today's top-level component (`Live.Core.Nesting`, `Live.Registry`).
- [ ] `AshDataTable.Live.Registry`: stream names from a pool, async keys `{:ash_data_table, id, …}`; upload names stay in `Files`, by id.
- [ ] The wiring renders one portal per nested table at the top level, parents first; `Parts.Related` renders only the empty target cell; the picker's table is drawn in place, in the slot of `Parts.Picker`.
- [ ] One close by path: async cancel, uploads cancelled and disallowed, stream reset, entry removed, stream name back to the pool. The registry reconciles its entries against the open rows in the page after every event (F11).
- [ ] Remove `@tables` (V14).
- [ ] Remove the nested `live_component`.
- [ ] `AshDataTable.Test`: read a nested table from its portal; send its events by name. `DemoWeb.TablePage` uses it.
- [ ] Browser tests of the portal combination itself (R §10.7 point 2), and one per removal path: live delete, page change, filter, actor change, `detach` (`detach` once stage 4 has it).
- Performance (owner, 2026-10-16): opening a nested table or a picker sends 4–7 KB more than before stage 5 (portals do not share the static markup that live components of one module shared). Accepted; looked at again in stage 7. Times are within 20 % (measured back to back on an idle machine, `8032ef2`).

### Stage 4: attach, function component, wiring on top. Runs after stage 5

- [ ] `AshDataTable.attach/4`, `detach/2`: hooks for `handle_event`, `handle_async`, `handle_info`, and `handle_params` with `url: true`; first read in place.
- [ ] `AshDataTable.attached/1` with `streams={@streams}`; documented: not inside a stream item of the host's own (F11).
- [ ] `AshDataTable.Live.Page` uses `attach` (R §8 decision 8).
- [ ] `<AshDataTable.table>` as one live component holding the same core and rendering `attached/1` (Q1, `AshDataTable.Live.Embedded`).
- [ ] Listener relay per Q10.
- [ ] The mode-independent demo tests run three ways (mounted, embedded, attached) on a chosen subset: the ten snapshot states plus one test file per feature group (F14).
- [ ] Exactly one `live_component` in `lib/`: the tag's (`AshDataTable.table/1` renders `AshDataTable.Live.Embedded`). None for nested tables or pickers, none behind the router line (`Live.Page` uses `attach`), none with `attach`. This replaces stage 5's line "no `live_component` in `lib/`" (stage 4 design note, section 9).

### Stage 6: events, commands, page values, veto (D-events, D-before, D-nolinks)

In the order of Q19.

- [ ] `Caller` holds the functions for `context`, `private_arguments`, `page_arguments`, `before_action` (Q5, Q7); 2b calls them with the current assigns in the LiveView process, before any async start, and hands the results to `Operation` (F8, F9).
- [ ] `Query`, `Record`, `Act`, `Edit`, `Bulk`, `Pick`: context on every call, as a new key of `opts`; private arguments filtered per action; reads by `Ash.Query.set_argument/3` (R §11.5).
- [ ] `AshDataTable.Request`; `Operation` takes the veto's answer after the checks and before the re-read; bulk: the veto is asked once, before `start_async`.
- [ ] DSL `page_argument` in `Resource.Action`; rule in `Resource.Acting`; verifier; panel never asks it.
- [ ] Selection on the server (RQ1): the entry holds the selected keys; the hook mirrors them.
- [ ] `AshDataTable.Event` and `Live.Core.Notify`: the events of D-events; `notify` on tag, attach, router line. The details of `:read` settled; `:selection_changed` carries the keys, marked as claims (F19).
- [ ] The record in an event has `sensitive?` values masked (D-1014). Guide: the host reads the record itself if it needs a sensitive field.
- [ ] Commands `refresh/2`, `put_state/3` (whole URL vocabulary, Q18), `clear_selection/2`, `selected_records/3`, with `attach` and on the router page only (RQ4).
- [ ] "Open" offered by the page, event `:row_opened` (Q8).
- [ ] Page values on a router line (Q6), last.

### Stage 7: component contract and kit (D-parts, D-headless)

- [ ] `AshDataTable.Attrs`: a bundle for every element, rows and cells included.
- [ ] Hooks find everything by markers; no tag selectors (R §10.3: about 75 statements in 25 functions); hooks stop toggling daisyUI classes.
- [ ] `AshDataTable.Kit` (behaviour, `use`, contract version, `class/2`); `AshDataTable.Kit.Default`. Kit-evolution rule: a new part comes with a default in `use AshDataTable.Kit` (F13).
- [ ] Kit named per Q12; resolution for a cell: column's component, kit's `cell/1`, default (R §4.7).
- [ ] The presentation hints of `Model.Column` documented as such (F3).
- [ ] `AshDataTable.KitCase` and `AshDataTable.Test.Resource`; `KitCase` asserts that no rendered state of any part holds a sensitive value of the test resource (F1).
- [ ] Development-mode marker check in the hook.
- [ ] **Presentation of what opens is changeable (owner, 2026-10-15):** not only the look of the action panel, the picker and the confirm dialog, but whether they open as a modal (as today: native dialog, page blocked, focus trapped, Escape closes) or inline (in the page, no trapping; focus moves in and back out). Declared by the kit, overridable per table. The hooks follow the declared presentation; what the panel shows, the checks and "nothing changes under you while it is open" do not depend on it. `KitCase` checks keyboard and screen-reader behaviour for both. To be shaped in the design note of stage 7.
- [ ] **Every UI element is completely changeable, behaviour included (owner, 2026-10-15) — headless with inversion of control.** Three levels for everything that opens (action panel, picker, confirm dialog, popovers, lists) and for every UI element: (1) style (classes); (2) markup (the developer's own part, still opened by the table); (3) behaviour, "controlled" as opposed to "uncontrolled": the table only reports the request with its data (e.g. "Reassign asked for this row", the fields, values, errors as data), and the developer decides whether, where and how anything is shown — their own drawer, a place in their layout, a page of theirs — and hands the inputs back with a command (submit, cancel). The default stays uncontrolled (the table's own drawer). Whatever the developer builds, the inputs go back through `Operation`: claim checks, veto, re-read as the person, authorization stay the table's. Controlled mode needs `attach` (commands only there, RQ4). Built on the events and commands of stage 6; shaped in the design notes of stages 6 and 7.

### After stage 7: final conformance review
- [ ] Adversarial review of the whole result against this document, then a judge; findings that hold go to the owner.
- [ ] Then the one documentation pass: guides, README, CHANGELOG, module docs, the code tour (owner, 2026-10-14: documentation is updated once the refactor is finished and working).
