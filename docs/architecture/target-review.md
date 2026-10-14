# Review of the target and of its critique

Judge: independent of the target's author and of the critic. 2026-10-14, code at `0393585`.
Read: `target.md`, `target-questions.md`, `test-coupling.md`, the decisions on issue #21
(2026-10-12 to 2026-10-14), the critique (20 findings), the code, LiveView 1.2.12 and Gettext 1.0.2 in `deps/`.
One check was run (Gettext locale in a Task, section 4). Nothing in the repository was changed except this file.

Marks: **[code]** read in the code; **[run]** tried; **[infer]** reasoning only.

---

## 1. Summary

**Findings:** 12 hold, 8 hold partly, none fails. The critic was right on the facts almost everywhere.
Where I differ, it is about severity and about the fix.

- **F1 is decided by the owner (2026-10-14, final):** sensitive values never reach the drawing by
  any path, except one value at a time through the "Show" (reveal) command. It is not a blocker any
  more; section 3 gives the exact changes to `target.md`. It is cheap: today's panel guard is one
  function, `panel_value/3`, and it moves into `Present`.
- **One live bug, confirmed by a run:** after a bulk action on a German page, the failure reasons
  are in English. They are made inside `start_async`, and a Task does not inherit the Gettext
  locale (section 4).

**Verdict on the target: sound with changes.** The four parts, the one-way dependencies, the xref
test and the safety order are right. It needs rework in three places:

1. **The stage plan (§9).** Stage 2 cannot remove `@tables`, and stage 3 is too big. Stages 4 and 5
   are in an order that builds a throw-away hybrid.
2. **What the core returns (§4.3).** Texts should be terms, not words. The panel needs a data shape.
   `Operation` needs its real inputs.
3. **Three agreed things the target contradicts or leaves out:** selection is "core" in the owner's
   split but browser-only in the target. The nested-table fallback and "proven on one nested table
   first" are missing. Q15's release-build check is missing.

**Must happen:**

| Before | What |
| --- | --- |
| Stage 0 | Decide owner question 5 (fix the locale bug now or later). Add Q2's private notifier tag to the stage 0 list, so no name changes after stage 0 (M1). |
| Stage 1 | Refresh §4.8 line ranges and §2/S17 against HEAD; place `Zone` (F17). Write down that hooks stay in the component module in stage 1; the move to JS files is its own step with the release-build check (M2). |
| Stage 2 | Amend stage 2 (section 6): keep `@tables` until nesting changes (F5); the 2a functions keep their `opts` and `Caller.reader_opts/1` produces them (F7); `Caller` holds no assigns (F8). These are text changes to the target only. Stage 2 then stays a pure move. |
| Stage 3 | The owner's design note must settle: stage 3 split into 3a/3b/3c (F6); `Operation`'s real inputs (F9); message terms instead of words (F2); the drawing-data shape with no sensitive values, panel and picker included (F1, decided); a short "cross-cutting" section (F18). Owner questions 1 and 2 answered. |

---

## 2. All findings

Severity: B blocker, M major, m minor. "Settle before" = the stage that must not start without it.

| Id | Title | Critic | Verdict | Mine | Stage | Settle before | Fix |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F1 | Panel's sensitive guard in the drawing | B | holds; decided by the owner | M | 3, 6, 7 | 3 | Adjusted to the owner's decision: no sensitive value on any path to the drawing; one value only through the reveal command |
| F2 | Texts, formatting, error words in the core | M | holds; live bug confirmed | M | 3 | 3 | Adjusted: outcomes carry message terms; words made in the LiveView process by a translation step beside part 3 |
| F3 | Model carries drawing; declaration carries drawing options | M | holds partly | m | 3, 7 | 7 | Adjusted: no struct split; mark the fields as hints the core passes through; `hideable/1` to part 3; note in §5.5 that xref does not see data coupling |
| F4 | Selection left in the hook | M | holds (contradiction) | M | 6 | 3 (entry fields) | Owner question 1 |
| F5 | `@tables` cannot go in stage 2; stage 4 hybrid | M | holds | M | 2, 4, 5 | 2 | Accepted: V14 to stage 5. Order of 4 and 5: owner question 2 |
| F6 | Stage 3 too big | M | holds | M | 3 | 3 | Accepted: 3a `Present` + `Intent`, 3b `Operation`, 3c `Live.Core` + namespacing |
| F7 | "Every 2a function takes `Caller`" breaks ~190 tests | M | holds | M | 2, 3 | 2 | Accepted: keep `opts`; `Caller.reader_opts/1` builds them |
| F8 | `Caller` holds assigns; veto and page values take assigns | M | holds | M | 2, 6 | 2 (field list), 6 | Accepted: 2b evaluates the functions with live assigns; plain results go into `Operation` |
| F9 | `Operation` signature too small | M | holds partly | M | 3, 6 | 3 | Adjusted: one 2a input value per write (model, state, parent, key check, form values, files callback); veto and checks run in the LiveView process before any async start |
| F10 | Nested-table decision, unrecorded costs | M | holds partly | m | 5 | 5 | Adjusted: keep the decision (owner question 3); record the owner's fallback and trigger; test blindness is solved by the portal reading seam (`0ff2672`) |
| F11 | Nested-table failure modes | M | holds | M | 5 | 5 | Adjusted: no list of paths that "must call close"; the registry reconciles against what is rendered after every event, as `close/1` does today; plus the host rule |
| F12 | React/Vue door narrower than §7 says | M | holds partly | m | 7, later | — | Accepted: state the limits in §7 |
| F13 | "Easier to add" not shown | M | holds partly | m | 7 | 7 | Adjusted: claim "findable"; add a kit-evolution rule (new parts get defaults in `use Kit`) |
| F14 | Tag mode is not the same core | M | holds | M | 4, 6 | 6 | Owner question 4; three-way runs on a chosen subset (accepted) |
| F15 | `Routes` in 2a couples to part 4 | m | holds partly | m | 1 | — | Adjusted: keep `Routes` in 2a (Q13 taken); name the coupling in §6; add `Phoenix.Router` to the grep's allow-list on purpose |
| F16 | Shallow splits, things built for no user | m | holds partly | m | 3, 7 | — | Adjusted: `Live.Core.*` are private file splits; S20 transport stays an internal JS module. Keep `class/2` and `KitCase` (rejected parts) |
| F17 | Target stale against the code | m | holds | m | 1 | 1 | Accepted |
| F18 | Missing cross-cutting decisions | m | holds | m | 3–6 | 3 | Accepted |
| F19 | Events: claims as facts, unscrubbed record | m | holds | m | 6 | 6 | Adjusted: specify `:read` and `:selection_changed`; mark claims; the record is scrubbed (follows the owner's F1 decision) |
| F20 | "Cannot be wired away" overstated | m | holds | m | doc | — | Accepted: reword |

---

## 3. The findings that hold

### F1. A sensitive value in the panel's data

**Evidence.**
- [code] `act.ex:614-615`: `AshPhoenix.Form.for_update(record, name, …)`. The form is built on the
  re-read record, so it holds the record's sensitive attributes.
- [code] `table_component.ex:9466-9498`, `panel_value/3`: "A sensitive field holds what was typed
  into it, and nothing else: never what the record has". Every other field reads
  `form[input.name].value`. So the guard sits in the drawing, in one function.
- Target §1.5 says `Present` is "the only way from a record to what a part draws". §4.3 limits
  `Present` to "a row and its cells". §4.5 makes `Parts.Panel` a replaceable kit part (S3). So the
  claim in §1.5 is not true for the panel.

**Decided by the owner, 2026-10-14 (final).** Sensitive values are never handed to the drawing or
a kit: not in rows, cells, the action panel's form data, picker labels, events to the page's
components, or anything else a part draws. The one exception is the explicit "Show" (reveal)
command: for one cell, the core reads the record again as the person, checks the field policy, and
returns that one value on request. A sensitive panel field starts empty (a password field). "Clear"
sends only the instruction, never a value.

Today's code already does most of this (rows: `Sensitive.scrub/2`; panel: `panel_value/3`; picker
labels: a sensitive `label_field` is a compile error, `resource/referencing.ex:129`; reveal:
`handle_event("reveal", …)`, `table_component.ex:2337`, and `revealed/4`, `:2905`). What changes is
where the guarantee lives: from "each part takes care" to "the data the drawing gets cannot hold
the value".

**Change to `target.md`:**
- **§1.5, row "Nothing sensitive reaches the browser before 'Show'"**, new text: "**By
  construction.** Every path from the core to the drawing goes through `AshDataTable.Present`,
  which drops or masks sensitive values first: rows, cells, the action panel's fields, picker
  rows and labels, failed edits, messages. No part gets a record, an `AshPhoenix.Form` or a
  changeset. The one way to a sensitive value is the reveal command (`Operation.reveal`): one cell,
  read again as the person, field policy checked, the value returned in the reply only."
- **§4.3, `Present` row**, responsibility: "From the core's data to everything a part draws: rows
  and cells; **the open action panel's fields (value, errors, flags; a sensitive field is always
  empty, or holds what was typed in this panel)**; **picker rows and the chosen labels**; failed
  edits. Calls `Sensitive.scrub/2` first. Today: `item/8`, `put_row`, `cell/…`, `typed_value`
  **and `panel_value/3` (`table_component.ex:9466`)**."
- **§4.3, `Operation` row**: keep `reveal/3`, and name its rule: "re-read as the person, field
  policy checked, returns one value; nothing else returns a sensitive value".
- **§1.4, row "Open action panel (`AshPhoenix.Form`)"**: add "The form stays in the entry. The
  drawing gets `Present`'s field map."
- **§3, S3 (kit), "What may cross"**: "Values from `Present` and attribute bundles. Never a record,
  an `AshPhoenix.Form`, a changeset, a sensitive value, the actor, or another field of a row."
- **§3, S4 (column component)**: add "a sensitive column has no component" (true today:
  `model/column.ex` comment "has no component").
- **§3, S6 (hook ↔ server)**: add "`reveal` is the only reply that carries a sensitive value, for
  one cell; `clear` carries no value."
- **§3, S8 (commands)**: the command set includes reveal for the browser path (S6). If a host
  command for reveal is wanted later, it goes through `Operation.reveal` with the same checks. (Not
  a new public command now.)
- **§6, row "`Present` and `Sensitive.scrub/2`"**: "the only way from the core's data to a part,
  panel and picker included".
- **§9 stage 3a**: "`Present` covers the panel's fields and the picker; `panel_value/3` moves into
  it. The markup snapshots stay identical."
- **§9 stage 6 and S7 (events)**: the owner's list includes "events to the page's components".
  Today's stage 6 item says "the record in an event is not scrubbed of `sensitive?` values; it is
  server code's", following D-headless ("the record as the action returned it"). These two now
  disagree. The direct reading of the new decision: the record in an event is scrubbed
  (`Sensitive.scrub/2`) like a row, and `arguments` already leave sensitive ones out. Change the
  stage 6 item to "the record in an event is scrubbed of `sensitive?` values" unless the owner
  says that host `handle_info` code is not "the drawing". (This replaces my F19 fix, which kept it
  unscrubbed.)
- **§9 stage 7, `KitCase`**: assert that no rendered state of any part contains a sensitive value
  of the test resource (a cheap mechanical check of "by construction").

### F2. Texts are made inside the core (and inside a Task)

**Evidence.**
- Owner, 2026-10-14: "the core reports what happened as data; turning it into words is a
  translation step the drawing uses."
- Target §4.3 puts `Text`, `Format`, `Errors` in 2a. §1.3 allows "the Gettext locale of the calling
  process" in pure code.
- [code] `bulk.ex:140, 201, 266-271` call `Text.t`. `bulk.ex:266` calls `Errors.of_action`, which
  calls the host's `translate_error` (`text.ex`, `error/1`).
- [code] `table_component.ex:3690`: `start_async(:bulk, fn -> Bulk.run(…) end)`. [code]
  `deps/phoenix_live_view/lib/phoenix_live_view/async.ex:266-271`: `Task.start_link`, which copies
  no process dictionary. [code] `deps/gettext/lib/gettext.ex:748-750`: the locale is read with
  `Process.get`.
- [run] In a Task started like this, `Gettext.get_locale()` is `"en"` when the caller set `"de"`.
  This is a live bug (section 4).

**Fix (adjusted).** Do not move all wording out at once. In stage 3, `Operation`, `Bulk` and the
outcomes of `Query` return message terms: `{:text, key, bindings}` for the table's own texts, and
`{:ash, message, vars}` for an action's messages. A translation step turns terms into words in the
LiveView process (2b, when it builds a reply or a status) or in the parts (3). `Text`, `Errors`'
wording and the text part of `Format` become that step, placed beside part 3 (for example
`AshDataTable.Words`). 2a may not call it. This also fixes the bug for good: words are never made
in a Task. How far `Format` goes is owner question 6.

**Change to `target.md`:**
- §1.3: delete "The Gettext locale of the calling process" as an allowed thing. Add: "2a returns
  messages as terms; it makes no words."
- §4.3: remove `Text`, `Format`'s wording, `Errors`' wording and `Gettext` from 2a. Add a row
  "`AshDataTable.Words` (translation step, beside part 3; called by 2b and 3; not by 2a)".
- §5.1: 2b → Words "yes"; 3 → Words "yes"; 2a → Words "no".
- §5.5: add to the grep for 2a: no call to `Gettext.` or `Words.`.
- §4.3 `Present`: "key, **values**, input values, flags" instead of "texts" (or per owner question 6).

### F3. Drawing hints in the model

**Evidence.** [code] `model/column.ex:117-142`: `component`, `max_lines`, `editor`. [code]
`model.ex:314, 458`: `sticky_label?`. [code] `model.ex:1010-1011` `hideable/1`, used by the markup
only (`table_component.ex:4649-4651`). [code] `model.ex:806-808` updates `column.component` with map
syntax, so xref sees no 2a → 3c edge.

**Why only partly.** These options were decided by the owner (`max_lines`, `sticky_label?`,
`component` exists today). A model "everything a table is drawn from" (ADR 0001) may carry hints. The
harm is small as long as the core does not act on them. Splitting `Model.Column` now would touch
about 192 root `Model` tests (test-coupling Appendix A) for no behaviour gain.

**Fix (adjusted).** Keep the struct. Document `component`, `max_lines`, `sticky_label?`, `editor`
as "presentation hints: the core passes them through and never branches on them". Move
`hideable/1` to part 3 in stage 1, together with the markup that uses it. A resource naming a HEEx
component is a known limit for O-ui (F12).

**Change to `target.md`:**
- §4.3 `Model` row: drop `hideable/1` from its API; add "presentation hints are passed through".
- §4.5 `Parts.Grid` (or a helper of 3): gets `hideable/1`.
- §5.5, at the end: "xref sees calls, not data. A 2a struct that holds a 3c value is not reported.
  Such fields are listed in §6."
- §6: a row "`Model.Column` presentation hints | carried for the drawing; the core never reads them".

### F4. Selection: core or browser?

**Evidence.** Owner, 2026-10-14: "The core knows … selection and expanded rows (they change what is
read and run)." Target §1.4: "Selection | The browser (hook) only." [code] the server holds only
the mode `selecting` (`table_component.ex:757, 788-793`). The hook keeps the keys and tells only the
dialog (`ash_table:selection`, a DOM event, `:7552`). The server sends `ash_table:unselect`
(`:2011`). Yet S7 lists `:selection_changed` and S8 `clear_selection/2`, `selected_records/3`.

**Fix.** A decision for the owner (question 1). Whatever is chosen, §1.4 and the owner's split must
say the same thing.

### F5. `@tables` and the order of stages 4 and 5

**Evidence.** [code] `table_component.ex:550` `@tables {__MODULE__, :tables}`. `:1349-1405`: every
table writes its entry (`path`, `cid`, listener pid, `open?`, `held?`) into the process
dictionary. It is read by the tables around it (`working/1`, `:1476-1498`), and they are woken with
`send_update(cid, live: :released)` (`:1378`). It exists because each nested table is its own live
component with its own socket. Until stage 5 there is no single socket that could hold the
registry. Stage 4 then puts an attached top table (no `cid`) over nested live components. The top
table would have to take part in `@tables` and in `send_update` without being a component. That is
hybrid code that stage 5 deletes.

**Fix.** Accepted: V14 moves to stage 5. In stage 2 each live component holds its own `Table` value
with one entry; `@tables` stays as it is. The order of 4 and 5 is owner question 2.

**Change to `target.md`:**
- §9 stage 2, second item: "`AshDataTable.Table`: options, `Caller`, the entry of this table.
  `@tables` stays until stage 5."
- §5.4 V14, "Fix": "`Live.Registry` inside `Table`, in stage 5 (needs one socket for all tables)".
- §4.4 `Live.Registry` row: "New, stage 5" (not "stage 2/5").
- §9 stage 5: add "Remove `@tables` (V14)".

### F6. Stage 3 is too big

**Evidence.** §9 stage 3 creates `Intent`, `Operation`, `Present`, `Live.Core` and nine
`Live.Core.*` modules. It also namespaces events and switches the dependency test to fail. The owner
asked for "a short design note before stages 3–7". The owner's speed rule is "each suite once per
build".

**Fix.** Accepted. 3a `Present` + `Intent` (no behaviour change; markup snapshots identical). 3b
`Operation` (the handlers call it; `Act`, `Edit`, `Pick`, `Bulk`, `Record` keep their arguments).
3c `Live.Core` + `Live.Core.*`, event namespacing (the test seam `send_event/4` absorbs it), and the
dependency test switched to fail. Each gets its own green run and its own commit.

**Change to `target.md`:** §9: replace "Stage 3: core" with three sub-stages as above. §5.5 last
item: "fails from the end of stage 3c".

### F7. Keep the arguments of the 2a functions

**Evidence.** Target §1.5: "every 2a function takes it [`Caller`]"; §4.3 `Query`: "as today, taking
`Caller`". [code] today they take keyword `opts`: `query.ex:101, 156, 206, 228, 255, 311, 406`;
`record.ex:19, 73`; `pick.ex:67, 90, 125, 164`. test-coupling §3: groups B (~79) and C (~110)
"survive if … their functions keep their arguments", and the agreed rule is that no test changes in
stages 0–5.

**Fix.** Accepted. `Caller` is built by 2b. `Caller.reader_opts/1` produces the keyword list the 2a
functions take today, and that list stays their argument. New values (context, private arguments)
go into the same `opts` in stage 6 as new keys.

**Change to `target.md`:**
- §1.5, row `authorize?`: "`AshDataTable.Caller` (new) holds them, built from server code only;
  2b passes `Caller.reader_opts/1` to every 2a function, which keep their keyword `opts`".
- §4.3 `Query`: "as today (keyword `opts`)".
- §9 stage 2 `Caller` item: add "2a signatures unchanged".

### F8. No assigns in `Caller`

**Evidence.** §4.3 `Caller`: "… time zone, the page assigns". S9: `map | (assigns, table_ref -> map)`.
S10: `before_action: (Request.t, assigns)`. §2 row 10: "evaluated each time an action is built". A
stored copy of assigns is stale at the next event. It is also nested in itself
(`assigns.table.caller.assigns`) and is copied into every `start_async` closure. In tag mode the
assigns are the live component's, not the host page's [infer].

**Fix.** Accepted. `Caller` holds the reader values, the time zone and the functions, not assigns.
2b calls the page-value and veto functions with the current assigns, in the LiveView process, and
passes the plain results (maps, `:cont | {:halt, text}`) into `Operation`. The tag-mode difference
in what "assigns" means is documented (or the tag passes only its attrs, by design).

**Change to `target.md`:**
- §4.3 `Caller`: delete "the page assigns".
- S9, S10: add "called by the live layer with the current assigns; 2a receives the result".
- §7.3 point 9: "evaluated in 2b, handed to `Operation`"; Hologram's adapter evaluates them per command.

### F9. `Operation`'s real inputs

**Evidence.** §4.3: `(Caller.t, Model.t, Intent.t)`. But the re-read uses the page's read with the
same state and parent (§6, R §11.5), so `State` and the parent key are needed. `submit` needs the
panel's form, which lives in the entry (§1.4). Key checks need the rows index. [code] files run the
action inside `consume_uploaded_entry` (`table_component.ex` "Files" section, about `:3994-4016`).
[code] bulk runs in a Task (`:3690`).

**Why only partly.** A signature in a matrix is a sketch. The design is not wrong, only underspecified.

**Fix (adjusted).** `Operation` takes one 2a value per write, for example `%Operation.Input{model,
state, parent, caller_opts, key_known?: fun, form_values, page_values, veto_result}`. Files: the
live layer passes a function `with_files(fn files -> … end)` that wraps `consume_uploaded_entry`.
The checks and the veto run in the LiveView process. Only the run itself (bulk) goes into a Task.
That keeps the order in one function and keeps the veto out of the Task (D-before 4: "asked once,
before the run").

**Change to `target.md`:** §4.3 `Operation` row: the input value above. §6 `Operation` row: add
"the checks and the veto run in the LiveView process, before any async start". §9 stage 6, third
item: add "bulk: the veto is asked before `start_async`".

### F10. Nested tables without live components

**Evidence.** The costs the critic lists are real ([code] `dom_patch.ts:871-874` throws on a missing
target; `phoenix_component.ex:3562-3577` says LiveViewTest cannot query portals). But the biggest
cost is gone: the test seam "read the page where a person sees it, portals included" is built
(`0ff2672`, `demo/test/support/table_page.ex:1272-1342`). The fallback is recorded by the owner
twice: D-events ("Fallback if a later LiveView breaks it: live components inside the library, as
today") and the method of 2026-10-14 ("5 … proven on one nested table first, the fallback kept").
What is true: `target.md` mentions neither (no "fallback" in it).

**Fix (adjusted).** Do not reopen the decision without the owner (question 3). Put the owner's
fallback, its trigger and "proven on one nested table first" into §9 stage 5.

**Change to `target.md`:** §9 stage 5, first item: "Prove it on one nested table first (task →
comments), browser and demo suites green; then the rest." New item: "Fallback (D-events): nested
live components inside the library, as today. Use it if a LiveView release breaks portals inside
streams, or if the browser tests of the combination cannot be made stable."

### F11. Nested-table failure modes

**Evidence.** [code] `close/1` today (`table_component.ex:1392-1405`) does not rely on each removal
path: after every event it compares the registered tables with what the table renders now
(`rendered/1`, `:1409-1412`) and drops the rest. [code] `dom_patch.ts:871-874`: a portal whose
target is gone throws. Paths that remove a parent row: live-update delete (`follow/1`), page change,
stream reset, actor/tenant change, `detach/2`. The R §10.7 host rule ("do not put
`<AshTable.attached>` inside a stream item of the host's own") is not in the target.

**Fix (adjusted).** Better than a list of paths: keep today's principle. After every event,
`Live.Registry` reconciles its entries against the open rows that are still in the page, and closes
the rest in the same render. Then a new removal path cannot forget it. Add the host rule. Add one
browser test per removal path in stage 5. On the "one listener per nested table" concern: Q10 keeps
it; it is what the code does today, so not a regression.

**Change to `target.md`:** §6 `Live.Registry` row: "Entries are reconciled after every event against
the open rows in the page; anything else is closed in the same render." §9 stage 5: "Browser test
per removal path: live delete, page change, filter, actor change, `detach`." §4.6 `attached/1`:
"Must not be placed inside a stream item of the host's own (R §10.7)."

### F12. The React/Vue door

**Evidence.** [code] about 60 direct DOM writes (`setAttribute`, `classList`, `.style.`,
`adoptedStyleSheets`, `removeAttribute`) in the hook code. The panel has no data contract (F1).
Intents for submit are `AshPhoenix.Form` params.

**Why only partly.** O-ui is "if possible" and no adapter comes in v1 (owner, Q20). The door is
narrower, not closed.

**Fix.** Accepted. §7.3 point 7: "The hook can be reused only on DOM it owns. A client framework
that renders the grid itself must leave those attributes to the hook, or rebuild keyboard, ARIA,
widths and selection." §7.4: list the known remaining work for an adapter: panel contract (F1),
selection (F4), cell mapping for a resource's `component` (F3), submit intents not shaped by
`AshPhoenix.Form`.

### F13. "Easier to add"

**Evidence.** The walk-throughs are estimates [infer]; I did not recount them. The structural point
holds: every new kit part or cell type is a kit-contract change, and §3/S3 has no rule for it.

**Fix (adjusted).** §0 or §1.1: "Each feature has one findable place per part." S3: "A new part is
added with a default in `use AshDataTable.Kit`, so an existing kit keeps working; `contract:` goes
up only when a part's assigns change incompatibly." Leave the per-table drawing-options channel
(`kit_opts`) until a second need appears.

### F14. Commands in tag mode

**Evidence.** S8: commands `(socket, table)`, "`table` is the attach name or a tag id. Each returns
the socket". In tag mode the table's state is in the live component's socket. The host can reach it
only with `send_update`, which is asynchronous. So `selected_records/3` cannot return records there,
and `refresh/2` cannot "return the socket" changed [infer, LiveView's component model]. Stage 4:
"The mode-independent demo tests run three ways" is about 3 × 1,600 runs.

**Fix.** Owner question 4 for the API. Accepted for the tests: the three-way run covers a chosen
subset (the ten snapshot states plus one test file per feature group).

### F15. `Routes` in 2a

**Evidence.** [code] `routes.ex:46`: `Phoenix.Router.routes(router)`, matching
`metadata: %{ash_table: …}` that `AshDataTable.Router` (part 4) writes.

**Fix (adjusted).** Q13 was taken as recommended; keep `Routes` in 2a. Name the coupling in §6 (row:
"`Routes` and the router's metadata format"). §5.5 grep: list `Phoenix.Router` as the one allowed
Phoenix module in 2a, on purpose.

### F16. Shallow splits

**Evidence.** Nine `Live.Core.*` modules all "socket in, socket out" over one entry (§4.4); S20 has
one implementation.

**Fix (adjusted).** `Live.Core.*`: private file splits, `@moduledoc false`, no promise. S20: an
internal JS module, not a documented seam, until a second transport exists. **Rejected:** dropping
`class/2` or the part callbacks (they serve two kinds of kit author, a re-skin and new markup; R §4);
moving `KitCase` out of `lib/` (a third-party kit needs it in its own tests).

### F17. Stale against the code

**Evidence.** [code] `table_component.ex` has 11,973 lines (target: 11,762); `@tables` is at `:550`
(target: `:413`). `lib/ash_table/zone.ex` exists; `format.ex:38` has `format/2` defaulting to UTC
and `format/3` with the zone; `Zone` is in no module table. §2 row 13 and S17 say "being built". The
owner's answers (Q1, Q15) are not yet written into §4.6, §8 and §9. `AshTable.table/1` has a new
internal attribute `select` (`lib/ash_table.ex:193`, commit `0393585`).

**Fix.** Accepted. Refresh §4.8 against HEAD before stage 1 (stage 1 cuts by it). Add
`AshDataTable.Zone` to §4.3 (2a); its value in `Caller`. §2 row 13, S17: "Exists (`time_zone` attr,
`time_zone` assign)". §4.6 and §8: write the answers in place of "Recommended".

### F18. Cross-cutting gaps

**Evidence.** [code] no `:telemetry` in `lib/`. The target says nothing on errors raised by
`Operation`, on reconnect (the registry is rebuilt, nested entries are lost), or on a tenant change
mid-page.

**Fix.** Accepted. A new §6a "Cross-cutting", one line each: telemetry (none in v1, or spans around
`Operation` and reads); a raise in `Operation` (logged; the person sees the generic failure text;
the entry is left as before); reconnect (nested tables close; open rows come from the URL only for
the top table: as today); tenant or actor change (all entries closed, listeners stopped, read
again; R §5.2); i18n (F2).

### F19. Events

**Evidence.** S7 lists `:selection_changed` without a source the server holds (F4). §9 stage 6:
"the record in an event is not scrubbed of `sensitive?` values". That follows the owner (D-headless:
"the record as the action returned it to that person").

**Fix (adjusted).** Specify the details of `:read` and `:selection_changed` in S7, and mark
selection keys as claims. On the record: the owner's F1 decision lists "events to the page's
components" among the paths that never carry a sensitive value, so the record in an event is
scrubbed (see F1's change to §9 stage 6). The critic's opt-in is not needed.

### F20. "Authorization cannot be wired away"

**Evidence.** A host can register its own `attach_hook(:handle_event)` before the table's and halt
`ash_data_table:*` events; it can rewrite the `Table` value in its assigns [infer; LiveView runs
hooks in order of attachment].

**Fix.** Accepted. §1.5, last-but-one row: "Nothing from the browser and no documented option can
skip a check. Server code of the host is trusted; it can stop an event from reaching the table, but
it cannot make the table write without the checks."

---

## 4. Live bugs in today's code

### Bug 1. Bulk failure reasons in the wrong language

- **What.** On a page in German, after "Run on selected rows" with failures, the summary is German,
  but each reason is English, e.g. "This record is no longer available." or "This could not be
  done." The host's `translate_error` (Ash messages) also runs in English.
- **Why.** [code] `table_component.ex:3690` runs `Bulk.run/5` with `start_async`. [code]
  `bulk.ex:140, 201, 266-271` make the texts there, via `Text.t` and `Errors.of_action` →
  `Text.error/1` → the host's `translate_error`. [code] `phoenix_live_view/async.ex:271`:
  `Task.start_link`, which starts with an empty process dictionary. [code] `gettext.ex:748-750`:
  the locale is `Process.get(backend) || Process.get(Gettext) || default`. [code]
  `table_component.ex:1643-1645`: the reasons are put into the German `:bulk_failure` text in the
  LiveView process. So the message is mixed.
- **Proof.** [run] `Gettext.put_locale("de")` in a process, then `Task.start_link`: in the Task,
  `Gettext.get_locale()` returns `"en"`. The demo sets the locale per LiveView with
  `Gettext.put_locale/1` (`demo/lib/demo_web/locale.ex:36-47`). The German entries exist
  (`demo/priv/gettext/de/LC_MESSAGES/ash_table.po:146, 268`).
- **Not affected (checked).** `start_async(:read, …)` and `(:summary, …)`: `Query.read`,
  `read_related` and `summaries` make no texts. The only texts in `query.ex` are in `arguments/2`,
  which runs in the LiveView process.
- **Severity.** Minor. It is visible, but only on non-English pages with a failed bulk action. No
  safety impact.
- **Fix.** Quick fix: read the locale before `start_async` and set it inside the closure
  (`Gettext.put_locale(backend, locale)` and the global one). Or return terms from `Bulk.run` and
  make the words in `handle_async` (this is F2's fix, at bulk size). When: owner question 5.

---

## 5. Questions for the owner

### 1. Where does selection live? (F4)

Your split of 2026-10-14 puts selection in the core. The target puts it in the browser only, which
is today's code.

| Option | For | Against |
| --- | --- | --- |
| a. The entry holds the selected keys (claims; read again before use); the hook mirrors them | Matches your split. `:selection_changed`, `clear_selection`, `selected_records` have a server source. A Vue/Hologram adapter needs no selection logic of its own | One event per selection change (keys only, small). Work in stage 6 |
| b. Selection stays in the hook; sent as a claim with a bulk action | Today's code; no extra traffic | Contradicts your split. `:selection_changed` would need the hook to report every change anyway. Every other UI must rebuild selection |

**Recommendation: a**, built in stage 6 with the events. Until then nothing changes. Decide before
stage 3 so the entry gets the field.

### 2. The order of stages 4 and 5 (F5)

| Option | For | Against |
| --- | --- | --- |
| a. As agreed: 4 `attach`, then 5 portals | Your agreed order; `attach` is visible to developers sooner | Stage 4 needs an attached top table to join `@tables` and `send_update` with nested live components; stage 5 deletes that code |
| b. Swap: portals and the flat registry first, inside today's top-level live component; then `attach` on the final shape | `attach` is built once; `@tables` goes earlier; the portal reading seam is already built (`0ff2672`) | The registry is first built inside a live component socket (supported: streams and portals work in components, [LV] `view.ts:1789-1801`) |

**Recommendation: b.** It removes a throw-away step. "Proven on one nested table first, the fallback
kept" applies unchanged.

### 3. Keep "no live component per nested table"? (F10)

| Option | For | Against |
| --- | --- | --- |
| a. Keep (decided) | One mechanism in every mode; `attach` has no live component at all; already proven in a browser (R §10) | Portals inside streams are new upstream; missing-target throws; cleanup is ours |
| b. Nested live components inside the library | Per-table state and cleanup for free | `attach` would contain live components after all; two mechanisms |

**Recommendation: keep a.** The test cost is gone (the reading seam is built). Record your own
fallback (b) and its trigger in the target (F10).

### 4. Commands in tag mode (F14)

| Option | For | Against |
| --- | --- | --- |
| a. Commands only with `attach` (and inside the router page); the tag sends events only | Honest: one behaviour per command; no async surprise | A tag user who needs commands must switch to `attach` |
| b. Commands in tag mode too, through `send_update`: they return the socket unchanged and act later; `selected_records` answers with an event | All modes have commands | Same name, different timing per mode; harder to test |

**Recommendation: a.** It matches "the tag is a ready-made default wiring". A developer who wants
control uses `attach`.

### 5. When to fix the bulk locale bug (section 4)

| Option | For | Against |
| --- | --- | --- |
| a. Now, before the tag and stage 0: set the locale in the Task, plus one demo test in German | A real bug fixed with a small change; the new test also guards stage 3 | Work during the preparation ("no feature builds in parallel"; this is a fix, not a feature) |
| b. In stage 3b, by F2's design (terms from `Bulk.run`) | No extra change now | The bug stays through stages 0–3; stage 3 must then add a test (allowed: a new test, not a changed one) |

**Recommendation: a.** It is a few lines, and a new German bulk test pins behaviour across the refactor.

### 6. What the core returns for a cell: values or texts? (F2)

| Option | For | Against |
| --- | --- | --- |
| a. `Present` returns values and types; a translation step beside part 3 formats them (`Words`/`Format`) | Exactly your split; locale handled in one place | Each future adapter calls the server-side formatting step itself, or reimplements it |
| b. `Present` returns formatted texts (made in the LiveView process, never in a Task) | Simple for every adapter | The core holds wording, against your split |

**Recommendation: a**, with `Format` as a public helper of the drawing side, so an adapter reuses it.

---

## 6. Changes to the stage plan (target §9)

Revised order. Changes are in **bold**.

0. **Preparation (going on):** test seams (done in part), snapshots, performance baseline. **Refresh
   the target (F17, and the text changes of section 3 here). Bulk locale fix if question 5 is "a".**
   Tag.
1. **Stage 0, rename:** as listed, **plus Q2's private notifier tag** (`:ash_data_table_changed`),
   so no message name changes after stage 0 (M1).
2. **Stage 1, split:** as listed, **by line ranges refreshed against HEAD; `hideable/1` moves with
   the markup (F3). Hooks stay in the component module, so rendered `phx-hook` names stay (M2,
   test-coupling §3 stage 1).**
3. **Stage 1b, hooks to JS files (Q15):** **its own step. First check that a colocated hook that
   imports from the package works in a release build (owner's answer to Q15); snapshots normalise
   hook names.**
4. **Stage 2, one state value:** **`Live.Entry` and one `Table` value per live component. `@tables`
   stays (F5). `Caller` with reader values, time zone and functions, no assigns (F8);
   `Caller.reader_opts/1` produces today's `opts`; no 2a signature changes (F7).** `State` is
   wrapped, not replaced.
5. **Stage 3a:** `Present` (rows, cells, **the panel's fields and the picker, no sensitive value on any path: F1, decided**) and `Intent`. No behaviour
   change.
6. **Stage 3b:** `Operation` **with its input value (F9); outcomes as message terms, words made in
   the LiveView process (F2).** `Act`, `Edit`, `Pick`, `Bulk`, `Record` keep their arguments.
7. **Stage 3c:** `Live.Core` and `Live.Core.*` (private file splits); event names namespaced (through
   the test seam); the dependency test fails from here.
8. **Stage 4 and 5, in the order of question 2.** Recommended:
   - **5 first:** flat registry and portals inside today's top-level component; **proven on one
     nested table first; the fallback recorded (F10); `@tables` removed (V14); reconciling close
     (F11); one browser test per removal path.**
   - **then 4:** `attach`, `attached/1`, `Live.Page` on `attach`, the tag as one live component;
     **three-way runs on a chosen subset (F14).**
9. **Stage 6:** as listed, **with the veto and page values evaluated in the LiveView process before
   any async start (F8, F9); selection per question 1; commands per question 4; `:read` and
   `:selection_changed` details specified (F19); the record in an event scrubbed of sensitive values (F1).**
10. **Stage 7:** as listed, **plus the kit-evolution rule (F13) and presentation hints documented
    (F3).**

**Before stage 3**, the design note also gets the cross-cutting section (F18).

---

## 7. Missed by the critic, and its conceded points

### Missed

- **M1. Q2 is in no stage.** Q2 (taken as recommended) gives the notifier its own tag. Target §9
  stage 0 lists "Prefixes per Q3 (message tag, …)" but not Q2. test-coupling §3 stage 0 point 2:
  "Rename all of them in stage 0 … Then no later stage changes a name." If Q2 lands later, the
  root `live_updates_test.exs` lines that match `{:ash_table, …}` change twice. Fix: put it in stage
  0. Minor.
- **M2. The owner's answers are not in the stage plan.** Q15's answer asks "To verify early: a
  colocated hook importing from the package works in a release build". §9 stage 1 says only "Hooks
  moved with the markup, or to JS files per Q15". If the hooks move in stage 1, the rendered
  `phx-hook` names change (test-coupling §3 stage 1: `phx-hook=".Grid"` renders with the module
  name), and the snapshots break unless they normalise them. Fix: keep the hooks in place in stage 1;
  do the JS move as its own step with the release check (section 6, item 3). Minor.
- **M3. The owner's method for stage 5 is shortened in the target.** The method of 2026-10-14 says
  "proven on one nested table first, the fallback kept". §9 stage 5 has neither. Covered in F10's
  change. Minor.

### Conceded points

I checked each briefly. None is wrong.
- The portal depth limit ([LV] `dom_patch.ts:554-561`) applies to portals inside portals. Flat
  portals rendered parents first are teleported in one pass, in order, so the limit is not reached.
  Right.
- Two message tags: with Q2 a host matching `{:ash_data_table, …}` cannot catch notifier traffic.
  Right, but see M1 for when it is done.
- Q11/Q14: no stage needs a `Source` behaviour or a public data contract. Right.
- Moving `CellType`, `Operator`, `humanize` and the predicates to part 1 (V1–V5) is right.
- Streams vs `live_vue`: based on documentation, not tried, as the target itself says. Fine as a
  concession; not settled.
