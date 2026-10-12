# A headless table for ash_table: research and design

Date: 2026-10-12. Versions read: ash_table `main` at 8e86c4b plus the uncommitted work
in the tree, Ash 3.34.4, AshPhoenix 2.3.25, Phoenix LiveView 1.2.12, Phoenix 1.8.15.
Nothing in the ash_table repo was changed. Nothing was reported upstream.

How to read the marks: **[code]** read in source, **[docs]** read in documentation,
**[experiment]** run by me (section 7), **[unverified]** not checked.

---

## Summary

**The idea is right, with one correction.** A table can be split into a core and
function components, and the live component can become a thin wrapper. But the core
cannot be a pure value like `AshPhoenix.Form`. A table owns streams, async reads,
uploads and pushed events. In LiveView all of these live on the socket. So the core is
"functions over a socket, with all table state under one assign", not "a struct plus a
reducer".

**The mechanism exists and works.** `attach_hook/4` lets a library install its
`handle_event`, `handle_async`, `handle_info` and `handle_params` into a host LiveView.
In LiveView 1.2 the first two also work on a live component's socket. So one core can
drive both. I proved this in a throwaway project: two tables in one LiveView without
any live component, streams, async reads, replies to hooks, an upload allowed later,
and the same core on a live component's socket. Change tracking stays per field when
the state is one struct passed to a function component.

**Recommended shape (three ways to use the same table):**

| Mode | The developer writes | State lives in |
| --- | --- | --- |
| Mounted | `ash_table "/tasks", MyApp.Task` (unchanged) | the library's page |
| Embedded | `<AshTable.table id=… resource=… />` (unchanged) | the library's live component |
| Attached (new) | `AshTable.attach(socket, :tasks, MyApp.Task, scope: …)` in `mount`, `<AshTable.attached table={@tasks} rows={@streams.tasks} />` in the template | the developer's own LiveView |

All three run the same core and the same function components.

**Events out and commands in are the same in all modes.** Events are messages to the
LiveView process: `{:ash_table, id, event}`, opt-in with `notify`. Commands are
functions: `AshTable.refresh/2`, `AshTable.put_state/3`, `AshTable.clear_selection/2`.

**No live component is needed for nested tables either.** **Corrected 2026-10-12, see section 10:** this
paragraph first said that nested tables and pickers must stay live components, because
a stream item is rendered once. That conclusion was wrong. Each nested table can be
rendered at the top level, with its own stream on the host's socket, and placed into
its parent's row by `<.portal>`. Proven in a browser. The price is a test helper:
`Phoenix.LiveViewTest` does not look into a portal.

**Replacing the look.** Today the browser hooks (2,800 lines) walk the markup directly:
about 45 `data-*` attributes, 20 id patterns, tag names. That is the real contract and
it is folklore. Make it explicit in the same way `@control` already works for editors:
the library hands each part an **attribute bundle** to spread; a **kit** module
(`use AshTable.Kit`) overrides parts; a **conformance test** (`AshTable.KitCase`)
checks a kit. The grid skeleton (table, rows, cells) is themed by classes, not
replaced, in the first step.

**Order of work.** First events and commands on today's component (small, useful at
once). Then the refactor in behaviour-preserving steps, guarded by the existing tests.
Then `attach`. Then the kit. Do not start with a pure reducer. (**Corrected 2026-10-12, see section 10:** "do not
make nested tables headless" is withdrawn.)

---

## Contents

1. How others split logic from rendering
2. How ash_table is tied together today
3. Design options
4. The component contract
5. Recommendation and public API
6. Staged plan
7. The experiment
8. Decisions for the owner
9. What not to do
10. Nested tables without live components (added later; corrects 3.4)
11. Before an action runs: values from the page, and a veto (added later)

---

## 1. How others split logic from rendering

Sources: `deps/` of ash_table for AshPhoenix and LiveView (`LV/` below is
`deps/phoenix_live_view/`, 1.2.12). Shallow clones of the others, made today, under
`…/scratchpad/headless-research/ext/` (`EXT/` below). JavaScript libraries from their
documentation on GitHub.

### 1.1 The Ash precedent: `AshPhoenix.Form` and `AshPhoenix.LiveView`

**`AshPhoenix.Form`** (**[code]** `deps/ash_phoenix/lib/ash_phoenix/form/form.ex`) is the
Ash example of headless.

- State: one struct (`form.ex:161`), kept by the host in an assign.
- Functions: `for_create/3`, `for_update/3`, `for_action/3` build it; `validate/3` and
  `submit/2` return a new one. No socket anywhere.
- Who is asking is given once, when the form is built, and kept: "you can set things
  like the tenant/actor. These will be retained, and provided again when
  `Form.submit/3` is called" (`form.ex:531`).
- The host wires everything: its own `handle_event("validate")` and
  `handle_event("save")`, its own markup (`Phoenix.Component.form`), what happens
  after success.
- Why it can be a pure value: a form has no streams, no async, no uploads of its own.

**`AshPhoenix.LiveView`** (**[code]** `deps/ash_phoenix/lib/ash_phoenix/live_view.ex`)
is the Ash example for things that do live on the socket. Every function takes the
socket and returns it: `keep_live/4` (`:145`), `handle_live/4` (`:550`),
`change_page/3` (`:221`), `assign_page_and_stream_result/3` (`:787`), which assigns the
page without its results and puts the results into a stream. The pure helpers beside
them (`page_link_params/2`, `page_number/1`, `last_page/1`) take the page.

What transfers: **reader fixed when the state is built; pure values where possible;
socket in, socket out where streams are involved.** A table is the second kind.

### 1.2 Elixir table libraries

| Library | Who holds the state | Logic and rendering | Events to the host | Commands from the host | Streams | Async |
| --- | --- | --- | --- | --- | --- | --- |
| **Flop + Flop Phoenix** 0.27 | Host LiveView (`Flop.Meta` in an assign, or the URL) | `Flop` is pure; `Flop.Phoenix` is function components only | None needed: the host's own `handle_params` or `handle_event` (`on_sort`, `on_paginate`, `target`) | The host runs the query itself | Pass-through: `items={@streams.pets}` | None |
| **Petal Components `DataTable`** 4.17 | Host LiveView (`%State{}`) | Pure `State` (`from_params`, `to_params`, `handle_op`) plus a function component | Link mode (URL) or one `on_change` event with an op grammar; selection on a separate `on_ui` event | The host runs the query | Pass-through | Host sets `loading` |
| **LiveTable** 0.4 | Host LiveView | A macro injects `handle_params` and `handle_event` clauses and a function component | In the host already | — | Optional, fixed name `:resources`, so one table per LiveView | None |
| **Cinder** 0.17 (Ash) | The library's live component | `Cinder.collection/1` is a function component that renders `Cinder.LiveComponent` | `send(self(), {host_named_event, payload})`: `on_state_change`, `on_selection_change`, `on_query_change`, bulk `on_success`/`on_error` | `send_update` behind helpers: `Cinder.refresh_table(socket, id)`, `update_item`, … | None; rows in assigns | `start_async` in the component |
| **AshAdmin** 1.3 | One LiveView with live components; the data table renders `Cinder.collection` | — | — | No host API | None | Cinder's |
| **Backpex** 0.22 | The library's LiveViews, generated by `use Backpex.LiveResource` | Host module is a callback module | Callbacks that get the socket (`on_item_created/2`, item actions' `handle/3`); for anything else `on_mount` plus `attach_hook` | — | None | None |
| **Exzeitable** | A nested LiveView of its own (`live_render`) | — | — | — | None | — |
| **Pyro / AshPyro** | `ash_pyro_components` is archived; the successor (PyroManiac) is a DSL with a separate renderer library that is not public | — | — | — | — | — |

Citations (**[code]** in the clones):

- Flop Phoenix: function components only (`EXT/flop_phoenix/lib/flop_phoenix.ex:140`);
  the two wiring modes (`:67-137`); streams (`lib/flop_phoenix/table.ex:53-54, 100`);
  filter forms through `to_form(meta)` and the host's own input component (`:1392-1503`);
  `pagination_for/1` hands a struct to the host's own markup (`:895`).
- Petal: `EXT/petal_components/lib/petal_components/data_table.ex:1-52`,
  `data_table/state.ex:124-274`.
- LiveTable: `EXT/live_table/lib/live_table/live_resource.ex:14-41`,
  `helpers/liveview_helpers.ex:8-203`. The injected clauses are not overridable.
- Cinder: `EXT/cinder/lib/cinder/collection.ex:482`, `live_component.ex:528-644, 1072`,
  `url_manager.ex:459`, `url_sync.ex:81-115, 326`, `refresh.ex:71`, `update.ex:73-228`.
  URL state needs a loop: component → message → the host's `push_patch` →
  `handle_params` → assign → the component's `update/2`.
- AshAdmin: `ash_reference/ash_admin/lib/ash_admin/components/resource/data_table.ex:101-189`.
- Backpex: `EXT/backpex/lib/backpex/live_resource.ex:173-351, 450-493`,
  `guides/live_resource/on_mount-hook.md`. Every field is a live component
  (`lib/backpex/field.ex:328`).
- Pyro: GitHub says `ash_pyro_components` is archived; `pyro_maniac_live_view` returns
  404. **[unverified]** beyond that.

**LiveSelect** is the widely used "live component talks to its host" pattern
(**[code]** `EXT/live_select`): the hook pushes `live_select_change` to the LiveView, or
to `phx-target` when one is given (`assets/js/live_select.js:39-56`); the host answers
with `send_update(LiveSelect.Component, id: …, options: …)` (`lib/live_select.ex:202`);
server-to-hook events carry the id and the hook filters on it, because `push_event` is
global (`lib/live_select/component.ex:553`).

Three families, then:

1. **Host holds the state, library is pure state plus function components**: Flop,
   Petal, LiveTable. Fits read-only tables: sort, filter, page. None of them edits,
   runs actions, uploads or nests.
2. **Library's live component holds the state**: Cinder. Events out as messages,
   commands in by `send_update`. This is ash_table today, minus the events and
   commands.
3. **Library owns the LiveView**: Backpex, AshAdmin, ash_table's router page.

Nobody uses `attach_hook` as the main wiring between a table and its host. Backpex
documents it for extending its pages.

### 1.3 JavaScript: only what transfers

| Source | Idea | For ash_table |
| --- | --- | --- |
| TanStack Table | Headless: "provide the logic, state, processing and API … but do not provide markup". State is internal by default; the host may control single slices (`state: {sorting}` plus `onSortingChange`). "Prefer exactly one … as the source of truth." Server side: `manualSorting`, `manualPagination` | Control per slice is what `url: true` and `put_state` give: the host may own sort, filters and page, and nothing else. The DOM is free in TanStack because it has no behaviour of its own: no keyboard grid, no editors. ash_table has both |
| AG Grid | Events out (`selectionChanged`), an imperative API in (`refreshServerSide`, `setFilterModel`, `deselectAll`). Server-side selection is a serialisable state | Same split as 5.3 and 5.4. Selection as a value the host can ask for |
| Radix | Controlled (`checked` + `onCheckedChange`) or uncontrolled (`defaultChecked`) | Same as TanStack |
| Downshift | `stateReducer(state, changes)`: the host may change a state transition before it happens | The LiveView analogue is a host hook that runs before the table's. Not needed in the first version |
| React Aria | Hooks give behaviour and ARIA props; the developer spreads them on own markup | The model of section 4: bundles. **[unverified]**: the documentation page was not reachable today; from memory |

Sources: TanStack `docs/introduction.md`, `docs/framework/react/guide/table-state.md`
(v8 and main), `docs/guide/sorting.md`, `docs/guide/pagination.md`; AG Grid
`documentation/ag-grid-docs/src/content/docs/` (`server-side-model-updating-refresh`,
`filter-api`, `row-selection-api-reference`, `server-side-model-selection`); Radix
checkbox documentation; Downshift `README.md#statereducer`. AG Grid's
`cellValueChanged` is **[unverified]**.

### 1.4 Phoenix LiveView's own guidance

All **[code]** or **[docs]** in `LV/` at 1.2.12.

**Function components first.** "Generally speaking, prefer function components over
live components as they are a simpler abstraction with a smaller surface area. The use
case for live components only arises when there is a need to encapsulate both event
handling and additional state. Avoid using LiveComponents merely for code organization
purposes." (`lib/phoenix_live_component.ex:37-44`). A table has both events and state,
so a live component is a legitimate choice. The owner's point stands for the host that
wants to hold the state itself.

**One source of truth.** "Avoid both the parent LiveView and the LiveComponent working
on two different copies of the state" (`:273-276`).

**What a live component cannot do.** No `handle_info` (`:392-405`). No `handle_params`:
"Patches are always handled by the parent LiveView" (`:537`). This is why the table
needs `url=` handed down today.

**Component to parent.** The guide's fix for a hard-coded `send(self(), …)` is a
function passed as an assign: `on_card_update={fn card -> send(self(), {:updated_card,
card}) end}`; "the parent has explicit control over the messages it will receive"
(`:413-468`).

**`attach_hook/4`** (`lib/phoenix_live_view.ex:1646-1703`):

- Stages: `:handle_params`, `:handle_event`, `:handle_info`, `:handle_async`,
  `:after_render`.
- Hooks run "immediately before" the callback. `{:halt, socket}`: the callback is not
  invoked, and the LiveView need not have a clause at all. `{:halt, reply, socket}`
  replies to the client, for `:handle_event`.
- A hook sees **every** event of its socket. Plugin authors "**must** define a
  catch-all clause". So names must be namespaced.
- **In a live component**: "only `:after_render`, `:handle_event` and `:handle_async`
  hooks are currently supported" (`:1661`; code `lib/phoenix_live_view/lifecycle.ex:103`).
  So the common belief "hooks do not work in live components" is out of date for the
  two stages a table needs most.
- Hooks are per socket. A hook on the LiveView does not see an event targeted at a
  component.
- `:handle_params` raises for a LiveView that is not mounted in the router
  (`lifecycle.ex:44`).
- The documentation presents hooks as the way to "extract related events out of the
  parent LiveView … without resorting unnecessarily to LiveComponents".

**Streams** are in `socket.assigns.streams`, so per socket; a component has its own
names. Items are freed after render, so the server cannot read rows back.
`stream_async/4` exists since 1.1.5 (`phoenix_live_view.ex:2434`); the table's read
needs more than it gives (first read in place, "busy" with the old rows left in view).

**Async** works in LiveViews and components; a later `start_async` under the same name
wins; results come back to whichever socket started them.

**`send_update/3`** takes a module and id, or `@myself`; from another process it needs
the LiveView's pid (`:1508-1581`).

**`push_event/3`** is global: "If you need to scope events, then this must be done by
namespacing them" (`:818`). There is no way to target one hook. The table already puts
`table: id` in every payload.

**JS hooks.** `pushEvent` goes to the LiveView. `pushEventTo(el, …)` goes to the
component the element is in, or to the LiveView when it is in none
(`assets/js/phoenix_live_view/view.ts`, `closestComponentID`). The table's hooks use
`pushEventTo(this.el, …)` everywhere, so they need no change to work in a host
LiveView.

**Colocated hooks** are extracted per OTP application, also for dependencies; the host
imports `phoenix-colocated/ash_table` (`lib/phoenix_live_view/colocated_js.ex:36-63`).
Names are prefixed with the module, so moving the markup to another module changes
nothing for the host.

**Uploads** work in components (the form needs `phx-target`). But **upload names are
unique per LiveView process, across components**: a second component that allows the
same name raises "existing upload for … already allowed in another component"
(`lib/phoenix_live_view/channel.ex:1728-1746`). The table allows `"file-ARGUMENT"`
without the table's id today. Two tables on one page whose actions take a file
argument of the same name should hit this. **[unverified]**: read, not reproduced.
Worth a test in ash_table now, whatever is decided here.

---

## 2. How ash_table is tied together today

All of this is **[code]**, from `lib/ash_table/live/table_component.ex` (9,578 lines,
419 kB) unless another file is named.

### 2.1 The file in three parts

| Lines | What | Size |
| --- | --- | --- |
| 1–3568 | Live component: `mount`, `update`, `handle_async`, 75 `handle_event` clauses, helpers | ~3,300 lines of logic |
| 3569–4127, 6912–9578 | `render/1` and about 30 private function components (`panel`, `picker`, `field`, `group`, `union`, `lines`, `pagination`, `filter`, `editor`, `selection`, …) | ~3,300 lines of markup |
| 4128–6911 | Four colocated hooks: `.Pagination`, `.Panel`, `.Picker`, `.Grid` | ~2,800 lines of JavaScript, `.Grid` alone ~2,400 |

So the markup is already function components. They are private, they read the
component's assigns, and they target `@myself`.

### 2.2 What is already pure

These modules take values and return values. None touches a socket. All are
`@moduledoc false` today.

| Module | Job |
| --- | --- |
| `AshTable.Model` | The table model: `build/2` (same for everybody), `for_actor/2` (per person), `defaults/2`, `supply/2` |
| `AshTable.State` | Sort, filters, page, arguments: `from_params/2`, `to_params/2`, `cycle_sort/3`, `filter/3`, `argue/3`, `to_page/2`, `fit/2` |
| `AshTable.Query` | `read/3`, `read_related/4`, `matching/3`, `records/3`, `arguments/2`, `load/3` |
| `AshTable.Record` | `fetch/3` by primary key, as the person |
| `AshTable.Edit` | `save/5`, `clear/4`, `refer/5`, `open/5`, `put/7` |
| `AshTable.Act` | Row actions, create, generic actions, the panel's form: `open*/…`, `validate/4`, `submit_*/…`, `run*/…` |
| `AshTable.Bulk` | `run/5` on a selection |
| `AshTable.Pick` | Reads the chosen related record again, as the person |
| `AshTable.Related` | The `of` parameter of a full view |
| `AshTable.Sensitive` | `scrub/2` before a record reaches a stream |
| `AshTable.Format`, `Text`, `Errors` | Text for people |

This is the headless part that exists. It is in the shape of Flop (`validate`, `run`,
`Meta`) and of `AshPhoenix.Form`: values in, values out.

### 2.3 What is tied to the socket

**Assigns.** `mount/1` and `update/2` set about 55 top-level assigns. Grouped:

| Group | Assigns |
| --- | --- |
| Given by the caller | `id`, `resource`, `scope`, `actor`, `tenant`, `authorize?`/`authorize_given`, `url`, `label`, `heading`, `mounted?`, `page_assigns`, `select`, `choose` |
| Given by the table around a nested one | `via`, `parent_key`, `parent_authorize?`, `parent_arguments`, `depth`, `depth_limit`, `labelledby`, `nested?` |
| Derived per person | `built` (cached model), `model`, `editing?`, `acting?`, `offered`, `expandable?`, `selecting`, `bulk`, `lead`, `creates` |
| Read state | `state`, `read` (what the last read was of), `page`, `row_count`, `busy?`, `loading?`, `error`, `gone?`, `fill`, `missing`, `refused`, `lines`, `rejected`, `related`, `related_title`, `full_view` |
| Row bookkeeping | `rows` (row key → primary key and row index), `failed`, `open` |
| Dialogs | `panel`, `picker`, `spent`, `running_files` |
| Bulk | `running`, `result` |
| Live region | `announce?`, `announcement`, `announcements` |

The server does not keep the records. It keeps the keys of the page (`rows`) and the
failed edits. Which rows are selected is kept by the browser hook alone.

**Stream.** One stream, `:rows`, with `dom_id: & &1.dom_id`. Each record is one item
(a `<tbody>`), and when rows can be expanded a second item, the detail. Used:
`stream/4` with `reset: true`, `stream_insert/3`, `stream_delete_by_dom_id/3`.

**Async.** Two keys: `:read` and `:bulk` (`start_async/3`, `handle_async/3`). The first
read of a top-level table is done in place, so the first render has rows. Nested tables
read async from the start.

**Uploads.** `allow_upload/3` is called when a panel with a file field first opens,
under the string name `"file-ARGUMENT"`. `consume_uploaded_entry/3` wraps the action.
`cancel_upload/3` drops what was left behind.

**Navigation.** `push_patch/2` when `url` is given (state in the URL). `redirect/2`
when a mounted page's read is refused later. `raise AshTable.NotFoundError` on the
first read.

**Child live components.** The component renders itself again in two places: a nested
table per open relationship line (id `ID-row-KEY-t-NAME`, inside a stream item), and
the table of a picker (id `ID-pick-NAME`, inside a `<dialog>`). No `send_update`, no
`send(self(), …)`, no PubSub anywhere.

**Server → browser events** (`push_event`, all carry `table: id`, so they are already
namespaced): `ash_table:focus`, `ash_table:ask`, `ash_table:bulk`,
`ash_table:unselect`.

**Browser → server events.** 20 from hooks via `pushEventTo(this.el, …)` or
`pushEventTo(dialog, …)`; the rest from `phx-click`, `phx-change`, `phx-submit` with
`phx-target={@myself}` (40 places). Many answer with `{:reply, map, socket}`.

| Group | Events |
| --- | --- |
| Read state | `sort`, `filter`, `clear_filter`, `clear_filters`, `page`, `arguments`, `argument_add`, `argument_remove` |
| Rows | `expand`, `toggle` |
| Cells | `save`, `clear`, `reveal`, `edit` (map and union cells), `discard`, `dismiss` |
| Reference cells | `pick`, `pick_input`, `picked`, `picker_cancel` |
| Actions | `act`, `create`, `table_act`, `table_run` |
| Selection | `bulk`, `bulk_run`, `bulk_seen` |
| Panel | `panel_validate`, `panel_submit`, `panel_add`, `panel_remove`, `panel_unpick`, `panel_clear`, `panel_cancel` |

**DOM events for the page's own JavaScript.** The grid hook dispatches
`ash_table:selection` and `ash_table:choose` on `ID-grid`, bubbling, with the selected
rows as detail. This is not in the guides. It is today's only "event out".

### 2.4 Where the authorization guarantees live

| Guarantee | Where |
| --- | --- |
| Who is asking is never taken from the browser | `reader/1` builds `[scope, actor, tenant, authorize?]` from assigns only |
| A row an event names must be on the person's page | Every row event looks the key up in `assigns.rows`; a miss runs nothing |
| A column or action an event names must be offered to this person | Looked up by name as text in the per-person `model` (`column/2`, `action/2`, `table_action/2`); no atoms from the browser |
| The record is read again, as the person, before a write | Inside `Edit.save`, `Edit.clear`, `Edit.refer`, `Edit.open`, `Act.run`, `Act.open`, `Record.fetch`, `Bulk.run`, `Pick.chosen` |
| A nested read reads its parent again, as the person | `Query.read_related/4` |
| What a person can never see or do | `Model.for_actor/2`, on every `update/2` |
| Sensitive values never reach a render | `Sensitive.scrub/2` in `show/3`, `put_row/3`, `put_failed/4`, before the stream |
| Hidden values never reach a column's component | `cell/2` does not call the component for `%Ash.ForbiddenField{}` or `nil` |
| A URL that names a hidden field is ignored | `State.from_params/2` and `State.fit/2` work on the per-person model |

Two things follow for a headless design:

1. The re-read is **inside the pure modules**. A core that calls them keeps it.
2. The lookups (`rows`, per-person `model`) are **in the event handlers**. Whoever
   owns the handlers owns the guarantee. If a developer wrote the handlers, the
   developer could skip them. So the handlers must stay the library's.

Note: a read does not limit `select`. A record holds all attributes the action
returns, also those that are no column (**[code]** `query.ex` selects only in
`matching/3`). This matters for what an event may carry (section 5.3).

### 2.5 What makes the split hard

| Thing | Why it is hard | Answer |
| --- | --- | --- |
| 55 top-level assigns | On a host's socket they would collide with the host's own | One struct under one assign. Per-field change tracking survives (experiment) |
| Stream name `:rows` | Two tables on one socket | Stream named after the table |
| Async keys `:read`, `:bulk` | Same | `{:ash_table, name, :read}` |
| Upload names `"file-ARG"` | Same. And already today: upload names are unique per LiveView process across components (section 1.4) | `"ID-file-ARG"`. String names and late `allow_upload` work on a LiveView (experiment) |
| Event names `"sort"`, `"save"` | A `handle_event` hook sees every event of the LiveView | `"ash_table:ID:sort"`; the hook passes on anything else |
| `phx-target={@myself}` | No component, no `@myself` | `phx-target={nil}` renders no attribute; the event goes to the LiveView |
| `pushEventTo(this.el, …)` in hooks | Same | Goes to the LiveView when the element is in no component (**[code]** `view.ts` `closestComponentID`; not run in a browser) |
| `{:reply, map, socket}` | Hooks must be able to reply | `{:halt, reply, socket}` (experiment) |
| `url` attribute and `push_patch` | The page hands the URL down, the patch comes back through `update/2` | A `:handle_params` hook. Only for a LiveView mounted in the router (**[code]** `lifecycle.ex:44`) |
| Nested tables | They are inside stream items | **Corrected 2026-10-12, see section 10:** a registry entry with its own stream, rendered at the top level and teleported into the row (was: "they stay live components") |
| Picker | A table in a dialog, needs its own stream, state and selection | **Corrected 2026-10-12, see section 10:** one more registry entry on the host socket (was: "stays a live component") |

---

## 3. Design options

### 3.1 Option 1: reducer core plus function components

```elixir
def mount(_params, _session, socket) do
  {table, effects} = AshTable.Table.new(MyApp.Task, scope: socket.assigns.current_scope)
  {:ok, socket |> assign(tasks: table) |> AshTable.Table.perform(:tasks, effects)}
end

def handle_event("ash_table:" <> _ = event, params, socket) do
  {table, effects} = AshTable.Table.handle_event(socket.assigns.tasks, event, params)
  {:noreply, socket |> assign(tasks: table) |> AshTable.Table.perform(:tasks, effects)}
end

def handle_async({:ash_table, :tasks, _} = key, result, socket) do
  {table, effects} = AshTable.Table.handle_async(socket.assigns.tasks, key, result)
  {:noreply, socket |> assign(tasks: table) |> AshTable.Table.perform(:tasks, effects)}
end
```

Effects would be: reset the stream, insert a row, delete a row, start an async read,
start a bulk run, push an event, patch the URL, redirect, allow an upload, cancel an
upload, consume an upload and run an action inside it, reply to the hook.

Verdict: **no**.

- The effect list is the socket API written a second time. `perform/3` is the real
  core, and it takes a socket anyway.
- An upload is consumed **around** the action (`consume_uploaded_entry` runs the action
  while LiveView holds the file). A reducer that has already returned cannot do that
  without splitting each submit into two steps.
- The developer must wire three or four callbacks per table correctly. A missing
  `handle_async` clause is a table that stays busy forever.
- Safety: the developer holds the state value and could change it (`%{table | model: …}`).
- No Phoenix or Ash precedent. `AshPhoenix.Form` is a pure value because a form has no
  streams and no async. `AshPhoenix.LiveView` helpers, which do touch streams, take and
  return the socket (`assign_page_and_stream_result/3`, `keep_live/4`).

What is good in it: pure state transitions are easy to test. We keep that by leaving
the pure modules (2.2) pure, which they are.

### 3.2 Option 2: `attach`

```elixir
defmodule MyAppWeb.BoardLive do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     AshTable.attach(socket, :tasks, MyApp.Tracker.Task,
       scope: socket.assigns.current_scope,
       notify: true
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <AshTable.attached table={@tasks} rows={@streams.tasks} heading={2} />
      <.chart :if={@selected != []} keys={@selected} />
    </Layouts.app>
    """
  end

  # events out
  def handle_info({:ash_table, "tasks", {:selection_changed, selection}}, socket),
    do: {:noreply, assign(socket, selected: selection.keys)}

  def handle_info({:ash_table, "tasks", _other}, socket), do: {:noreply, socket}

  # commands in
  def handle_event("show_mine", _params, socket),
    do: {:noreply, AshTable.put_state(socket, :tasks, %{"f" => %{"assignee" => "me"}})}
end
```

What `attach` does: puts an `%AshTable.Table{}` under the assign `:tasks`, configures
the stream `:tasks`, attaches hooks for `:handle_event`, `:handle_async`,
`:handle_info` and (when the LiveView is routed and `url: true`) `:handle_params`, and
does the first read in place.

- **No live component for the table, and no wiring.** One line in `mount`, one tag.
- **Safe by construction.** The handlers are the library's. The reader is fixed at
  `attach`. Nothing the developer writes sits between the browser and Ash.
- **The same core serves the live component.** `attach_hook` works on a component's
  socket for `:handle_event` and `:handle_async` in LiveView 1.2 (**[code]**
  `lifecycle.ex:103`, experiment). Or the component simply delegates its callbacks.
- **Costs.** The whole refactor of section 6. The developer must pass the stream
  (`rows={@streams.tasks}`): a function component cannot reach `@streams` by itself.
- **Limits.** Hooks see every event of the LiveView, so names must be namespaced. An
  unknown `ash_table:…` event is passed on to the host, which will have no clause for
  it: the hook should halt on its own prefix and id and ignore what it does not know.

### 3.3 Option 3: keep the live component, add events and commands

```heex
<AshTable.table id="tasks" resource={MyApp.Tracker.Task} scope={@current_scope} notify />
```

```elixir
def handle_info({:ash_table, "tasks", {:row_saved, %{key: key}}}, socket), do: …

def handle_event("reload", _params, socket),
  do: {:noreply, AshTable.refresh(socket, "tasks")}   # send_update inside
```

- Smallest step. Days, not weeks. Nothing existing changes.
- Does not give "no live component" and does not decouple anything.
- It is needed anyway: the same events and commands are the API of option 2. So it is
  **stage 1** of the recommendation, not an alternative.

### 3.4 Option 4: hybrids, and how tables nest

> **Corrected 2026-10-12, see section 10:** this section missed two ways that work: a portal (section 10,
> mechanism 1, now recommended) and no streams at all (mechanism 5). The first row of
> the table below describes mechanism 3 only. Its verdict "No" holds for that way; the
> second row's "Yes" and the closing paragraph are superseded.

Three ways to nest a table in a headless design:

| Way | How | Verdict |
| --- | --- | --- |
| Nested state in the one struct, rendered by the host's function component | The nested table sits in a stream item of the outer table. A stream item is rendered when it is inserted and not again (experiment: an assign used inside a stream item did not update). So every change in a nested table would mean inserting the whole detail again: the full nested table over the wire for one sorted column or one saved cell. No stream for the nested rows, so their records must be kept in memory. Stream names would have to be made from row keys at run time. | No |
| Nested tables as live components, the top-level table attached | As today. Each nested table has its own socket: stream, async read, uploads, state. The same core and the same function components run in it. | **Yes** |
| Everything stays a live component | Today | Already there |

Pickers: a picker is not in a stream item, so it could be driven from the host's
socket. But it is a whole second table with its own selection, and at most one is
open. Keeping it a live component costs nothing and keeps one way of nesting.

So "no live components" becomes: **the developer never writes, renders or addresses
one. The library uses them inside, for tables inside tables.** Their events reach the
host as messages like all others, with the nested table's id and its path.

### 3.5 Comparison

| | 1 Reducer | 2 Attach | 3 Events only | 2+3 with nested components (recommended) |
| --- | --- | --- | --- | --- |
| Table without a live component | yes | yes | no | yes, top level |
| Developer wiring | 3–4 callbacks per table | 1 line + 1 tag | 1 tag | 1 line + 1 tag |
| Can authorization be skipped by wrong wiring | yes (state is the developer's value) | no | no | no |
| Events out, commands in | by hand | yes | yes | yes, same in all modes |
| Streams and diffs | same as today if `perform` is right | same as today | same | same |
| Existing users | unchanged | unchanged | unchanged | unchanged |
| Closest precedent | none | `attach_hook` (LiveView), socket helpers of `AshPhoenix.LiveView` | LiveComponent guide: `send(self(), …)` and `send_update` | both |
| Effort | very high | high | low | high, in safe steps |

### 3.6 Testability

- Pure modules: unit tests as today (`test/model_test.exs`, `pick_test.exs`, …).
- The core over a socket: `Phoenix.LiveViewTest` against a small host LiveView, as in
  the experiment. No browser needed.
- The three modes must behave the same. Run the same test module three times, with a
  setup that mounts the table mounted, embedded or attached. The demo's tests already
  address elements by id, which does not change between modes.
- The refactor steps are guarded by what exists: ~930 root tests, ~1,400 demo tests,
  ~780 browser tests.

### 3.7 Performance

- Streams: unchanged. One stream per table, on whichever socket holds the table.
- Diffs: one struct under one assign keeps per-field change tracking through a
  function component (experiment: a changed sort re-evaluated the sort expression
  only; a saved row rendered one row).
- A live component is a change-tracking boundary: a host re-render does not re-render
  the component. In attached mode, the function component is called again when
  `@tasks` or the stream changes, and LiveView still sends only what changed. No
  measurable loss expected. **[unverified]** on the real table: measure the demo's
  `/tasks` before and after stage 3.
- Attached mode saves one component process boundary, nothing else. Do not sell it as
  faster.

---

## 4. The component contract

The owner's added requirement: replacing the default daisyUI components must be easy,
with a defined contract so that other UI components work with the table.

### 4.1 What the contract is today

It is implicit. The server renders markup; the hooks find things in it. From the code
of the four hooks (**[code]**, counted by `grep`):

**Ids the hooks build themselves** (so a renamed id breaks behaviour):

| Id | Used for |
| --- | --- |
| `ID-grid` | The grid hook's element. Also found from a dialog by replacing `-panel`/`-picker` with `-grid` |
| `ID-table` | The `<table role="grid">`, the stream container |
| `ID-row-KEY` | A row's `<tbody>`; the key is read out of the id |
| `ID-row-KEY-c-FIELD` | A cell; `CELLID-error` is its message |
| `ID-row-KEY-e` | The expander cell |
| `ID-editor-FIELD` | The `<template>` of a column's editor |
| `ID-dialog`, `ID-dialog-question` | The confirm dialog |
| `ID-failure` | The popover of a failed save |
| `ID-selection` | The selection line |
| `ID-arguments` | The argument line's form |

**Ids the server names to the hooks** (`ash_table:focus`, replies with `focus:`):
`ID-arg-NAME-N`, `ID-panel-f-NAME…`, `…-r-N`, `…-choose`, `…-clear`.

**Ids that only tests, labels and `aria-*` references use**: `ID-head-FIELD`,
`ID-filter-FIELD` (`-operator`, `-value`, `-clear`), `ID-name`, `ID-header`,
`ID-status`, `ID-result`, `ID-selected`, `ID-select-all`, `ID-clear-selection`,
`ID-bulk-ACTION`, `ID-do-ACTION`, `ID-fill`, `ID-picker` and its three buttons,
`ID-panel`, `ID-related…`, `ID-full-view`, `ID-view`, `ID-resize-FIELD`.

**`data-*` attributes the hooks read or select by** (45):

| On | Attributes |
| --- | --- |
| Grid root | `data-ash-table`, `data-lead`, `data-select`, `data-choose`, `data-chosen-rows` |
| Table | `data-first-row` |
| Row | `data-key`, `data-current`, `data-selected` |
| Cell | `data-value`, `data-saved`, `data-pending`, `data-invalid`, `data-editor`, `data-commit`, `data-confirm`, `data-nested`, `data-line-cell`, `data-expander-cell`, `data-pager`, `data-masked`, `data-mask`, `data-secret`, `data-reveal` |
| Header and filter | `data-sort`, `data-filter`, `data-select-page`, `data-resize`, `data-clear` |
| Editor | `data-control`, `data-value-text`, `data-own`, `data-max`, `data-count` |
| Lists of values | `data-list`, `data-item`, `data-add`, `data-remove`, `data-more`, `data-show`, `data-hide` and their labels |
| Actions | `data-action`, `data-question`, `data-destructive`, `data-create`, `data-table-action`, `data-bulk`, `data-ask`, `data-scope`, `data-all`, `data-select-all`, `data-selection` |
| Panel | `data-field`, `data-add-group`, `data-remove-group`, `data-clear-field`, `data-unpick`, `data-cancel`, `data-arguments` |
| Picker | `data-take`, `data-none`, `data-cancel`, `data-several` |

**ARIA the hooks read or write**: `role="gridcell"`, `aria-colindex`, `aria-rowindex`,
`aria-selected`, `aria-expanded`, `aria-readonly`, `aria-disabled`, `aria-busy`,
`aria-invalid`, `aria-describedby`, `aria-current="page"`, `aria-valuenow/min/max`
(resizer), `aria-label`.

**Structure the hooks assume**: `<table>` inside the grid root; one `<tbody>` per row
(`closest("tbody")`); cells are `td` or `th`; a `<template>` per editor; `<dialog>` for
panel, picker and confirm; a popover for the failure; `button`, `input`, `select`,
`textarea` found by tag; `:scope > span > button[data-reveal]`; `[id$='-value']`.

**LiveView markers**: `phx-hook` `.Grid`, `.Panel`, `.Picker`, `.Pagination`;
`phx-update="stream"` on the table; `phx-update="ignore"` in three places;
`JS.ignore_attributes` on dialogs and on buttons whose state the hook owns.

**daisyUI in the markup**: `btn` (29), `btn-sm`, `btn-xs`, `btn-ghost`, `btn-primary`,
`checkbox`, `checkbox-xs`, `input`, `join`, `join-item`, `link`, `label`. Everything
else is Tailwind utilities. The hooks toggle three daisyUI classes themselves:
`btn-primary`, `btn-error`, `btn-disabled`.

### 4.2 Essential and incidental

| Keep (essential) | Why |
| --- | --- |
| Row and cell ids built from names and keys | Focus, patches, messages, `aria-describedby`, and ~3,000 tests address by id |
| `role="grid"`, `row`, `gridcell`, `columnheader`, `aria-colindex`, `aria-rowindex`, roving `tabindex` | The ARIA grid pattern; the keyboard depends on it |
| `data-key`, `data-value`, `data-editor`, `data-commit`, `data-control` | What is saved, how, and with which control |
| One stream container, one item per row (and one per detail) | Streams |
| The live region `ID-status` | Announcements |
| Dialog semantics for panel, picker, confirm | Focus trap and return |

| Remove or replace (incidental) | With |
| --- | --- |
| Hooks toggling `btn-primary`/`btn-error`/`btn-disabled` | A state attribute (`data-destructive`, `aria-disabled`); the kit styles by attribute |
| Tag selectors (`table`, `tbody`, `td,th`, `button`) | `data-part="row"`, `data-part="cell"`, … carried by the bundles |
| `[id$='-value']`, `:scope > span > button[data-reveal]`, `dialog.id.replace(…)` | Explicit `data-*` references |
| State shown only by Tailwind classes written in HEEx (pending, invalid, selected) | State attributes the hook or server already set; classes hang off them |

After that, the contract a kit author must know is short: **spread the bundle you are
given on the element it is meant for, and keep the part's element kind where the table
says so.**

### 4.3 How others do it

| Who | How the look is replaced | For ash_table |
| --- | --- | --- |
| Flop Phoenix | `opts` with attribute lists per element (`table_attrs`, `thead_th_attrs`, `tbody_td_attrs`, `container_attrs`), set once in config or per call (**[code]** `EXT/flop_phoenix/lib/flop_phoenix.ex:176-204`). Filter inputs are the host's own input component. `pagination_for/1` yields a struct for fully own markup | Attribute lists for the skeleton; the host's own controls for leaf parts |
| Cinder | Themes: `use Cinder.Theme` with `set :row_class, "…"`, named in `config :cinder, default_theme:` or per table (**[code]** `EXT/cinder/lib/cinder/theme.ex:1-45`). Renderers (`table`, `list`, `grid`) are the library's | Classes per part, named once in config, overridable per table. The Ash-world precedent |
| Backpex | The host's layout, and named slots (`render_resource_slot(assigns, :index, :actions)`) (**[code]** `EXT/backpex/lib/backpex/live_resource.ex:254, 533-548`). Fields are modules | Slots by name for page areas |
| TanStack Table | No markup at all; per-framework adapters; the developer writes every element | Possible only because it has no DOM behaviour |
| React Aria | Hooks return props; the developer spreads them (`{...buttonProps}`) on own elements. **[unverified]** today, from memory | Bundles |
| shadcn/ui | Component source is copied into the app and owned there | Section 4.5 |
| Phoenix `core_components.ex` | Generated into the app by `phx.new` | Section 4.5 |
| ash_table today | `AshTable.Component`: `cell/1`, `editor/1` with `@control` to spread, `verify/1` at compile time | The seed of the model |

### 4.4 The proposed model: bundles, kit, conformance test

**One idea, already in the code.** A custom editor today gets `@control` and must put
`{@control}` on its form control (`AshTable.Component`). The table computes the
attributes; the author owns the markup. Extend exactly that to every part.

**Bundles.** For each element the hooks or the server need, the part receives a
ready-made attribute map:

```heex
<%!-- the kit's pagination part --%>
<nav {@root}>
  <button :for={page <- @pages} {page.attrs} class="my-page-button">{page.label}</button>
</nav>
```

`@root` and `page.attrs` hold the id, role, ARIA, `data-*`, `phx-click`, `phx-target`
and `phx-hook`. The author never types one of them. A new marker in a later version is
added to the bundle and reaches every kit without an edit.

**A kit.** One module names a set of parts. Every part has a default, so a kit can
replace one or all:

```elixir
defmodule MyAppWeb.TableKit do
  use AshTable.Kit, contract: 1

  # replace one part
  @impl true
  def pagination(assigns) do
    ~H"""
    <nav {@root} class="flex gap-1">
      <.my_button :for={page <- @pages} {page.attrs} current={page.current?}>{page.label}</.my_button>
    </nav>
    """
  end

  # restyle the grid without replacing it
  @impl true
  def class(:table, _state), do: "w-full text-sm"
  def class(:cell, %{invalid?: true}), do: "px-2 ring-2 ring-red-600"
  def class(part, state), do: super(part, state)
end
```

Named once, overridable per table:

```elixir
config :ash_table, kit: MyAppWeb.TableKit        # like `layout` and `gettext_backend`
```

```heex
<AshTable.table id="tasks" resource={MyApp.Task} kit={MyAppWeb.CompactKit} scope={@current_scope} />
```

**Two tiers of parts.** Not every part can be replaced at the same price.

| Tier | Parts | What a kit may do | Why |
| --- | --- | --- | --- |
| Replaceable parts | heading line, create and action buttons, selection line, argument line, filter control, pagination, action panel frame, panel field wrapper, picker frame, confirm dialog, failure popover, empty and error messages, loading mark, relationship line, full-view link, footer (when it exists) | Its own markup, with the bundles spread | The hooks touch these in a few named places |
| The grid skeleton | table, header row, filter row, row, cell, detail row, editor template | Classes only, through `class/2` | The grid hook (2,400 lines) walks this structure; ARIA grid correctness and the keyboard are the table's promise |
| Cell content and editor control | what is inside a cell, what a value is edited with | Its own markup; this is today's `AshTable.Component` | Already replaceable |

The skeleton can move to the first tier later, once the hooks find things by
`data-part` and not by tag. That is a large JavaScript change and should not block the
kit.

**Owner's decision, 2026-10-12:** the goal is fully headless. Every element gets a
bundle, rows and cells too, and the hooks rely on the markers in the bundles only, not
on tag names. The two tiers above are then the first step, not the end. The inventory
of what the grid hook assumes about `table`, `tbody`, `tr` and `td` today is in 10.3
(mechanism 4): about 75 statements in 25 functions.

**What each part receives.** The first cut, to be fixed when stage 5 is built:

| Part | Assigns (besides bundles) |
| --- | --- |
| `heading` | `label`, `level`, `create` (label or nil), `table_actions` |
| `selection_line` | `count_text`, `scope` (`:page`/`:all`), `bulk_actions` (label, destructive?, question), `running?`, `result` |
| `argument_line` | `arguments` (label, type, value, errors, required?), each with its control bundle |
| `filter` | `column` (as `AshTable.Component.Column`), `operators`, `value`, `rejected?` |
| `pagination` | `pages` (label, current?, attrs), `previous`, `next`, `range_text`, `total` |
| `panel` | `title`, `submit_label`, `error`, slot of fields, `kind` |
| `field` | `label`, `required?`, `errors`, `help`, the control as a slot or the kit's `control` |
| `control` | `type` (text, number, select, checkbox, date, file, …), `value`, `choices`, `control` bundle, `place` |
| `picker` | `title`, `several?`, `none?`, `error`, slot of the table |
| `confirm` | `question`, `destructive?` |
| `line` (relationship) | `label`, `open?`, `create`, `table_actions` |
| `message` | `kind` (`:empty`, `:error`, `:fill`, `:forbidden`, `:loading`), `text` |
| `cell` / `editor` | as `AshTable.Component` today: `value`, `text`, `column` / `value`, `control`, `label`, `column`, `place` |
| `class/2` | part name and a state map (`selected?`, `invalid?`, `pending?`, `nested?`, `editable?`, `align`, `density`) |

Never given to a part: the record, the actor, another field of the row. Same rule and
same reason as for a column's component today.

**Checkable, not folklore.**

| Check | When | Catches |
| --- | --- | --- |
| `use AshTable.Kit, contract: 1` | compile time (`@after_compile`) | A part with the wrong arity, an unknown part name, a kit written for another contract version |
| The table, when it is built with a kit | first render | A kit module that does not exist or is no kit: same message style as a column's component |
| `AshTable.KitCase` | the developer's `mix test` | A bundle that was not spread: the case renders a fixed table (a resource on the ETS data layer shipped in the library's test support) through the kit in every state (empty, error, selected, editing, panel open, picker open, nested) and asserts each required id, role, ARIA and `data-*` marker, one control per editor, one tab stop per grid |
| The grid hook in development | `mounted()` and `updated()`, only when `data-dev` is set | A missing marker, as a `console.error` naming the part and the marker |
| Contract version | compile time and release notes | A library upgrade that needs kit changes: the version goes up, the message says what changed |

```elixir
defmodule MyAppWeb.TableKitTest do
  use AshTable.KitCase, kit: MyAppWeb.TableKit
end
```

**Versioning.** The contract has an integer version. Adding a marker inside a bundle
does not raise it. Adding a required part with a default does not raise it. Changing
what a part receives, or removing a bundle, raises it; the library then supports the
old number for one minor release with a warning.

### 4.5 Generating components into the host app

`phx.new` writes `core_components.ex` into the app; shadcn copies component source.
For ash_table:

- **Fits** the replaceable parts: buttons, inputs, dialogs, pagination. A generator
  `mix ash_table.gen.kit MyAppWeb.TableKit` could write a kit with every replaceable
  part spelled out, calling the app's own `core_components` (`<.button>`, `<.input>`).
  That is the fastest way to "the table looks like my app".
- **Does not fit** the grid skeleton and the hooks. Copied once, they stop getting
  fixes, and the keyboard and ARIA behaviour drift. Never generate those.
- Cost: generated code is the developer's from then on. The contract version and
  `KitCase` are what make that safe.

Recommended: the default kit lives in the library. The generator is an optional later
step, and writes only replaceable parts.

### 4.6 Accessibility and the keyboard when markup is replaced

Rule: **hooks own behaviour, bundles own semantics, kits own looks.**

- Roles, ARIA states, ids, `tabindex`, and the references between them are in the
  bundles. A kit that spreads them cannot get them wrong.
- The live region, the confirm dialog's focus handling, the roving tab stop and every
  key are the hooks' and are not parts.
- What the kit owes, and `KitCase` plus the guide must say: a visible focus indicator;
  contrast (4.5:1 text, 3:1 for state and edges); no state by colour alone (the state
  is an attribute, the kit must show it); nothing focusable added inside a cell; one
  line per row unless the kit says otherwise; `aria-hidden` on what is said twice.
  This is the list `documentation/topics/custom-components.md` already gives for a
  column's component.
- `KitCase` can check structure. It cannot check contrast or the focus ring. The
  demo's browser tests do (`demo/e2e/contrast.spec.ts`). Offer those specs as a
  template a kit author can run against their own page. **[unverified]** how reusable
  they are outside the demo.

### 4.7 One model with the per-column `component`

| | Column's `component` (today) | Kit (new) |
| --- | --- | --- |
| Named in | the resource's `table` block, per column | config, or per table |
| Parts | `cell/1`, `editor/1` | all parts, among them `cell/1` and `editor/1` |
| Given | values and a bundle (`@control`) | values and bundles |
| Checked by | `verify/1` at compile time | `use AshTable.Kit` at compile time, `KitCase` in tests |

Resolution for a cell: the column's component, else the kit's `cell/1` for that cell
type, else the library's default. The same for the editor. So `AshTable.Component` is
"a kit for one column with two parts", with the same assigns. Nothing changes for
existing components.

---

## 5. Recommendation and public API

**Approach: one socket-level core, three wrappers, nested tables as registry entries
shown through portals (**Corrected 2026-10-12, see section 10:** was "as internal live components"), events as
messages, commands as functions, a kit for the look.**

### 5.1 Modules

| Module | Public? | Job |
| --- | --- | --- |
| `AshTable` | yes | `table/1` (unchanged), `attach/4`, `attached/1`, `detach/2`, the commands |
| `AshTable.Table` | yes, opaque | The state struct. Documented read-only fields: `id`, `resource`, `state` (sort, filters, page as params), `count`, `total`, `loading?`, `error`. Everything else under `private` |
| `AshTable.Live.Core` | no | `init`, `update`, `handle_event`, `handle_async`, `handle_info`, `handle_params`: socket in, socket out, for a table under a given assign |
| `AshTable.Live.Parts` | no | Today's private function components, reading `@table` |
| `AshTable.Live.TableComponent` | no | Live component: delegates to `Core`, renders `Parts`. Used by `table/1` only (**Corrected 2026-10-12, see section 10:** no longer by nested tables and pickers) |
| `AshTable.Live.Page` | no | Uses `attach` itself |
| `AshTable.Kit`, `AshTable.KitCase` | yes | Section 4 |
| `AshTable.Model`, `State`, `Query`, … | no (for now) | The pure modules. Making some public is decision 9 |

### 5.2 What the developer writes in each mode

Mounted (unchanged):

```elixir
ash_table "/tasks", MyApp.Tracker.Task
```

Embedded (unchanged, plus `notify`):

```heex
<AshTable.table id="tasks" resource={MyApp.Tracker.Task} scope={@current_scope} notify />
```

Attached (new):

```elixir
def mount(_params, _session, socket) do
  {:ok, AshTable.attach(socket, :tasks, MyApp.Tracker.Task, scope: socket.assigns.current_scope)}
end
```

```heex
<AshTable.attached table={@tasks} rows={@streams.tasks} />
```

**Corrected 2026-10-12, see section 10:** the tag takes `streams={@streams}`, not one stream: nested tables
and pickers have streams of their own, named by the core.

`attach/4` options: `id` (default: the name as a string), `scope` or `actor` and
`tenant`, `authorize?`, `url` (`true` keeps the state in the URL through a
`handle_params` hook), `label`, `notify`, `kit`, `assigns` (for argument defaults).
They are the attributes of `<AshTable.table>`.

When who is asking changes: `AshTable.attach/4` again with the same name replaces the
reader and reads again.

### 5.3 Events out

A message to the LiveView process, only when `notify` is set:

```elixir
{:ash_table, id, {event, payload}}
```

`notify: true` sends all; `notify: [:row_saved, :selection_changed]` sends those.

| Event | Payload | Notes |
| --- | --- | --- |
| `:read` | `%{state: params, count: n, total: n | nil}` | After every read that showed rows |
| `:read_failed` | `%{reason: :forbidden | :error}` | No error struct: it may name what the person may not know |
| `:row_saved` | `%{key: map, column: atom, record: record}` | An inline edit that the action accepted |
| `:row_created` | `%{key: map, record: record | nil}` | `record` nil when the person may not read what they created |
| `:row_destroyed` | `%{key: map}` | |
| `:action_ran` | `%{action: atom, type: atom, key: map | nil, record: record | nil, result: term}` | Row actions and table actions |
| `:bulk_ran` | `%{action: atom, done: n, failed_keys: [map]}` | |
| `:selection_changed` | `%{keys: [map], all?: boolean, count: n}` | See below |
| `:row_expanded`, `:row_collapsed` | `%{key: map}` | |

Rules:

- **`key` is the primary key as a map**, as the table read it. Never the DOM id.
- **`record` is what the action returned to this actor.** Ash has applied field
  policies to it; a hidden field is `%Ash.ForbiddenField{}`. It is not scrubbed of
  `sensitive?` values, and it holds attributes that are no column. The host is server
  code of the same application, like the caller of `AshPhoenix.Form.submit/2`. Say so
  in the guide. (Decision 5.)
- **Selection is a claim.** Which rows are selected is the browser's. The keys in
  `:selection_changed` are what the browser said, parsed with the table's own key
  parser, not read. To act on them, the host calls
  `AshTable.selected_records(socket, :tasks, selection)`, which reads them through the
  table's read action as the person (`Query.records/3` exists for bulk actions). The
  event costs a round trip per selection change, so it is sent only when asked for.
- **Nested tables and pickers** send the same messages with their own id and
  `path: [{parent_key, relationship}, …]` in the payload. The id of a nested table is
  not stable enough to match on; the path is.
- For "a task changed, whoever changed it", the Ash way is the resource's own
  notifications (`Ash.Notifier.PubSub`). The table's events say what **this person did
  in this table**. Do not rebuild notifiers in the table.

### 5.4 Commands in

One set of functions for both modes. Given a name that is an attached table, they act
on the socket. Given the id of an embedded table, they `send_update` it. Both return
the socket.

| Command | Does |
| --- | --- |
| `AshTable.refresh(socket, table)` | Reads again, as the person, keeping state, open rows closed as on any read |
| `AshTable.put_state(socket, table, params)` | Sets sort, filters, page, arguments from the same map the URL holds (`%{"sort" => "-title", "f" => %{…}, "a" => %{…}}`). It goes through `State.from_params/2`, so a hidden column is ignored, as in a URL |
| `AshTable.clear_selection(socket, table)` | Tells the hook (`push_event`) |
| `AshTable.selected_records(socket, table, selection)` | Reads the selected records as the person |
| `AshTable.detach(socket, name)` | Removes hooks, stream and assign |

Not offered: "save this cell", "run this action" as commands. The host can call the
resource directly. The table is an interface for a person, not an API for code.

### 5.5 What the library guarantees in every mode

1. Who is asking comes from `attach` or the tag. Never from an event.
2. Every write reads the record again, as the person.
3. Every event is checked against the person's page and model.
4. Sensitive values are scrubbed before any render.
5. A part of a kit never receives a record.
6. The `%AshTable.Table{}` struct is opaque. Changing it by hand is unsupported, and
   the handlers do not trust it more than they trust assigns today: the reader is in
   it, and only server code can reach it.

---

## 6. Staged plan

Each stage ships by itself. Stages 2 to 4 change no behaviour and are guarded by the
existing suites (~930 root, ~1,400 demo, ~780 browser tests).

| Stage | What | Changes behaviour? | Risk |
| --- | --- | --- | --- |
| 1 | **Events and commands on today's component.** `notify`, the messages of 5.3, `refresh`, `put_state`, `clear_selection` via `send_update` and one `update/2` clause; the hook pushes `selection` when asked | Adds only | Low |
| 2 | **Split the file.** Move the function components to `AshTable.Live.Parts` (several files by part), the hooks with the root markup. Colocated hook names are relative (`.Grid`), so they follow the module | No | Low. Mechanical, large diff |
| 3 | **One struct.** Move the ~55 assigns into `%AshTable.Table{}` under `assigns.table`; parts read `@table.x`. Stream name, async keys and upload names become functions of the table | No | Medium. Touches every line that reads an assign. Measure the diff size of `/tasks` before and after |
| 4 | **The core.** Move `mount`, `update`, `handle_event`, `handle_async` bodies to `AshTable.Live.Core`, taking the assign name. The component delegates. Event names become `ash_table:ID:event` in markup and hooks | No (names on the wire change; ids and markup do not) | Medium. The 20 `pushEventTo` calls and 40 `phx-target`s |
| 5 | **`attach/4` and `attached/1`.** Hooks for the four stages, `handle_params` for URL state, the first read in place. Run the mode-independent tests three ways | Adds only | Medium |
| 6 | **The page uses `attach`.** `AshTable.Live.Page` drops its live component | DOM loses `data-phx-component` on the root; ids stay | Low to medium. Can be skipped |
| 7 | **Kit, step 1.** Bundles for the replaceable parts, `AshTable.Kit`, `class/2` for the skeleton, config and attribute. Hooks stop toggling daisyUI classes | Default look unchanged | Medium |
| 8 | **Kit, step 2.** `AshTable.KitCase`, dev-mode marker check in the hook, guide, optional generator | Adds only | Low |
| Later | Skeleton parts replaceable (`data-part` selectors in the hooks); pure modules made public | | High / low |

Stage 1 is independent of the rest and can go first or in parallel. Stages 7 and 8
depend on stage 2 only, so the kit can come before `attach` if the owner wants looks
before headless.

Another agent is changing `table_component.ex` now. Stages 2 to 4 rewrite that file,
so they need a quiet tree: do them between feature slices, each in one sitting.

---

## 7. The experiment

Where: `/tmp/claude-1000/-home-stefan-roesch-doloops-ash-table/5c7207f9-c9ac-4f1f-a341-9d59f2b21019/scratchpad/headless-research/exp/`
(`lib/ht.ex`, `test/exp_test.exs`). A throwaway Mix project with path dependencies on
the demo's `deps` (LiveView 1.2.12, Phoenix 1.8.15). No Ash in it: it tests the
LiveView mechanisms only. `mix test`: 2 tests, 0 failures.

A toy table `HT`: a struct under one assign, `HT.attach/3`, a function component
`HT.table/1`, a stream named after the table, an async read under
`{:ht, name, :read}`, events named `ht:ID:event`.

What I saw:

| Question | Result |
| --- | --- |
| Two tables in one LiveView with no live component | Works. Each has its own assign, stream and hooks |
| A `handle_event` hook answers a JS hook's event with a reply | Works: `{:halt, %{ok: true}, socket}` |
| The host's own `handle_event`, `handle_async` and `handle_info` still run | Yes. The hooks return `{:cont, socket}` for what is not theirs |
| A `handle_async` hook takes the table's reads and leaves the host's own | Yes, matched on the key |
| Streams on the host's socket, reset by an async read, one row inserted by a save | Works. A sort rendered 5 rows of that table and none of the other; a save rendered 1 row |
| Change tracking through one struct into a function component | Per field. Changing `sort` re-evaluated the expression that reads `@table.sort` and not the one that reads `@table.label`; and the reverse |
| Events out by a callback given at attach | Works (the callback gets the socket). Messages were not tried; they are plain `send/2` |
| Commands in: from a host event, and from a message to the process | Both work (`HT.refresh/2`, and a `handle_info` hook) |
| `allow_upload` under a string name, called from an event long after mount, on a LiveView | Works; `live_file_input` renders |
| The same `attach` on a live component's socket (`handle_event` and `handle_async` hooks) | Works in 1.2.12. `handle_info` and `handle_params` hooks raise there, as `lifecycle.ex:103` says |
| An assign read inside a stream item after the item was inserted | Not updated (`<span id="inner">` kept `0` while the assign went to `42`). **Corrected 2026-10-12, see section 10:** the observation stands; the conclusion "this is why a nested table cannot be host-driven" was wrong |

Not tested, read from code only: that `pushEventTo(this.el, …)` from a hook on an
element outside any live component reaches the LiveView
(`deps/phoenix_live_view/assets/js/phoenix_live_view/view.ts`, `closestComponentID`
returns null without an enclosing `data-phx-component`). Stage 4 proves it in the
demo's browser tests.

Not tested: `handle_params` hooks with `push_patch`; uploads consumed in a hook;
colocated hooks compiled from a function-component module of a dependency.

---

## 8. Decisions for the owner

| # | Decision | Recommended | Why |
| --- | --- | --- | --- |
| 1 | Pure reducer core, or a core over the socket? | Over the socket | Streams, async, uploads and replies live on the socket; `AshPhoenix.LiveView` helpers do the same |
| 2 | How does a host LiveView get a table without a live component? | `AshTable.attach/4` with `attach_hook` | LiveView's own mechanism; one line; the handlers stay the library's, so authorization cannot be wired away |
| 3 | May nested tables and pickers stay live components inside the library? | **Corrected 2026-10-12, see section 10:** No need: see decisions 17–25 in 10.8 (was: "Yes") | The stated reason was wrong: a portal keeps streams and sends small diffs |
| 4 | How do events reach the host? | Messages `{:ash_table, id, {event, payload}}`, opt-in with `notify` | Works the same mounted, embedded, attached and nested. Cinder does the same with host-named messages. LiveView's guide prefers a function passed as an assign; a function written in a template is a new value on every render, which would run the table's `update/2` each time |
| 5 | What does an event carry: keys, or records too? | Keys always; the record as the action returned it to the actor | Field policies are applied by Ash; the host is the application's own server code |
| 6 | Is `:selection_changed` worth a round trip per change? | Yes, but only when asked for by name | It is the owner's own example; nobody else pays for it |
| 7 | Commands: which? | `refresh`, `put_state`, `clear_selection`, `selected_records` | State in the URL's own vocabulary needs no new validation; writes go to the resource, not through the table |
| 8 | Does `AshTable.Live.Page` move to `attach`? | Yes, after stage 5 | It proves the attached mode with every mounted-table test |
| 9 | Make `Model`, `State`, `Query` public as a data API (the Flop shape)? | Not now | It freezes structs that still change every slice. Revisit after the first release |
| 10 | Names: `attach` / `attached`? | `AshTable.attach/4`, `<AshTable.attached>` | `attach` matches `attach_hook`; the tag name is open to taste |
| 11 | Where is a kit named? | `config :ash_table, kit:`, and `kit=` per table and per router line | Web modules are named in config today (`layout`, `gettext_backend`); a resource should not name the look of the whole table |
| 12 | Is the grid skeleton replaceable in the first kit? | No: classes only. **Corrected 2026-10-12, see section 10:** the owner has since set the goal: bundles for every element, rows and cells included, and hooks that read markers only (decision 25) | The grid hook walks it; ARIA grid and keyboard are the table's promise |
| 13 | Generate the default kit into the host app? | No by default; an optional generator for replaceable parts later | Generated skeleton and hooks would stop getting fixes |
| 14 | One model with the column's `component`? | Yes: the kit has `cell/1` and `editor/1` with the same assigns; a column's component wins | One vocabulary: values plus a bundle to spread |
| 15 | What goes first? | Stage 1 (events and commands), then the refactor | It answers the owner's "another component reacts" at once and fixes the API the later stages must keep |
| 16 | Kit before or after `attach`? | Owner's call; both depend only on stage 2 | Theming is slice 7 of the spec and needs its own decisions |

---

## 9. What not to do

- **No pure reducer with an effect list.** It rewrites the socket API and makes the
  developer wire it.
- **No macro that injects callbacks** (`use AshTable.LiveView` defining
  `handle_event/3`). It collides with the host's own clauses. `attach_hook` exists for
  this.
- ~~No headless nested tables.~~ **Corrected 2026-10-12, see section 10:** withdrawn.
- **No event handlers written by the developer** for the table's own events. The
  lookups that guard a write are in them.
- **No records to kit parts.** Same rule as for a column's component.
- **No commands that write** ("save cell", "run action"). The resource has actions.
- **No rebuild of notifications.** `Ash.Notifier.PubSub` says that data changed.
- **No generated copy of the hooks or the grid skeleton** in the host app.
- **No public `Model`/`State`/`Query` yet.**
- **No change to `<AshTable.table>` or `ash_table` in the router.** Both keep working
  as they are through every stage.

---

## 10. Nested tables without live components

Added 2026-10-12, after the owner's "dig deeper". LiveView 1.2.12. All of it was run:
**[test]** is `Phoenix.LiveViewTest` (`mix test`: 15 tests, 0 failures), **[browser]** is
Chromium through Playwright (`browser/portal.mjs`: 27 checks, `browser/others.mjs`: 17
checks). Files are listed in 10.9. `LV/` is `demo/deps/phoenix_live_view/`.

### 10.1 Verdict

**The earlier conclusion was wrong.** It said a nested table cannot be driven from the
host's socket without giving up streams. It can. The fact behind it is true: a stream
item is rendered once. The conclusion drawn from it was not.

**What works:** every table (top level, nested at any depth, picker) is one entry in a
flat registry on the host socket, each with its own stream. Each open nested table is
rendered at the top level of the template, where it follows assigns, and LiveView's
`<.portal>` puts its DOM into the cell of the parent's stream row. The DOM is the same
as today: a grid in a grid cell. No `live_component` anywhere. Three levels, pickers,
uploads, hooks, focus, cleanup: all pass in a real browser.

**The remainder is not a live component.** It is this: `Phoenix.LiveViewTest` does not
look into a portal, so tests reach a nested table through a small helper and not
through `element/3`. And the combination "portal target inside a stream row, stream
inside the portal" has no test upstream; ash_table's own browser tests must guard it.

### 10.2 How LiveView ties a stream to its container

This decides everything below, so it comes first. **[code]**

- A stream is a struct on the socket with pending inserts and deletes. It is
  enumerable only inside a `for`, and yields the **pending** inserts only
  (`LV/lib/phoenix_live_view/live_stream.ex:96-124`).
- The diff attaches the operations to **the comprehension that consumed the stream**:
  `[ref, inserts, deletes, reset?]` (`live_stream.ex:81-92`, `diff.ex:821-822`).
- After every render the pending operations are thrown away, rendered or not
  (`LV/lib/phoenix_live_view.ex:2285-2296`, the `:after_render` hook that prunes).
- In the browser nothing names a container. Deletes are done by element id, a reset by
  `[data-phx-stream=ref]`, both over the whole document; inserts arrive as the children
  of whatever element the comprehension sits in (`assets/js/phoenix_live_view/dom_patch.ts:517-532, 232-257`).
- A stream item is rendered in full each time and keeps no fingerprints
  (`diff.ex:771-796`). So nothing inside it is change-tracked, and nothing inside it is
  evaluated again unless the item is inserted again.

So: **stream operations reach the browser only if the `for` over that stream is
evaluated in that render.** A `for` that sits inside another stream's item is evaluated
only when that item is inserted again. Otherwise the operations are dropped, silently.

### 10.3 The mechanisms, each tested

| # | Mechanism | Result | Shown by |
| --- | --- | --- | --- |
| 1 | **Portal**: nested table rendered at the top level, teleported into the parent's stream row; its own stream inside the portal | **Works.** Same DOM as today | `test/portal_test.exs` (6 tests), `browser/portal.mjs` (27 checks) |
| 2 | **Stream container inside a stream item**, fed by a second stream of the socket | **Does not work by itself**: the operations are lost. Works when the parent's detail item is inserted again on every nested change | `test/others_test.exs` "without inserting the parent item again…" (a save sends 47 bytes and nothing arrives); "with the parent's detail item inserted again it works, three levels deep"; `browser/others.mjs` |
| 3 | **Insert the parent item again**, nested rows as plain markup in it | Works. Sends the whole subtree for every change. `:key` does not help inside a stream item | `test/others_test.exs` "mechanism 3", and the sizes in 10.5 |
| 4 | **One flat stream, flat DOM**: nested rows, header and footer lines are sibling items placed with `at:` | Works, positions are reliable. But it changes markup, layout, ARIA and a quarter of the grid hook | `test/others_test.exs` "mechanism 4"; `browser/others.mjs` (order, alignment, sticky, resize, axe); screenshots in `browser/shots/` |
| 5 | **No streams**: one state tree, one recursive function component, `:key` on rows | **Works.** Simplest. Smallest diffs. Rows are kept in memory | `test/others_test.exs` "mechanism 5" |
| 6 | **Child LiveView** (`live_render`) in a stream item | Works. Another process per nested table | `test/others_test.exs` "option 6" |
| — | **Picker** driven from the host socket, also opened from a nested table | Works with 1 and with 5 | `portal_test.exs` "a picker…", `others_test.exs` "mechanism 5", `browser/portal.mjs` |

#### Mechanism 1: portal (flat inside, nested in the page)

What the experiment does (`lib/portal_live.ex`):

```heex
<.grid t={@tables["t"]} rows={@streams["nt:0"]} />
<.portal :for={t <- nested(@tables)} :key={t.id} id={"portal-#{t.id}"} target={"##{t.target}"}>
  <.grid t={t} rows={@streams[t.slot]} />
</.portal>
```

`@tables` is the flat registry: id → table. `t.target` is the id of the cell in the
parent's stream row. `nested/1` sorts parents before children.

| Question | Result |
| --- | --- |
| Portal target inside a stream item | Works **[browser]**. The nested table is physically in the cell; the cell's only child is the portal's wrapper `div` |
| `phx-update="stream"` container inside a portal | Works **[browser]**: insert, reset, delete; rows are not duplicated |
| `phx-click` from teleported content | Reaches the LiveView **[browser]** |
| Hook in teleported content: `mounted`, `updated`, `destroyed`, `pushEventTo(this.el)` with a reply | All work **[browser]**. `closestComponentID` follows the portal back to its source (`view.ts:1783-1808`) |
| Three levels | Works **[browser]**: level 3 is inside level 2 inside level 1 inside the top row. A sort at level 3 changes level 3 only |
| Parent row inserted again (`stream_insert`, as after a cell save) | Nested tables are kept, once. Focus three levels down stays. Text typed into a nested filter stays. No hook is destroyed or mounted again **[browser]**. Reason: "don't remove teleported elements" (`dom_patch.ts:343-346`) |
| Parent stream reset with the row still on the page (sort of the top table) | Nested table survives **[browser]** |
| Parent row deleted; parent page changed | The nested DOM leaves with the row; its hooks get `destroyed()` **[browser]**. The server must drop the nested table in the same step (see "the mistake") |
| Target row and portal arrive in the same patch | Works **[browser]**: teleports run after the morph (`dom_patch.ts:188-191, 553-561`) |
| Accessibility tree | `grid` → `row` → `gridcell` → `grid`, three deep, as today. axe: no violations **[browser]** |
| Change tracking with a dynamic set of streams (`@streams[t.slot]`) | Per field of the table's struct, also through the portal's slot **[test]**. A sort three levels down renders 3 rows and nothing else. The host's own assign: 9 bytes, no table rendered. Each open table costs about 160 bytes on another table's stream change |
| Stream names | A pool of names (`"nt:1"`, `"nt:2"`, …), reused after a table closes **[test]**. Names made from row keys would leave one stream struct and one `:after_render` hook on the socket for every table ever opened; `stream_configure` cannot be undone |
| Upload in a nested table | Works **[browser]**: name `"file:" <> table id`, the entry reaches the server |
| A patch that touches no table | Hooks are not told `updated`. About 5 ms per patch with 50 rows, with or without three nested tables open **[browser]** |

Limits, with the source:

- **LiveViewTest does not see portal content.** "you cannot query for elements inside
  of a portal when using `Phoenix.LiveViewTest.element/3`" (`LV/lib/phoenix_component.ex:3560-3579`).
  Confirmed **[test]** "LiveViewTest does not look into a portal": `has_element?` is
  false, `render/1` of the portal has the markup, `file_input/4` cannot reach a nested
  file input. `LazyHTML.query` on the page's HTML does not look into `<template>`
  either. Upstream closed the pull request that would have taught the test client to
  teleport (#3952). Events can still be sent by name (`render_click(view, event, value)`).
- **The mistake.** If the parent row leaves and the portal is still rendered, the
  browser throws "portal target with selector … not found" (`dom_patch.ts:871-874`)
  **[browser]**. The page keeps working. One `close(prefix)` function in the core that
  every row removal and every read calls prevents it.
- **Upstream has no test for this combination.** It tests a stream in a portal only
  inside a live component (`test/e2e/tests/portal.spec.js`, "streams work in teleported
  LiveComponent"), and a portal *source* in a stream item (issue #4442, fixed in
  1.2.12). Target-in-stream-row with an own stream in the portal is ours to guard.
- Nested portals are limited to 5 passes (`dom_patch.ts:554-561`). It does not apply
  here: the portals are siblings at the top level, parents first, done in one pass.
- A portal needs one root element with an id; `portal/1` supplies the wrapper
  `_lv_portal_wrap_<id>` and takes a `class`. Today's wrapper `div.w-0.min-w-full` can
  be that element, so the depth of the DOM does not change.
- Nothing is in the first (dead) render. A nested table is never open then.

#### Mechanism 2: nested stream, parent item inserted again

`lib/reinsert_stream_live.ex`. Without the re-insert a save in the nested table sends
47 bytes and the row never changes **[test]**. With it, three levels work **[test]**
**[browser]**: the browser keeps the nested rows (children of a stream container are
never discarded, `dom_patch.ts:332-342`) and focus stays.

Costs: the header, filter row and every other part of the nested table around its rows
is sent again for every change, and so is the same of every table above it (10.5). Text
typed into a nested filter and not yet sent is cleared **[browser]**. The server must
walk up and insert each ancestor's detail item.

#### Mechanism 3: plain markup in the parent's detail item

`Exp.ReinsertPlainLive`. Every change sends the whole subtree under the top-level row:
21 kB for one cell, 63 kB at level 3. A keyed comprehension inside a stream item is
rendered in full each time (`diff.ex:771-796`; "`:key` has no effect when using
streams", `phoenix_component.ex:872`). This is what the note assumed was the only way.

#### Mechanism 4: one flat stream, a flat DOM

`lib/flat_live.ex`: internals are a registry; the stream is one flat list of rows,
header lines and footer lines, each with the id of its table.

- **Ordering.** The stream API has `at: index` and nothing like "after this id". The
  index counts all children of the container (`dom_patch.ts:253-256`). The core keeps
  the ordered list of item ids (ids only, no records) and computes each position.
  Through open, nested sort, close, delete and reset the DOM matched the server's list
  **[test]** **[browser]**. Rule to keep: deletes are applied before inserts in a patch.
- **A nested read** is N deletes plus N inserts plus the header line again: 13.6 kB for
  10 rows, the same as a stream reset. Focus in another row survives **[browser]**.
- **Layout.** `div`s with ARIA roles; each row is `display: grid` with its table's
  column template in a CSS variable on the grid root. Cells line up with their own
  table's header at every level; one variable resizes a column in every table of that
  kind; the top header is sticky and scrolls sideways with its columns **[browser]**,
  screenshots `browser/shots/flat-1-open.png`, `flat-2-resized-scrolled.png`.
  **What is lost:** the browser's automatic table layout. Today a column is as wide as
  its content needs (`freeze()` in the grid hook measures that). In a flat DOM every
  column needs an explicit width from the start, or JavaScript that measures. Subgrid
  cannot help: it needs one column set per container, and nested tables have others.
- **ARIA.** A treegrid assumes one column set, and ARIA forbids `aria-level`,
  `aria-expanded`, `aria-posinset` on a row of a `grid` (WAI-ARIA 1.2, `row`). To keep
  "a grid in a grid cell" in a flat DOM the nested grid must adopt its rows with
  `aria-owns`. Chromium builds the right tree and axe is content **[browser]**. But
  the specification says "Authors SHOULD NOT use aria-owns as a replacement for the DOM
  hierarchy", and VoiceOver could not reach aria-owned rows of a grid until WebKit bug
  306130 was fixed in February 2026. JAWS and NVDA with owned rows: **[unverified]**.
  Today's promise would rest on a weaker footing.
- **The grid hook.** About 75 statements in 25 functions use the table's structure
  (`table.rows`, `row.cells`, `cellIndex`, `closest("tbody")`, `tHead`): roughly
  400–600 lines, a quarter of the hook, plus the 15 `>tbody>tr>td` selectors in the
  template and the width code. A nested grid would have no element that contains its
  rows, so a hook per table has nothing to sit on. The hook could work from markers
  only; it does not today.
- It fits the owner's goal of a fully headless contract (bundles for every element,
  hooks that read markers and not tag names). That work would make mechanism 4
  cheaper later. It does not make it necessary: mechanism 1 keeps the DOM.

#### Mechanism 5: no streams

`lib/keyed_live.ex`: `%Table{rows: [%{…, open: %Table{} | nil}]}`, one recursive
function component, `:for={row <- @t.rows} :key={row.id}`.

- A change deep in the tree sends that subtree's changed values only **[test]**: one
  cell at level 3 is 606 bytes. A keyed comprehension moves unchanged entries: a sort
  that reorders the same rows is 0.9 kB.
- Everything is ordinary markup. `element/3` finds every nested row. No portal, no
  positions, no stream names.
- **Cost:** the rows are kept in assigns. Today the server keeps only the keys of the
  page and the records of failed edits (section 2.3). With pages of 25–100 rows that
  is 25–100 records per open table per session, or only the cell values if the core
  keeps a row as what its cells show. Size per record: **[unverified]**, not measured
  with Ash records.
- Every expression in a row that reads a table-level value is evaluated for all rows
  when that value changes. Only its result is sent, but it is work per row.

#### Option 6: a child LiveView

Works in a stream item and survives the row's re-insert **[test]**. It is another
process: the reader must be rebuilt from the session, `notify` crosses processes,
uploads and URL are separate. It answers "no live component" by the letter only. No.

### 10.4 Pickers, uploads, async, events, cleanup on one socket

All **[test]** in `test/portal_test.exs` unless marked.

| Topic | Finding |
| --- | --- |
| Picker | A table in a `<dialog>` at page level is one more registry entry with its own stream. `element/3` works on it (no portal). Opened from a nested table, the choice lands in the teleported table **[browser]** |
| Event routing | Every event names its table by id; the id is the registry key. An unknown id does nothing. The parent's key comes from the registry, never from the browser |
| Hooks | `pushEventTo(this.el, …)` reaches the LiveView from teleported content. The 20 pushes need the table's id in the name or payload (one helper); nothing else in the hooks depends on components (no hook reads `phx-target` or `data-phx-component`) |
| Async | Key `{:nt, id, :read}`. Closing calls `cancel_async`; a read for a table that is gone never arrives |
| Uploads | One name per table: `"file:" <> id`. On close: `cancel_upload` for every entry, then `disallow_upload`. `disallow_upload` raises while entries are active (found the hard way). The name stays in `@uploads`, disallowed |
| Cleanup | One function drops a table and everything under it by id prefix: async, upload, stream reset, registry entry, stream name back to the pool. Called when a line closes, a row is removed, a table reads again |
| Selection | The hook's, per grid root. The DOM is unchanged, so nothing changes |

### 10.5 Diff sizes

JSON bytes of the diffs, toy markup: 50 rows at the top, 10 rows per nested table,
8 columns, a header with a filter row. `mix test` prints them.

| Action | 1 Portal + streams | 5 No streams | 2 Nested stream + re-insert | 3 Plain re-insert | 4 Flat stream |
| --- | --- | --- | --- | --- | --- |
| Save one cell, top | 1,645 | 468 | 1,461 | 1,421 | 1,244 |
| Expand a row | 22,809 | 20,904 | 20,395 | 21,174 | 13,788 |
| Save one cell, nested | 1,918 | 514 | 8,751 | 21,162 | 1,356 |
| Nested table reads again (10 new rows) | 15,013 | 13,686 | 20,422 | 21,176 | 13,644 |
| Expand at level 3 | 27,461 | 24,208 | 35,615 | 63,457 | 17,340 |
| Save one cell, level 3 | 2,558 | 606 | 21,635 | 63,445 | 1,580 |
| Level 3 reads again | 18,683 | — | 35,642 | 63,459 | 17,290 |
| Host's own assign | 9 | 9 | — | — | — |
| Close the level-1 table | 27 | 48 | — | — | 1,501 |
| Page change, top | 64,948 | 60,493 | — | — | — |

Reading it: a stream sends a whole row for one cell; without streams only the cell's
values go. Mechanisms 2 and 3 pay for every table above the change. The flat column is
smaller on "expand" because its nested header has no filter row; otherwise it is the
portal's size. A nested live component was not measured; it should equal the portal
column, since both are a stream of their own with tracked markup around it.
**[unverified]**

### 10.6 Is this state of the art, and is it Ash's way?

- **Flat registry, nested UI** is the standard elsewhere. AG Grid master/detail: "The
  Detail Grid is a fully fledged independent grid instance", registered by id
  (`getDetailGridInfo`, ids `detail_<row id>`). Redux: "Normalizing State Shape". React
  Stately: a flat `keyMap` with parent keys. TanStack: `rowsById` and `flatRows`, but
  its sub-rows share the parent's columns; a sub-table is "custom UI".
- **Ash's own precedent is a tree addressed by path.** `AshPhoenix.Form` keeps nested
  forms in `forms` on each form and addresses them by path: `[:comments, 0]` or
  `"form[comments][0]"` (`form.ex:228`, `get_form/2` at `:2877`, `add_form/3` at
  `:3805`).
- **The difference does not reach the developer.** They hold `@tasks` and see paths in
  events. Recommended: keep the registry flat inside the struct, because streams, async
  keys and uploads are flat on the socket anyway and the portals are siblings; address
  a nested table in the public API by a path, as `AshPhoenix.Form` does:
  `[{row_key, :comments}, …]`.
- **Portal for this** has no precedent we found. LiveView's documentation presents
  portals for dialogs and menus. That is the honest weak point of mechanism 1.

### 10.7 Recommendation

**Mechanism 1: flat registry on the host socket, one stream per table, nested tables
teleported into their parent's row.** It is the owner's design, and it works.

What it gives: no live component anywhere; the DOM, the look, the ARIA structure and
the keyboard stay as they are; diffs as with live components; the server still keeps
no records.

What it costs against keeping live components for nested tables:

1. **Tests.** A helper (`AshTable.Test`, public, about 100 lines) that reads a nested
   table from the portal's HTML and sends its events by name. The demo's helpers
   (`DemoWeb.TablePage`) go through it for nested ids. Developers who test nested
   tables on their own pages need it too. The ~780 browser tests need no change.
2. **Risk.** A young LiveView feature in a combination upstream does not test. Add
   three or four browser tests of the combination itself (the checks of
   `browser/portal.mjs`) so an upgrade that breaks it fails loudly.
3. **Discipline.** One cleanup function; a portal must never outlive its target row.
4. **Hooks.** 10–30 lines: the table's id in every push. To check in the browser when
   built: `beforeUpdate` and the editor's `phx-update="ignore"` under a portal.
5. The host passes the streams: `<AshTable.attached table={@tasks} streams={@streams} />`.

**If the portal ever proves fragile, fall back to mechanism 5 (no streams).** It needs
no client mechanism at all and tests see everything. Its price is rows in memory. The
registry, the paths, the events and the cleanup are the same for both, so the choice
stays inside the rendering layer and the place where rows are kept.

Neither is clearly better on every count. The portal keeps streams and memory as
today; no streams is simpler and more robust. The owner asked for the first, it is
proven, so it goes first.

**Not recommended:** 2 and 3 (they pay per ancestor), 6 (a process per table), and 4
for now. Mechanism 4 is the best on the wire with streams and visible to tests, but it
rewrites markup, layout and a quarter of the hook, gives up automatic column widths,
and moves the accessibility promise onto `aria-owns`. Revisit it only together with
the fully headless contract, and only if `aria-owns` on grid rows is verified in JAWS,
NVDA and VoiceOver.

**Unavoidable remainder:** none that is a live component. What remains is the test
helper, the pass-through of `@streams`, and one rule for the host: do not put
`<AshTable.attached>` inside a stream item of the host's own.

### 10.8 Decisions for the owner

| # | Decision | Recommended | Why |
| --- | --- | --- | --- |
| 17 | Nested tables and pickers without live components? | Yes, by portal (mechanism 1) | Proven in the browser; DOM, look and ARIA unchanged; streams kept |
| 18 | Accept that `element/3` cannot reach into a nested table? | Yes, with a public test helper | It is a documented LiveView limit; events and markup are still testable |
| 19 | Fallback if the portal breaks in a later LiveView | Mechanism 5, no streams | Same core, no client mechanism, at the price of rows in memory |
| 20 | Shape of the state | Flat registry inside `%AshTable.Table{}`, paths in the public API | Streams, async and uploads are flat on the socket; `AshPhoenix.Form` addresses by path |
| 21 | Do mounted and embedded tables use the portal too? | Yes, one way of nesting | Two ways double the code and the tests. The live component then only wraps the top-level table |
| 22 | Stream names | A pool, reused | Names from row keys never leave the socket |
| 23 | Event names | `ash_table:TABLE_ID:event`, the id being the registry key | One lookup guards every event; the hook already knows its id |
| 24 | Flat DOM (mechanism 4)? | Not now | Costs layout, hook and the footing of the accessibility promise for no gain over the portal |
| 25 | Kit: bundles for rows and cells too, hooks on markers only (the owner's new goal)? | Yes, as the goal; after `attach` | Independent of the nesting mechanism. It removes the tag selectors that make any later DOM change expensive |

### 10.9 Experiment files

Under `/tmp/claude-1000/-home-stefan-roesch-doloops-ash-table/5c7207f9-c9ac-4f1f-a341-9d59f2b21019/scratchpad/headless-research/exp/`:

| File | What |
| --- | --- |
| `lib/portal_live.ex` | Mechanism 1, with picker, uploads, async, cleanup |
| `lib/keyed_live.ex` | Mechanism 5 (`Exp.Tree`, `Exp.KeyedLive`) and mechanism 3 (`Exp.ReinsertPlainLive`) |
| `lib/reinsert_stream_live.ex` | Mechanism 2, and option 6 (`Exp.ChildLive`, `Exp.LRHostLive`) |
| `lib/flat_live.ex` | Mechanism 4 |
| `lib/nt_parts.ex` | Shared toy markup, layout, static files |
| `test/portal_test.exs`, `test/others_test.exs`, `test/support.exs` | The tests and the diff measurement. `mix test` |
| `browser/portal.mjs`, `browser/others.mjs`, `browser/perf.mjs` | Playwright scripts. `browser/restart.sh`, then `browser/run.sh portal` |
| `browser/shots/` | Screenshots of the flat layout |

Not tested: Ash records, the real grid hook under a portal, Firefox and Safari, screen
readers, `handle_params` with nested tables (their state is never in the URL).

---

## 11. Before an action runs: values from the page, and a veto

Added 2026-10-12, on the owner's new requirement. Same marks as above. `ASH/` is
`ash_table/deps/ash/`, `AP/` is `ash_table/deps/ash_phoenix/lib/ash_phoenix/form/form.ex`,
`REF/` is `ash_reference/`. **[experiment]** here means the script of 11.9.

### 11.1 Summary

Two things, and they are different in kind. So they get different tools.

**(a) Values only the page knows are data, not a callback.** Ash already has two
channels for "server code gives the action something": **private arguments** (declared
and typed on the action, `public?: false`) and **context** (a free map). The table
takes both as options: `private_arguments` and `context`. Each is a map, or a function
of the page's assigns. That is the vocabulary the table already has for
`ask :currency, default: &fun/1`. The table hands them to every action it builds:
cell saves, row actions, create, bulk, generic actions, and reads.

**(b) The veto is one function, asked before every write.** `before_action` gets a
short description of what is about to run and the page's assigns. It answers `:cont`
or `{:halt, message}`. Nothing else. It cannot change the action, its inputs, the
actor, or the checks. A halted write is shown where a refused save is shown today.

**What stays on the resource:** validate, change data, forbid. The function never
sees the typed value or the record, so it cannot become a validator.

**Recommended shape:**

```elixir
AshTable.attach(socket, :tasks, MyApp.Tracker.Task,
  scope: socket.assigns.current_scope,
  private_arguments: fn assigns -> %{project_id: assigns.project.id} end,
  before_action: &__MODULE__.before_task_action/2
)
```

No new command is needed. A function of the assigns cannot go stale.

**Proven in a script:** a private argument and a context value given by server code
reach an update action, a destroy, a generic action, a bulk update, a bulk destroy and
an `AshPhoenix.Form` (open, validate, submit). A caller's params cannot set the private
argument in any of them.

### 11.2 How a caller hands values to an action in Ash

**Two documented channels.** The actions guide has a heading "Private Inputs" with
exactly these two options **[docs]** (`ASH/documentation/topics/actions/actions.md:350-390`,
<https://hexdocs.pm/ash/actions.html#private-inputs>):

> it can be used by actions that require something provided by the "system" […] For
> example, you may want an `ip_address` input that can't be set by the user.

| | Private argument | Context |
| --- | --- | --- |
| Declared on the action | Yes: `argument :project_id, :uuid, public?: false` | No. A free map |
| Typed, cast, `allow_nil?` checked | Yes | No |
| Read in the action as | `changeset.arguments.project_id`, `arg(:project_id)` in expressions | `changeset.context.key`; in a change's third argument as `context.source_context.key` |
| Reaches nested actions | No | Only what is under `:shared` |
| A name the action does not know | Ignored | Carried, unread |
| Best for | A value **this action needs** to do its work | Facts about **the request** that any action may or may not look at |

**Private arguments** **[code]** **[experiment]**

- An argument is public unless it says `public?: false`. A private one can be set only
  by `set_argument` or the `private_arguments` option
  (`ASH/documentation/topics/security/sensitive-data.md:16-21`).
- `Ash.Changeset.for_create/for_update/for_destroy` take `private_arguments: map`,
  "set before validations and changes" (`ASH/lib/ash/changeset/changeset.ex:2009-2013`,
  applied at `:840`, `:2372`, `:3048`).
- `Ash.ActionInput.for_action` takes it too (`ASH/lib/ash/action_input.ex:188-192`,
  applied at `:261`).
- `Ash.bulk_update/bulk_destroy/bulk_create` take `private_arguments:` and `context:`
  ("on each changeset", `ASH/lib/ash.ex:435-443`; applied in
  `ASH/lib/ash/actions/update/bulk.ex:1832`, `destroy/bulk.ex:1374`, `create/bulk.ex:501`).
- `Ash.run_action/2` takes `context:` but **not** `private_arguments:`
  (`ASH/lib/ash.ex:901-956`). The experiment got "unknown options
  [:private_arguments]". They go on the input, in `for_action`.
- **Reads have no `private_arguments` option.** `Ash.Query.for_read(…, private_arguments: …)`
  is silently ignored: no error, no argument **[experiment]**. The way is
  `Ash.Query.set_argument/3` before `for_read`
  (`ASH/lib/ash/query/query.ex:2971`; the sensitive-data guide names it). It worked in
  the experiment: the preparation saw the argument and filtered by it.
- **A caller's params cannot set a private argument.** `for_update`, `for_action` and
  `for_read` answer `Ash.Error.Invalid.NoSuchInput` for a param with a private
  argument's name (`query.ex:1112` checks `public?`). With `private_arguments` given
  as well, the server's value stands and the param is still an error
  **[experiment]**.
- A **public** argument named in `private_arguments` is an error: "can't set public
  arguments using the private_arguments option" (`changeset.ex:6739-6750`)
  **[experiment]**. A name the action does not have is ignored **[experiment]**.
- `Ash.Changeset.set_private_argument/3` needs the action to be known. Called on a
  fresh `Ash.Changeset.new/1` it raises `BadMapError` **[experiment]**
  (`changeset.ex:6757` reads `changeset.action.arguments`). So it cannot be used in
  AshPhoenix's `prepare_source`. Use the option.

**Context** **[code]** **[docs]**

- `context: map` on every `for_*`, on `Ash.create/update/destroy/read/run_action`, and
  on the bulk calls. `set_context/2` on changeset, query and action input
  (`changeset.ex:5652`, `query.ex:2832`, `action_input.ex:796`). Always deep-merged.
- `:private` is Ash's. `:shared` is passed on to nested actions and is also written
  to the top level (`actions.md:111-124`, `changeset.ex:5660`). The guide warns:
  nothing big under `:shared`.
- An `Ash.Scope` carries context too: `get_context/1`, deep-merged with a `context:`
  option (`ASH/lib/ash/scope.ex:49`, `:139`). In the experiment a `context:` option
  won over the same key from the scope, and the scope's `:shared` was kept.
- The guide's own wording: context "is occasionally used by callers to provide
  additional information that the action may or may not use" (`actions.md:373-374`).

**Public arguments set by the caller, not the person.** `set_argument/3`, or simply a
key in the params. The table already does this for `record_argument`: the row's key
is merged over the params, and "nothing from the browser replaces" it
(`ash_table/lib/ash_table/act.ex:185-191`, `:618-628`).

**`AshPhoenix.Form`** **[code]** **[experiment]**

| Option | What the docs say it is for | When it runs |
| --- | --- | --- |
| `private_arguments:`, `context:` | Not options of the form. Unknown options are "passed to the underlying call" to `for_create/for_update/for_destroy/for_action/for_read` (`AP:494-502`, `:785`) | At open, again on every `validate`, again on `submit`: the form rebuilds its source with the same options each time (`AP:1440-1500`, `:2233-2300`) |
| `prepare_source` | "receives the initial changeset (or query)"; set argument defaults, "set changeset context", other pre-processing (`AP:320-330`) | Before `for_*`, at open, validate and submit. The action is not known yet |
| `prepare_params` | Receives the params and `:validate`; "called before the form is validated" (`AP:331-337`) | Validate only |
| `transform_params` | "post-processing the form parameters before they are used for changeset validation/submission" (`AP:338-344`) | Validate and submit |
| `params` | Initial params, for default values (`AP:363-369`) | Open |
| `before_submit` (of `submit/2`) | A function on the changeset just before the action is called (`AP:2141`, `:2227`) | Submit only |

Seen in the experiment:

- `private_arguments:` and `context:` given to `AshPhoenix.Form.for_update`, `for_destroy`
  and `for_action` are on the source after open, after `validate`, and reach the action
  on `submit`.
- Submitting `%{"project_id" => "EVIL"}` to a form whose `project_id` is private: the
  record got the server's value. Without a server value the action failed with
  "required". The param never set it.
- A public argument set in `prepare_source` **loses** to the same key in the params.
  One set in `transform_params` wins, on validate and on submit. The table's own merge
  in `Act.taken/3` is the third way, and the one it has.

**What the table does today:** nothing. It passes scope, or actor and tenant, and
`authorize?` (`ash_table/lib/ash_table/query.ex:527-538`). The only context that
reaches an action is what the scope's `get_context/1` returns.

### 11.3 What the API extensions let the host set

| Extension | Per request, the host sets | How | A hook that can cancel? |
| --- | --- | --- | --- |
| ash_graphql | actor, tenant, **context** | `Ash.PlugHelpers.set_context(conn, map)` in a plug; `AshGraphql.Plug` copies it (`REF/ash_graphql/lib/plug.ex:20-23`); every resolver does `set_context` on its query, changeset or input (`lib/graphql/resolver.ex:64`, `:235`, `:1648`) | No. `modify_resolution` is an MFA called **after** the action, with the result (`lib/resource/mutation.ex:72-77`, `resolver.ex:171`) |
| ash_json_api | actor, tenant, **context** | The same conn helpers (`REF/ash_json_api/lib/ash_json_api/request.ex:103`; `controllers/helpers.ex:67`, `:96`, `:342`) | No. `modify_conn` runs "before responding", after the action (`lib/ash_json_api/resource/resource.ex:34-38`) |
| ash_typescript | actor, tenant, **context** | From the conn, or `socket.assigns[:ash_context]` on a channel (`REF/ash_typescript/lib/ash_typescript/rpc/pipeline.ex:75-84`) | No |
| ash_admin | Nothing from the host. It sets `context: %{ash_admin?: true}` itself (`REF/ash_admin/lib/ash_admin/components/resource/form.ex:2824`) | | No |

What this says:

- **Context is the one channel every extension gives the host.** The same map goes to
  every action of the request, whatever the action is.
- **None of them sets private arguments.** `grep private_arguments` finds nothing in
  the four clones. A client of an API has no server code beside it. A LiveView page
  does. This is where a table differs, and `AshPhoenix.Form` (also LiveView) passes
  them through.
- **None has a before-hook that can stop an action.** To stop one, their users write a
  plug, which runs before the extension is reached. So a veto is not an Ash-extension
  idea. It is a page idea: the plug of a page is its own code.
- ash_graphql's `hide_inputs` leaves an input out of the schema
  (`mutation.ex:63-66`). It is the precedent for "this input is not asked of the
  client", declared statically, by the interface.

### 11.4 Elsewhere, briefly

**[unverified]**: from memory, not read again for this note.

| Library | Shape | Modify or veto |
| --- | --- | --- |
| MUI Data Grid | `isCellEditable(params)`: a synchronous question, asked before the editor opens. `processRowUpdate(newRow, oldRow)`: an async function; what it returns is the row, a throw rejects the edit and goes to `onProcessRowUpdateError` | Both, apart: one question, one writer |
| AG Grid | `editable` as a function per cell. `valueSetter` returns false for "not changed". `readOnlyEdit` with `onCellEditRequest`: the grid changes nothing, the application decides | Both; the fully controlled mode hands the write to the host |
| Handsontable | `beforeChange(changes, source)`: synchronous; return `false` to cancel all, or null an entry to drop one | Veto and edit of the change list |
| React Aria, headless "controlled" | The host owns the value; the component asks through `onChange` | The host writes |
| Phoenix LiveView | The form's `phx-submit` handler is the host's own code: it decides before it calls `AshPhoenix.Form.submit/2`. Lifecycle hooks answer `{:cont, socket}` or `{:halt, socket}` | The host's handler is the veto |

What transfers:

- **A veto is a synchronous function.** No library does it with an event.
- **The JavaScript grids let the host write the data.** That is because they have no
  server and no rules. The table has the resource. So only the veto transfers, not
  the writer. The owner's earlier decision stands.
- `:cont` and `:halt` are LiveView's own words for "go on" and "stop here".

### 11.5 The recommended design

**Three options. The same three in every mode.**

| Option | Value | Goes to |
| --- | --- | --- |
| `context` | A map, or a function of the assigns that returns one | Every action the table runs, reads included, as `context:` |
| `private_arguments` | A map, or a function of the assigns that returns one | Every action of the table's resource that **declares a private argument of that name**; reads included |
| `before_action` | A function of a request and the assigns | Asked before every write |

**The assigns** are what a default of `ask` already gets
(`ash_table/lib/ash_table/resource.ex:117-124`, `lib/ash_table.ex:145-148`):

| Mode | The assigns given to the functions |
| --- | --- |
| Attached | The host LiveView's `socket.assigns`, as they are when the action is built. Never stale |
| Embedded | The map passed as `assigns={…}` on the tag. LiveView tracks it, so it is as the page last rendered it |
| Mounted | The page's own assigns: `current_scope` and what `on_mount` hooks assigned |

The functions get assigns, not the socket. They answer a question. They cannot assign,
push or redirect.

**Attached**

```elixir
AshTable.attach(socket, :tasks, MyApp.Tracker.Task,
  scope: socket.assigns.current_scope,
  context: %{shared: %{source: :board}},
  private_arguments: fn assigns -> %{project_id: assigns.project.id} end,
  before_action: &__MODULE__.before_task_action/2
)
```

The functions are stored once, at attach. They run in the host's process with the
host's assigns. Nothing has to be pushed when the page changes.

**Embedded** (while it is a live component, and after)

```heex
<AshTable.table
  id="tasks"
  resource={MyApp.Tracker.Task}
  scope={@current_scope}
  private_arguments={%{project_id: @project.id}}
  assigns={%{notes_dirty?: @notes_form.source.changed?}}
  before_action={&MyAppWeb.BoardLive.before_task_action/2}
/>
```

- The values are plain maps built from assigns. LiveView sends them to the component
  when they change, and only then.
- `before_action` must be a **remote capture**, `&Module.function/2`. Two captures of
  the same function are equal, so it is never "changed" (`&String.upcase/1 ==
  &String.upcase/1` is `true`; its `Function.info(…, :type)` is `:external`, an
  anonymous function's is `:local`; checked). An expression without assigns is also
  evaluated once by HEEx **[docs]**. An anonymous function written in the template is
  a new value on every render: it would run the table's `update/2` each time, and the
  table reads its permissions again on changed attributes. The tag raises on a
  `:local` function, with this explanation.
- The function gets the `assigns` map of the tag. A live component cannot see the
  host's assigns. This is the rule `ask`'s defaults already follow.
- `Phoenix.LiveComponent`'s docs recommend a function passed as an assign for
  talking to the parent
  (`deps/phoenix_live_view/lib/phoenix_live_component.ex:414-440`,
  <https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html>). They show an
  anonymous function. For a component with a costly `update/2` the capture is the safe
  form.

**Mounted**

```elixir
ash_table "/tasks", MyApp.Tracker.Task,
  context: %{shared: %{source: :tasks_page}},
  before_action: {MyAppWeb.TablePages, :before_action}
```

- The router stores its options as route metadata
  (`ash_table/lib/ash_table/router.ex`, `__live_opts__/2`). So a map is a literal and
  a function is `{Module, :function}`, as `layout` is already written. Whether a
  capture can be stored there is **[unverified]**.
- A mounted page has no other component beside the table. Page state there is the
  session and what `on_mount` assigned. The options exist for completeness; the real
  use is attached and embedded.

**No commands.** `AshTable.put_context/3` and friends are not needed: a function of
the assigns, and a tracked attribute, are always current. A command would be a second
way to say the same thing, and the one that can be forgotten. (Decision 27.)

#### Case (a): what the table does with the values

- **Context:** merged into the options of every Ash call the table makes: the page
  read, counts, the re-read before a write, the forms, the bulk calls, the generic
  actions, nested tables and pickers. One page, one context, as one request has one
  in the API extensions. The host decides what goes under `:shared`.
- **Private arguments:** for each action, the table takes from the map the names that
  action declares as `public?: false` arguments. The rest is left out. This matters:
  Ash ignores an unknown name, but a name that is a **public** argument of another
  action is an error **[experiment]**. So the table filters; it does not pass the map
  whole.
  - create, update, destroy, generic: `private_arguments:` among the form's options
    (`Act.form/4`, `Act.open_generic/4`, `Act.open_create/4`, `Edit.submit/5`).
  - bulk update and destroy: `private_arguments:` among the bulk options
    (`ash_table/lib/ash_table/bulk.ex:219-236`).
  - reads: `Ash.Query.set_argument/3` before `for_read`, in the one place that builds
    the table's query, so that **the re-read before a write runs the same action with
    the same arguments as the page read** (`ash_table/lib/ash_table/record.ex:19-24`
    promises exactly this).
- **The resource declares what it accepts. The page supplies it.** A value for which
  the action declares nothing reaches nothing. A required private argument that the
  page does not supply fails the action with Ash's "is required". That is a
  developer's mistake: the table shows its general failure text and logs the name.
- **Evaluated when the action is built.** At panel open, on each validate, and again
  at submit (the table builds a fresh form at submit). A change of project between
  open and run is used at run.

**Public arguments from the page.** The owner allows that "some values come from the
UI". Three cases:

1. The value is always given by server code. Make the argument `public?: false`. This
   is Ash's own answer, and it is the recommended one. No interface can then set it.
2. The argument must stay public, because GraphQL or JSON:API clients give it, but in
   the table the page should give it. This needs a declaration, because **the panel
   must not show a field for it**, and the model that says which fields a panel has is
   built from the resource. Proposed, for a second step: in the `table` block,
   beside `record_argument` and `reference`:

   ```elixir
   action :move_to_project do
     page_argument :project_id
   end
   ```

   "The table never asks the person for this argument. The page gives it." The value
   then comes from an `arguments` option of the page, same shape as
   `private_arguments`. The table merges it over the params as it does for
   `record_argument`. Without a value from the page the argument is not set, and the
   action's own default or "is required" applies. This is ash_graphql's `hide_inputs`
   plus a value. (Decision 29.)
3. The page wants to prefill a field the person can still change. Not offered here.
   It is a default, and the place for defaults is the action.

What is ruled out: a silent rewrite of an input the person sees. The page cannot
replace what was typed.

#### Case (b): the veto

```elixir
@spec before_task_action(AshTable.Request.t(), map) :: :cont | {:halt, String.t()}
```

**The request** says what is about to run, and no more:

| Field | |
| --- | --- |
| `table` | The id given at attach or on the tag |
| `path` | `[]` for the table itself; `[{parent_key, relationship}, …]` for a nested table; the picker's place for a picker. As in the events of 5.3 |
| `resource` | The resource the action belongs to. For a nested table, the nested one |
| `action`, `type` | The action's name, and `:create`, `:update`, `:destroy` or `:action` |
| `from` | How the person started it: `:cell`, `:row_action`, `:table_action`, `:create`, `:bulk` |
| `column` | For a cell save, the column's name |
| `key` | For a write on one row: the primary key as a map, **as the browser named it**. A claim, not read yet |
| `selection` | For bulk: `{:rows, keys}` or `:all`, as claimed |

**Not in it:** the typed value, the panel's inputs, the record, the changeset, the
socket. A function that cannot see the value cannot validate it. A function that
cannot see the record cannot write a rule about data. Both belong on the resource.
The typed value may also be sensitive.

**Answers:** `:cont`, or `{:halt, message}`. The message is the host's own text, from
its own gettext. Anything else raises `ArgumentError`. There is no
`{:cont, changes}`: values go through the two options above.

**When it is asked:**

- Before every write, once: cell save, cell clear, reference cell, row action, table
  action, create, and a bulk run.
- **Bulk: once for the whole run, before the first record is read.** Not per record.
  A page state does not differ by record, and a half-run bulk is the worst outcome.
- Nested tables and pickers: the same function, with their `path` and `resource`. One
  page, one function. A write in a picker is the write of the reference cell of the
  table that opened it.
- **Not for reads.** A read cannot be halted. To show nothing, the host does not
  render the table. Reads get the context and the private arguments.
- Not when a panel opens, only when it is run. What the person typed stays in the
  panel, as after a refused submit. (An earlier ask at open is decision 31.)

**Order:**

1. The browser's confirm dialog. It is the browser's: the event is only sent after
   "yes" (`table_component.ex`, hook, `this.ask(…)`). Nothing can go before it without
   a round trip.
2. The table's own checks of the event: is this a column, an action, a row of this
   person's page. Unchanged. A forged event still gets no message.
3. **`before_action`.** Before the re-read: a halted write touches no data, and the
   function is not handed a record. It also means the key is still a claim.
4. The re-read as the person.
5. The action, built with context and private arguments.

For a bulk action whose confirm is asked by the server's reply (`bulk` then
`bulk_run`), the veto is asked at `bulk_run`.

**What the person sees.** A halt is shown as a refused save is shown today:

| From | Shown |
| --- | --- |
| Cell save | The reply the hook already knows, `%{ok: false, error: message}` (`table_component.ex:2069`): the editor stays open with the typed value, the message is at the cell |
| Panel (row action, table action, create) | The panel stays open with its inputs; the message is in the panel's error line (`role="alert"`) |
| Action without panel | Where the action's refusal is shown today |
| Bulk | The bulk line: nothing ran, and the message |

The message is announced through the table's status line (`role="status"`,
`table_component.ex:3718`) where the place itself is not an alert. No new place, no
new markup, no new hook reply.

**After-events.** A halted write sends none: the host halted it, and it knows. The
payloads of `:row_saved`, `:action_ran` and the others stay as in 5.3. They do not
repeat context or private arguments: the host gave them, and a private argument may be
`sensitive?`.

**Safety.**

- The three options are read from `attach`, the tag, or the router line. That is
  server code. No event and no URL parameter reaches them.
- `AshTable.put_state/3` speaks the URL's vocabulary. It can set the **public**
  arguments of the read action only. A private name in the URL should be dropped by
  the state (**[unverified]** for `State.from_params/2`); if it were not, Ash refuses it
  with `NoSuchInput` **[experiment]**.
- Private arguments are set by the options that only take private ones. A public
  argument in the map is filtered out by the table, and would be an Ash error if it
  were not.
- `before_action` can only remove writes. It cannot add one, and it cannot answer for
  the resource: after `:cont` every check runs as before.
- The functions run in the LiveView process, inside `handle_event`. A slow one blocks
  the page. A raise is the host's bug and crashes the LiveView, as a raise in its own
  `handle_event` would. (Decision 36.)

**Names.** `context` and `private_arguments` are Ash's own option names, with Ash's
meaning. `before_action` is the name of Ash's changeset hook, which also runs before
the action and can stop it; `:cont`/`:halt` are LiveView's hook answers.
(Alternatives in decision 30.)

### 11.6 The example: a board with a project switcher and notes

The page shows a project switcher, a notes form, and the Tasks table. "Move to
current project" is a row action and a bulk action. Edits are blocked while the notes
are unsaved.

**The resource** declares what it accepts:

```elixir
update :move_to_project do
  argument :project_id, :uuid, allow_nil?: false, public?: false
  change set_attribute(:project_id, arg(:project_id))
end
```

```elixir
table do
  action :move_to_project
end
```

The argument is private, so the action has no inputs. It runs when its button is
used. No panel.

**The page:**

```elixir
def mount(_params, _session, socket) do
  socket =
    socket
    |> assign(:project, first_project(socket.assigns.current_scope))
    |> assign(:notes_form, notes_form())
    |> AshTable.attach(:tasks, MyApp.Tracker.Task,
      scope: socket.assigns.current_scope,
      private_arguments: &__MODULE__.page_arguments/1,
      before_action: &__MODULE__.before_task_action/2
    )

  {:ok, socket}
end

def page_arguments(assigns), do: %{project_id: assigns.project.id}

def before_task_action(_request, %{notes_form: %{source: %{changed?: true}}}),
  do: {:halt, gettext("You have unsaved notes. Save them first.")}

def before_task_action(_request, _assigns), do: :cont

def handle_event("switch_project", %{"id" => id}, socket),
  do: {:noreply, assign(socket, :project, project(id, socket.assigns.current_scope))}
```

```heex
<.project_switcher project={@project} />
<.notes_form for={@notes_form} />
<AshTable.attached table={@tasks} streams={@streams} />
```

**What happens.**

- The person switches to project B. The host assigns `:project`. Nothing is told to
  the table.
- They use "Move to current project" on a row. The table checks the event, asks
  `before_task_action`: `:cont`. It reads the row again as the person. It builds the
  action with `private_arguments: %{project_id: B}`, because `:move_to_project`
  declares a private `project_id`. Ash casts it and runs the action. The row is shown
  from what the action returned. `{:ash_table, "tasks", {:action_ran, …}}` goes to the
  host if it asked.
- They select 40 rows and use the bulk button. One ask, then 40 records, each with
  the same private argument.
- They type into the notes, then edit a task's title and press Enter. The table asks
  `before_task_action`: `{:halt, "You have unsaved notes. Save them first."}`. Nothing
  is read, nothing is written. The editor stays open with what they typed, the
  message is at the cell and is announced. They save the notes and press Enter again.
  The title is saved.
- Somebody sends `{"project_id": "…"}` in a forged event. The action has no public
  input of that name. The table's `taken/3` takes declared inputs only, and Ash would
  refuse the name.

To block only some writes, match on the request:

```elixir
def before_task_action(%{type: :destroy}, %{uploading?: true}),
  do: {:halt, gettext("Wait for the upload to finish.")}

# master-detail: the row that is open in the form beside the table
def before_task_action(%{key: %{id: id}}, %{detail: %{id: id, dirty?: true}}),
  do: {:halt, gettext("This task is open in the form. Save or discard it there first.")}
```

### 11.7 What the developer can and cannot do

| Can | Cannot |
| --- | --- |
| Give any action a typed value it declares as a private argument | Set an input the person sees |
| Give every action a context map, and choose what is `:shared` | Change actor, tenant or `authorize?` this way |
| Give reads the same values, e.g. a private argument the read action filters by | Halt a read |
| Halt any write with a message, by action, type, column, row key or table | See or change the typed value, the record or the changeset |
| Halt a bulk run as a whole | Halt some records of a bulk run and not others |
| See writes of nested tables and pickers, by `path` | Skip the re-read, the policies, or the action's validations |
| | Run something else in the action's place, or change its result |

If a rule needs the record or the value, it is a business rule. It goes on the
resource, as a validation or a policy, and it may read the page's facts from the
**context** the page gives. That is the bridge: the page states a fact
(`context: %{board: %{locked?: true}}`), the resource decides what it means.

### 11.8 Tests the feature needs

Root (ETS resources):

1. A private argument reaches: cell save, reference cell, row update, row destroy,
   create, generic row action, table action, bulk update, bulk destroy, bulk generic.
2. Context reaches the same ten, and the page read, the count, the re-read, a nested
   table's read and a picker's read.
3. A read action with a private argument that filters: the page shows the filtered
   rows, **and a cell save on one of them finds its record** (re-read with the same
   argument).
4. A map with a name that is a public argument of another action: that action still
   runs, and the person's own input for it is used.
5. A required private argument the page does not give: the action fails, the general
   text is shown, the name is logged.
6. A function option is called with the assigns of the mode; a changed assign is used
   by the next action without any command (attached), and after a re-render
   (embedded).
7. `before_action` halts each of the ten writes: nothing is written, **no read is
   made** (count the data layer's calls), the message is shown in the right place,
   the typed value is still in the editor or panel, no after-event is sent.
8. Bulk: asked once; on halt, zero records touched.
9. A nested table's write and a picker's choice arrive with `path` and `resource`.
10. A read never calls `before_action`.
11. A forged event for a column or action the person does not have never calls it.
12. A bad answer raises `ArgumentError`. The tag raises on a `:local` function.
13. An event payload or URL parameter named like a private argument or `context`
    changes nothing.

Browser: a halted cell save keeps the editor and focus, and the status line announces
the message; a halted panel keeps its inputs; confirm comes before the halt message.

### 11.9 The experiment

`/tmp/claude-1000/-home-stefan-roesch-doloops-ash-table/5c7207f9-c9ac-4f1f-a341-9d59f2b21019/scratchpad/before-hook-research/exp.exs`
(`elixir exp.exs`; output in `output.txt`). `Mix.install` with ash 3.34.4 and
ash_phoenix 2.3.25, one ETS resource. No LiveView in it: the three options are plain
data and plain functions, and section 7 already covers the socket side.

| Question | Result |
| --- | --- |
| `for_update(private_arguments:, context:)` | Both reach the change: argument, `changeset.context`, and `context.source_context` |
| `Ash.update(record, %{}, action:, private_arguments:, context:)` | Same |
| Params with the private argument's name | `NoSuchInput`. With `private_arguments` too: the server's value, and still the error |
| A public argument in `private_arguments` | Error: "can't set public arguments using the private_arguments option" |
| An unknown name in `private_arguments` | Ignored, valid |
| `set_private_argument` before `for_update` | Raises `BadMapError` |
| Generic action: `ActionInput.for_action(private_arguments:, context:)` | Both reach `run` |
| `Ash.run_action(input, private_arguments:)` | "unknown options". `context:` is accepted |
| `Ash.bulk_update` and `bulk_destroy`, `strategy: :stream`, `batch_size: 1`, the table's options | Both reach every record's changeset |
| Bulk with the private name as input | `Ash.Error.Invalid` per record |
| Bulk without the required private argument | "argument project_id is required", per record |
| `AshPhoenix.Form.for_update/for_destroy/for_action` with both options | On the source at open and after validate; reach the action on submit |
| Form submit with the private name in the params | Server's value kept; without a server value, "required" |
| `for_create` with a private argument the action does not have | Ignored |
| `prepare_source` sets context | Applied on validate and submit |
| Public argument: `prepare_source` against params | Params win |
| Public argument: `transform_params` against params | The function wins, on validate and submit |
| Read: `for_read(context:)`, `Ash.read(context:)` | The preparation sees it |
| Read: `Ash.Query.set_argument` of a private argument, then `for_read` | Works, filter applied |
| Read: `for_read(private_arguments:)` | Silently ignored |
| Scope with `get_context` plus `context:` | Deep-merged; the option wins on the same key; the scope's `:shared` stays |

Not tested: policies that read the context; `:shared` reaching a nested action;
atomic bulk strategies (the table uses `:stream`); a capture in route metadata.

### 11.10 Decisions for the owner

| # | Decision | Recommended | Why |
| --- | --- | --- | --- |
| 26 | How does the page give values? | Two options, `context` and `private_arguments`: a map, or a function of the assigns | Ash's two documented channels, by their own names. The resource declares, the page supplies. Same vocabulary as `ask … default:` |
| 27 | Commands such as `AshTable.put_context/3`? | No | A function of the assigns and a tracked attribute cannot go stale. A command can be forgotten, and then a wrong value is written without any sign |
| 28 | Do reads get the values too? | Yes, both, and the re-read exactly as the page read | Otherwise a row that the read showed is "not there" at save time. Context to reads is what every API extension does |
| 29 | Public arguments from the page? | Not in the first step. First answer: make the argument private. If wanted later: `page_argument` in the `action` of the table block, value from an `arguments` option | The panel must know statically which fields it does not ask for. A silent rewrite of a visible input is ruled out |
| 30 | Name and shape of the veto | `before_action: fun(request, assigns) :: :cont \| {:halt, message}` | Synchronous, as in every grid library. Names from Ash and LiveView. Other names: `guard`, `before_write` |
| 31 | Ask the veto when a panel opens too? | No, only at run | One rule. Nothing the person typed is lost. Can be added later as `phase: :open` without breaking |
| 32 | Veto before or after the re-read? | Before | A halted write touches no data; the function gets no record, which keeps data rules on the resource. Price: `key` is a claim |
| 33 | Bulk: one ask or one per record? | One, before the run | Page state does not differ by record; no half-run bulk |
| 34 | What does the request carry? | Table, path, resource, action, type, from, column, key, selection. No value, no inputs, no record | What a page needs to decide. What it lacks is what a business rule would need |
| 35 | Nested tables and pickers | Context goes to all of them. `before_action` sees all, with `path`. `private_arguments` go to the top table's resource only, in the first step | One page, one context. A private argument is matched by name, and a nested resource may use the same name for something else |
| 36 | A raise or a slow function | Not caught, not timed | It is the host's code in the host's process, like its own `handle_event` |
| 37 | Function on the tag | Remote capture only; raise on an anonymous function | A new function every render would run `update/2`, and the permission reads, on every render |
| 38 | A declarative "read-only" state in addition (`read_only={message}`: editors do not open, buttons disabled, `aria-readonly`)? | Later, if asked for | Better up-front feedback for a whole-table lock, as MUI's `isCellEditable`. But it is a second mechanism, and the veto is still needed behind it |
