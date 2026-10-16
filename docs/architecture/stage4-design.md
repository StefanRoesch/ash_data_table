# Stage 4: design note (attach, the plain function component, the wiring on top)

Status: **accepted by the owner, 2026-10-16, all as recommended.** Code references are of `2c9845f`. LiveView references are of the installed `phoenix_live_view` 1.2.12, under `demo/deps/phoenix_live_view/` (written `LV lib/…` below). Names follow [target.md](target.md); words follow `CONTEXT.md`. The model for this note is [stage5-design.md](stage5-design.md).

Stage 4 runs after stage 5 (RQ2). Stage 5 left it three things (stage5-design §10): the top `live_component` in `AshDataTable.table/1` and in `Live.Page`; `Caller.authorize?`, written and never read; and the done-check line "no `live_component` in `lib/`", which must be reworded (section 9).

## 0. The decisions at a glance

Answer "as recommended", or per number.

| # | Question | Recommendation |
| --- | --- | --- |
| D1 | Where the `Table` lives, and how the core finds it | Under the attach name (`@tasks`). The core reads and writes it through `Core.table/1` and `Core.put/2`, which find the name in the socket's private data. A mechanical first step, on its own |
| D2 | Ids, names, several tables, attaching again | Id defaults as for the tag and the router line. Names and ids unique per socket, checked at attach. Attaching again with the same name tells the table again (who is asking may change); another resource, table or id raises |
| D3 | How events, async results, messages and params reach the right table | One set of four hooks per socket, attached once. They halt everything that is the table's (`ash_data_table:` events, `{:ash_data_table, id, kind}` keys, the relay message) and let the rest through |
| D4 | Stream names on the host's socket | Prefixed with the top table's id (`"tasks:rows"`, `"tasks:rows_1"`). The names a table configured are remembered on the socket across `detach` |
| D5 | How `attached/1` gets the uploads | An optional attribute: `uploads={assigns[:uploads]}`. A table with a file field that is not given it raises with a message that says what to write |
| D6 | `url: true`, `handle_params` and the first read | With `url: true` the first read happens in the first `handle_params`, in place, before the first render. Only in a routed root LiveView; attach raises otherwise. The hook always continues |
| D7 | `Live.Page` on `attach` | It attaches in its first `handle_params` (the route needs the URL) and runs the params step once itself. It raises `NotFoundError` there |
| D8 | The listener relay | `Table.options.target` decides: a cid → `send_update` (the tag); nil → `send(view, {:ash_data_table_heard, id, batch})` and the `handle_info` hook |
| D9 | What a default of an asked argument is given | With `attach`, the host's current assigns, without LiveView's own and without any `Table`. The tag keeps its `assigns` attribute |
| D10 | `Caller.authorize?` | Removed. Each entry's `authorize?` and the top entry's `authorize_given` already say it |
| D11 | One code path for the tag | `Live.Embedded` (today's `Live.TableComponent`, renamed) calls the same `Live.Core` functions as the hooks. No `attach_hook` on a component |
| D12 | Where the drawing lives; hook names; the root element | `AshDataTable.attached/1` and its private `body/1` and colocated hooks move into `AshDataTable`. Hook names become `AshDataTable.Grid` etc. `Live.Embedded` draws the root tag and calls `attached/1` with an internal `root={false}` |
| D13 | What `detach/2` does | Closes every entry with `Registry.close` (the top one too), sets the assign to nil. The hooks stay for the life of the socket, so late events and results are dropped, not sent to the host |
| D14 | Is `AshDataTable.Table` public now? | A public, opaque moduledoc ("pass it to `attached/1`"). The read-only fields wait for stage 6 |
| D15 | The three-way runs (F14) | ExUnit `parameterize` over `:mounted`, `:embedded`, `:attached`, with two support pages that place a router line's table by tag and by `attach`. The snapshot test and one file per feature group |
| D16 | Snapshots across modes | The normaliser drops `phx-target` (the attached markup has none). All snapshot files are written once, the diff reviewed to be only that |
| D17 | Browser tests and the ten-runs rule | A new attached page and spec. The stage-5 spec set plus the new spec ten times in a row, the whole suite once |
| D18 | The fallback | If attach cannot be made stable with public API: two fixes, then `Live.Page` stays on `Live.Embedded`, `attach` is not shipped, steps 1–2 stay. You are told |
| D19 | Performance | The five actions of `baseline.mjs` on `/tasks` (now `attach`) and the same on a tag page, at the start and the end, same machine |

## 1. What stage 4 changes, and what it does not

**Changes.**

- `AshDataTable.attach(socket, name, resource, opts)` puts a `Table` under the assign `name` of the host's LiveView, attaches LiveView's hooks, and reads (in place). `AshDataTable.attached/1` draws it: `<AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />`. No live component.
- `AshDataTable.detach(socket, name)` closes the table.
- `Live.Page` (the router line) uses `attach`. Every demo test of a router page then runs on `attach` (R §8 decision 8).
- `<AshDataTable.table>` renders one live component, `AshDataTable.Live.Embedded`, which holds the same `Table` and the same core, and renders `attached/1`.
- `Caller.authorize?` goes.

**Stays the same.** No new ability for a person. Every event, payload, reply and `push_event` means what it means today. The DOM of a tag is today's. The DOM of a router page loses `data-phx-component` on its root and every `phx-target` attribute: its events go to the LiveView, not to a component. The markup snapshots are rewritten once for that (D16). Commands (`refresh`, `put_state`, …) and events to the host are stage 6.

## 2. The shape

### 2.1 attach, step by step

```elixir
def mount(_params, _session, socket) do
  {:ok, AshDataTable.attach(socket, :tasks, MyApp.Tracker.Task, scope: socket.assigns.current_scope)}
end
```

```heex
<AshDataTable.attached table={@tasks} streams={@streams} uploads={assigns[:uploads]} />
```

1. Check the options (they are the tag's attributes: `id`, `table`, `scope`, `actor`, `tenant`, `authorize?`, `live?`, `label`, `heading`, `time_zone`; and `url: true`). Check that `name` and `id` are free on this socket (D2).
2. `Table.new()` with `options.target: nil` and `options.router: socket.router`. Put it under `name`. Take its first stream name (D4).
3. On the first attach of the socket: attach the four hooks (D3).
4. Without `url: true`: tell the table its options (`Core.told/2`, as the tag's `update/2` does) and tidy. That is the first read, in place. With `url: true`: the first `handle_params` does it (D6).

The socket's private data holds, under `:ash_data_table` (`put_private/3`, `LV lib/phoenix_live_view.ex:733`): the attached tables by name with their ids, the table the current callback works on (D1), and the stream names each id configured (D4).

### 2.2 The hooks

LiveView runs a hook before the view's own callback, in the order they were attached; `{:halt, …}` ends the stage, `{:cont, socket}` goes on (`LV lib/phoenix_live_view.ex:1646-1700`, `lifecycle.ex:187-196, 236-244`). A halted event or message never reaches the host, which then needs no clause for it (`channel.ex:567-590`, `598-606`; `async.ex:342-360`).

| Stage | Is the table's when | Returns for the table's | Else |
| --- | --- | --- | --- |
| `:handle_event` | the name starts `ash_data_table:` | `{:halt, socket}` or `{:halt, reply, socket}` from the table whose registry knows the id; an id no table knows gets `malformed/2`'s answer, halted | `{:cont, socket}` |
| `:handle_async` | the key is `{:ash_data_table, id, kind}` | `{:halt, socket}`; an id no table knows is dropped, halted | `{:cont, socket}` |
| `:handle_info` | the message is `{:ash_data_table_heard, id, batch}` (D8) | `{:halt, socket}`; a batch for an id no table knows is dropped | `{:cont, socket}` |
| `:handle_params` | attached only when a table has `url: true` | told the URL; always `{:cont, socket}`, so the host's own `handle_params` runs too | — |

Each hook ends in `tidy/1` for the table it ran on, as every callback does today (`core.ex:509-515`).

### 2.3 The tag

`AshDataTable.table/1` renders `<.live_component module={AshDataTable.Live.Embedded} …/>` with today's attributes (`lib/ash_data_table.ex:221-240`). `Live.Embedded`:

- `mount/1`: `Core.mount` with the name `:table` and `target: @myself`.
- `update/2`: `Core.update` (today `table_component.ex:559-567`). The `NotFoundError` check moves to `Live.Page` (D7): a tag is never `mounted?`.
- `handle_event/3`, `handle_async/3`: `Core.handle_event`, `Core.handle_async`.
- `render/1`: the root tag (a live component's root must be a static tag: `LV lib/phoenix_live_view/diff.ex:404-411`, `phoenix_live_component.ex:559-560`), and in it `<AshDataTable.attached table={@table} streams={@streams} uploads={assigns[:uploads]} root={false} />` (D12).
- Live updates: `send_update` to `@myself` (D8). The URL: from the `url` attribute.

### 2.4 The page

`Live.Page.mount/3` assigns nothing of the table. Its first `handle_params/3` finds the route (`page.ex:347-379`), attaches under `:table` with `url: true`, `heading: 1`, the page title as label, the reader from the domain's assigns (`page.ex:337-343`) and the zone (`page.ex:327-335`), runs the params step once itself (D7), and raises `NotFoundError` when the first read made the table `gone?`. Later `handle_params` calls reach the table through the hook. `render/1` draws `<div id="ID-page">` and `attached/1` inside the layout, as today (`page.ex:262-289`).

## 3. Decisions for the owner

**D1. Where the `Table` lives, and how the core finds it.**

The core reads `socket.assigns.table` everywhere: about 230 reads, 34 function heads that match `%{assigns: %{table: …}}`, 9 writes and 20 calls of `reader(socket.assigns)` (grep over `lib/ash_data_table/live/`). With `attach` the host names the assign (`@tasks`), and a page can hold several.

| Option | For | Against |
| --- | --- | --- |
| a. The attach name is the assign. `Core.table(socket)` reads it, `Core.put/2` writes it; the name of the table the callback works on is in the socket's private data, set where each callback starts (as `Registry.within/3` sets the current entry). The tag's name is `:table` | the host's own assign, change-tracked on its own; `table={@tasks}` as target §4.6 says; one mechanical step that the suites can judge before anything else moves | about 300 lines change; one more implicit "current" (beside `within/3`) |
| b. Swap: move `@tasks` to `@table` for the call and back | no change in the core | there is no public way to remove an assign: `@table` stays on the host's socket; a host (and `Live.Page` today, `page.ex:251`) may have its own `@table`; change tracking marks `@table` on every callback |
| c. One assign for all tables of a socket (`@ash_data_table`, by name) | one fixed name | a change of one table renders every table again; not `table={@tasks}` |

**Recommendation: a.** Its own commit, first (section 4, step 1). Stage 7 may make the name explicit, as it may for `within/3`.

**D2. Ids, names, several tables, attaching again.**

The name tells the host's assigns apart; the id tells the DOM, the events, the async keys and the upload names apart (stage 5, 2.2).

| Option | For | Against |
| --- | --- | --- |
| a. Id defaults to `Routes.default_id(resource, table)`, as the tag (`lib/ash_data_table.ex:210`) and the router line (`router.ex:142`) | one rule in all three modes; the same DOM for the same table, which the three-way runs need | two attached tables of one resource need an `id` each, as two tags do |
| b. Id defaults to the name as a string (R §5.2) | never clashes | `attach(:tasks, Task)` has the id `tasks`, the tag `task`: two DOMs |

**Recommendation: a.** Besides: `attach` raises when the name is an assign that holds no `Table` (nil after `detach` is free), and when the id is another attached table's. Attaching again with the same name tells the table again with the new options: another `scope`, `actor`, `tenant` or `authorize?` closes what is open and reads again (`Core.asker/2`, `core.ex:473-496`; target §2 row 23). Another resource, table or id raises: "detach first". No hook is attached twice (`attach_hook` raises on an id it has, `lifecycle.ex:53-59`).

**D3. How events, results, messages and params reach the right table.**

| Option | For | Against |
| --- | --- | --- |
| a. One set of four hooks per socket, attached with the first table. Each finds the table by the id (`Registry.known?/2` over the socket's tables) | an event for a closed table (a normal race: a `left` answer, a click while a nested table closes) gets `malformed/2`'s answer, as with the tag today, and never reaches the host | the hooks look at every table of the socket (a few map lookups) |
| b. Four hooks per table, each halting only its own | simplest | an `ash_data_table:` event that no table knows goes on to the host, whose `handle_event` has no clause for it: the LiveView crashes |

**Recommendation: a.** The returns are those of 2.2. A host's own hook attached before ours can still stop an event: that is F20, accepted.

**D4. Stream names on the host's socket.**

Today each `Table` takes `"rows"`, `"rows_1"`, … from its own pool (`registry.ex:81-95`). Two attached tables on one socket would both take `"rows"`. A stream cannot be configured twice (`LV lib/phoenix_live_view.ex:2077-2091`), so a table attached again after `detach` cannot start its pool at 0 either.

| Option | For | Against |
| --- | --- | --- |
| a. Names prefixed with the top table's id (`"tasks:rows"`, `"tasks:rows_1"`); the names an id has configured are kept in the socket's private data and given back to a table of that id that is attached again | no clash between tables, nor with a host's own streams (atoms, as a rule); the pool stays in the `Table` | the names configured outlive `detach` (they must: no undo) |
| b. One pool per socket in the private data, shared by all tables | fewest streams | the pool leaves the `Table`; the tag's component socket would need it too |

**Recommendation: a.** The tag does the same (one code path); its names never clash anyway.

**D5. How `attached/1` gets the uploads.**

A function component sees only what it is given. `@uploads` exists only after the first `allow_upload` (`upload.ex:31-39`), and a library cannot assign it (`:uploads` is not assignable, `LV lib/phoenix_component.ex:648`, `1482-1484`). The panel's file inputs need the live upload configs (`files.ex:221-306`).

| Option | For | Against |
| --- | --- | --- |
| a. Required `uploads={@uploads}`; `attach` makes `@uploads` exist by allowing and at once disallowing an upload of its own (a disallowed config stays in the map, `upload.ex:44-62`) | the plain `@uploads` | a dummy entry in the host's `@uploads` for the life of the page; a trick no LiveView document promises |
| b. Optional `uploads={assigns[:uploads]}`. A table that opens a panel with a file field without it raises: "pass `uploads={assigns[:uploads]}` to `AshDataTable.attached`" | public API only; `assigns[:uploads]` is change-tracked like `@uploads` (`LV lib/phoenix_live_view/engine.ex:1071-1082`) | an unusual line for the host |
| c. The `Table` keeps a copy of its upload configs | no attribute | stale: progress and the upload channel messages change `@uploads` without passing the table's hooks |

**Recommendation: b.** The tag and the page write the same line inside.

**D6. `url: true`, `handle_params` and the first read.**

`mount/3` has no URL. A routed LiveView runs `handle_params` before its first render (`channel.ex:618-641`, `utils.ex:457-478`). A `handle_params` hook needs the router (`lifecycle.ex:44-47`) and is refused in a child LiveView (`static.ex:252-253`).

| Option | For | Against |
| --- | --- | --- |
| a. With `url: true`, `attach` in `mount` only attaches; the first `handle_params` hook tells the URL, which is the first read, in place. Each later one tells the URL again; the table reads only when its own parameters changed (`core.ex:418-420`, `reading.ex:85-87`). Always `{:cont, socket}` | one read per page load, as today; the host's own `handle_params` and its own patches work beside it | `attach` must be called in `mount` for `url: true` |
| b. `attach` reads at once with the state it has, and `handle_params` reads again | no rule about where to call it | two reads on every load, in the static render too |

**Recommendation: a.** `attach(…, url: true)` raises in a LiveView that is not routed or not the root, with a message that names the option.

**D7. `Live.Page` on `attach`.**

The page finds its resource through the URL (`page.ex:347-350`). `live/4` has no session per route, only `metadata` and `private` for the plug conn (`LV lib/phoenix_live_view/router.ex:63-81`), so `mount/3` cannot know it. A hook attached inside `handle_params` does not run in that same call (`lifecycle.ex:199-203` reduces over the hooks the socket had when the call began).

| Option | For | Against |
| --- | --- | --- |
| a. Attach in the first `handle_params/3`, then run the params step once by hand (the function the hook runs); later calls go through the hook | public `attach` contract stays simple ("call it in `mount`"); the page is the library's own wiring and may call an internal function | the page has a first-call branch |
| b. `attach` also takes `url: url` (the current URL, as the tag's `url`) for a call from `handle_params` | no internal call | two forms of one option in the public API |
| c. Find the route in `mount` by `live_action` | `attach` in `mount` | two routes of one table share an id and differ in `authorize?` (`router.ex:178-191`): it cannot tell them apart |

**Recommendation: a.** The page raises `NotFoundError` right after that first read when the table is `gone?` (today `table_component.ex:559-567`); a later refusal stays the redirect of `reading.ex:396-403`. The page's own assigns become `:table` (the `Table`) and `:route` (what the route says; today `:table`, `page.ex:251-259`). `mounted?` becomes an internal option of `attach` (`doc false`, as the tag's `select`).

**D8. The listener relay (Q10).**

Today the relay is `send_update(view, myself, live: {:heard, id, batch})` (`updates.ex:38-52`); a LiveView socket has no `@myself`.

| Option | For | Against |
| --- | --- | --- |
| a. `Table.options.target`: the cid for the tag, nil for `attach`. The same field gives the parts their `phx-target`. nil relays `send(view, {:ash_data_table_heard, id, batch})`, a private tag like `:ash_data_table_changed` (Q2) | one field for both differences; the message cannot be mistaken for stage 6's events to the host (`{:ash_data_table, id, {event, details}}`, S7) | — |
| b. `{:ash_data_table, id, {:heard, batch}}` | one prefix | the shape of S7: a host hook attached before ours, or a host catch-all, would see it |

**Recommendation: a.** `AshDataTable.Test.flush/1` and `listening/2` work as they do (`test.ex:58-97`): they ask the listener processes, not the relay.

**D9. What a default of an asked argument is given.**

Today `options.page_assigns`: the tag's `assigns` attribute, or the page's socket assigns (`page.ex:323-324`). The stage-2 drift note says: with `attach`, the current assigns, not a copy (a copy would hold the `Table` itself).

| Option | For | Against |
| --- | --- | --- |
| a. With `attach`, `options.page_assigns` is `:socket`: the core takes the host's assigns where it builds the model (`core.ex:215`, `picker.ex:444`, `nesting.ex:239, 265`), without LiveView's own (`__changed__`, `flash`, `live_action`, `streams`, `uploads`) and without any `Table`. The tag keeps its map | current, never stale; no copy | the assigns a function sees depend on the host's names (as on the page today) |
| b. An `assigns:` option of `attach`, as the tag's attribute | the same as the tag | stale after the next host event; the page would copy its own assigns again |

**Recommendation: a.**

**D10. `Caller.authorize?`.**

`Core.update/2` writes it (`core.ex:60-68`). `Core.reader/1` overrides it with the entry's resolved value before every call (`core.ex:457-466`). `asker/2` compares the entry's `authorize_given` (`core.ex:483`). No test names it.

| Option | For | Against |
| --- | --- | --- |
| a. Remove the field; `Core.reader/1` adds the entry's `authorize?` to `Caller.reader_opts/1` | no value that looks like it counts and does not | `Caller.reader_opts/1` no longer gives the whole list alone |
| b. Keep it, and have `asker/2` read it in place of `authorize_given` | `Caller` keeps "what the top was told" | two places for one fact |

**Recommendation: a.**

**D11. One code path for the tag.**

| Option | For | Against |
| --- | --- | --- |
| a. `Live.Embedded`'s callbacks call the same `Live.Core` functions the hooks call | the same core; a component is told by `update/2`, which is no hook stage | two thin callers |
| b. The component calls `attach` on its own socket | literally "the same `attach`" | a component takes only `:handle_event`, `:handle_async` and `:after_render` hooks (`lifecycle.ex:97-100`, `LV lib/phoenix_live_view.ex:1661-1663`): no relay, no params; it would still need `update/2` |

**Recommendation: a.** Today's `table_component.ex` becomes `lib/ash_data_table/live/embedded.ex` (`test/architecture_test.exs:61` lists it as wiring already). The old module and name go; nothing forwards to them.

**D12. Where the drawing lives; the hook names; the root element.**

The drawing (`render/1`, `body/1`, `portals/2`, `rows/2`, `chooser/2`, the four colocated hooks, and the markup contract comment, `table_component.ex:1-537, 575-854`) is the tag's today. With `attach` it must be `AshDataTable.attached/1`'s. A colocated hook is named after its module (`phx-hook="AshDataTable.Live.TableComponent.Grid"`, `parts/grid.ex:679`, `assets/js/index.js:29-32`).

| Option | For | Against |
| --- | --- | --- |
| a. All of it in `AshDataTable` (`lib/ash_data_table.ex`): `attached/1` public, the rest private. Hook names `AshDataTable.Grid`, `.Panel`, `.Picker`, `.Pagination` | the public function is the drawing; no module that only forwards (greenfield rule) | `lib/ash_data_table.ex` grows to about 1,100 lines, most of it the contract comment, until stage 7 splits it into the kit |
| b. A part-4 module (e.g. `AshDataTable.Live.Drawing`) holds it; `attached/1` calls it | a small public module | `attached/1` is a forwarder |

**Recommendation: a.** The snapshots normalise the module part of hook names already (`markup_snapshot_test.exs:145`); `index.js`, the parts and `demo/e2e/support/table.ts` (a comment) change once.

The root: a live component needs a static root tag (D11 b's sources), and `attached/1` draws the root of the table (`table_component.ex:576-580, 592`). So `attached/1` takes an internal `root` attribute (`doc false`, default true). `Live.Embedded` draws the same root tag itself and passes `root={false}`. The DOM is the same in all modes. Rejected: an extra wrapper element in tag mode (the DOM changes, and the three-way snapshots would need a rule that hides it, which stage 5 refused, D4c).

**D13. What `detach/2` does.**

`Registry.close/2` closes any entry but the top one (`registry.ex:121-165`). LiveView has no way to remove an assign or to undo `stream_configure`.

| Option | For | Against |
| --- | --- | --- |
| a. Close every entry, the top one too (listener, async, copies of files, uploads, stream reset, pool name back), by the same function; keep the names configured (D4); set the assign to nil (`attached/1` draws nothing for nil); the socket's hooks stay as long as the socket lives | a late event, result or batch for the table is answered or dropped by our hooks, never sent to the host; portals go in the same render as their table | the hooks stay after the last table goes (they only look at the table's own names) |
| b. Also detach the hooks when the last table goes (R §5.4) | nothing of the table left | a late `ash_data_table:` event or a cancelled task's result reaches the host: a crash for a host with no catch-all |

**Recommendation: a.** `detach` is the removal path stage 5 left for stage 4 (stage5-design §3): it gets its browser test here (D17).

**D14. Is `AshDataTable.Table` public now?**

target §4.4 says "public, opaque struct" with read-only fields; today it is `@moduledoc false` (`table.ex:2`). With `attach` the host holds it and passes it on.

| Option | For | Against |
| --- | --- | --- |
| a. A public moduledoc: opaque, held under the attach name, given to `attached/1`, changed only by the library. The read-only fields (`id`, `state`, `count`, `total`, `loading?`, `error`) come with stage 6's commands and events | nothing promised before it is needed | a host cannot read the count yet |
| b. The read-only fields now | the full target | a promise made before stage 6 shapes `:read` (F19) |

**Recommendation: a.**

**D15. The three-way runs (F14).**

Once `Live.Page` uses `attach`, "mounted" runs on `attach` too. The three modes are then: the router page (`attach` in the library's page), the tag in a host page, and `attach` in a host page.

| Option | For | Against |
| --- | --- | --- |
| a. ExUnit `parameterize` (Elixir 1.18 and up; this machine runs 1.19.4, the demo's `mix.exs` says `~> 1.15` and is raised to `~> 1.18`). Two demo pages under `/support/modes/embedded/*path` and `/support/modes/attached/*path` look up the router line of `path` (`Phoenix.Router.route_info/4`, as `page.ex:350`) and place that table with the same id, label, heading 1, reader, zone and URL state. A case template rewrites the `live/2` path by the mode. The chosen files change only their `use` line | test bodies unchanged; the ids are the same in every mode (D2) | three runs of each chosen file; the support pages are code to keep |
| b. A `for mode <- …` loop that defines a module per mode | works on any Elixir | the same file compiled three times; harder to read |

**Recommendation: a.** The subset: the snapshot test, and one file per feature group: `task_table_test`, `task_filter_test`, `page_size_test`, `task_edit_test`, `reference_cell_test`, `picker_test`, `nested_table_test`, `task_actions_test`, `task_create_test`, `table_actions_test`, `task_bulk_test`, `file_actions_test`, `argument_line_test`, `live_updates_test`, `footer_summaries_test`, `sensitive_table_test`, `map_table_test`. A file with a test that depends on the mode (404, layout, router options) is swapped for another of its group, and the as-built section says which. Snapshot 10 (the dashboard, two tags) runs two ways: as today, and on an attached twin of the dashboard.

**D16. Snapshots across modes.**

The normaliser writes every `phx-target` as `T` (`markup_snapshot_test.exs:150`). An attached table has none: its events go to the LiveView (`view.ts:1783-1808` finds no component).

| Option | For | Against |
| --- | --- | --- |
| a. The normaliser drops `phx-target`. All 16 snapshot files are written once; the diff is reviewed to hold only the removed attributes | one set of files for three modes | one rewrite of every file |
| b. An attached table renders `phx-target` with a selector of its root | no rewrite | markup with no purpose, for the tests' sake |

**Recommendation: a.** Together with the hook names (D12) in one reviewed commit.

**D17. Browser tests and the ten-runs rule.**

The browser is where `attach` is proven: a hook's push from an element in no component (`view.ts:1783-1808, 1844`), portals moved out of a LiveView's own template, uploads on the LiveView's socket.

| Option | For | Against |
| --- | --- | --- |
| a. A new page `/e2e/attached` (two attached tables of which one keeps its state in the URL, a stream of the host's own, a button that attaches again with the viewer, one that detaches a table with a nested table open) and `attached.spec.ts`. Then, as stage 5's D8: the specs `nesting`, `a11y-nesting`, `scrolling`, `live_updates`, `relationships`, `hiding`, `resizing`, `portals`, `files` and `attached` ten times in a row (`--repeat-each=10`), the whole suite once; a failure caused by the new mechanism gets two fixes, then D18 | the same bar as stage 5, on the same specs, which now all run on `attach` through the page | about 1,600 test runs for the ten |
| b. The whole suite once | quicker | the race stage 5 found (`nesting.spec.ts:702`) showed only in the ten runs |

**Recommendation: a.** Every spec already fails on a console error (`demo/e2e/support/fixtures.ts`), which is how a portal without its target shows.

**D18. The fallback.**

Everything above uses public LiveView API: `attach_hook/4`, `detach_hook/3`, `put_private/3`, streams, uploads, `start_async`, `push_patch`. The points that may still fail: a hook push from an element in no component, portals of a LiveView's own template inside a stream, `uploads` handed through a function component.

| Option | For | Against |
| --- | --- | --- |
| a. The trigger of stage 5's D8 (two fixes, or a spec of D17 that fails once in ten runs). Then `Live.Page` stays on `Live.Embedded`, `attach`/`detach`/`attached` are not shipped, steps 1–2 of section 4 stay (they are worth having on their own). You are told, with the cause and the LiveView version | a builder can apply it; nothing is half shipped | `attach` waits |
| b. You decide each case | judgement | the build waits for you |

**Recommendation: a.**

**D19. Performance.**

`demo/perf/baseline.mjs` measures `/tasks`, which becomes `attach`. The probe records a component's `update` (`docs/architecture/baseline.md`); `/tasks` will have `handle_params`, `handle_info` and `handle_async` of the view instead.

| Option | For | Against |
| --- | --- | --- |
| a. At the start (tag `stage4-start`) and at the end, on the same machine: the five actions and stage 5's two extra ones on `/tasks`, and the same on a tag page (`/support/modes/embedded/tasks` in the perf environment). The probe adds the view's `handle_params`, `handle_info`, `handle_async`. Growth measured and explained; Ash reads and statements not more; times within 20 % | both shipped paths measured; the start numbers are taken on the day, not borrowed from stage 5 (its machine was loaded) | one more page in the perf environment |
| b. `/tasks` only | the script as it is | the tag's path goes unmeasured, though its rendering changes too (D12) |

**Recommendation: a.**

## 4. Order of work

Each step: each suite once (root, demo, browser), its own commit or commits on `main`, `docs/agents/architecture.md` updated.

0. Tag `stage4-start`. Perf run (D19).
1. **The core finds its table by name** (D1), `Caller.authorize?` removed (D10), `Table.options` gains `target` and `router`, which `render/1` reads in place of `@myself` and `@socket.router` (`table_component.ex:600-602`). The tag and the page as before. Snapshots byte for byte; no test changes.
2. **The drawing** (D12): `attached/1` in `AshDataTable` with the `root` attribute; `Live.TableComponent` becomes `Live.Embedded` and renders it; hook names, `index.js`, the parts; the normaliser drops `phx-target` and the snapshots are written once (D16).
3. **`attach/4`, `detach/2`** (D2–D9, D13): the socket's private data, the four hooks, stream names (D4), the relay (D8), page assigns (D9), `url: true` (D6). Demo tests of group M on a small host page.
4. **`Live.Page` on `attach`** (D7). Group L.
5. **The attached demo and e2e pages** (D17); `attached.spec.ts`; **the gate** (section 5).
6. **The three-way runs** (D15).
7. Moduledocs (`AshDataTable`, `Table` per D14, `Listener`'s comment, which still speaks of "a LiveComponent", `listener.ex:6-10`), `docs/agents/architecture.md`, the perf comparison, the as-built section of this note.

## 5. Gate

- Steps 1 and 2: the three suites green; snapshots identical (step 1) or the reviewed rewrite (step 2).
- After step 5: the browser runs of D17 (the ten-runs set and the whole suite once), the demo suite once, the root suite once. A failure that passes on a second run is still looked into (build rules).
- After step 6: the demo suite once, with the subset three times inside it.
- Perf (D19) at the end. No-go: D18.

## 6. Tests

**Group L: the call target changes, the body does not.**

| Where | Today | After |
| --- | --- | --- |
| `AshDataTable.Test.send_event/5`, its `reached/4` (`test.ex:204-220`) | a portal's event goes to the component in the element's `phx-target` | where there is no `phx-target`, to the view: `render_hook(view, name, payload)` |
| `DemoWeb.TablePage.click/2` (`table_page.ex:1229-1231`) | raises without `phx-target` | a table's element is one whose event is named `ash_data_table:…` |
| `table_page_test.exs:10` | a fixture with `phx-target="1"` | a second case without it |
| `nested_registry_test.exs:50-54`, `table/1` | the `Table` from `Debug.live_components/1` | from `Debug.socket/1`'s assigns (the page is attached) |
| `markup_snapshot_test.exs:150` | `phx-target` → `T` | dropped (D16) |
| The chosen files of D15 | `use DemoWeb.ConnCase` | the mode case template |

**Group M (new): attach on a host page** (demo suite, a support LiveView of its own). The host's own event, message, async result and `handle_params` still reach it; two attached tables do not see each other's events, streams or uploads; a host stream named `"rows"` beside them; an event for a closed nested table gets `malformed/2`'s answer and the LiveView lives; attaching again with another actor closes the nested tables and reads again; another resource under the same name raises; a name or id taken raises; `url: true` in a LiveView that is not routed raises; `detach` leaves no listener (`AshDataTable.Test.listening/2`), no entry, and a late batch is dropped; attach after detach with the same id works (D4); a file field without `uploads` raises the message of D5.

**Group N (new): the three-way runs** (D15).

**Group O (new): browser.** `attached.spec.ts` (D17): sorting, a saved cell, a nested table two levels deep, a picker, an upload in a top and in a nested panel, the URL kept and the back button, attaching again, detaching with a nested table open, the host's own stream and button still working. Each with no console error.

**Unchanged on purpose.** Every other test body. `nested_table_reads_test.exs` counts reads per page load: the page on `attach` must read as often as the page on the component (one read in place per render pass, D6); a change in a count is a finding, not a test to change.

## 7. Risks

| Risk | Check |
| --- | --- |
| An `ash_data_table:` event, async result or batch reaches the host and crashes it | D3 and D13: the hooks halt every one of the table's names, known or not; group M |
| Two tables on one socket mix streams, async keys or uploads | D4; ids unique per socket (D2); group M |
| The host's assigns change under the table (a host rewrites `@tasks`) | server code of the host is trusted (F20); `Table` is opaque (D14) |
| A host halts our events with its own hook | F20, accepted |
| Bytes grow: the host re-renders `attached/1` when its own `@streams` change | per-field change tracking through `attached/1` (R §3.7); D19 |
| `uploads` not passed | D5's message |
| The first read twice with `url: true` | D6; `nested_table_reads_test.exs` |
| Portals and hook pushes outside any component in the browser | D17; D18 |

## 8. What the owner said that this note keeps

- Q1: `attach` and the plain component have no live component; the tag is one live component holding the same core (D11, D12).
- RQ4: no commands here; with the tag none ever. D3's hooks are the place stage 6's commands will act through.
- F1: nothing sensitive reaches the drawing. `attached/1` draws only through `Present`, as the component does now; D9's page assigns go to a default function on the server, never to the drawing.
- Greenfield: no compat code. `Live.TableComponent` is renamed, not kept; no module forwards (D12 a).

## 9. Done-check

- The three suites green. Changed tests: group L only, and the reviewed snapshot rewrite of D16. New: groups M, N, O.
- **Exactly one `live_component` in `lib/`: the tag's (`AshDataTable.table/1` renders `AshDataTable.Live.Embedded`). None for nested tables or pickers, none behind the router line (`Live.Page` uses `attach`), none with `attach`.** This replaces stage 5's line "no `live_component` in `lib/`", which contradicted that note's own §1 ("one live component per top-level table").
- No `assigns.table` in `lib/ash_data_table/live/core*` (all through `Core.table/1`); no `authorize?` in `Caller`.
- `grep -rn attach_hook lib/` finds only the four hooks of D3.
- The dependency test passes in fail mode.
- The perf comparison (D19) in the as-built section of this note.
- Target §9 stage 4 ticked, or the fallback (D18) recorded.
- **The drift check**: an independent reviewer compares the build with target.md (§4.4 `Live.Core` with `handle_info` and `handle_params`, §4.6 `attach/4`, `attached/1`, `detach/2`, `Live.Page`, `Live.Embedded`; Q1, Q10, RQ4, F11's host rule in `attached/1`'s docs; F14), the safety rules (§1.5: who is asking only from `attach` or the tag; ids as claims; uploads and async closed with their entry), and that only the agreed tests changed. The stage is done only after it.

## 10. Where target.md and the code differ

For the drift check and your yes; target.md is not changed by this note.

1. §4.6 shows `<AshDataTable.attached table={@tasks} streams={@streams} />`. It also needs the uploads (D5): a function component cannot reach `@uploads`, and a library cannot assign it.
2. §4.4 says `Live.Registry` gives "stream names from a pool". Per `Table` that pool clashes when a socket holds two attached tables, and it cannot restart after `detach` (D4).
3. §4.4 calls `AshDataTable.Table` public with read-only fields; the code has `@moduledoc false` and no such fields (`table.ex:2`; D14).
4. S8 lists `detach(socket, table)` among the commands "new, stage 6"; §9 builds it in stage 4.
5. §4.6 says `Live.Page` "uses `attach` itself" with no word on how it learns its table: `mount/3` has no URL and `live/4` no per-route session (D7).
6. §4.4 gives `Live.Core` `init`, `handle_info` and `handle_params` "for a table under a given assign". The code has `mount/1`, `update/2`, `handle_event/3`, `handle_async/3`, bound to the assign `table` (D1).
7. `Caller` in §1.4 and §4.3 keeps "what the top was told"; the code's `Caller.authorize?` is written and never used (D10).
