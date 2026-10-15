# Stage 5: design note (nested tables and pickers without live components)


> **Decided by the owner, 2026-10-15:** all recommendations D1–D9 accepted, incl. D5 (a new test group K: the nested-upload part of `label_import_test.exs:280` moves into a browser test; the demo test keeps the part up to the panel) and D8 (the measurable stability rule; two fixing attempts, then the fallback, and the owner is told). Also from the stage 3c drift check: the actor-change race (`nested_create_test.exs:127`) is fixed in this stage — when who is asking changes, what is open below closes first; and the changed expected value in `argument_line_test.exs:170–171` is kept as an agreed change.

Status: **for the owner to decide.** Nothing of it is built. Code references are of `9f1031f` (the end of stage 3c). Names follow [target.md](target.md); words follow `CONTEXT.md`. The decisions are in section 8.

Stage 5 runs before stage 4 (RQ2). It is the riskiest stage: the mechanism that shows a nested table changes. The research proved it in a toy (`ash_reference/headless-table-architecture.md` §10, files under `…/scratchpad/headless-research/exp/`: `lib/portal_live.ex`, `test/portal_test.exs`, `browser/portal.mjs`). This note says how it fits the real code.

## 1. What stage 5 changes, and what it does not

**Changes.** Today every nested table and every picker's table is a live component of its own (`Parts.Related.lines`, `parts/related.ex:128-146`; `Parts.Picker.picker`, `parts/picker.ex:53-71`). The tables of a page know of each other through the process dictionary (`@tables`, `live/core.ex:41`, written in `tidy/1`, `:464-503`) and wake each other with `send_update(cid, live: :released)` (`:496-500`). After stage 5:

- One live component per top-level table (today's `Live.TableComponent`, the wiring) holds one `AshDataTable.Table` with a flat registry of every table it shows: itself, its open nested tables at every depth, and the tables of open pickers.
- Each registry entry has its own stream, async keys, upload names and listener.
- Each open nested table is drawn at the top level of the component's template and moved into its parent's row by `<.portal>`. A picker's table needs no portal (2.6).
- `@tables`, `live: :released`, the nested `live_component` calls and the picker's `live_component` are gone (V14).

**Stays the same.** No new ability. Every event, payload, reply and `push_event` means what it means today. Behaviour, look and keyboard are identical. The DOM in the browser is today's, with one more element: the portal's wrapper (`div#_lv_portal_wrap_…`, `display: contents`) between a nested table's cell and what the cell held. One timing changes, as target §6a says: when who is asking changes, the nested tables close at once, not when the top table's new read comes back.

**Markup snapshots.** LiveViewTest renders a portal as `<template id=… data-phx-portal=TARGET><div id="_lv_portal_wrap_…">…</div></template>` where the portal stands (`deps/phoenix_live_view/lib/phoenix_component.ex:3601-3615`). The normaliser (`demo/test/demo_web/markup_snapshot_test.exs:141-172`) learns three rules, in this order:

1. Move the content of each `template[data-phx-portal]` to the end of its target, as the browser does (the read seam does this already, `demo/test/support/table_page.ex:1291-1356`).
2. Drop the emptied templates.
3. Unwrap `_lv_portal_wrap_*`: put its children in its place.

Then snapshots 03 and 04 (nested tables) are the markup of today. Snapshot 05 (picker) has no portal. One class string of every grid changes on purpose (2.5, decision D4).

## 2. The shape

### 2.1 The value

```elixir
%AshDataTable.Table{
  options: %{url, heading, mounted?, page_assigns},  # what the top table was told
  caller:  %Caller{scope, actor, tenant, authorize?, time_zone},  # authorize?: as told, nil = untold
  entry:   %Entry{},             # the top table; inside within/3 the one being worked on
  entries: %{id => %Entry{}},    # every other open table: nested tables and pickers' tables
  pool:    %{free: [name], next: n}  # stream names
}
```

The registry is keyed by the table's id (`task-row-KEY-t-comments`, `task-pick-assignee`). Events carry that id (stage 3c), so it is the lookup key. Each entry holds its `path` (today's `lineage ++ [id]`, `Table` options `:31-34`); `path` decides what lies under what. The id is never parsed for structure.

New fields of `Live.Entry`, from the stage-2 drift notes (target §9 stage 2):

| Field | Today | Why per entry |
| --- | --- | --- |
| `path` | `options.lineage` (+ own id) | the entry's place; reconcile and "held" walk it |
| `authorize?` (resolved), `authorize_given` | `caller.authorize?`, `options.authorize_given` | a nested table of another domain authorizes as its domain says; `Caller` keeps only what the top was told |
| `label`, `labelledby`, `select`, `live_given` | `options` | each table is told its own |
| `stream` | the fixed name `:rows` (`core.ex:46-48`) | its stream name from the pool |
| `uploads` | none (every upload of a component was its own) | the upload names it allowed, to release on close |
| `target` | none | the id of the parent's cell the portal goes into |
| `given` | none | what its parent last told it, to tell it again only on a change |

`Core.reader/1` (`core.ex:445-452`) then builds the reader options from `caller` with the entry's own `authorize?`. `Caller.reader_opts/1` keeps its signature.

### 2.2 Names by id

| Thing | Today | Stage 5 |
| --- | --- | --- |
| Stream | `:rows` per component | a name from the pool, `stream_configure`d once when first made (D3) |
| Async keys | `:read`, `:summary`, `:bulk` per component | `{:ash_data_table, id, :read \| :summary \| :bulk}` |
| Uploads | `id <> "-file-" <> arg` (`files.ex:216`) | the same; the entry lists them |
| Listener relay | `send_update(view, myself, live: {:heard, batch})` (`updates.ex:52`) | `send_update(view, myself, live: {:heard, id, batch})` |
| Events | `ash_data_table:ID:event`, checked against the component's own id (`core.ex:85-94`) | the same names; the id is looked up in the registry |

### 2.3 How the core runs per entry

The `Live.Core.*` modules read `socket.assigns.table.entry` and write with `Core.put/2` everywhere. They stay as they are. `Live.Registry.within(socket, id, fun)` checks the entry `id` out into `table.entry`, runs `fun`, puts it back into `entries`, and checks the top entry in again. Outside `within/3` `table.entry` is always the top table's, so the wiring's `gone?` check (`table_component.ex:545-553`) keeps working (D6).

| Callback | Today, per component | Stage 5, in the one component |
| --- | --- | --- |
| `update/2` | `told/2` with the component's attrs (`core.ex:149-256`) | the top: as today. `{:heard, id, batch}`: `within(id)`, add to `waiting`. A nested entry is told when it opens, and told again, parents first, when what its parent passes changes (`given`) |
| `handle_event/3` | `addressed/2` says whether it is this table's | `addressed/2` gives the id; `within(id, &topic(intent).on(intent, &1))`. An unknown id gets the `malformed/2` answer, as an event for another table does today |
| `handle_async/3` | by name | by `{:ash_data_table, id, name}`; `within(id)`. An unknown id (closed) is dropped |
| `tidy/1` | per component: close, follow, close, summarise, note in `@tables` | once per callback, over the whole registry (section 3) |

What a nested table is given stays `Nesting.nested_reader/1` (`nesting.ex:255-270`) and `picker_reader/1` (`:231-242`), now read from the parent entry when the child opens. The parent's key comes from the parent's `rows`, never from the browser (R §10.4).

### 2.4 Opening

Reconcile works both ways: what the registry should hold is what the tables render. `Nesting.on({:toggle, …})` (`nesting.ex:214-226`) and the picker clauses (`live/core/picker.ex:84, 127, 143`) only change `open` or `picker`, as today. `tidy/1` then opens the missing entries: for an open line, the relationship from the parent's model and the row's primary key from its `rows`; for a picker, its `choose`, `select` and label from `picker`. Opening takes a stream name, configures it if new, resets it, runs `told/2` within the new entry (which starts its read and its listener). A nested read is async, as today. A picker's first read runs in place, as today (one frame).

### 2.5 Where the portal goes

The target is the nested table's cell that `Parts.Related.lines` already renders in the parent's detail item: `ID-row-KEY-n-NAME-c` (`related.ex:108-118`). The cell is now empty in the server's markup. The portal, rendered by the wiring at the top level of its template:

```heex
<.portal :for={e <- Registry.portals(@table)} :key={e.id}
         id={"#{e.id}-portal"} target={"[id='#{e.target}']"} class="contents">
  <div class="sticky left-0 w-0" data-pin>
    <div class="w-[var(--ash-data-table-view)]">
      <.body entry={e} … />   <%!-- today's render/1 body, as a function component of the wiring --%>
    </div>
  </div>
</.portal>
```

- **The wrapper carries no layout.** New Phoenix apps make every teleported element `display: contents` (`[data-phx-session], [data-phx-teleported-src] { display: contents }`, in the demo `demo/assets/css/app.css:107`; LiveView sets `data-phx-teleported-src` on the wrapper). Such a rule is unlayered and beats a utility class. So the two divs that pin and size the nested table stay inside, and the wrapper is `contents` on its own. The research's idea to make the wrapper the pinned div does not hold in such a host.
- **One selector changes.** The rule that shows a line's create and action buttons once the nested table has read, `td[data-nested]>div>div>[data-read]` (`parts/grid.ex:756-757`), gets one more `>div`. It is in the class of every grid: a one-time, reviewed snapshot change (D4).
- **Target as an attribute selector.** `[id='…']`, not `#…`: a table id given by a host may start with a digit.
- **`phx-target`.** The line buttons that target a nested table by selector (`related.ex:78, 96`) get `@myself`; the name already carries the table. The normaliser already writes every `phx-target` as `T`.
- **Hooks.** Nothing changes. `pushEventTo(hook.el, …)` from teleported content finds the component through the wrapper's `data-phx-teleported-src` (`deps/…/view.ts:1783-1808`). The grid hook finds nested grids with `closest` (`assets/js/grid/tree.js`, `shared.js` `AROUND`), which an extra element does not disturb. Panel and picker hooks find their grid by id (`panel.js:21`, `picker.js:14`).

### 2.6 The picker needs no portal

A portal is needed only where a table would sit inside another table's stream item. A picker's dialog never does. The top table's picker is in the component's root (`table_component.ex:687-694`). A nested table's picker is in that table's root, which is inside its portal, at the top level of the template. So the picker's table is drawn in place inside its dialog, from its entry. `Parts.Picker.picker` takes it as a slot instead of `component` and `reader` attributes. The dialog stays where it is today, so `picker/2` of the read seam (`> div[id^='ID-pick-']`) and the hooks see what they see today.

### 2.7 Order of the portals

LiveView teleports the templates of one patch in page order, after the morph (`deps/…/dom_patch.ts:553-561`). A template whose target is not there yet throws at once (`:868-875`). So `Registry.portals/1` gives parents before children: sorted by the length of `path`, then id. The portals are siblings; LiveView's five passes apply to portals inside portals only, so depth is not limited by it (D7).

## 3. Cleanup by reconciliation (F11)

**What is rendered decides what stays.** After every callback (`update`, `handle_event`, `handle_async`), `tidy/1` runs over the registry:

1. **Reconcile.** Start at the top. An entry renders: the nested table of each open line of each row that is still in its `rows` (`open` ∩ `rows`), and its picker's table while `picker` is set. That is today's `rendered/1` (`core.ex:529-532`) plus the `rows` check. Open what is rendered and missing (2.4); close every entry that is not reached. Closing by reachability takes a whole subtree.
2. **Follow** live updates, for each entry with something `waiting` or `held`, parents first (`Updates.follow/1`, within the entry).
3. **Reconcile again**: following may have removed rows.
4. **Summarise** each entry that has one due.

Closing by path, never by string prefix: `…-t-comments` is a prefix of `…-t-comments_archive`. The research's `close(prefix)` with `String.starts_with?` would close a sibling.

**Closing an entry** (`Live.Registry.close/2`), in this order:

| Step | How |
| --- | --- |
| Listener | `Listener.stop/1`; a late batch for the id is dropped (2.3) |
| Async | `cancel_async` of its three keys; a bulk run's copies removed (`Files.drop_copies/1`) |
| Uploads | each name in `entry.uploads`: `cancel_upload` for every entry of it, then `disallow_upload` (it raises while entries are active, R §10.4) |
| Stream | `stream(name, [], reset: true)`; the name back to the pool |
| Entry | removed from `entries` |

**Never a portal without its target.** Every change of `open` re-puts the row's detail in the same callback (`Nesting.on`, `Reading.remove_row`, `show`, `show_message`, verified in `nesting.ex:195-226`, `reading.ex:257-316, 372-379, 503-529`). So the target cell and the registry change in the same render. A root test asserts the invariant: after any callback, every entry's target is a line that its parent's last detail item holds.

**Each removal path:**

| Path | What removes the row or line | Where the entry goes |
| --- | --- | --- |
| Line closed, row collapsed | `toggle`, `expand` change `open` and put the detail | reconcile, same event |
| Live-update delete | `left` → `Reading.remove_row/2` deletes the row, its detail and its `open` | reconcile, same event |
| Page change, sort, filter, read again | the read's result: `show/3` resets the stream and `open` | reconcile in `handle_async`'s tidy, same render as the reset |
| A failed or refused read | `show_message/2` resets the stream, `open` and `picker` | the same |
| Who is asking changes | the top is told another `scope`, `actor`, `tenant` or `authorize?`: it forgets `open` and `picker`, puts its expanded details back closed, and reads again (target §6a) | reconcile, same `update` |
| Picker closed | `picked`, `picker_cancel`, a new read set `picker: nil` | reconcile, same event |
| `detach` (stage 4) | the top entry goes | all entries closed |

**One browser test per path** (target §9 stage 5): live delete of a parent row with its comments open; page change; filter; sort; actor change (a small page in `demo/e2e/server/`, like `select_live.ex`, whose button changes the `actor` given to the tag); a picker closed by Cancel, by a choice, and by a new read of its table; a level-2 row deleted with level 3 open. Each asserts the nested table is gone, focus is where the trail says, and nothing on the console: every browser test already fails on a console error or an uncaught exception (`demo/e2e/support/fixtures.ts:142-147`), which is how "portal target … not found" shows. `detach` gets its test in stage 4.

## 4. Live updates, the listener and "held" rows

- **One listener per entry, as today** (Q10). `Updates.listen/1` runs within the entry; the relay names the entry (2.2). `AshDataTable.Test.listening/2` counts the same listeners as today.
- **Held rows.** A row stays as it is while a panel or picker is open for it, or in any table under it. Today `working/1` reads `@tables` (`updates.ex:136-159`). Now it reads the registry: the rows of this entry whose open lines lead to an entry, at any depth below (by `path`), with `panel` or `picker` set.
- **Release.** Today a table that closes its panel tells the held tables around it with `send_update(cid, live: :released)`. Now step 2 of `tidy/1` follows every entry with `held` rows after every callback, in the same render. No message, no extra render.
- **`redetail/1`** (`updates.ex:217-223`) stays, per entry. It exists for LiveViewTest's view of nested components inside stream items; with portals it may be unneeded. It is removed only in a commit of its own, if the suites stay green without it.

## 5. "Proven on one nested table first"

**The first step (D1).** The registry and the portal for nested tables are built generically, for every relationship: a switch per relationship would need both mechanisms at once (a live component inside a portal-drawn table, taking part in `@tables`), which the next step deletes. Pickers stay live components in this step; they keep today's `@tables` code for themselves only, and reconcile also stops the listeners of picker components under a closed entry. Before anything else moves, the evidence is collected on **task → comments** on `/tasks` (the baseline's nested row, snapshot 03), then two levels (task → comment → author, snapshot 04).

**What is measured and which tests prove it:**

| Check | Go when |
| --- | --- |
| Portal combination, browser (R §10.7 point 2), new tests | target inside a stream row; parent row put again by a cell save keeps the nested table, focus three levels down and text typed into a nested filter; three levels; a teleported grid's hook mounts once (`ownedSheets`) — all green |
| Browser specs of nesting | `nesting.spec.ts`, `a11y-nesting.spec.ts`, `scrolling.spec.ts`, `live_updates.spec.ts`, `relationships.spec.ts`, `hiding.spec.ts`, `resizing.spec.ts` green 10 times in a row (`--repeat-each=10`), and the whole suite once |
| Removal paths of nested tables (section 3) | green, no console error |
| Demo suite | green; only the seam of group I changed |
| Snapshots | 03 and 04 identical after the new normalisation; all others identical but for the one reviewed class string |
| Performance, `demo/perf/baseline.mjs` | opening a nested table: bytes within the post-3c number plus the template and wrapper (about 100 bytes); Ash reads and statements not more; time within 20 % |

**No-go and the fallback (owner, D-events; RQ3).** The trigger: a LiveView release breaks portals inside streams, or the browser tests of the combination cannot be made stable (D8 says when: a failure caused by the portal mechanism that two fixes do not cure, or a spec of the table above that fails once in its ten runs). Applying it:

1. `git revert` the stage-5 commits back to the tag `stage5-start`.
2. Keep what does not depend on the mechanism: the entry fields of 2.1, the names by id of 2.2, the upload fix of section 7, and the removal-path browser tests (they test behaviour, valid for both).
3. Nested tables and pickers stay live components inside the library, as today; `@tables` stays.
4. Record in target §9 stage 5: fallback applied, the reason, the LiveView version. Target §1.1 ("no live component in the core, nested tables included") is amended, with the owner's yes.
5. Stage 4's design note must then cover `attach` over nested live components (F5's hybrid: the attached top table relays through `send(view, …)` and a `handle_info` hook instead of `send_update`).

## 6. Tests

**The read seam (group I, `DemoWeb.TablePage`; no test body changes).** What it must still learn:

| Seam | Today | Stage 5 |
| --- | --- | --- |
| `send_event/5` (`table_page.ex:1135-1146`) | `element("[id='ID-grid']") \|> render_hook` | from the hook's element when LiveViewTest sees it; else from the top table's grid. Every table is in that one component, and the name carries the table |
| `click/2`, `table_of/3` (`:1204-1260`) | the table from the element's `phx-target` (a cid, or a selector) | the table from the event's name. All grids now share one cid: `table_of/3` would find the top grid |
| Form helpers `filter`, `argue`, `page_size`, `type_in_panel`, `run_panel`, `send_panel` (`:29-34, 43-49, 81-86, 887-905`) | `Phoenix.LiveViewTest.form/3`, `element/2` | as today where LiveViewTest sees the form. For a form in a portal: read it from the resolved page, build what a browser sends (each named control's value, checked boxes, selected options, the given values merged in; a given name the form lacks raises, as `form/3` does) and send its `phx-change` or `phx-submit` by name through `send_event`. About 60 lines, tested in `table_page_test.exs`. About 15 calls in the demo suite pass a nested table's id |
| `document/1` (`:1293-1303`) | resolves portals | also unwraps `_lv_portal_wrap_*` (D4), as the snapshot normaliser does |

Then both move into the library as `AshDataTable.Test` (S21: read a nested table from its portal, send its events by name), and `TablePage` calls it.

**Group G (listener tests).** No change expected. The root tests that start listeners themselves (`test/live_updates_test.exs`, about `:460-550`) test `AshDataTable.Listener`, whose API stays. The demo's listener counts go through `AshDataTable.Test.listening/2`, and there is still one listener per open table.

**Group H (the scroll wrapper).** Not needed with D4a: `sideways_scroll_test.exs:59-64` reads `cell > div > div > [id=…]` on the resolved, unwrapped page, which is today's.

**Group K (new, D5).** `label_import_test.exs` "the labels under a task have the action on their line…" calls `file_input/4` itself on a nested panel's form (`:280`). LiveViewTest cannot reach a file input in a portal. Its upload half moves into a new browser test; the demo test keeps the half up to the panel.

**Snapshots.** The normalisation of section 1. Snapshots 03 and 04 prove the portal path draws today's markup.

**The browser suite is the main proof.** It runs the real hook under real portals; LiveViewTest does not teleport. The new tests: the combination tests of section 5 and the removal paths of section 3.

**Performance.** Run `demo/perf/baseline.mjs` at the start of stage 5 on the same machine (the baseline machine was busy), and after. Compare "Opening a nested table" (baseline 29,693 bytes, about +890 after 3c) and "Opening the picker" (27,078, +444 after 3c). Add two measurements: a cell save in a nested table, and a cell save in the top table with a nested table open (R §10.3: about 160 bytes per open table on another table's change). Growth is measured and explained, not forbidden (owner, 2026-10-15).

## 7. Risks and how each is kept in check

| Risk | Check |
| --- | --- |
| A portal outlives its target: LiveView throws "portal target … not found" | reconcile after every callback (section 3); the invariant test; every browser test fails on a console error; one browser test per removal path |
| Portal target inside a stream row is not tested upstream; a LiveView release breaks it | the combination browser tests; D9 (version bound); the fallback (section 5) |
| The host's CSS makes the wrapper `display: contents` | the wrapper carries no layout (2.5); the browser suite on the demo, which has that rule |
| **All tables share one `@uploads`.** `Files.drop_files/1` (`files.ex:63-79`) cancels every upload of the socket: opening a panel in a nested table would drop a file chosen in the top table's open panel | restrict it to `entry.uploads`; a demo test with files chosen in two tables' panels at once (as `file_two_tables_test.exs` does for two top tables) |
| Closing by string prefix closes a sibling (`comments` / `comments_archive`) | close by `path`; a root test with two such relationship names |
| A stream name reused in the render that closes its old table | a root test that closes and opens in one callback; the rows' DOM ids carry the table id, so a reused name cannot mix rows |
| An event, async result or listener batch for a closed entry | unknown id: `malformed/2`'s answer, or dropped; async cancelled, listener stopped on close |
| More bytes: every table is in one assign | `render` passes single fields; keyed portals; the perf runs of section 6 |
| Hooks under a portal: `beforeUpdate`, an editor's `phx-update="ignore"`, `busyThenIdle` on a nested grid | the browser suite: editing, live updates and nesting specs |
| Portals out of order | `Registry.portals/1` sorts parents first; the three-level browser test |
| `within/3` leaves an entry checked out | it always checks the top back in; a root test that `table.entry` is the top's after every callback |
| LiveViewTest cannot see into a portal, so demo tests read a model of the page | the seam is tested by `table_page_test.exs`; the browser suite is the proof |

## 8. Decisions for the owner

**D1. What "proven on one nested table first" means in code.**

| Option | For | Against |
| --- | --- | --- |
| a. The mechanism generic for nested tables; pickers stay components for that step; the gate is measured on task → comments, then all suites, before pickers and the removal of `@tables` move | no throw-away code; the gate comes before most of the work | not literally "one table" in the code |
| b. A temporary switch: only task → comments through the portal | literal | both mechanisms at once: a live component inside a portal-drawn table must join `@tables` and `send_update` through a table that is no component; that glue is deleted a step later |

**Recommendation: a.**

**D2. The picker: in stage 5 or after?**

| Option | For | Against |
| --- | --- | --- |
| a. Stage 5, after the gate: an entry with no portal (2.6) | `@tables`, `live: :released` and the last `live_component` go in this stage (V14); stage 4 builds on the final shape | one more step in the riskiest stage (a small one: no portal) |
| b. A later stage | stage 5 smaller | `@tables` stays for pickers; stage 4's `attach` then holds picker live components: F5's hybrid |

**Recommendation: a.**

**D3. Stream names.**

| Option | For | Against |
| --- | --- | --- |
| a. A pool, reused (`rows`, `rows_1`, …) | the socket holds as many streams as tables were open at once | a name must be reset before reuse (done on open) |
| b. Names from ids | readable | every table ever opened leaves a stream and an `:after_render` hook on the socket for the life of the page; `stream_configure` cannot be undone (R §10.3) |

**Recommendation: a.**

**D4. The portal's wrapper in tests and snapshots.**

| Option | For | Against |
| --- | --- | --- |
| a. The normaliser and the read seam resolve portals, drop the templates and unwrap the wrapper; the grid's class string (`grid.ex:756-757`) is updated once in the snapshots, the diff reviewed to be that string only | no test body changes; group H not needed; one rule in two places | tests do not see an element that is in the browser's DOM (it has no layout; the browser suite sees it) |
| b. Unwrap in the snapshots only | the read seam shows the true DOM | group H: `sideways_scroll_test.exs:64` changes |
| c. Also a normaliser rule for the class string | snapshots byte for byte | a normaliser that hides a real change of the markup |

**Recommendation: a.**

**D5. The demo test that uploads into a nested table's panel** (`label_import_test.exs:280`).

| Option | For | Against |
| --- | --- | --- |
| a. Group K: its upload half becomes a browser test; the demo test keeps the half up to the panel | a nested upload through a portal needs a browser test anyway; the demo test still checks the line and the panel | one demo test body changes |
| b. Draw a nested table's panel and picker outside its portal, so LiveViewTest reaches them | no test changes; `form/3` and `file_input/4` work on nested panels | the DOM moves; a dialog inherits the styles of where it stands (today a nested panel stands in a cell of a `.table`), so the look can change; more markup out of place |

**Recommendation: a.**

**D6. How the core addresses an entry.**

| Option | For | Against |
| --- | --- | --- |
| a. `Live.Registry.within/3` checks the entry out into `table.entry` | every `Live.Core.*` function and pattern stays; the diff of the riskiest step stays small | an implicit "current entry" |
| b. Every function takes the id and reads `entries[id]` | explicit | hundreds of changed lines in the step that must be easy to judge and to revert |

**Recommendation: a.** Stage 7 may make it explicit.

**D7. Depth.**

| Option | For | Against |
| --- | --- | --- |
| a. As today: `max_depth` defaults to 3 and takes any value (`resource/table.ex:93-98`) | no change; sibling portals have no depth limit in LiveView | none known |
| b. Cap at 5 | safe if portals were ever nested | a new limit for no present reason |

**Recommendation: a.**

**D8. When "cannot be made stable" holds.**

| Option | For | Against |
| --- | --- | --- |
| a. Measurable: the specs of section 5 ten times in a row and the whole suite once; a failure caused by the portal mechanism gets two fixes; then the fallback, and you are told | a builder can apply it | a number chosen, not given |
| b. You decide each case | judgement | the build waits for you |

**Recommendation: a.**

**D9. The LiveView version bound** (`mix.exs:141`, today `~> 1.2 and >= 1.2.10`).

| Option | For | Against |
| --- | --- | --- |
| a. `~> 1.2 and >= 1.2.12`, the version the mechanism is tested on; the combination browser tests run on every LiveView upgrade of the demo | honest about what is tested; hosts can still take 1.3 | a host on 1.2.10–11 must upgrade |
| b. Also `< 1.3` until the tests ran on 1.3 | no untested pairing | a library that holds hosts back |

**Recommendation: a.**

## 9. Order of work and the done-check

Each step: each suite once (root, demo, browser), its own commit or commits on `main`, `docs/agents/architecture.md` updated.

0. Tag `stage5-start`. Run `demo/perf/baseline.mjs` on the same machine.
1. **Names by id, no portal yet.** Each component still holds one `Table`, now with `entries` (empty), the pool, `within/3`, the entry fields of 2.1, async keys and stream names of 2.2, `entry.uploads` and the fix of `drop_files/1`. Snapshots byte for byte; no test changed.
2. **Nested tables through portals: the proof (D1).** `Live.Registry` (open, close, reconcile, portals, pool); `tidy/1` over the registry; `working/1` and release by registry; the relay with the id; `Parts.Related.lines` renders only the target; the wiring renders the portals; `Parts.Grid` takes `rows` instead of `streams` and loses `component` and `nested_reader`; the seam of group I; the snapshot normaliser; the combination and removal-path browser tests. **Gate (section 5).** No-go: the fallback.
3. **Pickers as entries** (D2). `Parts.Picker` with a slot; picker removal-path tests; then `@tables`, `tables/0`, `live: :released` (`core.ex:147`), the per-component `close/1` and both `live_component` calls removed. Group K (D5).
4. **`AshDataTable.Test`**: portal reading, forms in portals and events by name, from `TablePage`; `TablePage` calls it.
5. The LiveView bound (D9); the comment of `table_component.ex` ("Nested tables", "Live updates", "Choosing a related record"), the moduledocs of `Listener`, `Table`, `Entry`; perf run and comparison. Then `redetail/1` in its own commit, if it can go.

**Done when:**

- The three suites green. Changed tests: only the seams of group I (`TablePage`, the snapshot normaliser), group K, and the reviewed snapshot diff of D4; every other test body as at `stage5-start`.
- No `@tables`, no `Process.put` in the live core, no `live_component` in `lib/`.
- The dependency test passes in fail mode.
- The perf comparison with the baseline is written into `baseline.md`: bytes per action as in section 6, Ash reads and statements not more, times within 20 %.
- Target §9 stage 5 ticked, or the fallback recorded.
- **The drift check** (target §9): an independent reviewer compares the build with target.md — `Live.Registry` and `Table` per §4.4, the rules of §1.5 (the parent's key from the registry, ids as claims, uploads and async closed with their entry), §6's "one id names all four", the cleanup of F11, and that only the agreed tests changed. The stage is done only after it.
