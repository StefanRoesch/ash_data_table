# Testing

Tables are LiveViews: `Phoenix.LiveViewTest` tests them like any page.
Three things need the library's help, through `AshDataTable.Test`,
`AshDataTable.KitCase` and `AshDataTable.Test.Resource`:

- live updates, which reach a table a little after they happen;
- nested tables and pickers, which `Phoenix.LiveViewTest` does not see;
- a kit of your own, which must carry what the table's browser behaviour
  relies on.

## A table on a page

Mount the page, look at what it renders, send it what a person does. The
table's ids begin with its id (`task-row-…`), and its events are named with
it: `ash_data_table:task:sort`. `AshDataTable.Test.send_event/5` sends an
event as the table's hook does, by the table's id and the event's plain
name:

<!-- sketch -->
```elixir
{:ok, view, _html} = live(conn, "/tasks")

AshDataTable.Test.send_event(view, "task", "sort", %{"column" => "title"})
assert render_async(view) =~ "Write the docs"
```

Every read after the first runs beside the LiveView: `render_async/2` waits
for it. A test of a page with an attached or mounted table can give it
[commands](events-and-commands.md#commands) in the LiveView's process and
hear its events there.

## Live updates

A table hears of changes through a process of its own, which gathers
announcements for 100 ms before handing them over.
`AshDataTable.Test.flush/1` makes it hand everything over at once and
returns when the LiveView has taken it in: call it instead of sleeping. From
[`demo/test/demo_web/tables/live_updates_elsewhere_test.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/demo_web/tables/live_updates_elsewhere_test.exs):

<!-- source: demo/test/demo_web/tables/live_updates_elsewhere_test.exs -->
```elixir
defp heard(view, gone \\ []) do
  AshDataTable.Test.flush(view)
  render_async(view, 10_000)
  Enum.each(gone, &left(view, &1))
  render(view)
end
```

A row whose record is gone, or no longer the person's to read, leaves only
once the table's hook has said no cell of it is being edited. A LiveView
test has no hook, so the test answers, with the row of the event the table
pushed:

<!-- sketch -->
```elixir
assert_push_event(view, "ash_data_table:leaving", %{table: "task", row: row})
AshDataTable.Test.send_event(view, "task", "left", %{"row" => row})
```

`AshDataTable.Test.listening/2` counts the tables listening to a resource's
changes for a tenant, so a test can check that a closed page or a collapsed
row stopped listening:

<!-- sketch -->
```elixir
assert AshDataTable.Test.listening(MyApp.Tracker.Task, organization.id) == 1
```

See [Live updates](live-updates.md).

## Nested tables and pickers

LiveView portals move these into their places:

- the tables nested in a row, into their cells;
- a picker's table, into the picker's place (`AshDataTable.Ids.picker_place/1`);
- a picker opened from a modal panel, and the question's copy inside a modal
  panel or picker, into their places (`AshDataTable.Ids.panel_place/1`,
  `picker_place/1`).

`Phoenix.LiveViewTest` renders a portal's content where the portal stands,
in a `<template>`, and does not look into it: `element/2` and
`has_element?/2` find neither a nested table's rows nor a picker's. Three
helpers do:

- `AshDataTable.Test.page/1`: the page as the browser shows it, as a
  `LazyHTML`, each nested table in its cell, each picker's table in its
  place. Query it like `render/1`'s output.
- `AshDataTable.Test.send_event/5` reaches a nested table, or a picker opened
  in one, by its id: `"task-row-1-t-comments"`.
- `AshDataTable.Test.send_form/5` sends a form inside a portal as the browser
  does: what its controls hold, with your values merged in.

<!-- sketch -->
```elixir
html = render(view)
AshDataTable.Test.page(html) |> LazyHTML.query("[id='task-row-1-t-comments-table']")
AshDataTable.Test.send_event(view, "task-row-1-t-comments", "sort", %{"column" => "body"})
```

They read the page with `LazyHTML`, which `Phoenix.LiveViewTest` needs too.

## A kit of your own

`use AshDataTable.KitCase` in a test module checks a kit. It draws a table
through it in every state and presentation, and asserts that every page on
the way:

- carries the markers, ids and `data-*` values the table's hooks find their
  elements by and read, and the kinds of elements they need;
- gives each part its texts;
- holds no sensitive value.

The demo runs it against its kit of `div`s
([`demo/test/demo_web/kits/div_kit_test.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/demo_web/kits/div_kit_test.exs)):

<!-- source: demo/test/demo_web/kits/div_kit_test.exs -->
```elixir
use AshDataTable.KitCase, kit: DemoWeb.DivKit, endpoint: DemoWeb.Endpoint
```

`endpoint` is what `Phoenix.LiveViewTest.live_isolated/3` mounts with. The
tests run `async`, each in its own tenant.

The table it draws is `AshDataTable.Test.Resource`, shipped with the library
so your tests have a column of every kind a kit draws: text, a sensitive
text, a boolean, a component with a footer summary, an enum, a list, a map,
a list of maps, a union and a reference cell, a nested table, an argument
line, row actions with a file, with the sensitive field and with records
chosen in the picker, an action on the selected rows, a table action and
create. Its records are kept in memory.

`KitCase` names its twenty states (`states/0`) and four presentations
(`presentations/0`), and generates a test for each pair.

A part's texts are checked against the messages they are made of: each a
map `%{key: key, values: values}` of a key of `AshDataTable.Messages` with
exactly its values. A kit's rows are the items of `AshDataTable.Item`, whose
cells hold their texts. A kit that draws in the browser has the browser side
of its contract checked in a browser (see
[Kits](kits.md#a-kit-that-draws-in-the-browser)).

Keyboard use and what a screen reader says are not checked here: that needs
a browser. The library checks them for the default kit and the demo's kit of
`div`s in its own browser suite. See [Kits](kits.md).

## Edge cases

- **Checking for no listener** after a page closed: `listening/2` waits
  until each listener has taken in what it was told before.
- **A row that never leaves.** A live update that removes a row waits for
  the hook's answer: send `left` as above.
- **Two tables of one resource on a page** have their own ids; name the one
  an event is for.

## Things people trip over

- **Sleeping for live updates.** The 100 ms are a minimum, not a promise.
  Call `flush/1`.
- **`has_element?/2` finds nothing in a nested table.** Query
  `AshDataTable.Test.page/1` instead.
- **`render_hook/3` with the event's plain name.** A table's events are named
  with its id; `send_event/5` names them for you.
- **`KitCase` without `endpoint`.** `live_isolated/3` needs one: pass your
  app's.

## Not in the first version

No browser test helpers for a host's own suite. See the
[specification](https://github.com/StefanRoesch/ash_data_table/issues/21).
