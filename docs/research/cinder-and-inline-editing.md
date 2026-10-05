# Cinder and inline editing

Research for issue #6, "Whether Cinder can carry inline editing". Part of the map #2.

Researched 2026-10-05.

## Question

How is Cinder built internally, what are its supported extension points, and could inline cell editing and a manifest-driven, HEEx-free declaration be built on top of it as a dependency? Confirm or overturn the working assumption that `ash_table` stays independent of Cinder and only borrows ideas.

## Answer in brief

**Stay independent. The working assumption is confirmed.**

Cinder is a read-side collection component: filter, sort, paginate, select, bulk-act. It has no editing concept, no JS hooks, no keyboard navigation and no ARIA grid markup, and none of these are on its issue tracker. The parts `ash_table` would have to change to add them (the table markup, the LiveComponent's event handling, the row state) are exactly the parts Cinder does not expose as extension points. A HEEx-free read-only table could be layered on Cinder; an editable ARIA grid could not without forking or fighting it.

The reasons, strongest first:

1. **The cell and row markup is closed.** `Cinder.Renderers.Table` emits a plain `<table>` with no `role`, no `tabindex`, no cell ids and no hook. The renderer is picked by a private function from three hard-coded layouts. There is no supported way to supply another one.
2. **The LiveComponent owns the rows and accepts no foreign events.** Edit state (active cell, draft value, validation error, saving) has no home in it. It has no catch-all `handle_event`, so an unknown event targeted at it crashes it. The only supported write into its rows is `Cinder.Update`, an in-memory patch by closure that skips calculations and aggregates.
3. **It reads resource shape from `Ash.Resource.Info` directly, in about 45 places, almost all in two internal modules.** It does not use Spark or `Ash.Info.Manifest`. The standing preference that the manifest is the only source of resource shape cannot hold for a dependency built this way.
4. **It is pre-1.0 and moving fast.** Versions 0.14, 0.15 and 0.16 each shipped breaking changes within ten weeks in 2026. The internals `ash_table` would lean on are documented as "Internal" or not documented.

What Cinder does well is worth copying. See [Ideas worth borrowing](#ideas-worth-borrowing).

## Sources

All claims about Cinder's code were read from a clone of `https://github.com/sevenseacat/cinder` at commit `dd46eff524d78ad94bbcf482f1e0406055dd425f` (main, 2026-10-03). That is a few commits after tag `v0.17.0` (`1aef388`), so it includes two unreleased features (`initial_load={:sync}` and a `count` in `on_query_change`). File references below are relative to that commit and can be opened at:

`https://github.com/sevenseacat/cinder/blob/dd46eff524d78ad94bbcf482f1e0406055dd425f/<path>`

Other primary sources:

- Hex package metadata, `https://hex.pm/api/packages/cinder`: latest stable 0.17.0, published 2026-08-07, first release 2025-06-15, about 250,000 downloads in total.
- GitHub repository metadata and issues, read with `gh`: 127 stars, MIT, Discussions disabled, 22 open issues.
- The guides under `docs/` in the repository. `mix.exs` lists them as the ExDoc extras, so they are the source of the hexdocs pages. The rendered site at `https://cinder.hexdocs.pm/` was not fetched separately.
- `CHANGELOG.md` in the repository.

The starting hints from the earlier scout were all confirmed: hex `cinder` 0.17.0 by sevenseacat (Rebecca Le), function components around one shared `Cinder.LiveComponent`, not a Spark extension, `Cinder.Filter` behaviour and registry, `Cinder.UrlSync`, `Cinder.Update`, a macro-based theme DSL, no inline editing.

## How Cinder is built

### Shape and dependencies

`mix.exs` requires `ash ~> 3.0`, `ash_phoenix ~> 2.3`, `phoenix_live_view ~> 1.0`, `gettext ~> 1.0.0` and Elixir `~> 1.17`. `ash_phoenix` is used only for pagination helpers (`AshPhoenix.LiveView.page_number/1`, `prev_page?/1`, `next_page?/1` in `lib/cinder/renderers/pagination.ex`). `AshPhoenix.Form` is not used anywhere.

The library is about 16,500 lines in `lib/`. It ships no JavaScript: `priv/` holds only `cinder.css` and `themes/*.css`, and those files contain Tailwind `@source` directives, not styles. A search of `lib/` for `phx-hook` finds nothing. Client behaviour is limited to `Phoenix.LiveView.JS` commands (`toggle`, `hide`, `show`, `push`) for dropdowns and the filter panel.

### Components

The developer-facing API is one function component, `Cinder.collection/1` in `lib/cinder/collection.ex`. The developer writes HEEx with slots:

- `:col` with `field`, `filter`, `sort`, `search`, `label`, `class`, and the cell content as the slot body.
- `:filter` for filters that have no display column.
- `:item` for the list and grid layouts.
- `:bulk_action`, `:controls`, `:loading`, `:empty`, `:error`.

`collection/1` does the per-render preparation: it normalises `resource` or `query`, turns the `:col` slots into column maps (`process_columns/2`, which calls `Cinder.Column.parse_column/2`), builds the list of query columns, resolves the theme to a map, picks a renderer, and then renders a single `<.live_component module={Cinder.LiveComponent} …>` with about forty assigns.

The column map keeps the original slot under `:slot`, and the table renderer draws a cell with `render_slot(column.slot, item)`. When a `:col` has no body, the default is a function that returns the raw field value (`default_inner_block/1`). There is no type-driven display formatting.

### LiveComponent state

`lib/cinder/live_component.ex` (1,084 lines) is the one stateful piece, shared by all three layouts. Its assigns hold:

- Query state: `filters`, `sort_by`, `current_page`, `page_size`, `search_term`, `after_keyset`, `before_keyset`.
- Result state: `data` (a plain list of records), `page` (the `Ash.Page` struct), `loading`, `error`.
- Selection state: `selected_ids` (a `MapSet` of strings).

Rows are a list assign, not a LiveView stream. A search of `lib/` for `stream(` and `phx-update` finds nothing. The maintainer explains the choice in issue #16: live lists have "a lot of edge cases when it comes to sorting, filtering and pagination".

`update/2` has several clauses. The general one assigns, decodes URL state, and then compares a snapshot of the data-relevant assigns before and after (`data_state/1`: the keys in `@data_keys` plus actor, tenant and scope reduced to ids) to decide whether to reload. The others are private message protocols carried by `send_update`: `refresh: true`, `__update_item__`, `__update_items__`, `__update_item_if_visible__`, `__update_items_if_visible__`.

`handle_event/3` handles a fixed set of events: `goto_page`, `next_page`, `prev_page`, `change_page_size`, `clear_filter`, `toggle_sort`, `refresh`, `clear_all_filters`, `toggle_select`, `toggle_select_all_page`, `clear_selection`, `bulk_action_execute`, `filter_change`. There is no catch-all clause. Issue #73 (open) reports the consequence: a custom filter that sends its own event to the component crashes it, and there is no forwarding to the parent LiveView.

`render/1` is one line: `assigns.renderer.render(assigns)`.

Loading uses `start_async(socket, :load_data, …)` and keeps the previous rows on screen while `loading` is true. It runs synchronously when `initial_load` is `:sync` for the first load, or when `config :ash, :disable_async?` is set.

### Query building

`lib/cinder/query_builder.ex` (1,414 lines) is documented as internal. `build_query/2` runs a fixed pipeline on `Ash.Query.new(resource_or_query)`: validate sort fields, apply filters, apply search, apply sorting, then set the action with `Ash.Query.for_read/4`, using the `action` option or the primary read action. `execute/2` adds pagination and calls `Ash.read/2`:

- Offset: `Ash.Query.page(limit:, offset:, count: true)`.
- Keyset: `Ash.Query.page(limit:, after: | before:, count: true)`.
- If the action has `pagination: false`, it reads everything and logs a warning when a page size was configured.

Splitting build from execute lets Cinder hand the pre-pagination query to the parent through `on_query_change`, for exports and totals.

Authorisation options are passed through. `scope`, `actor` and `tenant` go to `Ash.Query.for_read` and `Ash.read`, and Ash resolves precedence. A query the developer already prepared with `for_read` is not mutated.

Relationships and calculations must be loaded by the developer through `query_opts: [load: …]`. Cinder does not infer loads from the column fields. Issue #122 (open) asks for this.

Field paths are strings: `department.name` for relationships and `profile__country` for embedded attributes. Sorting and filtering on a calculation is allowed only when the calculation is an expression (`calculation_sortable?/1`).

### Filters

`Cinder.Filter` (`lib/cinder/filter.ex`) is a behaviour with six callbacks: `render/4`, `process/2`, `validate/1`, `default_options/0`, `empty?/1`, `build_query/3`. A processed filter value is a map with `:type`, `:value` and `:operator`. Eleven filters are built in (`lib/cinder/filters/registry.ex`): text, select, multi_select, multi_checkboxes, date, date_range, number_range, boolean, radio_group, checkbox, autocomplete.

The filter type is inferred from the Ash attribute in `Cinder.Filters.Registry.infer_filter_type/2`:

| Attribute | Filter |
|---|---|
| `one_of` constraint or an `Ash.Type.Enum` | select |
| `{:array, _}` | multi_select |
| date and datetime types | date_range |
| boolean | boolean |
| integer, decimal, float | number_range |
| string and anything else | text |

Custom filters are registered through `config :cinder, :filters, %{name: Module}` plus a call to `Cinder.setup()` at application start. A built-in type cannot be overridden. `mix cinder.gen.filter` generates a skeleton.

### URL sync

Two modules. `Cinder.UrlManager` encodes and decodes state: filters become top-level query parameters named after the field, sort becomes `sort=-title`, the page is written only when greater than one, and keyset cursors go into `after` and `before`. `Cinder.UrlSync` is the LiveView side: `use Cinder.UrlSync` injects a `handle_info({:table_state_change, id, encoded_state}, socket)` clause that calls `push_patch`, and `Cinder.UrlSync.handle_params/3` puts the raw params into an `@url_state` assign that the developer passes back to the collection.

The LiveComponent never patches the URL itself. It sends a message to the parent LiveView process, which owns the URL. Parameters that do not belong to the collection are preserved.

Parameter names are global, not namespaced by collection id. Issue #78 (open) records that two URL-synced collections on one page conflict.

### Themes

A theme is a flat map of about 110 keys to CSS class strings (`@theme_defaults` in `lib/cinder/theme.ex`), for example `th_class`, `td_class`, `row_class`, `filter_text_input_class`. Renderers read `@theme.td_class` and also put `data-key="td_class"` on the element so that the key behind any element can be found in the browser.

`use Cinder.Theme` gives a small macro DSL with `set :key, "classes"` and `extends :modern` or `extends MyApp.BaseTheme`. It is implemented with module attributes and `__before_compile__`, not with Spark. Seven preset themes ship with the library, plus the unstyled default (the README counts nine). The default can be set with `config :cinder, default_theme: …`. The classes are Tailwind utilities, so the host app must add Cinder's files as Tailwind sources. `mix cinder.install` (Igniter) does this.

### Row updates and refresh

`Cinder.Refresh.refresh_table/2` sends `refresh: true` and causes a full re-query that keeps filters, sort and page. It shows the loading state. Issue #163 (open) asks for a way to skip that.

`Cinder.Update` (`lib/cinder/update.ex`) patches rows in memory without a query:

- `update_item(socket, collection_id, id, fun)` and `update_items/4`.
- `update_if_visible/4` and `update_items_if_visible/4`, which call the function only when the row is on the current page. They also accept a raw record, so the function can load associations lazily.

All four send a closure to the component with `send_update`. The documented caveats: calculations and aggregates are not recalculated, and an id that is not on the page is silently ignored. Matching is `Map.get(item, id_field) == id` with a single `id_field` that defaults to `:id`, so there is no composite primary key support and the caller must pass an id of the right type.

### Selection and bulk actions

`selectable` enables checkboxes and accepts a predicate per row. `:bulk_action` slots take an action name or a two-arity function. For a name, `Cinder.BulkActionExecutor` looks up the action type and calls `Ash.bulk_update` or `Ash.bulk_destroy` on a query filtered to the selected ids, then clears the selection and reloads. This is the only place Cinder writes to the data layer.

## Supported extension points

Documented and intended for developers:

- Custom filter types through the `Cinder.Filter` behaviour and the config registry.
- Custom themes through `use Cinder.Theme`.
- Cell content through the `:col` slot body. Item content through `:item`.
- Filter and search layout through the `:controls` slot and `Cinder.Controls` (added in v0.12.0).
- Loading, empty and error content through slots.
- Per-column `filter={[fn: …]}`, collection-level `search={[fn: …]}`, and a sort cycle per column.
- A pre-built `query`, a read `action`, and `query_opts`.
- Callbacks to the parent LiveView as process messages: `on_state_change`, `on_query_change`, `on_selection_change`, and `on_success` / `on_error` on bulk actions.
- `click` for a row and `item_class` for a row class.
- `Cinder.Refresh` and `Cinder.Update` from the parent LiveView.
- Gettext translations.

Not extension points:

- The renderer. `get_renderer/1` in `collection.ex` is private and maps `:table`, `:list` and `:grid` to three modules. An unknown layout logs a warning and falls back to the table.
- The markup of `<table>`, `<tr>`, `<th>` and `<td>`. Only classes can be changed. No attributes can be added.
- The LiveComponent's events and state.
- Type-driven display. There is no mapping from attribute type to a cell representation, only to a filter.
- `Cinder.QueryBuilder`, `Cinder.Column`, `Cinder.FilterManager`. They are grouped under "Internal" in the docs configuration.

## Could ash_table be built on Cinder?

### The HEEx-free declaration: yes, for the read-only part

Nothing in Cinder is declared on the resource. But a wrapper could be: an `ash_table` function component could read the table model and render `<Cinder.collection>` with `<:col :for={col <- @columns} :let={row} field={col.field} filter={col.filter} sort={col.sort}>…</:col>`. Phoenix allows `:for` on slot entries. The developer would write no HEEx. Loads could be generated from the model and passed in `query_opts`, which also closes Cinder's gap from issue #122.

This was not built or run. It is an inference from reading `collection.ex` and from Phoenix's slot semantics.

So the walking skeleton (read-only table, sorting, pagination) could run on Cinder. The question is what happens at the next slice.

### Inline editing: possible only as a workaround

The one seam is the `:col` slot body. An editor can be rendered there. Events from slot content that carry no `phx-target` go to the parent LiveView, not to Cinder's component, so the pattern would be:

1. Render each cell through a function component or a per-cell LiveComponent inside the slot.
2. Keep all edit state outside Cinder, in the parent LiveView or in those per-cell components.
3. Run the declared update action there.
4. Push the result back with `Cinder.Update.update_item/4`, or call `refresh_table/2` when calculations or aggregates are affected.

That works for click-to-edit. It leaves these problems:

- **Two owners of one row.** The record lives in Cinder's `data` assign. Its edit state lives elsewhere. They are synchronised by `send_update` with a closure. After an edit, the fresh record from the action result has to be patched in, with the same loads the table used, or the whole page is re-queried and flashes the loading state.
- **`ash_table` would have to be a LiveView-level construct, not an embeddable component.** Something has to receive the events and call `Cinder.Update`. Either the host LiveView does (through a `use` macro, as `Cinder.UrlSync` does), or `ash_table` wraps Cinder's LiveComponent in its own LiveComponent. `send_update` works from there, but the wrapper would be a second stateful layer whose only job is to work around the first.
- **No way to mark a cell as editing, invalid or saving in the table markup.** `<td>` gets `@theme.td_class` and `column.class` and nothing else. The state can only be shown inside the slot content.

### Keyboard navigation and ARIA grid: this fights the design

The first version needs `role="grid"`, `role="row"`, `role="gridcell"`, `aria-rowindex`, `aria-colindex`, `aria-sort`, a roving `tabindex`, and a hook on the grid element for arrow keys, Enter, Escape and Tab.

`lib/cinder/renderers/table.ex` has none of these and offers no place to add them. A search of `lib/` for `role=`, `tabindex`, `phx-keydown` and `phx-window` finds nothing. The only `aria-` attributes are on the page-size dropdown and the radio-group filter. Attributes added from a JS hook on a wrapper element would be removed again whenever LiveView patches the table, which it does on every sort, filter, page change and row update. A hook could find cells by DOM position, because rows carry `data-item-id`, but cells carry no column identity.

The remaining routes are to fork the renderer or to get a pluggable renderer accepted upstream. A fork is independence with extra maintenance. An upstream renderer seam is plausible in principle, since rendering is already one delegated call, but it does not exist, nobody has asked for it, and the assigns passed to a renderer are an undocumented internal contract. Issue #28 (open since mid-2025) shows that even keyboard support for Cinder's own dropdowns is still pending, because it needs the first JS hook in the library.

### The manifest preference

Cinder reads resource shape with `Ash.Resource.Info.attribute/2`, `attributes/1`, `relationships/1`, `calculations/1`, `aggregates/1`, `action/2` and `primary_action!/2`, mostly in `query_builder.ex` (22 call sites) and `filter_manager.ex` (19), with single calls in `column.ex`, `filter/helpers.ex`, `filters/date_range.ex` and `bulk_action_executor.ex`. It makes no use of `Ash.Info.Manifest` or Spark. On top of Cinder, `ash_table` would have two readers of resource shape with two sets of rules, for example for what counts as sortable or which filter fits a type. The map says there should be one.

### Stability

The changelog shows 0.13.0 on 2026-04-27, 0.14.0 on 2026-05-14, 0.15.0 on 2026-06-08, 0.16.0 on 2026-07-15 and 0.17.0 on 2026-08-08. Versions 0.14, 0.15 and 0.16 each list breaking changes. That is healthy for a young library and fine for someone using the documented API. It is a poor base for a library that depends on the shape of the column map, the LiveComponent's assigns and the private `send_update` messages.

### Nothing in Cinder's direction points at editing

There is no issue or pull request about inline or cell editing. Searches of the tracker for "inline", "editable", "keyboard" and "spark" return nothing relevant. The only mentions of "edit" in the docs are links to a separate edit page. Pull request #171 ("user-editable column preferences") is about column visibility and was closed unmerged. The maintainer's own framing in issue #16 is that Cinder has "a good middle ground at the moment": change data with an action elsewhere, then refresh the table.

Not checked: Elixir Forum, Discord and other channels outside the repository. GitHub Discussions are disabled for the repository.

## Verdict

Build `ash_table` independently. Do not depend on Cinder.

Cinder and `ash_table` solve neighbouring problems with opposite centres of gravity. Cinder is a query UI whose cells are opaque developer-written slots. `ash_table` is a grid whose cells are the product: typed, focusable, editable, generated from the resource. Everything `ash_table` adds sits in the layer Cinder keeps closed, and everything Cinder would contribute (the query pipeline, filter inference, URL encoding) is a few hundred lines of straightforward Ash code that `ash_table` needs to own anyway so that it can drive it from the manifest.

Depending on Cinder would save effort in the walking skeleton and cost more than that in the editing slice.

## Ideas worth borrowing

Architecture:

1. **A stateless function component in front of one LiveComponent, with rendering delegated to a module.** `render(assigns)` is `assigns.renderer.render(assigns)`. Make the renderer a real, documented seam from the start, which Cinder did not. It is the place for later slices such as alternative cell representations.
2. **Build the query and execute it in two steps.** Filters, search, sort and action first, pagination second. The pre-pagination query can then be given to the host for exports and counts (`on_query_change`).
3. **Decide on reload by diffing a snapshot of the data-relevant assigns**, with actor, tenant and scope reduced to ids so that struct metadata does not cause false reloads (`data_state/1`).
4. **Load with `start_async` and keep the old rows visible, dimmed, while loading.** Offer a synchronous first load for server-rendered HTML. Honour `config :ash, :disable_async?` so tests are deterministic.

Query and Ash integration:

5. **Hand `scope`, `actor` and `tenant` straight to Ash** and let it resolve precedence. Do not mutate a query the developer already prepared.
6. **Check what the action can do and say so.** Warn when a page size is set but the read action has no pagination. Validate sort fields before querying. Allow sort and filter on a calculation only when it is an expression.
7. **Offset pagination with `count: true` by default, keyset as an option** with cursors taken from `__metadata__.keyset` of the first and last row.
8. **Field path notation**: `relationship.field` and `embedded__field`.

Filters (for the "Filtering UI" item under "Not yet specified"):

9. **A filter is a behaviour** with render, process (raw input to a typed value), validate, empty? and build_query, and a filter value is `%{type, value, operator}`. The same `process/2` decodes both form input and URL params.
10. **The type-to-filter inference table** above is a tested starting point.

URL state:

11. **The parent LiveView owns the URL.** The component sends a message, and a `use` macro injects the `handle_info` that calls `push_patch`. Foreign params are preserved.
12. **Compact encoding**: `sort=-title,name`, the page only when it is not 1, the page size only when it is not the default.
13. **Do it differently: namespace the params by table id from the first version.** Cinder's global names are its open issue #78.

Row updates (for the later live multi-user slice, and for writing back after an edit):

14. **`update_if_visible`**: patch a row only when it is on the current page, and pass the incoming record to a function that can load what the table needs. Add what Cinder's version lacks: reload calculations and aggregates for that one row.
15. **Refresh that keeps filters, sort and page**, with an option to skip the loading state (Cinder's open issue #163).

Theming and assets (for "Extension points for later slices" and "Shipping assets"):

16. **A theme is a flat map from named element keys to class strings**, with `set` and `extends`, and a `data-key` attribute on each element so the key can be found in the browser inspector.
17. **Ship a CSS file in `priv/` that only contains Tailwind `@source` lines**, and have the Igniter installer import it. This delivers styles without npm.

Robustness and packaging:

18. **Re-check everything the client sends against server state**: selected ids against the rows on the page, page size against the allowed options.
19. **An Igniter installer, an upgrade task that rewrites user code between versions, a `usage-rules.md`, and Gettext for all built-in strings.**

Mistakes to avoid:

20. No catch-all for unknown events in the LiveComponent (issue #73).
21. A hard-coded renderer choice.
22. Loads that the developer must repeat by hand next to the column list (issue #122).
23. A single `id_field` that assumes one primary key attribute named `:id`.

## New questions

- **Row state: list assign or stream?** Cinder keeps rows in a list assign and its maintainer avoided streams because of sorting, filtering and pagination edge cases. With streams the server no longer holds the rows, which matters for editing (the record is needed to build the changeset) and for `update_if_visible`. This belongs to the rendering research and the grid prototype.
- **What happens to a row after an edit that makes it no longer match the current filter or sort position?** Leave it in place until the next reload, or re-query? Cinder never faces this because it does not edit.
- **After an edit, how is the row brought back to the table's shape?** The action result does not carry the table's loads, calculations and aggregates. Reload that one record with the table's load statement, or re-read the page?
- **Primary keys.** Ids arrive from the client as strings. How are they cast, and are composite primary keys supported in the first version?
- **Should URL params be namespaced per table from the first version**, so that two tables on one page work?
- **Is the renderer seam part of the first version's public contract**, or internal until the cell-representation slice?
- **Minimum LiveView version.** Colocated hooks (LiveView 1.1) came up in Cinder's issue #28 as the way to ship a hook without touching the host's `app.js`. That bears on the "Shipping assets" item.
