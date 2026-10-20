# A React/shadcn kit: design note

Status: **accepted, 2026-10-18; stage 0 (R0) built 2026-10-19, with the fixes of its drift check, and done (owner's yes); stage 1 (R1, tooling) built 2026-10-19 (section 14), done (owner's yes); stage 2 (R2, the React grid) built 2026-10-20 (section 15), done (owner's yes); stages 3 to 5 (R3 the panel, picker and question, R4 verification, R5 the guide and the demo page) built 2026-10-20 (section 16), done once their drift check and the owner say so.** It carries the owner's decisions of 2026-10-18 (O1–O9 below) and of 2026-10-19 after stage 0 (section 13, which amends C1, C3, C6, C8, Q4 and section 3). The questions of section 10 were answered as recommended. The amendments to [target.md](target.md) are made (section 12). Code references are of `202ebe4`. The research and the spike are throwaway: `research.md` and `spike.md` in the session's scratchpad (`react-kit/`), and the spike's code on the branch `worktree-agent-ae45e1e4887377ba7` (commit `f9e43ff`, not on `main`). Words follow `CONTEXT.md`. The model for this note is [stage7-design.md](stage7-design.md).

## 0. In one paragraph

A second kit, `ReactKit`, draws every part of a table with React and shadcn/ui. It is a kit like any other: `kit: DemoWeb.ReactKit` at attach, on the tag or on the router line. The core does not change. The rows stay a LiveView stream, and the server holds no rows. `live_react` 2.0 carries the props and the stream to React, with SSR off. The keyboard grid stays the library's hook, which React mounts through a public JS entry. To make this possible, the library makes some of **our own** internals public as documented contracts (section 3), and stream items become plain maps that already hold their finished, translated cell texts, for every kit (section 4).

## 1. The owner's decisions (2026-10-18)

| # | Decision |
| --- | --- |
| O1 | React + shadcn/ui draws every part: grid, cells, filter row, footer, heading, Columns popover, selection line, nested tables, panel, picker, question dialog, editors. It is a **kit** that works out of the box. Panels, the picker and the question are real kit parts, not controlled mode. Controlled mode stays for anyone who wants it |
| O2 | Nested tables are the same as top tables, never restricted |
| O3 | Rows stay LiveView streams; the server holds no rows (an open panel's form may hold its one record). Bridge: `live_react` 2.0, SSR off. This replaces Q20's "live_vue first" |
| O4 | Keyboard and ARIA: no rewrite and no split of the hook. A public JS entry `mountGrid(el, transport)` (S20 made public) and a documented list of the attributes the hook owns, which a kit must not render. The browser suite runs against the React page too |
| O5 | Stream rows become plain maps with finished, translated cell texts, for **every** kit (HEEx too: one way). The byte cost per page is measured |
| O6 | Kit rule: a nested table's portal target exists no later than the patch that opens the table (worded so after stage 0, 13 e) |
| O7 | npm and a bundler (Hex esbuild, no Vite) in the demo only. The library stays npm-free. The React kit lives in a demo folder first, an npm package later. shadcn tokens are scoped under a `.shadcn` wrapper with renamed `--sh-*` variables; Radix portals carry the class themselves |
| O8 | Our internals become public, documented contracts (section 3). Dependency internals stay forbidden. Prefer letting React spread the `Attrs` bundles over sending events by name |
| O9 | `requests/1` messages become maps `%{key:, values:}`, not tuples |

## 2. Goal and non-goals

**Goal.** A host writes `kit: DemoWeb.ReactKit` and gets the whole table drawn by React/shadcn, with everything the HEEx kit does: keyboard, editing, nested tables at any depth, selection, panels with files, the picker, questions, live updates, controlled mode. Same safety (every write through `Operation`; nothing sensitive in any prop). Every React part can be replaced, as every HEEx part can.

**Non-goals.**

- No change to the core (2a, 2b), apart from the item builder of section 4 and the message maps of O9.
- No second keyboard implementation. The hook stays the only one.
- No client-side sorting, filtering or paging (shadcn's Data Table / TanStack is not used: it reads all rows in the browser).
- No SSR, no Node at runtime, no Vite.
- No npm package in this build, and no npm in the library.
- No Vue or Hologram adapter. `Present` and `Intent` stay internal (Q14): a kit still runs on the LiveView core, so it is not a second adapter.

## 3. What the spike proved, and what is untested

**Proved** (spike, `/spike/react`, LiveView 1.2.12, Bandit 1.12.5, live_react 2.0.0):

- live_react 2.0 compiles and runs; SSR off works; no Node at runtime.
- Hex esbuild 0.25.4 bundles TSX and live_react's client (`--jsx=automatic`, `NODE_PATH` with `assets/node_modules`). Hex tailwind 4.1.12 scans the TSX. No Vite. Trap: a folder named `assets/react/` shadows the `react` package (the demo's `tsconfig.json` paths), so the folder is `assets/islands/`.
- shadcn next to daisyUI 5 works with scoping. daisyUI's `--border` is a width and shadcn's a colour, hence the `--sh-*` rename. Radix portals leave the scope, fixed by putting `shadcn` on the portalled element.
- The stream as a prop: sort, page, filter, expand all reach React as patches; the server held 0 rows and 0 records after each render.
- The grid hook runs on React's DOM, mounted by hand: arrow keys, roving tabindex, sort, expand, open a line, the tab stop across nested grids, Enter opens an editor. (History: that was the keyboard model before stage 8a, which removed the arrow keys, the roving tabindex and the shared tab stop; see [tab-model-design.md](tab-model-design.md) §7.)
- A nested table moves by LiveView portal into a cell React drew, and is a React grid itself, **once React draws the target cell ahead of time** (O6).
- A spread `Attrs` bundle with `phx-click` works from React DOM (LiveView delegates from its root, also into `phx-update="ignore"`). `pushEvent` with a reply works, also from a Radix portal.
- Cost: +97.5 KB gzip of JS (react-dom is 210 KB of the 312 KB minified), +2 KB gzip of CSS.

**Untested** (each one gets a test in the stage that builds it):

| What | Why it matters | Stage |
| --- | --- | --- |
| Writes: saving a cell, a reference choice, a row action, a bulk run | The spike sent no `save`; editing was only opened | 2, 3 |
| A live update of the row being edited | The hook's `beforeUpdate(toEl)` never runs under React (below). React may also insert into a cell whose children the hook replaced, and throw | 2 (needs React; moved from 0, owner 2026-10-19) |
| Uploads | `live_file_input` needs a LiveView hook, which is not mounted inside an island. live_react offers `upload`/`uploadTo` (LiveView's hook API) | 3 |
| React StrictMode | A double mount re-creates DOM the hook wrote to; `mountGrid` must be idempotent | 0, 4 |
| A table placed with the tag | Its bundles carry `phx-target` (a CID); an attached table has none | 2 |
| No `beforeUpdate` | LiveView's `beforeUpdate(toEl)` keeps the edited cell's fresh contents (`KEPT`). React has no equivalent. In the spike it held "by luck" (React updated the same text node in place) | 2 (needs React; moved from 0, owner 2026-10-19) |
| A container part as an island | The panel and the picker hold other parts (the picker's table, a question's place). A live_react island renders HEEx children as dead HTML | 3 |
| The development marker check with client debug provably on | It reported nothing, but debug may have been off | 4 |
| `destroyed()` timing | live_react unmounts a root only on `phx:page-loading-stop`, so cleanup runs late | 2 (needs React; moved from 0, owner 2026-10-19) |

## 4. The core change: texts in the stream items (O5)

**Today.** A stream item is a `Present.Row` (2a, `@moduledoc false`): values, no texts. The HEEx kit makes each cell's text when it draws (`Kit.Words.text(:cell, …)` → `Format.format/3`, with the column, the zone and the process's locale). React gets the item through `LiveReact.Encoder.encode(item, [])`, which knows no column, zone or locale. So React cannot make the text without copying `Format` into JS.

**Change.** The item is a plain map that holds the finished text. It is made where the row is put into the stream (`Core.Reading.put_row`, 2b, in the LiveView process), by a new module of the words, **`AshDataTable.Item`** (3w; 2b may call 3w, §1.2). It takes the `Present.Row` (already scrubbed), the model, the zone; the locale is the process's. The HEEx kit draws from the same item (one way). `Present.Row` stays internal; the item is public.

Shape (exact names to fix in stage 0; atoms as keys, encoded as strings by JSON):

```elixir
# a record's row
%{
  dom_id: "tasks-row-42",        # the stream's id
  key: "42",                     # the key events name (a claim when it comes back)
  rowindex: 3,
  names: nil | %{...},           # where the key in the id does not name the row
  open: false, current: false,   # expanded; the chosen record of a picker's table
  failure: nil | %{text: "…", message: %{key: :…, values: %{}}},   # a row action's
  attrs: %{"data-key" => "…"},  # the row group's varying attributes, a bare one `true` (13 a); no aria-rowindex (13 c)
  cells: %{
    title: %{
      state: :value,             # :value | :empty | :masked | :forbidden
      text: "Buy milk",          # finished and translated; nil but for :value
      value: nil,                # the raw value: a `component`'s, and a boolean's (Q4, 13 b)
      editable: true,
      failure: nil | %{typed: "…", text: "…", message: %{...}},
      attrs: %{"data-value" => "…"}   # the cell's varying attributes (today Attrs.cell/5)
    }
  }
}

# the detail under an expanded row (no `pk`, no `counts`: 13 c)
%{dom_id: "tasks-row-42-x", detail: true, key: "42",
  lines: nil | [%{name: :comments, open: true, count: 2, text: "2 records",
                  message: %{key: :records, values: %{count: 2}}}],   # nil while closed
  attrs: %{"data-detail" => true, "data-row" => "42"}}
```

- Texts that are the same on every row (a masked cell's "Show", "Not available") are **not** in the item. They go to the grid part once, by column, so a row carries only what varies; that the grid part gets the per-column constant texts is built in R2 (13 d).
- `attrs` holds only the attributes that vary per row or cell (stage 7a's fallback D3 b). The builder of those attributes moves from `Attrs.cell/5` and `Attrs.rowgroup/2` into `Item`; `Attrs` calls `Item` (3 → 3w, allowed). So the marker rules stay in one place.
- No sensitive value: `Item` only reads a `Present.Row`, which `Present` scrubbed (F1). A masked cell has no `text` and no `value`.
- This reverses RQ6 ("values, not texts") for the stream item only. The data layer still makes no words (F2): 2a gives values, 3w makes the text, in the LiveView process. An ADR is proposed (Q12).

**Measurement plan.**

| # | What | How | Limit |
| --- | --- | --- | --- |
| M1 | HEEx kit, before and after the change | `demo/perf/baseline.mjs` on `/tasks`, back to back, at the start and the end of stage 0; payload and wire (`PERF_WIRE=1`) | Bytes per action within 2 % (the HTML should be identical); times within 20 % |
| M2 | The JSON of one page of items | A demo test encodes the 25 rows and their details of `/tasks` page 1 as live_react would send them, and prints the bytes beside the HEEx HTML of the same rows | Reported; no gate |
| M3 | React page against HEEx page | `baseline.mjs` against `/react/tasks` and `/tasks` (page change, sort, filter, expand, open a nested table, save a cell); also the time from connect until the rows are visible (no SSR: the first paint is empty) and the JS bundle size | Reported to the owner at the end of stage 2; a flag if a page change sends more than 1.5× the HEEx bytes |
| M4 | Panel and picker | "open the panel", "open the picker" on both pages | Reported at the end of stage 3 |

## 5. The new public contracts (O8)

Each is written in a moduledoc or a JS file of the package, with its exact shape, and checked by a test. "Kit" below means any kit, HEEx or React.

| # | Contract | Exact shape | Where documented | Checked by |
| --- | --- | --- | --- | --- |
| C1 | The stream item | Section 4, as amended by 13 a–c: `attrs` keep a bare attribute as `true` (HEEx's markup byte for byte), no `aria-rowindex` in them; a cell's raw `value` for a `component` and for a boolean, a union in the state of the kind it holds; the detail has no `pk` and no `counts`, `lines` nil while closed, line names atoms. The grid part's `rows` is the table's stream as `@streams[name]` gives it; a kit hands it on unchanged (to `:for` in HEEx, to `<.react rows={@rows}>` in React) | `AshDataTable.Item` moduledoc; `Kit` moduledoc, part `grid` | `test/item_test.exs` (shape both ways, as `kit_test.exs` does for the structs); the secret check of `KitCase` |
| C2 | Messages as maps (O9) | A message is `%{key: atom, values: map}`; a value may be a message. An action's message is `%{key: :ash, values: %{message: String.t(), vars: map}}`. Everywhere a message is given: `requests/1` (and its `values` choices as `[%{value:, label:}]`, not tuples), `Kit.Words.messages/2`, `message/2`; an action's `vars` plain data (a value that is no string, number or atom as its text). JSON-safe now: messages, items and `requests/1` only (13 f) | `AshDataTable.Messages` moduledoc | `messages_test.exs`; `item_test.exs`; a test that `requests/1` encodes to JSON; the React kit's props are picked by its server side and tested in R2 (13 f) |
| C3 | The bundle → props rule | A bundle is turned into React props by: `true` → `""`, `false`/`nil` left out, everything else `to_string` (HEEx's rule, done on the server by `Attrs.props/1`; an item's `attrs` keep `true` for a bare attribute, and the JS half maps it to `""`, 13 a); then in JS the names React wants (`class` → `className`, `tabindex` → `tabIndex`, `colspan` → `colSpan`, `rowspan` → `rowSpan`, `for` → `htmlFor`, `readonly` → `readOnly`, `maxlength` → `maxLength`); `aria-*`, `data-*`, `phx-*`, `role`, `id` unchanged. A bundle's `phx-hook` is never rendered by React (the hook is mounted by C5) | `Attrs` moduledoc (server half); the React kit's `props.ts` (JS half, demo) | `attrs_test.exs`; the React kit's development check |
| C4 | The events a kit may send | Every event of S6 with its payload and reply, as the comment at the top of `attrs.ex` lists them today, becomes the "Events" section of `Attrs`' moduledoc. Rule: **a kit sends an event through a bundle** (`phx-click`, a form's `phx-change`/`phx-submit`) wherever a bundle exists. By name (`pushEventTo(el, "ash_data_table:ID:event", payload)`) only the events the list marks "a kit may push", with their reply. The server's pushes (`ash_data_table:focus`, `:ask`, `:select`, `:leaving`, `:answered`) are listed for reading only | `Attrs` moduledoc, "Events" | `intent_test.exs` (every listed event parses); a test that the list and `Intent.parse/2`'s clauses are the same |
| C5 | The JS entries and the transport (S20 public) | `mountGrid(el, transport, options) → {beforeUpdate(), updated(), destroy()}`; the same for `mountPanel`, `mountPicker`, `mountPagination` (Q6). `transport = {push(event, payload) → Promise(reply), on(event, handler), off(event), debug() → boolean}`. `liveViewTransport({el, pushEventTo, handleEvent, removeHandleEvent, liveSocket})` builds one from LiveView's documented hook functions (live_react passes them as props). `beforeUpdate()` is called before each React commit that may change the element, while its DOM is as it was, and `updated()` after it (as LiveView calls a hook's; drift fix of R0, owner 2026-10-19); `destroy()` on unmount; a second `mountGrid` on the same element after `destroy()` works (StrictMode). `options.onEdit(cellId \| null)` tells the kit which cell is being edited (Q7) | `assets/js/index.js` and a header comment in each entry; `package.json` `exports` | TypeScript types in `assets/js/types.d.ts`; `npm run check`; the browser suite against the React page |
| C6 | The attributes the hook owns | (As planned before stage 8a, which took `aria-selected`, `aria-invalid` and `aria-readonly` out and keeps `tabindex` as given: `assets/js/owned.js` is the list now; [tab-model-design.md](tab-model-design.md) §6.) Each attribute the hooks write, with what a kit may render of it (13 h): **never** (`aria-selected`, the boxes' `checked`, `aria-busy`, `phx-update` on an edited cell, the whole-text button `data-whole`, `data-over`, `data-dragging`, …), **once** as the table gives it and then left to the hook (`tabindex`, `aria-rowindex`), or **given**: rendered as the table gives it and again only when it gives another value (`aria-invalid`, `aria-describedby`, `aria-readonly`, `data-value`, `data-saved`); and the contents the hooks write (a cell while it is edited, …). The full list is made from every `setAttribute`/`removeAttribute`/`toggleAttribute`/`replaceChildren` of `assets/js/` | `assets/js/owned.js` (exported) and `Kit` moduledoc | A test that greps `assets/js/` and compares with `owned.js`; the React kit's development check warns when a rendered prop names one |
| C7 | The DOM ids in JS | `assets/js/ids.js` mirrors `AshDataTable.Ids` function by function (`row`, `cell`, `expander`, `actions_cell` (`actionsCell` in JS), `detail`, `lineCell`, `lineButton`, `nestedRow`, `nestedCell`, `nestedTable`, `field`, …), plus the ids that are "the table's id and a suffix" today (`-s`, `-head`, `-head-COL`, `-head-row`, `-filter-row`, `-dialog`), which `Ids` gains as functions (Q11) | `ids.js`, `Ids` moduledoc | A demo e2e spec renders samples of every `Ids` function on a page and compares them with `ids.js` |
| C8 | The portal-target rule (O6) | The place a nested table is moved into must exist no later than the patch that opens the table (13 e). A kit that draws after LiveView's patch (React) therefore draws the target of every line of an expanded row ahead of time, hidden while the line is closed; the HEEx kit draws it in that patch and draws no closed target ahead. The same for a slot of a container part (Q2, re-decided at R3). React must never re-create a target (stable `key` = the id) | `Kit` moduledoc, parts `detail` and `line` | The browser suite (nested tables) against the React page |
| C9 | The sender | A kit draws the grid's sender (`Attrs.sender/1`) **outside** any React island, so LiveView mounts its hook; the transport pushes through it, so LiveView never locks the grid | `Kit` moduledoc, part `grid` | `portals.spec.ts` against the React page |

Unchanged and still public as they are: `attach/4`, `attached/1`, `put_state/3`, `use AshDataTable.Kit` (with `contract: 2` since stage 0), `Attrs.*`, `Kit.editor/1`, `Kit.part/1`, the fields a kit part is given. The item replaces `Present.Row` as what the grid part's rows hold. That changes the assigns of `grid`, `row` and `cell` in a way old kits cannot handle, so the contract goes up to **2** (D15) (Q13).

## 6. How the React kit is put together

- **Where.** `demo/lib/demo_web/react_kit.ex` (`use AshDataTable.Kit, contract: 2`, every part overridden) and `demo/assets/islands/` (TSX, shadcn sources copied in, `props.ts`, `ids` from the package). npm only in `demo/assets/package.json`.
- **Islands.** One island per outer part: heading, argument line, selection line, grid, pagination, status, panel, picker, question. The parts inside an outer part (header cell, row, cell, footer, line, field, control, …) are React components inside its island, each replaceable by name.
- **Customizing.** Elixir side: a host's kit does `use DemoWeb.ReactKit` and overrides a part (HEEx or another island). JS side: the island's components come from a map the host passes to live_react (`getHooks(components)`); replacing `Cell` or `Panel` is one entry of that map.
- **What stays HEEx.** The kit's `root/1` (an element with its bundle, no visible UI), the filter row's empty `<form>` (inputs inside React name it with `form=`), the sender (C9), and anything a portal moves.
- **Behaviour stays the hook's.** The panel, the picker and the question are native `<dialog>` (modal) or `role=region` (inline) elements with shadcn's classes, opened by the hooks as today. Radix's Dialog is **not** used for them: it would fight the hook for focus and opening, and its portal leaves the LiveView root, where `phx-*` attributes are not delegated. Radix is used only inside a control (Select, Popover with a Calendar, Command in the picker's search) where the hook owns nothing; its portalled content carries `shadcn` (O7).
- **Look.** A root class of its own, not `Kit.Default`'s `Parts.Look` (the spike drew a double expander arrow). `look/1` answers the six options of the look; dark mode follows daisyUI's `[data-theme=dark]` in the demo.
- **Editors.** React draws each column's editor into its `<template>`'s content with `createPortal(editor, template.content)`; the hook clones `template.content` as today (Q8).
- **Column components.** A column with a HEEx `component` cannot draw inside React. The React kit maps components by module name to React components: the four shipped (`Badge`, `Image`, `Progress`, `Slider`) come with it; a host registers its own; a column without one shows its `text` and warns in development (Q10).

## 7. How verification works

`KitCase` renders on the server and asserts markers in the HTML. A React kit's server HTML has no rows and no markers, only `data-props` and the stream diffs. So:

1. **`KitCase`, server side, for the React kit**, with a new option `client: true`: it keeps the secret check (everything React gets is in the page's `data-props` and stream diffs, so "the page holds no `Test.Resource.secret/0`" still means "React was never given it"), the texts contract and "every part drawn once"; it skips the marker and element-kind assertions. To confirm in stage 4 that live_react writes every prop and stream item into the HTML that `LiveViewTest` sees.
2. **The browser-side kit check**, new: `react-kit.spec.ts` drives `/e2e/kit?kit=react` through the 20 states and 4 presentations of `KitCase` with Playwright, turns LiveView's client debug on, and fails on any message of the hook's development check (`check.js`). It also asserts the markers and element kinds `KitCase` asserts, on the browser's DOM, and that no rendered element carries an attribute of C6 that React set.
3. **The e2e suite against the React page.** A second Playwright project, `react`, runs the existing specs with the demo's kit set to `ReactKit` for every table (a demo setting per request). Specs that assert what only the HEEx kit draws (a daisyUI class, a text node's place) are tagged `@heex` and skipped there; each tag is listed and reviewed with the owner. Plus the untested items of section 3: a save, a save while a live update changes the row, an upload, StrictMode (the React page renders in `<StrictMode>` in the e2e environment), a table placed with the tag.
4. The markup snapshots stay HEEx-only.

## 8. Stages

Each stage: its own commits on `main`; during a stage only `mix test --stale` (root, demo) and the changed or named spec files; each of the three suites (root, demo, browser; from stage 2 the `react` browser project too) **once** at the end of the stage; `docs/agents/architecture.md` corrected where the stage made it false. **After every stage, an independent drift check** against target.md (as amended) and this note: modules and parts, dependency rules (2b calls 3w, never 3), safety (no sensitive value in any prop or item, every write through `Operation`), only the agreed tests changed, nothing built that the documents do not ask for. It reports; a stage is done only after it.

| Stage | What | Days | Done when | Its drift check also looks at |
| --- | --- | --- | --- | --- |
| **0. The contract in the library** | `AshDataTable.Item` and texts in items for every kit (section 4); the HEEx kit draws from it; `Present.Row` no longer reaches a part. Messages as maps (C2). `Attrs.props/1` (C3). The events list (C4). `mountGrid`/`mountPanel`/`mountPicker`/`mountPagination`, `liveViewTransport`, `onEdit`, idempotent `destroy` (C5). `owned.js` (C6). `ids.js` and the suffix ids in `Ids` (C7). The portal-target and sender rules in `Kit`'s moduledoc (C8, C9). Contract 2. M1, M2 | The HEEx kit is unchanged to the eye; the snapshots differ in nothing, or only where reviewed; M1 within its limits; every contract has its test; the library has no npm dependency | RQ6's amendment holds only for the item; 2a still makes no words; `Item` reads only scrubbed rows; no dependency internals (no `LiveStream` fields read by us) |
| **1. Tooling** | npm in `demo/assets`; esbuild `--jsx=automatic`, `NODE_PATH`; `config :live_react, ssr: false`; `getHooks` in `app.js`; Tailwind `@source "../islands"`; the `.shadcn` scope with `--sh-*` tokens and dark mode on `data-theme` and the system preference; the folder `assets/islands/`; the demo's test hook imports the package, not a relative path (13 g); a recipe in the demo's README | A page with one island builds in dev and in `MIX_ENV=e2e`; daisyUI's look elsewhere unchanged (contrast and a11y specs green) | npm only under `demo/`; the library's `mix.exs` and `package.json` unchanged |
| **2. The React grid** | Grid, header with resizers and the Columns popover, filter row, rows, every cell state (masked and "Show", forbidden, failure, components), actions cell, selection boxes, expander, lines with eager targets, nested tables, footer and summaries, nested pagination, editors through `createPortal`; heading, argument line, selection line, pagination, status; the grid part given the per-column constant texts (13 d); the props the server side picks, with a test (13 f); the three tests of section 3 that need React (13 i). M3 | `/react/tasks` does what `/tasks` does in the grid: the `react` project green for every grid spec not tagged `@heex`; a save, a save under a live update, StrictMode, a tag-placed table pass; M3 reported | C6: React renders no owned attribute; no event pushed by name that C4 does not list; no `phx-hook` rendered by React |
| **3. Panel, picker, question as kit parts** | The three as React parts on native `<dialog>`/region with shadcn's look, modal and inline; fields of every kind, groups, unions, chosen records; uploads through live_react's `uploadTo` (fallback: the file control as HEEx `live_file_input` moved in by portal); the slots of panel and picker by portal into targets drawn while closed (Q2); controlled mode still works with this kit. M4 | `kit.spec.ts`, the panel, picker, upload and question specs green in the `react` project; mixed presentations work | Every answer still goes through `Operation`; a sensitive field's value is in no prop; the Drawing change of Q2 is the same for every kit |
| **4. Verification** | `KitCase` `client: true`; `react-kit.spec.ts` over 20 states × 4 presentations; the `@heex` tags reviewed; the development check with debug provably on; StrictMode on the whole suite | The three suites and both browser projects green, each once | The checks test what they claim (one mutation: a React cell that renders `aria-selected` must fail the run; a prop with the secret must fail `KitCase`) |
| **5. Guide and demo page** | `documentation/topics/react-kit.md` (the recipe, the contracts, the traps: folder name, `--border`, portals); the demo's `/react/tasks` linked from its index | The guide test passes; the page is in `demo/README.md` | The guide promises only what the contracts say |

**Total: 17–23 days.**

## 9. Risks

| Risk | What we do |
| --- | --- |
| React re-creates a row or cell (a key change, a remount): the hook's writes and a moved nested table are lost | Keys are the ids of `Ids`; no conditional wrapper changes a cell's element; StrictMode in e2e; a spec that sorts while a nested table is open in another table |
| React inserts into a cell whose children the hook replaced with an editor, and throws | `onEdit` (C5): the kit freezes that cell's children until the edit ends (Q7); spec "save under a live update" |
| live_react reads LiveView's `LiveStream` fields: a LiveView upgrade may break it | Its coupling, not ours; pinned in `mix.lock`; the `react` project runs on every LiveView upgrade, as the `phx-update` exception is re-checked |
| +81.4 KB gzip of JS on every page of the demo (measured in R1, section 14; the spike's estimate was +97.5 KB) | Demo only; reported in M3; a second esbuild entry for React pages if the owner wants it (Q14) |
| No SSR: an empty grid until the socket connects | Measured in M3; the kit draws a skeleton of the header from props that are known at the dead render |
| The two kits drift | Words, ids and markers come from one place (`Item`, `Ids`/`ids.js`, `Attrs`/`markers.js`); the same browser suite runs on both |
| A Radix control inside a LiveView form does not send `phx-change` | Tried first in stage 3; else a native control with shadcn's classes |
| The suite's specs are coupled to HEEx markup | `@heex` tags, each reviewed; the coupling counted in `test-coupling.md` is the starting list |
| Making our internals public freezes them | Only the shapes of section 5 are public, each with a test; the contract version rises with an incompatible change (D15) |

## 10. Open questions

1. **How large is an island?** a) one per outer part; b) one per table (the whole body in React). b needs every entry field as a prop and still needs portals for nested tables. ➡️ **a**: one island per outer part (section 6), the inner parts as React components inside it.
2. **Container parts: how the picker's table, a question's place and a picker inside a panel get into a React panel or picker.** live_react renders HEEx children as dead HTML. a) by `<.portal>` into a target the React part draws, the part drawn always (closed, its target hidden) so the target exists before the patch that opens it (C8); b) panel and picker frames stay HEEx with shadcn classes. ➡️ **a**, for every kit (one way; the drawing changes once), and measured in M4. The root stays a HEEx element in every kit.
3. **Where the item is built.** ➡️ `AshDataTable.Item` in 3w (2b may call it; 2a stays word-free); the varying attributes of `Attrs.cell/5` and `Attrs.rowgroup/2` move into it and `Attrs` calls it.
4. **A cell's raw `value` in the item.** It costs JSON bytes on every row and needs encoders for `Decimal`, `Ash.CiString` and unions. ➡️ Only for a column with a `component` (which needs the value), and a boolean's (the HEEx kit draws it as a mark; a union that holds a boolean too, the union resolved to the state of the kind it holds; owner 2026-10-19, 13 b); else nil. The React kit implements `LiveReact.Encoder` for the few value types (a protocol of a dependency, its public API).
5. **Messages as maps beyond `requests/1`.** ➡️ Yes, everywhere a message is given (C2): one form, and every part's assigns become JSON-safe.
6. **One JS entry per hook.** ➡️ `mountGrid`, `mountPanel`, `mountPicker`, `mountPagination`, plus `liveViewTransport`. The sender stays a LiveView hook on a HEEx element (C9).
7. **What replaces `beforeUpdate(toEl)`.** ➡️ `options.onEdit(cellId | null)`: while a cell is edited, the kit renders its children frozen; when the edit ends, the kit renders the fresh item and the hook reads the cell as it is then. The HEEx path keeps `beforeUpdate`.
8. **Editors drawn by React.** ➡️ `createPortal(editor, template.content)`, the hook unchanged. Fallback if React cannot render into a template's content: the editors stay HEEx templates with shadcn's classes, outside the island.
9. **Radix for what opens.** ➡️ No Radix Dialog, Sheet or AlertDialog for the panel, picker and question: native `<dialog>`/region with shadcn's classes, opened by the hooks. Radix only inside controls.
10. **Column components in React.** ➡️ A map from component module to React component; the four shipped ones included; without one, the cell shows its text and warns in development.
11. **The ids in JS.** a) `ids.js` mirror; b) ids per item (bytes on every cell). ➡️ **a**, with the e2e comparison of C7; `Ids` gains the suffix ids.
12. **ADR.** ➡️ One: **ADR 0002 "Stream items carry finished texts, for every kit"** (it reverses RQ6 for the item, is surprising, and is costly to reverse: every kit draws from it). No ADR for live_react now: it is a demo dependency and easy to swap; write one when the kit becomes an npm package.
13. **Contract version.** The grid's, row's and cell's assigns change. ➡️ Contract 2 (D15: no support of contract 1; `Kit.Default` and `DivKit` move in stage 0).
14. **One bundle or two in the demo.** ➡️ One for now; a second entry only if M3 shows the HEEx pages suffer.
15. **The demo's React page.** ➡️ `/react/tasks` (attach, `ReactKit`) plus `/e2e/kit?kit=react` for tests; the `react` browser project switches every table of the demo to `ReactKit`.
16. **npm package later.** ➡️ Not in this build. When it comes: `ash_data_table_react` on npm (the TSX), the Elixir kit module in the library behind `Code.ensure_loaded?(LiveReact)`, so the library still needs no npm.

## 11. Public API only

| Where | What of a dependency it uses |
| --- | --- |
| Islands | `LiveReact.react/1`, `getHooks/1`, the `LiveReact.Encoder` protocol, the hook props `pushEvent`, `pushEventTo`, `handleEvent`, `removeHandleEvent`, `upload`, `uploadTo` (LiveView's documented hook API) |
| Streams | `@streams[name]` handed on unchanged; we read no field of `Phoenix.LiveView.LiveStream` (live_react does: its coupling) |
| Events | `phx-click`, `phx-change`, `phx-submit` delegated by LiveView from its root; `pushEventTo` |
| Portals | `Phoenix.Component.portal/1`, as stage 5 |
| React | `createRoot` through live_react, `createPortal`, `useLayoutEffect`/`useEffect`, `StrictMode` |
| Browser | `HTMLDialogElement.showModal()`, `HTMLTemplateElement.content`, the popover API |

Nothing of LiveView's wire protocol, no `data-phx-*`, no `__xxx__` field.

## 12. Proposed amendments to target.md

Made in target.md with the owner's yes of 2026-10-18 (the diff was `react-kit/target-amendment.diff` in the session's scratchpad), and amended after stage 0 with the decisions of section 13. In short:

1. Sources: **D-react**, the owner's decisions of 2026-10-18 (O1–O9).
2. §0 and §7: a React kit inside LiveView is built (in the demo), on `live_react` 2.0 with SSR off; Q20 changed.
3. §2 row 22 and S3: a kit may be React; stream items are plain maps with finished texts (`AshDataTable.Item`, 3w); contract 2.
4. S6: the events a kit may send, their payloads and replies, and the server's pushes are documented in `Attrs`; a kit prefers bundles.
5. S20: public: `mountGrid`, `mountPanel`, `mountPicker`, `mountPagination`, `liveViewTransport`, `onEdit`; the attributes the hook owns (`owned.js`); F16's "internal until a second transport exists" is met.
6. §4.3 `Present`: the row reaches a part only as an item; §4.5: `AshDataTable.Item` (3w), `ids.js`, `owned.js`.
7. §6: two couplings kept on purpose: `Ids` ↔ `ids.js`, and the hook ↔ the attributes it owns.
8. §7.4: "No JSON encoding inside the LiveView path" becomes "every value a part or item is given is JSON-safe or has a documented encoder; serialisation is the bridge's".
9. §8: Q14 (the item is public; `Present`/`Intent` stay internal), Q20 (`live_react` 2.0, SSR off), RQ6 (values and, in the stream item, the finished text).
10. §9: stage 8, the React kit, R0–R5, each with its drift check.

## 13. Decided after stage 0 (owner, 2026-10-19, "as recommended")

After stage 0's drift check the owner took these as recommended. They amend the sections named.

| # | Decision | Amends |
| --- | --- | --- |
| a | An item's `attrs` keep a bare attribute as `true`, so HEEx spreads them as before and the markup is the same byte for byte; the JS half of the props rule (`props.ts`) maps `true` to `""` | C1, C3 |
| b | A cell's raw `value` is also given for a boolean; a union is resolved to the state of the kind it holds (`:forbidden`, `:empty`, `:value`), and its `value` is the held boolean's | Q4, C1; target.md S3 (D23's raw value) |
| c | The detail item has no `pk` and no `counts`; its `lines` are nil while the row is closed; a line's `name` is an atom (it goes to JSON as a string); no `aria-rowindex` inside `attrs` (the part writes it) | C1, section 4 |
| d | The per-column constant texts (a masked cell's "Show", "Not available") are not in the item; that the grid part is given them per column is built in R2 | Section 4; R2's scope |
| e | C8 reads "the place must exist no later than the patch that opens the table". The HEEx kit draws no closed target ahead of time; whether a container part's slots are drawn ahead is decided again at R3, with Q2 | O6, C8 |
| f | JSON-safe now are messages, items and `requests/1` only, not every part's assigns. The React kit's server side picks the fields it sends as props, with a test in R2 | C2; target.md §7.4 |
| g | The demo's test hook imports the library's JS by a relative path in R0; R1 switches it to the package import | R1 |
| h | C6's "never" list becomes `owned.js`'s scheme: per attribute "never", "once" or "given" (`aria-invalid`, `aria-describedby`, `aria-readonly`, `data-value`, `data-saved` are "given") | C6 |
| i | The three tests that need React (a live update of the row being edited, the missing `beforeUpdate`, `destroyed()` timing) move from stage 0 to R2 | Section 3 |

## 14. Stage 1 (R1) as built (2026-10-19)

- **Tooling, as section 8 has it.** `live_react` 2.0.0 (`ssr: false`), npm in `demo/assets` (react and react-dom 19.3.1, `@radix-ui/react-slot`, `class-variance-authority`, `clsx`, `tailwind-merge`), installed by `mix assets.setup` (`npm install`, see the fix-up below; Node 20 or later), so `mix setup`, the browser tests' global setup, `e2e/server.sh` and `perf/setup.sh` install it. esbuild `--jsx=automatic`, `assets/node_modules` on `NODE_PATH`; Tailwind `@source "../islands"`; the `.shadcn` scope with `--sh-*`. The recipe is the demo's README, "React islands".
- **live_react's JS** is found in `deps/` through `NODE_PATH`, as `phoenix_live_view`'s, not installed as `file:../deps/live_react` (live_react's own guide), so the npm install does not need `mix deps.get` first.
- **The package import (13 g; stage 0's open question 6).** The demo's test hook imports `mountGrid` & co. from `"ash_data_table"`. A host needs nothing for it: the package's `package.json` (`exports`) is in `deps/ash_data_table`, which Phoenix's esbuild config has on `NODE_PATH`. The demo, whose dependency is the repository root, links it into `node_modules` with `"ash_data_table": "file:../.."`. No colocated export: it would be a second way to the same files.
- **Dark mode** follows daisyUI's both ways: `data-theme="dark"`, and the system's preference while no theme is chosen (daisyUI's `prefersdark`), which the spike did not cover.
- **The island.** `/react` (`DemoWeb.ReactLive`, `islands/Sample.tsx`): shadcn's Button and Badge, a prop from the server, an event the LiveView answers. `e2e/react.spec.ts`: props and the event; shadcn's colours inside, daisyUI's outside, in both themes; axe. `tw-animate-css` and `lucide-react` (the spike's) are not added: they come with the first component that needs them.
- **Cost, one bundle (Q14)**, minified as `mix assets.deploy` builds it, gzip -9: JS 213,089 → 476,457 B (64,400 → 145,833 B gzip, **+81.4 KB**), CSS 149,407 → 156,363 B (20,822 → 21,848 B gzip, **+1.0 KB**). Every page loads it; whether the HEEx pages suffer is M3's question (Q14).
- **M1 again** ("open panel" +20.5 % in stage 0), `baseline.mjs` on `/tasks` with `PERF_WIRE=1`, 15 repetitions, old (`5907e1f`, before R1) and new run back to back and alternating (old, new, old, new; load 5.1 falling to 1.8): bytes per action identical for all ten actions; "open panel" 34.3 and 32.7 ms old, 33.4 and 32.6 ms new (−1.5 %), so stage 0's +20.5 % was the one run's noise. Every time within ±10.5 % (cell save −10.5 %, expand +7.4 %, page change −0.2 %): the larger bundle does not slow an action.
- **M1's order.** The four runs alternated old, new, old, new (ABAB) while the load fell, so the later run of each pair had the lighter machine; the next comparison runs ABBA (old, new, new, old), which cancels a steady drift.
- **A flake, recorded.** `filtering.spec.ts:117` ("Tab walks the controls of one filter") failed once in R1's final run, under load ~19: the roving-tabindex race. The server renders a filter's controls with `tabindex="-1"`, the hook's after-patch `sync` (`assets/js/grid/tree.js`) gives the stop back, and a late patch races the test's Shift+Tab. Removed with the roving tabindex in K2; its assertion is rewritten in K3 (target.md, stage 8a).
- **Process note, no action.** A builder ran a spec with `--repeat-each=12`, against the owner's rule (one run of what was touched).

### The drift check's fix-up (owner, 2026-10-19, "as recommended")

- **The island's box has its own id** (`#react-sample-box` in `Sample.tsx`); `react.spec.ts` selects it instead of `#react-sample > div`, live_react's undocumented mount structure.
- **`mix assets.setup` runs `npm install`, not `npm ci`.** `npm ci` deleted `node_modules` on every run, so the browser tests' global setup could break the esbuild watcher of a dev server running meanwhile. `npm install` installs what `package-lock.json` pins as well and touches `node_modules` only where it differs.
- **Node: the Docker gap is resolved in the docs.** The Dockerfile installs Debian's Node (20, Debian 13); `demo/assets/.tool-versions` pins 24 for asdf. The READMEs now say "Node 20 or later"; the Docker base is unchanged.
- **R2's scope gets** an `emulateMedia` case in `react.spec.ts` (the system's dark preference while no theme is chosen), and, after R2, `/react` and `react.spec.ts` are removed or folded into `/react/tasks`: no dead page.
- **R5's scope gets** a check of the package import from a fresh host app (`deps/` on `NODE_PATH`, nothing else).

## 15. Stage 2 (R2) as built (2026-10-20)

What R2 built, per item of its line in target.md, and where it went its own way. Each **divergence** is marked so; the owner decides on each after the drift check.

### Per item

- **Every part of the grid, nested tables as top tables.** `DemoWeb.ReactKit` (`demo/lib/demo_web/react_kit.ex`) draws the `grid` part as one island, `AshGrid` (`demo/assets/islands/table/Grid.tsx`): the skip link, the grid's element with the table's own hook (`mountGrid`), the header with its sort buttons, locks and handles, the filter row with every kind of filter, a row group per item of the stream (a record's row: box, expander, a cell per column, the label column's the row's header, the actions cell; a detail: its lines), the footer with the summaries, a nested table's pages (`mountPagination`) and its link to the full view (live_react's `Link`), and the scrollbar at the bottom edge. A nested table is drawn by the same kit in its portal, an island of its own: the same parts at every depth. The inner parts are React components replaceable by name (`parts.tsx`, `reactKit({Cell: …})`); the columns' components by the module a column names (`cells.tsx`: Badge, Image, Progress, the demo's Progress and Hours), the cell's text where the kit has none (a warning in development, Q10).
- **Editors.** **Divergence D1:** the editors are not drawn by React into their templates (`createPortal`, Q8's recommendation): the templates are drawn beside the island, as markup of the LiveView's, by the kit's `editor` part (`Kit.editor/1`, `Kit.Default`'s), the failure template too. Why: what an editor's control says of its column (the least and most of a number, its step, the counter of a text, whether a sensitive cell can be emptied) is made by the table's internals (`Model.Limits`, `Edit.clearable?/1`), which the kit contract gives no part; a kit's own `editor` part could not draw them either. Q8's fallback (HEEx templates outside the island) is what was built, for this reason rather than the one Q8 names. The hook finds a template by its id anywhere in the page. To close it: the contract gives the `editor` part what the control says (a seam of the library), and the React kit draws it.
- **The per-column constant texts.** The library gives the `grid` part, in its `texts`, what a masked cell says by column (`show_value`, `hide_value`, one per column of the model, nil where it is not sensitive) and alike for all (`hidden_value`, `show`, `hide`), `not_available`, and `yes`/`no` (what a failed boolean cell shows of what was typed; **addition** beyond 13 d's two examples). `Kit` moduledoc, `test/kit_test.exs`.
- **The props the kit's server side picks, with a test.** `DemoWeb.ReactKit.Props`: one function per prop, each of the assigns it is made of (so LiveView marks a prop changed only with them, and live_react sends a JSON patch of what changed), plain data only; the bundles through `Attrs.props/1` without `phx-hook`/`phx-update`. `LiveReact.Encoder` for `Decimal` and `Ash.CiString` (a component's raw value). `demo/test/demo_web/react_kit_test.exs` decodes every island's props on /react/tasks at rest, with a nested table open, sorted, filtered and with a row selected.
- **The browser suite's grid specs against the React page.** A second Playwright project, `react`, runs 33 grid spec files (the list in `playwright.config.ts`: not the panel's, picker's, question's, uploads', controlled mode's, nor the kit's, markers' and contract's own) with every table a page does not give a kit of its own drawn by the React kit, as the page asks by request (`x-demo-kit: react`, `DemoWeb.E2E.KitChoice` keeps it in the session, `DemoWeb.E2E.ChosenKit` is the e2e configuration's kit and draws with the kit of the LiveView's process): /tasks and every other page as they are, router lines, the tag and attached tables alike (Q15: "a demo setting per request"). `@heex` excludes a test; none is tagged: the few assertions of what only the default kit draws were made to hold for both (below).
- **A save under a live update; the missing `beforeUpdate`; `destroyed()` timing** (13 i). `react.spec.ts`: a save while another person changes the row (and `live_updates.spec.ts`'s "a cell the member is editing keeps what they typed" in the `react` project); the nested table's hooks destroyed as LiveView destroys its island (the kit's `ash-react:gone`, and one hook after it is opened again: one `select` per box). How the kit takes them, below.
- **StrictMode.** Every island renders in `<StrictMode>` where React is a development build (dev and e2e): the hooks are mounted, destroyed and mounted again (`mountGrid` took it as built in R0). `react.spec.ts`: one `select` per box.
- **A table placed with the tag.** `/e2e/react/tag` (`DemoWeb.E2E.ReactTagLive`): its bundles carry `phx-target`; sort and save in `react.spec.ts`; the dashboard's two tags in the `react` project.
- **An `emulateMedia` case.** `react.spec.ts`: with no theme chosen, the table follows the system's dark preference, and back.
- **`/react` and `react.spec.ts`.** `/react` (`DemoWeb.ReactLive`, `islands/Sample.tsx`) is gone; `/react/tasks` (`DemoWeb.ReactTasksLive`, the tasks attached with the React kit) is the page, and `react.spec.ts` its spec, with R1's checks of shadcn's colours inside and daisyUI's outside in both themes folded in.
- **The rest of the note's stage 2 row** (heading, argument line, selection line, pagination, status). `columns` ("Columns" and its list), `selection_line`, `status` and `pagination` are islands. **Divergence D2:** the heading line around "Columns" (the name, create, the table actions) and the argument line stay `Kit.Default`'s HEEx: the values an argument's control is drawn with (its id, what it shows, its limits: `Model.Argument.argument_id/1`, `shown/3`, `Model.Limits`) are made by the internals in `Parts.Arguments.argument_line`, and the `argument` part, which is given them, is drawn per argument inside that HEEx form; one island would have to hold the HEEx form. To close it: the `argument_line` part is given each argument's values, as `argument` is.

### How the kit keeps the hook's work (the questions of section 3)

- **Commits at once.** live_react renders an island with `root.render`, which React runs later: two patches that came one after the other (a table busy, then its rows) could be drawn as the last only. The kit's hook (`reactKitHooks`, `mounting.tsx`) runs live_react's `mounted` and `updated` inside `flushSync`, React's public way to commit now: each patch is drawn as LiveView draws a HEEx kit's, in the hook's `updated`.
- **`beforeUpdate`.** A class component around what the hook's element holds (`Commits`) calls `beforeUpdate()` in `getSnapshotBeforeUpdate` and `updated()` in `componentDidUpdate`: the pagination keeps aside the focused control before a commit takes it.
- **A cell the hook holds** (the missing `beforeUpdate(toEl)`, Q7). A cell is drawn as it was while the hook edits it (`onEdit`) or while its save or action is on its way (`aria-busy`, which the hook writes and takes away; a `MutationObserver` on the grid, and the attribute read as the cell is drawn). The hook says `onEdit(null)` before it gives the cell its content back; the kit hears it at the end of that task (a microtask), when the content is back or the cell is busy. React never inserts into or removes from a cell whose children the hook replaced (it would throw). Once the server sent the row again (live_react replaces that row's item, and keeps the others), what a cell holds is drawn anew and the hook's "Show all" button in it goes, as LiveView draws a row it is sent: a value that was shown is hidden, a whole text offered again where it is cut off. The cell element stays, with its focus.
- **`destroyed()` timing.** live_react unmounts an island's root only on the next `phx:page-loading-stop`. The kit's hook destroys every table hook mounted in an island as LiveView destroys the island's hook (`gone`); React's unmount later finds them destroyed (they are idempotent). It says so on `window` (`ash-react:gone`, the island's id), which `react.spec.ts` hears.
- **What the hook owns** (C6). The boxes are drawn without `checked`; the Columns list's boxes ticked once by a ref, not React's `defaultChecked` (React puts that back after every change of the box, over the hook's); the filter's, the page size's and the width fields' controls are uncontrolled (the server's value set where it changes, unless the person is in the control); `aria-rowindex` once; the Columns button's name and count, the masked cell's value and button text drawn once. The expander's `aria-expanded` follows the row's detail item (lines while open), which the server sends whenever the row opens or closes; the row's own item is not sent again for it, and a value React drew last would not be drawn again after the hook's.
- **The places of a nested table** (C8). The lines of an expanded row, with the cell a nested table is moved into and the place of its heading line, are drawn as the row's detail comes, hidden while the line is closed, never drawn again as another element.

### Measured (2026-10-20)

- **The default kit's bytes (the budget of 2 % per stage).** `demo/perf/baseline.mjs` on `/tasks` (the picker among its actions), `PERF_WIRE=1`, 15 repetitions, `b2e240a` (before R2, a temporary worktree) and R2 back to back, old, new, new, old (load 1.1 to 5.2, falling): bytes per action identical for all ten actions (page change 158,252, open the picker 40,163, open a nested table 42,009, cell save 8,605). Times, the mean of each pair's medians: −13 % (select a row) to +11 % (open the panel inline, 15.8 → 17.5 ms), page change +6.0 %, open the picker −3.8 %.
- **M3, the React page against the default kit's** (`PERF_PAGE=/react/tasks`, one run, load 1.1; against the default kit's runs above), median bytes per action: page change 158,252 → 124,641 (0.79×; wire 11,977 → 10,673), open a nested table 0.72×, open the picker 0.86×, expand a row 0.68×, cell save 0.92×, cell save in a nested table 0.41×, open the panel 1.29×, select a row 591 → 1,646 (2.79×: the selection line's props as a patch, against the HEEx line's diff). No action over the note's flag of 1.5× for a page change. Times, medians, after rows drawn only where their item changed: page change 108 → 170 ms, cell save 70 → 131 ms, cell save in a nested table 55 → 170 ms, open a nested table 86 → 135 ms, expand a row 24 → 33 ms, open the picker 44 → 60 ms. React draws in the browser what LiveView patched; the saves are the slowest, to be looked at (open).
- **The bundle** (one for every page, Q14), minified, gzip -9: JS 144,403 → 151,181 B (**+6.8 KB**), CSS 21,684 → 23,683 B (**+2.0 KB**), against R1's islands.

### The suites, once each at the end (2026-10-20)

- Root `mix test`: 1297 tests, 0 failures (load 1.8 → 1.6).
- Demo `mix test`: 3089 tests, 0 failures (load 1.6 → 11.6).
- The whole browser suite, both projects (`E2E_FIRST_PORT=4490 E2E_WORKERS=4`): 1708 passed, 0 failed, 0 flaky, in 22.0 min (5 setup, the default kit's 1006, the `react` project's 697; load 11.6 → 7.2).

### Changes in the library

- `Kit.Words` (`:grid`): the per-column constant texts (above); `Live.Drawing` passes the columns.
- The `heading` part is given `label_column` (**addition**, not asked by the note): a kit's own heading can draw "Columns" without `Model.label_column/1`; `Kit.Default`'s heading uses it (`Parts.Grid.hideable/1` gone, its tests moved to `Model.label_column/1`).
- `focus.js` `repair`: focus that was in a nested table goes to its line's button also where the cell the nested table stood in stays, empty (a kit that draws the place ahead keeps it): the rule was "the holder is gone". Found by `nesting.spec.ts` in the `react` project.
- `Item`'s moduledoc names where a kit that draws the rows finds the constant texts.

### The suite, so that it holds for both kits

`support/table.ts`: the editors' templates by id (`editorTemplates`), `forge` and `answered` through the table's sender (the LiveView hook every kit draws) instead of the grid's LiveView hook, `BADGE` (the one element a Badge cell holds) in place of daisyUI's `.badge`; `selection.spec.ts` checks the destructive action's `data-destructive` for both and daisyUI's classes for the default kit only; `components.spec.ts` sets a template's question by id.

### Divergences and questions for the owner

- **D1** (editors as HEEx templates, Q8's fallback for another reason) and **D2** (heading frame and argument line stay HEEx): each needs a seam of the library to close (above). Proposed: in R3, give `editor` and `argument_line` what their controls say. **Closed in the fix-up (owner, 2026-10-20: "the whole UI must be React/shadcn"), below.**
- **D3:** the kit is chosen per request in the e2e environment by a dispatching kit (`DemoWeb.E2E.ChosenKit`) and the kit noted in the LiveView's process at mount (LiveView's documented telemetry, as `DemoWeb.E2E.Sandbox` hears it): e2e only, never in dev or prod. **Accepted by the owner 2026-10-20.**
- **D4:** `flushSync` around live_react's `mounted`/`updated` (React's public API; a wrapper of live_react's public hook object): the kit's hook, not live_react's own timing. **Accepted by the owner 2026-10-20.**
- Additions: `yes`/`no` among the grid's texts; `label_column` for the heading (**accepted by the owner 2026-10-20**); the `ash-react:gone` event (the kit's own seam, for its test).

### The fix-up (2026-10-20)

The owner's decisions of 2026-10-20, as recommended: close D1 and D2 now; find why saves are slower on `/react/tasks` and fix the cause where that can be done cleanly; D3, D4 and `label_column` accepted (above).

**D1 closed: the editors are React's.** The library gives the `editor` part what its control says, as plain data that goes to JSON (`Kit` moduledoc, part `editor`; `test/kit_test.exs`): `limits` (`min`, `max`, `step` of a number, each text or nil), `counted` (how a text with a most it can be long is counted: `max`, `unit`, `trim?`, `casing`; nil for none) and `clearable?` (a sensitive cell can be emptied). The `grid` part gets the same by column name, `editors`, for a kit that draws the editors itself. `Kit.editor/1` passes them (`Kit.editors/1` and the private `editing/1`, which call `Model.Limits` and `Edit.clearable?/1`), and `Kit.Default`'s `editor` draws from them: no call of the internals is left in it for these. The React kit's island draws a `<template>` per editable column (`Attrs.editor_template/3`) and the failure template, and each editor into its template's content with `createPortal` (Q8 as recommended; `Editors.tsx`, the part `Editor`); a column whose component edits is drawn by the React component of its module (`reactKit({editors: …})`: the library's `Slider` and the demo's `Progress` and `Hours`), else as text with a warning in development. The slider has a look of its own (`react_kit.css`), which `contrast.spec.ts` checks in both themes and forced colours, as it did daisyUI's.

**D2 closed: the heading line and the argument line are React's.** The library gives `heading` and `argument_line` `arguments`: per argument of `model.arguments`, in its order, what its input is drawn with, as plain data: `id`, `named`, `name`, `value`, `errors` (messages, `%{key:, values:}`: they were the internal tuples), `limits`, `counted`, `texts`, `messages` (`Kit.arguments/5`, called by `Live.Drawing`). The `argument` part is given `limits` and `counted` too; `Kit.Default`'s argument line draws from `arguments` and calls no internal. The React kit's `heading` is the island `AshHeading` (`Heading.tsx`, parts `Heading`, `Columns`, `ArgumentLine`, `Argument`): the name, "Columns" (no island of its own any more: `AshColumns` and the kit's `columns/1` are gone), the argument line as a form of the island's (LiveView hears its `phx-change`/`phx-submit` from its root), create and the table actions. A counter is drawn as the server's value comes (a new element per value), its text counted as the hooks count: the library's JS exports `count(text, counted)` (`assets/js/index.js`), the hooks' own counting. `arguments.spec.ts` runs in the `react` project now. To stay in contract 3, `heading` and `argument_line` are still given `lines`, `refused` and `state`, which neither kit reads now (question below).

**Why the saves were slower: the evidence.** Each save on `/react/tasks` split, in the page, into the time to the answer's frame and the time after it, with a CPU profile of the page bucketed by the bundle's modules (a throwaway script beside `baseline.mjs`; R2's code, `e1c9864`, 10 saves each):

| Cell save, median | Enter → frame | total | Server callbacks | CPU in `react`/`react-dom`/islands |
| --- | --- | --- | --- | --- |
| `/tasks` | 34 ms | 72 ms | 26 ms | – |
| `/react/tasks`, R2's build | 76 ms | 201 ms | 20 ms | 69 + 34 + 9 ms |
| `/react/tasks`, React's production build | 39 ms | 87 ms | 25 ms | 0.5 + 10 + 4 ms |

1. **The perf environment measured React's development build.** Unminified, esbuild sets `process.env.NODE_ENV` to `development` (it follows `--minify`), so `MIX_ENV=perf mix assets.build` bundled `react-dom-client.development.js`: StrictMode's double renders and effects, React's checks and its owner stacks (`console.createTask`). Production (`assets.deploy`, minified) never runs it. With React's production build R2's code saves in 81 ms (`baseline.mjs`, one run: nested save 71, page change 108, open a nested table 92). Not the server: its callbacks and the bytes are the same; not the wire.
2. **Every cell was drawn again whenever the hook took or gave back a cell.** The cells the hook holds (being edited, `aria-busy`) were a React context of the grid that every cell read: a save changed it four times (the edit ends, the cell busy, busy no more, …), and each change drew all 550 cells of `/tasks`' page again, about 5 ms each (counted by instrumenting the throwaway build); a save in a nested table drew the 550 cells of the table around it too (its observer saw the nested cell's `aria-busy`). The row's own patch drew 22 cells: the rows' `memo` held.

**The fix.** (1) `config/config.exs` bundles React's production build in the perf environment (`--define:process.env.NODE_ENV="production"`, perf only; dev and e2e keep the development build and StrictMode). (2) The held cells are a store each cell hears by its own id (`useSyncExternalStore`, `Grid.tsx`): only the cell taken or given back is drawn again.

**Before and after** (`baseline.mjs`, `PERF_WIRE=1`, 15 repetitions, ports 4490/4491, temporary worktrees of `e1c9864` (A) and the fix-up (B), run A, B, B, A per page; load 7.1 falling to 3.6; the mean of each pair's medians):

| Action | `/tasks` A → B | `/react/tasks` A → B |
| --- | --- | --- |
| Cell save | 68.8 → 67.1 ms | 145.9 → 68.7 ms |
| Cell save in a nested table | 55.3 → 54.7 ms | 181.1 → 66.3 ms |
| Cell save, a nested table open | 58.1 → 62.0 ms | 159.8 → 59.0 ms |
| Page change | 110.3 → 113.6 ms | 151.7 → 102.9 ms |
| Open a nested table | 89.5 → 88.6 ms | 133.6 → 95.6 ms |
| Expand a row | 23.8 → 23.6 ms | 33.4 → 20.3 ms |
| Open the picker | 45.9 → 46.9 ms | 65.7 → 40.8 ms |
| Select a row | 5.1 → 4.6 ms | 7.0 → 7.9 ms |

R2's measured gap (cell save 70 → 131, nested 55 → 170, page change 108 → 170, open a nested table 86 → 135) is gone but for a nested save (54.7 against 66.3 ms) and opening a nested table (88.6 against 95.6 ms). A's React times are R2's method (its development build); B's are of the production build.

**The default kit's bytes** (the 2 % budget), the same runs: identical per action but a page change, 158,220 → 157,703 (−0.3 %); open the picker 40,163 both, open a nested table 42,009, cell save 8,605. On `/react/tasks` a page change 124,608 → 125,409 (+0.6 %: the heading's props), open a nested table 30,123 → 29,265.

**Left open, for the owner.**

- `heading` and `argument_line` are given `lines`, `refused` and `state` as before, though both kits now draw the argument line from `arguments`: taking them away changes the parts' assigns in a way an existing kit cannot follow, which by the moduledoc's rule raises the contract to 4. Kept in contract 3; to be decided. **Done in the second fix-up (contract 4), below.**
- Still `Kit.Default`'s in the React kit: the root, `related` (the line above a table limited to related records), the messages, and the panel, picker and question (R3). `Kit.Default`'s panel parts (`field`, `control`, `list`, `count`) still compute limits and counters from the internals: R3's seam. **`related` and the messages moved in the second fix-up; the root did not (below).**

### The second fix-up (2026-10-20)

The owner's decisions of 2026-10-20, as recommended, under the rule "the whole UI must be React/shadcn": move to React what the React kit still drew as HEEx but the panel, picker and question (R3): the root frame, `related` and the messages; take `lines`, `refused` and `state` away from what `heading` and `argument_line` are given, and raise the kit contract to 4.

**`related` and the messages are React's.** Two islands, each a part replaceable by name (`reactKit({Related: …, Message: …})`, `parts.tsx`), the same for a nested table as for the table on the page:

- `related` is the island `AshRelated` (`Related.tsx`, the part `Related`): the heading (the relationship, or its words before and after the record, the record a live_react `Link` to its own table's page where the router mounts one), create and the table actions (their bundles, `Attrs.create/2`, `Attrs.table_action/3`) and "Show all records" (a `Link` that patches). `DemoWeb.ReactKit.Props.related/8` picks it of the part's assigns.
- `message` is the island `AshMessage` (`Message.tsx`, the part `Message`), one per message said in place of the rows (an error, `role=alert`; a nested table's first read on its way; an argument to fill; "No records"): `Props.message/4`.

No seam of the library was needed: both parts are given plain values and the documented fields of `Model.Action` (`label`, `name`), and their texts. `react_kit_test.exs` checks the props of both ("No records" after a filter that matches nothing; a table limited to a project's tasks).

**A fix in the drawing, for every kit.** `Live.Drawing` draws the messages keyed by their kind (`:key={kind}`, LiveView's keyed comprehension). Without it, a nested table whose first read found nothing showed "Loading…" in the React kit for good: the comprehension's slot was the same, the island of "No records" a new element (another id), and that new element came with the props of the "Loading…" island before it (its `data-props`, seen in the browser as the element was added), which live_react drew. Found by `nesting.spec.ts`, `a11y-nesting.spec.ts` and `full_view.spec.ts` in the `react` project; a message of another kind is now another item of the comprehension, drawn anew. The default kit's markup is the same; its bytes grow by 4 per opened nested table (below). Whether LiveView or live_react should give such an element its own props is a question for them, not taken further here.

**The root stays `Kit.Default`'s: an exception, accepted by the owner 2026-10-20.** The root (`root/1`) is the element that holds every other part of a table: the islands, the filter row's form and the sender (C9, which must be markup of the LiveView's), the messages, and in its slot `opened` the question, the panel and the picker, whose content LiveView patches. React cannot draw an element whose children LiveView patches (live_react draws HEEx children once, as dead HTML: section 3, "a container part as an island"), so the root could be React's only if every part it holds were moved into a place React draws (a portal per part, as Q2 does for the slots of the panel and picker). That is a decision the note does not cover: section 6 ("What stays HEEx: the kit's `root/1`, an element with its bundle, no visible UI") and Q2 ("The root stays a HEEx element in every kit") keep it HEEx. The root draws nothing to be seen: its bundle (`Attrs.root/2`, the markers), the kit's class (`class(:root, …)`, the React kit's look and the `shadcn` scope), the look's heights as custom properties, and the empty element the skip link jumps to (`Attrs.skip_target/1`). Proposed: keep it so (the rule's "UI" is what is seen), or decide at R3 together with Q2 whether every part goes into a place a React root draws, measured as M4 is. **Accepted by the owner 2026-10-20: the root stays `Kit.Default`'s, an exception.**

**Kit contract 4** (**accepted by the owner 2026-10-20**). `heading` and `argument_line` are no longer given `lines` and `refused`, and `argument_line` no longer `state`: both kits draw the argument line from `arguments`. `heading` keeps `state`: its "Columns" says what is filtered and sorted (`Kit.Default`'s `columns` part is given it, the React kit's `Props.heading_columns/6` reads it), so the premise "no kit reads them" held for `lines` and `refused`, not for the heading's `state` (**divergence D5**: to take it away too, "Columns" would be given what is filtered and sorted by column, a seam of its own; **accepted by the owner 2026-10-20**: `heading` keeps `state`). `use AshDataTable.Kit, contract: 4` everywhere (`Kit.Default`'s moduledoc, `KitCase`'s probe kit, `DivKit`, the test kits, `ChosenKit`, `ReactKit`, the guides `kits.md` and `mistakes-at-compile-time.md`, the CHANGELOG); "Kit contract 4" in `Kit`'s moduledoc, with what changed; a kit of contract 3 fails to compile and is told so, one of 1 or 2 every step since (`changed/1`). `kit_test.exs`: the message of each older contract, and that a kit's `heading` and `argument_line` are given no `lines` and `refused`, the argument line no `state`.

**Measured** (`baseline.mjs`, `PERF_WIRE=1`, 15 repetitions; temporary worktrees of `1bda22b` (A, the first fix-up) and `bcd87ac` (B, this fix-up's code), on ports 4490/4491 and 4492/4493; run A, B, B, A per page, /tasks first; load 10.5 falling to 1.6, then 2.0 to 3.2; the mean of each pair's medians):

| Action | `/tasks` A → B | `/react/tasks` A → B |
| --- | --- | --- |
| Cell save | 77.1 → 76.9 ms | 80.8 → 79.8 ms |
| Cell save in a nested table | 68.8 → 64.6 ms | 81.2 → 75.4 ms |
| Cell save, a nested table open | 69.4 → 68.7 ms | 84.5 → 67.4 ms |
| Page change | 129.3 → 137.8 ms | 122.2 → 118.7 ms |
| Open a nested table | 104.8 → 103.2 ms | 105.8 → 111.5 ms |
| Expand a row | 25.4 → 26.9 ms | 20.6 → 21.5 ms |
| Open the picker | 53.3 → 56.0 ms | 52.0 → 46.0 ms |
| Open the panel | 45.5 → 37.0 ms | 31.2 → 31.4 ms |
| Select a row | 4.9 → 4.0 ms | 6.1 → 6.4 ms |

- **The default kit's bytes** (the 2 % budget): identical per action but two, each +4 bytes (the keyed messages): page change 157,703 both, open the picker 40,163 → 40,167 (+0.01 %), open a nested table 42,009 → 42,013, cell save 8,605 both. On `/react/tasks` a page change 125,411 both, open a nested table 29,265 → 29,454 (+0.6 %: the "Loading…" island's props).
- **`/react/tasks` against the first fix-up.** Run beside it on the same machine, this fix-up's times are the first fix-up's or better, but opening a nested table (+5.4 %: 102.7 and 108.9 ms against 114.8 and 108.3, the pairs overlap; the "Loading…" message is an island now, mounted and taken away again as the table reads). The first fix-up's own figures (cell save 68.7, nested save 66.3, page change 102.9, open a nested table 95.6, open the picker 40.8 ms) were not reached by either today: its own code (A) measured 80.8, 81.2, 122.2, 105.8 and 52.0 ms, and /tasks, whose code did not change, 10–17 % slower than then too (cell save 67.1 → 77.1, page change 113.6 → 129.3): the machine, not the change.

**The suites, once each at the end** (2026-10-20):

- Root `mix test`: 1300 tests, 0 failures (load 2.9 → 3.7).
- Demo `mix test`: 3090 tests, 0 failures (load 3.5 → 14.8).
- The whole browser suite, both projects (`E2E_FIRST_PORT=4490 E2E_WORKERS=4`): 1729 passed, 0 failed, 0 flaky, in 25.6 min (5 setup, the default kit's 1011, the `react` project's 713; load 13.9 → 9.9).

**Left open, for the owner.** The root (an exception, above), D5 (the heading's `state`) and contract 4: **accepted by the owner 2026-10-20**. Still open: whether a new island element given the props of the element before it in the same slot is LiveView's or live_react's to fix.

### The drift-check fix-up (2026-10-20)

The owner approved every finding of R2's drift check (2026-10-20). What was done:

- **Every part replaceable by name, the islands' own too.** `Filter` and `Pagination` were in `DEFAULT_PARTS` but drawn directly, `SelectionLine` and `Status` were no parts. Now every island takes its outer part through `usePart` (`Grid`, `SelectionLine`, `Status`, `Pagination`, besides `Heading`, `Related` and `Message`), and so does every part it draws, nested tables alike: new parts `FilterCell`, `Resizer`, `FullView`, `Count` (the counter of a cell's editor and of an argument's input, one part) and `Failure` (a failed cell's and actions cell's message, and the failure template's) (`parts.tsx`). What stays inside a part is its own markup (a masked value, a yes or no, the controls of a filter or an argument), as `Kit.Default`'s parts keep their helpers.
- **Our own `dom_id`.** The rows are keyed and named by the item's `dom_id` (the stream's `dom_id: & &1.dom_id`, `Live.Registry`), not live_react's `__dom_id`, which is gone from the types.
- **The skip link and the scrollbar spread their bundles** (`Props.skip/1`, `Props.scrollbar/1`: `Attrs.skip/1`, `Attrs.scrollbar/1`, without `phx-update`), as O8 asks, in place of hand-written attributes.
- **`react_kit_test.exs` on documented APIs.** It reads each island with `LiveReact.Test.get_react/2` by the id the kit gives it (Floki, test only), no longer live_react's `data-name`/`data-props` markup nor a copy of its `@doc false` decoder. live_react sends the props in full in the test environment (`enable_props_diff: false`, as `LiveReact.Test` advises), so the test reads every prop in every state (at rest, a nested table open, sorted, filtered and not, a row selected, "No records", a table limited to a project's tasks) and checks that each island's props are exactly the kit's and hold what the state holds; the patches are the browser suite's. The rows are the stream, beside the props (their JSON is `item_test.exs`'s). The moduledoc says so.
- **More of the suite in the `react` project.** `actions.spec.ts`, `table_actions.spec.ts` and `open.spec.ts` run there too. Only the single tests that need the action panel or the question (R3) are tagged `@heex` (Playwright's `{ tag: "@heex" }`, which the project's `grepInvert` matches; §7.3), never a whole file: in `actions.spec.ts` the question of an action that asks first (7 tests), a refused destroy (Confirm), the action panel (8), creating a record through the panel (5), creating in a nested table and in the full view through its panel (4), the dashboard's panels and dialogs (2) and the panel's look (2); in `table_actions.spec.ts` one that makes a label through "New label"'s panel first, the question (2, each after "New label" too), the panel (3) and the nested table's own question and panel (1). Each says so in its file's header; R3 takes the tags away.
- **Docs.** The root exception, D5 and contract 4 marked accepted (above); target.md's S3 and `Item` row say contract 4 with a pointer to `Kit`'s "Contract versions" (the owner's yes for this correction only; R2 not ticked); the CHANGELOG has `/react/tasks` and the React kit, the grid's per-column constant texts, `label_column` for `heading`, the JS `count` and the messages keyed by kind; the demo's README and `ReactTasksLive` name every island; the architecture map's `Parts.Grid` row has no `hideable/1`.
- **No change in the library**, so the default kit's bytes are as they were; no `PERF_WIRE` run.

**The suites, once each at the end** (2026-10-20):

- Root `mix test`: 1300 tests, 0 failures (load 6.4 → 7.6).
- Demo `mix test`: 3090 tests, 0 failures (load 7.0 → 15.3).
- The whole browser suite, both projects (`E2E_FIRST_PORT=4490 E2E_WORKERS=4`): 1754 passed, 1 failed, 0 flaky, in 27.0 min (5 setup, the default kit's 1011, the `react` project's 739; load 14.1 → 12.6). The failure is the default kit's `tab_order.spec.ts:476` ("a page change from inside the rows"): its last assertion, that the window did not scroll, read a different `scrollY`. Nothing of the default kit or of the spec changed; run alone once afterwards (load 7.0) it passed. A timing fault under load, **left open** to be looked into (where the scroll comes from after `goBack`), not fixed here.

## 16. Stages 3 to 5 (R3, R4, R5) as built (2026-10-20)

Built in one go on the owner's decisions of 2026-10-20 after Phase 0 (below). Nothing is left open but what is marked so; each item names where it is built and tested.

### The decisions of Phase 0 (owner, 2026-10-20)

| # | Decision |
| --- | --- |
| A (13 e, Q2) | One drawing for every kit: the `panel` and `picker` parts are drawn always, given nil while closed; what opens inside them goes by `<.portal>` into their places. C8 reads "no later than the patch that opens it" for these places too: `Kit.Default` draws nothing while closed and the place as it opens; the React kit draws both closed, with their places, ahead. Kit contract 5 |
| B (uploads) | live_react's `upload`/`uploadTo` need a `live_file_input` in the page (LiveView's `dispatchUploads`). One hidden `live_file_input` per file field, beside the island, in the island's form (`form=`); the visible control, progress and entries are React's, and hand the files over with `uploadTo` |
| C (R4's browser check) | The spec reaches each state by the UI, driven by Playwright; it posts the DOM as drawn to an e2e-only route that runs `KitCase`'s checks through a new public `KitCase` function over an HTML string; a development check's or `props.ts`'s C6 message fails it |
| D (R5's fresh host) | A one-off check in the session's scratchpad, recorded here, then removed |

### R3: the panel, the picker and the question as React parts

- **Contract 5, the drawing** (`c8979fb`). `Live.Drawing.body/1` draws the `panel` part always (`open_panel/3`, nil while closed or while the host draws it, controlled mode) with `fields` (`Kit.fields/3`), and the `picker` part always (`open_picker/2`); the panel's slot content (a picker where the panel is modal and the picker inline, which is drawn closed in the panel while the panel is open; the question's copy) and the picker's (its table; the question's copy) go by `<.portal>` into `Ids.panel_place/1` and `Ids.picker_place/1`, marked `data-ash-data-table-portal` with the place (so `AshDataTable.Test.page/1` and the snapshots put them in). The drawing gives the two parts what they are made of field by field (the entry's `panel` and `picker`, the options' `controlled`; the picker's table by `@table.entries`, the entry's id and its picker), so that LiveView draws a closed one again only when one of them changes: a React island's props are sent again whenever its part is drawn again (first measured: +1,230 bytes per cell save on `/react/tasks`, the panel's and the picker's props, gone after this). `Kit.Default`'s `panel` and `picker` draw nothing while closed and the place after the form or title as they open (`parts/panel.ex`, `parts/picker.ex`). `Kit` moduledoc: the parts, "The places a nested table is moved into", "Contract versions"; `changed(4)`; `test/kit_test.exs` (the message of a contract-4 kit). `ids.js` mirrors the two ids (`/e2e/ids`, `contract.spec.ts`). The snapshots changed only by the place element and the portal's marker (six files, reviewed).
- **No internal call left in the default kit's panel parts.** `Kit.fields/3` (`@doc false`, beside `Kit.editors/1` and `Kit.arguments/5`) gives each field's assigns with `limits`, `counted`, and what a value made of fields holds (`members`, `items`, `kind`, `single`: what `Parts.Panel`'s group helpers worked out with `Act.items/1`, `Act.kind/3`, `Act.fresh/2` and `Present.in_union?/2`); `Parts.Panel.field/1` and its helpers draw from them (`kit_test.exs`, "the panel is given each field's assigns"). The `count` part counts with the new public `Kit.count/2` (`739bc98`; `kit_test.exs`), not `Model.Limits`. The markup of every panel snapshot is unchanged.
- **The group buttons' bundles** (`4bc10fe`). `Attrs.add_group/3` and `remove_group/3` carried a `JS.push` command, which a client framework cannot spread (the command's JSON is LiveView's own); they are plain `phx-click` with the way as a JSON list in `phx-value-path`, which `Intent.parse/2` decodes (`intent_test.exs`; `union_table_test.exs`; snapshots 06a, 07a, 07b).
- **The React parts** (`4738421`). `ReactKit.confirm/1`, `panel/1`, `picker/1` draw the islands `AshConfirm` (`Confirm.tsx`; its island's id is `ID-dialogs`, `-in-panel`, `-in-picker`), `AshPanel` (`Panel.tsx`: the parts `Panel`, `Field`, `Control`, `List`; groups, lists of groups, unions, a reference and several, a sensitive field's Clear and Keep, a component's editor by its module, a file) and `AshPicker` (`Picker.tsx`), each a part replaceable by name (`parts.tsx`). Native `<dialog>` (modal) or `<section>` region (inline) with shadcn's classes (`react_kit.css`); the hooks open them: `useMountedWhile` (`mounting.tsx`) mounts `mountPanel`/`mountPicker` on the element as it opens and destroys the hook and closes the dialog as it closes. A list field's rows are drawn once per opening (`React.memo` that never draws again), as the default kit's `phx-update="ignore"`. `Props.confirm/6`, `panel/6`, `picker/6` (`react_kit/props.ex`), the bundles without `phx-hook`, `phx-update` and now `phx-mounted`. `react_kit_test.exs`: the three islands' props, closed and open, go to JSON.
- **Uploads** (decision B). `ReactKit.panel/1` draws `live_file_input` per file field with `form="ID-panel-form"` and `hidden`; `Panel.tsx`'s `FileField` hands the chosen files to it with `uploadTo(form, name, files)` (its own change and input events stop at the island), shows each entry's progress and empties itself when the server holds no entry any more. `files.spec.ts` in the `react` project.
- **Controlled mode** (`controlled.spec.ts` in the `react` project). The answer to a held save that no patch reached (`saving.js` `answered`): saved, the hook puts the cell's own content back before it takes `aria-busy` away (a React kit holds a busy cell as it was and draws it from its row once it is not: else React met children the hook had replaced and threw). A HEEx kit's patch always comes first (`patched`), so nothing changes for it. The one assertion that differs by kit: while a held cell waits and another cell's save sends its row again, the default kit shows the record's value (LiveView's patch), the React kit what was typed (it holds the busy cell, §15 "a cell the hook holds"); `controlled.spec.ts` says so per project. **This follows from R2's accepted hold rule; the owner may want to look at it.**
- **The `@heex` tags** are gone (36 in `actions.spec.ts` and `table_actions.spec.ts`); `arrays.spec.ts` finds the editors' templates by id, as `table.ts` does.

### R4: verification

- **`KitCase` with `client: true`** (`lib/ash_data_table/kit_case.ex`; `demo/test/demo_web/kits/react_kit_case_test.exs`: 80 tests). The texts contract (the probe kit) and that no page holds `Test.Resource.secret/0`, which for the React kit is that no island's props (in `data-props`) and no stream item were given it; the events from the grid's sender, a form as its event. A mutation (the secret in a prop of `Props.confirm/6`) failed it, and was taken back.
- **`KitCase.problems/4`** (public, documented): the markers, ids, element kinds and Tab stops `KitCase` checks, over a page's HTML as the browser drew it; `:row_selected` beside the states; the hooks' elements without `phx-hook` there (a kit mounts them itself).
- **The kit check in the browser** (`fb850f8`, decision C). `e2e/kit_check.spec.ts`: KitCase's 20 states × 4 presentations, each reached by the table's controls on `/e2e/kit/states` (`DemoWeb.E2E.KitStatesLive`: KitCase's table and records for the state, `KitCase.given/4`, drawn with the kit the request asks for, so the `chromium` project checks the default kit and `react` the React kit), `loading` taken in the patch that draws it (a `MutationObserver`), `links` through the nested table's full view into `/e2e/kit/parts` (`KitTenant`), each page posted to `/e2e/kit/check` (`KitCheckController`); LiveView's client debug asserted on. It found, and the build fixed: the development check of a hook a kit mounts ran before the patch's later islands were drawn (`mount.js` runs it after the task of the mount); `KitCase` asked for `phx-hook` on the elements of hooks a kit mounts. `lazy_html` is a dependency of the e2e environment too.
- **The React kit's own development check** (`props.ts`): a bundle or an item's `attrs` that names an attribute the hooks own as "never" (`OWNED`, `owned.js`) is said with `console.error` in development, which fails a browser test. `id`, `hidden`, `aria-busy` (the table while it reads) and `data-destructive` (an action's button) are left out: the table gives them for elements of its own that are not the ones the hooks write them on.
- **The whole suite as the `react` project** (`playwright.config.ts`: no list of files any more).

### R5: the guide and the demo page

- `documentation/topics/react-kit.md` ("A kit drawn in React": the recipe, the contracts, customizing, testing, edge cases and traps; `mix.exs` extras, `documentation_test.exs`); `kits.md` points at it. `/react/tasks` is linked from the demo's front page (`HomeLive`, `#react`); `demo/README.md` names every island and the kit check.
- **The package import from a fresh host app** (decision D): `mix phx.new freshhost --no-ecto` (Phoenix 1.8.15) in the scratchpad, `{:ash_data_table, git: <the repository>, branch: "main"}` (commit `a5cd908`), so the package is in `deps/`; `assets/js/app.js` imported `mountGrid, mountPanel, mountPicker, mountPagination, liveViewTransport, ids, OWNED, count` from `"ash_data_table"`; `mix assets.build` (compile, Tailwind, esbuild with the generated `NODE_PATH` of `deps/` and the build path, nothing added) bundled them (476.8 KB). Removed afterwards.

### Ticket #50

`tab_order.spec.ts` "a page change from inside the rows": the window's scroll after `goBack` was LiveView's scroll restoration, not the table's. The click on "Next" scrolls the window to the button; LiveView's scroll listener records that for the current history entry 100 ms later; the back button scrolls back there (`maybeScroll`). Under load the listener fired before the click's `pushState`, so the first page's entry held the scroll at "Next", while the test's focus into page two's rows had scrolled the window up a little. Reproduced by waiting 300 ms before the click (a throwaway spec): 353 against 365. Fixed by focusing the cell without scrolling the window (`focus({preventScroll: true})`), so the window is where LiveView restores it whatever its listener did (`12eff46`, "Fixes #50"; `tab_order.spec.ts` once in both projects, green).

### Measured (2026-10-20)

`demo/perf/baseline.mjs`, `PERF_WIRE=1`, 15 repetitions, temporary worktrees of `775aad1` (A, the start of this build) on 4490/4491 and of this build's code (B) on 4492/4493, run A, B, B, A per page, `/tasks` first; the mean of each pair's medians. Load 5.6 falling to 4.7, then up to 12.2 during the `/react/tasks` runs (the B runs of `/react/tasks` at 10.6 to 12.2), ending at 8.0.

- **The default kit's bytes** (the 2 % budget): page change 157,735 → 157,771 (+0.02 %), open the picker 40,167 → 40,911 (+1.85 %: the picker's table moved by a portal, its place and the portal's marker), open a nested table 42,013 → 42,211 (+0.5 %), cell save 8,605 → 8,629, select a row 591 → 603, open the panel 4,450 → 4,449. (The note's figures of R2, 157,703 and 40,167, were of the same code A; today's A measures a page change at 157,735.) Every action within 2 %.
- **M4, open the panel and open the picker** (ms, A → B): `/tasks` open the panel 36.3 → 38.5, inline 16.8 → 18.3, open the picker 52.5 → 50.2; `/react/tasks` (where B draws them in React, A with the default kit's HEEx) open the panel 31.9 → 49.2 (4,151 bytes against 5,743), open the picker 47.5 → 66.7 (37,323 bytes against 34,622). React draws the panel's form and mounts its hook after the patch; the `/react/tasks` B runs had the heaviest load of the evening, so these are not taken as more than "slower by 15 to 20 ms".
- **The rest of `/react/tasks`** (A → B, bytes): cell save 12,805 → 12,829, page change 125,442 → 126,027, select a row 1,646 → 1,658, open a nested table 29,765 → 31,478 (+5.8 %: the nested table's closed panel and picker islands). Times, under the load above: cell save 78.3 → 93.9 ms, page change 221.3 → 196.3 ms (A's pair 149.8 and 292.8), open a nested table 108.5 → 172.0 (B's pair 125.5 and 218.5). Too noisy under that load to say more than that nothing became faster.
- `/tasks` times: every action within ±6 % (page change 132.1 → 139.4 ms, A's pair 114.1 and 150.2).
