# Test coupling before the refactor

This file says which tests are tied to internals and will break when code moves, not when behaviour changes. It is for the rule agreed on 2026-10-14: in stages 0–5 no existing test may change.

The stages: 0 rename to `ash_data_table`; 1 split `table_component.ex`; 2 all table state in one value; 3 the event handling as a core module; 4 `attach` and a plain function component; 5 nested tables and pickers through `<.portal>`, no live components.

How the numbers were found: grep over all three suites, then a script that reads every `test` block, the `setup` of its `describe`, and the private functions it calls. Counts are close, not exact: a name like `pick(` or the text `-t-` can match by chance. Every finding named with `file:line` was read by hand. Line numbers are of commit `c787bb8`.

## 1. Summary

### The suites

| Suite | Files | Tests | Public behaviour only | Coupled to something else |
| --- | --- | --- | --- | --- |
| Root `test/` | 21 | 1,056 | 452 | 604 call internal modules of part 2 |
| Demo `demo/test/` | 83 | 1,554 | 446 with no coupling at all, 682 without events, nesting or process | 844 send hook events by name; 298 look into a nested table or a picker |
| Browser `demo/e2e/` | 42 | 827 | about 800 | 3 reach into the hook object, 5 count hook style sheets, 3 use a page that mounts the live component directly, 7 check daisyUI classes |

The browser suite is in good shape. It finds almost everything by documented ids, roles and labels, through one class (`support/table.ts`). It is the safety net for stages 3–5 and should not change at all.

The demo suite is the risk. Almost everything goes through one module, `DemoWeb.TablePage` (`demo/test/support/table_page.ex`). That is good news: most fixes are in one file.

The root suite tests the modules of part 2 directly. Those modules do not move in stages 0–1. They are at risk in stage 2 (`State`, `Query`) and stage 3 (`Act`, `Edit`, `Pick`, `Bulk`, `Record`).

### Coupling by category

| Category | Root | Demo | Browser |
| --- | --- | --- | --- |
| 1. Public behaviour only | 452 | 446 (strict) | ~800 |
| 2. Internal modules or functions | 604 | 12 (+ 8 through a helper that calls `AshTable.Listener.flush/1`) | 0 |
| 3. The live component's state, process, events | 4 (`Listener`) | 844 (event names, 82 of them with `render_hook` written in the test), 173 (push events and replies), 21 (`wire`/`kept`), 2 (`send_update` traces) | 3 (`_ashTable`) |
| 4. Markup beyond the documented contract | 0 | 713 use a reading helper that relies on it; 193 have such a selector in the test itself | 5 (style sheets), 7 (classes), about 16 (child combinators) |
| 5. Mechanisms stage 5 changes | 4 | 298 (167 nested, 135 picker) | 3 (live component page); the 90 nested and 73 picker tests are the stage-5 acceptance tests |
| 6. Timing and process | 3 (100 ms batch) | 117 (`AshTable.Test.flush`, `ran/1`, telemetry, sleeps) | everything that waits on `aria-busy` (`reads`, `saves`, `acts`: 500 uses) |

### The five biggest risks

1. **The event protocol is written into 844 demo tests.** Helpers send `save`, `pick`, `act`, `toggle` and 20 other events with `render_hook` on `#ID-grid`, `#ID-panel` or `#ID-picker`. LiveViewTest routes them by the element's `phx-target`. Stage 3 may rename events or change payloads. Stage 4 removes the component target: the table must then be named in the payload, which no test sends. 82 tests in 30 files call `render_hook` themselves, outside the helper.
2. **LiveViewTest cannot see into a portal.** Checked: `LazyHTML.query/2` finds nothing inside a `<template>`, and `<.portal>` renders its content in a `<template data-phx-portal>`. After stage 5, about 298 demo tests that read or use a nested table or a picker fail. Worse, tests that assert a picker is *closed* (`picker(html) == nil`) pass for the wrong reason.
3. **604 root tests call part-2 functions directly.** They are good tests of pure logic. But stage 2 may reshape `%AshTable.State{}` and `Query.read/3`; stage 3 may reshape `Act`, `Edit`, `Pick`, `Bulk`. Every changed signature changes tests.
4. **The rename touches about 2,700 test lines** (2,373 `AshTable.` in root, about 215 in demo, 11 in e2e), and also wire names: push events `ash_table:*`, the PubSub message `{:ash_table, …}` and topic `ash_table:…`, config `:ash_table`, router metadata `ash_table:`, `data-ash-table`, `--ash-table-view`, `_ashTable`, `phoenix-colocated/ash_table`. If it is not one script, stage 0 cannot be checked.
5. **Tests that pin a mechanism, not a behaviour.** `send_update` traces (2 tests), listener counts per topic (8 + 4), two support pages that mount `AshTable.Live.TableComponent` with the internal `select` option (5 demo + 3 browser tests), a `phx-target` assertion (1), "every LiveView is rendered twice" read counts (`nested_table_reads_test.exs`, 7), and `kept/1`, which reads `live_components` and would quietly check less once state leaves component assigns.

A sixth risk, low for stages 0–5 and high for stage 7: the helpers rely on about 30 ids and 25 `data-*` attributes that the markup contract at the top of `table_component.ex` does not list (section 2.3). They are a contract in practice, but nowhere written down.

## 2. The helpers

A coupling in a helper counts for every test that uses it. "Users" counts tests that call the helper in their own body. Calls through `setup` or private functions add more.

### 2.1 `DemoWeb.TablePage` (`demo/test/support/table_page.ex`)

**Events sent with `render_hook` (category 3).**

| Helper | Lines | Sends | On | Users | Breaks in |
| --- | --- | --- | --- | --- | --- |
| `save/5` | 180–184 | `save` | `#ID-grid` | 168 | 3–4 |
| `clear/4`, `discard/4` | 193–197, 218–222 | `clear`, `discard` | `#ID-grid` | 8, 10 | 3–4 |
| `expand/3` | 229–231 | `expand` | `#ID-grid` | 114 | 3–4 |
| `toggle/4` | 241–247 | `toggle` + `render_async` | `#ID-grid` | 111 | 3–4; 5 (it opens a nested table) |
| `pick/4`, `edit/4` | 271–275, 423–427 | `pick`, `edit` | `#ID-grid` | 70, 78 | 3–4; 5 for `pick` |
| `act/4`, `dismiss/3`, `reveal/4` | 460–464, 616–618, 1049–1053 | `act`, `dismiss`, `reveal` | `#ID-grid` | 171, 2, 10 | 3–4 |
| `confirm_table_action/3`, `bulk/4`, `run_bulk/4` | 509–545 | `table_run`, `bulk`, `bulk_run` | `#ID-grid` | 7, 50, 53 | 3–4 |
| `clear_in_panel/3`, `unpick/4`, `add_group/3`, `remove_group/3`, `cancel_panel/2` | 204–212, 322–326, 437–450, 922–924 | `panel_*` | `[id='ID-panel']` | 7, 6, 20, 14, 31 | 3–4 |
| `picked/3`, `confirm_picked/3`, `picked_rows/3`, `cancel_picker/2` | 295–351 | `picked`, `picker_cancel` | `[id='ID-picker']` | 53, 3, 25, 16 | 3–4; 5 (the picker is in a portal) |

**Events through the markup (category 1, they survive).** `filter/4`, `argue/3`, `page_size/3`, `type_in_panel/3`, `run_panel/3`, `send_panel/3` use `form(...) |> render_change/submit`; `table_act/4`, `open_create/2`, `pick_input/3` use `render_click` on a button. LiveViewTest reads the event and target from the markup, so these keep working when names or targets change, as long as the markup says so. `page_size/3` (46) uses the undocumented id `ID-page-size-form` and the field name `size`.

**Waiting (category 6).** `ran/1` (551–554) calls `render_async` exactly twice: once for the action, once for the read after it. It is used by `table_act`, `confirm_table_action`, `run_bulk` and in 34 tests directly. If stage 3 or 4 chains the work differently (one hop more), `ran/1` returns too early.

**Reading with structure beyond the contract (category 4).** They pass while the markup stays identical, which is the point of stages 0–5. The markup snapshots guard them. They matter for stage 7.

| Helper | Lines | Relies on | Users | Also breaks in |
| --- | --- | --- | --- | --- |
| `lines/3` | 257–261 | `-x > tr > td[data-line] > div > button[aria-expanded]` | 26 | — |
| `picker/2` | 359–381 | `> div[id^='ID-pick-']`, `> div:last-child > button`, `data-question` | 75 | 5 |
| `current/2` | 387–393 | `-table > tbody[data-current]` | 11 | 5 (it reads the picker's table) |
| `table_actions/2` | 470–474 | `[id='ID'] > div button[data-table-action]` | 10 | — |
| `line_buttons/4` | 481–485 | `-l-NAME-c > div > button:not([aria-expanded])` | 6 | — |
| `arguments/2` | 96–166 | `> [data-argument]`, `data-label`, `data-error`, tag names `select`/`input`/`div` | 20 | — |
| `panel/2` | 668–886 | `data-field`, `data-group(s)`, `data-union`, `data-references`, `data-list`, `data-item`, `data-cleared`, `data-key`, `data-chosen`; direct children; tag `div`; ids ending `-error` and `-label`; **the CSS class `.sr-only`** as the sign of "required" (746, 772, 785, 845) | 245 | — |
| `actions/3`, `box/2`, `radio/2` | 935–939, 607–610 | `-a > button`, `-s > input` | 20, 4, 0 | — |
| `editor/3`, `editors/2` | 942–1012 | `template[id='ID-editor-F']` and its content, `data-editor`, `[data-list] > template`, `data-remove`, `data-add`, `data-confirm` | 18, 53 | — |
| `failure/4`, `action_failure/3` | 1019–1041, 624–632 | children of the `<td>`, `aria-describedby` | 85, 16 | — |
| `masked/4` | 1061–1080 | `data-reveal`, `data-mask`, `data-masked`, `data-secret` | 18 | — |
| `filter_controls/3` | 1143–1155 | `select[id$='-operator']`, `select[id$='-value']` | 27 | — |
| `selection/2`, `bulk_result/2`, `result/2` | 565–604, 515 | `data-more`, `data-selected`, `data-all`, `data-summary`, `data-failure` | 23, 62, 37 | — |

`headers/2`, `column/3`, `cell/3`, `announcement/2`, `nested/3` and `text`/`attribute` rely on documented ids and on "every row is one `<tbody>`" (documented). They are fine. `nested/3` (254) builds `ID-row-KEY-t-REL`: documented, but stage 5 must keep that id.

**The process (category 3).**

| Helper | Lines | What it does | Users | Risk |
| --- | --- | --- | --- | --- |
| `wire/2` | 1087–1107 | traces every message the LiveView process sends | 20 | Survives while the table runs in the LiveView's process. |
| `kept/1` | 1113–1123 | `Phoenix.LiveView.Debug.socket` and `.live_components`, all assigns as text | 2 (`project_budget_test.exs:275`, `live_updates_elsewhere_test.exs:168`) | Stage 4–5: no components any more. It still passes, but if table state moves into the process dictionary or a registry (stage 5's "flat registry"), it no longer looks there. It already misses today's `@tables` in the process dictionary. |

**The fix for this file.** It already is the one place. Give it two private seams, and move the stray calls into it:

- `send_event(view, id, event, payload)`: the one function that sends a hook's event. Today it is `element("##{id}-grid") |> render_hook(event, payload)` (or `-panel`, `-picker`). In stage 4 or 5 it changes once (for example to `render_hook(view, event, Map.put(payload, "table", id))`). A public `forge/4` on top of it serves the tests that send events a browser never sends.
- `query/2` (1160): every reader already goes through it. Add portal resolution now: put the content of each `template[data-phx-portal]` at its target before querying. Today it does nothing. In stage 5 it lets every reader see nested tables and pickers.

### 2.2 Demo support pages that mount the live component

| File | Line | Used by | Breaks in |
| --- | --- | --- | --- |
| `demo/test/support/bulk_tables.ex` (`DemoWeb.Support.SelectLive`, `/support/select`) | 321–337 | `bulk_elsewhere_test.exs` 844, 869, 877, 887, 895 (5 tests) | 1 if the module is renamed or split; 4–5 for sure |
| `demo/e2e/server/select_live.ex` (`/e2e/select`) | 44–58 | `selection.spec.ts` 1023, 1084, 1105 (3 tests) | the same |

Both pass `select`, `mounted?`, `url` and the rest by hand to `AshTable.Live.TableComponent`. `select` is not an attribute of `AshTable.table/1` (`lib/ash_table.ex:126–171`).

Fix before stage 0: give `AshTable.table/1` a `select` attribute (`@doc false` is enough) and let both pages use `<AshTable.table>`.

### 2.3 `Table` (`demo/e2e/support/table.ts`)

Almost all of it finds parts by id. The couplings:

| What | Lines | Category | Users | Breaks in |
| --- | --- | --- | --- | --- |
| `busyThenIdle`: waits for `aria-busy` to go on and off, `window.__ashTableIdle` | 59–77 | 6 | `reads` 316 uses, `saves` 135, `acts` 49, in 27 files | 3–4 if a read ever finishes without a busy phase (it then hangs); 5 if a nested grid's node is replaced while observed |
| `columnRules`, `ownedSheets`: `document.adoptedStyleSheets`, `[data-ash-table]` | 946–961 | 4 | 5 tests: `resizing.spec.ts:425,439`, `hiding.spec.ts:609,625`, `scrolling.spec.ts:280` | 0 if `data-ash-table` is renamed; 5 if teleporting mounts a hook again |
| `tabStops()` filters by `dialog:not([open])`, `form[data-arguments]`, `[data-columns-button]` | 904–925 | 4 | 127 uses, 24 files | 7 |
| `rows`, `boxes`, `radios`, `expanders`, `openEditors`, `columnCells`, `headerCells`: `:scope > tbody:not([data-detail]) > tr > td[data-selector]` and the like | 149–311, 440, 558, 624, 782 | 4 | about 200 uses | 7 |
| `tableActions`: `root :scope > div button[data-table-action]` | 493 | 4 | 7 | 4 if the root element changes |
| `rowIndexes`, `selectedKeys`: `tbody.rows[0]` | 537–581 | 4 | 101 | 7 |
| `failure(cell)`: `[popover]` | 463–465 | 4 | 68 | 7 |
| `panelSettled`: LiveView's `phx-change-loading` class | 733–735 | 6 | 54 | — (LiveView's own) |

Undocumented ids and attributes it uses (found by comparing with the contract comment at the top of `table_component.ex`): `ID-table`, `ID-row-KEY-r`, `-e`, `-a-ACTION`, `ID-header`, `ID-create`, `ID-dialog`, `ID-empty`, `ID-error`, `ID-status`, `ID-pagination`, `ID-range`, `ID-page-size`, `ID-pager`, `ID-loading`, `ID-columns-status`, `ID-clear-filters`, `ID-actions-head`, `ID-actions-filter`, `ID-panel-title`, `-form`, `-errors`, `-cancel`, `-submit`, `-f-NAME-chosen`, `ID-picker-title`, `ID-picker-error`, `ID-related-parent`, `ID-row-KEY-l-REL-create`; `data-detail`, `data-selector`, `data-expander`, `data-line`, `data-table-action`, `data-action`, `data-bulk`, `data-flag`, `data-field`, `data-key`, `data-chosen`, `data-arguments`, `data-columns-button`, `data-ash-table`. `ID-name` is documented in `layout-and-embedding.md`. The demo helper adds `data-argument`, `data-label`, `data-error`, `data-group`, `data-groups`, `data-group-item`, `data-union`, `data-references`, `data-list`, `data-item`, `data-cleared`, `data-mask`, `data-masked`, `data-more`, `data-all`, `data-failure`, `data-remove`, `data-add`, `data-clear-field`.

Fix before stage 0: write them into the contract comment (or a guide). No code changes. Then the snapshots and these helpers check one written contract.

### 2.4 Other support

- `demo/e2e/support/a11y.ts:47`: `td[data-nested] [data-ash-table]`. Stage 0 if the attribute is renamed. Fine in stage 5: the teleported grid ends up inside the cell.
- `test/support/*.ex`: resources named `AshTable.Test.*`. Stage 0 only. `test/support/limiting.ex:55` names `AshTable.Model.Limits` in a comment.
- `demo/test/support/argument_tables.ex:35–47` (`Demo.Support.Hold`) and `bulk_tables.ex:141` (`Process.sleep(300)`) hold a read or an action back so that a test sees the table while it is busy. They depend on reads being async (category 6). Users: `argument_line_test.exs:71`, `bulk_elsewhere_test.exs:496–539`.

## 3. Stage by stage

### Stage 0: rename

Everything with the old name:

| Kind | Root | Demo | Browser |
| --- | --- | --- | --- |
| `AshTable.` modules (with `AshTable.Test.*` and `AshTable.*Test`) | 2,373 lines, 48 files | 156 lines, 37 files | 3 (comments) |
| `ash_table:` push events and topics; `{:ash_table, …}` messages | `live_updates_test.exs` 157, 346–351, 377–507 | `live_updates_test.exs`, `live_updates_elsewhere_test.exs`, `task_bulk_test.exs`, `bulk_elsewhere_test.exs`, `table_actions_test.exs`, `label_actions_test.exs`, `argument_line_test.exs` (28 lines) | `selection.spec.ts:1012` (`ash_table:selection`) |
| config and metadata `:ash_table` | `named_tables_test.exs:971–990`, `live_updates_test.exs:335–338` | `translation_settings_test.exs:34–36`, `unchecked_table_test.exs:383–393` | — |
| texts that name the library | `table_block_test.exs:5363`, `documentation_test.exs:33, 46, 220–222` | `named_table_test.exs:194`, `unchecked_table_test.exs:392`, `footer_summaries_test.exs:678` | page titles "ash_table demo" (`dashboard.spec.ts:37`, `tables.spec.ts:104`, `locale.spec.ts:81–131`) |
| installer output | `test/mix/tasks/ash_table.install_test.exs` (26 tests: `phoenix-colocated/ash_table`, `ashTableHooks`) | — | — |
| browser names | — | `sideways_scroll_test.exs:63` (`--ash-table-view`) | `_ashTable` (`hiding.spec.ts:552,733,760`, `actions.spec.ts:989`), `data-ash-table` (`table.ts:959`, `a11y.ts:47`), `__ashTableIdle` (`table.ts:63,76`) |
| file names | `test/mix/tasks/ash_table.install_test.exs`, the tutorial `get-started-with-ash-table.md`, `priv/gettext/ash_table.pot`, `demo/priv/gettext/de/LC_MESSAGES/ash_table.po` | | |

How to keep it mechanical:

1. Write it as one script in the repository (`scripts/rename.sh`): ordered replacements `AshTable` → `AshDataTable`, `ash_table` → `ash_data_table`, `ash-table` → `ash-data-table`, `ashTable` → `ashDataTable`, then `git mv` of the files above.
2. Decide once which wire names go with it. Rename all of them in stage 0 (push events, PubSub message and topic, `data-ash-table`, `--ash-table-view`, the router macro, the config key). Then no later stage changes a name.
3. Leave out what is not the library: the demo's title "ash_table demo", the GitHub URL until the repository is renamed, issue numbers in texts.
4. The rule for stage 0: the diff of the tests is exactly what the script produces. Check it by running the script on the tag before stage 0 and comparing.

### Stage 1: split the component

No test calls a function of `table_component.ex`. What can break:

- The two support pages name `AshTable.Live.TableComponent` (5 demo + 3 browser tests). Keep that module as the entry point in stage 1, or do fix 2.2 first.
- The rendered `phx-hook` holds the module's name (`phx-hook=".Grid"` renders as `…TableComponent.Grid`, line 4495). If the hooks move to another module, a markup snapshot changes, although nothing a person sees does. The snapshots must ignore hook names, or the hooks stay in the module.
- Markup that changes by accident while function components move: only the snapshots see that today. 713 demo tests read through helpers that rely on exact structure.

### Stage 2: one state value

- `kept/1` (2 tests): still passes. Check by hand that the new value is in what it inspects.
- Root tests that build `%AshTable.State{}` or call `State.*` and `Query.read/3`, `Query.summaries/4`: `filter_values_test.exs` (13), `model_test.exs` (about 35), `summaries_test.exs` (26), `table_block_test.exs` (3), `sensitive_test.exs` (1), `reference_test.exs` (1); demo `footer_summaries_test.exs:328–346, 593–599` (2).
- They do not break if the new value holds a `%State{}` and `State` keeps its functions. Recommended: wrap, do not replace.

### Stage 3: the core module

- Event names, payloads and replies. 844 demo tests send events by name (82 of them with `render_hook` in the test itself, in 30 files, listed in the appendix). 173 tests check `assert_push_event` or `assert_reply` payloads. Browser: `hiding.spec.ts:552,733,760` call `root._ashTable.pushEventTo(root, "sort", …)`, `actions.spec.ts:989` calls `grid._ashTable.ask(…)`.
- Root tests that call `Act`, `Edit`, `Pick`, `Bulk`, `Record`: `files_test.exs` (9), `managing_test.exs` (26), `pick_test.exs` (16), `reference_test.exs` (8), `sensitive_test.exs` (about 15), `unions_test.exs` (about 12), `model_test.exs` (about 22). About 110 tests. They survive if the core calls these modules and their functions keep their arguments.
- `ran/1` and the browser's `busyThenIdle` count on a read being async and marked busy.

### Stage 4: `attach` and a function component

- `render_hook` on an element today goes to the element's `phx-target`, the component. Without a component it goes to the LiveView. That works only if the event still says which table it is for. If the hook adds the table to the payload, every event sent by a test lacks it: all 844 tests, unless the seam of 2.1 is there.
- Host events of the same name (`save`, `sort`, `filter`) would collide with the table's. If stage 4 prefixes the names for that reason, see stage 3.
- `AshTable.Router.__live_opts__/2` and `AshTable.Routes`: root `named_tables_test.exs` (5 with `Routes.default_id`, 971–1003), `live_updates_test.exs:335–338`; demo `unchecked_table_test.exs:347–393` (2 tests).
- `send_update` traces: `live_updates_test.exs:527` refutes a `{:phoenix, :send_update, _}` (it then passes for nothing); `live_updates_test.exs:561` expects exactly one (it then fails). A listener cannot `send_update` a function component.
- `nested_table_reads_test.exs:86` counts the reads of "every LiveView is rendered twice". If `attach` reads only when connected, the number changes. The other 6 tests of that file count reads after an event and should hold.
- The support pages of 2.2 (8 tests).
- The installer test (26) if the installer has to write something new.

### Stage 5: nested tables and pickers through the portal

- **LiveViewTest cannot see into a portal.** `<.portal>` renders `<template id=… data-phx-portal=…>` (`phoenix_component.ex:3601–3615`), the browser moves it. LiveViewTest does not: there is no portal handling in `phoenix_live_view/test/` (1.2.12), and `LazyHTML.query/2` finds nothing inside a `<template>` (tried: `{0, 1}` for the table inside and the template). So `element/2`, `has_element?/2` and every `TablePage` reader miss the nested table and the picker.
- That is 298 demo tests: 167 that read or use a nested table, 135 a picker (listed in appendix B). Some only assert that nothing is open (`picker(html) == nil`); those keep passing for the wrong reason.
- `table_actions_test.exs:470` asserts `phx-target == ["#rota-row-…-t-shifts"]` on a line button.
- `sideways_scroll_test.exs:52`: `#{cell} > div > div > [id='…']`. The portal wraps its content in one more `div` (`_lv_portal_wrap_…`).
- Listener counts per topic, if a flat registry listens once per page: demo `live_updates_test.exs` 666, 927, 981, 987 and `live_updates_elsewhere_test.exs` 207, 222, 243, 260 (8, through `AshTable.Listener.flush/1` and `Registry.lookup`); root `live_updates_test.exs` 445, 490, 515, 540 (4, `Listener.start/3`, `of/1`, `flush/1`, `stop/1`).
- Browser: the 90 nested and 73 picker tests use ids and roles only and are the acceptance test of stage 5. Watch `ownedSheets` (5 tests, if a teleported grid's hook mounts twice) and `busyThenIdle` on a nested grid whose node is replaced.
- If the action panel is also put in a portal, 245 more demo tests (`panel/2`) are affected. Keep the panel out of stage 5, or rely on the seam.

### Tests per stage, if nothing is done first

| Stage | Root | Demo | Browser |
| --- | --- | --- | --- |
| 0 rename | 48 files (all that name a module) | 37 files | 6 files |
| 1 split | 0 | 5 (support page) | 3 (support page) |
| 2 one state value | about 79, only if `State`/`Query` change shape | 2 | 0 |
| 3 core | about 110, only if `Act`/`Edit`/`Pick`/`Bulk` change | up to 844 if names or payloads change | 3 |
| 4 attach | 8 | up to 844 (target), + 2 + 1 + 2 + 5 | 3 + 3 |
| 5 portal | 4 | 298 + 1 + 1 + 8 | 0 expected; 5 to watch |

## 4. Recommendations, in order

### Before stage 0 (test work, allowed now)

1. **Write down the contract the tests already use.** Add the ids and `data-*` attributes of 2.3 to the markup contract at the top of `table_component.ex`. Also the hook's event protocol: each event, its payload, its reply. No code changes.
2. **One seam for events** (2.1): `send_event/4` and `forge/4` in `TablePage`. Move the 82 `render_hook` calls of the test files onto `forge/4`, and the `left/2` helpers of both live-update tests (`live_updates_test.exs:83–92`, `live_updates_elsewhere_test.exs:51–60`). In the browser suite add `Table.forge(event, payload)` and `Table.ask(question, danger)` and use them at `hiding.spec.ts:552,733,760` and `actions.spec.ts:989`.
3. **One seam for reading** (2.1): portal resolution in `TablePage.query/2`. Add `click(view, selector)` and `has?(view, selector)` that read the resolved markup and send the button's `phx-click` with its `phx-value-*` through `send_event/4`. Move the clicks on nested and picker elements onto them (for example `nested_table_reads_test.exs:186`).
4. **Make `ran/1` wait until the table is idle**, not for a fixed number of async hops. `render_async` until the grid has no `aria-busy`.
5. **Replace the support pages' `live_component`** with `<AshTable.table select={…}>` (2.2). Needs a `select` attribute on `AshTable.table/1`: a small library change.
6. **Rewrite the mechanism tests as behaviour:**
   - `live_updates_test.exs:527, 561`: instead of `send_update` traces, assert that the table reads nothing and sends no diff (`wire/2` and Ash read telemetry).
   - The listener counts (8 demo tests): count through a public test function, for example `AshTable.Test.listening(topic)`, so that the count can change its meaning in one place.
   - `table_actions_test.exs:470`: drop the `phx-target` check; the tests that click the button and see the nested table's action run already prove it.
   - `kept/1`: also inspect `Process.info(view.pid, :dictionary)`, so it keeps looking wherever state goes.
7. **Write the rename script** (stage 0 above) and agree which wire names change.

### Done (2026-10-14)

The eight steps were done on `main`, one commit each. Line numbers above are still those of `c787bb8`.

1. **Contract** (`ceb9ad5`). The comment at the top of `table_component.ex` has two new sections: "What the tests rely on besides" (the ids and `data-*` attributes of 2.3, checked against the markup) and "Events" (every event the hooks and the markup send, its payload and answer; every `push_event`; the DOM events between hooks).
2. **Event seam** (`6ffac50`). `TablePage.send_event/5` (private) is the one place that sends an event: from the element of the hook that sends it in a browser (panel events from `ID-panel`, picker events from `ID-picker`, the rest from `ID-grid`). The public `forge/5` takes `on: :grid | :panel | :picker` for an event sent from elsewhere. The test files had 60 `render_hook` calls (58 in 26 files plus the two `left/1` helpers), not 82 in 30: all go through `forge`. Browser: `Table.forge(event, payload)` and `Table.ask(question, danger)`; `hiding.spec.ts` and `actions.spec.ts` use them, and no spec reaches `_ashTable` any more.
3. **Read seam** (`0ff2672`). `query/2` puts the content of every `template[data-phx-portal]` at the end of its target (by the target's id, as LiveView 1.2.12's client does, up to five rounds) and empties the template; checked by `demo/test/demo_web/table_page_test.exs` on markup shaped like `<.portal>`'s. `click/2` sends an element's `phx-click` (a name or a `JS` push) with its `phx-value-*` through `send_event` to the table its `phx-target` names (a cid via the grid with that `phx-target`, or a `#ID` selector); `has?/3` checks presence on the resolved markup. 30 clicks on controls inside nested tables and pickers, and on line buttons that target a nested table, use `click/2`; `table_act`, `open_create` and `pick_input` use it too; one `render_submit` on a nested panel form became `send_panel/3`. No test used `has_element?` on a nested table or a picker: presence checks already went through the readers. **Not done:** the form helpers (`filter`, `argue`, `page_size`, `type_in_panel`, `run_panel`, `send_panel`) still use `Phoenix.LiveViewTest.form/3` and `element/2`, which do not see into a portal. They are in the seam module (group I); stage 5 changes them there, no test body.
4. **`ran/1`** (`5bd2686`) calls `render_async` until no element of the page says `aria-busy` (tables while they read or run, footer cells while summaries come), at most 20 rounds.
5. **`select`** (`0393585`). `AshTable.table/1` has `attr :select` (`doc: false`); `/support/select` and `/e2e/select` use the tag.
6. **Mechanism tests** (`c351c00`).
   - `live_updates_test.exs` "are not announced to the table that made them" and "…whichever way it writes": before, a trace of `{:phoenix, :send_update, _}` received by the LiveView; after, `handed/2` runs the write, lets what it started finish, then flushes and records the Ash reads of the LiveView's process (and its tasks) and the diffs it sends (`wire/2`): `%{reads: [], diffs: 0}` for the table's own writes, reads and diffs for another person's change. Checked once by mutation: with the notifier's `origin` dropped, both fail.
   - Listener counts: `AshTable.Test.listening(resource, tenant \\ nil)` (library, public). The demo's `listeners/1` helpers in both live-update files call it. In the root suite only "ends when it is stopped…" counted listeners; it uses `listening/1` now. The other three root tests (445, 490, 540) test `AshTable.Listener` itself and stay in group G.
   - `table_actions_test.exs:470`: the `phx-target` assertion is gone; "run on the nested table…" (the next test) runs the button and sees the nested table's result.
   - `kept/1` also inspects the LiveView's process dictionary, `@tables` among it.
7. **Rename script** (`9d7211c`): `scripts/rename_to_ash_data_table.sh`, `--check` for a dry run. Its head lists every exclusion and why. Tried on a copy of `ceb9ad5`: root and demo compile with `--warnings-as-errors`, the root suite passes (1,162 tests), a second run changes nothing.
8. **Snapshots and baseline** (`142c393`). 16 files in `demo/test/snapshots/` for the ten states of "Markup snapshots" (state 6 is two files, 7 three, 9 four). Normalised besides the rules above: the per-test part of emails, every uuid by its first place. The projects' fields that the generator derives from ids or from today are fixed in the test; the union's state is the panel alone, as a specimen's other fields follow from today. Two captures were identical, and the comparison passed twice. The performance baseline is in [baseline.md](baseline.md).

### What to accept as "expected to change in stage N"

Each group needs the owner's yes. Everything not listed must stay unchanged.

| Group | Stage | Tests | Why |
| --- | --- | --- | --- |
| A. The rename | 0 | every file that names `AshTable`, `ash_table`, `ash-table`, `ashTable` (48 root, 37 demo, 6 browser files) | Mechanical: the diff must equal the script's output. |
| B. `State` and `Query` callers | 2 | root `filter_values_test` 13, `model_test` ~35, `summaries_test` 26, `table_block_test` 3, `sensitive_test` 1, `reference_test` 1; demo `footer_summaries_test` 2 | Only if the new state value cannot hold `%State{}`. Better avoided. |
| C. `Act`, `Edit`, `Pick`, `Bulk`, `Record` callers | 3 | root ~110 (files, managing, pick, reference, sensitive, unions, model) | Only if the core changes their arguments. |
| D. Router and routes internals | 4 | root `named_tables_test` 5, `live_updates_test` 1 (335–338); demo `unchecked_table_test` 2 | `__live_opts__/2` and `Routes` are part of the wiring stage 4 rebuilds. |
| E. Rendered twice | 4 | `nested_table_reads_test.exs:86` (1) | Only if `attach` stops reading in the dead render. That is a behaviour change too, and should be a decision. |
| F. The installer's output | 4 | `ash_table.install_test.exs` (26) | Only if the host needs a new line. |
| G. The listener | 5 | root `live_updates_test.exs` 445, 490, 515, 540 (4) | A flat registry may replace one listener per table. |
| H. Wrapper of the portal | 5 | `sideways_scroll_test.exs:52` (1) | The portal adds an element around the nested table. |
| I. The seams themselves | 3–5 | the private functions `send_event/4` and `query/2` of `TablePage`, `Table.forge` | The one place allowed to change; no test body changes. |
| J. If recommendation 3 is not done | 5 | the 298 demo tests of appendix B | Not recommended: it would remove the server-side tests of nested tables and pickers during the stage that changes them. |

### New tests to add first

**Markup snapshots.** About ten states, rendered by LiveViewTest, stored as files, compared on every run. Normalise before comparing: `phx-hook` names, `phx-target` values, `data-phx-*` attributes, the LiveView's own ids, CSRF tokens, record keys and timestamps. Take the states that cover what stages 1–5 move:

1. `/tasks` first page as the member: header, filter row, page size menu, pagination, footer summaries, boxes, expanders, actions column, reference cells, editor templates. (Most of `render/1`.)
2. The same after a sort, a filter with a pending operator, page 2 and a size from the URL. (State and URL: stage 2.)
3. A task expanded, its comments line open, its nested table with pager and full-view link. (Stage 5.)
4. Two levels deep (task → comment → author), at the depth limit. (Stage 5, the flat registry.)
5. The picker open on a reference cell, with the current row marked. (Stage 5.)
6. The create panel with a reference field, and the picker for several records over it (task labels). (Panel and picker together.)
7. A map cell's panel with groups, and a union's panel (`/support/sites`, specimen). (The largest function components.)
8. A failed cell save and a failed row action. (Errors as data: stage 3.)
9. After a bulk run with failures and a table action's result; the argument line with a refused value and the fill message. (Stage 3 replies.)
10. The dashboard: two embedded `<AshTable.table>`, one with a sensitive column masked, and a live-update notice after `AshTable.Test.flush/1`. (Stage 4: the function component on a host page.)

**Performance baseline.** Agreed: update sizes and times for a cell save, a page change, and expanding a row. `demo/perf/` already has scripts (`measure.mjs`, `nested.mjs`, `/perf/probe`). Add opening a nested table and opening the picker, the two paths stage 5 changes. Keep `wire/2` sizes of the same three events as a server-side number that needs no browser.

## Appendix A: root suite

"Internal" counts tests that call a part-2 module. Pure functions that only move with their module are marked "survives".

| File | Tests | Internal | What they call | Stage at risk |
| --- | --- | --- | --- | --- |
| `component_test.exs` | 7 | 0 | `render_component` of a column component | 0 |
| `documentation_test.exs` | 18 | 0 | guides, repository URL, `app: :ash_table` (220–222) | 0 |
| `domain_block_test.exs` | 5 | 0 | `Domain.Info` | 0 |
| `files_test.exs` | 14 | 9 | `Act.submit_row/submit_create/submit_generic/values/errors`, `Bulk.run`, `Resource.Acting.file?`, `Resource.Uploading.limits` | 0, 3 |
| `filter_values_test.exs` | 33 | 13 | `%State{}`, `State.from_params/fit/pending`, `Query.read`, `Model.Operator.*` (survives) | 0, 2 |
| `fragments_test.exs` | 7 | 2 | `Model.build`, `Model.naming` (survives) | 0 |
| `image_component_test.exs` | 7 | 1 | `Model.build` (survives) | 0 |
| `limits_test.exs` | 36 | 30 | `Model.Limits.of/count/counted` (survives) | 0 |
| `live_updates_test.exs` | 24 | 11 | `Listener.start/stop/of/flush` (445–540), `Query.reader_opts` (406), `Resource.Listening.*`, `Router.__live_opts__` (335), `Notifier.topic` (346) | 0, 4, 5 |
| `long_text_test.exs` | 8 | 5 | `Model.build`, `Resource.Presenting.max_lines` (survives) | 0 |
| `managing_test.exs` | 47 | 26 | `Act.*`, `Edit.refer`, `Pick.related`, `Resource.Managing.*` | 0, 3 |
| `mix/tasks/ash_table.install_test.exs` | 26 | 0 | installer output | 0, 4? |
| `model_test.exs` | 370 | 272 | `Model.*` (192, survives), `State` (23), `Query` (12), `Format` (23, survives), `Act` (18), `Bulk`, `Record`, `Errors` | 0, 2, 3 |
| `named_tables_test.exs` | 38 | 16 | `Model.build` (survives), `Routes.default_id` (5), `Router.__live_opts__` (971–990) | 0, 4 |
| `pick_test.exs` | 16 | 16 | `Pick.chosen/current/value/reader` | 0, 3 |
| `reference_test.exs` | 18 | 8 | `Act.submit_row/submit_generic`, `Bulk.run`, `%State{}` | 0, 2, 3 |
| `sensitive_test.exs` | 47 | 33 | `Sensitive.scrub` (survives), `Edit.save/clear`, `Act.clearable/values`, `Format` | 0, 3 |
| `summaries_test.exs` | 26 | 26 | `Query.summaries`, `%State{}`, `Model.summarised`, `Format.summary` | 0, 2 |
| `table_block_test.exs` | 236 | 105 | `Model.build` (survives), `Query.summaries` + `%State{}` (3) | 0, 2 |
| `unions_test.exs` | 49 | 31 | `Format` (survives), `Act.typed/sent/kind/values`, `Edit`, `Resource.Embedding` | 0, 3 |
| **Total** | **1,056** | **604** | | |

## Appendix B: demo suite

Columns: **Public** has no coupling the script finds. **Events** sends hook events by name (in brackets: with `render_hook` in the test itself). **Markup** has a class, child combinator, tag tree or `aria-colindex` selector in the test. **Nested/picker** reads or uses a nested table or a picker (stage 5). **Process/timing**: `flush`, `wire`, `kept`, telemetry, sleeps, `ran`. **Internal**: an internal module. **Push**: `assert_push_event` or `assert_reply`. "3–4" means: breaks only if the event protocol changes and the seam is not there.

| File | Tests | Public | Events | Markup | Nested/picker | Process/timing | Internal | Push | Stage at risk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| controllers/error_html_test.exs | 2 | 2 | 0 (0) | 0 | 0 | 0 | 0 | 0 | — |
| controllers/error_json_test.exs | 2 | 2 | 0 (0) | 0 | 0 | 0 | 0 | 0 | — |
| live/home_live_test.exs | 5 | 5 | 0 (0) | 0 | 0 | 0 | 0 | 0 | — |
| tables/action_fields_test.exs | 13 | 0 | 10 (0) | 1 | 1 | 0 | 0 | 0 | 3–4, 5 |
| tables/actions_elsewhere_test.exs | 13 | 0 | 10 (0) | 4 | 4 | 0 | 0 | 0 | 3–4, 5 |
| tables/argument_line_test.exs | 58 | 19 | 17 (3) | 1 | 11 | 0 | 0 | 5 | 0, 3–4, 5 |
| tables/array_table_test.exs | 53 | 9 | 36 (1) | 5 | 0 | 0 | 0 | 0 | 3–4 |
| tables/bulk_elsewhere_test.exs | 39 | 4 | 28 (2) | 2 | 1 | 5 | 0 | 10 | 0, 1, 3–4, 4, 5 |
| tables/column_hiding_test.exs | 17 | 8 | 2 (0) | 9 | 2 | 0 | 0 | 0 | 3–4, 5 |
| tables/column_resize_test.exs | 7 | 2 | 1 (0) | 5 | 1 | 0 | 0 | 0 | 3–4, 5 |
| tables/comment_table_test.exs | 12 | 11 | 0 (0) | 1 | 0 | 0 | 0 | 0 | — |
| tables/component_table_test.exs | 21 | 2 | 10 (1) | 16 | 0 | 0 | 0 | 0 | 3–4 |
| tables/deadline_assignee_test.exs | 9 | 0 | 8 (0) | 0 | 8 | 0 | 0 | 7 | 3–4, 5 |
| tables/deadline_table_test.exs | 11 | 6 | 2 (0) | 0 | 1 | 0 | 0 | 1 | 3–4, 5 |
| tables/domain_settings_test.exs | 16 | 13 | 2 (0) | 0 | 0 | 0 | 0 | 0 | 0, 3–4 |
| tables/embedded_table_test.exs | 12 | 10 | 2 (0) | 0 | 0 | 0 | 0 | 0 | 0, 3–4 |
| tables/embedded_url_table_test.exs | 7 | 7 | 0 (0) | 0 | 0 | 0 | 0 | 0 | 0 |
| tables/failed_read_test.exs | 12 | 12 | 0 (0) | 0 | 0 | 0 | 0 | 0 | — |
| tables/file_actions_test.exs | 21 | 0 | 19 (0) | 2 | 0 | 3 | 0 | 2 | 3–4 |
| tables/file_two_tables_test.exs | 4 | 0 | 4 (0) | 4 | 0 | 0 | 0 | 0 | 3–4 |
| tables/filter_values_test.exs | 34 | 30 | 0 (0) | 4 | 0 | 1 | 0 | 0 | 0 |
| tables/footer_summaries_test.exs | 28 | 12 | 6 (0) | 8 | 3 | 1 | 2 | 1 | 0, 2, 3–4, 5 |
| tables/full_view_link_test.exs | 9 | 1 | 8 (0) | 1 | 8 | 0 | 0 | 0 | 0, 3–4, 5 |
| tables/full_view_states_test.exs | 9 | 8 | 1 (0) | 0 | 1 | 0 | 0 | 0 | 0, 3–4, 5 |
| tables/full_view_test.exs | 30 | 27 | 3 (0) | 0 | 2 | 0 | 0 | 0 | 0, 3–4, 5 |
| tables/image_table_test.exs | 3 | 0 | 1 (0) | 3 | 0 | 0 | 0 | 0 | 0, 3–4 |
| tables/label_actions_test.exs | 14 | 1 | 7 (1) | 1 | 2 | 4 | 0 | 1 | 0, 3–4, 5 |
| tables/label_import_test.exs | 13 | 0 | 2 (0) | 1 | 1 | 1 | 0 | 0 | 3–4, 5 |
| tables/label_table_test.exs | 1 | 1 | 0 (0) | 0 | 0 | 0 | 0 | 0 | — |
| tables/layout_test.exs | 3 | 3 | 0 (0) | 0 | 0 | 0 | 0 | 0 | 0 |
| tables/ledger_default_config_test.exs | 2 | 1 | 1 (1) | 0 | 1 | 0 | 0 | 0 | 3–4, 5 |
| tables/ledger_table_test.exs | 17 | 9 | 8 (3) | 1 | 4 | 0 | 0 | 0 | 3–4, 5 |
| tables/live_updates_elsewhere_test.exs | 17 | 0 | 11 (11) | 5 | 3 | 17 | 4 | 12 | 0, 3–4, 5 |
| tables/live_updates_test.exs | 45 | 6 | 36 (32) | 15 | 11 | 38 | 4 | 31 | 0, 3–4, 4, 5 |
| tables/long_text_table_test.exs | 7 | 2 | 2 (0) | 5 | 1 | 0 | 0 | 0 | 3–4, 5 |
| tables/managed_relationships_test.exs | 27 | 0 | 24 (1) | 0 | 23 | 0 | 0 | 5 | 3–4, 5 |
| tables/map_table_test.exs | 79 | 13 | 62 (0) | 1 | 0 | 1 | 0 | 0 | 3–4 |
| tables/named_table_test.exs | 15 | 6 | 7 (0) | 0 | 6 | 0 | 0 | 0 | 0, 3–4, 5 |
| tables/nested_create_test.exs | 12 | 0 | 12 (0) | 1 | 11 | 0 | 0 | 0 | 3–4, 5 |
| tables/nested_table_guard_test.exs | 16 | 4 | 12 (8) | 2 | 12 | 0 | 0 | 0 | 3–4, 5 |
| tables/nested_table_reads_test.exs | 7 | 1 | 5 (0) | 0 | 4 | 6 | 0 | 0 | 3–4, 4, 5 |
| tables/nested_table_states_test.exs | 11 | 1 | 9 (2) | 0 | 7 | 0 | 0 | 0 | 3–4, 5 |
| tables/nested_table_test.exs | 56 | 1 | 52 (3) | 11 | 45 | 0 | 0 | 7 | 3–4, 5 |
| tables/nobody_test.exs | 5 | 3 | 1 (0) | 0 | 0 | 0 | 0 | 0 | 3–4 |
| tables/page_size_test.exs | 18 | 6 | 2 (0) | 1 | 2 | 0 | 0 | 0 | 3–4, 5 |
| tables/picker_keys_test.exs | 23 | 0 | 21 (1) | 0 | 18 | 0 | 0 | 8 | 3–4, 5 |
| tables/picker_panel_test.exs | 22 | 0 | 18 (1) | 2 | 15 | 1 | 0 | 2 | 3–4, 5 |
| tables/picker_test.exs | 34 | 2 | 31 (2) | 1 | 32 | 0 | 0 | 14 | 3–4, 5 |
| tables/private_action_test.exs | 29 | 13 | 16 (0) | 0 | 8 | 0 | 0 | 3 | 0, 3–4, 5 |
| tables/project_budget_test.exs | 25 | 5 | 14 (1) | 1 | 0 | 9 | 0 | 11 | 3–4 |
| tables/project_table_test.exs | 10 | 10 | 0 (0) | 0 | 0 | 0 | 0 | 0 | 0 |
| tables/protected_aggregate_test.exs | 2 | 0 | 2 (0) | 0 | 2 | 0 | 0 | 0 | 3–4, 5 |
| tables/reference_action_test.exs | 12 | 1 | 7 (0) | 0 | 7 | 4 | 0 | 0 | 3–4, 5 |
| tables/reference_cell_states_test.exs | 4 | 2 | 1 (0) | 2 | 0 | 0 | 0 | 0 | 3–4 |
| tables/reference_cell_test.exs | 17 | 10 | 5 (0) | 1 | 2 | 0 | 0 | 0 | 3–4, 5 |
| tables/save_error_fields_test.exs | 6 | 0 | 6 (0) | 0 | 0 | 0 | 0 | 0 | 3–4 |
| tables/sensitive_table_test.exs | 43 | 4 | 33 (0) | 2 | 0 | 6 | 0 | 11 | 3–4 |
| tables/sideways_scroll_test.exs | 4 | 1 | 1 (0) | 3 | 1 | 0 | 0 | 0 | 0, 3–4, 5 |
| tables/specimen_edit_test.exs | 11 | 1 | 9 (0) | 0 | 0 | 0 | 0 | 0 | 3–4 |
| tables/specimen_filter_test.exs | 11 | 9 | 0 (0) | 1 | 0 | 0 | 0 | 0 | — |
| tables/specimen_table_test.exs | 10 | 9 | 0 (0) | 1 | 0 | 0 | 0 | 0 | — |
| tables/specimen_union_test.exs | 14 | 1 | 12 (0) | 1 | 0 | 0 | 0 | 0 | 3–4 |
| tables/table_actions_test.exs | 32 | 4 | 20 (0) | 3 | 6 | 11 | 0 | 9 | 0, 3–4, 5 |
| tables/task_actions_test.exs | 36 | 6 | 28 (3) | 2 | 1 | 0 | 0 | 0 | 3–4, 5 |
| tables/task_arguments_test.exs | 16 | 6 | 4 (0) | 0 | 2 | 0 | 0 | 2 | 3–4, 5 |
| tables/task_arrays_test.exs | 14 | 2 | 9 (0) | 0 | 0 | 0 | 0 | 0 | 3–4 |
| tables/task_authorization_test.exs | 22 | 11 | 5 (1) | 4 | 0 | 0 | 0 | 0 | 3–4 |
| tables/task_bulk_test.exs | 38 | 3 | 29 (1) | 2 | 0 | 6 | 0 | 11 | 0, 3–4 |
| tables/task_components_test.exs | 11 | 0 | 3 (0) | 11 | 1 | 0 | 0 | 0 | 0, 3–4, 5 |
| tables/task_create_test.exs | 12 | 3 | 3 (1) | 3 | 1 | 0 | 0 | 0 | 3–4, 5 |
| tables/task_edit_test.exs | 45 | 4 | 39 (1) | 1 | 1 | 0 | 0 | 2 | 3–4, 5 |
| tables/task_filter_test.exs | 55 | 44 | 0 (0) | 4 | 0 | 0 | 0 | 0 | — |
| tables/task_label_table_test.exs | 6 | 4 | 2 (0) | 0 | 0 | 0 | 0 | 0 | 3–4 |
| tables/task_labels_action_test.exs | 31 | 0 | 30 (0) | 0 | 17 | 2 | 0 | 8 | 3–4, 5 |
| tables/task_table_test.exs | 25 | 22 | 0 (0) | 3 | 0 | 0 | 0 | 0 | — |
| tables/text_counter_test.exs | 15 | 1 | 7 (0) | 14 | 0 | 0 | 0 | 0 | 3–4 |
| tables/tracker_maps_test.exs | 16 | 3 | 13 (0) | 0 | 0 | 0 | 0 | 0 | 3–4 |
| tables/translation_settings_test.exs | 2 | 0 | 2 (0) | 0 | 0 | 0 | 0 | 0 | 0, 3–4 |
| tables/translation_test.exs | 9 | 4 | 3 (0) | 0 | 0 | 0 | 0 | 0 | 0, 3–4 |
| tables/unchecked_table_test.exs | 27 | 7 | 16 (1) | 2 | 8 | 0 | 2 | 8 | 0, 3–4, 4, 5 |
| tables/uncounted_table_test.exs | 2 | 2 | 0 (0) | 0 | 0 | 0 | 0 | 0 | — |
| tables/union_table_test.exs | 34 | 4 | 26 (0) | 5 | 0 | 1 | 0 | 2 | 3–4 |
| tables/validation_display_test.exs | 17 | 0 | 6 (0) | 14 | 0 | 0 | 0 | 0 | 3–4 |
| **Total** | **1,554** | **446** | **844 (82)** | **193** | **298** | **117** | **12** | **173** | |

Most "Markup" hits are documented `aria-colindex`/`aria-rowindex` checks and are fine. The ones beyond the contract: CSS classes (`column_hiding_test.exs:57,165,188,225` `btn btn-sm`; `table_actions_test.exs:51,466`; `sideways_scroll_test.exs:25,61,63,66,74`; `task_components_test.exs:56` `badge`; `.sr-only` in `component_table_test.exs:92,307`, `long_text_table_test.exs:139`, `picker_panel_test.exs:242,243,525`, `footer_summaries_test.exs:195,313`, `specimen_table_test.exs:90`, `reference_cell_states_test.exs:49`), and nesting of tags (`task_create_test.exs:53–55`, `actions_elsewhere_test.exs:78,120,276,283`, `nested_create_test.exs:88`, `nested_table_test.exs:149`, `array_table_test.exs:811–827`, `task_table_test.exs:201–202`, `text_counter_test.exs` and `validation_display_test.exs` template trees). They matter in stage 7.

### Demo tests that read or use a nested table (n) or a picker (p)

By the line of the `test`. Found by script: check a line before agreeing to its group.

- `action_fields_test.exs`: 253n
- `actions_elsewhere_test.exs`: 162n 173n 182n 204n
- `argument_line_test.exs`: 685n 696n 715n 722n 742n 759n 782p 803p 828p 866p 885p
- `bulk_elsewhere_test.exs`: 635n
- `column_hiding_test.exs`: 215n 231p
- `column_resize_test.exs`: 96n
- `deadline_assignee_test.exs`: 79p 100p 114p 131p 143p 160p 171p 192p
- `deadline_table_test.exs`: 157n
- `footer_summaries_test.exs`: 481n 513n 530p
- `full_view_link_test.exs`: 81n 98n 135n 157n 181n 202n 215n 238n
- `full_view_states_test.exs`: 168n
- `full_view_test.exs`: 637n 723n
- `label_actions_test.exs`: 314n 322n
- `label_import_test.exs`: 254n
- `ledger_default_config_test.exs`: 82n
- `ledger_table_test.exs`: 146n 303n 354n 384n
- `live_updates_elsewhere_test.exs`: 207n 260p 279p
- `live_updates_test.exs`: 359p 561p 633n 657n 666n 699n 729n 745n 768n 790n 927n
- `long_text_table_test.exs`: 150n
- `managed_relationships_test.exs`: 90p 115p 181p 205p 222p 252p 271p 300p 334p 346p 357p 368p 393p 419p 434p 474p 494p 511p 525p 543p 583p 614p 631p
- `named_table_test.exs`: 177n 200n 222n 241n 269n 307p
- `nested_create_test.exs`: 75n 118n 127n 171n 196n 212n 223n 239n 261n 277n 290n
- `nested_table_guard_test.exs`: 100n 108n 132n 161n 189n 210n 220n 239n 256n 270n 378n 405n
- `nested_table_reads_test.exs`: 147n 160n 179n 193n
- `nested_table_states_test.exs`: 71n 84n 94n 107n 125n 135n 146n
- `nested_table_test.exs`: 236n 260n 282n 304n 313n 326n 343n 366n 376n 395n 414n 428n 452n 476n 499n 617n 629n 647n 667n 710n 730n 754n 773n 821n 835n 864n 897n 919n 933n 993n 1007n 1030n 1047n 1069n 1102n 1126n 1154n 1179n 1236n 1254n 1277n 1298n 1315n 1340n 1384n
- `page_size_test.exs`: 361n 403n
- `picker_keys_test.exs`: 88p 105p 117p 130p 157p 178p 190p 201p 212p 233p 256p 275p 287p 338p 401p 410p 418p 432p
- `picker_panel_test.exs`: 73p 125p 145p 171p 183p 200p 209p 246p 262p 312p 349p 384p 470p 489np 517p
- `picker_test.exs`: 69p 75p 93p 110p 139p 156p 166p 174p 183p 191p 242p 267p 303p 323p 340p 357p 375p 395p 407p 436p 450p 484p 502p 523p 546p 570p 584p 619p 660np 688np 702p 724p
- `private_action_test.exs`: 667n 755n 788n 849n 858n 875n 965n 997n
- `protected_aggregate_test.exs`: 44n 55n
- `reference_action_test.exs`: 121p 149p 166p 219p 261p 280p 324p
- `reference_cell_test.exs`: 357n 382n
- `sideways_scroll_test.exs`: 52n
- `table_actions_test.exs`: 456n 479n 487n 501n 536n 552n
- `task_actions_test.exs`: 397n
- `task_arguments_test.exs`: 238n 270p
- `task_components_test.exs`: 202n
- `task_create_test.exs`: 204n
- `task_edit_test.exs`: 762n
- `task_labels_action_test.exs`: 133p 225p 258p 265p 279p 296p 305p 313p 322p 358p 433p 450p 468p 523p 548p 589np 617p
- `unchecked_table_test.exs`: 144p 180p 251n 266n 286n 305n 314n 416n

### The 82 tests that call `render_hook` themselves

These go onto `forge/4` before stage 0 (recommendation 2). By file and line of the call:

`argument_line_test.exs` 408, 816, 847, 875; `array_table_test.exs` 181; `bulk_elsewhere_test.exs` 501, 548, 555; `component_table_test.exs` 225; `label_actions_test.exs` 225; `ledger_default_config_test.exs` 92; `ledger_table_test.exs` 171, 371, 429; `live_updates_elsewhere_test.exs` 55; `live_updates_test.exs` 87, 823, 829, 832, 864, 898; `managed_relationships_test.exs` 286; `nested_table_guard_test.exs` 76, 81; `nested_table_states_test.exs` 211, 238; `nested_table_test.exs` 290, 1175, 1198, 1367; `picker_keys_test.exs` 146, 223, 251; `picker_panel_test.exs` 475, 482; `picker_test.exs` 538, 557, 578, 633; `project_budget_test.exs` 105, 110; `reference_cell_test.exs` 244, 253; `sensitive_table_test.exs` 546; `task_actions_test.exs` 148, 151, 659, 673; `task_authorization_test.exs` 243, 245; `task_bulk_test.exs` 326, 328, 409, 627; `task_create_test.exs` 279, 282; `task_edit_test.exs` 748, 754; `task_labels_action_test.exs` 339; `unchecked_table_test.exs` 411. The calls to `left` in the live-update files are inside a private helper, so 82 counts the tests, not the lines.

## Appendix C: browser suite

All files use `Table` from `support/table.ts`, and so documented ids, roles and labels. Only what goes beyond that is listed.

| File | Tests | Beyond ids and roles | Stage at risk |
| --- | --- | --- | --- |
| a11y-actions.spec.ts | 22 | `btn-error` class (36) | 7 |
| a11y-editing.spec.ts | 16 | — | — |
| a11y-nesting.spec.ts | 7 | `td[data-nested] [data-ash-table]` through `a11y.ts:47` | 0 (name), 5 (watch) |
| a11y-tables.spec.ts | 18 | — | — |
| action_references.spec.ts | 10 | picker (8) | 5 (acceptance) |
| actions.spec.ts | 49 | `_ashTable.ask` (989); `btn-*` classes (377–430, 940, 991); `:scope > tbody > tr > td[data-actions] > button` (90) | 0, 3–4, 7 |
| arguments.spec.ts | 20 | — | — |
| arrays.spec.ts | 37 | — | — |
| authorization.spec.ts | 20 | `.phx-connected` (403) | — |
| components.spec.ts | 15 | latency simulation (LiveView's own) | — |
| contrast.spec.ts | 28 | computed styles | 7 |
| counter.spec.ts | 20 | computed styles | 7 |
| dashboard.spec.ts | 16 | title "ash_table demo" (37) | 0 if the demo is renamed |
| editing.spec.ts | 41 | latency simulation | — |
| files.spec.ts | 10 | — | — |
| filtering.spec.ts | 33 | — | — |
| filter_values.spec.ts | 8 | — | — |
| footer.spec.ts | 9 | `:scope > tfoot > tr` (36, 185) | — |
| full_view.spec.ts | 13 | nested (9) | 5 (acceptance) |
| hiding.spec.ts | 38 | `_ashTable.pushEventTo(root, "sort", …)` (552, 733, 760); `ownedSheets`/`columnRules` (609, 625); computed styles | 0, 3–4, 5 (watch), 7 |
| live_updates.spec.ts | 7 | — | — |
| locale.spec.ts | 17 | titles (81–131); `header > *` (32–36, the demo's own) | 0 if the demo is renamed |
| long_text.spec.ts | 16 | `td > p`, computed styles | 7 |
| maps.spec.ts | 24 | computed styles | 7 |
| named_tables.spec.ts | 15 | — | — |
| navigation.spec.ts | 12 | — | — |
| nesting.spec.ts | 24 | nested (22) | 5 (acceptance) |
| page_size.spec.ts | 12 | — | — |
| pagination.spec.ts | 25 | — | — |
| picker.spec.ts | 35 | picker (32) | 5 (acceptance) |
| references.spec.ts | 5 | — | — |
| relationships.spec.ts | 15 | picker (15) | 5 (acceptance) |
| resizing.spec.ts | 26 | `ownedSheets`/`columnRules` (425, 439); computed styles | 5 (watch), 7 |
| scrolling.spec.ts | 16 | `ownedSheets` (280); sticky styles; nested (10) | 5 (watch), 7 |
| selection.spec.ts | 56 | `/e2e/select`, which mounts the live component (1023, 1084, 1105); `ash_table:selection` (1012); `btn-*` (652, 721) | 0, 1, 4–5, 7 |
| sensitive.spec.ts | 29 | — | — |
| sorting.spec.ts | 10 | — | — |
| table_actions.spec.ts | 11 | — | — |
| tables.spec.ts | 7 | title (104) | 0 if the demo is renamed |
| task_labels.spec.ts | 11 | — | — |
| unions.spec.ts | 11 | — | — |
| validation.spec.ts | 13 | — | — |
| **Total** | **827** | | |
