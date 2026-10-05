# How to build an editable grid in LiveView without npm

Research for issue #7 (part of map #2). Researched 2026-10-05.

Versions read: Phoenix LiveView 1.2.12 (latest stable on Hex) and `main` (1.3.0-dev), Phoenix 1.8.15, Backpex 0.21.0, ash_admin 1.3.2, Phoenix LiveDashboard 0.9.1, Cinder 0.17.0. Library source was read from the default branch of each GitHub repo on the research date.

Every claim carries a source. Claims marked **Unverified** are inferences or secondary reports that were not confirmed against a primary source or by running code.

## Answer in brief

- **Rendering:** keep the current page of records in a plain assign and render rows and cells with `:for` plus `:key` (LiveView 1.1+). This gives per-cell diffs without one LiveComponent per cell and without streams. Streams are the fallback when server memory matters more than diff size; they are a poor fit for cell edits because the server keeps no row state.
- **Client behaviour:** one small JS hook on the grid root handles arrow-key navigation, roving `tabindex`, entering and leaving edit mode, and pushing the save event. Navigation never goes to the server.
- **Editing:** only the active cell renders an input. Save on Enter or blur through one event carrying row id, column and value; Escape cancels. LiveView never overwrites the value of a focused input, which protects typing from in-flight patches.
- **Focus across patches:** LiveView restores focus only for textual inputs and selects. Focus on a non-input cell (`<td tabindex="0">`) is kept only as long as the element survives the patch, so cells need stable DOM ids and the hook must re-apply the roving `tabindex` and focus in `updated()`.
- **Assets without npm:** ship the hook as a colocated hook, or as a prebuilt ES module in the package, imported by the host's existing esbuild through `NODE_PATH` (which already includes `deps`). CSS needs one `@source` line in the host's `app.css` so Tailwind scans the package. None of this needs Node or npm.
- **ARIA:** `role="grid"`, `row`, `columnheader`, `gridcell`; arrow keys, Home, End, Ctrl+Home, Ctrl+End, Page Up and Page Down navigate; Enter or F2 enters editing, Escape leaves it; `aria-rowcount` and `aria-rowindex` are required because pagination keeps most rows out of the DOM.
- **No packaged solution exists:** no Hex package was found that provides an Ash-aware editable grid with keyboard navigation. Backpex is the closest prior art for inline editing and has no grid keyboard model.

## 1. Prior art: Backpex index editing

Sources: [index-edit guide](https://github.com/naymspace/backpex/blob/main/guides/fields/index-edit.md), [`lib/backpex/field.ex`](https://github.com/naymspace/backpex/blob/main/lib/backpex/field.ex), [`lib/backpex/fields/text.ex`](https://github.com/naymspace/backpex/blob/main/lib/backpex/fields/text.ex), [`lib/backpex/html/resource.ex`](https://github.com/naymspace/backpex/blob/main/lib/backpex/html/resource.ex), [`resource_index_table.html.heex`](https://github.com/naymspace/backpex/blob/main/lib/backpex/html/resource/resource_index_table.html.heex).

- A field opts in with `index_editable: true` (boolean or a function of the assigns). Supported fields: BelongsTo, Date, DateTime, Email, Number, Select, Text. A custom field adds support by defining `render_index_form/1`.
- **One LiveComponent per cell, not per row.** `resource_field/1` renders `<.live_component module={@field_options.module} type={:index} …>` for every field of every item. The field module is the LiveComponent; its `render(%{type: :index})` chooses `render_index_form/1` or the read-only `render_value/1`. The guide's wording is "the index form of every row as its own live component".
- The component receives almost all parent assigns: `{Map.drop(assigns, lv_reserved_assigns())}`. LiveView's own docs warn against exactly this (see section 3).
- **Every editable cell is always an input.** Each cell renders its own `<.form>` holding one input, styled as a ghost input until hovered. There is no separate display state and edit state.
- **Save happens on change, not on Enter or blur.** The form has `phx-change="update-field"` and `phx-submit="update-field"` with `phx-debounce="100"` on the text input, targeted at the cell component (`phx-target={@myself}`).
- `Backpex.Field.handle_index_editable/3` calls `Backpex.Resource.update/6` with a one-key change map, then sets `:valid` on the component. An invalid value turns the input red (`input-error bg-error/10`); the error text is hidden (`hide_errors`).
- **No optimistic update.** The cell re-renders from the server result. Other cells of the row refresh only through the `on_item_updated` callback and the item event that follows.
- **N+1 queries are a known cost of this design.** The guide states that data loaded in `render_index_form/1` "runs one query per row on every render of the index view"; the `index_assigns/3` callback exists to load such data once for all rows.
- Items live in a plain `:items` assign, not a stream (`assign(:items, items)` in [`live_resource/index.ex`](https://github.com/naymspace/backpex/blob/main/lib/backpex/live_resource/index.ex)). Rows are rendered with `:for` without `:key`.
- **No grid semantics and no cell navigation.** The table is a plain `<table class="table">` with no `role="grid"`, no arrow-key handling and no roving `tabindex`. Keyboard users move through cells with Tab only.

Takeaway: Backpex proves inline editing with per-cell LiveComponents works at admin-page sizes, and shows its costs (state per cell, N+1 risk, always-on inputs). It does not answer keyboard navigation or the save-on-Enter-or-blur contract.

## 2. Other existing approaches

- **Cinder 0.17.0** renders read-only tables only. Its `lib/` contains no `phx-hook`, no stream and no inline editing; rows come from a plain `@data` assign ([`renderers/table.ex`](https://github.com/sevenseacat/cinder/blob/main/lib/cinder/renderers/table.ex)). It ships no JavaScript at all.
- **AG Grid through a hook** ([Curiosum article](https://curiosum.com/blog/interactive-data-tables-in-phoenix-liveview), secondary source): installs with `npm install ag-grid-community`, uses `phx-hook` plus `phx-update="ignore"`, and sends the grid configuration with `push_event`. The article does not cover cell editing. This violates the no-npm constraint unless the library is vendored, and it moves rendering out of LiveView.
- **LiveVue 1.2.3** lists "Node.js installed" as a prerequisite ([installation guide](https://live-vue.hexdocs.pm/installation.html)). **LiveSvelte 0.18.0** needs `node` for server-side rendering and replaces esbuild with Vite ([readme](https://live-svelte.hexdocs.pm/readme.html)). Both are ruled out by the no-npm constraint.
- **Elixir Forum thread** "[Editable tabular data / grid / table in Phoenix LiveView?](https://elixirforum.com/t/editable-tabular-data-grid-table-in-phoenix-liveview/72576)" (secondary source, community reports): the original poster reported losing input focus when a cell edit was applied with `stream_insert`, abandoned streams and moved to one LiveComponent per row; another reply recommended keyed `:for` over both. **Unverified** by running code; consistent with the mechanics in sections 3 and 4.
- No Hex package was found that provides an Ash-aware editable grid. **Unverified** as a negative: the search covered Hex-hosted packages known to the scout and one web search, not all of Hex.

## 3. Rendering strategies in LiveView

Sources: [LiveView 1.1 changelog, "Change tracking in comprehensions"](https://github.com/phoenixframework/phoenix_live_view/blob/v1.1/CHANGELOG.md), [`Phoenix.Component` docs on `:key`](https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_component.ex), [`Phoenix.LiveView.stream/4` docs](https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_live_view.ex), [`Phoenix.LiveComponent` docs, "Cost of live components"](https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_live_component.ex).

| Strategy | Server memory | Diff when one cell changes | Notes |
| --- | --- | --- | --- |
| `:for` with `:key` over an assign | Page of records plus change-tracking data | Only the changed parts of that entry | Default since 1.1; "we recommend to use a `:key` whenever possible" |
| Stream | None for the items | All dynamic parts of the updated row | Server has no row state to diff against |
| LiveComponent per row or per cell | All assigns of every component | Only the changed parts of that component | Needs a module; N+1 risk in `update/2` unless `update_many/1` is used |

Facts from the sources:

- Before 1.1, changing one item in a `:for` re-sent the dynamic parts of every item. Since 1.1, comprehensions are change tracked by default, by index; with `:key`, by key, so moved items only send their new position.
- The changelog compares the options directly: streams "are not kept in memory on the server", but "if you update an item in a stream, all the dynamic parts of the updated item are sent again". LiveComponents "allow for more granular diffs … but require more memory on the server". Keyed comprehensions come "with a slightly increased memory footprint. If memory is a concern, you should think about using streams."
- `:key` has no effect inside a stream, and is not supported on slots.
- Stream items "are temporary and freed from socket state immediately after the `render/1` function is invoked". A stream container needs `phx-update="stream"` and a DOM id on the container and on every child.
- LiveComponent cost: "all of the components' assigns are kept in memory". The docs advise against passing all parent assigns into a component and against using LiveComponents "to provide abstract DOM components".

Consequence for a paginated grid: the server already needs the current page in memory to build a changeset or Ash action input for an edit and to show the old value on cancel. That removes the main benefit of streams, and keyed comprehensions give the per-cell diff that streams cannot. Streams remain the right tool for a later unpaginated or virtualised slice.

## 4. Focus and input state across patches

Sources: [form bindings guide, "JavaScript client specifics"](https://github.com/phoenixframework/phoenix_live_view/blob/main/guides/client/form-bindings.md), [bindings guide, "DOM patching"](https://github.com/phoenixframework/phoenix_live_view/blob/main/guides/client/bindings.md), [`dom_patch.ts`](https://github.com/phoenixframework/phoenix_live_view/blob/main/assets/js/phoenix_live_view/dom_patch.ts), [`dom.ts`](https://github.com/phoenixframework/phoenix_live_view/blob/main/assets/js/phoenix_live_view/dom.ts), [JS interop guide](https://github.com/phoenixframework/phoenix_live_view/blob/main/guides/client/js-interop.md).

- "For any given input with focus, LiveView will never overwrite the input's current value, even if it deviates from the server's rendered updates." An input can opt out with `phx-patch-focused` (added in the 1.2 series).
- After every patch the client calls `DOM.restoreFocus(focused, selectionStart, selectionEnd)`. That function re-focuses **only** `<select>` elements and textual inputs, and restores the caret. For any other element, including a `<td tabindex="0">`, it returns without doing anything.
- Therefore focus on a non-input cell survives a patch only if the same DOM element survives. Stable ids on rows and cells (and `:key` on the comprehension) are what make that true. When a cell switches between display and edit markup, or when the page changes, the hook must set focus itself.
- A hook's `updated()` runs after the element was patched, and `handleEvent` callbacks "are invoked after the page is updated". Both are safe places to re-apply `tabindex` and call `focus()`.
- Attributes set on the client are overwritten by the next patch unless protected. Three documented ways to protect them: `JS.ignore_attributes/1` (1.1+, typically from `phx-mounted`), the `dom.onBeforeElUpdated` LiveSocket option (host-level, not usable by a library on its own), or re-applying them in the hook's `updated()`.
- `phx-update="ignore"` freezes content and attributes of an element except `data-*` attributes. It suits a fully client-rendered grid such as AG Grid, not a server-rendered one.
- `phx-hook` requires a unique DOM id on the element.
- `phx-keydown` and `phx-keyup` "are not supported on inputs". Key handling inside an editing cell (Enter, Escape, Tab) therefore has to live in a hook or in the form's `phx-submit`.
- On `phx-submit`, the form's inputs are set to `readonly` until the server acknowledges, then "the last input with focus is restored (unless another input has received focus)".
- `JS.focus/1`, `JS.focus_first/1`, `JS.push_focus/1` and `JS.pop_focus/1` exist as server-declared commands. Since 1.2 a `%JS{}` can be JSON-encoded and sent in `push_event`, then run with `this.js().execJS(…)`.

## 5. Keyboard navigation and where it runs

- Arrow-key navigation needs no server knowledge: all cells of the current page are in the DOM. Running it in the hook avoids one round trip per key press. The LiveView docs make the same point for key events in general: `phx-keydown` is throttled only for key repeats, and server-bound key events are meant for cases where the server must know.
- The [APG keyboard interface practice](https://www.w3.org/WAI/ARIA/apg/practices/keyboard-interface/) describes two focus techniques for composite widgets. Roving `tabindex`: one element has `tabindex="0"`, all others `tabindex="-1"`; on navigation, swap the values and call `element.focus()`. `aria-activedescendant`: focus stays on the container, which points at the active child by id. The practice names one advantage of roving `tabindex`: "the user agent will scroll the newly focused element into view."
- Roving `tabindex` conflicts with server patches, because the server render does not know which cell is active and would reset the attributes. `aria-activedescendant` keeps all client-owned state in one attribute on the grid root, which is easier to protect with `JS.ignore_attributes`. **Unverified** which of the two behaves better with LiveView patches and with screen readers; this is a prototype question.

## 6. Optimistic updates

Source: [syncing changes guide](https://github.com/phoenixframework/phoenix_live_view/blob/main/guides/client/syncing-changes.md).

- LiveView has no client-side data model. Its documented optimistic tools are CSS loading classes (`phx-click-loading`, `phx-change-loading`, `phx-submit-loading`, `phx-blur-loading`, …) that stay until the event is acknowledged, the `loading:` option of `JS.push` to mark another element as loading, and JS commands that change the DOM immediately.
- For a cell edit this gives a cheap form of optimism for free: the typed value stays visible in the focused input while the event is in flight, and a loading class can mark the cell as saving.
- A true optimistic write (show the new value in the display cell before the server confirms, roll back on error) would have to be written in the hook. **Unverified** whether it is needed; with a local server round trip the built-in behaviour may be enough.
- Backpex does no optimistic update (section 1).

## 7. Performance limits by row and column count

No primary source publishes row or column limits for LiveView tables. The facts below are structural; the numbers are arithmetic, not measurements.

- Cell count is rows times columns. 50 rows by 12 columns is 600 cells; 100 by 20 is 2,000; 200 by 30 is 6,000.
- With one LiveComponent per cell (the Backpex model) every cell holds its own assigns on the server and adds a component id to the diff. With keyed comprehensions the server holds one copy of the page plus change-tracking data.
- If every editable cell always renders a form and an input (the Backpex model), the DOM carries one form and one input per editable cell. Rendering an input only in the active cell keeps the DOM at one element per cell.
- Initial render and page change send every cell once, whatever the strategy. Static parts of a comprehension are sent once regardless of the item count ([assigns and HEEx guide](https://github.com/phoenixframework/phoenix_live_view/blob/main/guides/server/assigns-eex.md)).
- A cell edit with keyed comprehensions sends only the changed parts of one entry. With a stream it sends the whole row.
- **Unverified:** the page size at which a server-rendered grid becomes sluggish in the browser. The prototype should measure 25, 100 and 500 rows at 10 and 30 columns: payload size of first render, payload size of one cell edit, and patch time reported by `liveSocket.enableProfiling()`.

## 8. How a Hex package ships JS and CSS to a host app

### What existing packages do

| Package | JavaScript | CSS | Host setup |
| --- | --- | --- | --- |
| Phoenix LiveDashboard 0.9.1 | Prebuilt `dist/js/app.js` read at compile time, concatenated with the Phoenix and LiveView client files, served by its own plug | Prebuilt `dist/css/app.css`, same plug | Router macro only |
| ash_admin 1.3.2 | Prebuilt `priv/static/assets/app.js` read at compile time and inlined in its own root layout with a CSP nonce | Prebuilt `app.css`, inlined the same way | Router macro only |
| Backpex 0.21.0 | Prebuilt `priv/static/js/backpex.esm.js` plus `package.json`; host writes `import { Hooks as BackpexHooks } from 'backpex'` | None shipped; host Tailwind scans the dependency with `@source "../../deps/backpex/**/*.*ex"` | Edit `app.js` and `app.css`, or run the Igniter installer |
| Cinder 0.17.0 | None | `priv/cinder.css` containing only `@source` lines; host adds `@import "../../deps/cinder/priv/cinder.css"` | `mix cinder.install` edits `app.css` |

Sources: [LiveDashboard `assets.ex`](https://github.com/phoenixframework/phoenix_live_dashboard/blob/main/lib/phoenix/live_dashboard/controllers/assets.ex), [ash_admin `layouts.ex`](https://github.com/ash-project/ash_admin/blob/main/lib/ash_admin/components/layouts.ex), [Backpex installation guide](https://github.com/naymspace/backpex/blob/main/guides/get_started/installation.md) and [`package.json`](https://github.com/naymspace/backpex/blob/main/package.json), [Cinder `priv/cinder.css`](https://github.com/sevenseacat/cinder/blob/main/priv/cinder.css) and [theming guide](https://github.com/sevenseacat/cinder/blob/main/docs/theming.md).

The LiveDashboard and ash_admin model works because they own the whole page: their own layout, their own `LiveSocket`, their own bundle. An embeddable table lives inside the host's LiveView and the host's `LiveSocket`, so its hooks must be registered there. That rules this model out for the core table (it stays available for the later mounted all-resources UI).

Backpex and Cinder show the model for embedded components: nothing is built on the host by npm. The host's existing esbuild and Tailwind binaries (Hex packages `esbuild` and `tailwind`, no Node) pick up files from `deps/`.

### Options for ash_table's hook

1. **Colocated hook, extracted (LiveView 1.1+, Phoenix 1.8+).** The hook is written in a `<script :type={Phoenix.LiveView.ColocatedHook} name=".Grid">` inside the component. At compile time it is written to `_build/$MIX_ENV/phoenix-colocated/<app>/…`, and a manifest `index.js` exporting `hooks` is generated per application. The [ColocatedJS docs](https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_live_view/colocated_js.ex) state that each application, including dependencies, gets its own folder, and that "simple hooks or code snippets that do not require access to third-party libraries can also be directly imported into your own bundle. If a library requires this, it should be stated in its documentation." Host change: `import {hooks as ashTableHooks} from "phoenix-colocated/ash_table"` and spread it into `hooks`. New Phoenix apps already resolve `phoenix-colocated` through `NODE_PATH`. The manifest is written by the `:phoenix_live_view` Mix compiler ([`compile/phoenix_live_view.ex`](https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/mix/tasks/compile/phoenix_live_view.ex), [`colocated_assets.ex`](https://github.com/phoenixframework/phoenix_live_view/blob/main/lib/phoenix_live_view/colocated_assets.ex)), so ash_table's own `mix.exs` would need `compilers: [:phoenix_live_view] ++ Mix.compilers()`. **Unverified:** that the manifest is generated when ash_table is compiled as a dependency of a host app; no published library was found doing this, and it was not run.
2. **Colocated hook with `runtime`.** The script stays in the rendered HTML and registers the hook in the browser; no bundler and no host `app.js` change. Documented limits: the code is not processed by a bundler, and under a Content Security Policy the script needs a nonce passed as an attribute. LiveDashboard documents this for custom pages. This is the only option with zero host setup; the cost is a CSP nonce the declarative table would need to receive.
3. **Prebuilt ES module plus `package.json` (the Backpex and LiveView model).** ash_table commits `priv/static/ash_table.esm.js` and a `package.json` whose `module`/`main` point at it, and lists both in the Hex `files`. The host writes `import {hooks} from "ash_table"`; esbuild resolves it through `NODE_PATH` containing `deps`. For a hook without third-party imports the source file can be the shipped file, so ash_table itself needs no build step either. Works on LiveView versions before 1.1.

All three need no npm on the host. Options 1 and 3 need one import line in `app.js`, which an Igniter installer can add (Backpex does this).

### CSS

- A new Phoenix 1.8 app uses Tailwind 4 with `@import "tailwindcss" source(none)` and explicit `@source` lines, with daisyUI loaded as a vendored Tailwind plugin ([`app.css.eex`](https://github.com/phoenixframework/phoenix/blob/v1.8/installer/templates/phx_assets/app.css.eex)). Because of `source(none)`, classes used only inside `deps/ash_table` are **not** generated unless the host adds a source line.
- Host change: one line, either `@source "../../deps/ash_table/lib";` (Backpex style) or `@import "../../deps/ash_table/priv/ash_table.css";` where that file holds the `@source` lines (Cinder style). An installer can add it.
- Since ash_table's default look is daisyUI classes, it needs no CSS of its own beyond this. LiveView 1.2 adds colocated CSS for rules that Tailwind utilities cannot express; the generated `app.css` already imports `phoenix-colocated/<app>/colocated.css` for the host's own app.
- Tailwind only finds class names that appear literally in source. Classes built by string interpolation in the table's components would be missed.

## 9. The ARIA grid keyboard contract

Sources: [APG grid pattern](https://www.w3.org/WAI/ARIA/apg/patterns/grid/), [APG grid and table properties](https://www.w3.org/WAI/ARIA/apg/practices/grid-and-table-properties/). The APG pages were read through a fetch tool that summarises; wording below follows what it returned and should be checked against the page before being quoted in the spec.

### Navigation mode (data grid)

| Key | Behaviour |
| --- | --- |
| Right / Left Arrow | Move focus one cell; at the row edge, focus does not move |
| Down / Up Arrow | Move focus one cell; at the column edge, focus does not move |
| Home / End | First / last cell of the current row |
| Ctrl+Home / Ctrl+End | First cell of the first row / last cell of the last row |
| Page Down / Page Up | Move focus an author-determined number of rows |

Navigation does not wrap. For a grid that loads rows dynamically, Ctrl+End "may move focus to the last row in the DOM rather than the last available row in the back-end data". The pattern does not define what arrow keys do at a page boundary of a paginated grid.

### Entering and leaving a cell

| Key | Behaviour |
| --- | --- |
| Enter | Disables grid navigation and places focus in the cell's input. In a single-line text field, a second Enter "may either restore grid navigation functions or move focus to an input field in a neighboring cell" |
| F2 | Places focus in the input; a second F2 restores grid navigation |
| Alphanumeric key | Places focus in the input (typing starts editing) |
| Escape | Restores grid navigation; "if content was being edited, it may also undo edits" |
| Tab / Shift+Tab (while editing) | Moves focus to the next / previous widget in the grid |
| Arrow keys (while editing) | Passed to the focused widget |

The grid as a whole is one tab stop. The project's contract "save on Enter or blur" fits: Enter commits and restores navigation, Escape cancels, and a blur caused by Tab or a click commits.

### Roles and properties

- Container `role="grid"` with `aria-label` or `aria-labelledby`. Rows `role="row"`. Cells `columnheader`, `rowheader` or `gridcell`. These roles can be placed on native `<table>`, `<tr>`, `<th>` and `<td>` elements.
- `aria-sort` on the header cell of the sorted column; values `ascending`, `descending`, `other`, `none`. The practice sees limited value in marking more than one column.
- `aria-readonly="true"` on cells that cannot be edited in a grid that offers editing. A grid without any editing must not carry `aria-readonly` at all.
- `aria-selected="true"` on selected cells or rows, if selection is supported.
- Pagination means not all rows are in the DOM, so: `aria-rowcount` on the grid with the total row count, or `-1` if unknown; `aria-rowindex` on every row including header rows, 1-based and increasing. `aria-colcount` and `aria-colindex` are needed only when columns are hidden or missing from the DOM.
- Focus placement: the pattern recommends focusing the cell itself when it holds text, and focusing the inner widget directly when the cell holds a single widget that does not use arrow keys (checkbox, button, link). A boolean column rendered as a checkbox therefore takes focus directly and toggles with Space, with no edit mode.

## 10. Recommended technique set for the prototype

1. A native `<table>` with `role="grid"`, rendered by function components from a plain `@rows` assign with `:for` and `:key`, stable ids on the grid, each row and each cell.
2. One hook on the grid root: key handling, active-cell tracking, focus management, entering and leaving edit mode, pushing `save` with row id, column and value.
3. Edit state kept on the server as a single `{row_id, column}` assign so only one cell renders an input, or kept entirely in the hook with a hidden input per cell. The prototype should compare both; the first costs a round trip to open a cell, the second costs DOM size.
4. Save on Enter or blur through one event; Escape cancels in the hook without a server call. A loading class marks the cell while the event is in flight; a failed action leaves the cell in edit mode with `aria-invalid` and the error.
5. Assets: a colocated hook or a single hand-written ES module, with an Igniter installer adding one import line to `app.js` and one `@source` line to `app.css`.

## 11. Open questions surfaced

- Does a colocated hook in a dependency produce a usable `phoenix-colocated/ash_table` manifest in the host build? Needs a two-project test.
- Roving `tabindex` or `aria-activedescendant`: which survives LiveView patches with less code, and how do screen readers treat each?
- Should the edit state (which cell is open) live on the server or in the hook?
- What happens at a page boundary: do Down Arrow on the last row and Page Down load the next page, or stop?
- Which minimum LiveView version does ash_table require? Keyed comprehensions and colocated hooks need 1.1; JSON-encoded JS commands, colocated CSS and `phx-patch-focused` need 1.2.
- How is a CSP nonce passed to a declarative table, if the runtime-hook route is chosen?
- Which page sizes stay responsive? Needs the measurements listed in section 7.
- How are validation errors of an Ash action shown inside a cell, and announced to assistive technology?
- How do cell types whose widgets use arrow keys themselves (select, date picker, multi-line text) fit the Enter and Escape contract?
