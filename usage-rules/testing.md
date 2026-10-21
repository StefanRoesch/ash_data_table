# Testing

Tables are LiveViews: test them with `Phoenix.LiveViewTest`, and with
`AshDataTable.Test` and `AshDataTable.KitCase` where the library's help is
needed. Details:
[Testing](https://github.com/StefanRoesch/ash_data_table/blob/main/documentation/topics/testing.md).

## A table on a page

- Send what a person does with `AshDataTable.Test.send_event/5`, by the
  table's id and the event's plain name: a table's events are named with
  its id, which `send_event/5` adds.
- Every read after the first runs beside the LiveView: `render_async/2`
  waits for it.

<!-- sketch -->
```elixir
{:ok, view, _html} = live(conn, "/tasks")

AshDataTable.Test.send_event(view, "task", "sort", %{"column" => "title"})
assert render_async(view) =~ "Write the docs"
```

## Live updates

Call `AshDataTable.Test.flush/1` in place of sleeping: it hands over every
gathered announcement and returns when the LiveView has taken it in. A row
that leaves waits for the hook's answer, which a LiveView test sends itself:

<!-- sketch -->
```elixir
assert_push_event(view, "ash_data_table:leaving", %{table: "task", row: row})
AshDataTable.Test.send_event(view, "task", "left", %{"row" => row})
```

`AshDataTable.Test.listening/2` counts the tables listening to a resource
for a tenant.

## A file an action returns

The table pushes it to the page, its content in Base64: assert the push,
once an action on the selection has run beside the LiveView (`render_async/2`):

<!-- sketch -->
```elixir
AshDataTable.Test.send_event(view, "task", "bulk", %{"action" => "export_csv"})
render_async(view)

assert_push_event(view, "ash_data_table:download", %{name: "tasks.csv", data: data})
assert Base.decode64!(data) =~ "Write the docs"
```

That the browser saves it is the library's own JavaScript: a browser test
waits for the download (Playwright's `page.waitForEvent("download")`).

## Nested tables and pickers

They are moved into place by LiveView portals, which `element/2` and
`has_element?/2` do not look into. Query `AshDataTable.Test.page/1` (the page
as the browser shows it, a `LazyHTML`), reach a nested table with
`send_event/5` by its id (`"task-row-1-t-comments"`), and send a form inside
a portal with `AshDataTable.Test.send_form/5`.

## A kit of your own

<!-- source: demo/test/demo_web/kits/div_kit_test.exs -->
```elixir
use AshDataTable.KitCase, kit: DemoWeb.DivKit, endpoint: DemoWeb.Endpoint
```

`endpoint` is required: `live_isolated/3` mounts with it. Keyboard use and
what a screen reader says need a browser, outside `KitCase`.
