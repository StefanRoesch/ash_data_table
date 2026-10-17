# Stage 7: design note (markers, bundles, the kit, what opens, controlled mode widened)

Status: **accepted by the owner on 2026-10-16, all as recommended (D1–D22; D23 added for 7c.0 on 2026-10-17); D11 changed by the owner on 2026-10-17 (the question modal or inline); D3 changed by the owner on 2026-10-17 (`Attrs` public, a kit calls it); D17 changed by the owner on 2026-10-17 (nested tables and pickers' tables controlled too). 7a, 7b and 7c built, with the drift fixes of 7b and of 7c (sections 13, 14, 15).** Code references are of `6c0245b`. LiveView references are of the installed `phoenix_live_view` 1.2.12 under `demo/deps/phoenix_live_view/` (written `LV …`). The research is `ash_reference/headless-table-architecture.md` (written `R §n`, outside the repository). Names follow [target.md](target.md); words follow `CONTEXT.md`. The model for this note is [stage6-design.md](stage6-design.md).

Stage 7 is the last stage of the refactor. It makes the look and the behaviour of every UI element replaceable against a contract that can be checked: the hooks find the table's elements by markers only, every element gets its markers from one place (`AshDataTable.Attrs`), a kit draws the parts, and a host can take over what opens (controlled mode) for every kind of thing that opens on the table on the page. The table stays "just an interface" to the resource: whatever a kit or a host draws, the inputs go back through `Operation`, and nothing sensitive reaches a part.

## 0. The decisions at a glance

Answer "as recommended", or per number.

| # | Question | Recommendation |
| --- | --- | --- |
| D1 | One build or several | Three, each with its own drift check and its own single run of the three suites: **7a** markers and bundles (no public API), **7b** the kit, what opens, `KitCase`, **7c** controlled mode widened |
| D2 | What a marker is | An ARIA role where the element has one (`grid`, `row`, `rowgroup`, `gridcell`, `columnheader`, `dialog`), else the `data-*` attribute the table already writes. Nothing new on a row or cell. Every name in `assets/js/markers.js` and in `Attrs`, side by side |
| D3 | The shape of `AshDataTable.Attrs` | One function per element, returning the complete attribute map (id, role, ARIA, `data-*`, `phx-*`, `phx-hook`); a part spreads it. Bytes per row measured; fallback in D21. Built: public, and a kit's part calls it itself (owner, 2026-10-17; section 14) |
| D4 | How the hooks stop relying on tags | Structure by markers; positions by `aria-rowindex`/`aria-colindex` in place of `rowIndex`/`cellIndex`; "which grid owns this element" by `closest('[role=grid]')`. A native control's kind (`TEXTAREA` vs `INPUT`) may still be asked of an element first found by a marker |
| D5 | The three class toggles and the theme in the hooks | Gone. The hook sets attributes (`data-destructive`, `aria-disabled`); the kit styles them. The hooks' colours are `--ash-data-table-*` properties the kit sets, not daisyUI's `--color-*` |
| D6 | The table's own structural style (the 3.4 KB class list on every `<table>`) | Moved, written on markers, to the root of the table on the page, once per page; nested tables and pickers' tables send none of it |
| D7 | `AshDataTable.Kit` | A behaviour with one callback per part and `class/2`; `use AshDataTable.Kit, contract: 1` delegates every callback to `Kit.Default` (`defoverridable`, so `super` works); checks at compile time. `class/2` is called for parts drawn once per table, never per row or cell; row and cell state is styled through attributes |
| D8 | The parts of contract 1 | The list of section 3.8 |
| D9 | Where a kit is named | `config :ash_data_table, kit:`, `kit=` on the tag, `kit:` at attach and on the router line (Q12). Nested tables and pickers' tables draw with the kit of the table on the page |
| D10 | A cell's resolution | The column's `component`, else the kit's `cell/1`, else `Kit.Default.cell/1`. The same for the editor. A sensitive column has no component and the kit's `cell/1` gets `:masked` with no value |
| D11 | Modal or inline | The kit says it per thing that opens (`presentation/1`: `:modal` or `:inline`); `presentation: [panel: :inline]` overrides it per table. The part's root carries `data-presentation`; the hooks follow it. The confirm is modal or inline like the others (b, owner 2026-10-17) |
| D12 | `KitCase` and `Test.Resource` | `use AshDataTable.KitCase, kit: MyKit` renders a fixed table of an ETS resource shipped in `lib/` through the kit, in every state and both presentations, and asserts every marker, the element kinds the hooks need, and that no rendered state holds the test resource's sensitive value. Keyboard and screen-reader behaviour are the library's browser suite's, for `Kit.Default` and a test kit, not `KitCase`'s |
| D13 | The development check in the hook | On `mounted`/`updated`, only when LiveView's client debug is on (`liveSocket.isDebugEnabled()`); `console.error` naming the part and the missing marker |
| D14 | The presentation hints (F3) | `component`, `max_lines`, `sticky_label?` are hints; `editor` is not (it decides the write path) and leaves the list. A test asserts that no module of 2a or 2b branches on the three |
| D15 | Contract version and the evolution rule (F13) | A new part comes with a default in `use AshDataTable.Kit`, a new marker inside a bundle: no new version. A part whose assigns change incompatibly, or a bundle taken away: version + 1, and `use` with the old number fails to compile with a message that says what changed. No support of two versions (greenfield) |
| D16 | The three levels for every UI element | Style (`class/2`), markup (a kit's part), behaviour (controlled mode). Table of 3.16: which element has which level |
| D17 | Controlled mode, what stage 7 takes on | All the table on the page opens: the column's and the reference cell's question (`:confirm`), the picker (`:picker`, new), a map cell's panel, panels with files, groups, unions and chosen records (`:panel`). Owner, 2026-10-17: nested tables and pickers' tables controlled too, by the same attach option |
| D18 | The bytes of an opened nested table or picker | D6 and a constant resizer class: about 4.9 KB less for the comments table (5 columns), measured in step 0 of 7a. No live component comes back |
| D19 | The grid's unlock (stage 5) | Kept as it is, for every push of a grid; the item is closed with a deterministic browser test of an event that answers while a nested table opens |
| D20 | Rows that scroll under fixed headers | After the release. Stage 7 only keeps it possible: the scroll area is a part with a bundle, so the option comes later as a new kit option with a default |
| D21 | Fallback | Per step (section 7) |
| D22 | Performance | `baseline.mjs` at the start and the end of each of 7a, 7b, 7c, back to back, plus "open the panel", "open the panel inline" and "open the picker" |
| D23 | Texts and values for every part (owner, 2026-10-17, step 7c.0) | Every part is given, wherever it shows a text or a value, the finished text (`text`, or `texts` by name), the message it was made of (`message`, `messages`: a key of the public list `AshDataTable.Messages` and its values) and, for a value, the raw `value` and the `locale`. Added in one seam, `Kit.part/1`, from one module, `AshDataTable.Kit.Words` |

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
| `root` | `id`, `nested?`, `page`, the slots; it draws the root element (`Attrs.root/2`) of the table on the page, of nested tables and of pickers' tables; the tag keeps a static element of its own around it (final review A2, owner 2026-10-17) | the root `div` of `attached/1`, `live/embedded.ex` |
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
| a. `Kit.presentation(:panel \| :picker \| :confirm)`, `Kit.Default` answers `:modal` for all three; option `presentation: [panel: :inline, picker: :inline]` on tag, attach and router line. `Attrs` puts `data-presentation` on the part's root. **Modal:** the root is a `<dialog>`, the hook calls `showModal()` (today's behaviour: page inert, focus trapped by the browser, Escape is Cancel). **Inline:** the root is any element with `role="region"` and `aria-labelledby`, drawn where the kit's `root/1` puts the slot `:opened` (by default after the grid); the hook moves focus to the first control as it opens, Escape inside it is Cancel, focus goes back to the opener when it goes; nothing is inert, Tab leaves it. The confirm is modal-only in v1 (not taken: the owner chose b, 2026-10-17) | one marker decides; the panel's form and events are the same; the server does not know the difference | a kit author must keep a `<dialog>` for a modal part (`KitCase` checks it) |
| b. Inline confirm too (**chosen by the owner, 2026-10-17**: "any component must be customizable, this is also true for dialogs") | complete | an inline question that the page can Tab away from leaves an action half asked; ARIA says an `alertdialog` should be modal (WAI-ARIA 1.2, `alertdialog`): so an inline question is a `role="region"` named by its question, not an `alertdialog`, and one question at a time per table |
| c. The host places the inline panel with a slot of its own | full freedom | that is controlled mode (D17), which already gives it |

**Recommendation: a; the owner chose b (2026-10-17).** Inline needs the panel's hook to find its grid by `data-table` (D4), not by its id. A picker inline shows its table in the page under the panel or the cell's row; the picker's table is still a registry entry, drawn in the part's slot as today.

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
| Confirm (actions, a column's, a reference cell's; a panel's own question is asked with the panel, by the table or by the host with `:panel`) | `class(:confirm, …)` | `confirm` | yes, `:confirm` (widened, D17). The host shows the question; the browser can still send an event as if confirmed, which runs as in the table's own mode: a question is no safety check (target §1.5; final review S1, owner 2026-10-17) |
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
| Nested tables and pickers' tables | — | **no, deferred.** A host addresses the table it placed, by its attach name (stage 6 D2, D11); a nested table's id is generated, and its questions are about rows the host never listed. Revisit after release with a real use. **Changed by the owner, 2026-10-17: nested tables and pickers' tables controlled too** (every component's behaviour can be taken over; a nested table is the same as its parent): `controlled:` applies to the whole tree; each request carries its table's id and `path`; a command finds the table by the request's `ref`; section 15, drift fixes |

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

**D23. Texts and values for every part (owner, 2026-10-17; amendment for step 7c.0).** Until 7c a kit of one's own got raw values only: `AshDataTable.Text` and `AshDataTable.Format` are internal, so the demo's `DivKit` wrote English and showed raw summary values. The owner said yes to the principle; this is its shape.

- **What a part is given.** Wherever a part shows a text or a value: `texts`, a map from a name to the finished string in the person's language (`text` alone for a part with one, `message` and `failure`), and `messages`, the same map with the message each was made of (`message` alone). A name may hold a list (the errors of a field). For a value, besides the raw `value` the part had: `text` (as the default kit shows it) and `locale` (Gettext's locale of the table's backend). A HEEx kit shows `text`; a React or Vue kit (live_react, live_vue) or an API client ignores it, translates `message` itself and formats `value` with `Intl`.
- **A message** is `{key, values}`: `key` one of `AshDataTable.Messages.keys/0`, `values` a map of the names that key documents (a value may be a message itself). Three keys are no text of the table's own: `:label` (`%{text: …}`, the resource's own wording, translated in the `ash_data_table` domain as a column label is), `:join` (`%{separator: …, messages: […]}`) and `:words` (`%{text: …}`, words already). An action's message (an Ash validation error) passes as Ash and AshPhoenix give it: `{message, vars}`, a string and a keyword list, which a host's `translate_error/1` takes. The labels of the model (columns, values, actions, relationships, arguments, the table) are given in words in the model, as they are now: they are the resource's wording, translated as the model is made for the person.
- **The public list.** `AshDataTable.Messages` (part 3w, public) holds every key with the names of its values, documented in its moduledoc, generated from the list: like a Gettext msgid with its bindings, or react-intl's `id` and `values`. `AshDataTable.Text.t/2` and `n/3` refuse a key that is not in the list, and a test says the list and the texts agree (each key has a text, and the text's `%{…}` are the list's names) and greps `lib/` for keys used.
- **Where it is made.** The core makes keys and values as before. `AshDataTable.Kit.Words` (part 3, internal) is the one module that says which texts each part shows, and `Kit.part/1` (through which every part is drawn, `Kit.cell/1` and `Kit.editor/1` too) puts them into the part's assigns before the kit draws it, in the LiveView's process, as the words are made today. To change what a part is given is to change that module. They are given again (marked changed for LiveView) only when an assign they are made of changed (`Phoenix.Component.changed?/2`), so a part sends a text again only with what it is made of.
- **`Kit.Default`** shows the texts it is given and calls `Text`/`Format` no more for what a part is given; what it draws below a part (a group's item, a position in a list) keeps its own words. `KitCase` draws every state through a kit that checks each part's assigns against the contract (`texts` and `messages` where it says), and the demo's `DivKit` shows the given texts (one test draws it in German).
- **Bytes.** `messages` and `texts` are assigns on the server: only what a part renders is sent. Measured with `baseline.mjs` at the end of 7c (section 15).

Example, the question part in German: `texts: %{cancel: "Abbrechen", confirm: "Bestätigen"}`, `messages: %{cancel: {:cancel, %{}}, confirm: {:confirm, %{}}}`; a summary cell: `value: 1240, text: "1240", locale: "de", texts: %{kind: "Summe"}, messages: %{kind: {:summary_sum, %{}}}`; the pagination: `messages: %{range: {:range_of_total, %{from: 1, to: 25, total: 140}}, …}`.

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
- `attach/4` refuses nothing the table on the page opens; nested tables and pickers' tables are controlled too (owner, 2026-10-17).
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
7. §9 stage 7, "presentation … confirm dialog": the confirm is modal or inline like the panel and the picker (D11 b, chosen by the owner 2026-10-17; this amendment first said "modal-only in v1").
8. Stage 6 D14 and S7/S8: controlled mode gains `:picker`, `pick_request/4`, `add_group_request/4`, `remove_group_request/4`; nested tables stay uncontrolled in v1 (D17).
9. §7.5, rows under fixed headers: after the release, as a kit option (D20).
10. `CONTEXT.md` gains "kit", "part", "bundle", "marker" in the documentation pass after stage 7 (the rule for docs during the refactor).
11. S5 and the module table: `AshDataTable.Attrs` is public; a kit's parts call it with the values they are given (owner, 2026-10-17; made in target.md with the drift fixes of 7b).
12. §9 stage 7, what opens: one question at a time per table. A question asked while another of the table is open gives the first up, as Cancel does, and what it was about does not run; a question about the selection is given up when the selection changes, and Confirm runs the action only on the selection the question named (owner, 2026-10-17).
13. §9 stage 7, what opens: a question in the page asked from a panel or picker that is over the page (or from what is drawn inside one) is shown inside it, a copy the hook removes when it is answered; a patch that removes it answers Cancel. A picker in the page that a field of a panel over the page opens is drawn inside that panel (owner, 2026-10-17: mixing presentations is never refused and always works).
14. S3 and S13: a part is given, wherever it shows a text or a value, the finished text, the message (a key of the public `AshDataTable.Messages` and its values) and, for a value, the raw value and the locale (D23, owner 2026-10-17; made in target.md with step 7c.0, as the owner said yes to it).
15. S7, S8, §9 stage 7 (amendment 8 changed): owner, 2026-10-17: nested tables and pickers' tables controlled too. `requests/1` reads every request of the tree, each with its `table` and `path`; the commands find the table by `ref`; `:request_ended` says a request is held no more (D17; made in target.md with the drift fixes of 7c, as the owner said yes to it).
16. S6: the wire protocol of controlled mode: the push `ash_data_table:answered` (`{table, ref, cell, saved, error}`) and the reply `{held: true, ref}` to a save, clear or reference choice whose question the host asks (owner said yes, 2026-10-17; made in target.md with the drift fixes of 7c).

## 11. Public API only (owner's rule, 2026-10-16)

| Decision | What of a dependency it uses |
| --- | --- |
| D3, D7, D8 | `Phoenix.Component` attribute spread and slots; `defoverridable`; `@after_compile` |
| D10 | `apply/3` inside a function component (LV "Dynamic Component Rendering", as `parts/common.ex:11-21`) |
| D11 | `HTMLDialogElement.showModal()`; ARIA `region` |
| D12 | `Phoenix.LiveViewTest` (`live_isolated/3`, `render/1`, `render_hook/3`), `AshDataTable.Test` for portals; `Ash.DataLayer.Ets` |
| D13 | `liveSocket.isDebugEnabled()` (`this.liveSocket` of a hook, both in LV's public TypeScript API) |
| D17 | `Phoenix.Component.live_file_input/1`; `AshPhoenix.Form` as stage 6 |
| Final review R12 | The fields of `Ash.Policy.FieldPolicy` (`condition`, `policies`, `fields`): a Spark entity's documented DSL options, read in `Resource.Exposing` (allowed by the owner, 2026-10-17) |
| Final review R3 | **Owner-kept exception (owner, 2026-10-17):** the grid's hook sets and removes `phx-update="ignore"` on the one cell whose single value is being edited (`assets/js/grid/editing.js`, `startEdit`; `saving.js`, `detach`), and nowhere else since the browser-side simplification (§15): LiveView documents the attribute as rendered by the server. The documented way, an empty container with the attribute and an id in every editable cell, measured on `/tasks` with `PERF_WIRE=1` (7 runs, medians): a page change 155,550 → 183,412 bytes of payload (+17.9 %), 11,796 → 13,901 on the wire (+17.8 %); a cell save 8,500 → 9,674 (+13.8 %), 116 → 130 on the wire. Re-checked on every LiveView upgrade; guarded by `editing.spec.ts` and `live_updates.spec.ts` |
| D19 | `phx:push` with `detail.unlock` (as today; LV's CHANGELOG names `phx:push`'s `detail.lock()` as client API, #4351). To be confirmed against LV's JS-interop guide in 7a step 0; if it is not documented there, it is an internal and you are told |

## 12. What the owner said that this note keeps

- D-parts, D-headless: fully headless, a bundle for every element, rows and cells too; the hooks on markers only.
- 2026-10-15: what opens is modal or inline, by the kit, per table; three levels for every UI element; controlled mode needs `attach`; safety stays in `Operation`.
- F1: no sensitive value on any path but "Show"; `KitCase` checks it.
- F3, F13, Q12 as decided; D-nested: no live component per nested table (D18 d not proposed).
- Ash way and public API only (2026-10-16); greenfield (no old contract numbers, no shims); tests exactly once per suite at the end (2026-10-16); docs: the architecture map and the moduledocs of new public functions only.

## 13. As built: 7a

Commits on `main` after `stage7-start` (`c3e5a94`): `915bfb8` (step 0: status, target.md amendments 1–9), `a55a445` ("open the panel" in `baseline.mjs`, D22), `72b281a` (step 1), `8d3c302` (step 3), `07ebe47` (step 4 and test group X), `77e25e6` (step 5), `5a76a99` (step 6), `1bbef66` (a test formatted), `6256e58` (the grid's sender in place of the unlock; the snapshots, reviewed by the owner).

**The shape.** As section 4, with these details:

- `AshDataTable.Attrs` (`lib/ash_data_table/attrs.ex`, part 3: `test/architecture_test.exs` places `attrs.ex` there) and `assets/js/markers.js` name the same markers (`Attrs.markers/0`; `test/markers_test.exs` compares them and greps the hooks for the done-check of section 9). New on the markup: `role="rowgroup"` on a record's and a detail's row group, `role="dialog"` on the three dialogs, `data-table` on the element of each hook, `data-paragraph` on the paragraph of a cell with `max_lines`, `data-unseen` beside `sr-only` in a cell (D5), and the grid's sender (below).
- **D3: fallback b, wider than the row, row group and cell.** With every bundle spread, "Page change" sent 11.3 % more (149,779 → 166,750 bytes), and a cell save 50 % more (the footer row of the summaries is sent twice per save, each cell's whole attribute list as one dynamic). So every element drawn per row or per column (a record's row group, row and cells, the action buttons, the header and filter cells, the lines, the summaries, the resizers, the editor templates) writes its constant attributes in the part and spreads only what varies (`Attrs.rowgroup/2`, `cell/5`, `actions/2`, `action/2`, `column_header/5`, `summary/2`). Elements drawn once per table spread their whole bundle. `KitCase` (7b) asserts the constants.
- **D4: rows by place, not `aria-rowindex`** (accepted by the owner, 2026-10-16). A column is by `aria-colindex`; a row by its place among the grid's own `[role=row]`s, the header's first (the stream may put the records before the header in the page), the footer's last, as `HTMLTableElement.rows` had them. The lines of a detail have no `aria-rowindex`. Native controls are still asked for by kind (`input`, `button`, `form`, `template`, …), never the table's structure.
- **D5: the default colours** (accepted by the owner, 2026-10-16). The hooks read `var(--ash-data-table-ground, var(--ash-data-table-default-ground, Canvas))` and the same for `-line`; the root sets only the `-default-` pair from daisyUI. A value set on the root itself would hide the one a host sets on an ancestor (`layout-and-embedding.md`).
- **D6** is `Parts.Grid.root/0`: the rules written out in full on markers (Tailwind finds a class only as written), a grid's own cells reached through `[role=grid]>[role=rowgroup]>[role=row]>[role=gridcell]`. Only the root of the table on the page carries them; a table keeps `class="table"` (and `w-auto` nested).
- **D18 c**: `phx-no-format` stays only where whitespace is drawn (the rows, a header's label, the live region, the failure template, the whole-text popover, the related heading).
- **D13**: `assets/js/check.js`, run by the transport's `hook(behaviour, part)` after `mounted` and `updated` while `liveSocket.isDebugEnabled()`.
- **D19: no unlock; a sender** (owner, 2026-10-16). `detail.unlock`/`detail.lock` of `phx:push` are not in LiveView 1.2.12's documentation (the guides JS interop, bindings and syncing changes at https://hexdocs.pm/phoenix_live_view/1.2.12/, nor its module docs; only a CHANGELOG fix, #4351, names `detail.lock()`): an internal. LiveView locks the element of the hook that pushes (`pushEventTo` of a hook): observed in 1.2.12, not documented either (the drift check read the guides "Syncing changes and optimistic UIs" and "JavaScript interoperability" of 1.2.12: they name the `-loading` classes of an element that pushes, not a lock of a hook's element nor patches kept aside); `portals.spec.ts` is what guards it. So the grid's events are pushed by its sender, an empty element drawn before the grid (`Attrs.sender/1`, `data-sender`, `data-table`, hook `.Sender`, `assets/js/sender.js`), and the grid is never locked. `portals.spec.ts` holds the server's answers as one stream (it reads none of them) while a line opens and then a cell saves: the nested table must arrive while the grid's own save is still on its way. Without the sender it fails with stage 5's "portal target … not found" (checked once).
- **Test group Y** is `/e2e/markers` (`DemoWeb.E2E.MarkersLive`): a grid of `div`s and `span`s with the markers, a sender, a table nested in a cell, and a style sheet of no weight (`:where`); `markers.spec.ts` drives it (arrow keys, Enter into the nested table and Escape out, editing, Space and Shift+Down, widths, hiding) and checks D13. **Group X**: the ExUnit and Playwright helpers and about 60 test lines find rows and cells by role, not by tag; the ten `btn-error`/`btn-primary` assertions check `data-destructive`.

**Bytes (D18, D3; §6), smallest of 15 runs, at `stage7-start` → the end.** The class list of a `<table>` was 4,321 bytes (4,328 nested), a resize handle's 501 (2,505 for the five columns of the comments table); an opened nested table's statics held 1,073 characters of indentation. Opening a nested table 33,923 → 29,813 (−4,110), opening the picker 31,932 → 26,814 (−5,118), "Page change" 149,307 → 144,991 (median −2.9 %), a cell save 7,312 → 7,309. D18 c alone: −168 bytes per nested table, −92 per picker; the sender: about +220 per nested table. The markup snapshots grow by about 2 KB per page with one table (the root's rules, 6,348 bytes, sent once at mount).

**Performance (D22).** `demo/perf/baseline.mjs` on `/tasks`, `stage7-start` in a worktree and `6256e58`, back to back, 15 runs each, at the machine's load: 13.2 at the start of the first run, 5.5 at the start of the second, 2.9 after it. Median ms, start → end; median bytes; Ash reads and statements the same for every action:

| Action | ms | bytes |
| --- | --- | --- |
| Cell save | 37.7 → 35.4 | 7,312 → 7,309 |
| Expanding a row | 9.3 → 9.2 | 3,294 → 3,266 |
| Opening a nested table | 42.4 → 38.3 | 37,195 → 32,985 |
| Opening the picker | 36.1 → 34.4 | 41,071 → 32,508 |
| Opening the panel | 25.9 → 23.3 | 4,231 → 4,201 |
| Cell save in a nested table | 22.0 → 23.3 | 3,494 → 3,418 |
| Cell save with a nested table open | 33.7 → 32.0 | 7,547 → 7,544 |
| Selecting a row | 3.3 → 3.5 | 198 → 198 |
| Page change | 69.1 → 73.6 | 149,735 → 145,420 |

**Tests.** During the steps, `mix test --stale` (root and demo) and the browser spec files of each step, once per change. At the end, once each: root 1,232 tests, 0 failures; demo 2,862, 0 failures; browser 987 passed, 0 failed (8.0 min); no laptop sleep during any run.

**Left for 7b.** The kit draws the parts; the bundles become its assigns; `KitCase` asserts the constants that D3 b leaves in the parts. The drift check of 7a.

**For the docs pass.** LiveView turns its client debug on by itself on `localhost` and `*.localhost`, unless it was turned off (`LV assets/js/phoenix_live_view/live_socket.ts:554-560`, in `connect()`): in a usual dev setup the D13 check runs, and walks every cell of every grid after every patch. Not on `127.0.0.1`, which the browser suite uses.

**The marker contract is wider than `markers.js`.** Besides the markers, the hooks rely on ids and on `data-*` values they read; `KitCase` (7b) must cover them too. Ids, after the table's id: `-grid`, `-table`, `-head`, `-head-row`, `-filter-row`, `-foot`, `-summaries`, `-row-KEY` (a record's row group; its cells `…-c-FIELD`, a line's cell `…-l-REL-c`, the expander `…-e`), `-editor-FIELD`, `-count-N`, `-error`, `-failure`, `-whole`, `-dialog`, `-dialog-question`, `-selection`, `-selected`, `-selection-controls`, `-select-all`, `-select-head`, `-clear-selection`, `-result`, `-arguments`, `-columns`, `-columns-button`, `-columns-control`, `-columns-status`, `-columns-text`, `-scrollbar`. `dataset` keys: `action`, `addGroup`, `all`, `ask`, `bulk`, `choicesButton`, `choose`, `chosenRows`, `clearField`, `commit`, `confirm`, `count`, `editor`, `expanderCell`, `filtered`, `firstRow`, `head`, `hide`, `hideLabel`, `invalid`, `keepsOne`, `key`, `label`, `lead`, `line`, `lineCell`, `lines`, `max`, `more`, `pending` (the hook's own), `question`, `removeGroup`, `removeLabel`, `row`, `saved`, `sayHidden`, `sayShown`, `select`, `selected`, `several`, `show`, `showLabel`, `sort`, `sorted`, `unpick`, `value`, `valueLabel` (`grep -rhoE 'dataset\.[a-zA-Z]+' assets/js`).

**Drift fixes** (after the drift check of 7a):

- The paragraph the hook puts into a cell with `max_lines` as a save goes out has its marker (`data-paragraph`), so the root's rules cut it off and `cutIn` measures it; `long_text.spec.ts` holds the save on `/e2e/held` (its table's `before_action` waits until the test lets it go) and checks the cut.
- Every part takes its markers from `Attrs`: bundles for the selection line's buttons, the heading's create and table actions, the argument line's form and the filter row's form; what varies of the lines, the counter, the list editor and the panel's fields and groups (D3 b). `markers.js` names `DESTRUCTIVE`, `SELECT_ALL`, `BULK`, `QUESTION`, `CONFIRM`; the hooks test them by marker, not by `dataset`. Bytes (§6, 15 runs, smallest and median, `/tasks`, load 2.7): opening a nested table 29,681 / 32,853 (−132 against the end of 7a), the picker 26,782 / 32,478 (−32, −30), the panel 4,161 median (−40), "Page change" 144,963 / 145,392 (−28), a cell save 7,309, a save in a nested table 3,418, with one open 7,544, selecting a row 198: none grew.
- The sender's reliance on LiveView's lock of a pushing hook's element: not documented in 1.2.12 (D19 above); the comments say so and name `portals.spec.ts` as its guard.
- A record's row group is a `role=rowgroup` that is not the header (`ID-head`), the footer (`ID-foot`) or a detail (`isRecord`); the header of `/e2e/markers` is a row group, and selecting the page selects only its records.
- `actions.spec.ts` checks that the Confirm of a question that deletes has another ground than one that does not; `picker.spec.ts` that "Choose" looks otherwise while `aria-disabled`.
- A table without its question dialog runs nothing it would ask about (`ask` resolves to no; `console.error` while debugging), and the development check names `ID-dialog` where the table asks. Mutation-checked once.
- `footer_summaries_test` asserts again that the footer group is a child of the grid; each test that finds nothing of a role asserts that the role is there.
- `/e2e/markers` also runs `whole_text.js` (a cell with `max_lines` and its popover), `expanding.js` (a line that opens and closes the nested table), `dialog.js` and `arrays.js`'s save of a text. Only the grep of `test/markers_test.exs` guards `counter.js`, `choices.js`, `actions.js` (row actions), `sensitive.js`, `failure.js`, the list editor of `arrays.js`, the expander of `expanding.js`, the sticky labels and the window's scrollbar of `scrolling.js`, and `panel.js`, `picker.js`, `pagination.js`.

## 14. As built: 7b

Commits on `main` after `stage7b-start` (`9bee2a1`): `209a2c3` (step 1), `5b0ce87` (step 2), `fb381db` (step 3), `9c72d32` (step 4), `4be14d2` (step 5), `051289a` (bytes, below; "open the panel inline" in `baseline.mjs`), `6a48665` (the question inline, owner 2026-10-17), `3cd40ed` (the snapshots, reviewed by the owner), `a02fe5c` (an inline question asked from a modal panel or picker, owner 2026-10-17).

**The shape.** As section 4, with these details:

- **The kit (D7, D8, D15).** `AshDataTable.Kit` (`lib/ash_data_table/kit.ex`, part 3) has a callback per part of D8 (33, `Kit.parts/0`), `class/2` and `presentation/1`. `use AshDataTable.Kit, contract: 1` defines every part as `Kit.Default`'s, overridable (`super`), and `use Phoenix.Component`; another contract fails at `use`, and `@after_compile {AshDataTable.Kit, :checked}` fails a public function of arity 1 that is no part and a `class`/`presentation` of another arity (`test/kit_test.exs`). A part draws the parts in it through the kit, `<Kit.part part={:row} kit={@kit} …/>`, never by calling another part's function; `Kit.cell/1` and `Kit.editor/1` resolve the column's component before the kit (D10) for a kit's own row and grid. `Kit.check!/2` refuses a module that is no kit, or whose `presentation/1` answers neither `:modal` nor `:inline`. `Kit.Default` delegates every part to `Parts.*` and holds the classes of the parts drawn once per table (`class/2`).
- **The drawing.** `AshDataTable.Live.Drawing` (`live/drawing.ex`, part 4, in the architecture test's wiring list) turns what the core holds into the values each part is given and calls the kit's parts in their order, inside the kit's `root/1`. The root element of every table was the wiring's, with the kit's `class(:root, …)`, as a live component's root must be a static tag; that holds for the tag only. Since the final review (A2, owner 2026-10-17) the kit's `root/1` draws the root element (`Attrs.root/2`) of the table on the page, of each nested table and of each picker's table, around the table (`inner_block`) and `opened`, where the question, the panel and the picker are drawn; the tag's live component keeps a plain static element (`display: contents`) around it. `lib/ash_data_table.ex` keeps `attached/1` (the root element) and the five colocated hooks, whose names stay `AshDataTable.Grid` and so on. The markup contract comment moved to the top of `lib/ash_data_table/attrs.ex`. The filter row's form is drawn by `grid/1`. The failure popover and the boolean mark are HEEx (`Parts.Common.failure/1`, `Parts.Grid`).
- **D3, D8 changed: a part calls `AshDataTable.Attrs` itself** (owner, 2026-10-17). `Attrs` is public and its moduledoc is the contract; a kit's part computes its bundles from the values it is given, as `Kit.Default`'s do. The bundles are not given as assigns: a value a library function adds to a component's assigns is not change-tracked by LiveView unless the caller passes it as an attribute, so a part would be drawn again on every patch or not when it should; and a kit that replaces a parent part would have to compute its children's bundles anyway. What varies per row and column is given where it is cheap (`header_cell`'s `attrs`); values a kit needs that were computed inside parts are given as values (`grid`'s `filters` and `pages?`).
- **D9.** `kit` in `config :ash_data_table, kit:`, `kit={…}` on the tag, `kit:` at attach and on the router line; held in `Table.options.kit`, which nested tables and pickers' tables are drawn with.
- **D11 and its change (owner, 2026-10-17): the question is modal or inline like the others.** `presentation: [panel:, picker:, confirm:]` on the tag, at attach and on the router line, over the kit's `presentation/1`. Every part that opens carries `data-presentation` and, modal, is a `<dialog role=dialog>` the hook opens with `showModal()`; inline, an element with `role=region` named by its title or question. `panel.js`'s `opened/2` (the picker's too) and `grid/dialog.js`'s `askInline` follow it: focus to the first control (the question's Cancel), Escape inside it is Cancel, focus back to the opener, nothing inert, Tab leaves it; `grid/shared.js`'s `AROUND` stops at `[data-presentation]` as at a dialog. The question inline is not an `alertdialog` (ARIA has that one modal). **One question at a time per table:** a question asked while another of the table is still open in the page gives the first up, as Cancel does (its action does not run). **An inline question asked from a panel or picker that is open over the page** is shown inside that panel or picker: a copy of the question with ids ending in `-in`, removed when it is answered; a patch that takes the copy away answers it as Cancel. Everywhere else it is shown where the kit's `root/1` puts it. A missing question fails closed as in 7a.
- **D12.** `AshDataTable.KitCase` (`kit_case.ex`, T) and `AshDataTable.Test.Resource` (`test/resource.ex`, T, with `.Domain`, `.Owner`, `.Part`: `AshDataTable.Test.Domain` is the name of a domain of the library's own test support). `use AshDataTable.KitCase, kit:, endpoint:` (the endpoint is needed by `live_isolated/3`) runs 10 states × 3 presentations (`:modal`, `:inline`, and `:mixed`: the panel and the picker modal, the question inline), each in an ETS tenant of the test's own, and asserts the markers, ids and element kinds of section 13 (the constants of D3 b on every cell, header, row and record, the question, panel and picker per presentation, one control per editor template, no tab stop in the grid) and that the page holds no `Test.Resource.secret/0`. Mutation-checked once: `Present` giving a sensitive cell its value fails 16 of 20. The library runs it against `Kit.Default` and `DemoWeb.DivKit` (`demo/test/demo_web/kits/`). The shipped resource is compile-connected to the extension as a host's resource is; the architecture test lets that file be. The root `config/config.exs` sets `default_string_length_count` for every environment, as the library compiles the resource as its own.
- **The demo's kit** `DemoWeb.DivKit` (`demo/lib/demo_web/div_kit.ex`) draws the grid, its rows, cells, lines and footer with `div`s (laid out with `display: table`) and opens everything inline. `/e2e/kit` (`DemoWeb.E2E.KitLive`) draws a table of `Test.Resource` with it (`?presentation=modal`, `?presentation=mixed`); `kit.spec.ts` is group AA (panel, picker and question inline, modal, and the question inline from a modal panel: focus in, Escape, Cancel, Confirm, focus back, Tab out, axe) and part of group Y (arrow keys, editing, a nested table). `/e2e/markers` stays for what a kit can leave out, which the development check names.
- **D14.** The hints are `component`, `max_lines`, `sticky_label?` (`Model.Column`'s comment, `Kit`'s moduledoc); `test/architecture_test.exs` fails on a read of one in 2a or 2b but the model and `Live.Core.in_words/1` (checked once by adding one).
- **Bytes.** At first "Page change" sent 21 % more: the root's class (the structural style, 6 KB), the filters and the messages depended on the whole table and were sent with every patch. They now depend on the fields they show (`@table.options.kit`, `@entry.model`, …), and LiveView's change tracking leaves them out. What is left is the kit's dispatch: every cell, row and actions cell is a component of its own.

**Performance (D22, §6).** `demo/perf/baseline.mjs` on `/tasks`, `stage7b-start` in a worktree and `a02fe5c`, 15 runs each, wire bytes with `PERF_WIRE=1`, at the machine's load: 1.6 before the first run, 3.9 before the second (10 a few minutes earlier). Median ms, payload bytes and wire bytes, start → end; Ash reads and statements the same for every action:

| Action | ms | bytes | wire bytes |
| --- | --- | --- | --- |
| Cell save | 37.0 → 35.0 | 7,309 → 8,277 | 88 → 125 |
| Expanding a row | 10.3 → 8.1 | 3,266 → 3,345 | 171 → 171 |
| Opening a nested table | 60.2 → 58.6 | 32,853 → 33,703 | 4,598 → 4,853 |
| Opening the picker | 36.2 → 34.2 | 32,478 → 34,961 | 3,288 → 3,606 |
| Opening the panel | 24.6 → 27.2 | 4,161 → 4,244 | 81 → 84 |
| Opening the panel inline (new) | — → 13.6 | — → 4,185 | — → 84 |
| Cell save in a nested table | 21.5 → 17.6 | 3,418 → 3,696 | 48 → 50 |
| Cell save with a nested table open | 36.3 → 32.5 | 7,544 → 8,520 | 99 → 123 |
| Selecting a row | 3.9 → 3.9 | 198 → 215 | 10 → 10 |
| Page change | 76.1 → 73.7 | 145,392 → 152,255 (+4.7 %) | 10,869 → 11,603 |

Times within 20 %; "Page change" within 5 % (D3).

**Tests.** During the steps, `mix test --stale` (root and demo) and the browser spec files of each step, once per change. At the end, once each: root 1,243 tests, 0 failures; demo 2,928, 0 failures; browser 1,003 passed, 2 failed (8.5 min), no laptop sleep during any run. The two:

- `files.spec.ts` "a bar under the input says how far the file has come": fails at `stage7b-start` too (checked once in the worktree). The server closes the socket, "Received compressed frame inflating too much": the test's file of 90,000 empty lines is sent deflated since the demo's LiveView socket is compressed (`75a2e10`), and inflates beyond what the server takes. Not of 7b; left for the owner.
- `pagination.spec.ts` "a cursor that is none says that the records could not be loaded": showed "You are not allowed to see these records." once, under the load of the full run, and passed alone. Not found: the servers' logs of the run were overwritten by the check that followed. 7b changed nothing of how a read's error is said.

**Left for 7c.** Controlled mode widened (section 4, 7c). The drift check of 7b.

### Drift fixes of 7b

After the drift check of 7b (owner's decisions of 2026-10-17: every component customizable, mixing presentations never refused; the question `:modal` or `:inline`; `Attrs` public; one question at a time per table). Commits `2193660`, `6f9456c`, `7f26231`, `4bb1622`, `30c86aa`, `40d9aa3`, `a355af2`, and the installer's `65f2fc7`.

- **A question about the selection confirms that selection** (M1). The reply to `bulk` carries `selection`, a token of what the entry holds as selected and what under (`Core.Selection.token/1`, a hash of claims the page has already); `bulk_run` sends it back, and `Core.Bulk` runs nothing where the selection is another, and says so in the result and the live region (`:bulk_selection_changed`). In controlled mode the request holds the token, so the host's Confirm is checked the same way. The action is looked up first, so a forged `bulk_run` of an action not offered still meets that check. Tests: `selection_test.exs` (hook path) and `controlled_test.exs`; mutation-checked once (the refusal made to pass any text: both fail). `DemoWeb.TablePage.confirm_bulk/3` and `bulk_token/3` send what the hook sends.
- **One question at a time** (M2). The grid's two flags that dropped a second question are gone; only the `bulk` push keeps a guard while it is out. `ask` gives up the open question (`giveUp`), which resolves to `GIVEN_UP` (`grid/shared.js`): nothing it was about runs, and its callers (`arrays.js`, the cell editors) leave focus where it is. A change of the selection gives up an open question about it. A modal question given up is closed; the close event of a question given up is told apart from the next one's (`dialog.open`).
- **The picker inside the panel** (M3a). The `panel` part has a slot (`inner_block`), drawn after its form: a picker a field opened, where the panel is modal and the picker inline, is drawn there (`Live.Drawing.picker_in_panel?/2`); the panel's hook leaves the events of what is drawn inside it to their own hooks (`own` in `panel.js`). `KitCase`'s presentation `:inside` and `kit.spec.ts` cover it.
- **The host of the copy** (M3b). `panel.js` and `picker.js` pass their element to `ask`; else the dialog that is `:modal`. `document.activeElement` is still the opener focus goes back to.
- **KitCase** covers section 13's contract: the ids (`-foot`, `-summaries`, `-count-N`, `-arguments` among them), every server-written `data-*` value the hooks read, every part drawn once (`related` and `full_view`, which need a router, through `render_component/2`), every page on the way to a state, and 20 states × 4 presentations. `Test.Resource` gained what that needs (its moduledoc lists it). The demo's kit of divs now draws its summaries and its full view, which `KitCase` found missing. The secret check covers the create and `rekey` panels, a failed save of the secret column, a failed create with the secret typed, and the sensitive columns of the nested and picker tables. **Mutation check (redone):** `Present` letting the value through (no scrub, `:value` for a sensitive cell, the typed text kept, the panel's sensitive field filled) fails 68 of 76 `Kit.Default` tests: every state but `:empty` and `:error`, which hold no record.
- **Smaller fixes.** Focus goes to Cancel; a missing question or Confirm runs nothing; a copy whose panel is removed answers Cancel. `Kit.editor/1` reads `Model.Column.required?`, not Ash. Every part's assigns are in `Kit`'s moduledoc, every public function of `Attrs` has a doc. `Parts.Filter.filter_form/1` (dead) is gone; `Parts.Messages.confirm/1` and `whole_text/1` are named as their parts. The D14 guard catches `.component`. `Kit.check!/2` refuses a kit without `presentation/1`; the tag checks its kit once, as it is first named (`AshDataTable.kit!/3`, `Live.Embedded`). A configured bad kit is tested through a mounted LiveView. Tests of bad `kit:`/`presentation:` at attach and on the router line. `config/test.exs` lost a line `config.exs` has.
- **Owner's browser behaviours** (`kit.spec.ts`, `live_updates.spec.ts`): a table action asked while a question about the selection is open shows its own and the first runs nothing; a selection change gives that question up; Confirm inside the copy; a patch that removes the copy answers Cancel; the picker inside a modal panel; a live update under an open inline panel keeps its row until the panel goes (`/e2e/inline/tasks`).
- **`pagination.spec.ts`, "a cursor that is none".** Read, not rerun in loops: "You are not allowed to see these records." is the comments' answer to a read without an actor (`actor_present`). `Demo.Actors.fetch/1` took every failed read of the session's user (a connection of the test's transaction not had in time, under load) for nobody. It raises now, and LiveView mounts the page again; the spec passed once.
- **Compression (owner, 2026-10-17).** The installer no longer turns on compression on LiveView's socket (`65f2fc7`): an app-wide trade-off the host decides; the demo keeps it. `files.spec.ts`'s progress test sent 90 kB of empty lines, which deflate past Bandit's inflate guard; it now sends one label and varied comment lines (`#`, which the demo's import skips), about 3.5 to 1.


## 15. As built: 7c

Commits on `main` after `stage7c-start` (`452306e`): `d5521aa` (D23 written into this note), `3c5a7ce` (step 7c.0, texts and values for every part), `90a5cb4` (7c.1, a column's and a reference cell's question), `2f5f330` (7c.2, the picker), `054cd9c` (7c.3, every panel; `attach/4` refuses nothing), `1522103` (the browser tests of group AB), `3659c40` (the architecture map and the markup contract).

**7c.0, texts and values (D23).** As section 3, D23: `AshDataTable.Messages` (`messages.ex`, 3w, public) lists 132 keys with their values and the three made ones (`:label`, `:join`, `:words`); `Text.t/2` and `n/3` refuse a key not in it; `test/messages_test.exs` checks each key's text against its values and greps `lib/` for keys used. `AshDataTable.Kit.Words` (`kit/words.ex`, part 3, internal) is the one seam: one clause per part, applied by `Kit.part/1`. `Kit.Default` shows the given texts; what it draws below a part (a group's item in the panel, a value's place in a list of groups, the forbidden value inside a union) keeps its own words. `Attrs.selection/3`, `list/1` and `pagination/3` take texts instead of calling `Text` (`Attrs` calls `Text` no more). `KitCase` draws every state through a probe kit that checks each part's assigns (checked once by asking a name no part has: 76 of 76 fail). The demo's `DivKit` shows the given texts, its summary as `Summe 43` in German (`div_kit_test.exs`). Model labels stay words in the model (section 3, D23).

**7c.1, the questions.** With `:confirm`, the editors' templates carry no `data-confirm` (`asks?`), so the hook asks nothing; `Core.Cells.on/2` holds a save or clear of a column with `confirm` as `%{kind: :confirm, for: {:save | :clear, key, name}}` (the typed text in `run`, `value` nil in the projection for a sensitive column), replying `{held: true}`: the hook keeps the cell `aria-busy` and what puts it back (`holds`). `Core.Picker.refer/7` holds a reference cell's choice the same way and closes the picker. `confirm_request/3` runs `Cells.write/2` or `Picker.refer/7` confirmed, through `Operation`; the hook is told `ash_data_table:answered` (`saved`, `error`), and puts the cell back where it was not saved, also when Cancel or a new request lets the question go. A question ends a panel or picker held for the host.

**7c.2, the picker.** With `:picker`, a picker of the table on the page (a reference cell's, or a field's of a panel the table draws) is a request: the drawing draws no picker and `Nesting` opens no table for it (`Requests.host?/3`). The projection gives `resource`, `several?`, `none?`, `value` (what is held), `chosen` (labels of a field's records), `question`. `pick_request/4` takes a primary key (a map, or a one-field key's value), a list, or nil; each is read again as the person through the picker's read action (`Pick.chosen/3`), after the veto. Where the table asks its own questions, the host's choice is its answer to the column's question (it is in the request); with `:confirm` too, it is a request of its own.

**7c.3, every panel.** A map cell's panel is a `:panel` request; every panel kind is handed to the host; `attach/4`'s refusal is gone. The projection describes each field with `editor`, a group's `fields`, a union's `kinds`, the chosen records (`chosen`), and a file field's `upload` (`Files.upload_name/2`, whose `live_file_input/1` the page draws; `submit_request/4` consumes it as the panel does). `add_group_request/4` and `remove_group_request/4` take a path, as `panel_add` and `panel_remove`; a path that is not a list of names raises. Chosen keys come back in the params and are read again as the person (`Act.unchosen/4`). **Fallback of section 7 (7c.3): not taken**; the two commands were enough.

**Not taken on, as D17 said then.** Nested tables and pickers' tables stayed uncontrolled in 7c: they are drawn with the kit of the table on the page (every part replaceable, D16 levels 1 and 2), but a host could not take over what they open (level 3). Taken on in the drift fixes of 7c (owner, 2026-10-17), below.

**Tests.** Group AB: `demo/test/demo_web/tables/controlled_widened_test.exs` (21 tests, `DemoWeb.Support.ControlledKitLive`, a table of `Test.Resource`, whose `secret` and `owner` columns now ask first) and `controlled_test.exs` (the map cell's panel a request; attach refuses no panel). Mutation-checked once each: the projection giving a sensitive column's typed value (1 of 10 fails), a stale `ref` answered (2 of 10), `Pick.chosen/3` taking a key without reading it (2 of 16). Browser: `controlled.spec.ts` on `/e2e/controlled/kit` (a column's question: the cell waits, Confirm saves, Cancel puts it back; the page's picker and its question). At the end, once each: root 1,247 tests, 0 failures (load 6.4 at the start); demo 3,044, 0 failures (load 8.3); browser 1,015 passed, 0 failed (8.4 min, load 12.6 at the start, 19.4 at the end). No laptop sleep. The markup snapshots did not change.

**Performance (D22, §6).** `demo/perf/baseline.mjs` on `/tasks`, `stage7c-start` in a worktree and `3659c40`, back to back, 15 runs each, `PERF_WIRE=1`, at the machine's load: 15.4 before the first run, 10.2 before the second (8.8 after it). Median ms, payload bytes and wire bytes, start → end; Ash reads and statements the same for every action:

| Action | ms | bytes | wire bytes |
| --- | --- | --- | --- |
| Cell save | 33.3 → 34.6 | 8,277 → 8,277 | 120 → 120 |
| Expanding a row | 9.1 → 7.4 | 3,345 → 3,345 | 171 → 171 |
| Opening a nested table | 56.8 → 58.4 | 33,710 → 33,752 | 4,835 → 4,838 |
| Opening the picker | 34.9 → 36.3 | 34,980 → 35,616 | 3,598 → 3,507 |
| Opening the panel | 22.0 → 22.0 | 4,299 → 4,299 | 85 → 86 |
| Opening the panel inline | 14.3 → 14.9 | 4,240 → 4,240 | 88 → 88 |
| Cell save in a nested table | 19.0 → 19.0 | 3,710 → 3,710 | 51 → 51 |
| Cell save with a nested table open | 30.9 → 33.2 | 8,534 → 8,534 | 123 → 123 |
| Selecting a row | 3.5 → 3.0 | 215 → 215 | 10 → 10 |
| Page change | 71.8 → 67.9 | 152,255 → 153,625 (+0.9 %) | 11,607 → 11,895 (+2.5 %) |

The growth is D23's: a part whose texts depend on what changed sends them again with it. On a page change the pagination's texts (`Previous`, `Next`, `Rows per page`, its name, one `Go to page N` per number) and the selection line's are made of the page and are sent again, where the default kit's constant texts were sent once at mount. The picker's table sends its parts' texts once more as it opens (+636 bytes payload, −91 wire). Times within 20 %.

**Proposed for target.md (owner's yes needed).** §9 stage 7: "`attach/4` refuses nothing the table on the page opens" ticked; S8 lists `pick_request/4`, `add_group_request/4`, `remove_group_request/4` already (amendment 8). No other change. (Made with the drift fixes of 7c, with amendments 15 and 16.)

### Drift fixes of 7c

After the drift check of 7c (owner's decisions of 2026-10-17, all as recommended). Commits `1e79a32`, `354c9ad`, `0a10573`, `be9c8e6`, `0c2e9c1`, `d6329f6`, `c1dd99d`, `49d2b14`, `51fbdae`, `7b67c2c`.

- **A. Texts as attributes.** `Kit.Words` merged the texts into a function component's assigns without `assign/3` (`Map.merge`, unmarked), which leant on LiveView's change tracking beyond what `Phoenix.Component` documents. Now `AshDataTable.Kit.Words` (public) makes them of the part's other assigns (`texts/2`, `messages/2`, `text/2`, `message/2`, `value/2`, `locale/0`), and whoever draws the part passes them as attributes: the drawing, `Kit.Default`'s parts, `Kit.cell/1`, `Kit.editor/1`, a kit's own parts (the demo's `DivKit`), `KitCase`. `Kit.part/1` only draws. A spread (`{Words.of(…)}`) was not taken: LiveView turns change tracking off for a component called with a spread that has dependencies (LV `engine.ex`, "We must disable change tracking when there is a non empty dynamic part"). The latent bug is fixed: a summary cell's text is made of `time_zone` too (`time_zone_test.exs`, a datetime's summary in two zones).
- **B. Nested tables and pickers' tables controlled too** (D17 changed). `controlled:` applies to every table the table shows (`Requests.host?/3` asks no more for the top; the drawing and `Registry.within/3` keep the option). Each table holds one request; a command finds the table that holds its `ref` (`Requests.answer/4`), so the commands keep their signatures. `AshDataTable.requests/1` (every request of the tree, the top's first, parents before children) replaces `request/1`, which would be a part of it. Each request has `table` and `path`, and fields of its kind only: a question `action`, `column`, `value`; a panel `action`, `column`, `title`, `errors`, `fields`; a picker `column`, `resource`, `several?`, `allow_none?` (was `none?`), `current` (was `value`), `chosen`, `title`, `errors`. Maps, not structs: a projection of what is held, documented per kind in `requests/1`. A request ends with `:request_ended` (a new event): answered, given up, taken over, or gone with its table as its row collapses (`Registry.close/2` → `Requests.closing/1`, which lets a waiting cell go). A picker's table opens nothing (`Model`'s chooser), so it holds nothing. `Test.Resource.Part` has a question (`title`), a reference cell (`owner`) and a row action with a panel (`retitle`).
- **C. The wire protocol** is in target.md S6: the push `ash_data_table:answered` `{table, ref, cell, saved, error}` and the reply `{held: true, ref}` (amendment 16).
- **D1.** `pick_request/4` with a map that lacks a field of the primary key (`%{"id" => …}`) raises `ArgumentError` naming it; before, it chose no record.
- **D2. The hook's holds.** The reply `{held: true, ref}` and `answered` carry the request's `ref`; `holds` are kept by it (`waitFor`), a stale `answered` touches nothing, the held branch sets `aria-busy` again, and a patch of the held cell's row leaves it busy (`rehold`, from `sync`) and is not put back over when the answer is no. The picker registers its held cell in the grid. A cell's DOM id is `Present.cell_id/3`.
- **D3. Messages for JS and API kits.** The msgids (the `*_noop` calls) are in `AshDataTable.Messages`; `all/0` (in place of `keys/0`, which a map of more than names made wrong) gives each key its `values`, `msgid` and `msgid_plural`; `mix gettext.extract` leaves the template as it was. A plural key lists `count` (tested). `Text.say/1` and `Messages.of/1` make a `{:once, …}` each text once the same way, by its words (`Text.once/1`).
- **D4.** No part of `Kit.Default` calls `Text` or `Format`: the panel's groups, unions and group items, a failed cell's typed text, a union's value, the related heading's words before and after the record (`heading_before`, `heading_after`) are given. `Parts.Common.said/1` is gone. None had to stay.
- **D5.** `Errors.ash/2` masks every variable of a message about a `sensitive?` field (a column, an input, an attribute, an argument of that name), as `%{value}` may hold what was typed; a whole `count` stays. Mutation-checked (2 of 50 fail).
- **D6. Tests of group AB.** A forged pick of a real person of another organization, and a viewer's forged save of a column with a question, against the demo's tasks (`controlled_policies_test.exs`); a group's path that names no group changes nothing, one of no names raises. Mutation checks: the ref lookup (5 of 8 fail), the cleanup on close (2 of 8), the path guard (1), `let_go` (4), `host?` as it was (8), the hook's `rehold` (1 of 6 browser tests). `Cells.asked/2`'s guard `editable?: true` survives: the model drops a column's `confirm` with its `editable?` (`Model.read_only_if/2`), so no column reaches it without one.
- **D7.** `Attrs.editor_template/3` (an editor's template, `data-confirm` only where the table asks; `Kit.Default` and `DivKit`); `request/1`'s shape per kind (B); `allow_none?`; a group's path takes names as atoms (as the request's fields have them) or strings; `confirm_request/3`'s and `pick_request/4`'s docs (the page shows the question with its chooser); the map's `states/0` is 19; `KitCase` checks every message's shape against `AshDataTable.Messages` (checked once by adding a value: the kit tests fail).

**Tests.** During the work, `mix test --stale` (root and demo) and the browser spec files of each change. At the end: root 1,252 tests, 0 failures (the first run had 1, the architecture test: `text.ex` read `AshDataTable.Messages` at compile time; fixed in `7b67c2c` and run again; load 2.0 and 1.4 at the starts); demo 3,057, 0 failures (load 1.8 at the start, 11.2 at the end); browser 1,017 passed, 0 failed (8.4 min, load 10.3 at the start, 20.7 at the end). No laptop sleep. The markup snapshots did not change.

**Performance (D22, §6).** `demo/perf/baseline.mjs` on `/tasks`, `8fdb34f` in a worktree and `51fbdae`, back to back, 15 runs each, `PERF_WIRE=1`, at the machine's load: 0.84 before the first run, 0.96 before the second (1.22 after it). Median ms, payload bytes and wire bytes, start → end; Ash reads and statements the same for every action:

| Action | ms | bytes | wire bytes |
| --- | --- | --- | --- |
| Cell save | 33.9 → 37.7 | 8,277 → 8,277 | 120 → 120 |
| Expanding a row | 7.4 → 7.6 | 3,345 → 3,345 | 171 → 171 |
| Opening a nested table | 56.9 → 58.5 | 33,752 → 33,712 | 4,838 → 4,826 |
| Opening the picker | 48.9 → 34.4 | 35,616 → 35,616 | 3,507 → 3,507 |
| Opening the panel | 28.1 → 22.7 | 4,299 → 4,299 | 86 → 86 |
| Opening the panel inline | 14.1 → 13.5 | 4,240 → 4,240 | 88 → 88 |
| Cell save in a nested table | 18.2 → 19.0 | 3,710 → 3,710 | 51 → 51 |
| Cell save with a nested table open | 32.8 → 31.6 | 8,534 → 8,534 | 123 → 123 |
| Selecting a row | 4.3 → 3.3 | 215 → 215 | 10 → 10 |
| Page change | 68.0 → 66.1 | 153,625 → 153,625 | 11,897 → 11,895 |

The bytes are neutral, as A expected: LiveView tracks the attributes as it tracked the unmarked texts. Times within 20 %.

### Final review fixes

After the final conformance review (`scratchpad/final-review/verdict.md`) and the owner's decisions of 2026-10-17. Commits from `088fbd9` to the commit of this subsection, on `main` after `1bac00f`.

- **R1** (`c5157e1`). `Live.Page.in_layout/1` and its demo copy put the layout's assigns in with `assign/2` always (it marks only the values that changed); the layout is called without `layout` and `given`, as LiveView's "Dynamic Component Rendering" pops what is not the component's.
- **R2** (`52ab084`). `AshDataTable.Test.listening/2` counts the listeners by Erlang's own process information: each `Listener` puts `{pub_sub, topic}` in its process dictionary once subscribed, and the helper finds them with `Process.list/0` and `Process.info/2`. Mutation-checked: with `Registry.close/2` not stopping the listener, 7 demo tests fail.
- **S4, A1** (`c907d64`). The parts `grid` and `selection_line` are given the running action (`running`, a `Model.Action` or nil), never who started it. No other part is given the actor or a part of it (`Live.Drawing` checked: `caller`, `scope` and `actor` reach no part).
- **S3** (`8afbcbf`). `Sensitive.scrub/1` goes into plain maps and tuples: `:action_ran`'s `result` is masked as `AshDataTable.Event` says. Mutation-checked (the new test fails without it).
- **S2** (`17ff070`). `panel.js` runs nothing of a panel whose action asks when it finds no grid to ask in (`console.error` while the client debug is on), as `dialog.ask` and `picker.js`; `/e2e/markers?panel=1` and `markers.spec.ts` (mutation-checked: fail-open fails the spec).
- **R7, the planned mutation checks.** `Record.fetch/3` reading with `authorize?: false`: 3 of 1,253 root tests fail (a reveal and a save and an emptying of a field hidden from the person), 30 of 3,057 demo tests (`task_edit_test`, `save_error_fields_test`, `attach_test`'s other person, …). `Event.saved/4`, `ran/5` and `created` without `Sensitive.scrub`: 1 root test and 2 demo tests (`events_test`, a save and a create) fail. `selected_records/2` without the scrub: 1 demo test (`commands_test`) fails.
- **B3** (`c6ecff2`). `Event.request/2` (2a) is given the request and plain values (`table`, `path`, `panel`, `picker`, the row's primary key) by `Requests.projections/1` (2b), not `Live.Entry`.
- **N3, R5** (`fd8a0f3`). `attach/4` takes no `mounted?`: `Live.Page` attaches through `AshDataTable.attach_mounted/4` (`@doc false`). The tag's test-only `select` is gone; `/support/select` keeps the tables with nothing to run on a selection with the public tag, and `/e2e/select` and its describe block are gone: rows selectable with nothing to run or choose was a state only that attribute made.
- **B5** (`2706b4c`). The page numbers and a list's item errors are `Kit.Words`' own; it calls no part of `Kit.Default`. `Parts.Common` is no leaf (a cycle of two with `Attrs`, in part 3).
- **S6** (`d2ba1eb`, `54fb701`). An error about a sensitive field inside a value made of fields has its values masked (`Errors.sensitive_within?/2`, asked by `nested_text/4` and `Act.errors/4`). Mutation-checked. The first commit bound the mask as a filter of a comprehension, which dropped every other nested error; the root suite caught it.
- **B2, B1, R4, N5** (`4045708`). `AshDataTable.Ids` (2a, public) makes every id the core and the parts both name; `Present.cell_id/3` is gone; `Kit`'s moduledoc lists them per part; `KitCase` checks the line's button and the nested grid's `aria-labelledby` (mutation-checked: a `DivKit` button of another id fails 8 of 159). `Kit`'s moduledoc has "Kit contract 1", the fields of every struct a part is given; `test/kit_test.exs` compares the list with the structs both ways. A kit's own part gets no `attr` defaults (said in `Kit`'s moduledoc).
- **A2** (`c487447`). The kit's `root/1` draws the root element of every table (D8 and §14 above); the portal's wrappers carry markers only (`data-ash-data-table-portal`, `data-ash-data-table-view`), pinned and sized by `Kit.Default`'s root rules, and the portal takes the kit's `class(:portal, …)`. `data-pin` is gone. The markup snapshots change (not committed; the review is in the scratchpad's `final-fix/snapshot-review.md`).
- **R3** (`ec7525e`). Not changed; proposed as an owner-kept exception, commented at each place in the hooks. LiveView 1.2.12's guide "Bindings" documents `phx-update="ignore"` as a server-rendered attribute on a container with a unique id ("Updates from the server to the element's content and attributes are ignored, except for data attributes"; "a unique DOM ID must always be set in the container"), used "to integrate with another JS library"; "JavaScript interoperability" says nothing of switching it from a hook. The documented way would be an empty container with that attribute and an id in every editable cell, which the editor goes into. Measured against `/tasks`: 14 editable columns × 25 rows, about 55 bytes of dynamic id each, some 19 kB more on a page change (153.6 kB today, about +12 %) and some 0.8 kB more on a cell save (8.3 kB, about +9 %), against D3's 5 %; and the cell's own content and the attributes the hook sets on it (`aria-busy`, the held value) would be patched under the editor, which needs per-cell `JS.ignore_attributes/1` (more bytes) or a kit's CSS to hide them. So not taken; the owner decides.
- **R6, R9, R11, R13, N1** (`088fbd9`). The installer puts `[:table, :tables]` and `[:table]` first in Spark's section order (tested); `primary_read_warning?: false` on `test/support/given.ex`'s two resources; `Resource.Info.live?/1` gone (`table_live?/1`); `@report_only` gone; the hint guard sees `max_lines:`, `sticky_label?:` and the atoms, the read guard `Ash.read_first`.
- **B4** (`764adb3`). `request/1` → `requests/1` in `lib/ash_data_table.ex`.
- **S1** (docs only, owner 2026-10-17). Not enforced on the server: target §1.5, `attach/4`'s doc, `Requests`, the D17 table and S6 say that in controlled mode the host shows the question, the browser can still send an event as if confirmed, and a question is no safety check.
- **R12.** Allowed (§11).
- **Amendments** of the verdict's (d) made in target.md (§1.5, S3, S6, S7, S8, S19, §4.3–4.7, §5.5, §6, §7.4, Q14, §9 stage 7 ticked but the final review), in stage 6's drift fix 8 (the process dictionary), and in D8, D17 and §14 here.

### Browser-side simplification

After the critique of the browser side and its judge's verdict (`scratchpad/js-review/verdict.md`), and the owner's decisions of 2026-10-17: "avoid floating stuff if possible in a state of the art way and for editing multivalue stuff like enums also use the side modal concept. keep it simple"; plurals through Gettext. Commits `2096a66`, `6ce670f`, `c800f84`, `2797328`, `18a21ad` and the commit of this subsection, on `main` after `b7795b1`. JS of the hooks: 4,602 lines → 4,094 (`wc -l assets/js/**/*.js`); `arrays.js`, `choices.js` and `failure.js` are gone, what stayed of `arrays.js` (a component's editor, saving a cell) is `grid/saving.js`.

- **Plurals on the server** (R2, R2b, R3-plural; `6ce670f`). The selection line is drawn from what the server holds (`Core.Selection`, `whole_page?/1`): the count in its live region with `dngettext` (`selected`, plural), its buttons `hidden` while nothing is selected, "all that match" while the whole page is and more match. The hook paints the rows and their boxes, and moves focus when a button it used goes. `values_chosen` is plural. The Columns button carries its phrases for every number from 1 to the number of columns (`data-text-hidden`, `-filtered`, `-sorted`, JSON lists), each box what is read out of its column (`data-say-hidden`, `-shown`); the hook takes one. No `{n}` or `{column}` is put in by a hook; the `{details}` of `columns_with` (the parts joined with a comma) and the `{n}` of a list field's row names (a place, no count) stay.
- **Multi-value cells in the side panel** (`c800f84`). A cell of an array (`:choices`, `:list`) opens the side panel (`edit`, `Model.in_panel?/1`) on Enter, F2, a double click or a typed key, with the column's attribute as the one field of a form of its update action; Save runs `Operation.submit/1` (`Edit.put/7`), closing gives the focus back to the cell. The in-cell list editor, its template, the cell's array `data-value` and `data-invalid`, a cell failure's `places`, a save of a list (`Intent`, `Edit.save/5`, `Edit.typed?/2`) and the list part's `place` are gone. The panel's list field keeps its client-side rows (`panel.js`). Mutation-checked: `Edit.put/7` given the raw params fails 86 demo tests, the new "a panel of one array saves that one" among them.
- **Nothing floats but the Columns list** (R5, R11 as the owner decided; `2797328`). No element is placed by a scroll listener: only the scrollbar at the window's bottom edge follows the window (`PLACE`). A failed cell's message stands in the cell under its value (the row grows); the counter of a text stands under the cell's editor; a cell that cuts its text off shows all of it in place (a button the hook puts into the cell, `data-whole`, `aria-expanded`, for the eye, and Shift+Enter; Escape cuts it off again; the `whole_text` part is gone, `Kit.parts/0` has 32). Columns is the browser's popover (`popover="auto"`, `popovertarget`), placed under its button by CSS anchor positioning (`anchor-name` on the button, `position-anchor` and `position-area` on the list) and centred where a browser has none: no hand-written open, close, click outside, Escape or `aria-expanded`; the hook closes it when focus leaves. Not in Firefox before its anchor positioning: there it opens in the middle of the window.
- **"Is any of" in the side panel** (replaces R4; `2797328`). The filter's button (`filter_values`, with its column and operator, `Attrs.filter_values/4`) opens the table's panel (`kind: :filter`, `Model.filter_input/1`) with a box per value, a form of its own; Apply filters that column (`Reading.filtered/2`, `State.filter_column/4`), Cancel filters nothing. The values that apply are hidden inputs of the filter row's form. In controlled mode it is a `:panel` request without an action (`action` nil, `column`, one `:choices` field), answered with `submit_request/4` (tested). Mutation-checked: the panel taking any column and operator fails `filter_values_test`.
- **The question inside a modal panel or picker** (R1-clone; `2797328`). Where questions are inline, the drawing draws the question once more inside a modal panel and a modal picker (`confirm`'s `place`: `ID-dialog-in-panel`, `ID-dialog-in-picker`, `phx-update="ignore"`); the hook asks there (`placeOf`), with no round trip. The clone, its ids and the page-wide observer are gone; a panel or picker that goes answers its question as Cancel (`goneWith`).
- **Panel buttons and picker** (R6, R7; `2797328`). Add and remove group (`JS.push` with the path, which a `phx-value-*` cannot hold), unpick and clear (`phx-value-*`) send their events with `phx-click`; the server says where focus goes (`ash_data_table:focus`, which the panel's hook hears). The picker sends `picked` without rows: the server takes the row its table holds as selected (`Core.Selection.in_view/1`; all of it where several are chosen), and draws "Choose"'s `aria-disabled` (`takes?`). A hand-made `picked` names nothing any more; a row that is no row of the picker's page is not there to be taken.
- **The cell editor's `phx-update` switch** (owner-kept, `18a21ad`): only the single-value cell editor switches it now (§11, with the measured cost of the documented way: a page change +17.9 % payload and +17.8 % on the wire, a cell save +13.8 %, 116 → 130 wire bytes).
- **Comments** (verdict d; `2096a66`): `sender.js` and `transport/live_view.js` say that LiveView documents patches held for an input, a button and a form in flight, and that the lock of a hook's own element is observed, not documented.
- **Kit contract 1** (public changes): parts `whole_text` gone; `selection_line` given `selected`, `all?`, `whole_page?`; `confirm` given `place`; `picker` given `takes?`; `count` without `floats?`; `list` without `place`; `filter`'s button through `Attrs.filter_values/4`; `Present.Cell.failure` without `places`; `Present.Panel.kind` may be `:filter`. `Attrs`: `selection/2`, `selection_controls/2`, `select_all/2`, `selected/1` without `phx-update`, `grid/6` (`data-show-whole`, `data-show-less`), `columns_button/2`, `columns/3`, `confirm/3`, `asked_in/1`, `take/3`, `unpick/4`, `clear_field/3`, `add_group/3`, `remove_group/3`, `filter_values/4`; `whole/1` and `failure/0` gone. Markers: `[data-whole]` new; `[data-choices-button]`, `[data-choices]`, `[data-add-group]`, `[data-unpick]`, `[data-clear-field]` gone. Messages: `show_whole`, `show_less`, `apply` new; `selected`, `values_chosen`, `columns_hidden`, `columns_filtered`, `columns_sorted` plural. `KitCase`: states `list_panel` and the filter's panel on the way to `filtered`, the question's place, the server-drawn count.
