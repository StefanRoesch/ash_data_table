# A React/shadcn kit: design note

Status: **accepted, 2026-10-18; stage 0 (R0) built 2026-10-19, with the fixes of its drift check; R0 is done once the owner says yes.** It carries the owner's decisions of 2026-10-18 (O1–O9 below) and of 2026-10-19 after stage 0 (section 13, which amends C1, C3, C6, C8, Q4 and section 3). The questions of section 10 were answered as recommended. The amendments to [target.md](target.md) are made (section 12). Code references are of `202ebe4`. The research and the spike are throwaway: `research.md` and `spike.md` in the session's scratchpad (`react-kit/`), and the spike's code on the branch `worktree-agent-ae45e1e4887377ba7` (commit `f9e43ff`, not on `main`). Words follow `CONTEXT.md`. The model for this note is [stage7-design.md](stage7-design.md).

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
- The grid hook runs on React's DOM, mounted by hand: arrow keys, roving tabindex, sort, expand, open a line, the tab stop across nested grids, Enter opens an editor.
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
| C6 | The attributes the hook owns | Each attribute the hooks write, with what a kit may render of it (13 h): **never** (`aria-selected`, the boxes' `checked`, `aria-busy`, `phx-update` on an edited cell, the whole-text button `data-whole`, `data-over`, `data-dragging`, …), **once** as the table gives it and then left to the hook (`tabindex`, `aria-rowindex`), or **given**: rendered as the table gives it and again only when it gives another value (`aria-invalid`, `aria-describedby`, `aria-readonly`, `data-value`, `data-saved`); and the contents the hooks write (a cell while it is edited, …). The full list is made from every `setAttribute`/`removeAttribute`/`toggleAttribute`/`replaceChildren` of `assets/js/` | `assets/js/owned.js` (exported) and `Kit` moduledoc | A test that greps `assets/js/` and compares with `owned.js`; the React kit's development check warns when a rendered prop names one |
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
| **1. Tooling** | npm in `demo/assets`; esbuild `--jsx=automatic`, `NODE_PATH`; `config :live_react, ssr: false`; `getHooks` in `app.js`; Tailwind `@source "../islands"`; the `.shadcn` scope with `--sh-*` tokens and dark mode on `data-theme`; the folder `assets/islands/`; the demo's test hook imports the package, not a relative path (13 g); a recipe in the demo's README | A page with one island builds in dev and in `MIX_ENV=e2e`; daisyUI's look elsewhere unchanged (contrast and a11y specs green) | npm only under `demo/`; the library's `mix.exs` and `package.json` unchanged |
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
| +97.5 KB gzip of JS on every page of the demo | Demo only; reported in M3; a second esbuild entry for React pages if the owner wants it (Q14) |
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
