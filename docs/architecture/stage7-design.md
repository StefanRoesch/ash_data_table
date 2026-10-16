# Stage 7: design note (markers, bundles, the kit, what opens, controlled mode widened)

Status: **accepted by the owner on 2026-10-16, all as recommended (D1–D22).** Code references are of `6c0245b`. LiveView references are of the installed `phoenix_live_view` 1.2.12 under `demo/deps/phoenix_live_view/` (written `LV …`). The research is `ash_reference/headless-table-architecture.md` (written `R §n`, outside the repository). Names follow [target.md](target.md); words follow `CONTEXT.md`. The model for this note is [stage6-design.md](stage6-design.md).

Stage 7 is the last stage of the refactor. It makes the look and the behaviour of every UI element replaceable against a contract that can be checked: the hooks find the table's elements by markers only, every element gets its markers from one place (`AshDataTable.Attrs`), a kit draws the parts, and a host can take over what opens (controlled mode) for every kind of thing that opens on the table on the page. The table stays "just an interface" to the resource: whatever a kit or a host draws, the inputs go back through `Operation`, and nothing sensitive reaches a part.

## 0. The decisions at a glance

Answer "as recommended", or per number.

| # | Question | Recommendation |
| --- | --- | --- |
| D1 | One build or several | Three, each with its own drift check and its own single run of the three suites: **7a** markers and bundles (no public API), **7b** the kit, what opens, `KitCase`, **7c** controlled mode widened |
| D2 | What a marker is | An ARIA role where the element has one (`grid`, `row`, `rowgroup`, `gridcell`, `columnheader`, `dialog`), else the `data-*` attribute the table already writes. Nothing new on a row or cell. Every name in `assets/js/markers.js` and in `Attrs`, side by side |
| D3 | The shape of `AshDataTable.Attrs` | One function per element, returning the complete attribute map (id, role, ARIA, `data-*`, `phx-*`, `phx-hook`); a part spreads it. Internal module; its content is the contract. Bytes per row measured; fallback in D21 |
| D4 | How the hooks stop relying on tags | Structure by markers; positions by `aria-rowindex`/`aria-colindex` in place of `rowIndex`/`cellIndex`; "which grid owns this element" by `closest('[role=grid]')`. A native control's kind (`TEXTAREA` vs `INPUT`) may still be asked of an element first found by a marker |
| D5 | The three class toggles and the theme in the hooks | Gone. The hook sets attributes (`data-destructive`, `aria-disabled`); the kit styles them. The hooks' colours are `--ash-data-table-*` properties the kit sets, not daisyUI's `--color-*` |
| D6 | The table's own structural style (the 3.4 KB class list on every `<table>`) | Moved, written on markers, to the root of the table on the page, once per page; nested tables and pickers' tables send none of it |
| D7 | `AshDataTable.Kit` | A behaviour with one callback per part and `class/2`; `use AshDataTable.Kit, contract: 1` delegates every callback to `Kit.Default` (`defoverridable`, so `super` works); checks at compile time. `class/2` is called for parts drawn once per table, never per row or cell; row and cell state is styled through attributes |
| D8 | The parts of contract 1 | The list of section 3.8 |
| D9 | Where a kit is named | `config :ash_data_table, kit:`, `kit=` on the tag, `kit:` at attach and on the router line (Q12). Nested tables and pickers' tables draw with the kit of the table on the page |
| D10 | A cell's resolution | The column's `component`, else the kit's `cell/1`, else `Kit.Default.cell/1`. The same for the editor. A sensitive column has no component and the kit's `cell/1` gets `:masked` with no value |
| D11 | Modal or inline | The kit says it per thing that opens (`presentation/1`: `:modal` or `:inline`); `presentation: [panel: :inline]` overrides it per table. The part's root carries `data-presentation`; the hooks follow it. The confirm stays modal-only in v1 |
| D12 | `KitCase` and `Test.Resource` | `use AshDataTable.KitCase, kit: MyKit` renders a fixed table of an ETS resource shipped in `lib/` through the kit, in every state and both presentations, and asserts every marker, the element kinds the hooks need, and that no rendered state holds the test resource's sensitive value. Keyboard and screen-reader behaviour are the library's browser suite's, for `Kit.Default` and a test kit, not `KitCase`'s |
| D13 | The development check in the hook | On `mounted`/`updated`, only when LiveView's client debug is on (`liveSocket.isDebugEnabled()`); `console.error` naming the part and the missing marker |
| D14 | The presentation hints (F3) | `component`, `max_lines`, `sticky_label?` are hints; `editor` is not (it decides the write path) and leaves the list. A test asserts that no module of 2a or 2b branches on the three |
| D15 | Contract version and the evolution rule (F13) | A new part comes with a default in `use AshDataTable.Kit`, a new marker inside a bundle: no new version. A part whose assigns change incompatibly, or a bundle taken away: version + 1, and `use` with the old number fails to compile with a message that says what changed. No support of two versions (greenfield) |
| D16 | The three levels for every UI element | Style (`class/2`), markup (a kit's part), behaviour (controlled mode). Table of 3.16: which element has which level |
| D17 | Controlled mode, what stage 7 takes on | All the table on the page opens: the column's and the reference cell's question (`:confirm`), the picker (`:picker`, new), a map cell's panel, panels with files, groups, unions and chosen records (`:panel`). Nested tables and pickers' tables stay uncontrolled in v1 |
| D18 | The bytes of an opened nested table or picker | D6 and a constant resizer class: about 4.9 KB less for the comments table (5 columns), measured in step 0 of 7a. No live component comes back |
| D19 | The grid's unlock (stage 5) | Kept as it is, for every push of a grid; the item is closed with a deterministic browser test of an event that answers while a nested table opens |
| D20 | Rows that scroll under fixed headers | After the release. Stage 7 only keeps it possible: the scroll area is a part with a bundle, so the option comes later as a new kit option with a default |
| D21 | Fallback | Per step (section 7) |
| D22 | Performance | `baseline.mjs` at the start and the end of each of 7a, 7b, 7c, back to back, plus "open the panel", "open the panel inline" and "open the picker" |

## 1. What stage 7 changes, and what it does not

**Changes.** The markup: every element gets its attributes from `Attrs`, every part is drawn through the kit, and the snapshots are rewritten once in 7a and once in 7b (reviewed, D21). The hooks: markers only. New public modules: `AshDataTable.Kit`, `AshDataTable.Kit.Default`, `AshDataTable.KitCase`. New options: `kit` and `presentation` (tag, attach, router line). New controlled kinds and commands (D17). `lib/ash_data_table.ex` loses the drawing and the markup contract comment (1,669 lines today; the comment is `:828-1366`): the drawing goes to the kit and `Parts.*`, the contract to the moduledocs of `Attrs` and `Kit`.

**Stays the same.** Everything the core does: reads, writes, `Operation`, `Present`, events, commands. What a person sees with `Kit.Default` stays as it is today, pixel for pixel where a browser test can say so (contrast and a11y specs unchanged). Keyboard and screen-reader behaviour stay. The data layer is not touched but for D14's test and the projections of D17.

## 2. What the code is today

Counted at `6c0245b` with `grep` over `assets/js/` (3,988 lines in 23 files):

| What | Count | Where |
| --- | --- | --- |
| Lines with a tag name in a selector (`querySelector`, `closest`, `matches`) | 65 of 135 selector lines | most in `grid/tree.js` (22 selector lines), `panel.js` (21), `grid/editing.js` (18), `grid/arrays.js` (11) |
| Lines that walk the table's structure (`.rows`, `.cells`, `cellIndex`, `rowIndex`, `tBodies`, `tHead`, `tagName`) | 50 | `grid/tree.js` 11, `hiding.js` 7, `selecting.js` 6, `widths.js` 5, `expanding.js` 5, `arrays.js` 5, `editing.js` 4, `actions.js` 4, `whole_text.js` 2, `picker.js` 1 |
| Style-sheet rules the hook writes with `>tbody>tr>td` | 3 | `grid/widths.js:89`, `grid/scrolling.js:93, 107` |
| daisyUI classes the hooks toggle | 3 | `grid/dialog.js:16-17` (`btn-error`, `btn-primary`), `picker.js:68` (`btn-disabled`) |
| daisyUI variables in the hooks' CSS | 2 | `grid/scrolling.js:100` (`--color-base-100`), `:103` (`--color-base-content`) |
| A Tailwind class the hook reads | 1 | `grid/whole_text.js:55` (`.sr-only`) |
| Elements found from another's id | 3 | `panel.js:21`, `picker.js:14` (`-panel`/`-picker` → `-grid`), `transport/live_view.js:19` (`tableOf`) |
| Marker names in one place | 2 | `assets/js/markers.js` (`GRID`, `HANDLE`) |

R §10.3 counted "about 75 statements in 25 functions"; the count above is wider (it includes the panel's and picker's hooks and native-control checks).

On the server side: 206 `class=` attributes in `lib/ash_data_table/parts/*.ex` and `lib/ash_data_table.ex`; daisyUI component classes among them (`btn` 38, `checkbox` 23, `btn-sm` 19, `btn-xs` 13, …). The `<table>` of every grid carries a class list of about 3,400 bytes of Tailwind variants written on tags (`[&>tbody>tr>td[data-lines]]:…`, `parts/grid.ex:718-775`), and every column's resize handle one of about 490 bytes (`parts/grid.ex:44-49`). Both are `class={[…]}` lists, so LiveView sends them as dynamics, each time a table body is drawn. Two cells are drawn as raw strings, not HEEx (`Parts.Common.failure_message/2`, `parts/common.ex:51-60`; the boolean mark, `parts/grid.ex:617-628`). The three dialogs are native `<dialog>`s opened with `showModal()` (`panel.js:28`, `picker.js:26`, `grid/dialog.js:22`; markup `parts/panel.ex:38`, `parts/picker.ex:30`, `parts/messages.ex:140`).

Controlled mode (stage 6): `controlled: [:confirm, :panel]` for the table on the page (`live/core/requests.ex:29-36`); `attach/4` refuses a panel with a file, group, union, reference or references field (`lib/ash_data_table.ex:469-492`); left out: a column's question before a save, a reference cell's question, a map cell's panel, the picker, nested tables and pickers' tables (`lib/ash_data_table.ex:381-384`). Nested tables and pickers' tables are drawn with `controlled: []` (`lib/ash_data_table.ex:1411, 1608`).

## 3. Decisions for the owner

**D1. One build or several.**

Stage 7 touches every hook module, every part, the wiring's drawing, and adds public API. Stage 6 (one build, eight steps) is the largest so far.

| Option | For | Against |
| --- | --- | --- |
| a. 7a markers and bundles; 7b the kit, what opens, `KitCase`; 7c controlled mode widened. Each: its own commits, its own single run of the three suites at its end, its own drift check | 7a is the risky JavaScript change and has no public API: if it fails, nothing public is half-built. 7b builds the kit on markers that are settled. 7c is server work on stage 6's protocol, independent of the look | three drift checks; the snapshots change twice (7a: attributes; 7b: the kit's markup) |
| b. One build | one drift check | the riskiest change of the refactor and the new public API in one diff; a failure late in it blocks everything |
| c. Two: 7a + 7b together, then 7c | fewer checks | the hooks' rewrite and the kit's markup change the same snapshots in one step: a reviewer cannot tell a broken marker from an intended change |

**Recommendation: a.** The cut: 7a ends when no hook names a tag, every element's attributes come from `Attrs`, and the snapshots differ only in attributes. 7b ends when every part is drawn through a kit. 7c ends when `attach/4` refuses nothing a table on the page opens.

**D2. What a marker is.**

The owner decided "the hooks rely on the markers in the bundles only, not on tag names" (R §4.4, owner 2026-10-12). Every row is sent again whenever it changes, and the grid is "written without whitespace on purpose: every byte of a row is sent again" (`parts/grid.ex:897-899`). A new attribute on every cell costs bytes on every read.

| Option | For | Against |
| --- | --- | --- |
| a. The ARIA role where the element has one (the grid, its rows, row groups, cells, column headers, dialogs); the `data-*` the table already writes where it has none (`data-action`, `data-expander`, `data-line`, `data-selector`, `data-cancel`, …). A marker is looked for inside the table's own root only | no new byte on a row; the role is already the a11y contract the browser suite checks; a kit that draws divs must give them the roles anyway | two kinds of marker |
| b. One `data-part="cell"` on everything (Zag.js style) | one rule | about 15 bytes per cell on every row; `data-part` is common in other libraries (a component inside a cell may use it) |
| c. `data-ash-data-table-part="…"` | no clash | about 33 bytes per cell |

**Recommendation: a.** The row group (`<tbody>` today, one per record and one per detail) gets `role="rowgroup"` written out, so a kit without `<tbody>` keeps it.

**D3. The shape of `Attrs`.**

Today the attributes are written inline in HEEx, plus `cell_attributes/5` and `action_attributes/2` (`parts/grid.ex`), and the editor's `@control` (`AshDataTable.Component`) is the seed.

| Option | For | Against |
| --- | --- | --- |
| a. One function per element (`Attrs.grid/1`, `Attrs.row/2`, `Attrs.cell/3`, `Attrs.panel/2`, `Attrs.confirm/1`, …), each returning the complete map: id, role, ARIA, `data-*`, `phx-*`, `phx-hook`, `phx-target`. A part spreads it: `<td {@attrs}>`. The parts and `Kit.Default` get them as assigns; a kit never calls `Attrs` | the kit author types no marker; a marker added later reaches every kit (R §4.4) | a spread is one dynamic: the constants of a cell (`role="gridcell"`, `tabindex="-1"`, about 30 bytes) move from statics into each row's diff |
| b. Bundles hold only what varies; the constants are written by the part | no byte added | the kit author must type `role` and `tabindex` on every cell; `KitCase` would catch a miss, but the promise "you type no marker" breaks |

**Recommendation: a**, measured in 7a step 2 on "Page change" (149,779 bytes at the end of stage 6). Over 5 % more: fallback b for the row, the row group and the cell only (D21). `Attrs` stays `@moduledoc false`; its content is documented in `Kit`'s moduledoc, part by part (target S5).

**D4. How the hooks stop relying on tags.**

| Option | For | Against |
| --- | --- | --- |
| a. Every structural query by marker (`[role=gridcell]`, `[role=rowgroup]`); a position by `aria-rowindex`/`aria-colindex`, which every cell and row already carries, not by `rowIndex`/`cellIndex`; the grid an element belongs to is its `closest('[role=grid]')` (a nested grid sits inside a cell); the three style-sheet rules become `#ID [role=gridcell][aria-colindex="3"]:not(#ID [role=gridcell] [role=gridcell])` (a cell of a nested grid is a cell inside a cell). The kind of a native control (`TEXTAREA`: Shift+Enter, `SELECT`: Enter) may still be asked, of an element found by `[data-control]` | the hook works on any element kinds that carry the markers; R §10.3's mechanism 4 becomes cheaper later | all of `grid/tree.js`'s movement changes: the riskiest code of the hook |
| b. Markers, but keep `rowIndex`/`cellIndex` where the element is a `<td>` | smaller change | a kit's grid would still have to be a `<table>` |

**Recommendation: a.** The names go into `markers.js`; `panel.js:21`, `picker.js:14` and `transport/live_view.js:19` find their grid by `data-table` (the table's id, written by `Attrs`), not by cutting an id. `grid._ashDataTable` (the hook object hung on the element, `assets/js/types.d.ts:10`) stays: it is the library's own.

**D5. The class toggles and the theme in the hooks.**

| Option | For | Against |
| --- | --- | --- |
| a. The confirm dialog's button gets `data-destructive` from the hook, the picker's "Choose" keeps `aria-disabled` (`picker.js:67`, already set); `Kit.Default` styles them (`data-[destructive]:btn-error`, `aria-disabled:btn-disabled`, both in `lib/`, so Tailwind sees them). The hooks' two colours become `var(--ash-data-table-ground, Canvas)` and `var(--ash-data-table-line, CanvasText)`, which `Kit.Default` sets from daisyUI's variables on the root. `whole_text.js:55` skips `[data-unseen]` (the marker `Kit.Default` puts beside `sr-only`) | no daisyUI in `assets/js/`; a kit without daisyUI works | the tests that assert `btn-error`/`btn-primary` (10 lines in `selection.spec.ts`, `a11y-actions.spec.ts`, `actions.spec.ts`) assert the attribute instead |

**Recommendation: a.** `--ash-data-table-ground` exists today (`scrolling.js:100`); `--ash-data-table-line` is new.

**D6. The table's own structural style.**

The 3.4 KB class list on every `<table>` (`parts/grid.ex:718-775`) styles cells by tag (`>tbody>tr>td`): the focus ring, a busy table dimmed, a failed cell's ring and mark, one line per row, `max_lines`, the expander's triangle, the line buttons. It is the default kit's look, but written so that it only works on `<table>` markup, and it is sent with every table body.

| Option | For | Against |
| --- | --- | --- |
| a. Written on markers (`[role=gridcell]`, `[data-lines]`, `[aria-invalid]`) and moved to the root of the table on the page (`Attrs.root`, `Kit.Default.root/1`'s class), once per page. Nested tables and pickers' tables are inside that root in the DOM (portals move into its cells; the picker's dialog is drawn in its body), so the rules reach them | about 3.4 KB less per nested table or picker opened; the default kit's look no longer needs `<table>` | the "child of this grid only" rules (a busy table dims its own cells, not a nested one's) need `:not(… [role=gridcell] [role=gridcell])`, as in D4 |
| b. A CSS file in the package that the host imports (`@import` in `app.css`, the installer adds it) | no class list at all | one more setup line; the installer touches the host's CSS twice |
| c. As today | nothing to do | — |

**Recommendation: a.**

**D7. `AshDataTable.Kit`.**

Precedent. AshAuthentication.Phoenix lets a host restyle its components with override modules (`use AshAuthentication.Phoenix.Overrides`, `override Component do set :class, "…" end`), a list of them on the route, first wins, and ships `Overrides.Default` and `Overrides.DaisyUI` (`deps/ash_authentication_phoenix/lib/ash_authentication_phoenix/overrides.ex:6-40`, 3.0.0-rc.11, in another project of the owner). Ash's own behaviours with defaults are `use`d with `defoverridable` (`use Ash.Resource.Change`). Cinder names a theme in config or per table (R §4.3). Phoenix's `core_components.ex` is copied into the app, which suits buttons and inputs, never the grid (R §4.5).

| Option | For | Against |
| --- | --- | --- |
| a. A behaviour: one callback per part (`part(assigns) :: Phoenix.LiveView.Rendered.t()`), `class(part, state) :: String.t() \| nil`, `presentation(thing) :: :modal \| :inline`. `use AshDataTable.Kit, contract: 1` defines every callback as a call of `Kit.Default`'s and makes them overridable, so `super/1` works. At compile time (`@after_compile`): an unknown contract number, a public function of arity 1 whose name is no part (a typo: `pagniation/1`) and a `class/2` that is not a function of two arguments fail. `class/2` is called for the parts drawn once per table (root, heading, lines above the grid, panel, picker, confirm, pagination, …); rows and cells are styled through their attributes from the root's rules (D6), never by a per-cell call | the target's shape (S3); restyle without replacing; replace one part without the others; the Ash and AshAuthentication.Phoenix pattern | a class from `class/2` is a dynamic: fine once per table, not per cell |
| b. Overrides as data (`override :cell, class: "…"`), as AshAuthentication.Phoenix does | declarative | no own markup; levels 2 and 3 need a second mechanism anyway |
| c. `class/2` per cell too | complete | every row's diff grows by every cell's class (D3's measure) |

**Recommendation: a.** `class/2`'s `state` is what the server knows when it draws the part (`nested?`, `kind`, `destructive?`, `align`); what the hook changes in the browser (selected, pending, invalid, busy) is an attribute and is styled by it. A kit is checked when a table is built with it: a module that is not a kit raises with the message style of a column's component (`resource/presenting.ex`).

**D8. The parts of contract 1.**

From `body/1` (`lib/ash_data_table.ex:1484-1660`) and `Parts.*`. Each part gets its bundles and the values `Present` and the entry give; never a record, an `AshPhoenix.Form`, a changeset, the actor or another field of the row (S3, F1).

| Part | Gets besides its bundles | Today |
| --- | --- | --- |
| `root` | `nested?`, the slot | the root `div` of `attached/1`, `live/embedded.ex` |
| `heading` | `label`, `level`, `create`, `table_actions` | `Parts.Heading` |
| `related`, `line`, `full_view` | `title`, `label`, `open?`, `create`, `table_actions` | `Parts.Related` |
| `argument_line`, `argument` | arguments with label, type, value, errors, required? | `Parts.Arguments` |
| `filter` | `column` (`Component.Column`), operators, value, `rejected?` | `Parts.Filter` |
| `selection_line` | count, scope, bulk actions, running?, result | `Parts.Selection` |
| `columns` (the "Columns" list) | columns with label | `Parts.Grid.columns/1` |
| `status` | — (the live region; its text is the core's) | `Parts.Messages.status/1` |
| `grid`, `header_cell`, `filter_cell`, `row`, `detail`, `cell`, `actions_cell`, `footer`, `summary_cell`, `resizer` | per element: the column, the `Present.Cell`, the row's flags | `Parts.Grid`, `Parts.Summary` |
| `cell`, `editor` | as `AshDataTable.Component`: `value`, `text`, `column` / `value`, `control`, `label`, `column`, `place` | `Parts.Grid` `cell/3`, `editor/1` |
| `count`, `list` | the counter, the list editor | `Parts.Editors` |
| `panel`, `field`, `control` | `Present.Panel` / `Present.Field` as values: title, submit, errors, fields | `Parts.Panel` |
| `picker` | `Present.Picker`: title, several?, none?, error, the table as slot | `Parts.Picker` |
| `confirm` | question, destructive? | `Parts.Messages.dialog/1` |
| `failure`, `whole_text` | the message | `Parts.Common.failure_message/2`, `Parts.Messages.whole/1` |
| `message` | kind (`:empty`, `:error`, `:fill`, `:forbidden`, `:loading`), text | `Parts.Messages.messages/1`, `notice/1` |
| `pagination` | pages (label, current?, bundle), previous, next, sizes | `Parts.Pagination` |

`Parts.*` become the internals of `Kit.Default`: the modules stay (each feature keeps one findable place, F13), `Kit.Default`'s callbacks call them. The two raw-string cells become HEEx parts (`failure`, the boolean mark in `cell`).

**Recommendation: the list above.**

**D9. Where a kit is named.** Q12 decided: config, per table, router line.

| Option | For | Against |
| --- | --- | --- |
| a. `config :ash_data_table, kit: Mod` (beside `layout`, `gettext_backend`); `kit={Mod}` on the tag; `kit: Mod` at attach; `kit: Mod` on the router line. Held in `Table.options`. Nested tables and pickers' tables draw with it | one look per table on the page; Q12 | a nested table cannot look different from its parent |
| b. Also per resource (`table do kit Mod end`) | a resource's tables look alike everywhere | the declaration would name a part-3 module beyond 3c (§5.1) |

**Recommendation: a.**

**D10. A cell's resolution.** R §4.7 and target §9 stage 7: the column's component, the kit's `cell/1`, the default.

**Recommendation:** as decided, with two rules. The kit's `cell/1` gets `Present.Cell`'s `state` and `value` (a value only in the state `:value`; `:masked` and `:forbidden` without one), so a kit cannot draw a sensitive value: none is given. `Common.dynamic_component/1` (`parts/common.ex:16-21`) stays the one way a component's function is called.

**D11. Modal or inline.** Owner, 2026-10-15: declared by the kit, overridable per table; the hooks follow; what the panel shows and the checks do not depend on it; `KitCase` checks both.

| Option | For | Against |
| --- | --- | --- |
| a. `Kit.presentation(:panel \| :picker \| :confirm)`, `Kit.Default` answers `:modal` for all three; option `presentation: [panel: :inline, picker: :inline]` on tag, attach and router line. `Attrs` puts `data-presentation` on the part's root. **Modal:** the root is a `<dialog>`, the hook calls `showModal()` (today's behaviour: page inert, focus trapped by the browser, Escape is Cancel). **Inline:** the root is any element with `role="region"` and `aria-labelledby`, drawn where the kit's `root/1` puts the slot `:opened` (by default after the grid); the hook moves focus to the first control as it opens, Escape inside it is Cancel, focus goes back to the opener when it goes; nothing is inert, Tab leaves it. The confirm is modal-only in v1 | one marker decides; the panel's form and events are the same; the server does not know the difference | a kit author must keep a `<dialog>` for a modal part (`KitCase` checks it) |
| b. Inline confirm too | complete | an inline question that the page can Tab away from leaves an action half asked; ARIA says an `alertdialog` should be modal (WAI-ARIA 1.2, `alertdialog`) |
| c. The host places the inline panel with a slot of its own | full freedom | that is controlled mode (D17), which already gives it |

**Recommendation: a.** Inline needs the panel's hook to find its grid by `data-table` (D4), not by its id. A picker inline shows its table in the page under the panel or the cell's row; the picker's table is still a registry entry, drawn in the part's slot as today.

**D12. `KitCase` and `AshDataTable.Test.Resource`.**

| Option | For | Against |
| --- | --- | --- |
| a. `use AshDataTable.KitCase, kit: MyKit` generates ExUnit tests that mount a support LiveView (shipped in `lib/`, test support only) attaching a table of `AshDataTable.Test.Resource` (`Ash.DataLayer.Ets`, with a `sensitive?` attribute holding a known secret, a reference, a map, a union, a file argument, a confirm) and drive it with `Phoenix.LiveViewTest` through every state: empty, error, loading, selected, editing, a failed save, panel open, picker open, nested table open, both presentations. Each state asserts the markers of every part, the element kinds the hooks need (a modal part's root is a `<dialog>`, one control per editor, one tab stop per grid) and that the secret is in no rendered state (F1). `KitCase` uses `AshDataTable.Test` for what is inside a portal | checks what can be checked in ExUnit, in the host's own `mix test`; the kit author gets the same check the library runs against `Kit.Default` | ExUnit runs no hook |
| b. Also keyboard and screen readers in `KitCase` | the owner's wording | needs a browser in the host's `mix test`; not available in ExUnit |

**Recommendation: a.** Keyboard and screen-reader behaviour for both presentations are checked by the library's browser suite, against `Kit.Default` and a test kit with markup of its own (divs, inline panel) in the demo (`/e2e/kit`). The guide offers those specs as a template (R §4.6). This is target amendment 2 (section 10).

**D13. The development check in the hook.**

| Option | For | Against |
| --- | --- | --- |
| a. When LiveView's client debug is on (`liveSocket.isDebugEnabled()`, LV `assets/js/phoenix_live_view/live_socket.ts:470`, a public method with its docs), `mounted`/`updated` of each hook check the markers of the parts they rely on and `console.error` the part and the missing marker. The transport gives the hooks `debug()` | no option, no server state; a developer turns it on as for LiveView | off by default |
| b. A `data-dev` attribute from `config :ash_data_table, check_markers: true` | on in dev by config | one more option; bytes on the root |

**Recommendation: a.**

**D14. The presentation hints (F3).**

Target §4.3 and §6 list `component`, `max_lines`, `sticky_label?`, `editor` as hints "the core never reads". `editor` is not one: it decides how a value is given and the write path (`live/core/picker.ex:31, 111, 179, 355` for `:references`; `live/core/files.ex:32` for `:file`; `act.ex:700, 772, 1018`). `component` is only carried by the core: `Core.in_words/1` puts the translated label into the component's column (`live/core.ex:386-398, 435`), it never branches on it.

**Recommendation:** the hints are `component`, `max_lines`, `sticky_label?`, documented as such in the comment of `Model.Column` and in `Kit`'s moduledoc. A test in `test/architecture_test.exs` greps 2a and 2b for a match or a branch on them (`component:` in a pattern, `.max_lines`, `.sticky_label?`), allowing `in_words/1`. Target amendment 3.

**D15. The contract version and the evolution rule.** F13 decided: a new part comes with a default. R §4.4 proposed supporting the old number for one minor release with a warning.

**Recommendation:** a new part with a default, or a new marker in a bundle: same version. A part's assigns changed incompatibly, or a bundle taken away: the version goes up; `use AshDataTable.Kit, contract: 1` then fails to compile with a message naming the parts that changed. No support of the old number beside the new (greenfield: no compatibility code before the release; after it, the owner decides per release). Target amendment 4 drops "one minor release".

**D16. The three levels for every UI element.**

| Element | 1 style | 2 markup | 3 behaviour (controlled) |
| --- | --- | --- | --- |
| Grid, rows, cells, headers, filters, footer | rules on the root (D6); `class(:grid, …)` | the grid parts, bundles spread | no: the grid is the table (R §4.6) |
| Cell content, editor | `class/2` of the kit's `cell` | column's `component`, kit's `cell/1`, `editor/1` | no |
| Heading, lines above the grid, pagination, messages | `class/2` | kit parts | no: they open nothing |
| Action panel (row, table, create, selection, map cell) | `class(:panel, …)` | `panel`, `field`, `control` | yes, `:panel` (D17) |
| Picker | `class(:picker, …)` | `picker` | yes, `:picker` (new, D17) |
| Confirm (actions, a column's, a reference cell's) | `class(:confirm, …)` | `confirm` | yes, `:confirm` (widened, D17) |
| Failure popover, whole text, "Columns" list, "is any of" list | `class/2` | `failure`, `whole_text`, `columns`, `filter` | no: they ask nothing of the server that writes; the hook owns them |

**Recommendation: as the table.** "Every UI element" at level 3 means every element that opens something the server holds (panel, picker, question). The popovers and lists are the hook's own and hold nothing the host could answer.

**D17. Controlled mode, widened.**

Stage 6 left out (D14 there): the picker, a map cell's panel, panels with files, groups or chosen records, a column's question before a save, a reference cell's question, nested tables (`lib/ash_data_table.ex:381-384`).

| Kind | How | Take on in 7c? |
| --- | --- | --- |
| A column's question before a save | Today the hook sends `save`, the reply asks, the hook sends it again confirmed. Controlled: the server holds `%{kind: :confirm, for: {:save, row, column}}` with the typed text (in the entry, never in `request/1`'s projection for a sensitive column), the hook is told the cell waits (`aria-busy`), `confirm_request/3` runs `Operation.save` confirmed, `cancel_request/3` tells the hook to put the cell back | yes |
| A reference cell's question | the same, for `picked` (`live/core/cells.ex`, `picker.ex`) | yes |
| The picker | New kind `:picker`: `request/1` gives the destination resource, whether several, the current choice (scrubbed labels); the host draws its own chooser (for instance a table of its own) and answers `pick_request(socket, name, ref, key \| [keys] \| nil)`. The key is a claim: `Pick.chosen/3` reads it again as the person through the picker's read action, as today | yes |
| Panels with files | The request's field says `type: :file` and `upload`, the name of the table's upload (`Files.upload_name/2`); the host draws `<.live_file_input upload={@uploads[name]} />` (LiveView's public component). The files are consumed by `Operation`'s `with_files`, as today | yes |
| Groups and unions | The field holds its `fields` (and a union its `kinds`); the host adds and removes with `add_group_request/4` and `remove_group_request/4` (a path), as the panel's `panel_add`/`panel_remove` | yes; fallback in D21 |
| Chosen records in a panel | The field holds `chosen` (key and label, scrubbed); the host answers with `pick_request/4` for that field, or with keys in `submit_request/4`'s params; each key read again as the person (`Pick.chosen/3`) | yes |
| A map cell's panel | a `:panel` request of kind `:cell` | yes |
| Nested tables and pickers' tables | — | **no, deferred.** A host addresses the table it placed, by its attach name (stage 6 D2, D11); a nested table's id is generated, and its questions are about rows the host never listed. Revisit after release with a real use |

**Recommendation: take on all but nested tables.** `attach/4`'s refusal (`lib/ash_data_table.ex:473-491`) goes; `controlled:` takes `[:confirm, :panel, :picker]`. Every answer goes through `Operation` with its claim checks, the veto and the re-read (the owner's rule, 2026-10-15). `request/1`'s projection stays `AshDataTable.Event`'s (`event.ex:188-227`), with nested fields.

**D18. The bytes of an opened nested table or picker.**

Stage 5 measured +6,606 bytes to open a nested table and +4,249 to open the picker, accepted for a second look in stage 7 (stage5-design.md, performance). Why: a live component of one module reused the statics LiveView already had (LV `lib/phoenix_live_view/diff.ex`, components' shared statics); a function component in a new portal item shares statics only within one diff (`maybe_share_template/4`, `diff.ex:799-810`), so every opened table sends its body's statics again. On top of that every body sends two big dynamic class lists (section 2).

| Option | Saves (estimate, for the comments table: 5 columns) | Cost |
| --- | --- | --- |
| a. D6: the structural class list on the root, once | about 3.4 KB per opened nested table or picker | part of 7a anyway |
| b. The resizer's class as a literal (`class="…"`), so it is a static of the comprehension, sent once per body | about 490 bytes for every column but one: about 2 KB | none |
| c. Statics trimmed: the `phx-no-format` indentation kept for byte-identical snapshots (`docs/agents/architecture.md`, "keep the indentation") is no longer needed once the snapshots are rewritten | a few hundred bytes; measured | none |
| d. A live component per nested table again, for its statics | all of the growth | breaks D-nested ("never a live component per nested table", Q1) |

**Recommendation: a, b and c,** measured in 7a's step 0 (the bytes of the body's statics and of the two class lists, with the perf probe) and at its end. Expected: about 4.9 KB less per opened nested table or picker; together with c, back to about stage 5's start or below. d is not proposed.

**D19. The grid's unlock.** Stage 5's gate found a race: LiveView locks a hook's element while its event is answered; a nested table's portal target inside a locked grid was not there when its portal moved. The first fix unlocks every push of a grid (`assets/js/transport/live_view.js:31-45`, commit `493c400`, "first attempt"), through `phx:push` and `detail.unlock`, which LiveView's CHANGELOG names as client API (`detail.lock()` in `phx:push`, #4351). I take the item deferred from stage 5 to be "narrow the unlock to the events that can change a portal's target"; I found it in no document.

| Option | For | Against |
| --- | --- | --- |
| a. Keep it for every push of a grid; close the item with a deterministic browser test: a save whose answer is held back (the `routeWebSocket` hold `files.spec.ts` uses) while a row is expanded, the nested table must arrive | no list of events in the transport; the hook keeps what a person does (`beforeUpdate`), as it has since stage 5 | the grid takes patches while a push is out, always |
| b. Unlock only for the pushes that change rows or lines (`expand`, `toggle`, `page`, `sort`, `filter`, `read_again`, …) | the lock protects the other pushes | a second list of events to keep in step with `Intent`; a missing name brings the race back |

**Recommendation: a.**

**D20. Rows that scroll under fixed headers (owner, 2026-10-16, target §7.5).**

| Option | For | Against |
| --- | --- | --- |
| a. After the release; stage 7 keeps it possible: the grid's scroll area is the `grid` part with its bundle, and a later kit option (`scroll: :rows`) is a new option with a default, no new contract version | stage 7 stays a refactor; the option changes `grid/scrolling.js` (scroll inside scroll, keyboard into view in two directions, printing, find), which is new behaviour and its own browser tests | not in the first release |
| b. In 7b, as a kit option | ships with the kit | 7b, the kit build, also becomes a feature build with the riskiest hook module |

**Recommendation: a.**

## 4. Order of work

Each step: its own commits on `main`; during a step only `mix test --stale` (root and demo) and `npx playwright test --only-changed=main` or the named spec files; `docs/agents/architecture.md` corrected where the step made it false. Each suite (root, demo, browser) runs **once**, at the end of 7a, of 7b and of 7c. No repeat runs, no gate, no waiting for low load.

**7a: markers and bundles.**

0. Tag `stage7-start`. Perf run (D22). Measure the statics and class bytes of D18.
1. `markers.js` and `Attrs`, every name of D2; the parts take their attributes from `Attrs` (D3). Markup changes in attributes only (`role="rowgroup"`, `data-table`).
2. Measure "Page change" bytes (D3).
3. The hooks on markers (D4), module by module: `tree.js`, `selecting.js`, `editing.js`, `arrays.js`, `expanding.js`, `widths.js`, `hiding.js`, `scrolling.js`, `actions.js`, `whole_text.js`, then `panel.js`, `picker.js`, `pagination.js`, the transport. No tag selector left.
4. Class toggles and theme out of the hooks (D5).
5. The structural style on the root (D6), the resizer's class literal (D18 b), statics trimmed (D18 c).
6. The development check (D13). The grid's unlock test (D19).
7. Snapshots rewritten once and reviewed with the owner before commit (D21). The three suites once. Perf. As-built section. Drift check.

**7b: the kit.**

1. `AshDataTable.Kit`, `use`, compile-time checks (D7, D15); `Kit.Default` calling `Parts.*` (D8); the drawing moves out of `lib/ash_data_table.ex`; the contract comment becomes the moduledocs of `Kit` and `Attrs`.
2. `kit` named per D9; the cell's resolution (D10).
3. Modal and inline (D11): `presentation/1`, the option, the hooks.
4. `AshDataTable.Test.Resource`, `KitCase` (D12); the library's own `KitCase` run against `Kit.Default`; a test kit in the demo with markup of its own and inline presentation.
5. The hints (D14).
6. Snapshots once, reviewed. Suites once. Perf. As-built. Drift check.

**7c: controlled mode widened.**

1. `:confirm` for a column's and a reference cell's question.
2. `:picker` and `pick_request/4`.
3. Map cell's panel, files, chosen records, groups and unions in `:panel`; `attach/4`'s refusal goes.
4. Moduledocs of the new commands. Suites once. Perf. As-built. Drift check.

## 5. Tests

**Group X (changed, 7a): markers.** The tests that read classes or tags beyond the contract (counted with grep: 37 lines of demo and browser tests name `btn`, `badge`, `sr-only` and the like, and 16 browser locators start with a tag; `docs/architecture/test-coupling.md` §2.3 lists the demo ones) read the marker instead. Call target only; no assertion changes meaning. The ten `toHaveClass(/btn-error|btn-primary/)` lines assert `data-destructive`.

**Group Y (new, browser, 7a): markers only.** One spec drives the grid of a support page whose kit draws the grid with `div`s and roles (built in 7b; in 7a a fixture page of the demo): arrow keys, Enter to edit, Escape, selection with Shift, a nested table, widths, hiding a column. If the hook relied on a tag, it fails here.

**Group Z (new, root and demo, 7b): the kit.** Compile-time messages of `use AshDataTable.Kit` (unknown contract, unknown part, wrong arity); a kit named in config, on the tag, at attach, on the router line; a nested table and a picker's table use the top's kit; the cell's resolution order; `KitCase` against `Kit.Default` and the demo's test kit, both presentations; the secret of `Test.Resource` in no state (mutation check: what is sent to the browser).

**Group AA (new, browser, 7b): what opens.** Panel, picker and confirm modal (as today) and panel and picker inline: focus in, Escape, Cancel, focus back to the opener, Tab leaves an inline panel, axe content in both.

**Group AB (new, demo and browser, 7c): controlled mode widened.** Each kind of D17: `request/1` projection, the answer through `Operation` (a forged key in `pick_request` reads nothing the person may not read; a sensitive field's value nil; the veto asked), a stale `ref` does nothing. Browser: a controlled picker and a controlled column question on a support page. Mutation checks where a key or value is written.

**Unchanged on purpose.** Every other test. The snapshots change twice, each time reviewed.

## 6. Performance (D22)

`demo/perf/baseline.mjs` on `/tasks`, at `stage7-start` in a worktree and at the end of each of 7a, 7b, 7c, back to back, on the standard seed, at whatever load the machine has (no waiting). The actions of stage 6 plus: "open the panel", "open the panel inline" (a support page, 7b on), "open the picker". Times within 20 %, Ash reads and statements the same. Bytes: "Page change" within 5 % of the start (D3); "Opening a nested table" and "Opening the picker" at least 4 KB less (D18).

## 7. Fallback (D21)

| Step | If it fails | Then |
| --- | --- | --- |
| 7a.1 bundles on every row and cell | "Page change" more than 5 % up | Bundles of row, row group and cell hold only what varies; their constants are written by the part, `KitCase` asserts them (D3 b). You are told |
| 7a.3 the hooks on markers | a module cannot be moved without changing behaviour a browser test checks, after two fixes | That module keeps its tag selectors in 7a; `markers.js` names them, and the kit contract says the grid parts keep their element kinds (R §4.4's two tiers, as a first step). You are told; the target's "no tag selectors" waits |
| 7a.7, 7b.6 snapshots | — | Rewritten only after you have seen the diff |
| 7b.3 inline | focus cannot be returned reliably for the picker inline | Picker modal-only in v1; the panel inline stays |
| 7c.3 groups and unions | the add/remove protocol needs more than two commands | `attach/4` keeps refusing a panel with a group or union; the rest of 7c ships |

## 8. Risks

| Risk | Check |
| --- | --- |
| A kit draws a sensitive value | No part is given one (`Present`); `KitCase` asserts it on every state (F1) |
| A kit drops a marker and the keyboard breaks | `KitCase`; the development check; group Y |
| A controlled host bypasses a check | every answer through `Operation`; group AB |
| Bytes per row grow with bundles | D3's measure and fallback |
| Inline panels make "nothing changes under you" weaker | It is the server's rule (held rows, `Core.Updates`), independent of the presentation; group AA keeps a live update under an open inline panel |

## 9. Done-check

- `grep -rnE "closest\(\"(td|th|tbody|tr|table)|\.cells\b|cellIndex|rowIndex|tBodies|tHead|classList" assets/js` finds nothing.
- `grep -rn "\-\-color-\|btn\|sr-only" assets/js` finds nothing.
- Every part's attributes come from `Attrs`; `markers.js` and `Attrs` name the same markers (a test compares the two lists).
- `use AshDataTable.Kit, contract: 1` documented with every part; `Kit.Default` passes `KitCase`, both presentations.
- `attach/4` refuses nothing the table on the page opens; nested tables stay uncontrolled, documented.
- No `__xxx__` field, no `Phoenix.LiveViewTest.DOM`, no undocumented markup of LiveView in `lib/`, `demo/test`, `demo/e2e`.
- The dependency test passes; `Kit`, `Kit.Default`, `Attrs` are part 3, `KitCase` and `Test.Resource` are T.
- Perf of section 6. Target §9 stage 7 ticked, or the fallback recorded.
- **The drift check** after each of 7a, 7b, 7c; then the final conformance review of target §9.

## 10. Proposed amendments to target.md

For your yes; target.md is not changed by this note.

1. §9 stage 7 is built as 7a, 7b, 7c, each with its drift check (D1).
2. §9 stage 7, "`KitCase` checks keyboard and screen-reader behaviour for both": `KitCase` checks the structure they rest on; the behaviour is checked by the library's browser suite for `Kit.Default` and a test kit (D12).
3. §4.3 and §6 list `editor` as a presentation hint; it decides the write path. The hints are `component`, `max_lines`, `sticky_label?` (D14).
4. R §4.4's "supports the old number for one minor release" is not taken: no compatibility code before the release (D15).
5. S3: `class/2` is called for parts drawn once per table; row and cell state is styled through attributes (D7). `presentation/1` joins the callbacks (D11).
6. S5: a marker is an ARIA role or an existing `data-*` attribute; no `data-part` (D2).
7. §9 stage 7, "presentation … confirm dialog": the confirm is modal-only in v1 (D11 b).
8. Stage 6 D14 and S7/S8: controlled mode gains `:picker`, `pick_request/4`, `add_group_request/4`, `remove_group_request/4`; nested tables stay uncontrolled in v1 (D17).
9. §7.5, rows under fixed headers: after the release, as a kit option (D20).
10. `CONTEXT.md` gains "kit", "part", "bundle", "marker" in the documentation pass after stage 7 (the rule for docs during the refactor).

## 11. Public API only (owner's rule, 2026-10-16)

| Decision | What of a dependency it uses |
| --- | --- |
| D3, D7, D8 | `Phoenix.Component` attribute spread and slots; `defoverridable`; `@after_compile` |
| D10 | `apply/3` inside a function component (LV "Dynamic Component Rendering", as `parts/common.ex:11-21`) |
| D11 | `HTMLDialogElement.showModal()`; ARIA `region` |
| D12 | `Phoenix.LiveViewTest` (`live_isolated/3`, `render/1`, `render_hook/3`), `AshDataTable.Test` for portals; `Ash.DataLayer.Ets` |
| D13 | `liveSocket.isDebugEnabled()` (`this.liveSocket` of a hook, both in LV's public TypeScript API) |
| D17 | `Phoenix.Component.live_file_input/1`; `AshPhoenix.Form` as stage 6 |
| D19 | `phx:push` with `detail.unlock` (as today; LV's CHANGELOG names `phx:push`'s `detail.lock()` as client API, #4351). To be confirmed against LV's JS-interop guide in 7a step 0; if it is not documented there, it is an internal and you are told |

## 12. What the owner said that this note keeps

- D-parts, D-headless: fully headless, a bundle for every element, rows and cells too; the hooks on markers only.
- 2026-10-15: what opens is modal or inline, by the kit, per table; three levels for every UI element; controlled mode needs `attach`; safety stays in `Operation`.
- F1: no sensitive value on any path but "Show"; `KitCase` checks it.
- F3, F13, Q12 as decided; D-nested: no live component per nested table (D18 d not proposed).
- Ash way and public API only (2026-10-16); greenfield (no old contract numbers, no shims); tests exactly once per suite at the end (2026-10-16); docs: the architecture map and the moduledocs of new public functions only.
