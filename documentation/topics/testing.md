# Testing

Your tables are LiveViews, so `Phoenix.LiveViewTest` tests them as it tests
any page of yours. Three things need help from the library: live updates,
which a table hears a little later than they happen; nested tables and
pickers, which `Phoenix.LiveViewTest` does not see; and a kit of your own,
which has to carry what the table's behaviour in the browser relies on.
After reading this guide you can test all three with `AshDataTable.Test`,
`AshDataTable.KitCase` and `AshDataTable.Test.Resource`.

## A table on a page

Mount the page, then look at what it renders and send it what a person
does. The table's ids begin with its id (`task-row-…`), and its events are
named with it: `ash_data_table:task:sort`. `AshDataTable.Test.send_event/5`
sends a table its event as its hook does, by the table's id and the event's
plain name:

<!-- sketch -->
```elixir
{:ok, view, _html} = live(conn, "/tasks")

AshDataTable.Test.send_event(view, "task", "sort", %{"column" => "title"})
assert render_async(view) =~ "Write the docs"
```

A read after the first one runs beside the LiveView: `render_async/2`
waits for it. A test of a page with an attached table, or a mounted one,
can give it [commands](events-and-commands.md#commands) in the LiveView's
process, and hear its events there.

## Live updates

A table hears of a change through a process of its own, which gathers what
was announced for 100 ms before it hands it to the table.
`AshDataTable.Test.flush/1` has it hand everything over at once and returns
when the LiveView has taken it in: call it in place of sleeping. From the
demo's tests
([`demo/test/demo_web/tables/live_updates_elsewhere_test.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/demo_web/tables/live_updates_elsewhere_test.exs)):

<!-- source: demo/test/demo_web/tables/live_updates_elsewhere_test.exs -->
```elixir
defp heard(view, gone \\ []) do
  AshDataTable.Test.flush(view)
  render_async(view, 10_000)
  Enum.each(gone, &left(view, &1))
  render(view)
end
```

A row whose record is gone, or no longer the person's to read, leaves the
page only once the table's hook has said that no cell of it is being
edited. A LiveView test has no hook, so the test answers for it, with the
row of the event the table pushed:

<!-- sketch -->
```elixir
assert_push_event(view, "ash_data_table:leaving", %{table: "task", row: row})
AshDataTable.Test.send_event(view, "task", "left", %{"row" => row})
```

`AshDataTable.Test.listening/2` counts the tables that listen to the changes
of a resource, for a tenant: a test can check that a closed page or a
collapsed row stopped listening.

<!-- sketch -->
```elixir
assert AshDataTable.Test.listening(MyApp.Tracker.Task, organization.id) == 1
```

See [Live updates](live-updates.md).

## Nested tables and pickers

The tables nested in a row are moved into their cells by LiveView portals.
`Phoenix.LiveViewTest` renders a portal's content where the portal stands,
in a `<template>`, and does not look into it, so `element/2` and `has_element?/2`
do not find a nested table's rows. Three helpers do:

- `AshDataTable.Test.page/1` is the page as a person sees it in the browser,
  as a `LazyHTML`, each nested table in its cell. Query it as you would
  `render/1`'s output.
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

`use AshDataTable.KitCase` in a test module of yours checks a kit: it draws
a table through it in every state and every presentation, and asserts that
every page on the way carries the markers, ids and `data-*` values the
table's hooks find their elements by and read, the kinds of elements they
need, the texts each part is given, and that no page holds a sensitive
value. The demo runs it against its own kit of `div`s
([`demo/test/demo_web/kits/div_kit_test.exs`](https://github.com/StefanRoesch/ash_data_table/blob/main/demo/test/demo_web/kits/div_kit_test.exs)):

<!-- source: demo/test/demo_web/kits/div_kit_test.exs -->
```elixir
use AshDataTable.KitCase, kit: DemoWeb.DivKit, endpoint: DemoWeb.Endpoint
```

`endpoint` is the endpoint `Phoenix.LiveViewTest.live_isolated/3` mounts
with. The tests run `async`, each in a tenant of its own.

The table it draws is `AshDataTable.Test.Resource`, which ships with the
library so that your tests have a table with a column of every kind a kit
draws: text, a sensitive text, a boolean, a component with a footer
summary, an enum, a list, a map, a list of maps, a union and a reference
cell, a nested table, an argument line, row actions with a file, with the
sensitive field and with records chosen in the picker, an action on the
selected rows, a table action and create. Its records are kept in memory.

`KitCase` names its twenty states (`states/0`) and four presentations
(`presentations/0`), and generates a test for each pair.

The texts a part is given are checked with the messages they are made of:
each a map `%{key: key, values: values}` of a key of `AshDataTable.Messages`
with exactly its values. A kit's rows are the items of `AshDataTable.Item`,
whose cells hold their texts; a kit that draws in the browser has the
browser side of its contract checked in a browser (see
[Kits](kits.md#a-kit-that-draws-in-the-browser)).

What a person does with the keyboard and hears from a screen reader is not
checked there: that needs a browser. The library checks it for the default
kit and for the demo's kit of `div`s in its own browser suite. See
[Kits](kits.md).

## Edge cases

- **A test that checks for no listener** after a page closed calls
  `listening/2`, which waits until each listener has taken in what it was
  told before.
- **A row that never leaves.** A live update that removes a row waits for
  the hook's answer: send `left` as above.
- **Two tables of one resource on a page** have ids of their own; name the
  one an event is for.

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
